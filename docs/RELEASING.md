# バージョンとリリースの手順

## バージョンの付け方

`package.json` の `version` が正本です（SemVer）。破壊的な変更は最初の数字を上げ、
機能追加は2番目、直しだけなら3番目を上げます。作った機能と次に作るものは
[ROADMAP.md](../ROADMAP.md) にバージョンごとの一覧があります。

## リリースの手順

1. `main` で `npm test` が通ることを確かめる
2. `package.json` の `version` を上げてコミットする
3. `git tag vX.Y.Z && git push origin vX.Y.Z` でタグを push する
4. タグを検知して [.github/workflows/release.yml](../.github/workflows/release.yml) が動き、
   Dockerイメージを `ghcr.io/kouheisatou/cutlog` へ `linux/amd64` と `linux/arm64` の両方で公開する
5. GitHubの Releases に、上げた内容を書く（現時点では自動生成のCHANGELOGはない）

## 確認

- `docker pull ghcr.io/kouheisatou/cutlog:vX.Y.Z` でイメージが取れることを見る
- タグを付ける前の通常のpushでは、[.github/workflows/ci.yml](../.github/workflows/ci.yml) が
  テスト（SQLite・PostgreSQL）とDockerビルドの確認だけを行い、公開はしない
