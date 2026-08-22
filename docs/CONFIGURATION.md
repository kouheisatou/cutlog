# 設定（.env）

すべて環境変数です。`.env.example` をコピーして使ってください。

## 基本

| 変数 | 既定 | 説明 |
|---|---|---|
| `BASE_URL` | `http://localhost:8787` | 公開URL。共有リンクとOIDCのコールバックに使う |
| `PORT` | `8787` | 待ち受けポート |
| `INSTANCE_NAME` | `cutlog` | ログイン画面に出す名前 |
| `TRUST_PROXY` | `false` | リバースプロキシの後ろに置くなら `true` |
| `COOKIE_SECURE` | `false` | HTTPSで公開するなら `true` |
| `DATA_DIR` | `./data` | メディアとSQLiteの置き場所 |

## データベース

| 変数 | 説明 |
|---|---|
| `DB_DRIVER` | `sqlite`（既定）か `postgres` |
| `DATABASE_URL` | `postgres://user:pass@host:5432/cutlog` |
| `SQLITE_FILE` | SQLiteのファイル（既定は `DATA_DIR/cutlog.db`） |

**どちらでも同じ機能が動きます。** 人数が増える、複数台にする、バックアップを整えたい。このどれかに当てはまるならPostgreSQLを選んでください。

## メディアの保存先

| 変数 | 説明 |
|---|---|
| `STORAGE_DRIVER` | `local`（既定）か `s3` |
| `S3_BUCKET` / `S3_REGION` / `S3_ENDPOINT` | S3互換の接続先（MinIO・R2・AWS S3） |
| `S3_ACCESS_KEY_ID` / `S3_SECRET_ACCESS_KEY` | 認証情報 |
| `S3_FORCE_PATH_STYLE` | MinIOでは `true` |
| `S3_PREFIX` | バケット内の接頭辞 |

## 認証

| 変数 | 説明 |
|---|---|
| `AUTH_LOCAL_ENABLED` | IDとパスワードのログインを使うか |
| `AUTH_OPEN_SIGNUP` | 誰でも登録できるか（`false` でも最初の1人は作れる） |
| `ADMIN_USERNAMES` | 管理者にするユーザー名（カンマ区切り） |
| `OIDC_ISSUER` / `OIDC_CLIENT_ID` / `OIDC_CLIENT_SECRET` | **これを書くとSSOが有効になる** |
| `OIDC_SCOPE` | 既定は `openid email profile` |
| `OIDC_BUTTON_LABEL` | ボタンの文言 |
| `OIDC_ALLOWED_DOMAINS` | 許可するメールのドメイン |
| `OIDC_AUTO_CREATE_USERS` | 初めての人を自動で作るか |
| `SESSION_DAYS` | セッションの有効日数 |

手順は [AUTH_OIDC.md](AUTH_OIDC.md) にあります。

## 通知

| 変数 | 説明 |
|---|---|
| `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` | `npm run vapid` で作る |
| `VAPID_SUBJECT` | 連絡先（`mailto:` かURL） |

## メディアとまとめ動画

| 変数 | 既定 | 説明 |
|---|---|---|
| `MAX_UPLOAD_MB` | `200` | 1カットの上限 |
| `CUT_SECONDS_DEFAULT` | `3` | 新しいログの既定の秒数 |
| `RENDER_ENABLED` | `true` | まとめ動画を使うか |
| `RENDER_CONCURRENCY` | `1` | 同時に走らせるffmpegの数 |
| `RENDER_WORKER` | `true` | この台でジョブを処理するか |
| `FFMPEG_PATH` / `FFPROBE_PATH` | `ffmpeg` / `ffprobe` | 実行ファイルの場所 |
| `RENDER_FONT_FILE` | (空) | まとめ動画に焼き込む文字のフォントファイル。空ならffmpegが持っている既定のフォントを使う |

## そのほか

| 変数 | 既定 | 説明 |
|---|---|---|
| `RATE_LIMIT_WRITE_PER_MINUTE` | `120` | 1つのIPあたりの書き込み回数 |
| `MEDIA_RETENTION_DAYS` | `0` | 0なら消さない（自動削除はv0.3で実装します） |
