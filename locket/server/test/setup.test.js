import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { test } from 'node:test';
import { loadConfig } from '../src/config.js';
import { openDb } from '../src/db.js';
import { reminderMessage } from '../src/push.js';

const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'locket-setup-'));
const quiet = { warn() {} };

test('a version 1 database (companies + email) is moved aside, not deleted', () => {
  const dir = tmp();
  const file = path.join(dir, 'locket.db');
  const old = new DatabaseSync(file);
  old.exec("CREATE TABLE circles (id TEXT PRIMARY KEY); CREATE TABLE users (id TEXT PRIMARY KEY, email TEXT); INSERT INTO circles VALUES ('c1');");
  old.close();

  const db = openDb(file, { log: quiet, stamp: () => 'T1' });
  const backup = path.join(dir, 'locket.v1-T1.db');
  assert.ok(fs.existsSync(backup));
  const kept = new DatabaseSync(backup);
  assert.equal(kept.prepare('SELECT id FROM circles').get().id, 'c1');
  kept.close();
  assert.equal(db.prepare('PRAGMA user_version').get().user_version, 3);
  const columns = db.prepare('PRAGMA table_info(users)').all().map((c) => c.name);
  assert.ok(columns.includes('password_key') && columns.includes('username_key') && !columns.includes('email'));
  db.prepare("INSERT INTO users (id, password_key, created_at) VALUES ('u1', 'k1', 0)").run();
  db.close();

  // A version 2 file is opened as it is.
  const again = openDb(file, { log: quiet, stamp: () => 'T2' });
  assert.equal(again.prepare('SELECT COUNT(*) AS n FROM users').get().n, 1);
  assert.ok(!fs.existsSync(path.join(dir, 'locket.v1-T2.db')));
  again.close();

  // A version 2 file (before wishlists) keeps its data and gains the wishes table.
  const v2file = path.join(dir, 'v2.db');
  const v2 = new DatabaseSync(v2file);
  v2.exec("CREATE TABLE users (id TEXT PRIMARY KEY, username TEXT, username_key TEXT UNIQUE, password_key TEXT NOT NULL UNIQUE, created_at INTEGER NOT NULL); INSERT INTO users VALUES ('u2', 'барсук', 'барсук', 'k2', 0); PRAGMA user_version = 2;");
  v2.close();
  const upgraded = openDb(v2file, { log: quiet, stamp: () => 'T3' });
  assert.equal(upgraded.prepare('SELECT username FROM users').get().username, 'барсук');
  assert.equal(upgraded.prepare('SELECT COUNT(*) AS n FROM wishes').get().n, 0);
  assert.equal(upgraded.prepare('PRAGMA user_version').get().user_version, 3);
  assert.ok(!fs.existsSync(path.join(dir, 'locket.v1-T3.db')));
  upgraded.close();
});

test('the password pepper is created once in the data folder, or taken from the environment', () => {
  const dir = tmp();
  const first = loadConfig({ DATA_DIR: dir });
  assert.match(first.passwordPepper, /^[0-9a-f]{64}$/);
  assert.equal(fs.statSync(path.join(dir, 'pepper')).mode & 0o777, 0o600);
  assert.equal(loadConfig({ DATA_DIR: dir }).passwordPepper, first.passwordPepper, 'reused, never regenerated');
  assert.equal(loadConfig({ DATA_DIR: dir, PASSWORD_PEPPER: 'from-env' }).passwordPepper, 'from-env');

  assert.equal(first.trustProxy, false);
  assert.equal(loadConfig({ DATA_DIR: dir, TRUST_PROXY: '1' }).trustProxy, true);
  assert.equal(first.maxFriends, 100);
  assert.equal(loadConfig({ DATA_DIR: dir, MAX_FRIENDS: '5' }).maxFriends, 5);

  fs.writeFileSync(path.join(dir, 'pepper'), '');
  assert.throws(() => loadConfig({ DATA_DIR: dir }), /empty/);
});

test('reminder copy: unrated, locked, both', () => {
  const body = (o) => reminderMessage({ hours: 3, ...o }).aps.alert.body;
  assert.equal(body({ unrated: 1, locked: 0 }), '1 фото ждёт твоей оценки — успей до итогов');
  assert.equal(body({ unrated: 2, locked: 1 }), '2 фото ждут твоей оценки — успей до итогов · ещё 1 закрыто — выложи своё');
  assert.equal(body({ unrated: 0, locked: 3 }), '3 фото друзей закрыты — выложи своё, чтобы открыть');
  assert.equal(body({ unrated: 0, locked: 1 }), '1 фото друзей закрыто — выложи своё, чтобы открыть');
  assert.equal(reminderMessage({ unrated: 1, hours: 3 }).aps.alert.title, 'До итогов недели 3 ч');
});
