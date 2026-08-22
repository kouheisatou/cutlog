# セルフホストの手引き

## 最小構成（1台・SQLite・ローカルディスク）

```bash
git clone https://github.com/kouheisatou/cutlog.git
cd cutlog && cp .env.example .env
docker compose up -d
```

データはDockerのボリューム `cutlog_data`（コンテナの中の `/data`）に入ります。

## HTTPSを張る（実質必須）

**カメラと通知は、HTTPSかlocalhostでしか動きません。** Caddyがいちばん短く済みます。

```caddy
cutlog.example.com {
    reverse_proxy 127.0.0.1:8787
}
```

`.env` をこう変えます。

```
BASE_URL=https://cutlog.example.com
TRUST_PROXY=true
COOKIE_SECURE=true
```

Nginxの例です。

```nginx
server {
  server_name cutlog.example.com;
  client_max_body_size 250m;   # MAX_UPLOAD_MB より大きくする
  location / {
    proxy_pass http://127.0.0.1:8787;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }
}
```

## 規模が大きいとき

```bash
docker compose --profile postgres --profile minio up -d
```

`.env`:

```
DB_DRIVER=postgres
DATABASE_URL=postgres://cutlog:cutlog@postgres:5432/cutlog
STORAGE_DRIVER=s3
S3_BUCKET=cutlog
S3_ENDPOINT=http://minio:9000
S3_ACCESS_KEY_ID=cutlog
S3_SECRET_ACCESS_KEY=cutlogcutlog
S3_FORCE_PATH_STYLE=true
```

### Webとffmpegを分ける

```yaml
services:
  app:
    environment:
      RENDER_WORKER: "false"    # 受け付けだけを担う
  worker:
    image: ghcr.io/kouheisatou/cutlog:latest
    environment:
      RENDER_WORKER: "true"
      PORT: "8788"
```

同じDBと保存先を見ていれば、ジョブは自動で分かれます。台数は増やせます。

## まとめ動画に焼き込む文字のフォント

Dockerイメージにはフォントを同梱していません。時刻の焼き込みは既定でONなので、そのまま動かすとまとめ動画の
文字が出ない・崩れることがあります。フォントファイルをコンテナへ持ち込み、`RENDER_FONT_FILE` で指す先を
決めてください。

```yaml
services:
  app:
    volumes:
      - cutlog_data:/data
      - ./fonts:/data/fonts:ro   # 好きなフォントファイルを置いたディレクトリ
    environment:
      RENDER_FONT_FILE: /data/fonts/NotoSansJP-Regular.otf
```

日本語のメモを焼き込むなら、日本語をカバーするフォント（Noto Sans JP など）を選んでください。

## 個人情報の扱い

**外部へは送りません。** 何を保存し、どこに置くかは次のとおりです。

| データ | 保存先 |
|---|---|
| ユーザー名・表示名・メールアドレス・パスワードのハッシュ（scrypt） | 自分のDB（SQLite または PostgreSQL） |
| カットの元ファイルとサムネイル | 自分の保存先（ローカルディスク または 自分のS3互換バケット） |
| カットのメタデータ（撮影日時・タイムゾーン・長さ・カメラの前後・取り込み方法・メモ・タグ・SHA-256） | 自分のDB |
| 誰が何をしたかの記録 | 自分のDBの `audit_log` |

**位置情報は取りません。**（`Permissions-Policy` で `geolocation` を無効にしている）

次の2つは、管理者が設定した場合だけ外部と通信します（既定では両方オフ）。

- **シングルサインオン（OIDC）**: ログイン時に、設定した認証プロバイダ（Google・Entra IDなど）へ問い合わせます
- **通知（Web Push）**: 利用者が通知を許可すると、ブラウザの提供元（Google・Mozillaなど）のプッシュ配信の
  仕組みを経由して届きます。内容は暗号化され、cutlog側では文言（「いま何してる？」等）だけを渡します

## バックアップ

| 対象 | 方法 |
|---|---|
| SQLite | `/data/cutlog.db*` をコピーする（止めてからが安全） |
| PostgreSQL | `pg_dump -Fc` |
| メディア | `/data/media`、またはS3のバケット |

## 監視

- `GET /api/healthz` が `{"ok":true}` を返します（Dockerのヘルスチェックにも入れてあります）
- 管理者は `GET /api/admin/stats` で件数と容量を見られます

## 更新

```bash
git pull && docker compose build && docker compose up -d
```

マイグレーションは起動時に自動で流れます。
