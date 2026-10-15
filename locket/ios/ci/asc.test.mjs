// node --test ci/  — checks the signing script against a fake App Store Connect API.
import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { UserFacingError, cleanup, createClient, prepare } from './asc.mjs';

const { privateKey, publicKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' });
const keyPem = privateKey.export({ type: 'pkcs8', format: 'pem' });

function fakeAppStoreConnect() {
  const db = { bundleIds: [], capabilities: [], apps: [], certificates: [], profiles: [] };
  const calls = [];
  let nextId = 1;
  const id = () => `ID${nextId++}`;

  const server = http.createServer(async (req, res) => {
    let raw = '';
    for await (const chunk of req) raw += chunk;
    const body = raw ? JSON.parse(raw) : null;
    const url = new URL(req.url, 'http://x');
    calls.push(`${req.method} ${url.pathname}`);
    const send = (status, json) => {
      res.writeHead(status, { 'content-type': 'application/json' });
      res.end(json === undefined ? '' : JSON.stringify(json));
    };

    // Every request must carry a valid ES256 token for our key.
    const [head, claims, sig] = (req.headers.authorization || '').replace('Bearer ', '').split('.');
    const valid = crypto.verify('sha256', Buffer.from(`${head}.${claims}`), { key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(sig || '', 'base64url'));
    const payload = valid && JSON.parse(Buffer.from(claims, 'base64url'));
    if (!valid || payload.aud !== 'appstoreconnect-v1' || payload.iss !== 'issuer-1') return send(401, { errors: [{ detail: 'bad token' }] });

    const p = url.pathname;
    if (req.method === 'GET' && p === '/v1/bundleIds') {
      const prefix = url.searchParams.get('filter[identifier]');
      return send(200, { data: db.bundleIds.filter((b) => b.attributes.identifier.startsWith(prefix)) });
    }
    if (req.method === 'POST' && p === '/v1/bundleIds') {
      const b = { id: id(), type: 'bundleIds', attributes: body.data.attributes };
      db.bundleIds.push(b);
      return send(201, { data: b });
    }
    let m;
    if (req.method === 'GET' && (m = p.match(/^\/v1\/bundleIds\/(\w+)\/bundleIdCapabilities$/))) {
      return send(200, { data: db.capabilities.filter((c) => c.bundleId === m[1]) });
    }
    if (req.method === 'POST' && p === '/v1/bundleIdCapabilities') {
      const c = { id: id(), bundleId: body.data.relationships.bundleId.data.id, attributes: body.data.attributes };
      db.capabilities.push(c);
      return send(201, { data: c });
    }
    if (req.method === 'GET' && p === '/v1/apps') {
      return send(200, { data: db.apps.filter((a) => a.bundleId === url.searchParams.get('filter[bundleId]')) });
    }
    if (req.method === 'POST' && p === '/v1/certificates') {
      assert.equal(body.data.attributes.certificateType, 'DISTRIBUTION');
      assert.match(body.data.attributes.csrContent, /BEGIN CERTIFICATE REQUEST/);
      const c = { id: id(), attributes: { certificateContent: Buffer.from('DER').toString('base64') } };
      db.certificates.push(c);
      return send(201, { data: c });
    }
    if (req.method === 'POST' && p === '/v1/profiles') {
      const a = body.data.attributes;
      assert.equal(a.profileType, 'IOS_APP_STORE');
      const pr = {
        id: id(),
        attributes: { ...a, uuid: crypto.randomUUID(), profileContent: Buffer.from(`profile ${a.name}`).toString('base64') },
        bundleId: body.data.relationships.bundleId.data.id,
      };
      db.profiles.push(pr);
      return send(201, { data: pr });
    }
    if (req.method === 'DELETE' && (m = p.match(/^\/v1\/(profiles|certificates)\/(\w+)$/))) {
      db[m[1]] = db[m[1]].filter((x) => x.id !== m[2]);
      return send(204);
    }
    send(404, { errors: [{ detail: `no route ${req.method} ${p}` }] });
  });

  return { server, db, calls };
}

test('prepare registers everything, signs for TestFlight, cleanup revokes', async () => {
  const fake = fakeAppStoreConnect();
  await new Promise((r) => fake.server.listen(0, '127.0.0.1', r));
  const api = createClient({ keyId: 'KEY1', issuerId: 'issuer-1', keyPem, baseUrl: `http://127.0.0.1:${fake.server.address().port}` });
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'asc-'));
  const options = {
    api,
    bundleId: 'com.masha.locket',
    teamId: 'TEAM123456',
    csrPem: '-----BEGIN CERTIFICATE REQUEST-----\nMIIB\n-----END CERTIFICATE REQUEST-----\n',
    runNumber: '7',
    profileDirs: [path.join(dir, 'a'), path.join(dir, 'b')],
  };

  try {
    // First run: no app record yet. Bundle IDs get registered so the app can be created.
    await assert.rejects(prepare(options), (err) => err instanceof UserFacingError && /Новое приложение/.test(err.message));
    assert.deepEqual(
      fake.db.bundleIds.map((b) => b.attributes.identifier),
      ['com.masha.locket', 'com.masha.locket.NotificationService', 'com.masha.locket.NotificationContent', 'com.masha.locket.widget'],
    );
    assert.deepEqual(fake.db.capabilities.map((c) => c.attributes.capabilityType), ['PUSH_NOTIFICATIONS']);
    assert.equal(fake.db.certificates.length, 0, 'no certificate is created before the app exists');

    // Second run, after the app was created in App Store Connect.
    fake.db.apps.push({ id: 'APP1', bundleId: 'com.masha.locket' });
    const result = await prepare(options);
    assert.equal(fake.db.bundleIds.length, 4, 'existing bundle IDs are reused');
    assert.equal(fake.db.capabilities.length, 1, 'push is not enabled twice');
    assert.equal(fake.db.certificates.length, 1);
    assert.equal(fake.db.profiles.length, 4);
    assert.deepEqual(result.certificateDer, Buffer.from('DER'));
    assert.deepEqual(
      Object.fromEntries(Object.values(result.profiles).map((p) => [p.env, p.name])),
      {
        LOCKET_PROFILE_APP: 'Locket CI 7 app',
        LOCKET_PROFILE_NOTIFICATION_SERVICE: 'Locket CI 7.NotificationService',
        LOCKET_PROFILE_NOTIFICATION_CONTENT: 'Locket CI 7.NotificationContent',
        LOCKET_PROFILE_WIDGET: 'Locket CI 7.widget',
      },
    );
    for (const sub of ['a', 'b']) assert.equal(fs.readdirSync(path.join(dir, sub)).length, 4);
    assert.match(result.exportOptions, /<key>com\.masha\.locket\.widget<\/key>\s*<string>Locket CI 7\.widget<\/string>/);
    assert.match(result.exportOptions, /<string>app-store-connect<\/string>/);
    assert.match(result.exportOptions, /<string>TEAM123456<\/string>/);

    await cleanup({ api, state: result.state });
    assert.equal(fake.db.certificates.length, 0, 'the temporary certificate is revoked');
    assert.equal(fake.db.profiles.length, 0);
  } finally {
    fake.server.close();
  }
});

test('the command line flow the workflow runs', async () => {
  const fake = fakeAppStoreConnect();
  fake.db.apps.push({ id: 'APP1', bundleId: 'com.masha.locket' });
  await new Promise((r) => fake.server.listen(0, '127.0.0.1', r));
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'asc-cli-'));
  fs.writeFileSync(path.join(dir, 'AuthKey.p8'), keyPem);
  execFileSync('openssl', ['req', '-new', '-newkey', 'rsa:2048', '-nodes', '-keyout', path.join(dir, 'dist.key'),
    '-out', path.join(dir, 'dist.csr'), '-subj', '/CN=Locket CI/O=Locket'], { stdio: 'ignore' });
  const githubEnv = path.join(dir, 'github-env');
  fs.writeFileSync(githubEnv, '');
  const env = {
    ...process.env,
    HOME: dir,
    SIGNING_DIR: dir,
    ASC_API: `http://127.0.0.1:${fake.server.address().port}`,
    ASC_KEY_ID: 'KEY1',
    ASC_ISSUER_ID: 'issuer-1',
    LOCKET_BUNDLE_ID: 'com.masha.locket',
    LOCKET_TEAM_ID: 'TEAM123456',
    GITHUB_RUN_NUMBER: '12',
    GITHUB_ENV: githubEnv,
  };
  const script = new URL('./asc.mjs', import.meta.url).pathname;
  // Async child process: a synchronous one would block the fake server in this process.
  const run = (command) =>
    new Promise((resolve) => {
      const child = spawn(process.execPath, [script, command], { env });
      let out = '';
      child.stdout.on('data', (d) => (out += d));
      child.stderr.on('data', (d) => (out += d));
      child.on('close', (code) => resolve({ code, out }));
    });
  try {
    const prepared = await run('prepare');
    assert.equal(prepared.code, 0, prepared.out);
    assert.match(fs.readFileSync(githubEnv, 'utf8'), /^LOCKET_PROFILE_WIDGET=Locket CI 12\.widget$/m);
    assert.ok(fs.existsSync(path.join(dir, 'dist.cer')));
    assert.ok(fs.existsSync(path.join(dir, 'ExportOptions.plist')));
    assert.equal(fs.readdirSync(path.join(dir, 'Library/Developer/Xcode/UserData/Provisioning Profiles')).length, 4);

    const cleaned = await run('cleanup');
    assert.equal(cleaned.code, 0, cleaned.out);
    assert.equal(fake.db.certificates.length, 0);
    assert.equal(fake.db.profiles.length, 0);
  } finally {
    fake.server.close();
  }
});
