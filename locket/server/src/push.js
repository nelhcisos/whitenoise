import crypto from 'node:crypto';

// Identifiers shared with the iOS app (Locket/Core/PushSupport.swift).
export const CATEGORY_RATE_PHOTO = 'PHOTO_RATING';
export const CATEGORY_WEEKLY = 'WEEKLY_RESULTS';
export const CATEGORY_FRIEND_REQUEST = 'FRIEND_REQUEST'; // has the «Принять» button

// Reaction marks are the app's rating scale (data), the only emoji in push copy.
const EMOJI = { creative: '✍️', funny: '😂', wild: '🫪' };
const NBSP = '\u00a0';

function plural(n, one, few, many) {
  const mod10 = n % 10;
  const mod100 = n % 100;
  if (mod10 === 1 && mod100 !== 11) return one;
  if (mod10 >= 2 && mod10 <= 4 && !(mod100 >= 12 && mod100 <= 14)) return few;
  return many;
}

export function createPushService({ store, apns, log = console }) {
  async function sendToUsers(userIds, payload, opts = {}) {
    if (!userIds.length) return;
    const devices = store.devicesForUsers(userIds);
    if (!apns) {
      log.info(`[push dry-run] ${devices.length} device(s): ${payload.aps.alert.title} — ${payload.aps.alert.body}`);
      return;
    }
    await Promise.all(
      devices.map(async (d) => {
        const res = await apns.send(d.token, d.env, payload, opts);
        if (res.status === 200) return;
        if (res.status === 410 || ['BadDeviceToken', 'DeviceTokenNotForTopic', 'Unregistered'].includes(res.reason)) {
          store.deleteDevice(d.token);
        } else {
          log.warn(`APNs ${res.status} ${res.reason ?? ''} for user ${d.userId}`);
        }
      }),
    );
  }
  return { sendToUsers };
}

// A friend posted a photo that is open for you: rich notification. The app's
// extensions download the image and show stars 1–3 plus ✍️ / 😂 / 🫪 when it is
// long-pressed, even on the lock screen.
export function newPhotoMessage({ photo, imageUrl }) {
  return {
    aps: {
      alert: {
        title: photo.authorName,
        body: photo.caption ? `«${photo.caption}» — удерживай, чтобы оценить` : 'Новое фото — удерживай, чтобы оценить',
      },
      sound: 'default',
      category: CATEGORY_RATE_PHOTO,
      'mutable-content': 1,
      'thread-id': 'photos',
    },
    type: 'photo',
    photoId: photo.id,
    authorId: photo.authorId,
    authorName: photo.authorName,
    caption: photo.caption ?? '',
    imageUrl,
    createdAt: photo.createdAt,
  };
}

// A friend posted a photo that is locked for you: no picture, no caption —
// post your own to open it.
export function lockedPhotoMessage({ photo }) {
  return {
    aps: {
      alert: { title: photo.authorName, body: 'Новое фото закрыто — выложи своё, и оно откроется' },
      sound: 'default',
      'thread-id': 'photos',
    },
    type: 'locked',
    photoId: photo.id,
  };
}

// Someone rated your photo. One notification per (photo, friend): later taps
// replace it via apns-collapse-id instead of stacking up.
export function reactionMessage({ photo, reactor, stars, kinds, imageUrl }) {
  const parts = [];
  if (stars) parts.push(`${stars}${NBSP}${plural(stars, 'звезда', 'звезды', 'звёзд')}`);
  const marks = Object.keys(EMOJI).filter((k) => kinds.includes(k)).map((k) => EMOJI[k]);
  if (marks.length) parts.push(marks.join(' '));
  return {
    payload: {
      aps: {
        alert: { title: reactor.username, body: `${parts.join(' · ')} — твоему фото` },
        sound: 'default',
        'mutable-content': 1,
        'thread-id': 'reactions',
      },
      type: 'reaction',
      photoId: photo.id,
      imageUrl,
    },
    opts: { collapseId: crypto.createHash('sha1').update(`${photo.id}:${reactor.id}`).digest('hex') },
  };
}

export function weeklyResultsMessage(results) {
  const lines = [];
  if (results.friendOfWeek) lines.push(`Друг недели — ${results.friendOfWeek.name}`);
  if (results.bestPhoto) lines.push(`Фото недели — ${results.bestPhoto.authorName}`);
  const nominations = [
    results.mostCreative && `✍️ ${results.mostCreative.name}`,
    results.mostFunny && `😂 ${results.mostFunny.name}`,
    results.mostWild && `🫪 ${results.mostWild.name}`,
    results.mostActive && `самый активный — ${results.mostActive.name}`,
  ].filter(Boolean);
  if (nominations.length) lines.push(nominations.join(' · '));
  return {
    aps: {
      alert: { title: 'Итоги недели', body: lines.join('\n') || 'Неделя закрыта — открой Locket, чтобы посмотреть итоги' },
      sound: 'default',
      category: CATEGORY_WEEKLY,
      'mutable-content': 1,
      'thread-id': 'weekly',
    },
    type: 'weekly',
    weekId: results.weekId,
    imageUrl: results.bestPhoto?.imageUrl ?? '',
  };
}

// Before the week closes: friends' photos still waiting for your rating, and
// the ones you can't see until you post.
export function reminderMessage({ unrated, locked = 0, hours }) {
  const closed = (n) => `${n}${NBSP}${plural(n, 'закрыто', 'закрыты', 'закрыты')}`;
  let body;
  if (unrated > 0) {
    body = `${unrated}${NBSP}${plural(unrated, 'фото ждёт', 'фото ждут', 'фото ждут')} твоей оценки — успей до итогов`;
    if (locked > 0) body += ` · ещё ${closed(locked)} — выложи своё`;
  } else {
    body = `${locked}${NBSP}фото друзей ${plural(locked, 'закрыто', 'закрыты', 'закрыты')} — выложи своё, чтобы открыть`;
  }
  return {
    aps: { alert: { title: `До итогов недели ${hours}${NBSP}ч`, body }, sound: 'default', 'thread-id': 'weekly' },
    type: 'reminder',
  };
}

export function friendRequestMessage({ from }) {
  return {
    aps: {
      alert: { title: 'Заявка в друзья', body: `${from.username} хочет дружить` },
      sound: 'default',
      category: CATEGORY_FRIEND_REQUEST,
      'thread-id': 'friends',
    },
    type: 'friend_request',
    userId: from.id,
  };
}

export function friendAcceptedMessage({ user }) {
  return {
    aps: { alert: { title: 'Новый друг', body: `${user.username} теперь в друзьях` }, sound: 'default', 'thread-id': 'friends' },
    type: 'friend_accepted',
    userId: user.id,
  };
}
