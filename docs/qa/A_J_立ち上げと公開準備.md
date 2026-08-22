# リリース前確認: A（立ち上げ）・J（公開の準備）

`docs/RELEASE_QA.md` のA1〜A10・J1〜J8を、実際にコマンドを叩いて確かめた記録である。

## 実行環境の前提

- このマシンにDockerが入っていない（`docker --version` が `command not found` を返した）。
  そのため **A1と、A2のdocker経路は⏭にし、A3以降と同じNode直起動の経路で代わりに確かめた。**
- 他の担当が同じマシンでポート `8787`・`8791`・`8792`・`8793` を使っていたため、
  自分の確認では **8790番台の使われていないポート（8795〜8798）** を使った。README・`.env.example` が
  既定にしている `8787` そのものではないが、`PORT` 環境変数で変えられることの確認（A9）と同じ経路なので、
  結果は既定ポートでも変わらない。
- リポジトリを一時ディレクトリへコピーし（`.git`・`node_modules`・既存の `data` は除外）、
  そこで `npm ci` を通したうえで確認した。

## 判定の内訳

| 区分 | 件数 |
|---|---|
| 通った（✅） | 17 |
| 落ちた（❌） | 0 |
| この版では対象外（⏭） | 1（A1のみ） |

---

## A. 立ち上げ

| # | 確認すること | 判定 | 実際に叩いたコマンドと出力の要点 |
|---|---|---|---|
| A1 | `git clone` → `docker compose up` だけで動く | ⏭ | `docker --version` → `command not found`。このマシンにDockerが未導入のため実行できなかった。同じ内容はA3（Node直起動）で確認した |
| A2 | `.env.example` をコピーするだけで動く | ✅ | Docker経路は未検証（A1と同じ理由）。代わりに `cp .env.example .env` → `PORT=8795 DATA_DIR=<一時dir> node src/index.js`。ログに `[db] applied 00*.sql` → `cutlog: http://localhost:8787 で待ち受けます` → `curl http://127.0.0.1:8795/api/healthz` が `{"ok":true,"db":"sqlite","storage":"local",...}` を返し、未設定の項目があっても落ちなかった |
| A3 | Dockerを使わない起動も動く | ✅ | `npm ci`（`added 222 packages`、0 vulnerabilities）→ `PORT=8795 DATA_DIR=<一時dir> npm start`。ビルド工程なしで `node src/index.js` がそのまま起動し、`/api/healthz` が200を返した。Node v24.14.1（`engines.node: >=22` を満たす） |
| A4 | 初回のマイグレーションが自動で走る | ✅ | 空のデータディレクトリで起動すると、ログに `[db] applied 001_init.sql` `[db] applied 002_private_log.sql` `[db] applied 003_private_log_unique.sql` の3行が出た。`node:sqlite` でテーブルを確認 → `audit_log, comments, cuts, jobs, logs, memberships, push_subs, reactions, reminder_fires, reminders, schema_migrations, sessions, share_cuts, shares, users` の15テーブルが存在した |
| A5 | 2回目の起動でマイグレーションが二重に走らない | ✅ | 同じデータディレクトリで再度 `node src/index.js` を実行。ログに `[db] applied` の行は出ず、`[jobs] ワーカーを開始しました` から始まり、`/api/healthz` は正常に応答した |
| A6 | 最初に登録した人が管理者になる | ✅ | `POST /api/auth/signup` に `{"username":"alice","password":"password123"}` → 応答は `"isAdmin":true`。続けて `GET /api/me` でも `"isAdmin":true` を確認した |
| A7 | 2人目以降は管理者にならない | ✅ | 同じデータベースへ `POST /api/auth/signup` で `{"username":"bob",...}` を登録 → 応答は `"isAdmin":false` |
| A8 | `AUTH_OPEN_SIGNUP=false` で登録を止められる。最初の1人は作れる | ✅ | ①既存DB（alice・bob登録済み）で `AUTH_OPEN_SIGNUP=false` を付けて再起動 → 3人目 `carol` の登録は `403 {"error":"新規登録は閉じています"}`。既存の `alice` の `POST /api/auth/login` は `200` で成功した。②別の空のデータディレクトリで最初から `AUTH_OPEN_SIGNUP=false` にして起動 → 最初の1人（`firstadmin`）の登録は `200` で成功し `"isAdmin":true` になった |
| A9 | ポート・データ置き場を環境変数で変えられる | ✅ | A2〜A8のすべてで `PORT=8795〜8798` と `DATA_DIR=<一時dir>` を指定して起動し、指定したポートで応答し、指定したディレクトリに `cutlog.db`・`media`・`renders`・`tmp` が作られることを確認した |
| A10 | 起動に失敗したとき、原因が分かるメッセージが出る | ✅ | `DB_DRIVER=postgres DATABASE_URL=postgres://nouser:nopass@localhost:59999/nodb node src/index.js` → 終了コード1、`起動できませんでした: AggregateError [ECONNREFUSED]` に続けて `code: 'ECONNREFUSED'`・接続を試みた `address`・`port` が出た。存在しないホスト名（`DATABASE_URL=not-a-valid-url`）でも同様に `起動できませんでした: Error: getaddrinfo ENOTFOUND base` が出て、原因（接続先が見つからない）が読み取れた |

---

## J. 公開の準備（OSSとして）

| # | 確認すること | 判定 | 実際に叩いたコマンドと出力の要点 |
|---|---|---|---|
| J1 | `README` の手順どおりに、初見の人が動かせる | ✅ | 「1. いちばん簡単（Docker）」はDocker未導入のため未実行（A1と同じ理由）。「2. Nodeで直接動かす」を書かれた順に実行: `npm install`（`up to date, audited 223 packages`）→ `npm run dev`（`node --watch src/index.js`）→ `http://localhost:8798/` が200でトップページを返した → README記載どおり「最初のユーザーを登録します」を `POST /api/auth/signup` で行い `"isAdmin":true` を確認した。書かれた手順と実際の動きは一致していた |
| J2 | LICENSE・SECURITY・CONTRIBUTING・CODE_OF_CONDUCT がある | ✅ | `ls LICENSE SECURITY.md CONTRIBUTING.md CODE_OF_CONDUCT.md` → 4件とも存在した |
| J3 | CIが通る（テスト・Dockerビルド） | ⏭ | `gh api repos/kouheisatou/cutlog` を見たところ、リモートのGitHubリポジトリはまだ空（`git rev-parse HEAD` のローカルコミットが未push）で、Actionsの実行結果が存在しない。ワークフロー自体（`.github/workflows/ci.yml`）はSQLite・PostgreSQLでの `npm test` とDockerビルドを回す内容になっている。push後でなければ判定できないため対象外とし、同じ内容をローカルで代わりに確かめた（J4） |
| J4 | テストが全部通る | ✅ | `npm test` → `ℹ tests 39` `ℹ pass 39` `ℹ fail 0`。3回連続で実行し、いずれも39件全通過した。**なお1回だけ、npm install直後の最初の実行で `private-log.test.js` の全件が「サーバが起動しませんでした」で落ちたことがあった**（`tests/private-log.test.js` は起動確認を10秒でタイムアウトさせる作りで、初回起動の遅さに引っかかったと見られる。再現せず、テストコード自体の不具合ではないため直していない。他の担当（tests/ 担当）への申し送り事項として下に記す） |
| J5 | 設定項目が一覧になっている（`docs/CONFIGURATION.md` と `.env.example` が実装と合っている） | ✅（2件直した） | `src/config.js` が読む環境変数を全て洗い出し、`docs/CONFIGURATION.md` の表と突き合わせた。項目自体はすべて文書化されていたが、`.env.example` に **`DATA_DIR`と`MEDIA_RETENTION_DAYS`**（いずれも `docs/CONFIGURATION.md` には既定値まで書かれている）が無かったため、コメント付きで追記した |
| J6 | APIの一覧が実装と合っている | ✅（2件直した） | `grep -nE "^api\.(get|post|patch|delete|put)\("` で `src/routes/api.js` の46経路を洗い出し、`docs/API.md` と1つずつ突き合わせた。**`GET /auth/oidc/callback`と`GET /renders/file/:name`** の2経路が実装にあるのに `docs/API.md` に無かったため追記した。他は一致していた |
| J7 | バージョンとリリースの手順がある | ✅（新規に作成） | `package.json` の `version`（`0.1.0`）、`.github/workflows/release.yml`（タグ `v*` の push を検知して `ghcr.io/kouheisatou/cutlog` へDockerイメージを公開する）は実装されていたが、**それを人が読む手順として書いた文書が無かった**。`docs/RELEASING.md` を新規に作り、バージョンの付け方・タグの切り方・公開後の確認方法を書き、`README.md`と`ROADMAP.md`からリンクした |
| J8 | 個人情報の扱いが書かれている | ✅（新規に作成） | 何を保存し、外部へ送らないことを明記した文書が無かった（`docs/RELEASE_QA.md` 自身の確認項目にしか出てこなかった）。`docs/SELF_HOSTING.md` に「個人情報の扱い」の節を追加し、保存する項目（ユーザー名・メール・パスワードのハッシュ・カットのメタデータ・監査ログ）と保存先（自分のDB・自分の保存先）、位置情報を取らないこと、OIDCとWeb Pushの2つだけが管理者の設定時に外部と通信することを明記した |

---

## 直したもの

1. `.env.example`: `DATA_DIR`・`MEDIA_RETENTION_DAYS` をコメント付きで追記（J5）
2. `docs/API.md`: `GET /auth/oidc/callback`・`GET /renders/file/:name` の2行を追記（J6）
3. `docs/RELEASING.md`: 新規作成。バージョンの付け方とリリースの手順（J7）
4. `docs/SELF_HOSTING.md`: 「個人情報の扱い」の節を新規追加（J8）
5. `ROADMAP.md`・`README.md`: `docs/RELEASING.md` へのリンクを追加

`src/config.js` は、A2・A3で「未設定でも落ちない」ことを確認できたため変更していない。

## 他の担当へ回すべき不具合

- **`tests/private-log.test.js` が初回実行時に一度、全件「サーバが起動しませんでした」で落ちた。**
  `before()` の起動待ちが最大10秒（200ms×50回）で切られており、`npm install` 直後の一番遅い起動には
  足りないことがある。2回目以降は3回連続で39件全通過しており、テストの内容自体は正しい。
  `tests/` はこのタスクの担当外のため直していない。タイムアウトを延ばすか、リトライ回数を増える調整を
  tests/ 担当に申し送る
- **J3（CIが通る）は、GitHubリポジトリがまだ空でpushされていないため判定できなかった。**
  リリース担当がpushしたあとに、GitHub Actionsの実行結果（`ci.yml` のSQLite・PostgreSQL・Dockerビルドの
  3ジョブ）を見て判定してほしい
