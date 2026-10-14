import crypto from 'node:crypto';
import http2 from 'node:http2';

const HOSTS = {
  production: 'https://api.push.apple.com',
  sandbox: 'https://api.sandbox.push.apple.com',
};

// Minimal Apple Push Notification service client: token (.p8) auth over HTTP/2.
export function createApnsClient({ keyPem, keyId, teamId, topic }) {
  const sessions = {};
  let jwt = null;
  let jwtIssuedAt = 0;

  function authToken() {
    const now = Math.floor(Date.now() / 1000);
    // Apple wants the token refreshed at most every 20 min and at least every 60 min.
    if (!jwt || now - jwtIssuedAt > 50 * 60) {
      const header = b64url({ alg: 'ES256', kid: keyId });
      const claims = b64url({ iss: teamId, iat: now });
      const signature = crypto
        .sign('sha256', Buffer.from(`${header}.${claims}`), { key: keyPem, dsaEncoding: 'ieee-p1363' })
        .toString('base64url');
      jwt = `${header}.${claims}.${signature}`;
      jwtIssuedAt = now;
    }
    return jwt;
  }

  function session(env) {
    let s = sessions[env];
    if (!s || s.closed || s.destroyed) {
      s = http2.connect(HOSTS[env] || HOSTS.production);
      s.on('error', () => {});
      s.on('goaway', () => s.close());
      sessions[env] = s;
    }
    return s;
  }

  function send(deviceToken, env, payload, { collapseId, pushType = 'alert', priority = 10 } = {}) {
    return new Promise((resolve) => {
      const headers = {
        ':method': 'POST',
        ':path': `/3/device/${deviceToken}`,
        authorization: `bearer ${authToken()}`,
        'apns-topic': topic,
        'apns-push-type': pushType,
        'apns-priority': String(priority),
        'content-type': 'application/json',
      };
      if (collapseId) headers['apns-collapse-id'] = collapseId;

      let req;
      try {
        req = session(env).request(headers);
      } catch (err) {
        resolve({ status: 0, reason: err.message });
        return;
      }
      let status = 0;
      let data = '';
      req.setEncoding('utf8');
      req.setTimeout(10_000, () => {
        req.close();
        resolve({ status: 0, reason: 'timeout' });
      });
      req.on('response', (h) => (status = h[':status']));
      req.on('data', (chunk) => (data += chunk));
      req.on('end', () => {
        let reason;
        try {
          reason = data ? JSON.parse(data).reason : undefined;
        } catch {}
        resolve({ status, reason });
      });
      req.on('error', (err) => resolve({ status: 0, reason: err.message }));
      req.end(JSON.stringify(payload));
    });
  }

  function close() {
    for (const s of Object.values(sessions)) s.close();
  }

  return { send, close };
}

function b64url(obj) {
  return Buffer.from(JSON.stringify(obj)).toString('base64url');
}
