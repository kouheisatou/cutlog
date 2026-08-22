import express from 'express';
import path from 'node:path';
import { config, ROOT } from './config.js';
import { initDb, db, nowIso } from './db/index.js';
import { api, pushToUser } from './routes/api.js';
import { startWorker } from './jobs/queue.js';
import './jobs/render.js';

// 地図の絵の配信元。MAP_TILE_URL が指す先だけを、画像の取得先として足す。
// 設定していなければ何も足さない（外へは出ない）。
const mapImgSrc = (() => {
  const u = config.map?.tileUrl;
  if (!u) return '';
  try {
    const { protocol, host } = new URL(u.replace('{z}', '0').replace('{x}', '0').replace('{y}', '0'));
    return ` ${protocol}//${host}`;
  } catch {
    console.warn('[csp] MAP_TILE_URL を住所として読めませんでした:', u);
    return '';
  }
})();

const app = express();
if (config.trustProxy) app.set('trust proxy', 1);
app.disable('x-powered-by');
app.use(express.json({ limit: '2mb' }));

app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'same-origin');
  res.setHeader('Permissions-Policy', 'camera=(self), microphone=(self), geolocation=()');
  // 画面は自分のオリジンのファイルだけで動く。外部へは何も取りに行かないし、送らない。
  // media（利用者が上げたファイル）は routes/api.js の側でさらに強く縛っている。
  // ただし地図の絵だけは、設定したその配信元に限って取りに行けるようにする。
  res.setHeader('Content-Security-Policy', [
    "default-src 'self'",
    `img-src 'self' blob: data:${mapImgSrc}`,
    "media-src 'self' blob:",
    "script-src 'self'",
    "style-src 'self'",
    "connect-src 'self'",
    "worker-src 'self'",
    "frame-ancestors 'none'",
    "object-src 'none'",
    "base-uri 'none'",
    "form-action 'self'",
  ].join('; '));
  next();
});

app.use('/api', api);

const webDir = path.join(ROOT, 'web');
// 開発中はキャッシュしない（直したものがすぐ反映されるように）
app.use(express.static(webDir, {
  extensions: ['html'],
  maxAge: config.env === 'production' ? '1h' : 0,
  etag: true,
}));
app.get('/s/:token', (req, res) => res.sendFile(path.join(webDir, 'share.html')));
app.get('*', (req, res) => {
  if (req.path.startsWith('/api/')) return res.status(404).json({ error: 'not found' });
  return res.sendFile(path.join(webDir, 'index.html'));
});

// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  console.error('[error]', err);
  if (res.headersSent) return;
  res.status(err.status || 500).json({ error: err.message || 'サーバでエラーが起きました' });
});

// 撮影を促す通知（1分ごとに、その時刻かどうかを見る）
function startReminderLoop() {
  if (!config.push.publicKey) return;
  setInterval(async () => {
    try {
      const rows = await db.all("SELECT * FROM reminders WHERE mode <> 'off'");
      for (const r of rows) {
        const local = new Date(Date.now() - (r.tz_offset || 0) * 60000);
        const hour = local.getUTCHours();
        const minute = local.getUTCMinutes();
        const hh = String(hour).padStart(2, '0');
        const mm = String(minute).padStart(2, '0');
        const slot = `${local.toISOString().slice(0, 10)}T${hh}:${mm}`;
        const inWindow = hour >= r.from_hour && hour <= r.to_hour;
        let fire = false;
        if (r.mode === 'hourly') fire = inWindow && mm === '00';
        if (r.mode === 'times') fire = String(r.times || '').split(',').map((s) => s.trim()).includes(`${hh}:${mm}`);
        if (r.mode === 'random') {
          const span = Math.max(1, r.to_hour - r.from_hour + 1) * 60;
          fire = inWindow && Math.random() < Math.min(1, (r.per_day || 6) / span);
        }
        if (!fire) continue;
        // eslint-disable-next-line no-await-in-loop
        const already = await db.get('SELECT 1 AS ok FROM reminder_fires WHERE user_id = ? AND slot = ?',
          [r.user_id, slot]);
        if (already) continue;
        // eslint-disable-next-line no-await-in-loop
        await db.run('INSERT INTO reminder_fires (user_id, slot) VALUES (?,?)', [r.user_id, slot]);
        // eslint-disable-next-line no-await-in-loop
        await pushToUser(r.user_id, { title: 'cutlog', body: 'いま何してる？ 1カット撮りましょう。', url: '/?capture=1' });
      }
    } catch (err) {
      console.error('[reminders]', err.message);
    }
  }, 60_000);
}

// 古いセッションと一時ファイルの掃除
function startJanitor() {
  setInterval(async () => {
    await db.run('DELETE FROM sessions WHERE expires_at < ?', [nowIso()]).catch(() => {});
    await db.run("DELETE FROM reminder_fires WHERE slot < ?", [new Date(Date.now() - 3 * 864e5).toISOString().slice(0, 16)])
      .catch(() => {});
  }, 60 * 60 * 1000);
}

const port = config.port;
initDb().then(() => {
  startWorker();
  startReminderLoop();
  startJanitor();
  app.listen(port, () => {
    console.log(`cutlog: ${config.baseUrl} で待ち受けます（DB=${db.driver} / 保存先=${config.storage.driver}）`);
  });
}).catch((err) => {
  console.error('起動できませんでした:', err);
  process.exit(1);
});
