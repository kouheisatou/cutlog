import path from 'node:path';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
export const ROOT = path.resolve(here, '..');

// .env を読む（依存を増やさないための最小実装）
const envFile = path.join(ROOT, '.env');
if (fs.existsSync(envFile)) {
  for (const line of fs.readFileSync(envFile, 'utf8').split(/\r?\n/)) {
    const m = /^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/.exec(line);
    if (!m) continue;
    const value = m[2].replace(/^["'](.*)["']$/, '$1');
    if (process.env[m[1]] === undefined) process.env[m[1]] = value;
  }
}

const bool = (v, dflt) => (v === undefined ? dflt : ['1', 'true', 'yes', 'on'].includes(String(v).toLowerCase()));
const num = (v, dflt) => (v === undefined || v === '' ? dflt : Number(v));

export const config = {
  env: process.env.NODE_ENV || 'development',
  port: num(process.env.PORT, 8787),
  baseUrl: (process.env.BASE_URL || `http://localhost:${num(process.env.PORT, 8787)}`).replace(/\/$/, ''),
  trustProxy: bool(process.env.TRUST_PROXY, false),
  dataDir: path.resolve(process.env.DATA_DIR || path.join(ROOT, 'data')),

  db: {
    // sqlite（既定・設定なしで動く）か postgres（大きめの環境向け）
    driver: (process.env.DB_DRIVER || (process.env.DATABASE_URL ? 'postgres' : 'sqlite')).toLowerCase(),
    url: process.env.DATABASE_URL || '',
    sqliteFile: process.env.SQLITE_FILE || '',
  },

  storage: {
    // local（既定）か s3（S3互換。MinIOでも動く）
    driver: (process.env.STORAGE_DRIVER || (process.env.S3_BUCKET ? 's3' : 'local')).toLowerCase(),
    s3: {
      bucket: process.env.S3_BUCKET || '',
      region: process.env.S3_REGION || 'us-east-1',
      endpoint: process.env.S3_ENDPOINT || '',
      accessKeyId: process.env.S3_ACCESS_KEY_ID || '',
      secretAccessKey: process.env.S3_SECRET_ACCESS_KEY || '',
      forcePathStyle: bool(process.env.S3_FORCE_PATH_STYLE, true),
      prefix: process.env.S3_PREFIX || 'cutlog',
    },
  },

  auth: {
    // ローカルのID・パスワード
    localEnabled: bool(process.env.AUTH_LOCAL_ENABLED, true),
    openSignup: bool(process.env.AUTH_OPEN_SIGNUP, true),
    // OIDC（Google・Entra ID・Keycloak・Auth0 など。envを書くだけで有効になる）
    oidc: {
      issuer: process.env.OIDC_ISSUER || '',
      clientId: process.env.OIDC_CLIENT_ID || '',
      clientSecret: process.env.OIDC_CLIENT_SECRET || '',
      scope: process.env.OIDC_SCOPE || 'openid email profile',
      buttonLabel: process.env.OIDC_BUTTON_LABEL || 'シングルサインオンで入る',
      // 例: OIDC_ALLOWED_DOMAINS=example.co.jp,example.com
      allowedDomains: (process.env.OIDC_ALLOWED_DOMAINS || '').split(',').map((s) => s.trim()).filter(Boolean),
      autoCreateUsers: bool(process.env.OIDC_AUTO_CREATE_USERS, true),
    },
    sessionDays: num(process.env.SESSION_DAYS, 90),
    cookieSecure: bool(process.env.COOKIE_SECURE, false),
  },

  // 地図の絵（タイル）の出どころ。既定は OpenStreetMap。
  // 外へ出したくないときは MAP_TILE_URL を空にすると、印だけの地図になる。
  map: {
    tileUrl: process.env.MAP_TILE_URL !== undefined
      ? process.env.MAP_TILE_URL
      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    credit: process.env.MAP_CREDIT || '© OpenStreetMap contributors',
  },

  media: {
    maxUploadMb: num(process.env.MAX_UPLOAD_MB, 200),
    cutSecondsDefault: num(process.env.CUT_SECONDS_DEFAULT, 2),
    retentionDays: num(process.env.MEDIA_RETENTION_DAYS, 0), // 0 なら消さない
  },

  ffmpeg: {
    bin: process.env.FFMPEG_PATH || 'ffmpeg',
    probe: process.env.FFPROBE_PATH || 'ffprobe',
    enabled: bool(process.env.RENDER_ENABLED, true),
    concurrency: num(process.env.RENDER_CONCURRENCY, 1),
    // 複数台で動かすとき、この台でジョブを処理するか
    worker: bool(process.env.RENDER_WORKER, true),
    // まとめ動画に文字を焼き込むフォント。空ならffmpegが持っている既定のフォントを使う
    fontFile: process.env.RENDER_FONT_FILE || '',
  },

  push: {
    publicKey: process.env.VAPID_PUBLIC_KEY || '',
    privateKey: process.env.VAPID_PRIVATE_KEY || '',
    subject: process.env.VAPID_SUBJECT || 'mailto:admin@example.com',
  },

  limits: {
    // 1分あたりの書き込み回数（IPごと）
    writePerMinute: num(process.env.RATE_LIMIT_WRITE_PER_MINUTE, 120),
  },

  instance: {
    name: process.env.INSTANCE_NAME || 'cutlog',
    // 管理者にするユーザー名（カンマ区切り）。最初のユーザーは自動で管理者になる
    admins: (process.env.ADMIN_USERNAMES || '').split(',').map((s) => s.trim()).filter(Boolean),
  },
};

export const paths = {
  media: path.join(config.dataDir, 'media'),
  renders: path.join(config.dataDir, 'renders'),
  tmp: path.join(config.dataDir, 'tmp'),
};

for (const dir of Object.values(paths)) fs.mkdirSync(dir, { recursive: true });

export const oidcEnabled = Boolean(config.auth.oidc.issuer && config.auth.oidc.clientId);
