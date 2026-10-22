import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { createApp } from '../src/app.js';
import { passwordKey } from '../src/auth.js';
import { openDb } from '../src/db.js';

const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4, 0xff, 0xd9]);
const PHOTO = JPEG.toString('base64');
const token = (ch) => ch.repeat(64);
// Saturday 10 Oct 2026, 12:00 Moscow: week 2026-W41.
const W41 = Date.UTC(2026, 9, 10, 9);
// Wednesday 14 Oct 2026, 12:00 Moscow: week 2026-W42, which closes Sunday 18 Oct 21:00 MSK = 18:00 UTC.
const W42 = Date.UTC(2026, 9, 14, 9);

/** A fresh server with an in-memory database, a fake APNs and a movable clock. */
async function harness(t, overrides = {}) {
  const sent = [];
  const deadTokens = new Set();
  const apns = {
    async send(deviceToken, env, payload, opts) {
      if (deadTokens.has(deviceToken)) return { status: 410, reason: 'Unregistered' };
      sent.push({ token: deviceToken, env, payload, opts });
      return { status: 200 };
    },
  };
  const clock = { now: W42 };
  const config = {
    publicUrl: 'https://locket.test',
    dataDir: fs.mkdtempSync(path.join(os.tmpdir(), 'locket-test-')),
    week: { tzOffsetMinutes: 180, endDay: 7, endHour: 21 },
    reminderHoursBefore: 3,
    passwordPepper: 'test-pepper',
    trustProxy: true,
    maxFriends: 100,
    ...overrides,
  };
  const log = { info() {}, warn() {}, error: console.error };
  const app = createApp({ config, db: openDb(':memory:'), apns, now: () => clock.now, log });
  const server = http.createServer(app.handle);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  t.after(() => new Promise((resolve) => server.close(resolve)));

  async function api(method, url, { auth, json, raw, ip = '10.0.0.1' } = {}) {
    const headers = { 'x-forwarded-for': ip };
    if (auth) headers.authorization = `Bearer ${auth}`;
    let body;
    if (json) {
      headers['content-type'] = 'application/json';
      body = JSON.stringify(json);
    } else if (raw) {
      headers['content-type'] = 'image/jpeg';
      body = raw;
    }
    const res = await fetch(base + url, { method, headers, body });
    const type = res.headers.get('content-type') || '';
    const data = type.includes('json') ? await res.json() : Buffer.from(await res.arrayBuffer());
    await app.idle();
    return { status: res.status, body: data, headers: res.headers };
  }

  /** The whole sign-up: unknown password → first photo → username. */
  async function signUp(password, username, { device, ip } = {}) {
    let res = await api('POST', '/api/auth/password', { json: { password }, ip });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body.status, 'new');
    res = await api('POST', '/api/auth/register', { json: { password, photo: PHOTO }, ip });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body.status, 'created');
    const auth = res.body.token;
    res = await api('POST', '/api/me/username', { auth, json: { username } });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    if (device) {
      assert.equal((await api('POST', '/api/devices', { auth, json: { token: device, env: 'sandbox' } })).status, 200);
    }
    return { token: auth, user: res.body.user, id: res.body.user.id };
  }

  async function befriend(a, b) {
    assert.equal((await api('POST', '/api/friends/requests', { auth: a.token, json: { userId: b.id } })).status, 200);
    const res = await api('POST', `/api/friends/requests/${b.id === a.id ? 'x' : a.id}/accept`, { auth: b.token });
    assert.equal(res.status, 200, JSON.stringify(res.body));
  }

  const upload = async (who, caption) => {
    const res = await api('POST', `/api/photos${caption ? `?caption=${encodeURIComponent(caption)}` : ''}`, { auth: who.token, raw: JPEG });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    return res.body;
  };
  const feedOf = async (who) => (await api('GET', '/api/photos', { auth: who.token })).body.photos;
  const pushesTo = (deviceToken) => sent.filter((s) => s.token === deviceToken).map((s) => s.payload);
  const lastPushTo = (deviceToken) => pushesTo(deviceToken).at(-1);

  return { app, api, sent, deadTokens, clock, config, signUp, befriend, upload, feedOf, pushesTo, lastPushTo };
}

test('the password is the account: new → first photo → username → back in by password alone', async (t) => {
  const h = await harness(t);
  const { api } = h;

  assert.equal((await api('POST', '/api/auth/password', { json: { password: 'abc' } })).body.error, 'Пароль — минимум 4 символа');
  assert.equal((await api('POST', '/api/auth/password', { json: { password: 'я'.repeat(65) } })).status, 400);
  assert.equal((await api('POST', '/api/auth/password', { json: { password: 12345 } })).status, 400, 'only strings');
  // Four Cyrillic letters are 8 bytes but 4 characters: allowed.
  assert.deepEqual((await api('POST', '/api/auth/password', { json: { password: 'ёжик' } })).body, { status: 'new' });

  // Nothing is created until the first photo arrives.
  assert.equal((await api('POST', '/api/auth/register', { json: { password: 'kotik123' } })).status, 400);
  assert.equal((await api('POST', '/api/auth/register', { json: { password: 'kotik123', photo: Buffer.from('GIF89a').toString('base64') } })).body.error, 'Нужна картинка в формате JPEG');
  assert.deepEqual((await api('POST', '/api/auth/password', { json: { password: 'kotik123' } })).body, { status: 'new' });

  let res = await api('POST', '/api/auth/register', { json: { password: 'kotik123', photo: PHOTO, caption: '  первое   фото ' } });
  assert.equal(res.status, 200);
  assert.equal(res.body.status, 'created');
  assert.equal(res.body.user.username, null);
  assert.deepEqual(res.body.friends, []);
  assert.equal(res.body.incomingRequests, 0);
  assert.equal(res.body.week.id, '2026-W42');
  assert.equal(res.body.week.endsAt, Date.UTC(2026, 9, 18, 18));
  const auth = res.body.token;
  const id = res.body.user.id;

  // Before a username: only the onboarding endpoints.
  assert.equal((await api('GET', '/api/photos', { auth })).body.error, 'Сначала выбери юзернейм');
  assert.equal((await api('GET', '/api/friends', { auth })).status, 409);
  assert.equal((await api('GET', '/api/users/search?q=ба', { auth })).status, 409);
  assert.equal((await api('GET', '/api/photos', {})).status, 401, '401 comes before 409');
  assert.equal((await api('GET', '/api/me', { auth })).body.user.username, null);
  assert.deepEqual((await api('GET', '/api/widget', { auth })).body, { photo: null });

  const suggestions = (await api('GET', '/api/usernames/suggestions', { auth })).body.suggestions;
  assert.deepEqual(suggestions.map((s) => s.kind), ['animal', 'swear', 'name']);
  assert.equal(new Set(suggestions.map((s) => s.username)).size, 3);

  // You can't type your own: only what the generator could have offered.
  assert.equal((await api('POST', '/api/me/username', { auth, json: { username: 'кот' } })).body.error, 'Такого юзернейма нет среди вариантов — выбери из предложенных');
  assert.equal((await api('POST', '/api/me/username', { auth, json: { username: 'барсук1' } })).status, 400);
  assert.equal((await api('POST', '/api/me/username', { auth, json: { username: 'барсук1000' } })).status, 400);
  res = await api('POST', '/api/me/username', { auth, json: { username: ' Барсук ' } });
  assert.equal(res.status, 200);
  assert.deepEqual(res.body.user, { id, username: 'барсук' });
  assert.equal((await api('POST', '/api/me/username', { auth, json: { username: 'енот' } })).body.error, 'Юзернейм уже выбран');
  assert.equal((await api('GET', '/api/usernames/suggestions', { auth })).status, 409);

  // Usernames are unique; «ё» and «е» are the same letter.
  const second = (await api('POST', '/api/auth/register', { json: { password: 'второй-пароль', photo: PHOTO } })).body;
  assert.equal((await api('POST', '/api/me/username', { auth: second.token, json: { username: 'барсук' } })).body.error, 'Этот юзернейм только что заняли — выбери другой');
  assert.equal((await api('POST', '/api/me/username', { auth: second.token, json: { username: 'ежик7' } })).body.user.username, 'ёжик7');
  const third = (await api('POST', '/api/auth/register', { json: { password: 'третий-пароль', photo: PHOTO } })).body;
  assert.equal((await api('POST', '/api/me/username', { auth: third.token, json: { username: 'ЁЖИК7' } })).status, 409);
  for (let i = 0; i < 30; i++) {
    const offered = (await api('GET', '/api/usernames/suggestions', { auth: third.token })).body.suggestions;
    assert.ok(!offered.some((s) => ['барсук', 'ёжик7'].includes(s.username)), 'taken usernames are never offered');
  }

  // Back in with the password alone, from anywhere.
  res = await api('POST', '/api/auth/password', { json: { password: 'kotik123' } });
  assert.equal(res.body.status, 'signedIn');
  assert.equal(res.body.user.id, id);
  assert.equal(res.body.user.username, 'барсук');
  assert.notEqual(res.body.token, auth);

  // The first photo was published at once.
  const feed = await h.feedOf({ token: auth });
  assert.equal(feed.length, 1);
  assert.equal(feed[0].caption, 'первое фото');
  assert.equal(feed[0].locked, false);
  assert.equal(feed[0].authorName, 'барсук');

  // Registering a password that already exists signs in and publishes there.
  res = await api('POST', '/api/auth/register', { json: { password: 'kotik123', photo: PHOTO } });
  assert.equal(res.body.status, 'signedIn');
  assert.equal(res.body.user.id, id);
  assert.equal((await h.feedOf({ token: auth })).length, 2);

  // NFC: «й» typed as one code point or as «и» + combining breve is the same password.
  await api('POST', '/api/auth/register', { json: { password: 'мой пароль', photo: PHOTO } });
  res = await api('POST', '/api/auth/password', { json: { password: 'мой пароль' } });
  assert.equal(res.body.status, 'signedIn');
  // Spaces are part of the password.
  assert.equal((await api('POST', '/api/auth/password', { json: { password: ' kotik123' } })).body.status, 'new');

  // Logging out ends only that session.
  const other = (await api('POST', '/api/auth/password', { json: { password: 'kotik123' } })).body.token;
  assert.equal((await api('POST', '/api/auth/logout', { auth, json: {} })).status, 200);
  assert.equal((await api('GET', '/api/me', { auth })).status, 401);
  assert.equal((await api('GET', '/api/me', { auth: other })).status, 200);

  // The account is found by HMAC(pepper, password); the password itself is not stored.
  assert.equal(h.app.store.userByPasswordKey(passwordKey('test-pepper', 'kotik123')).id, id);
  assert.equal(h.app.store.userByPasswordKey('kotik123'), undefined);
});

test('guessing is slowed down per client address', async (t) => {
  const h = await harness(t);
  const { api } = h;
  for (let i = 0; i < 20; i++) {
    assert.equal((await api('POST', '/api/auth/password', { json: { password: `guess-${i}` }, ip: '10.1.1.1' })).body.status, 'new');
  }
  let res = await api('POST', '/api/auth/password', { json: { password: 'guess-20' }, ip: '10.1.1.1' });
  assert.equal(res.status, 429);
  assert.equal(res.body.error, 'Слишком много попыток — подожди 10 минут');
  assert.equal((await api('POST', '/api/auth/register', { json: { password: 'guess-21', photo: PHOTO }, ip: '10.1.1.1' })).status, 429);
  assert.equal((await api('POST', '/api/auth/password', { json: { password: 'guess-20' }, ip: '10.1.1.2' })).body.status, 'new');
  h.clock.now += 10 * 60_000 + 1;
  assert.equal((await api('POST', '/api/auth/password', { json: { password: 'guess-20' }, ip: '10.1.1.1' })).body.status, 'new');

  // At most 10 new accounts an hour from one address; existing passwords still sign in.
  for (let i = 0; i < 10; i++) {
    assert.equal((await api('POST', '/api/auth/register', { json: { password: `account-${i}`, photo: PHOTO }, ip: '10.2.2.2' })).body.status, 'created');
  }
  res = await api('POST', '/api/auth/register', { json: { password: 'account-10', photo: PHOTO }, ip: '10.2.2.2' });
  assert.equal(res.status, 429);
  assert.equal(res.body.error, 'Слишком много новых аккаунтов — попробуй через час');
  assert.equal((await api('POST', '/api/auth/register', { json: { password: 'account-3', photo: PHOTO }, ip: '10.2.2.2' })).body.status, 'signedIn');
});

test('without TRUST_PROXY a forwarded address is ignored', async (t) => {
  const h = await harness(t, { trustProxy: false });
  for (let i = 0; i < 20; i++) await h.api('POST', '/api/auth/password', { json: { password: `guess-${i}` }, ip: `10.3.3.${i}` });
  assert.equal((await h.api('POST', '/api/auth/password', { json: { password: 'guess-x' }, ip: '10.3.4.4' })).status, 429);
});

test('friends find each other by username: request → accept', async (t) => {
  const h = await harness(t);
  const { api } = h;
  const bars = await h.signUp('bars-pass', 'барсук', { device: token('a') });
  const yara = await h.signUp('yara-pass', 'ярослава', { device: token('b') });
  const ezh = await h.signUp('ezh-pass', 'ёжик', { device: token('c') });
  const bars7 = await h.signUp('bars7-pass', 'барсук7');
  const nameless = (await api('POST', '/api/auth/register', { json: { password: 'nameless', photo: PHOTO } })).body;

  // Search: at least two letters, prefix, case and ё/е insensitive, exact match first.
  assert.deepEqual((await api('GET', '/api/users/search?q=б', { auth: yara.token })).body, { users: [] });
  let found = (await api('GET', `/api/users/search?q=${encodeURIComponent(' @БАРСУК ')}`, { auth: yara.token })).body.users;
  assert.deepEqual(found.map((u) => [u.username, u.relation]), [['барсук', 'none'], ['барсук7', 'none']]);
  found = (await api('GET', `/api/users/search?q=${encodeURIComponent('еж')}`, { auth: bars.token })).body.users;
  assert.deepEqual(found.map((u) => u.username), ['ёжик']);
  found = (await api('GET', `/api/users/search?q=${encodeURIComponent('бар')}`, { auth: bars.token })).body.users;
  assert.equal(found[0].relation, 'self');
  assert.equal((await api('GET', `/api/users/search?q=${encodeURIComponent('%_')}`, { auth: bars.token })).body.users.length, 0);

  // Request.
  const send = (from, to) => api('POST', '/api/friends/requests', { auth: from.token, json: { userId: to.id } });
  let res = await send(bars, yara);
  assert.equal(res.status, 200);
  assert.deepEqual(res.body.outgoing.map((r) => r.username), ['ярослава']);
  assert.deepEqual(res.body.friends, []);
  const request = h.lastPushTo(token('b'));
  assert.equal(request.type, 'friend_request');
  assert.equal(request.userId, bars.id);
  assert.equal(request.aps.category, 'FRIEND_REQUEST');
  assert.equal(request.aps.alert.title, 'Заявка в друзья');
  assert.equal(request.aps.alert.body, 'барсук хочет дружить');
  const pushes = h.sent.length;
  await send(bars, yara);
  assert.equal(h.sent.length, pushes, 'asking twice notifies once');
  assert.equal((await api('GET', '/api/me', { auth: yara.token })).body.incomingRequests, 1);
  assert.deepEqual((await api('GET', '/api/friends', { auth: yara.token })).body.incoming.map((r) => r.username), ['барсук']);
  found = (await api('GET', `/api/users/search?q=${encodeURIComponent('яро')}`, { auth: bars.token })).body.users;
  assert.equal(found[0].relation, 'outgoing');
  found = (await api('GET', `/api/users/search?q=${encodeURIComponent('бар')}`, { auth: yara.token })).body.users;
  assert.equal(found[0].relation, 'incoming');

  assert.equal((await send(bars, bars)).body.error, 'Это ты');
  assert.equal((await api('POST', '/api/friends/requests', { auth: bars.token, json: { userId: 'nope' } })).status, 404);
  assert.equal((await api('POST', '/api/friends/requests', { auth: bars.token, json: { userId: nameless.user.id } })).status, 404);

  // Accept.
  assert.equal((await api('POST', `/api/friends/requests/${ezh.id}/accept`, { auth: yara.token })).body.error, 'Заявка не найдена');
  res = await api('POST', `/api/friends/requests/${bars.id}/accept`, { auth: yara.token });
  assert.equal(res.status, 200);
  assert.deepEqual(res.body.friends.map((f) => f.username), ['барсук']);
  assert.deepEqual(res.body.incoming, []);
  const accepted = h.lastPushTo(token('a'));
  assert.equal(accepted.type, 'friend_accepted');
  assert.equal(accepted.userId, yara.id);
  assert.equal(accepted.aps.alert.body, 'ярослава теперь в друзьях');
  assert.deepEqual((await api('GET', '/api/me', { auth: bars.token })).body.friends, [{ id: yara.id, username: 'ярослава' }]);
  assert.equal((await api('POST', `/api/friends/requests/${bars.id}/accept`, { auth: yara.token })).status, 404);
  assert.equal((await send(yara, bars)).status, 200, 'already friends: nothing changes');

  // Asking someone who already asked you is accepting.
  await send(ezh, bars);
  res = await send(bars, ezh);
  assert.deepEqual(res.body.friends.map((f) => f.username), ['ёжик', 'ярослава']);
  assert.equal(h.lastPushTo(token('c')).type, 'friend_accepted');

  // Decline and cancel remove the request on both sides.
  await send(bars7, yara);
  res = await api('DELETE', `/api/friends/requests/${bars7.id}`, { auth: yara.token });
  assert.deepEqual(res.body.incoming, []);
  assert.deepEqual((await api('GET', '/api/friends', { auth: bars7.token })).body.outgoing, []);
  await send(bars7, yara);
  await api('DELETE', `/api/friends/requests/${yara.id}`, { auth: bars7.token });
  assert.equal((await api('GET', '/api/me', { auth: yara.token })).body.incomingRequests, 0);

  // Friends see each other's photos; removing a friend hides them again.
  const barsPhotoId = (await h.feedOf(bars)).find((p) => p.authorId === bars.id).id;
  assert.equal((await api('GET', `/api/photos/${barsPhotoId}`, { auth: yara.token })).status, 200);
  assert.equal((await api('GET', `/api/photos/${barsPhotoId}`, { auth: bars7.token })).status, 404, 'not friends');
  assert.deepEqual((await h.feedOf(yara)).map((p) => p.authorName).sort(), ['барсук', 'ярослава']);
  res = await api('DELETE', `/api/friends/${bars.id}`, { auth: yara.token });
  assert.deepEqual(res.body.friends, []);
  assert.deepEqual((await api('GET', '/api/friends', { auth: bars.token })).body.friends.map((f) => f.username), ['ёжик']);
  assert.equal((await api('GET', `/api/photos/${barsPhotoId}`, { auth: yara.token })).status, 404);
  assert.deepEqual((await h.feedOf(yara)).map((p) => p.authorName), ['ярослава']);
});

test('friend limit', async (t) => {
  const h = await harness(t, { maxFriends: 1 });
  const a = await h.signUp('aaaa', 'барсук');
  const b = await h.signUp('bbbb', 'ярослава');
  const c = await h.signUp('cccc', 'ёжик');
  await h.befriend(a, b);
  assert.equal((await h.api('POST', '/api/friends/requests', { auth: a.token, json: { userId: c.id } })).body.error, 'У тебя уже максимум друзей — 1');
  assert.equal((await h.api('POST', '/api/friends/requests', { auth: c.token, json: { userId: a.id } })).body.error, 'У барсук уже максимум друзей');
});

test('locked photos: one free per friend each week, one more for every photo you post', async (t) => {
  const h = await harness(t);
  const { api } = h;
  // Everyone's first photo of the week is their sign-up photo (rank 0).
  const me = await h.signUp('me-pass', 'барсук', { device: token('a') });
  const yara = await h.signUp('yara-pass', 'ярослава', { device: token('b') });
  const ezh = await h.signUp('ezh-pass', 'ёжик', { device: token('c') });
  const dobr = await h.signUp('dobr-pass', 'добрыня', { device: token('d') });
  await h.befriend(me, yara);
  await h.befriend(me, ezh);
  await h.befriend(dobr, yara);
  await h.befriend(dobr, me);
  const tick = () => (h.clock.now += 60_000);

  // I posted 1 photo this week, so I see 2 of each friend's photos.
  tick();
  const y2 = await h.upload(yara, 'второе');
  assert.equal(y2.unlocked, 0);
  let push = h.lastPushTo(token('a'));
  assert.equal(push.type, 'photo');
  assert.equal(push.photoId, y2.photo.id);
  assert.equal(push.aps.category, 'PHOTO_RATING');
  assert.equal(push.imageUrl, y2.photo.imageUrl);

  // Her third photo is locked for me: the push has no picture and no caption.
  tick();
  const y3 = (await h.upload(yara, 'секрет')).photo;
  assert.deepEqual(h.lastPushTo(token('a')), {
    aps: { alert: { title: 'ярослава', body: 'Новое фото закрыто — выложи своё, и оно откроется' }, sound: 'default', 'thread-id': 'photos' },
    type: 'locked',
    photoId: y3.id,
  });
  assert.equal(h.lastPushTo(token('d')).type, 'locked', 'the same rule for every friend');

  let feed = await h.feedOf(me);
  const lockedY3 = feed.find((p) => p.id === y3.id);
  assert.deepEqual(lockedY3, {
    id: y3.id,
    authorId: yara.id,
    authorName: 'ярослава',
    createdAt: y3.createdAt,
    weekId: '2026-W42',
    locked: true,
    caption: null,
    imageUrl: null,
    canReact: false,
    counts: { creative: 0, funny: 0, wild: 0 },
    stars: { count: 0, total: 0, average: 0 },
    myStars: 0,
    mine: [],
    reactors: [],
    raters: [],
  });
  assert.equal(feed.find((p) => p.id === y2.photo.id).locked, false);
  const file = new URL(y3.imageUrl).pathname;
  for (const body of [feed, (await api('GET', `/api/photos/${y3.id}`, { auth: me.token })).body, (await api('GET', '/api/widget', { auth: me.token })).body]) {
    const json = JSON.stringify(body);
    assert.ok(!json.includes('секрет') && !json.includes(file), 'nothing of a locked photo leaks');
  }
  assert.equal((await api('GET', `/api/photos/${y3.id}`, { auth: me.token })).body.photo.locked, true);
  let res = await api('PUT', `/api/photos/${y3.id}/stars`, { auth: me.token, json: { stars: 3 } });
  assert.equal(res.status, 403);
  assert.equal(res.body.error, 'Это фото закрыто — выложи своё, чтобы открыть');
  assert.equal((await api('PUT', `/api/photos/${y3.id}/reactions/funny`, { auth: me.token })).status, 403);
  assert.equal((await api('GET', '/api/widget', { auth: me.token })).body.photo.id, y2.photo.id, 'the widget shows the newest open photo');
  // The author always sees her own photos.
  assert.equal((await h.feedOf(yara)).find((p) => p.id === y3.id).caption, 'секрет');

  // I post: one more photo of every friend opens.
  tick();
  const m2 = await h.upload(me);
  assert.equal(m2.unlocked, 1, 'only ярослава had a locked photo');
  feed = await h.feedOf(me);
  assert.equal(feed.find((p) => p.id === y3.id).caption, 'секрет');
  for (const device of ['b', 'c', 'd']) assert.equal(h.lastPushTo(token(device)).type, 'photo', 'my second photo is open for everyone');
  assert.equal((await api('PUT', `/api/photos/${y3.id}/stars`, { auth: me.token, json: { stars: 1 } })).status, 200, 'open now: rating works');
  await api('DELETE', `/api/photos/${y3.id}/stars`, { auth: me.token });

  // добрыня posts three more: his fourth is locked for me (I have posted 2).
  for (let i = 0; i < 3; i++) {
    tick();
    await h.upload(dobr);
  }
  assert.deepEqual(pushTypes(h.pushesTo(token('a')).slice(-3)), ['photo', 'photo', 'locked']);
  // He has posted 4, so he sees ярослава's third photo and rates it.
  assert.equal((await api('PUT', `/api/photos/${y3.id}/stars`, { auth: dobr.token, json: { stars: 3 } })).status, 200);

  tick();
  const y4 = (await h.upload(yara, 'лучшее')).photo;
  assert.equal(h.lastPushTo(token('a')).type, 'locked');
  assert.equal(h.lastPushTo(token('d')).type, 'photo');
  await api('PUT', `/api/photos/${y4.id}/stars`, { auth: dobr.token, json: { stars: 3 } });
  await api('PUT', `/api/photos/${y4.id}/reactions/funny`, { auth: dobr.token });

  // Not friends: nothing at all.
  assert.equal((await api('GET', `/api/photos/${y2.photo.id}`, { auth: ezh.token })).status, 404);
  assert.deepEqual([...new Set((await h.feedOf(ezh)).map((p) => p.authorName))].sort(), ['барсук', 'ёжик']);

  // The photo of the week is the prize: its picture shows even where it is locked.
  const live = (await api('GET', '/api/week/current', { auth: me.token })).body;
  assert.deepEqual(live.leaderboard.map((s) => s.name).sort(), ['барсук', 'добрыня', 'ярослава', 'ёжик']);
  assert.equal(live.bestPhoto.photoId, y4.id);
  assert.equal(live.bestPhoto.imageUrl, y4.imageUrl);
  assert.equal(live.photoCount, 11);
  assert.equal((await h.feedOf(me)).find((p) => p.id === y4.id).locked, true);
  // ёжик's circle is only ёжик and барсук.
  assert.deepEqual((await api('GET', '/api/week/current', { auth: ezh.token })).body.leaderboard.map((s) => s.name).sort(), ['барсук', 'ёжик']);

  // Sunday 18:30 MSK: unrated and locked counts.
  h.clock.now = Date.UTC(2026, 9, 18, 15, 30);
  h.sent.length = 0;
  await h.app.runDue();
  assert.equal(h.lastPushTo(token('a')).aps.alert.body, '7 фото ждут твоей оценки — успей до итогов · ещё 2 закрыты — выложи своё');
  assert.equal(h.lastPushTo(token('c')).aps.alert.body, '2 фото ждут твоей оценки — успей до итогов');

  // Monday: the week closes, everyone gets their own results.
  h.clock.now = Date.UTC(2026, 9, 19, 7);
  h.sent.length = 0;
  await h.app.runDue();
  assert.equal(h.lastPushTo(token('a')).type, 'weekly');
  assert.equal(h.lastPushTo(token('a')).imageUrl, y4.imageUrl);
  assert.equal(h.sent.length, 4);

  // A new week: her first photo is free again; last week's stays as it was.
  const y5 = (await h.upload(yara)).photo;
  assert.equal(y5.weekId, '2026-W43');
  assert.equal(h.lastPushTo(token('a')).type, 'photo');
  feed = await h.feedOf(me);
  assert.equal(feed.find((p) => p.id === y5.id).locked, false);
  assert.equal(feed.find((p) => p.id === y4.id).locked, true);

  // You see as many as you posted: deleting my photo closes one again.
  assert.equal((await api('DELETE', `/api/photos/${m2.photo.id}`, { auth: me.token })).status, 200);
  assert.equal((await h.feedOf(me)).find((p) => p.id === y3.id).locked, true);
});

const pushTypes = (payloads) => payloads.map((p) => p.type);

test('a full week: photos, ratings on the lock screen, reminder, awards', async (t) => {
  const h = await harness(t);
  const { api, lastPushTo, sent } = h;
  // Sign up the week before, so the sign-up photos don't count in this week.
  h.clock.now = W41;
  const masha = await h.signUp('masha-pass', 'ярослава');
  const petya = await h.signUp('petya-pass', 'барсук');
  const olya = await h.signUp('olya-pass', 'ёжик');
  await h.befriend(masha, petya);
  await h.befriend(masha, olya);
  await h.befriend(petya, olya);
  h.clock.now = W42;
  await h.app.runDue(); // closes 2026-W41
  for (const [who, ch] of [[masha, 'a'], [petya, 'b'], [olya, 'c']]) {
    assert.equal((await api('POST', '/api/devices', { auth: who.token, json: { token: token(ch), env: 'sandbox' } })).status, 200);
  }
  assert.equal((await api('POST', '/api/devices', { auth: masha.token, json: { token: 'not-a-token' } })).status, 400);
  const relogin = (await api('POST', '/api/auth/password', { json: { password: 'petya-pass' } })).body;

  // --- photos ---
  assert.equal((await api('POST', '/api/photos', { auth: masha.token, raw: Buffer.from('GIF89a') })).status, 400);
  const up = await api('POST', `/api/photos?caption=${encodeURIComponent('  На   море 🌊 ')}`, { auth: masha.token, raw: JPEG });
  assert.equal(up.status, 200);
  const m1 = up.body.photo;
  assert.equal(m1.caption, 'На море 🌊');
  assert.equal(m1.canReact, false);
  assert.equal(m1.locked, false);
  assert.match(m1.imageUrl, /^https:\/\/locket\.test\/media\/[a-f0-9]{32}\.jpg$/);

  const notif = lastPushTo(token('b'));
  assert.equal(notif.type, 'photo');
  assert.equal(notif.aps.category, 'PHOTO_RATING');
  assert.equal(notif.aps['mutable-content'], 1);
  assert.equal(notif.aps.alert.title, 'ярослава');
  assert.equal(notif.aps.alert.body, '«На море 🌊» — удерживай, чтобы оценить');
  assert.equal(notif.photoId, m1.id);
  assert.equal(notif.imageUrl, m1.imageUrl);
  assert.equal(lastPushTo(token('c')).photoId, m1.id);
  assert.notEqual(lastPushTo(token('a'))?.photoId, m1.id, 'author does not get her own photo');

  const media = await api('GET', new URL(m1.imageUrl).pathname);
  assert.equal(media.status, 200);
  assert.equal(media.headers.get('content-type'), 'image/jpeg');
  assert.deepEqual(media.body, JPEG);
  assert.equal((await api('GET', '/media/../locket.db')).status, 404);

  // --- ratings (the same calls the lock-screen notification makes) ---
  const rate = (who, photoId, kind, method = 'PUT') => api(method, `/api/photos/${photoId}/reactions/${kind}`, { auth: who.token });
  const starIt = (who, photoId, stars) => api('PUT', `/api/photos/${photoId}/stars`, { auth: who.token, json: { stars } });

  let res = await starIt(petya, m1.id, 3);
  assert.equal(res.status, 200);
  assert.equal(res.body.photo.myStars, 3);
  assert.deepEqual(res.body.photo.stars, { count: 1, total: 3, average: 3 });
  const firstReactionPush = sent.at(-1);
  assert.equal(firstReactionPush.token, token('a'));
  assert.equal(firstReactionPush.payload.aps.alert.title, 'барсук');
  assert.equal(firstReactionPush.payload.aps.alert.body, '3 звезды — твоему фото');

  res = await rate(petya, m1.id, 'creative');
  assert.deepEqual(res.body.photo.counts, { creative: 1, funny: 0, wild: 0 });
  assert.deepEqual(res.body.photo.mine, ['creative']);
  assert.equal(lastPushTo(token('a')).aps.alert.body, '3 звезды · ✍️ — твоему фото');
  assert.equal(sent.at(-1).opts.collapseId, firstReactionPush.opts.collapseId, 'replaces the earlier notification');

  const before = sent.length;
  await starIt(petya, m1.id, 3);
  await rate(petya, m1.id, 'creative');
  assert.equal(sent.length, before, 'repeating a rating sends nothing');

  await starIt(petya, m1.id, 2);
  assert.equal(lastPushTo(token('a')).aps.alert.body, '2 звезды · ✍️ — твоему фото');
  res = await rate(petya, m1.id, 'creative', 'DELETE');
  assert.deepEqual(res.body.photo.counts, { creative: 0, funny: 0, wild: 0 });
  await rate(petya, m1.id, 'funny');
  assert.equal(lastPushTo(token('a')).aps.alert.body, '2 звезды · 😂 — твоему фото');
  await starIt(olya, m1.id, 1);
  await rate(olya, m1.id, 'funny');

  assert.equal((await starIt(masha, m1.id, 3)).body.error, 'Свои фото оценивать нельзя');
  assert.equal((await rate(masha, m1.id, 'funny')).status, 403);
  assert.equal((await starIt(olya, m1.id, 4)).status, 400);
  assert.equal((await starIt(olya, m1.id, 0)).status, 400);
  assert.equal((await rate(olya, m1.id, 'fire')).status, 400);
  assert.equal((await rate(olya, 'missing', 'funny')).status, 404);

  h.clock.now += 3_600_000;
  const p1 = (await api('POST', '/api/photos', { auth: petya.token, raw: JPEG })).body.photo;
  await starIt(olya, p1.id, 3);
  await rate(olya, p1.id, 'wild');
  await starIt(masha, p1.id, 1);
  // Clearing stars works and is silent.
  const quiet = sent.length;
  res = await api('DELETE', `/api/photos/${p1.id}/stars`, { auth: masha.token });
  assert.equal(res.body.photo.myStars, 0);
  assert.equal(sent.length, quiet);
  await starIt(masha, p1.id, 2);
  await rate(masha, p1.id, 'creative');
  h.clock.now += 3_600_000;
  const o1 = (await api('POST', '/api/photos?caption=кот', { auth: olya.token, raw: JPEG })).body.photo;

  const feed = await h.feedOf(masha);
  assert.deepEqual(feed.slice(0, 3).map((p) => p.id), [o1.id, p1.id, m1.id]);
  assert.equal(feed.length, 6, 'plus the three sign-up photos of last week');
  assert.deepEqual(feed[1].mine, ['creative']);
  assert.equal(feed[1].myStars, 2);
  assert.deepEqual(feed[1].stars, { count: 2, total: 5, average: 2.5 });
  assert.deepEqual(feed[2].counts, { creative: 0, funny: 2, wild: 0 });
  assert.deepEqual(feed[2].stars, { count: 2, total: 3, average: 1.5 });
  assert.deepEqual(feed[2].reactors.map((r) => `${r.name}:${r.kind}`), ['барсук:funny', 'ёжик:funny']);
  assert.deepEqual(feed[2].raters.map((r) => `${r.name}:${r.stars}`), ['барсук:2', 'ёжик:1']);
  assert.ok(feed.every((p) => !p.locked));
  const widget = (await api('GET', '/api/widget', { auth: olya.token })).body.photo;
  assert.equal(widget.id, p1.id, "the widget shows a friend's newest photo, not your own");
  assert.equal(widget.myStars, 3);
  assert.deepEqual(widget.mine, ['wild']);
  const page2 = (await api('GET', `/api/photos?before=${feed[1].createdAt}&limit=1`, { auth: masha.token })).body.photos;
  assert.deepEqual(page2.map((p) => p.id), [m1.id]);

  // --- live standings ---
  const live = (await api('GET', '/api/week/current', { auth: olya.token })).body;
  assert.equal(live.closedAt, null);
  assert.equal(live.photoCount, 3);
  assert.deepEqual(live.leaderboard.map((s) => [s.name, s.points]), [['барсук', 11], ['ярослава', 9], ['ёжик', 6]]);

  // --- Sunday 18:30 MSK: reminder to those with unrated photos ---
  h.clock.now = Date.UTC(2026, 9, 18, 15, 30);
  sent.length = 0;
  await h.app.runDue();
  assert.deepEqual(sent.map((s) => s.token).sort(), [token('a'), token('b')]);
  assert.equal(sent[0].payload.aps.alert.body, '1 фото ждёт твоей оценки — успей до итогов');
  assert.equal(sent[0].payload.aps.alert.title, 'До итогов недели 3 ч');
  await h.app.runDue();
  assert.equal(sent.length, 2, 'reminder is sent once');

  // --- Sunday 21:00 MSK: the week closes ---
  h.clock.now = Date.UTC(2026, 9, 18, 18, 0, 30);
  sent.length = 0;
  await h.app.runDue();
  assert.equal(sent.length, 3);
  const weekly = lastPushTo(token('c'));
  assert.equal(weekly.aps.alert.title, 'Итоги недели');
  assert.equal(weekly.aps.alert.body, 'Друг недели — барсук\nФото недели — барсук\n✍️ барсук · 😂 ярослава · 🫪 барсук · самый активный — ёжик');
  assert.equal(weekly.aps.category, 'WEEKLY_RESULTS');
  assert.equal(weekly.weekId, '2026-W42');
  assert.equal(weekly.imageUrl, p1.imageUrl);
  await h.app.runDue();
  assert.equal(sent.length, 3, 'results are announced once');

  const weeks = (await api('GET', '/api/weeks', { auth: petya.token })).body.weeks;
  assert.deepEqual(weeks.map((w) => w.weekId), ['2026-W42', '2026-W41']);
  assert.equal(weeks[0].closedAt, h.clock.now);
  assert.equal(weeks[0].bestPhoto.photoId, p1.id);
  assert.deepEqual([weeks[0].bestPhoto.stars, weeks[0].bestPhoto.starCount], [5, 2]);
  assert.equal(weeks[0].friendOfWeek.name, 'барсук');
  assert.equal(weeks[0].mostFunny.name, 'ярослава');
  assert.equal(weeks[0].mostCreative.name, 'барсук');
  assert.equal(weeks[0].mostWild.name, 'барсук');
  assert.equal(weeks[0].mostActive.name, 'ёжик');
  assert.deepEqual((await api('GET', '/api/weeks/2026-W42', { auth: petya.token })).body, weeks[0]);
  assert.equal((await api('GET', '/api/weeks/2026-W30', { auth: petya.token })).status, 404);

  // Voting for the closed week is over, the new week starts empty.
  assert.equal((await rate(masha, o1.id, 'funny')).status, 409);
  assert.equal((await starIt(masha, o1.id, 3)).body.error, 'Голосование за ту неделю уже закрыто');
  assert.equal((await h.feedOf(masha))[0].canReact, false);
  const w43 = (await api('POST', '/api/photos', { auth: olya.token, raw: JPEG })).body.photo;
  assert.equal(w43.weekId, '2026-W43');
  assert.equal((await api('GET', '/api/week/current', { auth: olya.token })).body.photoCount, 1);

  // --- dead device tokens are dropped ---
  h.deadTokens.add(token('c'));
  await api('POST', '/api/photos', { auth: masha.token, raw: JPEG });
  assert.equal(h.app.store.devicesForUsers([olya.id]).length, 0);

  // --- deleting, unfriending, logging out ---
  assert.equal((await api('DELETE', `/api/photos/${w43.id}`, { auth: masha.token })).status, 403);
  assert.equal((await api('DELETE', `/api/photos/${w43.id}`, { auth: olya.token })).status, 200);
  assert.equal((await api('GET', `/api/photos/${w43.id}`, { auth: olya.token })).status, 404);
  assert.equal((await api('GET', new URL(w43.imageUrl).pathname)).status, 404);

  await api('DELETE', `/api/friends/${masha.id}`, { auth: olya.token });
  await api('DELETE', `/api/friends/${petya.id}`, { auth: olya.token });
  assert.equal((await api('GET', '/api/widget', { auth: olya.token })).body.photo, null);
  assert.equal((await api('GET', `/api/photos/${m1.id}`, { auth: olya.token })).status, 404);

  assert.equal((await api('POST', '/api/auth/logout', { auth: petya.token, json: { deviceToken: token('b') } })).status, 200);
  assert.equal((await api('GET', '/api/me', { auth: petya.token })).status, 401);
  assert.equal(h.app.store.devicesForUsers([petya.id]).length, 0);
  assert.equal((await api('GET', '/api/me', { auth: relogin.token })).status, 200, 'other sessions stay');
});

test('oversized uploads are rejected cleanly', async (t) => {
  const h = await harness(t);
  const user = await h.signUp('big-pass', 'барсук');
  const huge = Buffer.alloc(9 * 1024 * 1024, 0xff);
  assert.equal((await h.api('POST', '/api/photos', { auth: user.token, raw: huge })).status, 413);
  const res = await h.api('POST', '/api/auth/register', { json: { password: 'другой', photo: huge.toString('base64') } });
  assert.equal(res.status, 413);
  assert.equal((await h.api('POST', '/api/auth/password', { json: { password: 'другой' } })).body.status, 'new');
});
