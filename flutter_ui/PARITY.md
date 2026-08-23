# cutlog を Flutter で作り直す — 見比べの手引き

`web/` の画面を正として、Flutter で同じ絵を出す。合っているかは目で見ず、**同じ Chrome で撮った 2 枚を重ねて測る**。

## 一周する

```bash
cd flutter_ui
./tool/parity/run.sh          # 全画面
./tool/parity/run.sh logs     # その画面だけ
```

- `shots/web/` … 本物（正）
- `shots/flutter/` … Flutter
- `shots/diff/` … 違うところを赤で塗った絵
- `shots/probe/` … 本物の DOM の座標と最終スタイル（**数字はここを見る。目で測らない**）

## 測り方

| 名前 | 意味 |
| --- | --- |
| 置き場所 | 8×8 に潰してから比べる。位置・大きさ・色のずれだけが残る。**これが本命** |
| 見える差 | 画素の差が 32 を超えたところ。字の縁のなめらかさは無視する |
| 完全一致でない | 1 でも違う画素。参考値 |

## 撮影の画面だけの決めごと

カメラの映像は、Chrome に**真っ黒の y4m を流し込んで**撮る（`tool/parity/fixtures/black.y4m`、
`run.sh` が無ければ作る）。既定の作り物は動く模様なので、撮るたびに絵が変わって
見比べられない。黒にすると、上に乗る操作だけを測れる。

## 決めごと

- 書体は web・Flutter とも同梱の **Noto Sans JP / Roboto Mono**。端末任せにすると字幅が変わる。
- 余白は画面の幅で変わる（`Space.forWidth`）。390px 幅では `s3=18, s4=16, s5=28, s6=44, gutter=46`。
- 行の高さは CSS の `line-height` をそのまま持つ。Flutter 側は `leadingDistribution: even` で CSS と同じ配り方にする。
- 数字を手で決めない。`shots/probe/*.json` に本物の値がある。

## 作り直しではなく、作り直すところ

`web/` を正として写すのが原則。ただし次の2つは**写さない**。

### day（その日の詳細）— 作り直す

いまの web の再生まわりは作りかけなので、Flutter で組み直す。

- 上に**プレビュー**、その下に**縦の1択スピナー**（ドラム）だけ。他は置かない。
- スピナーの行は、いまのカットの行がそのままドラムの目盛りになった形。
- 真ん中に来たカットが再生される。選ぶ＝再生する。
- **再生バーはプレビューの直下に1本だけ**。行ごとには付けない。
  ★ 行が全部こまかく動くと、どれを見ているのか分からなくなる。
    区切りの帯を時間で動かすのをやめた（137ef7c）のと同じ理由。

### 撮影後の確認画面 — 新しく作る

撮ったものを確かめてから残す画面。いまは撮影の中の帯でしかない。独立した画面にする。

## いまの出来ぐあい

| 画面 | 出来 | 置き場所の差 |
| --- | --- | --- |
| logs（ログ一覧） | できた | 0.56% |
| all（カット一覧） | できた | 0.98% |
| log（カレンダー） | できた | 1.62% |
| settings（設定） | できた | 2.49% |
| auth（ログイン） | できた | 0.57% |
| logset（ログの設定） | できた | 3.30% |
| day（その日） | 作り直した（映像＋ドラム） | 対象外 |
| review（撮影後の確認） | 作った | 対象外 |
| map（マップ） | できた | 43.73%（下記） |
| capture（撮影） | できた | 1.01% |
| logs-add（ログを追加） | できた | 1.01% |
| logs-search（ログを検索） | できた | 1.00% |
| all-search（検索） | できた | 3.00% |
| cut（カットの詳細） | できた | 10.07%（下記） |

## 端末で動かす

### iPhone 実機（release）

```bash
flutter build ios --release --dart-define=CUTLOG_BASE=https://appserver.tail7ca50.ts.net:8787
flutter install --release -d <端末のID>        # flutter devices で調べる
xcrun devicectl device process launch --device <devicectl のID> dev.cutlog.cutlog
```

- 行き先は既存の殻（`native.env`）と同じ Tailscale の口。素の http ではないので、
  外の網からでも届く。
- 手元の網の中で素の http を使うときのために、`NSAllowsLocalNetworking` を入れてある。
  ★ 実機では `localhost` は端末自身を指す。母艦の住所（`ipconfig getifaddr en0`）か
    Tailscale の名前を渡すこと。

### Android

```bash
flutter build apk --debug
```

- ★ Java 25 では Kotlin の道具が版番号を読めずに落ちる（`What went wrong: 25.0.2` だけが出る）。
  JDK 21 を入れて `flutter config --jdk-dir=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home`
  を指してある。
- Android SDK も 36 が要る（`sdkmanager "platforms;android-36"`）。

## iOS シミュレータで動かす

```bash
flutter build ios --simulator --debug --dart-define=CUTLOG_BASE=http://localhost:8787
xcrun simctl boot "iPhone 17 Pro"
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl launch booted dev.cutlog.cutlog
xcrun simctl io booted screenshot /tmp/ios.png
```

- 起動してログイン画面が出るところまで確かめてある（`/tmp/ios3.png`）。
- 鍵（cookie）は web ではブラウザが持つが、端末では誰も持たない。
  `Api` が預かって毎回付ける。ここは `test/api_test.dart` で本物のサーバ相手に試してある。
- ★ 書く所（TextField）は `Material` の下に居ないと組み上がらない。根に透けたものを1枚敷いてある。

## 動くようになったもの

ログイン／ログアウト、ログの作成・参加・改名・1カット長の変更、招待コードの
作り直しとコピー、**撮影→確認→保存（本物のカメラ）**、カットの移動・削除・
ゴミ箱からの復元、コメント、反応、撮影リマインダーの保存とテスト送信、検索の絞り込み。

書き込みは `test/api_test.dart` で本物のサーバ相手に一周させて確かめてある
（作る→直す→移す→消す→戻す→ひとこと→反応→リマインダー）。

## 次にやること（上から順に）

1. **残りの操作**。書き出し（まとめ動画）・共有リンクの一覧・アイコン画像の設定・
   その日のクリップ操作（非表示／コメント）・カット一覧の長押し選択。
2. **web で動画が動かない件**（下の「詰まっているところ」）。これが直ると cut の 10% も消える。
3. **実機で触って確かめる**。シミュレータ／実機でログインし、撮影・地図・つないだ再生まで通す。
4. **細かいずれ潰し**。下の「残っている細かいずれ」を参照。

## 測りきれないもの

- **map の 43% は、ほぼ地図そのものの違い**。web は Leaflet、こちらは flutter_map で、
  束ね方（クラスタ）と寄せ方が完全には一致しない。加えて Leaflet は拡大ボタンと
  出典表示を自分で描く。**ここは数字で追わない**。瓦・ピンの形・数の印・件数の帯が
  合っていれば良しとする。
  - ★ 地図は「出したあとに動かす」と、取りに行きかけた瓦が全部打ち切られ、
    取り直されない（48枚とも打ち切られていた）。寄せは `initialCameraFit` で
    最初から渡すこと。
  - ★ 配り口（`serve.mjs`）に COOP/COEP を付けてはいけない。付けると、よそから
    取ってくる瓦が軒並み弾かれる。

## 詰まっているところ

- **web で動画が始まらない**。`video_player` の `initialize()` が返ってこない。
  素の `<video>` では同じ道の動画が読める（readyState 4）ので、道の側の問題ではない。
  いまはサムネを敷いてしのいでいる。本命は iOS / Android なので、実機で確かめてから直す。

## 残っている細かいずれ

- **cut の 10% は、ほぼ全部が映像の枠の中**。本物は `<video>` の1コマ目、こちらは
  サムネの絵を伸ばして出している。同じ絵ではないので平均で 35 ほど違う。
  web の `video_player` が動くようになれば消える（下の「詰まっているところ」）。
- logset はまだ 3.48%。行ごとに 1〜5px の食い違いが残る。
- 等幅の字が 0.67px ほど下にずれる（`.log-sub`, タブの名前）。書体の縦の取り方の違い。
  `tool/parity` に「一番よく合う ずれ」を測る手が要る（下の測り方を参照）。
- アイコンの線が少し違う。`lib/design/icons.dart` の描き方を詰める。
- `.check` の行は高さの下限が 32px、行の高さは 1.2。いまの `_Label` は 1.7 のままで低い。

### ずれを数で測る

```python
from PIL import Image, ImageChops
a = Image.open('shots/web/logset.png').convert('L')
b = Image.open('shots/flutter/logset.png').convert('L')
box = (100, 300, 1100, 360)          # 端末の画素（CSS px × 3）
best = min(((sum(ImageChops.difference(a.crop(box),
    b.crop((box[0]+dx, box[1]+dy, box[2]+dx, box[3]+dy))).getdata()), dx, dy)
    for dy in range(-9, 10) for dx in range(-9, 10)))
print('ずれ', best[1]/3, best[2]/3, 'CSSpx')
```
