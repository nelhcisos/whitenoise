// Signing for TestFlight without a Mac, driven by an App Store Connect API key.
//
//   node asc.mjs prepare   bundle IDs (+ push capability), a fresh Apple Distribution
//                          certificate from dist.csr, App Store profiles, ExportOptions.plist
//   node asc.mjs cleanup   revokes that certificate and deletes the profiles again
//
// A new certificate per run means nothing secret has to be stored between runs,
// and revoking it afterwards keeps the team under Apple's certificate limit.
// Builds already uploaded to TestFlight are not affected by the revocation.
//
// Environment: ASC_KEY_ID, ASC_ISSUER_ID, LOCKET_BUNDLE_ID, LOCKET_TEAM_ID, SIGNING_DIR
// (holds AuthKey.p8 and dist.csr), optional ASC_API (for tests), GITHUB_ENV, GITHUB_RUN_NUMBER.
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export const TARGETS = [
  { env: 'LOCKET_PROFILE_APP', suffix: '', name: 'Locket', push: true },
  { env: 'LOCKET_PROFILE_NOTIFICATION_SERVICE', suffix: '.NotificationService', name: 'Locket Notification Service' },
  { env: 'LOCKET_PROFILE_NOTIFICATION_CONTENT', suffix: '.NotificationContent', name: 'Locket Notification Content' },
  { env: 'LOCKET_PROFILE_WIDGET', suffix: '.widget', name: 'Locket Widget' },
];

export class UserFacingError extends Error {}

export function createClient({ keyId, issuerId, keyPem, baseUrl = 'https://api.appstoreconnect.apple.com' }) {
  let token = null;
  let tokenExpires = 0;

  function jwt() {
    const now = Math.floor(Date.now() / 1000);
    if (!token || now > tokenExpires - 60) {
      const enc = (obj) => Buffer.from(JSON.stringify(obj)).toString('base64url');
      const head = enc({ alg: 'ES256', kid: keyId, typ: 'JWT' });
      const body = enc({ iss: issuerId, iat: now, exp: now + 15 * 60, aud: 'appstoreconnect-v1' });
      const sig = crypto.sign('sha256', Buffer.from(`${head}.${body}`), { key: keyPem, dsaEncoding: 'ieee-p1363' });
      token = `${head}.${body}.${sig.toString('base64url')}`;
      tokenExpires = now + 15 * 60;
    }
    return token;
  }

  async function call(method, urlPath, body) {
    const res = await fetch(baseUrl + urlPath, {
      method,
      headers: { authorization: `Bearer ${jwt()}`, 'content-type': 'application/json' },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (res.status === 204) return null;
    const text = await res.text();
    const json = text ? JSON.parse(text) : null;
    if (!res.ok) {
      const detail = json?.errors?.map((e) => e.detail || e.title).join('; ') || text;
      const err = new Error(`${method} ${urlPath} → ${res.status}: ${detail}`);
      err.status = res.status;
      throw err;
    }
    return json;
  }

  return { call };
}

async function findBundleId(api, identifier) {
  const res = await api.call('GET', `/v1/bundleIds?filter[identifier]=${encodeURIComponent(identifier)}&limit=200`);
  return res.data.find((b) => b.attributes.identifier === identifier) ?? null;
}

async function ensureBundleId(api, identifier, name) {
  const existing = await findBundleId(api, identifier);
  if (existing) return existing;
  console.log(`Регистрирую Bundle ID ${identifier}`);
  const res = await api.call('POST', '/v1/bundleIds', {
    data: { type: 'bundleIds', attributes: { identifier, name, platform: 'IOS' } },
  });
  return res.data;
}

async function ensurePush(api, bundle) {
  const caps = await api.call('GET', `/v1/bundleIds/${bundle.id}/bundleIdCapabilities`);
  if (caps.data.some((c) => c.attributes.capabilityType === 'PUSH_NOTIFICATIONS')) return;
  console.log(`Включаю Push Notifications для ${bundle.attributes.identifier}`);
  await api.call('POST', '/v1/bundleIdCapabilities', {
    data: {
      type: 'bundleIdCapabilities',
      attributes: { capabilityType: 'PUSH_NOTIFICATIONS' },
      relationships: { bundleId: { data: { type: 'bundleIds', id: bundle.id } } },
    },
  });
}

export async function prepare({ api, bundleId, teamId, csrPem, runNumber, profileDirs }) {
  const bundles = [];
  for (const t of TARGETS) {
    const bundle = await ensureBundleId(api, bundleId + t.suffix, t.name);
    if (t.push) await ensurePush(api, bundle);
    bundles.push({ ...t, identifier: bundleId + t.suffix, id: bundle.id });
  }

  const apps = await api.call('GET', `/v1/apps?filter[bundleId]=${encodeURIComponent(bundleId)}`);
  if (!apps.data.length) {
    throw new UserFacingError(
      `В App Store Connect ещё нет приложения с Bundle ID ${bundleId}. ` +
        'Создай его: appstoreconnect.apple.com → Приложения → «+» → Новое приложение, ' +
        `платформа iOS, Bundle ID «${bundleId}», SKU любой (например locket). Потом запусти сборку ещё раз.`,
    );
  }

  let certificate;
  try {
    certificate = (
      await api.call('POST', '/v1/certificates', {
        data: { type: 'certificates', attributes: { certificateType: 'DISTRIBUTION', csrContent: csrPem } },
      })
    ).data;
  } catch (err) {
    if (err.status === 409) {
      throw new UserFacingError(
        'Apple не даёт создать ещё один сертификат Apple Distribution — лимит исчерпан. ' +
          'Отзови старые на developer.apple.com → Certificates, Identifiers & Profiles → Certificates и запусти сборку снова.',
      );
    }
    throw err;
  }

  const state = { certificateId: certificate.id, profileIds: [] };
  const profiles = {};
  try {
    for (const b of bundles) {
      const name = `Locket CI ${runNumber}${b.suffix || ' app'}`;
      const profile = (
        await api.call('POST', '/v1/profiles', {
          data: {
            type: 'profiles',
            attributes: { name, profileType: 'IOS_APP_STORE' },
            relationships: {
              bundleId: { data: { type: 'bundleIds', id: b.id } },
              certificates: { data: [{ type: 'certificates', id: certificate.id }] },
            },
          },
        })
      ).data;
      state.profileIds.push(profile.id);
      const content = Buffer.from(profile.attributes.profileContent, 'base64');
      for (const dir of profileDirs) {
        fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(path.join(dir, `${profile.attributes.uuid}.mobileprovision`), content);
      }
      profiles[b.identifier] = { name, env: b.env };
    }
  } catch (err) {
    err.state = state;
    throw err;
  }

  return {
    state,
    certificateDer: Buffer.from(certificate.attributes.certificateContent, 'base64'),
    profiles,
    exportOptions: exportOptionsPlist(teamId, profiles),
  };
}

export async function cleanup({ api, state }) {
  for (const id of state.profileIds ?? []) {
    await api.call('DELETE', `/v1/profiles/${id}`).catch((e) => console.warn(e.message));
  }
  if (state.certificateId) {
    await api.call('DELETE', `/v1/certificates/${state.certificateId}`).catch((e) => console.warn(e.message));
  }
}

function exportOptionsPlist(teamId, profiles) {
  const xml = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const entries = Object.entries(profiles)
    .map(([id, p]) => `      <key>${xml(id)}</key>\n      <string>${xml(p.name)}</string>`)
    .join('\n');
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>destination</key>
  <string>upload</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>signingCertificate</key>
  <string>Apple Distribution</string>
  <key>teamID</key>
  <string>${xml(teamId)}</string>
  <key>provisioningProfiles</key>
  <dict>
${entries}
  </dict>
  <key>uploadSymbols</key>
  <true/>
  <key>manageAppVersionAndBuildNumber</key>
  <false/>
</dict>
</plist>
`;
}

async function main() {
  const command = process.argv[2];
  const dir = process.env.SIGNING_DIR;
  if (!dir) throw new Error('SIGNING_DIR is not set');
  const statePath = path.join(dir, 'asc-state.json');
  const api = createClient({
    keyId: process.env.ASC_KEY_ID,
    issuerId: process.env.ASC_ISSUER_ID,
    keyPem: fs.readFileSync(path.join(dir, 'AuthKey.p8'), 'utf8'),
    baseUrl: process.env.ASC_API || undefined,
  });

  if (command === 'cleanup') {
    if (!fs.existsSync(statePath)) return;
    await cleanup({ api, state: JSON.parse(fs.readFileSync(statePath, 'utf8')) });
    fs.rmSync(statePath);
    console.log('Временный сертификат отозван, профили удалены.');
    return;
  }
  if (command !== 'prepare') throw new Error('usage: node asc.mjs prepare|cleanup');

  const home = os.homedir();
  try {
    const result = await prepare({
      api,
      bundleId: process.env.LOCKET_BUNDLE_ID,
      teamId: process.env.LOCKET_TEAM_ID,
      csrPem: fs.readFileSync(path.join(dir, 'dist.csr'), 'utf8'),
      runNumber: process.env.GITHUB_RUN_NUMBER || String(Date.now()),
      profileDirs: [
        path.join(home, 'Library/MobileDevice/Provisioning Profiles'),
        path.join(home, 'Library/Developer/Xcode/UserData/Provisioning Profiles'),
      ],
    });
    fs.writeFileSync(statePath, JSON.stringify(result.state));
    fs.writeFileSync(path.join(dir, 'dist.cer'), result.certificateDer);
    fs.writeFileSync(path.join(dir, 'ExportOptions.plist'), result.exportOptions);
    const envLines = Object.values(result.profiles).map((p) => `${p.env}=${p.name}`);
    if (process.env.GITHUB_ENV) fs.appendFileSync(process.env.GITHUB_ENV, envLines.join('\n') + '\n');
    console.log(`Сертификат и ${envLines.length} профиля готовы.`);
  } catch (err) {
    if (err.state) fs.writeFileSync(statePath, JSON.stringify(err.state));
    throw err;
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((err) => {
    console.error(err instanceof UserFacingError ? `::error::${err.message}` : err);
    process.exit(1);
  });
}
