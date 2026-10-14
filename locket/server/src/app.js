import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { KINDS, MAX_STARS, computeStandings } from './awards.js';
import { createAttemptLimiter, hashPassword, hashToken, newSessionToken, verifyPassword } from './auth.js';
import { createStore } from './db.js';
import { HttpError, createRouter, readBody, readJson, sendJson } from './http.js';
import {
  createPushService,
  joinedMessage,
  newPhotoMessage,
  reactionMessage,
  reminderMessage,
  weeklyResultsMessage,
} from './push.js';
import { makeWeekCalendar } from './week.js';

const MAX_PHOTO_BYTES = 8 * 1024 * 1024;
const MEDIA_FILE = /^[a-f0-9]{32}\.jpg$/;
const INVITE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

export function createApp({ config, db, apns = null, now = () => Date.now(), log = console }) {
  const store = createStore(db);
  const calendar = makeWeekCalendar(config.week);
  const push = createPushService({ store, apns, log });
  const loginLimiter = createAttemptLimiter();
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
  const currentWeekId = () => calendar.weekIdFor(now());

  // ---------- serializers ----------

  function meResponse(user) {
    const circle = user.circleId ? store.circle(user.circleId) : null;
    const weekId = currentWeekId();
    return {
      user: { id: user.id, name: user.name, email: user.email },
      circle,
      members: circle ? store.members(circle.id) : [],
      week: { id: weekId, ...calendar.weekBounds(weekId) },
    };
  }

  function serializePhotos(photos, viewerId) {
    const weekId = currentWeekId();
    const ids = photos.map((p) => p.id);
    const reactionsBy = new Map(ids.map((id) => [id, []]));
    const starsBy = new Map(ids.map((id) => [id, []]));
    for (const r of store.reactionsFor(ids)) reactionsBy.get(r.photoId).push(r);
    for (const s of store.starsFor(ids)) starsBy.get(s.photoId).push(s);
    return photos.map((p) => {
      const reactions = reactionsBy.get(p.id);
      const ratings = starsBy.get(p.id);
      const counts = Object.fromEntries(KINDS.map((k) => [k, 0]));
      for (const r of reactions) counts[r.kind]++;
      const total = ratings.reduce((sum, s) => sum + s.value, 0);
      return {
        id: p.id,
        authorId: p.authorId,
        authorName: p.authorName,
        caption: p.caption,
        imageUrl: mediaUrl(p.file),
        createdAt: p.createdAt,
        weekId: p.weekId,
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

  function weekResults(circleId, weekId, closedAt = null) {
    const { photos, reactions, stars } = store.weekData(circleId, weekId);
    const s = computeStandings({ members: store.members(circleId), photos, reactions, stars });
    const best = s.bestPhoto;
    return {
      weekId,
      ...calendar.weekBounds(weekId),
      closedAt,
      photoCount: photos.length,
      leaderboard: s.leaderboard,
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

  function requireCircle(user) {
    if (!user.circleId) throw new HttpError(409, 'Сначала создай компанию или вступи в неё');
    return user.circleId;
  }

  function cleanName(value, max, what) {
    const name = String(value ?? '').replace(/\s+/g, ' ').trim();
    if (!name) throw new HttpError(400, `Укажи ${what}`);
    if (name.length > max) throw new HttpError(400, `${what[0].toUpperCase()}${what.slice(1)}: не длиннее ${max} символов`);
    return name;
  }

  function photoInCircle(user, photoId) {
    const photo = store.photo(photoId);
    if (!photo || photo.circleId !== user.circleId) throw new HttpError(404, 'Фото не найдено');
    return photo;
  }

  function newInviteCode() {
    for (;;) {
      const bytes = crypto.randomBytes(6);
      const code = [...bytes].map((b) => INVITE_ALPHABET[b % INVITE_ALPHABET.length]).join('');
      if (!store.circleByCode(code)) return code;
    }
  }

  function startSession(user) {
    const { token, hash } = newSessionToken();
    store.createSession(hash, user.id, now());
    return { token, ...meResponse(user) };
  }

  // ---------- routes ----------

  const router = createRouter();
  const pub = { public: true };

  router.get('/health', () => ({ ok: true }), pub);

  router.post(
    '/api/auth/register',
    async ({ body }) => {
      const email = String(body.email ?? '').trim().toLowerCase();
      const password = String(body.password ?? '');
      const name = cleanName(body.name, 30, 'имя');
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new HttpError(400, 'Проверь email');
      if (password.length < 6) throw new HttpError(400, 'Пароль — минимум 6 символов');
      if (store.userByEmail(email)) throw new HttpError(409, 'Такой email уже зарегистрирован');
      const user = { id: crypto.randomUUID(), email, name, circleId: null };
      store.createUser({ ...user, passwordHash: await hashPassword(password), now: now() });
      return startSession(user);
    },
    pub,
  );

  router.post(
    '/api/auth/login',
    async ({ body }) => {
      const email = String(body.email ?? '').trim().toLowerCase();
      if (loginLimiter.blocked(email, now())) throw new HttpError(429, 'Слишком много попыток, подожди 15 минут');
      const user = store.userByEmail(email);
      if (!user || !(await verifyPassword(String(body.password ?? ''), user.passwordHash))) {
        loginLimiter.fail(email, now());
        throw new HttpError(401, 'Неверный email или пароль');
      }
      loginLimiter.reset(email);
      return startSession(user);
    },
    pub,
  );

  router.post('/api/auth/logout', ({ req, user, body }) => {
    store.deleteSession(hashToken(req.headers.authorization.slice(7).trim()));
    if (body.deviceToken) store.deleteDevice(String(body.deviceToken), user.id);
    return { ok: true };
  });

  router.get('/api/me', ({ user }) => meResponse(user));

  router.patch('/api/me', ({ user, body }) => {
    store.renameUser(user.id, cleanName(body.name, 30, 'имя'));
    return meResponse(store.user(user.id));
  });

  router.post('/api/devices', ({ user, body }) => {
    const token = String(body.token ?? '');
    const env = body.env === 'sandbox' ? 'sandbox' : 'production';
    if (!/^[0-9a-f]{32,200}$/i.test(token)) throw new HttpError(400, 'Некорректный токен устройства');
    store.upsertDevice(token.toLowerCase(), user.id, env, now());
    return { ok: true };
  });

  router.delete('/api/devices/:token', ({ user, params }) => {
    store.deleteDevice(params.token.toLowerCase(), user.id);
    return { ok: true };
  });

  router.post('/api/circles', ({ user, body }) => {
    if (user.circleId) throw new HttpError(409, 'Ты уже в компании — сначала выйди из неё');
    const circle = { id: crypto.randomUUID(), name: cleanName(body.name, 40, 'название'), ownerId: user.id };
    store.transaction(() => {
      store.createCircle({ ...circle, inviteCode: newInviteCode(), now: now() });
      store.setUserCircle(user.id, circle.id);
    });
    return meResponse(store.user(user.id));
  });

  router.post('/api/circles/join', ({ user, body }) => {
    const code = String(body.code ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '');
    const circle = store.circleByCode(code);
    if (!circle) throw new HttpError(404, 'Компания с таким кодом не найдена');
    if (user.circleId === circle.id) return meResponse(user);
    if (user.circleId) throw new HttpError(409, 'Ты уже в компании — сначала выйди из неё');
    const others = store.members(circle.id);
    if (others.length >= config.maxCircleMembers) throw new HttpError(409, 'В компании уже максимум участников');
    store.setUserCircle(user.id, circle.id);
    background(push.sendToUsers(others.map((m) => m.id), joinedMessage({ user, circle })));
    return meResponse(store.user(user.id));
  });

  router.post('/api/circles/leave', ({ user }) => {
    store.setUserCircle(user.id, null);
    return meResponse(store.user(user.id));
  });

  router.patch('/api/circle', ({ user, body }) => {
    store.renameCircle(requireCircle(user), cleanName(body.name, 40, 'название'));
    return meResponse(user);
  });

  router.get('/api/photos', ({ user, url }) => {
    const circleId = requireCircle(user);
    const before = Number(url.searchParams.get('before')) || Number.MAX_SAFE_INTEGER;
    const limit = Math.min(Math.max(Number(url.searchParams.get('limit')) || 30, 1), 100);
    return { photos: serializePhotos(store.feed(circleId, before, limit), user.id) };
  });

  router.post(
    '/api/photos',
    ({ user, url, body }) => {
      const circleId = requireCircle(user);
      if (body.length < 3 || body[0] !== 0xff || body[1] !== 0xd8 || body[2] !== 0xff) {
        throw new HttpError(400, 'Нужна картинка в формате JPEG');
      }
      const caption = String(url.searchParams.get('caption') ?? '').replace(/\s+/g, ' ').trim().slice(0, 60) || null;
      const file = `${crypto.randomBytes(16).toString('hex')}.jpg`;
      fs.writeFileSync(path.join(mediaDir, file), body);
      const t = now();
      const id = crypto.randomUUID();
      store.insertPhoto({ id, circleId, authorId: user.id, weekId: calendar.weekIdFor(t), caption, file, now: t });
      const photo = store.photo(id);
      const friends = store.members(circleId).filter((m) => m.id !== user.id).map((m) => m.id);
      background(push.sendToUsers(friends, newPhotoMessage({ photo, imageUrl: mediaUrl(file) })));
      return { photo: serializePhotos([photo], user.id)[0] };
    },
    { raw: true },
  );

  router.get('/api/photos/:id', ({ user, params }) => ({ photo: serializePhotos([photoInCircle(user, params.id)], user.id)[0] }));

  router.delete('/api/photos/:id', ({ user, params }) => {
    const photo = photoInCircle(user, params.id);
    if (photo.authorId !== user.id) throw new HttpError(403, 'Удалять можно только свои фото');
    store.deletePhoto(photo.id);
    fs.rm(path.join(mediaDir, photo.file), { force: true }, () => {});
    return { ok: true };
  });

  // Shared checks for stars and reactions: a friend's photo of the current week.
  function ratablePhoto(user, photoId) {
    const photo = photoInCircle(user, photoId);
    if (photo.authorId === user.id) throw new HttpError(403, 'Свои фото оценивать нельзя 😉');
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

  router.get('/api/week/current', ({ user }) => weekResults(requireCircle(user), currentWeekId()));

  router.get('/api/weeks', ({ user }) => ({ weeks: store.closedWeeks(requireCircle(user), 52) }));

  router.get('/api/weeks/:weekId', ({ user, params }) => {
    const circleId = requireCircle(user);
    const week = store.closedWeek(circleId, params.weekId);
    if (week) return week;
    if (params.weekId === currentWeekId()) return weekResults(circleId, params.weekId);
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
      if (!route.opts.public) ctx.user = authenticate(req);
      if (route.opts.raw) ctx.body = await readBody(req, MAX_PHOTO_BYTES);
      else ctx.body = req.method === 'GET' ? {} : await readJson(req);
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

  async function closeWeek(circleId, weekId, announce) {
    const results = weekResults(circleId, weekId, now());
    if (!store.saveWeek(circleId, weekId, results.closedAt, results)) return;
    if (announce) {
      const members = store.members(circleId).map((m) => m.id);
      await push.sendToUsers(members, weeklyResultsMessage(results));
    }
  }

  async function runDue() {
    const t = now();
    const weekId = calendar.weekIdFor(t);
    const { endsAt } = calendar.weekBounds(weekId);
    const previousWeekId = calendar.weekIdFor(calendar.weekBounds(weekId).startsAt - 1);

    // Close finished weeks. Only the week that just ended gets a push; older
    // ones only show up after a long server outage.
    for (const w of store.unclosedWeeksBefore(weekId)) {
      await closeWeek(w.circleId, w.weekId, w.weekId === previousWeekId);
    }

    const reminderMs = config.reminderHoursBefore * 3_600_000;
    if (reminderMs > 0 && t >= endsAt - reminderMs && t < endsAt) {
      for (const circleId of store.circlesWithPhotosIn(weekId)) {
        if (!store.claimJob(`reminder:${circleId}:${weekId}`, t)) continue;
        const hours = Math.max(1, Math.round((endsAt - t) / 3_600_000));
        for (const { userId, unrated } of store.unratedCounts(circleId, weekId)) {
          background(push.sendToUsers([userId], reminderMessage({ unrated, hours })));
        }
      }
    }
    await idle();
  }

  async function idle() {
    while (pending.size) await Promise.allSettled([...pending]);
  }

  return { handle, runDue, idle, store, calendar };
}
