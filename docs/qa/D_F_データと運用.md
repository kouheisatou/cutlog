# D（データ）・F（運用）の確認結果

実施日: 2026-08-22 / 実施範囲: `docs/RELEASE_QA.md` の D1〜D9・F1〜F10
検証環境: Windows 11 / Node.js v24.14.1 / ffmpeg 8.1（実機同梱）/ Docker・PostgreSQL・MinIOはこの環境に無し
検証サーバ: 8787は他担当が使用中のため、8792・8793・8794・18792〜18810 など未使用のポートを都度確認して使用した。
DATA_DIRはすべて `scratchpad/qa-*` 配下の専用ディレクトリを使い、リポジトリ本体の `data/` には触れていない。

---

## 判定の一覧

| # | 項目 | 判定 |
|---|---|---|
| D1 | SQLiteで動く | ✅ |
| D2 | PostgreSQLで動く | ⏭（Docker・PostgreSQLが環境に無し。コード洗い出しで代替） |
| D3 | ストレージをS3互換に切り替えて動く | ⏭（Docker・MinIOが環境に無し。コード洗い出しで代替） |
| D4 | バックアップと復元の手順が実際に通る | ✅（手順書を本ファイルに作成し、実際に通した） |
| D5 | 消したカットが戻せる | ✅ |
| D6 | 容量の上限を設定でき、超えたら止まる | ✅（止まる。ただし応答の粗さを検出） |
| D7 | ディスクが満杯になったときに、データが壊れない | ✅（壊れない。ただし一時ファイルの残留を検出） |
| D8 | 同じ内容を二重に登録しない | ❌ |
| D9 | 時差をまたいでも現地の日付でまとまる | ✅ |
| F1 | `/api/healthz` が生死を正しく返す | ❌ |
| F2 | Dockerのヘルスチェックが機能する | ⏭（Dockerが環境に無し。コマンド自体は検証済み） |
| F3 | 複数台で動く（ワーカーを分けられる） | ✅ |
| F4 | 同じジョブが二重に処理されない | ✅（検証中に別の不具合を発見し修正） |
| F5 | ログが読める形で出る | ✅ |
| F6 | 再起動してもデータが残る | ✅ |
| F7 | リバースプロキシの後ろで動く | ❌ |
| F8 | 一時ファイルが溜まり続けない | ✅（まとめ動画の経路は溜まらない。D7と同じ穴が別経路にある） |
| F9 | 古いセッションが自動で消える | ✅ |
| F10 | 監査ログに、誰が何をしたかが残る | ✅（restoreだけ記録が漏れている） |

---

## D. データ

### D1 ✅ SQLiteで動く

既定設定（`DATA_DIR` のみ指定、`DB_DRIVER` は未指定）で起動。

```
PORT=8792 DATA_DIR=<scratch>/qa-data-d1 node src/index.js
```

ログに `[db] applied 001_init.sql` 〜 `003_private_log_unique.sql` が出て、`/api/healthz` が
`{"ok":true,"db":"sqlite","storage":"local"}` を返した。同じディレクトリで2回目に起動しても
`applied` は出ず、二重にマイグレーションが走らないことも確認した（A5相当）。

### D2 ⏭ PostgreSQLで動く

この環境には `docker` コマンドが無く（`docker --version` が `command not found`）、
`psql` などPostgreSQL本体も入っていない。PowerShellでも同様に確認し、Docker Desktopの
サービスも見当たらなかった。よって実機での検証は断念し、代わりに `src/db/index.js` の方言吸収層と
全SQLを突き合わせて「PostgreSQLで落ちそうな箇所」を洗い出した。結果は本ファイル末尾の
「PostgreSQLで落ちそうな箇所」を参照。目立った危険箇所は無く、コードは概ねPostgreSQL安全な書き方で
統一されていた（詳細は末尾）。

### D3 ⏭ ストレージをS3互換に切り替えて動く

同じ理由でMinIOも立てられなかった（`docker` が無い）。`src/storage/index.js` を読み、
S3経路のコードを洗い出した。1点、構造的な欠陥を見つけた（下記）。詳細は末尾の
「S3切り替えで落ちそうな箇所」を参照。

**見つけた欠陥: まとめ動画の出力は `STORAGE_DRIVER=s3` でもローカルディスク固定**

`src/storage/index.js` の末尾:

```js
export const storage = config.storage.driver === 's3'
  ? new S3Storage(config.storage.s3)
  : new LocalStorage(paths.media);

export const renderStorage = new LocalStorage(paths.renders);
```

素材（写真・動画）はS3に切り替えられるが、まとめ動画の出力先 `renderStorage` は常に
ローカルディスクになる。さらに配布側の `src/routes/api.js` の `/api/renders/file/:name` は
`storage` 抽象を経由せず `path.join(paths.renders, name)` を直接 `res.sendFile` している
（api.jsは今回の担当外のため確認のみ）。

このため、F3のように複数台（Web用とワーカー用、あるいはロードバランサ配下の複数Web）を
S3で構成した場合、まとめ動画を作った台とは別の台にリクエストが飛ぶと、そのファイルは
存在せず404になる。素材はS3で複数台から見えるのに、まとめ動画だけは作った台に閉じ込められる。

直し方の案（`src/storage/index.js` だけでは完結しない）:
1. `renderStorage` も `config.storage.driver === 's3'` のとき `S3Storage` を使うようにする
   （`src/storage/index.js` 側は今回対応可能）。
2. `src/routes/api.js` の `/api/renders/file/:name` を、直接 `sendFile` する代わりに
   `renderStorage.stream(name)` を使うように直す（担当外のため未対応。再現手順のみ報告）。
   1だけ直しても2が直らない限り効果が出ないため、今回は見送り、報告のみとした。

### D4 ✅ バックアップと復元の手順が実際に通る

`docs/SELF_HOSTING.md` は別担当が編集中のため、正式な手順書はそちらに委ね、
ここには検証した手順案だけを書く。

**バックアップ手順案（SQLite + ローカルストレージの場合）**

1. サービスを止める（`docker compose stop app` あるいはプロセスを終了する）。
   SQLiteはWALモードのため、`cutlog.db` 本体だけでなく `cutlog.db-wal` ・ `cutlog.db-shm`
   も含めて3ファイルをまとめて退避する（止めずに `cutlog.db` だけをコピーすると、
   コミット前の内容が `-wal` 側に残っていて欠落する恐れがある）。
2. `DATA_DIR` 配下をまるごとコピーする（`cutlog.db*` ・ `media/` ・ `renders/`）。
   `tmp/` はレンダリング中の断片なのでバックアップ対象に含めなくてよい。
3. 退避先を別ディスク・別ホストへ移す。

**復元手順案**

1. 空の `DATA_DIR` を用意し、バックアップの `cutlog.db*` ・ `media/` ・ `renders/` を
   そのまま配置する。
2. 同じ `DATA_DIR` を指定してサービスを起動する。マイグレーションは
   `schema_migrations` テーブルの記録により再実行されない。

**実際に通した内容**

- `qa-data-d1` を停止し、`cutlog.db` ・ `cutlog.db-shm` ・ `cutlog.db-wal` ・ `media/` ・
  `renders/` を別ディレクトリへ `cp -r` で複製した。
- 複製先を `DATA_DIR` に指定し、新しいポートで起動した
  （`PORT=8795 DATA_DIR=<restore> node src/index.js`。**1回目は未使用のはずのポートが
  別プロセスに使われていて `EADDRINUSE` になり、無関係な既存サーバの応答を自分の結果と
  誤認しかけた。ポートを変えて再実行し、`netstat` でPIDが自分の起動したプロセスと一致する
  ことを確認してから検証をやり直した**）。
- 複製先のサーバで、元のサーバで発行したセッションCookieのまま `/api/me` がログイン状態を返し、
  `/api/logs/:id/cuts` が同じカット一覧を返し、`/api/media/:id` が同じバイト数
  （3660バイトの動画）でファイルを返すことを確認した。バックアップと復元は機能している。

### D5 ✅ 消したカットが戻せる

1. カットを `DELETE /api/cuts/:cutId` で削除 → 一覧から消え、`GET /api/logs/:logId/trash`
   に現れる。
2. `POST /api/cuts/:cutId/restore` → 一覧に戻る。

4件のカットで確認し、期待どおりに動いた。

### D6 ✅（応答の粗さあり） 容量の上限を設定でき、超えたら止まる

`MAX_UPLOAD_MB=1` で起動し、3MBのファイルをアップロードした。

```
{"error":"File too large"}
HTTP 500
```

サーバログに `MulterError: File too large (code: LIMIT_FILE_SIZE)`。
**アップロードは確かに止まり、カットの行も作られず、`media/` にファイルも残らなかった。
コア要件（超えたら止まる）は満たしている。**

一方で、応答が本来あるべき `413 Payload Too Large` ではなく `500` になっており、
メッセージも他のエラーのような日本語（「〜してください」）ではなく英語の生の
Multerメッセージがそのまま返っている。原因はmulterのエラーが `src/routes/api.js` の
`upload.single('file')` ミドルウェアから直接 `next(err)` され、`src/index.js` の汎用エラーハンドラ
（`err.status || 500`）に落ちるため。両方とも今回の担当外のファイルのため直していない。
直し方の案: `src/routes/api.js` 側にmulter専用のエラーハンドラを足し、
`err.code === 'LIMIT_FILE_SIZE'` のとき413と日本語メッセージを返す。

### D7 ✅（一時ファイル残留あり） ディスクが満杯になったときに、データが壊れない

書き込み先を読み取り専用にする代わりに、Windowsの `icacls` で `media/` フォルダへの
書き込みだけを拒否し、ディスク満杯を模した。

```
icacls <media> /deny "GMO\usr0107095:(OI)(CI)(W,WD,AD)"
```

この状態でアップロードすると:

```
{"error":"EPERM: operation not permitted, copyfile '...\\tmp\\...' -> '...\\media\\c_....jpg'"}
HTTP 500
```

**カットの行はDBに作られず（半端な行は残らない）、`cuts` 一覧も変化しなかった。
データの整合性は壊れていない。** ACLは検証後に `icacls /remove:d` で元に戻した。

一方で、`tmp/` ディレクトリに書きかけの一時ファイル（アップロード本体＋サムネイル）が
残り続けることを確認した。

```
tmp/5424fa15dd560147fcc89e1e66b4e44e  (674 bytes, アップロード本体)
tmp/c_8uBxAGc3FDUB_thumb.jpg          (674 bytes, サムネイル)
```

原因は `src/routes/api.js` の `createCut`（該当箇所は概ね330行目付近）で、

```js
await storage.put(key, tmpFile);
if (gotThumb) await storage.put(thumbKey, thumbTmp);
await fsp.unlink(tmpFile).catch(() => {});
await fsp.unlink(thumbTmp).catch(() => {});
```

という順で書かれており、`storage.put` が例外を投げると後続の2つの `unlink` が実行されず、
一時ファイルが `tmp/` に残り続ける。ディスク満杯が続く運用では、この一時ファイルの蓄積が
「満杯の原因を自分で増やす」形になり、F8（一時ファイルが溜まり続けない）にも波及する。
`src/routes/api.js` は担当外のため直していないが、直し方は明確で、
`try { ...put... } finally { ...unlink... }` に変えるだけでよい。

### D8 ❌ 同じ内容を二重に登録しない

同じ動画ファイル（`clip1.mp4`）を2回アップロードした。

```
1回目: {"id":"c_dNt_cC7QS1gY", ..., "checksum":"7b1589...ae6ad"}
2回目: {"id":"c_k-NOcjeqcoAY", ..., "checksum":"7b1589...ae6ad"}  ← 同じchecksum
```

`media/` を見ると、`c_dNt_cC7QS1gY.mp4` と `c_k-NOcjeqcoAY.mp4` の両方が実体として存在し
（どちらも3660バイト、内容は同一）、`cuts` テーブルにも2行できていた。

**checksumは記録されるが、重複を検知して止める・まとめる仕組みが無い。** 同じ動画を
何度もアップロードするたびにディスク容量を消費する。原因は `src/routes/api.js` の `createCut` に
「既存の同じchecksumを探す」処理が無いこと。直し方の案:
アップロード前に `SELECT id FROM cuts WHERE log_id = ? AND checksum = ? AND deleted_at IS NULL`
で既存カットを探し、見つかれば新規保存をやめて既存カットを返す（またはユーザーに選ばせる）。
`src/routes/api.js` は担当外のため直していない。

### D9 ✅ 時差をまたいでも現地の日付でまとまる

3パターンで確認した（`tzOffset` はJavaScriptの `getTimezoneOffset()` の符号）。

| takenAt (UTC) | tzOffset | 想定される現地日付 | 実際の `localDate` |
|---|---|---|---|
| 2026-08-22T15:30:00Z | -540（JST, UTC+9） | 08-23 00:30 → **08-23** | 2026-08-23 ✅ |
| 2026-08-22T18:35:00Z | -330（IST, UTC+5:30） | 08-23 00:05 → **08-23** | 2026-08-23 ✅ |
| 2026-08-23T02:00:00Z | +300（UTC-5） | 08-22 21:00 → **08-22** | 2026-08-22 ✅ |

UTC日付をまたぐ・またがない両方向、UTCより進む・遅れる両方向で正しく現地日付に
まとまることを確認した。

---

## F. 運用

### F1 ❌ `/api/healthz` が生死を正しく返す

`src/routes/api.js` の実装は次のとおり（該当箇所のみ確認、変更はしていない）。

```js
api.get('/healthz', asyncRoute(async (req, res) => {
  await db.get('SELECT 1 AS ok');
  res.json({ ok: true, db: db.driver, storage: storage.driver, time: nowIso() });
}));
```

`SELECT 1 AS ok` はテーブルに触らないリテラル問い合わせのため、SQLite接続オブジェクトが
存在していれば、実際のDBファイルが壊れていても成功してしまう。これを実際に確認した。

1. 動作中のサーバに対し、`cutlog.db` を0バイトに上書き（`fs.writeFileSync(path, '')`）。
2. その後 `/api/healthz` を叩いても `{"ok":true,"db":"sqlite",...}` のまま。
3. さらに新規ユーザーの登録・ログの一覧取得も成功した（WALと内部キャッシュにより
   実害が表面化しなかった面もあるが、少なくとも `healthz` は本当の破損を検知できていない）。

PostgreSQLを使う場合は `SELECT 1` でも実際にサーバへの接続往復が発生するため、
接続断は検知できる可能性が高い。**SQLite運用時に限り、この項目は実質的に機能しない。**
直し方の案: `SELECT 1 AS ok` の代わりに実テーブルへの軽い問い合わせ
（例: `SELECT 1 AS ok FROM schema_migrations LIMIT 1`）に変える。
`src/routes/api.js` は担当外のため直していない。

### F2 ⏭ Dockerのヘルスチェックが機能する

この環境に `docker` が無く、`docker ps` の `healthy` 表示は確認できなかった。
代わりに `Dockerfile` の `HEALTHCHECK` に書かれているコマンドをそのまま手で実行し、
ロジック自体が正しく動くことは確認した。

```js
node -e "fetch('http://127.0.0.1:18792/api/healthz').then(r=>{console.log('status',r.status); process.exit(r.ok?0:1)})"
→ status 200 / 終了コード 0
```

Dockerを使った統合的な `healthy` 表示までは検証できていない。

### F3 ✅ 複数台で動く（ワーカーを分けられる）

同じ `DATA_DIR`（同じSQLiteファイル）を指す3プロセスを起動した。

- A: `PORT=18792`（既定、ワーカー動作）
- B: `PORT=18793` `RENDER_WORKER=false`（Web専用）
- C: `PORT=18794`（ワーカー動作、2台目）

Bからまとめ動画を6件連続で依頼し、実際にレンダリングを処理したのはA・Cのみで、
Bはジョブを一切処理しなかった（`jobs.locked_by` を見るとAまたはCのプロセスIDしか現れない）。
Web専用インスタンスがレンダリングをしない、という設計が機能している。

### F4 ✅（検証中に不具合を発見・修正） 同じジョブが二重に処理されない

上記A・Cの2ワーカーで、Bから合計6件のまとめ動画ジョブを依頼し、完了を待った。

```
jobs（kind='render_timeline'）: 6件すべて status='done', attempts=0
renders/ の出力ファイル数: 6件（重複無し）
locked_by は A・CのプロセスIDが交互に付き、同一ジョブが2ワーカーに同時に取られた形跡は無い
```

SQLiteでも「`UPDATE ... WHERE status='queued'` の変更行数で判定する」方式
（`src/jobs/queue.js` の `claimOne`）により、正しく排他されている。

**検証の途中で、別の不具合を見つけて修正した（`src/jobs/queue.js`、担当範囲内）。**

`startWorker()` の起動時の「落ちた処理を拾い直す」処理が、次のように
自分自身の `WORKER_ID`（`hostname:pid`）でしか検索していなかった。

```js
// 修正前
db.run(`UPDATE jobs SET status = 'queued', locked_by = NULL WHERE status = 'running' AND locked_by = ?`,
  [WORKER_ID]);
```

`WORKER_ID` は再起動のたびにPIDが変わるため、**前回のプロセスが `running` のまま残した
ジョブは、次に起動したどのプロセスからも `locked_by` が一致せず、二度と拾われない**。
実際に次の手順で再現した。

1. ジョブを1件処理させ、完了後にDBを直接書き換えて `status='running',
   locked_by='deadhost:11111', locked_at=（10分より前）` に強制的に戻す
   （ワーカーがクラッシュした状態を模した）。
2. サーバを終了し、同じ `DATA_DIR` を指して新しいプロセスで再起動。
3. 修正前のコードでは、再起動後も `status='running', locked_by='deadhost:11111'` のまま
   変化せず、そのジョブは永久にワーカーへ取られなかった。

**修正**: `WORKER_ID` による絞り込みをやめ、`locked_at` の古さ（既定15分、
`JOB_STALE_MINUTES` で調整可）で判定するようにした。他のワーカーが今まさに処理中の
ジョブ（`locked_at` が新しい）は奪わない。起動時1回だけでなく、5分おきに繰り返し確認する
ようにも変えた（1プロセスがずっと生き続け、別プロセスだけがクラッシュするケースにも対応）。

```js
// 修正後（src/jobs/queue.js）
async function recoverStale() {
  const threshold = new Date(Date.now() - STALE_RUNNING_MS).toISOString();
  await db.run(
    `UPDATE jobs SET status = 'queued', locked_by = NULL
      WHERE status = 'running' AND (locked_at IS NULL OR locked_at < ?)`,
    [threshold],
  ).catch(() => {});
}
```

修正後、同じ再現手順で「再起動後にジョブが自動的に再キューされ、そのまま完了する」ことを
確認した。さらにA・B・Cの3プロセスを修正後のコードで再起動し、F3/F4の6件テストを
再実行して、退行が無いことも確認した（6件依頼→12件目まで、すべて `done` / `attempts=0`、
出力ファイル数も一致）。

### F5 ✅ ログが読める形で出る

起動時: `cutlog: http://localhost:8792 で待ち受けます（DB=sqlite / 保存先=local）`。
ジョブ関連: `[jobs] ワーカーを開始しました（同時実行 1）`、
マイグレーション: `[db] applied 001_init.sql`、
エラー時: `[error] Error: EPERM: ...`（D7で確認）。すべて標準出力（stdout/stderr）に出て、
`docker logs` で読める形（1行1メッセージ、タイムスタンプ不要な短文）になっている。

### F6 ✅ 再起動してもデータが残る

D4の検証で使ったサーバを、テスト中に一度 `MAX_UPLOAD_MB` を変えるために再起動している
（同じ`DATA_DIR`）。再起動後も既存のセッション・カット・ログがすべて引き続き見え、
新規登録もでき、マイグレーションも再実行されなかった。ボリューム（`DATA_DIR`）を
維持していれば再起動でデータが消えないことを確認した。

### F7 ❌ リバースプロキシの後ろで動く

`TRUST_PROXY` を設定せず（既定false、プロキシの背後にいない想定）、
偽装した `X-Forwarded-For` ヘッダを付けてアップロードした。

```
curl -H "X-Forwarded-For: 203.0.113.99" -X POST .../cuts ...
→ audit_log.ip = "203.0.113.99"（クライアントが名乗った値がそのまま記録された）
```

`src/index.js` の `app.set('trust proxy', 1)` は `TRUST_PROXY=true` のときだけ有効になるが、
実際のIP記録・書き込みレート制限は `src/routes/api.js` の独自コードが担っており、
Expressの`trust proxy`設定を経由していない。

```js
// src/routes/api.js の audit() とレート制限ミドルウェア（いずれも同様の書き方）
(req.headers['x-forwarded-for'] || req.socket.remoteAddress || '').toString()
```

`config.trustProxy` の値を一切見ていないため、**リバースプロキシの背後にいなくても、
クライアントが送ってきた `X-Forwarded-For` を無条件に信用してしまう**。これは
「プロキシの背後で正しいIPになる」だけでなく「プロキシが無いときに勝手には信用しない」も
含めて確認すべき項目であり、後者が成立していない。監査ログの発信元記録も
書き込みレート制限（G4）も、このヘッダを送るだけで偽装・回避できてしまう。
直し方の案: `config.trustProxy` が真のときだけ `x-forwarded-for` を見る
（Expressの `req.ip`（`app.set('trust proxy', ...)` 済み）を使うのが素直）。
`src/routes/api.js` は担当外のため直していない。

### F8 ✅（別経路に穴あり） 一時ファイルが溜まり続けない

F3/F4の検証でまとめ動画を合計12件作成した後、`tmp/` を確認した。

```
tmp/ に残っていたのは D7 の時点で残った2ファイルのみ（新規のレンダリング関連ファイルは0件）
```

`src/jobs/render.js` の `renderTimeline` は、パーツ動画・結合用リストファイル・
文字焼き込み用テキストファイルを、成功時に `Promise.all(...unlink...)` でまとめて
削除しており、12件処理してもレンダリング経路からの残留は無かった。

一方、D7で見つけた「アップロード失敗時に `tmp/` の一時ファイルが残る」問題
（`src/routes/api.js` のcreateCut、try/finallyになっていない）は、そのままF8にも当てはまる。
アップロードの失敗が繰り返される運用では `tmp/` が肥大化し続ける。担当外のため直していない
（再現手順・直し方はD7の項目を参照）。

### F9 ✅ 古いセッションが自動で消える

`src/index.js` の `startJanitor()` が1時間おきに
`DELETE FROM sessions WHERE expires_at < ?` を実行するよう `setInterval` で組まれている
ことをコードで確認した。1時間待つのは非現実的なため、期限切れのセッション行を1件直接挿入し、
janitorが実行する同じSQLを直接実行して、期限切れの行だけが消え、有効な行は残ることを確認した。

```
before cleanup: [有効token, 期限切れtoken]
DELETE FROM sessions WHERE expires_at < now() → 1行削除
after cleanup: [有効tokenのみ]
```

掃除のクエリ自体は正しく動く。間隔が1時間固定で環境変数化されていない点は運用上の
細かい改善余地だが、機能としては満たしている。

### F10 ✅（restoreの記録漏れあり） 監査ログに、誰が何をしたかが残る

これまでの検証操作（ログ作成・カット作成・カット削除）は、いずれも `audit_log` に
`action` / `target` / `ip` / `created_at` が記録されることを確認した。

```
log.create, cut.create ×4, cut.delete → すべて記録あり
```

一方、`POST /api/cuts/:cutId/restore`（D5で使用）だけは `src/routes/api.js` の実装を見ると
`audit(...)` の呼び出しが無く、ゴミ箱から復元した操作は監査ログに残らない。
「削除は記録されるが復元は記録されない」非対称な状態になっている。
`src/routes/api.js` は担当外のため直していないが、`restore` ハンドラの中で
`delete` と同様に `await audit(req, 'cut.restore', c.id);` を1行足すだけで直る。

---

## PostgreSQLで落ちそうな箇所（D2の代替調査）

`src/db/index.js` の `toPgSql()`（`?` → `$n` への機械的な置換）と、全SQLを突き合わせて
確認した。マイグレーション（`001_init.sql` 〜 `003_private_log_unique.sql`）には
`-- @sqlite` / `-- @postgres` の方言分岐マーカーが1つも使われておらず、
**全SQLが両方言で無変更のまま流れる前提で書かれている**。

**確認できた、既に安全な設計（要修正ではない）**
- `RETURNING` は一度も使われていない。INSERT後は必ず別の `SELECT ... WHERE id = ?` で
  取り直しており、SQLiteとPostgreSQLの `RETURNING` 対応差を最初から回避している。
- `FOR UPDATE SKIP LOCKED` は `src/jobs/queue.js` の `claimOne()` で
  `db.driver === 'postgres'` のときだけ使われ、SQLiteでは条件付き `UPDATE` の
  変更行数判定に分岐している。設計は正しい（実機テスト自体はできていない）。
- boolean列を作らず、`is_admin` ・ `disabled` ・ `archived` ・ `allow_download` など
  すべてINTEGER（0/1）で統一している。PostgreSQLの `boolean` 型との不一致による
  型エラーは起きにくい。
- `ALTER TABLE ... ADD COLUMN col TEXT NOT NULL DEFAULT '...'`（002番）、
  部分ユニーク索引 `CREATE UNIQUE INDEX ... WHERE kind = 'private'`（003番）は、
  いずれもPostgreSQLでも通る構文。SQLite側は今回の検証で実際に適用できることを確認済み。
- `ORDER BY CASE WHEN l.kind = 'private' THEN 0 ELSE 1 END, l.created_at DESC` は
  標準的なSQLで、PostgreSQLでも問題なく通る。
- `?` の埋め込みはすべてバインドパラメータとしての使用で、SQL文字列側に
  リテラルの `?`（`LIKE` パターン中の `?` など）は見当たらなかった。
  `toPgSql()` の単純な逐次置換で壊れる箇所は無いと見ている。

**気になる点（未検証・要注意）**
- `src/jobs/queue.js` の `db.tx()` は、PostgreSQL側は `pool.connect()` で専用クライアントを
  取得する実装になっている。`PG_POOL_MAX`（既定10）に対し、`RENDER_CONCURRENCY` や
  同時アクセス数が大きい環境で、プールが枯渇して `claimOne` がブロックする可能性がある
  （実機で負荷をかけないと確認できない）。
- `SqliteDb.run()` は node:sqlite の `.run()` の戻り値をそのまま返し、`PostgresDb.run()` は
  `{ changes: r.rowCount }` を明示的に作っている。両者が呼び出し側の期待する
  `.changes` プロパティを同じ意味で持つことは、SQLite側は今回の検証（`claimOne` の動作）で
  確認できたが、PostgreSQL側の `rowCount` が同じ意味で一致するかは実機未確認。
- `PostgresDb.tx()` 内で例外が起きた場合の `ROLLBACK` 漏れは無いように見えるが、
  `client.release()` を呼ぶ前に例外が起きるケースの網羅は実機のエラー注入でしか確認できない。

総じて、コードレベルでは方言差を吸収する意図が一貫しており、危険な書き方は
見当たらなかった。**最終的な合否は実機でのD2実施が必須**であり、この洗い出しは
その代替にはならない。

## S3切り替えで落ちそうな箇所（D3の代替調査）

`src/storage/index.js` を確認した。

- **（本文で既述）まとめ動画の出力 `renderStorage` が常にローカルディスク固定**で、
  S3に切り替えても素材だけがS3へ行き、書き出し結果はローカルに残る。複数台構成で
  問題になる（詳細は上のD3項目）。
- `S3Storage.getPath()` は、ffmpegがローカルファイルしか読めないことに対応して
  `paths.tmp` へダウンロードしてキャッシュしているが、**このキャッシュファイルを
  削除する処理が無い**。同じキャッシュファイル名（`s3_${basename}`）を使う限り
  再利用はされるが、削除されたカットや使われなくなった素材のキャッシュは
  `tmp/` に残り続ける。長期運用でS3を使うと `tmp/` が肥大化する。
  F8（一時ファイルが溜まり続けない）にも関わる。
- `forcePathStyle` の既定値が `true`（`S3_FORCE_PATH_STYLE` 未設定時）になっており、
  MinIOなど多くのS3互換実装で必要な設定が既定でオンになっている点は良い。
  一方、AWS S3本体を使う場合はバケット名によってはpath-styleが使えないことがあり、
  `S3_FORCE_PATH_STYLE=false` を明示する必要がある（ドキュメント側の記載の要否は
  今回の担当外）。
- `S3Storage.put()` / `putBuffer()` は成功・失敗にかかわらず特別なリトライを行わない。
  ネットワークが不安定な環境でアップロードが部分的に失敗した場合の挙動
  （AWS SDKの既定リトライに委ねている）は実機未確認。
- 認証情報を `accessKeyId` が設定されているときだけ明示的に渡し、無いときは
  `credentials: undefined` としてSDKの既定プロバイダチェーン（環境変数・IAMロール等）に
  委ねる作りになっている。これは自己ホストで環境変数を使う分には妥当だが、
  実機（MinIOなど実際の認証情報）での通信確認ができていない。

いずれもコード上の懸念であり、**実機（MinIO等）でのD3実施が必須**である点は
D2と同様である。
