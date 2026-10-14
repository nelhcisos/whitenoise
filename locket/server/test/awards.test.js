import assert from 'node:assert/strict';
import { test } from 'node:test';
import { computeStandings } from '../src/awards.js';

const members = [
  { id: 'masha', name: 'Маша' },
  { id: 'petya', name: 'Петя' },
  { id: 'olya', name: 'Оля' },
];
const photo = (id, authorId, createdAt = 0) => ({ id, authorId, createdAt, file: `${id}.jpg`, caption: null });
const r = (photoId, userId, kind) => ({ photoId, userId, kind });

test('picks photo of the week, friend of the week and nominations', () => {
  const s = computeStandings({
    members,
    photos: [photo('p1', 'masha', 1), photo('p2', 'petya', 2), photo('p3', 'petya', 3)],
    reactions: [
      r('p1', 'petya', 'fire'),
      r('p1', 'olya', 'fire'),
      r('p1', 'olya', 'creative'),
      r('p2', 'masha', 'funny'),
      r('p2', 'olya', 'funny'),
      r('p3', 'masha', 'funny'),
      r('p3', 'olya', 'creative'),
    ],
  });

  assert.equal(s.bestPhoto.id, 'p1');
  assert.equal(s.bestPhoto.score, 5); // 2×🔥 + 🎨
  assert.equal(s.bestPhoto.authorName, 'Маша');

  const by = Object.fromEntries(s.leaderboard.map((x) => [x.userId, x]));
  // Маша: received 2🔥 1🎨 = 5, posted 1 = 2, gave 2 = 2 → 9
  assert.deepEqual([by.masha.points, by.masha.activity, by.masha.given], [9, 4, 2]);
  // Петя: received 3😂 1🎨 = 4, posted 2 = 4, gave 1 = 1 → 9
  assert.deepEqual([by.petya.points, by.petya.activity], [9, 5]);
  // Оля: posted nothing, gave 4 → 4
  assert.equal(by.olya.points, 4);

  // Tie on points goes to more 🔥.
  assert.equal(s.friendOfWeek.userId, 'masha');
  assert.equal(s.mostFunny.userId, 'petya');
  assert.equal(s.mostFunny.value, 3);
  assert.equal(s.mostActive.userId, 'petya');
  // 🎨 tie (1 each) goes to whoever leads the leaderboard.
  assert.equal(s.mostCreative.userId, 'masha');
});

test('self-reactions and unknown kinds are ignored', () => {
  const s = computeStandings({
    members,
    photos: [photo('p1', 'masha')],
    reactions: [r('p1', 'masha', 'fire'), r('p1', 'petya', 'love')],
  });
  assert.equal(s.bestPhoto, null);
  assert.equal(s.leaderboard.find((x) => x.userId === 'masha').fire, 0);
  assert.equal(s.leaderboard.find((x) => x.userId === 'petya').given, 0);
});

test('empty week has no winners except activity', () => {
  const s = computeStandings({ members, photos: [photo('p1', 'olya')], reactions: [] });
  assert.equal(s.bestPhoto, null);
  assert.equal(s.mostCreative, null);
  assert.equal(s.mostFunny, null);
  assert.equal(s.mostActive.userId, 'olya');
  assert.equal(s.friendOfWeek.userId, 'olya');
});

test('posting is capped so spam does not win', () => {
  const photos = Array.from({ length: 40 }, (_, i) => photo(`s${i}`, 'petya', i));
  const s = computeStandings({ members, photos, reactions: [] });
  assert.equal(s.leaderboard.find((x) => x.userId === 'petya').activity, 28);
});

test('photo ties: more 🔥 first, then the earlier one', () => {
  const s = computeStandings({
    members,
    photos: [photo('a', 'masha', 1), photo('b', 'petya', 2), photo('c', 'olya', 0)],
    reactions: [
      r('a', 'petya', 'creative'),
      r('a', 'olya', 'funny'),
      r('b', 'masha', 'fire'),
      r('c', 'masha', 'fire'),
    ],
  });
  assert.equal(s.bestPhoto.id, 'c');
});

test('photos of people who left the circle cannot win', () => {
  const s = computeStandings({
    members: members.slice(0, 2),
    photos: [photo('x', 'gone'), photo('y', 'masha')],
    reactions: [r('x', 'petya', 'fire'), r('x', 'masha', 'fire'), r('y', 'petya', 'funny')],
  });
  assert.equal(s.bestPhoto.id, 'y');
  assert.equal(s.leaderboard.length, 2);
});
