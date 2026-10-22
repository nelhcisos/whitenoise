import assert from 'node:assert/strict';
import { test } from 'node:test';
import { USERNAME_KINDS, USERNAME_WORDS, canonicalUsername, suggestUsername, suggestUsernames, usernameKey } from '../src/usernames.js';

test('word lists: lowercase Cyrillic words, no duplicates across kinds', () => {
  assert.deepEqual(USERNAME_KINDS, ['animal', 'swear', 'name']);
  const all = USERNAME_KINDS.flatMap((kind) => USERNAME_WORDS[kind]);
  for (const word of all) assert.match(word, /^[а-яё]+$/u, word);
  assert.equal(new Set(all.map(usernameKey)).size, all.length);
});

test('only usernames the generator could offer are accepted, in their list spelling', () => {
  assert.equal(canonicalUsername('барсук'), 'барсук');
  assert.equal(canonicalUsername('  Барсук12 '), 'барсук12');
  assert.equal(canonicalUsername('ежик'), 'ёжик', '«е» typed for «ё» gets the list spelling');
  assert.equal(canonicalUsername('долбоеб999'), 'долбоёб999');
  for (const bad of ['', 'кот', 'барсук1', 'барсук01', 'барсук1000', 'барсук 2', 'барсукбарсук', 'barsuk', null, 42]) {
    assert.equal(canonicalUsername(bad), null, String(bad));
  }
});

test('suggestions: one free username of each kind, all different', () => {
  const taken = new Set(['барсук', 'ярослава']);
  for (let i = 0; i < 50; i++) {
    const s = suggestUsernames((key) => taken.has(key));
    assert.deepEqual(s.map((x) => x.kind), ['animal', 'swear', 'name']);
    for (const { username } of s) {
      assert.ok(!taken.has(usernameKey(username)));
      assert.notEqual(canonicalUsername(username), null, `${username} must pass the grammar`);
    }
    assert.equal(new Set(s.map((x) => usernameKey(x.username))).size, 3);
  }
});

test('when every bare word is taken, a number is added', () => {
  const bare = new Set(USERNAME_WORDS.animal.map(usernameKey));
  for (let i = 0; i < 20; i++) {
    const name = suggestUsername('animal', (key) => bare.has(key));
    assert.match(name, /\d+$/);
    assert.notEqual(canonicalUsername(name), null);
  }
  assert.throws(() => suggestUsername('animal', () => true), /no free username/);
});
