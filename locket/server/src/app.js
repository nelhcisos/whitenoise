import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { KINDS, MAX_STARS, computeStandings } from './awards.js';
import { createAttemptLimiter, hashToken, newSessionToken, passwordKey } from './auth.js';
import { createStore } from './db.js';
import { HttpError, createRouter, readBody, readJson, sendJson } from './http.js';
import {
  createPushService,
  duelMessage,
  friendAcceptedMessage,
  friendRequestMessage,
  lockedPhotoMessage,
  newPhotoMessage,
  reactionMessage,
  reminderMessage,
  weeklyResultsMessage,
} from './push.js';
import { canonicalUsername, suggestUsernames, usernameKey } from './usernames.js';
import { makeWeekCalendar } from './week.js';

const MAX_PHOTO_BYTES = 8 * 1024 * 1024;
const MAX_REGISTER_JSON = 12 * 1024 * 1024; // the photo travels as base64 inside JSON
const MEDIA_FILE = /^[a-f0-9]{32}\.jpg$/;
const PASSWORD_MIN = 4;
const PASSWORD_MAX = 64;
const MINUTE = 60_000;
const DAY_MS = 24 * 60 * MINUTE;
// The day rating's option ids, shared with the iOS app (Shared/DayRating.swift).
export const DAY_REASONS = ['unchanged', 'distracted', 'awkward', 'odor', 'issues', 'reckless', 'noChance', 'fatigued', 'gps', 'rude'];
export const DAY_HIGHLIGHTS = ['advice', 'polite', 'comfort', 'clean', 'conversation', 'music'];

export function createApp({ config, db, apns = null, now = () => Date.now(), log = console, random = Math.random }) {
  if (!config.passwordPepper) throw new Error('config.passwordPepper is required');
  const store = createStore(db);
  const calendar = makeWeekCalendar(config.week);
  const push = createPushService({ store, apns, log });
  const maxFriends = config.maxFriends ?? 100;
  // Unknown passwords per client IP: a password is the whole account, so guessing is the threat.
  const passwordMisses = createAttemptLimiter({ max: 20, windowMs: 10 * MINUTE });
  const newAccounts = createAttemptLimiter({ max: 10, windowMs: 60 * MINUTE });
  const mediaDir = path.join(config.dataDir, 'media');
  fs.mkdirSync(mediaDir, { recursive: true });

  // Push sends run in the background; tests wait for them via idle().
  const pending = new Set();
  const background = (promise) => {
    const p = Promise.resolve(promise)
      .catch((err) => log.error('background task failed', err))
      .finally(() => pending.delete(p));
    pending.add(p);
  };

  const mediaUrl = (file) => `${config.publicUrl}/media/${file}`;
  // The friends' local day ("2026-10-23") and its midnight, in the same time zone as the week.
  const tz = (config.week?.tzOffsetMinutes ?? 180) * MINUTE;
  const localDate = (ms) => new Date(ms + tz).toISOString().slice(0, 10);
  const localMidnight = (ms) => {
    const d = new Date(ms + tz);
    return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) - tz;
  };
  const currentWeekId = () => calendar.weekIdFor(now());

  // ---------- locked photos ----------

  /**
   * The one place that decides what a viewer may see (API.md «Закрытые фото»).
   * A friend's photo is open when its place among that friend's photos of the
   * week is below 1 + the viewer's own photos of that week. Own photos are open.
   * Counts are cached per call, so build one per request.
   */
  function visibilityFor(viewerId) {
    const allowance = new Map();
    const decided = new Map();
    return (photo) => {
      if (photo.authorId === viewerId) return true;
      if (decided.has(photo.id)) return decided.get(photo.id);
      let limit = allowance.get(photo.weekId);
      if (limit === undefined) {
        limit = 1 + store.postsInWeek(viewerId, photo.weekId);
        allowance.set(photo.weekId, limit);
      }
      const open = store.rankInWeek(photo) < limit;
      decided.set(photo.id, open);
      return open;
    };
  }

  // ---------- serializers ----------

  function meResponse(user) {
    const weekId = currentWeekId();
    return {
      user: { id: user.id, username: user.username ?? null },
      friends: store.friends(user.id).map((f) => ({ id: f.id, username: f.username })),
      incomingRequests: store.incomingCount(user.id),
      week: { id: weekId, ...calendar.weekBounds(weekId) },
    };
  }

  function friendsResponse(userId) {
    return {
      friends: store.friends(userId),
      incoming: store.incoming(userId),
      outgoing: store.outgoing(userId),
    };
  }

  const zeroCounts = () => Object.fromEntries(KINDS.map((k) => [k, 0]));

  // A locked photo keeps only who and when: no picture, no caption, no ratings.
  const lockedPhoto = (p) => ({
    id: p.id,
    authorId: p.authorId,
    authorName: p.authorName,
    createdAt: p.createdAt,
    weekId: p.weekId,
    locked: true,
    caption: null,
    imageUrl: null,
    canReact: false,
    counts: zeroCounts(),
    stars: { count: 0, total: 0, average: 0 },
    myStars: 0,
    mine: [],
    reactors: [],
    raters: [],
  });

  function serializePhotos(photos, viewerId, isOpen = visibilityFor(viewerId)) {
    const weekId = currentWeekId();
    const open = photos.filter(isOpen);
    const ids = open.map((p) => p.id);
    const reactionsBy = new Map(ids.map((id) => [id, []]));
    const starsBy = new Map(ids.map((id) => [id, []]));
    for (const r of store.reactionsFor(ids)) reactionsBy.get(r.photoId).push(r);
    for (const s of store.starsFor(ids)) starsBy.get(s.photoId).push(s);
    return photos.map((p) => {
      if (!reactionsBy.has(p.id)) return lockedPhoto(p);
      const reactions = reactionsBy.get(p.id);
      const ratings = starsBy.get(p.id);
      const counts = zeroCounts();
      for (const r of reactions) counts[r.kind]++;
      const total = ratings.reduce((sum, s) => sum + s.value, 0);
      return {
        id: p.id,
        authorId: p.authorId,
        authorName: p.authorName,
        createdAt: p.createdAt,
        weekId: p.weekId,
        locked: false,
        caption: p.caption,
        imageUrl: mediaUrl(p.file),
        canReact: p.authorId !== viewerId && p.weekId === weekId,
        counts,
        stars: { count: ratings.length, total, average: ratings.length ? Math.round((total / ratings.length) * 10) / 10 : 0 },
        myStars: ratings.find((s) => s.userId === viewerId)?.value ?? 0,
        mine: reactions.filter((r) => r.userId === viewerId).map((r) => r.kind),
        reactors: reactions.map((r) => ({ userId: r.userId, name: r.name, kind: r.kind })),
        raters: ratings.map((s) => ({ userId: s.userId, name: s.name, stars: s.value })),
      };
    });
  }

  /** Most picked in «Кто лучше?» that week, among these people; ties go by the leaderboard. */
  function favoriteFriend(weekId, memberIds, leaderboard) {
    const picks = new Map(store.picksInWeek(weekId, memberIds).map((r) => [r.userId, r.picks]));
    let best = null;
    for (const s of leaderboard) {
      const count = picks.get(s.userId) ?? 0;
      if (count > 0 && (!best || count > best.value)) best = { userId: s.userId, name: s.name, value: count };
    }
    return best;
  }

  /** Weekly results as one viewer sees them: the viewer and their friends right now. */
  function weekResults(viewer, weekId, closedAt = null) {
    const memberIds = [viewer.id, ...store.friendIds(viewer.id)];
    const members = store.usersByIds(memberIds).map((u) => ({ id: u.id, name: u.username ?? '' }));
    const { photos, reactions, stars } = store.weekData(memberIds, weekId);
    const s = computeStandings({ members, photos, reactions, stars });
    const inCircle = new Set(memberIds);
    const best = s.bestPhoto;
    return {
      weekId,
      ...calendar.weekBounds(weekId),
      closedAt,
      photoCount: photos.filter((p) => inCircle.has(p.authorId)).length,
      leaderboard: s.leaderboard,
      // The photo of the week is the prize: its picture is shown even to whoever had it locked.
      bestPhoto: best && {
        photoId: best.id,
        authorId: best.authorId,
        authorName: best.authorName,
        caption: best.caption,
        imageUrl: mediaUrl(best.file),
        stars: best.stars,
        starCount: best.starCount,
        creative: best.creative,
        funny: best.funny,
        wild: best.wild,
      },
      friendOfWeek: s.friendOfWeek,
      // «Кто лучше?»: only the most picked is told; the least picked stays a secret.
      favoriteFriend: favoriteFriend(weekId, memberIds, s.leaderboard),
      mostCreative: s.mostCreative,
      mostFunny: s.mostFunny,
      mostWild: s.mostWild,
      mostActive: s.mostActive,
    };
  }

  // ---------- helpers ----------

  function authenticate(req) {
    const header = req.headers.authorization || '';
    const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
    const user = token && store.userBySession(hashToken(token));
    if (!user) throw new HttpError(401, 'Нужно войти заново');
    return user;
  }

  function clientIp(req) {
    if (config.trustProxy) {
      const forwarded = String(req.headers['x-forwarded-for'] || '').split(',')[0].trim();
      if (forwarded) return forwarded;
    }
    return req.socket.remoteAddress || 'unknown';
  }

  function cleanPassword(value) {
    const password = typeof value === 'string' ? value.normalize('NFC') : '';
    const length = [...password].length;
    if (length < PASSWORD_MIN) throw new HttpError(400, `Пароль — минимум ${PASSWORD_MIN} символа`);
    if (length > PASSWORD_MAX) throw new HttpError(400, `Пароль — не длиннее ${PASSWORD_MAX} символов`);
    return password;
  }

  const cleanCaption = (value) => String(value ?? '').replace(/\s+/g, ' ').trim().slice(0, 60) || null;

  function assertJpeg(buf) {
    if (buf.length > MAX_PHOTO_BYTES) throw new HttpError(413, 'Слишком большой файл');
    if (buf.length < 3 || buf[0] !== 0xff || buf[1] !== 0xd8 || buf[2] !== 0xff) {
      throw new HttpError(400, 'Нужна картинка в формате JPEG');
    }
  }

  function saveMedia(buf) {
    const file = `${crypto.randomBytes(16).toString('hex')}.jpg`;
    fs.writeFileSync(path.join(mediaDir, file), buf);
    return file;
  }

  function startSession(user, status) {
    const { token, hash } = newSessionToken();
    store.createSession(hash, user.id, now());
    return { status, token, ...meResponse(user) };
  }

  /** Your own photo or a friend's; anything else does not exist for you. */
  function visiblePhoto(user, photoId) {
    const photo = store.photo(photoId);
    if (!photo || (photo.authorId !== user.id && !store.areFriends(user.id, photo.authorId))) {
      throw new HttpError(404, 'Фото не найдено');
    }
    return photo;
  }

  /**
   * Stores a photo and tells each friend: an open photo arrives with its picture
   * and rating buttons, a locked one without. `unlocked` = friends whose photo
   * count this week was above the author's old allowance, so one more opened.
   */
  function publish(user, file, caption) {
    const t = now();
    const weekId = calendar.weekIdFor(t);
    const allowanceBefore = 1 + store.postsInWeek(user.id, weekId);
    const id = crypto.randomUUID();
    store.insertPhoto({ id, authorId: user.id, weekId, caption, file, now: t });
    const photo = store.photo(id);
    const friendIds = store.friendIds(user.id);

    const theirs = store.photosByAuthorsInWeek(friendIds, weekId);
    const perFriend = new Map();
    for (const p of theirs) perFriend.set(p.authorId, (perFriend.get(p.authorId) ?? 0) + 1);
    let unlocked = 0;
    for (const count of perFriend.values()) if (count > allowanceBefore) unlocked++;

    // This photo's rank is fixed; each friend's allowance depends on their own posts.
    const rank = store.rankInWeek(photo);
    const open = [];
    const locked = [];
    for (const friendId of friendIds) (rank < 1 + store.postsInWeek(friendId, weekId) ? open : locked).push(friendId);
    background(push.sendToUsers(open, newPhotoMessage({ photo, imageUrl: mediaUrl(file) })));
    background(push.sendToUsers(locked, lockedPhotoMessage({ photo })));
    return { photo, unlocked };
  }

  function relation(me, otherId) {
    if (otherId === me) return 'self';
    if (store.areFriends(me, otherId)) return 'friend';
    if (store.hasRequest(me, otherId)) return 'outgoing';
    if (store.hasRequest(otherId, me)) return 'incoming';
    return 'none';
  }

  function assertRoomForFriend(user, other) {
    if (store.friendCount(user.id) >= maxFriends) throw new HttpError(409, `У тебя уже максимум друзей — ${maxFriends}`);
    if (store.friendCount(other.id) >= maxFriends) throw new HttpError(409, `У ${other.username} уже максимум друзей`);
  }

  function befriend(a, b) {
    store.transaction(() => {
      store.addFriendship(a.id, b.id, now());
      store.deleteRequestsBetween(a.id, b.id);
    });
  }

  // ---------- routes ----------

  const router = createRouter();
  const pub = { public: true };
  // Allowed before a username is chosen; everything else needs one.
  const early = { early: true };

  router.get('/health', () => ({ ok: true }), pub);

  router.post(
    '/api/auth/password',
    ({ req, body }) => {
      const ip = clientIp(req);
      if (passwordMisses.blocked(ip, now())) throw new HttpError(429, 'Слишком много попыток — подожди 10 минут');
      const password = cleanPassword(body.password);
      const user = store.userByPasswordKey(passwordKey(config.passwordPepper, password));
      if (!user) {
        passwordMisses.fail(ip, now());
        return { status: 'new' };
      }
      return startSession(user, 'signedIn');
    },
    pub,
  );

  router.post(
    '/api/auth/register',
    ({ req, body }) => {
      const ip = clientIp(req);
      if (passwordMisses.blocked(ip, now())) throw new HttpError(429, 'Слишком много попыток — подожди 10 минут');
      const password = cleanPassword(body.password);
      const jpeg = Buffer.from(typeof body.photo === 'string' ? body.photo : '', 'base64');
      assertJpeg(jpeg);
      const caption = cleanCaption(body.caption);
      const key = passwordKey(config.passwordPepper, password);

      // Someone made this password a moment ago: that is a sign-in, and the photo goes there.
      const existing = store.userByPasswordKey(key);
      if (existing) {
        publish(existing, saveMedia(jpeg), caption);
        return startSession(existing, 'signedIn');
      }

      if (newAccounts.blocked(ip, now())) throw new HttpError(429, 'Слишком много новых аккаунтов — попробуй через час');
      const user = { id: crypto.randomUUID(), username: null };
      const file = saveMedia(jpeg);
      const t = now();
      try {
        store.transaction(() => {
          store.createUser({ id: user.id, passwordKey: key, now: t });
          store.insertPhoto({ id: crypto.randomUUID(), authorId: user.id, weekId: calendar.weekIdFor(t), caption, file, now: t });
        });
      } catch (err) {
        fs.rm(path.join(mediaDir, file), { force: true }, () => {});
        throw err;
      }
      newAccounts.fail(ip, now());
      return startSession(user, 'created');
    },
    { public: true, jsonLimit: MAX_REGISTER_JSON },
  );

  router.post(
    '/api/auth/logout',
    ({ req, user, body }) => {
      store.deleteSession(hashToken(req.headers.authorization.slice(7).trim()));
      if (body.deviceToken) store.deleteDevice(String(body.deviceToken), user.id);
      return { ok: true };
    },
    early,
  );

  router.get('/api/me', ({ user }) => meResponse(user), early);

  router.get(
    '/api/usernames/suggestions',
    ({ user }) => {
      if (user.username) throw new HttpError(409, 'Юзернейм уже выбран');
      return { suggestions: suggestUsernames((key) => store.usernameTaken(key)) };
    },
    early,
  );

  router.post(
    '/api/me/username',
    ({ user, body }) => {
      if (user.username) throw new HttpError(409, 'Юзернейм уже выбран');
      const username = canonicalUsername(body.username);
      if (!username) throw new HttpError(400, 'Такого юзернейма нет среди вариантов — выбери из предложенных');
      const key = usernameKey(username);
      if (store.usernameTaken(key)) throw new HttpError(409, 'Этот юзернейм только что заняли — выбери другой');
      if (!store.setUsername(user.id, username, key)) throw new HttpError(409, 'Юзернейм уже выбран');
      return meResponse(store.user(user.id));
    },
    early,
  );

  router.post(
    '/api/devices',
    ({ user, body }) => {
      const token = String(body.token ?? '');
      const env = body.env === 'sandbox' ? 'sandbox' : 'production';
      if (!/^[0-9a-f]{32,200}$/i.test(token)) throw new HttpError(400, 'Некорректный токен устройства');
      store.upsertDevice(token.toLowerCase(), user.id, env, now());
      return { ok: true };
    },
    early,
  );

  router.delete(
    '/api/devices/:token',
    ({ user, params }) => {
      store.deleteDevice(params.token.toLowerCase(), user.id);
      return { ok: true };
    },
    early,
  );

  // ----- friends -----

  router.get('/api/users/search', ({ user, url }) => {
    const raw = String(url.searchParams.get('q') ?? '').trim().replace(/^@+/, '');
    const key = usernameKey(raw);
    if ([...key].length < 2) return { users: [] };
    return {
      users: store.searchUsers(key, 20).map((u) => ({ id: u.id, username: u.username, relation: relation(user.id, u.id) })),
    };
  });

  router.get('/api/friends', ({ user }) => friendsResponse(user.id));

  router.post('/api/friends/requests', ({ user, body }) => {
    const target = store.user(String(body.userId ?? ''));
    if (!target || !target.username) throw new HttpError(404, 'Пользователь не найден');
    if (target.id === user.id) throw new HttpError(400, 'Это ты');
    if (store.areFriends(user.id, target.id)) return friendsResponse(user.id);
    assertRoomForFriend(user, target);
    // They asked first: asking back is accepting.
    if (store.hasRequest(target.id, user.id)) {
      befriend(user, target);
      background(push.sendToUsers([target.id], friendAcceptedMessage({ user })));
      return friendsResponse(user.id);
    }
    if (store.createRequest(user.id, target.id, now())) {
      background(push.sendToUsers([target.id], friendRequestMessage({ from: user })));
    }
    return friendsResponse(user.id);
  });

  router.post('/api/friends/requests/:userId/accept', ({ user, params }) => {
    const requester = store.user(params.userId);
    if (!requester || !store.hasRequest(requester.id, user.id)) throw new HttpError(404, 'Заявка не найдена');
    assertRoomForFriend(user, requester);
    befriend(user, requester);
    background(push.sendToUsers([requester.id], friendAcceptedMessage({ user })));
    return friendsResponse(user.id);
  });

  router.delete('/api/friends/requests/:userId', ({ user, params }) => {
    store.deleteRequestsBetween(user.id, params.userId);
    return friendsResponse(user.id);
  });

  router.delete('/api/friends/:userId', ({ user, params }) => {
    store.removeFriendship(user.id, params.userId);
    return friendsResponse(user.id);
  });

  // ----- photos -----

  router.get('/api/photos', ({ user, url }) => {
    const before = Number(url.searchParams.get('before')) || Number.MAX_SAFE_INTEGER;
    const limit = Math.min(Math.max(Number(url.searchParams.get('limit')) || 30, 1), 100);
    const authors = [user.id, ...store.friendIds(user.id)];
    return { photos: serializePhotos(store.feed(authors, before, limit), user.id) };
  });

  router.post(
    '/api/photos',
    ({ user, url, body }) => {
      assertJpeg(body);
      const { photo, unlocked } = publish(user, saveMedia(body), cleanCaption(url.searchParams.get('caption')));
      return { photo: serializePhotos([photo], user.id)[0], unlocked };
    },
    { raw: true },
  );

  // The newest open photo from a friend, for the home-screen widget.
  router.get(
    '/api/widget',
    ({ user }) => {
      if (!user.username) return { photo: null };
      const isOpen = visibilityFor(user.id);
      const photo = store.feed(store.friendIds(user.id), Number.MAX_SAFE_INTEGER, 100).find(isOpen);
      return { photo: photo ? serializePhotos([photo], user.id, isOpen)[0] : null };
    },
    early,
  );

  router.get('/api/photos/:id', ({ user, params }) => ({ photo: serializePhotos([visiblePhoto(user, params.id)], user.id)[0] }));

  router.delete('/api/photos/:id', ({ user, params }) => {
    const photo = visiblePhoto(user, params.id);
    if (photo.authorId !== user.id) throw new HttpError(403, 'Удалять можно только свои фото');
    store.deletePhoto(photo.id);
    fs.rm(path.join(mediaDir, photo.file), { force: true }, () => {});
    return { ok: true };
  });

  // Shared checks for stars and reactions: an open photo of a friend, this week.
  function ratablePhoto(user, photoId) {
    const photo = visiblePhoto(user, photoId);
    if (photo.authorId === user.id) throw new HttpError(403, 'Свои фото оценивать нельзя');
    if (!visibilityFor(user.id)(photo)) throw new HttpError(403, 'Это фото закрыто — выложи своё, чтобы открыть');
    if (photo.weekId !== currentWeekId()) throw new HttpError(409, 'Голосование за ту неделю уже закрыто');
    return photo;
  }

  // Tells the author what this friend gave the photo so far (one notification per friend).
  function notifyAuthor(photo, user) {
    const { payload, opts } = reactionMessage({
      photo,
      reactor: user,
      stars: store.starsBy(photo.id, user.id),
      kinds: store.kindsBy(photo.id, user.id),
      imageUrl: mediaUrl(photo.file),
    });
    background(push.sendToUsers([photo.authorId], payload, opts));
  }

  const react = (on) => ({ user, params }) => {
    if (!KINDS.includes(params.kind)) throw new HttpError(400, 'Неизвестная оценка');
    const photo = ratablePhoto(user, params.id);
    if (store.setReaction(photo.id, user.id, params.kind, on, now()) && on) notifyAuthor(photo, user);
    return { photo: serializePhotos([photo], user.id)[0] };
  };
  router.put('/api/photos/:id/reactions/:kind', react(true));
  router.delete('/api/photos/:id/reactions/:kind', react(false));

  router.put('/api/photos/:id/stars', ({ user, params, body }) => {
    const value = Number(body.stars);
    if (!Number.isInteger(value) || value < 1 || value > MAX_STARS) throw new HttpError(400, `Звёзд может быть от 1 до ${MAX_STARS}`);
    const photo = ratablePhoto(user, params.id);
    if (store.setStars(photo.id, user.id, value, now())) notifyAuthor(photo, user);
    return { photo: serializePhotos([photo], user.id)[0] };
  });

  router.delete('/api/photos/:id/stars', ({ user, params }) => {
    const photo = ratablePhoto(user, params.id);
    store.setStars(photo.id, user.id, 0, now());
    return { photo: serializePhotos([photo], user.id)[0] };
  });

  // ----- «Кто лучше?»: once a day, pick one of two friends -----

  const duelJSON = (d) => ({ id: d.id, date: d.date, left: d.left, right: d.right, choice: d.choice ?? null });

  // Today's pick, once it has been sent (the random moment stays a surprise).
  router.get('/api/duels/today', ({ user }) => {
    const duel = store.duelFor(user.id, localDate(now()));
    return { duel: duel && duel.sentAt ? duelJSON(duel) : null };
  });

  router.post('/api/duels/:id/choice', ({ user, params, body }) => {
    const duel = store.duel(params.id);
    if (!duel || duel.userId !== user.id || !duel.sentAt) throw new HttpError(404, 'Выбор не найден');
    if (body.pick !== 'left' && body.pick !== 'right') throw new HttpError(400, 'Выбери левого или правого');
    if (duel.choice) throw new HttpError(409, 'Выбор уже сделан');
    const chosen = body.pick === 'left' ? duel.left : duel.right;
    if (!store.chooseDuel(duel.id, body.pick, chosen.id, calendar.weekIdFor(now()), now())) {
      throw new HttpError(409, 'Выбор уже сделан');
    }
    return { duel: duelJSON(store.duel(duel.id)) };
  });

  // ----- the day rating: «оцени свой день, как поездку» -----

  /** "2026-10-23", a real calendar date from two months ago to tomorrow (the phone's own date). */
  function cleanDate(value) {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(value ?? ''));
    const time = match ? Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])) : NaN;
    if (!match || new Date(time).toISOString().slice(0, 10) !== value) throw new HttpError(400, 'Неверная дата');
    if (time > now() + 2 * DAY_MS || time < now() - 62 * DAY_MS) throw new HttpError(400, 'Эту дату оценить нельзя');
    return value;
  }

  function cleanOptions(value, allowed) {
    const list = Array.isArray(value) ? value : [];
    for (const item of list) if (!allowed.includes(item)) throw new HttpError(400, 'Неизвестный вариант оценки');
    return allowed.filter((item) => list.includes(item));
  }

  const cleanAnswer = (value) => (value === true || value === false ? value : null);

  router.put('/api/days/:date', ({ user, params, body }) => {
    const date = cleanDate(params.date);
    const stars = Number(body.stars);
    if (!Number.isInteger(stars) || stars < 1 || stars > 5) throw new HttpError(400, 'Звёзд может быть от 1 до 5');
    const reasons = cleanOptions(body.reasons, DAY_REASONS);
    const liked = cleanOptions(body.liked, DAY_HIGHLIGHTS);
    store.saveDay({
      userId: user.id,
      date,
      stars,
      // Below five stars you say what got in the way; at five, what you liked most.
      reasons: stars < 5 ? reasons : [],
      liked: stars === 5 ? liked : [],
      condition: cleanAnswer(body.condition),
      place: cleanAnswer(body.place),
      now: now(),
    });
    return { day: store.day(user.id, date) };
  });

  router.get('/api/days', ({ user, url }) => {
    const limit = Math.min(Math.max(Number(url.searchParams.get('limit')) || 30, 1), 120);
    return { days: store.days(user.id, limit) };
  });

  // ----- weeks -----

  router.get('/api/week/current', ({ user }) => weekResults(user, currentWeekId()));

  router.get('/api/weeks', ({ user }) => ({ weeks: store.closedWeeks(user.id, 52) }));

  router.get('/api/weeks/:weekId', ({ user, params }) => {
    const week = store.closedWeek(user.id, params.weekId);
    if (week) return week;
    if (params.weekId === currentWeekId()) return weekResults(user, params.weekId);
    throw new HttpError(404, 'Неделя не найдена');
  });

  // ---------- HTTP entry point ----------

  function serveMedia(res, file) {
    if (!MEDIA_FILE.test(file)) throw new HttpError(404, 'Не найдено');
    const full = path.join(mediaDir, file);
    let stat;
    try {
      stat = fs.statSync(full);
    } catch {
      throw new HttpError(404, 'Не найдено');
    }
    res.writeHead(200, {
      'content-type': 'image/jpeg',
      'content-length': stat.size,
      'cache-control': 'public, max-age=31536000, immutable',
    });
    fs.createReadStream(full).pipe(res);
  }

  async function handle(req, res) {
    try {
      const url = new URL(req.url, 'http://localhost');
      if (req.method === 'GET' && url.pathname.startsWith('/media/')) {
        serveMedia(res, url.pathname.slice('/media/'.length));
        return;
      }
      const match = router.match(req.method, url.pathname);
      if (!match) throw new HttpError(404, 'Не найдено');
      const { route, params } = match;
      const ctx = { req, url, params };
      if (!route.opts.public) {
        ctx.user = authenticate(req);
        if (!route.opts.early && !ctx.user.username) throw new HttpError(409, 'Сначала выбери юзернейм');
      }
      if (route.opts.raw) ctx.body = await readBody(req, MAX_PHOTO_BYTES);
      else ctx.body = req.method === 'GET' ? {} : await readJson(req, route.opts.jsonLimit);
      sendJson(res, 200, await route.handler(ctx));
    } catch (err) {
      if (err instanceof HttpError) {
        sendJson(res, err.status, { error: err.message });
      } else {
        log.error(err);
        sendJson(res, 500, { error: 'Что-то сломалось на сервере' });
      }
    }
  }

  // ---------- scheduled work ----------

  /** Friends' photos of the week waiting for this user: open but unrated, and locked. */
  function pendingFor(user, weekId) {
    const photos = store.photosByAuthorsInWeek(store.friendIds(user.id), weekId);
    const allowance = 1 + store.postsInWeek(user.id, weekId);
    const open = [];
    let locked = 0;
    let rank = 0;
    let author = null;
    for (const p of photos) {
      rank = p.authorId === author ? rank + 1 : 0;
      author = p.authorId;
      if (rank < allowance) open.push(p.id);
      else locked++;
    }
    const rated = store.ratedBy(user.id, open);
    return { unrated: open.filter((id) => !rated.has(id)).length, locked };
  }

  function closeWeek(weekId, announce) {
    for (const user of store.usersWithUsername()) {
      const results = weekResults(user, weekId, now());
      if (results.photoCount === 0) continue;
      if (store.saveWeek(user.id, weekId, results.closedAt, results) && announce) {
        background(push.sendToUsers([user.id], weeklyResultsMessage(results)));
      }
    }
    // Marked only after the pass: a crash halfway means the next tick finishes it.
    store.claimJob(`close:${weekId}`, now());
  }

  /** Two different friends at random. */
  function pickPair(ids) {
    const first = Math.floor(random() * ids.length);
    let second = Math.floor(random() * (ids.length - 1));
    if (second >= first) second++;
    return [ids[first], ids[second]];
  }

  /**
   * Plans each person's «Кто лучше?» for today at a random moment between the
   * configured hours, and sends the ones that are due. Needs two friends.
   */
  function runDuels(t) {
    const date = localDate(t);
    const midnight = localMidnight(t);
    const from = midnight + (config.duel?.fromHour ?? 11) * 60 * MINUTE;
    const to = midnight + (config.duel?.toHour ?? 21) * 60 * MINUTE;
    if (t < to) {
      for (const user of store.usersWithUsername()) {
        if (store.duelFor(user.id, date)) continue;
        const friends = store.friendIds(user.id);
        if (friends.length < 2) continue;
        const start = Math.max(t, from);
        const [leftId, rightId] = pickPair(friends);
        store.createDuel({ id: crypto.randomUUID(), userId: user.id, date, leftId, rightId, sendAt: Math.floor(start + random() * (to - start)) });
      }
    }
    for (const duel of store.duelsDue(t)) {
      // Friends may have changed since the morning: pick again from the current ones.
      const friends = store.friendIds(duel.userId);
      if (!friends.includes(duel.left.id) || !friends.includes(duel.right.id)) {
        if (friends.length < 2) {
          store.deleteDuel(duel.id);
          continue;
        }
        const [leftId, rightId] = pickPair(friends);
        store.setDuelPair(duel.id, leftId, rightId);
      }
      store.markDuelSent(duel.id, t);
      // After a long outage yesterday's pick is not sent late.
      if (duel.date === date) background(push.sendToUsers([duel.userId], duelMessage(store.duel(duel.id))));
    }
  }

  async function runDue() {
    const t = now();
    runDuels(t);
    const weekId = calendar.weekIdFor(t);
    const { startsAt, endsAt } = calendar.weekBounds(weekId);
    const previousWeekId = calendar.weekIdFor(startsAt - 1);

    // Close finished weeks. Only the week that just ended gets a push; older
    // ones only show up after a long server outage.
    for (const w of store.weeksWithPhotosBefore(weekId)) {
      if (!store.jobDone(`close:${w}`)) closeWeek(w, w === previousWeekId);
    }

    const reminderMs = config.reminderHoursBefore * 3_600_000;
    if (reminderMs > 0 && t >= endsAt - reminderMs && t < endsAt && store.claimJob(`reminder:${weekId}`, t)) {
      const hours = Math.max(1, Math.round((endsAt - t) / 3_600_000));
      for (const user of store.usersWithUsername()) {
        const { unrated, locked } = pendingFor(user, weekId);
        if (unrated > 0 || locked > 0) background(push.sendToUsers([user.id], reminderMessage({ unrated, locked, hours })));
      }
    }
    await idle();
  }

  async function idle() {
    while (pending.size) await Promise.allSettled([...pending]);
  }

  return { handle, runDue, idle, store, calendar };
}
