export class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export function createRouter() {
  const routes = [];
  const add = (method) => (pattern, handler, opts = {}) => {
    const keys = [];
    const source = pattern.replace(/:(\w+)/g, (_, key) => {
      keys.push(key);
      return '([^/]+)';
    });
    routes.push({ method, regex: new RegExp(`^${source}$`), keys, handler, opts });
  };
  return {
    get: add('GET'),
    post: add('POST'),
    put: add('PUT'),
    patch: add('PATCH'),
    delete: add('DELETE'),
    match(method, pathname) {
      let pathMatched = false;
      for (const route of routes) {
        const m = route.regex.exec(pathname);
        if (!m) continue;
        pathMatched = true;
        if (route.method !== method) continue;
        const params = {};
        route.keys.forEach((k, i) => (params[k] = decodeURIComponent(m[i + 1])));
        return { route, params };
      }
      if (pathMatched) throw new HttpError(405, 'Метод не поддерживается');
      return null;
    },
  };
}

export function readBody(req, limit) {
  return new Promise((resolve, reject) => {
    const declared = Number(req.headers['content-length'] || 0);
    if (declared > limit) {
      reject(new HttpError(413, 'Слишком большой файл'));
      req.resume();
      return;
    }
    const chunks = [];
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > limit) {
        // Keep draining so the 413 response can still be delivered.
        chunks.length = 0;
        reject(new HttpError(413, 'Слишком большой файл'));
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

export async function readJson(req, limit = 64 * 1024) {
  const buf = await readBody(req, limit);
  if (!buf.length) return {};
  try {
    const value = JSON.parse(buf.toString('utf8'));
    return value && typeof value === 'object' ? value : {};
  } catch {
    throw new HttpError(400, 'Некорректный JSON');
  }
}

export function sendJson(res, status, body) {
  const data = JSON.stringify(body);
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(data),
    'cache-control': 'no-store',
  });
  res.end(data);
}
