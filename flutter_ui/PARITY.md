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
| logs（ログ一覧） | できた | 0.59% |
| all（カット一覧） | できた | 1.92% |
| log（カレンダー） | できた | 2.57% |
| settings（設定） | できた | 2.67% |
| auth（ログイン） | できた | 3.43% |
| logset（ログの設定） | できた | 5.23% |
| day（その日） | 作り直した（映像＋ドラム） | 対象外 |
| review（撮影後の確認） | 作った | 対象外 |
| map（マップ） | まだ | — |
| capture（撮影） | 下書きあり（`tool/parity/capture_screen.dart.wip`） | — |
| logs-add（ログを追加） | できた | 1.84% |
| logs-search（ログを検索） | できた | 1.56% |
| all-search（検索） | できた | 2.63% |
| cut（カットの詳細） | まだ | — |

## 次にやること（上から順に）

1. **cut（カットの詳細のシート）**。`lib/ui/sheet.dart` の器に載せる。中身は
   映像・題・操作・反応・値の表・コメント。`shots/probe/cut.json` に座標がある。
2. **map**。地図そのものは外の部品に任せる（web は Leaflet 同梱）。
   Flutter では `flutter_map` を足すか、まずピンと件数の帯だけ作って地図は後回しでもよい。
3. **capture**。`tool/parity/capture_screen.dart.wip` に下書きがある。
   ただし余白の変数が古い（`s1` などの直書き）ので、`spaceOf(context)` に直してから使う。
4. **画面のつなぎ込み**。いまは `?shot=` で1枚ずつ出しているだけ。
   タブと戻るを本当に動かして、行き来できるようにする。
5. **細かいずれ潰し**。下の「残っている細かいずれ」を参照。

## 詰まっているところ

- **web で動画が始まらない**。`video_player` の `initialize()` が返ってこない。
  素の `<video>` では同じ道の動画が読める（readyState 4）ので、道の側の問題ではない。
  いまはサムネを敷いてしのいでいる。本命は iOS / Android なので、実機で確かめてから直す。

## 残っている細かいずれ

- **logset で行ごとに 5px ほど下へずれていく**（積み上がって最後は 15px ほど）。
  行の高さか、行間の重なりの計算がどこかで 1 行ぶん多い。まず `shots/probe/logset.json` の
  `div.panel-row` の y を並べて、どの行から離れ始めるかを見ること。
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
