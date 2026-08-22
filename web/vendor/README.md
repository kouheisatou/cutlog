# vendor

外から持ってきたものを、そのまま置いてあります。
ビルド工程を挟まないという方針なので、CDNから読むのではなく同梱しています。
（CDNから読むと、外へ通信が出ますし、Content-Security-Policy も緩めることになります）

| もの | 版 | 出どころ | 何に使うか |
|---|---|---|---|
| Leaflet | 1.9.4 | https://leafletjs.com/ (BSD-2-Clause) | マップの画面 |
| Leaflet.markercluster | 1.5.3 | https://github.com/Leaflet/Leaflet.markercluster (MIT) | 近いピンをまとめる |

更新するときは、同じ版のファイルを上書きしてください。中身には手を入れていません。
