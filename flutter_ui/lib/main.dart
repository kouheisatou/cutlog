// cutlog を Flutter で作り直したもの。web / iOS / Android を1つの元から出す。
// ★ 見た目の正は web/（styles.css と index.html）。
//   数字は目で測らず、tool/parity で本物の DOM から吸い出した値に合わせる。
import 'package:flutter/widgets.dart';

import 'app.dart';

void main() {
  runApp(const CutlogApp());
}
