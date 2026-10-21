import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { after, before, test } from 'node:test';
import { createApp } from '../src/app.js';
import { openDb } from '../src/db.js';

// Wednesday 14 Oct 2026, 12:00 Moscow. The week closes Sunday 18 Oct 21:00 MSK = 18:00 UTC.
let clock = Date.UTC(2026, 9, 14, 9);
const sent = [];
const deadTokens = new Set();
const apns = {
  async send(token, env, payload, opts) {
    if (deadTokens.has(token)) return { status: 410, reason: 'Unregistered' };
    sent.push({ token, env, payload, opts });
    return { status: 200 };
  },
};

let app, server, base;
const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4, 0xff, 0xd9]);
const token = (ch) => ch.repeat(64);

before(async () => {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'locket-test-'));
  const config = {
    publicUrl: 'https://locket.test',
    dataDir,
    week: { tzOffsetMinutes: 180, endDay: 7, endHour: 21 },
    reminderHoursBefore: 3,
    maxCircleMembers: 30,
  };
  const log = { info() {}, warn() {}, error: console.error };
  app = createApp({ config, db: openDb(':memory:'), apns, now: () => clock, log });
  server = http.createServer(app.handle);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => server.close());

async function api(method, url, { auth, json, raw } = {}) {
  const headers = {};
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

const pushesTo = (deviceToken) => sent.filter((s) => s.token === deviceToken).map((s) => s.payload);
const lastPushTo = (deviceToken) => pushesTo(deviceToken).at(-1);

test('a full week: sign up, circle, photos, ratings, reminder, awards', async () => {
  // --- accounts ---
  const reg = async (name, email) => {
    const res = await api('POST', '/api/auth/register', { json: { name, email, password: 'secret1' } });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    return res.body;
  };
  const masha = await reg('Маша', 'Masha@Example.com');
  const petya = await reg('Петя', 'petya@example.com');
  const olya = await reg('Оля', 'olya@example.com');
  assert.equal(masha.user.email, 'masha@example.com');
  assert.equal(masha.circle, null);
  assert.equal(masha.week.id, '2026-W42');
  assert.equal(masha.week.endsAt, Date.UTC(2026, 9, 18, 18));

  assert.equal((await api('POST', '/api/auth/register', { json: { name: 'X', email: 'petya@example.com', password: 'secret1' } })).status, 409);
  assert.equal((await api('POST', '/api/auth/register', { json: { name: 'X', email: 'x@example.com', password: '123' } })).status, 400);
  assert.equal((await api('POST', '/api/auth/login', { json: { email: 'petya@example.com', password: 'nope' } })).status, 401);
  const relogin = await api('POST', '/api/auth/login', { json: { email: ' PETYA@example.com', password: 'secret1' } });
  assert.equal(relogin.status, 200);
  assert.equal(relogin.body.user.id, petya.user.id);
  assert.equal((await api('GET', '/api/me')).status, 401);

  for (const [who, ch] of [[masha, 'a'], [petya, 'b'], [olya, 'c']]) {
    assert.equal((await api('POST', '/api/devices', { auth: who.token, json: { token: token(ch), env: 'sandbox' } })).status, 200);
  }
  assert.equal((await api('POST', '/api/devices', { auth: masha.token, json: { token: 'not-a-token' } })).status, 400);

  // --- circle ---
  assert.equal((await api('GET', '/api/photos', { auth: masha.token })).status, 409);
  const created = await api('POST', '/api/circles', { auth: masha.token, json: { name: 'Банда' } });
  assert.equal(created.status, 200);
  const code = created.body.circle.inviteCode;
  assert.match(code, /^[A-Z2-9]{6}$/);
  assert.equal((await api('POST', '/api/circles/join', { auth: petya.token, json: { code: 'NOPE00' } })).status, 404);
  const joined = await api('POST', '/api/circles/join', { auth: petya.token, json: { code: ` ${code.toLowerCase().slice(0, 3)} ${code.slice(3)} ` } });
  assert.equal(joined.status, 200);
  assert.equal(joined.body.circle.name, 'Банда');
  assert.equal(lastPushTo(token('a')).aps.alert.body, 'Петя теперь с вами');
  await api('POST', '/api/circles/join', { auth: olya.token, json: { code } });
  assert.deepEqual((await api('GET', '/api/me', { auth: olya.token })).body.members.map((m) => m.name), ['Маша', 'Петя', 'Оля']);
  assert.equal((await api('POST', '/api/circles', { auth: olya.token, json: { name: 'Вторая' } })).status, 409);

  // --- photos ---
  assert.equal((await api('POST', '/api/photos', { auth: masha.token, raw: Buffer.from('GIF89a') })).status, 400);
  const up = await api('POST', `/api/photos?caption=${encodeURIComponent('  На   море 🌊 ')}`, { auth: masha.token, raw: JPEG });
  assert.equal(up.status, 200);
  const m1 = up.body.photo;
  assert.equal(m1.caption, 'На море 🌊');
  assert.equal(m1.canReact, false);
  assert.match(m1.imageUrl, /^https:\/\/locket\.test\/media\/[a-f0-9]{32}\.jpg$/);

  const notif = lastPushTo(token('b'));
  assert.equal(notif.aps.category, 'PHOTO_RATING');
  assert.equal(notif.aps['mutable-content'], 1);
  assert.equal(notif.aps.alert.title, 'Маша');
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
  assert.equal(firstReactionPush.payload.aps.alert.body, '3\u00a0звезды — твоему фото');

  res = await rate(petya, m1.id, 'creative');
  assert.deepEqual(res.body.photo.counts, { creative: 1, funny: 0, wild: 0 });
  assert.deepEqual(res.body.photo.mine, ['creative']);
  assert.equal(lastPushTo(token('a')).aps.alert.body, '3\u00a0звезды · ✍️ — твоему фото');
  assert.equal(sent.at(-1).opts.collapseId, firstReactionPush.opts.collapseId, 'replaces the earlier notification');

  const before = sent.length;
  await starIt(petya, m1.id, 3);
  await rate(petya, m1.id, 'creative');
  assert.equal(sent.length, before, 'repeating a rating sends nothing');

  await starIt(petya, m1.id, 2);
  assert.equal(lastPushTo(token('a')).aps.alert.body, '2\u00a0звезды · ✍️ — твоему фото');
  res = await rate(petya, m1.id, 'creative', 'DELETE');
  assert.deepEqual(res.body.photo.counts, { creative: 0, funny: 0, wild: 0 });
  await rate(petya, m1.id, 'funny');
  assert.equal(lastPushTo(token('a')).aps.alert.body, '2\u00a0звезды · 😂 — твоему фото');
  await starIt(olya, m1.id, 1);
  await rate(olya, m1.id, 'funny');

  assert.equal((await starIt(masha, m1.id, 3)).status, 403);
  assert.equal((await rate(masha, m1.id, 'funny')).status, 403);
  assert.equal((await starIt(olya, m1.id, 4)).status, 400);
  assert.equal((await starIt(olya, m1.id, 0)).status, 400);
  assert.equal((await rate(olya, m1.id, 'fire')).status, 400);
  assert.equal((await rate(olya, 'missing', 'funny')).status, 404);

  clock += 3_600_000;
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
  clock += 3_600_000;
  const o1 = (await api('POST', '/api/photos?caption=кот', { auth: olya.token, raw: JPEG })).body.photo;

  const feed = (await api('GET', '/api/photos', { auth: masha.token })).body.photos;
  assert.deepEqual(feed.map((p) => p.id), [o1.id, p1.id, m1.id]);
  assert.deepEqual(feed[1].mine, ['creative']);
  assert.equal(feed[1].myStars, 2);
  assert.deepEqual(feed[1].stars, { count: 2, total: 5, average: 2.5 });
  assert.deepEqual(feed[2].counts, { creative: 0, funny: 2, wild: 0 });
  assert.deepEqual(feed[2].stars, { count: 2, total: 3, average: 1.5 });
  assert.deepEqual(feed[2].reactors.map((r) => `${r.name}:${r.kind}`), ['Петя:funny', 'Оля:funny']);
  assert.deepEqual(feed[2].raters.map((r) => `${r.name}:${r.stars}`), ['Петя:2', 'Оля:1']);
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
  assert.deepEqual(live.leaderboard.map((s) => [s.name, s.points]), [['Петя', 11], ['Маша', 9], ['Оля', 6]]);

  // --- Sunday 18:30 MSK: reminder to those with unrated photos ---
  clock = Date.UTC(2026, 9, 18, 15, 30);
  sent.length = 0;
  await app.runDue();
  assert.deepEqual(sent.map((s) => s.token).sort(), [token('a'), token('b')]);
  assert.equal(sent[0].payload.aps.alert.body, '1\u00a0фото ждёт твоей оценки — успей до итогов');
  assert.equal(sent[0].payload.aps.alert.title, 'До итогов недели 3\u00a0ч');
  await app.runDue();
  assert.equal(sent.length, 2, 'reminder is sent once');

  // --- Sunday 21:00 MSK: the week closes ---
  clock = Date.UTC(2026, 9, 18, 18, 0, 30);
  sent.length = 0;
  await app.runDue();
  assert.equal(sent.length, 3);
  const weekly = lastPushTo(token('c'));
  assert.equal(weekly.aps.alert.title, 'Итоги недели');
  assert.equal(weekly.aps.alert.body, 'Друг недели — Петя\nФото недели — Петя\n✍️ Петя · 😂 Маша · 🫪 Петя · самый активный — Оля');
  assert.equal(weekly.aps.category, 'WEEKLY_RESULTS');
  assert.equal(weekly.weekId, '2026-W42');
  assert.equal(weekly.imageUrl, p1.imageUrl);
  await app.runDue();
  assert.equal(sent.length, 3, 'results are announced once');

  const weeks = (await api('GET', '/api/weeks', { auth: petya.token })).body.weeks;
  assert.equal(weeks.length, 1);
  assert.equal(weeks[0].weekId, '2026-W42');
  assert.equal(weeks[0].closedAt, clock);
  assert.equal(weeks[0].bestPhoto.photoId, p1.id);
  assert.deepEqual([weeks[0].bestPhoto.stars, weeks[0].bestPhoto.starCount], [5, 2]);
  assert.equal(weeks[0].friendOfWeek.name, 'Петя');
  assert.equal(weeks[0].mostFunny.name, 'Маша');
  assert.equal(weeks[0].mostCreative.name, 'Петя');
  assert.equal(weeks[0].mostWild.name, 'Петя');
  assert.equal(weeks[0].mostActive.name, 'Оля');
  assert.deepEqual((await api('GET', '/api/weeks/2026-W42', { auth: petya.token })).body, weeks[0]);

  // Voting for the closed week is over, the new week starts empty.
  assert.equal((await rate(masha, o1.id, 'funny')).status, 409);
  assert.equal((await starIt(masha, o1.id, 3)).status, 409);
  const fresh = await api('GET', '/api/photos', { auth: masha.token });
  assert.equal(fresh.body.photos[0].canReact, false);
  const w43 = (await api('POST', '/api/photos', { auth: olya.token, raw: JPEG })).body.photo;
  assert.equal(w43.weekId, '2026-W43');
  assert.equal((await api('GET', '/api/week/current', { auth: olya.token })).body.photoCount, 1);

  // --- dead device tokens are dropped ---
  deadTokens.add(token('c'));
  await api('POST', '/api/photos', { auth: masha.token, raw: JPEG });
  assert.equal(app.store.devicesForUsers([olya.user.id]).length, 0);

  // --- deleting, leaving, logging out ---
  assert.equal((await api('DELETE', `/api/photos/${w43.id}`, { auth: masha.token })).status, 403);
  assert.equal((await api('DELETE', `/api/photos/${w43.id}`, { auth: olya.token })).status, 200);
  assert.equal((await api('GET', `/api/photos/${w43.id}`, { auth: olya.token })).status, 404);
  assert.equal((await api('GET', new URL(w43.imageUrl).pathname)).status, 404);

  const left = await api('POST', '/api/circles/leave', { auth: olya.token });
  assert.equal(left.body.circle, null);
  assert.equal((await api('GET', '/api/widget', { auth: olya.token })).body.photo, null);
  assert.equal((await api('GET', `/api/photos/${m1.id}`, { auth: olya.token })).status, 404);

  assert.equal((await api('POST', '/api/auth/logout', { auth: petya.token, json: { deviceToken: token('b') } })).status, 200);
  assert.equal((await api('GET', '/api/me', { auth: petya.token })).status, 401);
  assert.equal(app.store.devicesForUsers([petya.user.id]).length, 0);
  assert.equal((await api('GET', '/api/me', { auth: relogin.body.token })).status, 200, 'other sessions stay');
});

test('oversized uploads are rejected cleanly', async () => {
  const user = (await api('POST', '/api/auth/register', { json: { name: 'Big', email: 'big@example.com', password: 'secret1' } })).body;
  await api('POST', '/api/circles', { auth: user.token, json: { name: 'Big' } });
  const huge = Buffer.alloc(9 * 1024 * 1024, 0xff);
  const res = await api('POST', '/api/photos', { auth: user.token, raw: huge });
  assert.equal(res.status, 413);
});
