# cutlog（Flutter）

`web/` の cutlog を、Flutter で作り直したもの。**web・iOS・Android を1つの元から出す**。

## すぐ動かす

```bash
# 1. サーバを起こす（別の窓で）
cd .. && npm start                     # http://localhost:8787

# 2. 中身を入れる（初回だけ。見比べ用の捨てアカウントを作る）
cd flutter_ui && node tool/parity/seed.mjs

# 3. 動かす
flutter run -d chrome                  # ブラウザ
flutter run -d <端末のID>               # 実機・シミュレータ（flutter devices で調べる）
```

つなぎ先は `.env` の `CUTLOG_BASE` で決まる。決め方は **組み立ての指定 → `.env` → 同じ出どころ**。

| 出す先 | `CUTLOG_BASE` |
| --- | --- |
| web（同じサーバから配る） | 空のまま |
| iOS シミュレータ | `http://localhost:8787` |
| Android エミュレータ | `http://10.0.2.2:8787` |
| 実機 | 母艦の住所（`ipconfig getifaddr en0`）か Tailscale の名前 |

> ★ 実機で `localhost` は端末自身を指す。母艦は見えない。

## 中身の並び

```
lib/
  main.dart          入口。.env を読み、読み上げの仕組みを要るなら立ち上げる
  app.dart           画面の行き来。どのタブ・どの深さに居るかはここが持つ
  design/            見た目の素。web/styles.css をそのまま写したもの
    tokens.dart        色・余白（画面幅で変わる）・書体
    text.dart          CSS のクラスごとの字の指定
    icons.dart         web/index.html の <symbol> を、その d のまま描く
  data/              サーバとのやりとり
  ui/                部品（帯・札・押しどころ・余白の重なり）
  screens/           画面
tool/parity/         本物と重ねて測る仕掛け（下記）
```

## 決めごと

- **見た目の正は `web/`**。数字は目で測らず、`tool/parity` で本物の DOM から吸い出した値に合わせる。
- 書体は web・Flutter とも同梱の **Noto Sans JP / Roboto Mono**。端末任せにすると字幅が変わる。
- 余白は画面の幅で変わる（`Space.forWidth`）。390px 幅では `s3=18, s4=16, s5=28, s6=44`。
- 縦のマージンは**隣り合うと重なって1つになる**（`CssColumn`）。足し合わせると下ほどずれが積み上がる。
- 行の高さは CSS の `line-height` をそのまま。`leadingDistribution: even` で CSS と同じ配り方にする。

## 確かめ方

```bash
flutter analyze && flutter test        # 組み上がるか・寸法が合っているか
./tool/parity/run.sh                   # 本物と重ねて測る（全画面）
node tool/parity/walk.mjs              # 実際に触って一通り動かす
python3 tool/parity/walk_check.py shots  # 着いた先が正しい画面か判を押す
```

- `shots/web/` … 本物（正）
- `shots/flutter/` … Flutter
- `shots/diff/` … 違うところを赤く塗った絵
- `shots/walk/` … 触った各手順の絵
- `shots/probe/` … 本物の DOM の座標と最終スタイル（**数字はここを見る**）

いまの一致ぐあいと、残っていることは [PARITY.md](PARITY.md) にまとめてある。

## 通知（Firebase）

サーバ側の設えは `../.env.example` の「iOS / Android のアプリへ通知を出す」を参照。
アプリ側には、同じ企画（Firebase プロジェクト）から落とした設定ファイルを置く。

```
android/app/google-services.json
ios/Runner/GoogleService-Info.plist
```

置かなければ、通知だけを諦めて他はそのまま動く。

## 詰まりやすいところ

| 症状 | 訳 |
| --- | --- |
| Android が `What went wrong: 25.0.2` だけ出して落ちる | Java 25 では Kotlin の道具が版番号を読めない。JDK 21 を入れ、`flutter config --jdk-dir=...` で指す |
| 札（モーダル）が開くのに何も出ない | 配色を配る仕組みが道案内より内側に居る。`MaterialApp.builder` で外側から配る |
| 地図の瓦が出ない | 出したあとに動かしている。寄せは `initialCameraFit` で最初から渡す。配り口に COOP/COEP を付けない |
| web で動画が始まらない | `video_player` の初期化が返ってこない（web のみ）。サムネで代替してある |
