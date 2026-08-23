// cutlog を Flutter で作り直したもの。web / iOS / Android を1つの元から出す。
// ★ 見た目の正は web/（styles.css と index.html）。
//   数字は目で測らず、tool/parity で本物の DOM から吸い出した値に合わせる。
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app.dart';

/// 読み上げの取っ手。手放すと畳まれるので、動いているあいだ持ち続ける。
// ignore: unused_element
SemanticsHandle? _a11y;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // つなぎ先などの設え。無くても動く（同じ出どころを見る）。
  try {
    await dotenv.load();
  } catch (_) {
    // .env が無い組み立てでも止めない
  }
  // 読み上げの仕組み。ふだんは端末が要ると判断したときだけ立ち上がるが、
  // 外から掴んで試すときは常に要るので、設えで先に立ち上げられるようにしてある。
  // ★ 返ってくる取っ手を持ち続けないと、すぐ畳まれてしまう（読み上げの木が空になる）。
  if (dotenv.env['CUTLOG_A11Y'] == '1' ||
      const String.fromEnvironment('CUTLOG_A11Y') == '1') {
    _a11y = SemanticsBinding.instance.ensureSemantics();
  }
  runApp(const CutlogApp());
}
