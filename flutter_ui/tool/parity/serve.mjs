// Flutter の web ビルドを、本物と同じ土俵に立たせるための小さな配信口。
// ★ 別の港（ポート）から配ると、ログインの鍵（cookie）が別物になって中身が空になる。
//   ここでは静のファイルを配りつつ、/api と /media だけ本物のサーバへ横流しする。
//   ブラウザから見れば1つの出どころなので、鍵はそのまま通る。
import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, normalize, resolve } from 'node:path';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(here, '../../build/web');
const UPSTREAM = process.env.CUTLOG_BASE || 'http://localhost:8787';
const PORT = Number(process.env.PARITY_PORT || 8788);

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8', '.png': 'image/png', '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml', '.wasm': 'application/wasm', '.ttf': 'font/ttf',
  '.otf': 'font/otf', '.woff': 'font/woff', '.woff2': 'font/woff2', '.bin': 'application/octet-stream',
  '.symbols': 'application/json; charset=utf-8', '.map': 'application/json; charset=utf-8',
};

async function pipeUpstream(req, res) {
  const url = `${UPSTREAM}${req.url}`;
  const chunks = [];
  for await (const c of req) chunks.push(c);
  const body = chunks.length ? Buffer.concat(chunks) : undefined;

  const headers = { ...req.headers };
  delete headers.host;
  delete headers['accept-encoding'];   // そのまま流すので、圧縮は挟まない

  const up = await fetch(url, { method: req.method, headers, body, redirect: 'manual' });
  const out = {};
  up.headers.forEach((v, k) => {
    if (k === 'content-encoding' || k === 'content-length' || k === 'transfer-encoding') return;
    out[k] = v;
  });
  // Set-Cookie は forEach でひとつに潰れるので、生の並びを取り直す
  const cookies = up.headers.getSetCookie?.() ?? [];
  res.writeHead(up.status, cookies.length ? { ...out, 'set-cookie': cookies } : out);
  res.end(Buffer.from(await up.arrayBuffer()));
}

createServer(async (req, res) => {
  try {
    if (req.url.startsWith('/api/') || req.url.startsWith('/media/') || req.url.startsWith('/share/')) {
      return await pipeUpstream(req, res);
    }
    const clean = normalize(decodeURIComponent(req.url.split('?')[0])).replace(/^(\.\.[/\\])+/, '');
    let file = join(ROOT, clean);
    if (!existsSync(file) || statSync(file).isDirectory()) file = join(ROOT, 'index.html');
    res.writeHead(200, {
      'content-type': TYPES[extname(file)] || 'application/octet-stream',
      'cache-control': 'no-store',
      // ★ COOP/COEP は付けない。付けると、地図の瓦のように
      //   よそから取ってくるものが軒並み弾かれる（Flutter は無くても動く）。
    });
    createReadStream(file).pipe(res);
  } catch (e) {
    res.writeHead(500, { 'content-type': 'text/plain; charset=utf-8' });
    res.end(String(e.message));
  }
}).listen(PORT, () => console.log(`Flutter の web を http://localhost:${PORT} で配ります（API は ${UPSTREAM} へ横流し）`));
