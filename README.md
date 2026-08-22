# cutlog

**セルフホストできる、オープンソースの「1日の記録」アプリ。** ブラウザだけで完結します。

数秒のカットを1日に何度か撮ると、時系列でたまっていきます。カレンダーで振り返り、
**カット単位で選んで**書き出したり、共有リンクを作ったりできます。

```
docker compose up -d   →  http://localhost:8787
```

---

## なぜ作ったか

短い動画で1日を記録するアプリ（SetLog）のコンセプトはとても良いものです。一方で、使っていると次の点に困ります。

| 困りごと | cutlog での答え |
|---|---|
| 通知を見逃すとその時間の記録が残らない | **撮る時刻を自分で決める。**通知を切っても、いつでも撮れる |
| 過去を振り返る導線が弱い | **一覧＋詳細**の素直な画面。カレンダーは一覧の表示方法の1つ |
| 1日が1本に固められ、1カットだけ外せない | **カット単位で選んで**書き出し・共有できる |
| 書き出しが動画1本だけ | **メタデータを全部残す**（`cuts.json` / `cuts.csv` ＋ 元ファイル） |
| データを持ち出せない | **自分のサーバに置く。**いつでも丸ごと書き出せる |
| アプリを入れる必要がある | **ブラウザだけで動く。**カメラも画面の中で開く |
| まとめ動画の見た目が固定 | **書き出した動画の見た目を自分で変えられる**（大きさ・収め方・背景色・時刻の焼き込みなど） |
| 違うログへ撮ってしまったカットを直せない | **カットを後からどのログのものかへ変えられる** |
| 記録先をその都度選ばないといけない | **既定の記録先を選べる。**指定しなければそこへ入る |

---

## 主な機能

- **撮影**: ブラウザ内のカメラ（前後の切り替え・秒数の指定・撮り直し）。写真も撮れる。手元のファイルの取り込みも可
- **一覧＋詳細**: タイムライン / カレンダー / グリッドの3表示。メモと撮影者で絞り込み
- **メタデータ**: 撮影日時・タイムゾーン・長さ・解像度・カメラの前後・取り込み方法・サイズ・SHA-256 を保持
- **書き出し**: 選んだカットだけを ZIP（元ファイル＋サムネイル＋`cuts.json`＋`cuts.csv`）で
- **共有リンク**: 含めるカットを選んで発行。パスワード・有効期限・ダウンロード可否・あとから停止
- **まとめ動画**: 選んだカットを1本の mp4 に（サーバ側 ffmpeg。大きさ・収め方・背景色・fps・時刻とメモの焼き込み・
  表紙などの見た目を自分で決められ、前に使った設定を次も使う）
- **グループ**: 招待コードで参加。1つのログを複数人で。リアクションとコメント
- **プライベートログと既定の記録先**: 利用者は誰も招待できない自分だけのログを必ず1つ持つ。行き先を指定しない
  カットの既定の記録先にもなり、既定の記録先は自分で変えられる
- **カットの付け替え**: 撮ったあとで、そのカットをどのログのものかへ動かせる
- **通知**: Web Push（毎時 / 決めた時刻 / ランダム）。通知は前提ではありません
- **運用**: SQLite または PostgreSQL、ローカルディスクまたは S3 互換、OIDC（Google・Entra ID・Keycloak…）、
  監査ログ、ヘルスチェック、ジョブキュー（複数台で動かせる）

---

## 始め方

### 1. いちばん簡単（Docker）

```bash
git clone https://github.com/kouheisatou/cutlog.git
cd cutlog
cp .env.example .env      # そのままでも動きます
docker compose up -d
```

`http://localhost:8787` を開き、最初のユーザーを登録します。**最初に登録した人が管理者**になります。

> **カメラは HTTPS か localhost でしか開けません。**（ブラウザの決まり）
> 外から使うときは、Caddy や Nginx で HTTPS を張ってください。→ [docs/SELF_HOSTING.md](docs/SELF_HOSTING.md)

### 2. Node で直接動かす（開発するとき）

```bash
npm install
npm run dev        # http://localhost:8787
```

必要なもの: **Node.js 22 以上**とffmpeg（まとめ動画を作る場合）。

---

## 設定

すべて `.env` で切り替えます。→ [docs/CONFIGURATION.md](docs/CONFIGURATION.md)

| 目的 | 変数 |
|---|---|
| PostgreSQL を使う | `DB_DRIVER=postgres` / `DATABASE_URL=...` |
| メディアを S3 に置く | `STORAGE_DRIVER=s3` / `S3_BUCKET` ほか |
| Google でログイン | `OIDC_ISSUER=https://accounts.google.com` / `OIDC_CLIENT_ID` / `OIDC_CLIENT_SECRET` |
| 社内ドメインだけ許可 | `OIDC_ALLOWED_DOMAINS=example.co.jp` |
| 通知を使う | `npm run vapid` で作った `VAPID_*` を貼る |
| 新規登録を閉じる | `AUTH_OPEN_SIGNUP=false` |

---

## 更新する

サーバに置いた cutlog を新しくするときは、リポジトリの `deploy.sh` を使います。
gitから取ってきて、イメージを作り直し、入れ替えて、健康確認まで一度に行います。

```bash
cd /opt/cutlog
./deploy.sh              # origin/main の最新へ
./deploy.sh v0.2.0       # タグ・ブランチ・コミットを指定
./deploy.sh --status     # いまの状態を見るだけ
./deploy.sh --rollback   # 直前の版へ戻す
```

- 健康確認（`/api/healthz`）が通らなければ、**自動で直前の版へ戻します**。
- `.env` は git の管理外なので、更新しても**サーバの設定はそのまま残ります**。
- すでに最新なら、作り直さずに終わります。

---

## 大きく使うとき

- **Web と ffmpeg を分ける**: 同じイメージを2つ立て、Web 側は `RENDER_WORKER=false`、ワーカー側は `true`。
  ジョブは DB のキューで受け渡します（PostgreSQL では `SKIP LOCKED` で取り合いません）
- **保存先を S3 に**: 複数台から同じメディアを読めます
- **バックアップ**: PostgreSQL のダンプ ＋ メディア（`/data/media` か S3 バケット）

詳細は [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

---

## 開発に参加する

**大歓迎です。** Issue も Pull Request もお気軽にどうぞ。

- 全体像: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- 進め方: [CONTRIBUTING.md](CONTRIBUTING.md)
- これから作るもの: [ROADMAP.md](ROADMAP.md)
- バージョンとリリースの手順: [docs/RELEASING.md](docs/RELEASING.md)

```
src/     サーバ（Express・素のJS・ビルド不要）
  db/       DBアダプタ（SQLite / PostgreSQL）とマイグレーション
  storage/  保存先アダプタ（ローカル / S3互換）
  auth/     ログイン（ローカル / OIDC）
  jobs/     ジョブキューと ffmpeg
  routes/   HTTP API
web/     フロント（素のESモジュール。ビルド不要）
docs/    ドキュメント
```

**ビルド工程がありません。** `npm install` して `npm run dev` すれば、そのまま直せます。

## ライセンス

MIT
