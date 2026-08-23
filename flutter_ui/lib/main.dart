// cutlog を Flutter で作り直したもの。web / iOS / Android を1つの元から出す。
// ★ 見た目の正は web/（styles.css と index.html）。
//   数字は目で測らず、tool/parity で本物の DOM から吸い出した値に合わせる。
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // つなぎ先などの設え。無くても動く（同じ出どころを見る）。
  try {
    await dotenv.load();
  } catch (_) {
    // .env が無い組み立てでも止めない
  }
  runApp(const CutlogApp());
}
