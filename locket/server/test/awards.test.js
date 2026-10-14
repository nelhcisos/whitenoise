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
const star = (photoId, userId, value) => ({ photoId, userId, value });

test('picks photo of the week, friend of the week and nominations', () => {
  const s = computeStandings({
    members,
    photos: [photo('p1', 'masha', 1), photo('p2', 'petya', 2), photo('p3', 'petya', 3)],
    stars: [star('p1', 'petya', 3), star('p1', 'olya', 2), star('p2', 'masha', 1), star('p2', 'olya', 2), star('p3', 'masha', 2)],
    reactions: [
      r('p1', 'olya', 'creative'),
      r('p2', 'masha', 'funny'),
      r('p2', 'olya', 'funny'),
      r('p3', 'masha', 'wild'),
      r('p3', 'olya', 'creative'),
    ],
  });

  assert.equal(s.bestPhoto.id, 'p1');
  assert.equal(s.bestPhoto.stars, 5);
  assert.equal(s.bestPhoto.starCount, 2);
  assert.equal(s.bestPhoto.authorName, 'Маша');

  const by = Object.fromEntries(s.leaderboard.map((x) => [x.userId, x]));
  // Маша: 5⭐ + 1✍️ = 6, posted 1 = 2, rated 2 photos with stars + 2 reactions = 4 → 12
  assert.deepEqual([by.masha.points, by.masha.activity, by.masha.given, by.masha.stars], [12, 6, 4, 5]);
  // Петя: 5⭐ + 2😂 + 1🫪 + 1✍️ = 9, posted 2 = 4, gave 1 = 1 → 14
  assert.deepEqual([by.petya.points, by.petya.activity, by.petya.stars], [14, 5, 5]);
  // Оля: posted nothing, gave 2 ratings + 3 reactions → 5
  assert.equal(by.olya.points, 5);
  assert.deepEqual(s.leaderboard.map((x) => x.userId), ['petya', 'masha', 'olya']);

  assert.equal(s.friendOfWeek.userId, 'petya');
  assert.equal(s.mostFunny.userId, 'petya');
  assert.equal(s.mostFunny.value, 2);
  assert.equal(s.mostWild.userId, 'petya');
  assert.equal(s.mostActive.userId, 'masha');
  // ✍️ tie (1 each) goes to whoever leads the leaderboard.
  assert.equal(s.mostCreative.userId, 'petya');
});

test('self-ratings, bad star values and unknown kinds are ignored', () => {
  const s = computeStandings({
    members,
    photos: [photo('p1', 'masha')],
    stars: [star('p1', 'masha', 3), star('p1', 'petya', 5), star('p1', 'olya', 0)],
    reactions: [r('p1', 'masha', 'funny'), r('p1', 'petya', 'fire')],
  });
  assert.equal(s.bestPhoto, null);
  assert.equal(s.leaderboard.find((x) => x.userId === 'masha').points, 2); // just the post
  assert.equal(s.leaderboard.find((x) => x.userId === 'petya').given, 0);
});

test('reactions alone do not make the photo of the week', () => {
  const s = computeStandings({ members, photos: [photo('p1', 'olya')], stars: [], reactions: [r('p1', 'masha', 'funny')] });
  assert.equal(s.bestPhoto, null);
  assert.equal(s.mostFunny.userId, 'olya');
});

test('empty week has no winners except activity', () => {
  const s = computeStandings({ members, photos: [photo('p1', 'olya')], reactions: [] });
  assert.equal(s.bestPhoto, null);
  assert.equal(s.mostCreative, null);
  assert.equal(s.mostFunny, null);
  assert.equal(s.mostWild, null);
  assert.equal(s.mostActive.userId, 'olya');
  assert.equal(s.friendOfWeek.userId, 'olya');
});

test('posting is capped so spam does not win', () => {
  const photos = Array.from({ length: 40 }, (_, i) => photo(`s${i}`, 'petya', i));
  const s = computeStandings({ members, photos, reactions: [] });
  assert.equal(s.leaderboard.find((x) => x.userId === 'petya').activity, 28);
});

test('photo ties: more reactions first, then the earlier one', () => {
  const s = computeStandings({
    members,
    photos: [photo('a', 'masha', 1), photo('b', 'petya', 2), photo('c', 'olya', 0)],
    stars: [star('a', 'petya', 3), star('b', 'masha', 3), star('c', 'masha', 3)],
    reactions: [r('b', 'olya', 'funny'), r('c', 'petya', 'wild')],
  });
  assert.equal(s.bestPhoto.id, 'c');
});

test('photos of people who left the circle cannot win', () => {
  const s = computeStandings({
    members: members.slice(0, 2),
    photos: [photo('x', 'gone'), photo('y', 'masha')],
    stars: [star('x', 'petya', 3), star('x', 'masha', 3), star('y', 'petya', 1)],
    reactions: [],
  });
  assert.equal(s.bestPhoto.id, 'y');
  assert.equal(s.leaderboard.length, 2);
});
