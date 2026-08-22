# cutlog に参加する

**「使いにくいところを直す」プロジェクトです。** 気づいた不便は、そのままIssueにしてください。

## まず動かす

```bash
git clone https://github.com/kouheisatou/cutlog.git
cd cutlog
npm install
cp .env.example .env
npm run dev      # http://localhost:8787
```

必要なもの: **Node.js 22以上**（`node:sqlite` を使うため）と、まとめ動画を試すなら **ffmpeg**。
**ビルド工程はありません。**フロントは素のESモジュールなので、保存して再読み込みすれば反映されます。

## 決めごと（少しだけ）

1. **依存は増やさない。** 標準ライブラリで書けるものは標準で書く。追加するときはIssueで理由を書く
2. **ビルドを挟まない。** フロントにバンドラを入れない（誰でもすぐ直せる状態を保つ）
3. **SQLite でも PostgreSQL でも動く SQL を書く。** 方言は `src/db/` に閉じ込める
4. **UIの日本語は素直に。** 体言止めを避け、主語と述語をそろえる
5. **プライバシーを既定で守る。** 位置情報は取らない。メタデータは書き出しで消せるようにする

## Pull Request の流れ

1. Issue を立てる（または既存のIssueに「やります」とコメント）
2. ブランチを切る（`feat/...` `fix/...` `docs/...`）
3. `npm test` が通ることを確かめる
4. PRを出す。**画面が変わるときはスクリーンショットを貼る**

## 動作を確かめる

```bash
npm test                     # APIの結合テスト（SQLite）
DB_DRIVER=postgres DATABASE_URL=postgres://... npm test   # PostgreSQL でも
```

CIでは SQLite と PostgreSQL の両方で走ります。

## どこから手をつけるか

`good first issue` のラベルが付いたものが入口です。[ROADMAP.md](ROADMAP.md) に、これから作るものを並べています。
