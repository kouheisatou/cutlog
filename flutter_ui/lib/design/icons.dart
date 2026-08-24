// web/index.html の <symbol> を、そのままの形で描く。
// ★ 座標を書き写すと、写し違いが必ず起きる。
//   SVG の d の文字列をそのまま持ってきて、その場で読み解いて描くことにした。
//   元の HTML から貼るだけでよく、線の太さも角の丸みも元と同じになる。
import 'package:flutter/widgets.dart';

/// viewBox 24 のなかの図形。d の文字列と、円・四角をそのまま持つ。
class _Glyph {
  const _Glyph(this.paths, {this.circles = const <List<double>>[], this.rects = const <List<double>>[], this.round = true});

  final List<String> paths;
  final List<List<double>> circles;   // [cx, cy, r]
  final List<List<double>> rects;     // [x, y, w, h, (rx)]
  final bool round;                   // 線の端を丸めるか（stroke-linecap: round）
}

/// 塗りで描くもの（再生・一時停止）だけは別に持つ
class _Filled {
  const _Filled(this.paths, {this.rects = const <List<double>>[]});
  final List<String> paths;
  final List<List<double>> rects;
}

const Map<String, _Glyph> _glyphs = <String, _Glyph>{
  'settings': _Glyph(<String>['M4 7h9M17 7h3M4 17h3M11 17h9'],
      circles: <List<double>>[<double>[15, 7, 2.2], <double>[9, 17, 2.2]]),
  'close': _Glyph(<String>['M6 6l12 12M18 6L6 18']),
  'flip': _Glyph(<String>[
    'M20 11a8 8 0 0 0-13.7-5.6L4 7.6',
    'M4 4v3.6h3.6',
    'M4 13a8 8 0 0 0 13.7 5.6L20 16.4',
    'M20 20v-3.6h-3.6',
  ]),
  'back': _Glyph(<String>['M14 6l-6 6 6 6']),
  'prev': _Glyph(<String>['M14 6l-6 6 6 6']),
  'next': _Glyph(<String>['M10 6l6 6-6 6']),
  'film': _Glyph(<String>['M7 5v14M17 5v14M3 12h4M17 12h4M3 8.5h4M17 8.5h4M3 15.5h4M17 15.5h4'],
      rects: <List<double>>[<double>[3, 5, 18, 14]], round: false),
  'photo': _Glyph(<String>['M8 6l1.4-2h5.2L16 6'],
      circles: <List<double>>[<double>[12, 12.5, 3.4]],
      rects: <List<double>>[<double>[3, 6, 18, 13]], round: false),
  'download': _Glyph(<String>['M12 4v11M8 11l4 4 4-4M4 19h16']),
  'share': _Glyph(<String>['M9.2 10.9l5.7-3.4M9.2 13.1l5.7 3.4'],
      circles: <List<double>>[<double>[17, 6, 2.4], <double>[7, 12, 2.4], <double>[17, 18, 2.4]]),
  'merge': _Glyph(<String>['M10 7h4a3 3 0 0 1 3 3v1M10 17h4a3 3 0 0 0 3-3v-1', 'M17 8l3 3-3 3'],
      rects: <List<double>>[<double>[3, 4, 7, 6], <double>[3, 14, 7, 6]]),
  'trash': _Glyph(<String>['M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 11v6M14 11v6']),
  'copy': _Glyph(<String>['M15 9V4H4v11h5'], rects: <List<double>>[<double>[9, 9, 11, 11]], round: false),
  'search': _Glyph(<String>['M15.5 15.5L20 20'], circles: <List<double>>[<double>[11, 11, 6]]),
  'plus': _Glyph(<String>['M12 5v14M5 12h14']),
  'move': _Glyph(<String>['M3 12h11M10 8l4 4-4 4'], rects: <List<double>>[<double>[15, 5, 6, 14]]),
  'camera': _Glyph(<String>['M8 6l1.4-2h5.2L16 6'],
      circles: <List<double>>[<double>[12, 12.5, 3.6]],
      rects: <List<double>>[<double>[3, 6, 18, 13, 1]], round: false),
  // 選んだ印。web は CSS の傾けた線で描いている。同じ形を線で引く。
  'check': _Glyph(<String>['M5 12.5l5 5 9-10']),
  'list': _Glyph(<String>['M4 6h16M4 12h16M4 18h16']),
  'grid': _Glyph(<String>[], rects: <List<double>>[
    <double>[3, 3, 7.5, 7.5], <double>[13.5, 3, 7.5, 7.5],
    <double>[3, 13.5, 7.5, 7.5], <double>[13.5, 13.5, 7.5, 7.5],
  ], round: false),
  'eye': _Glyph(<String>['M2.5 12S6 6 12 6s9.5 6 9.5 6-3.5 6-9.5 6-9.5-6-9.5-6z'],
      circles: <List<double>>[<double>[12, 12, 3]], round: false),
  'eye-off': _Glyph(<String>[
    'M4 4l16 16',
    'M9.5 6.4A9.9 9.9 0 0 1 12 6c6 0 9.5 6 9.5 6a17 17 0 0 1-3.3 3.9M6.6 8.2A17 17 0 0 0 2.5 12S6 18 12 18a9.6 9.6 0 0 0 3.2-.5',
    'M9.9 9.9a3 3 0 0 0 4.2 4.2',
  ], round: false),
  'sound': _Glyph(<String>['M4 9.5h3.5L12 6v12l-4.5-3.5H4z', 'M15.5 9a4 4 0 0 1 0 6'], round: false),
  'mute': _Glyph(<String>['M4 9.5h3.5L12 6v12l-4.5-3.5H4z', 'M16 10l4 4M20 10l-4 4'], round: false),
  'expand': _Glyph(<String>['M9 4H4v5M15 4h5v5M9 20H4v-5M15 20h5v-5']),
  // 全画面をやめる。expand の矢を内向きに返したもの。
  'collapse': _Glyph(<String>['M4 9h5V4M20 9h-5V4M4 15h5v5M20 15h-5v5']),
  'comment': _Glyph(<String>['M4 5h16v11H9l-5 4z'], round: false),
  'pin': _Glyph(<String>['M12 21s7-6.3 7-11a7 7 0 1 0-14 0c0 4.7 7 11 7 11z'],
      circles: <List<double>>[<double>[12, 10, 2.6]], round: false),
  'lock': _Glyph(<String>['M8.5 11V8a3.5 3.5 0 0 1 7 0v3'],
      rects: <List<double>>[<double>[6, 11, 12, 9]], round: false),
};

const Map<String, _Filled> _filled = <String, _Filled>{
  'play': _Filled(<String>['M8 5.5v13l11-6.5z']),
  'pause': _Filled(<String>[], rects: <List<double>>[<double>[7, 5.5, 3.4, 13], <double>[13.6, 5.5, 3.4, 13]]),
};

/// CSS の .ic は 17px、.ic.sm は 13px。
class Ic extends StatelessWidget {
  const Ic(this.name, {super.key, this.size = 17, this.color, this.strokeWidth = 1.6});

  const Ic.sm(this.name, {super.key, this.color, this.strokeWidth = 1.6}) : size = 13;

  final String name;
  final double size;
  final Color? color;

  /// .tab-item.active .ic は 1.9 に太る
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _IconPainter(name, color ?? const Color(0xFF101012), strokeWidth),
      ),
    );
  }
}

class _IconPainter extends CustomPainter {
  const _IconPainter(this.name, this.color, this.strokeWidth);

  final String name;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24);

    final _Filled? solid = _filled[name];
    if (solid != null) {
      final Paint fill = Paint()..color = color;
      for (final String d in solid.paths) {
        canvas.drawPath(parseSvgPath(d), fill);
      }
      for (final List<double> r in solid.rects) {
        canvas.drawRect(Rect.fromLTWH(r[0], r[1], r[2], r[3]), fill);
      }
      canvas.restore();
      return;
    }

    final _Glyph g = _glyphs[name] ?? _glyphs['close']!;
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = g.round ? StrokeCap.round : StrokeCap.butt
      ..strokeJoin = StrokeJoin.round;

    for (final String d in g.paths) {
      canvas.drawPath(parseSvgPath(d), stroke);
    }
    for (final List<double> c in g.circles) {
      canvas.drawCircle(Offset(c[0], c[1]), c[2], stroke);
    }
    for (final List<double> r in g.rects) {
      final Rect rect = Rect.fromLTWH(r[0], r[1], r[2], r[3]);
      if (r.length > 4) {
        canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(r[4])), stroke);
      } else {
        canvas.drawRect(rect, stroke);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.name != name || old.color != color || old.strokeWidth != strokeWidth;
}

// ── SVG の d を読み解く ────────────────────────────────
// M L H V C S Q T A Z（大文字＝絶対、小文字＝相対）。cutlog の絵はこれで足りる。
// ★ 曲線を落とすと、目やピンの形が崩れたまま気付けない。
//   反射（S / T）は直前の制御点を折り返して作るので、その点を持ち回る。
Path parseSvgPath(String d) {
  final Path path = Path();
  final RegExp token = RegExp(r'[MmLlHhVvCcSsQqTtAaZz]|-?\d*\.?\d+(?:[eE]-?\d+)?');
  final List<String> bits = token.allMatches(d).map((RegExpMatch m) => m[0]!).toList();

  double x = 0, y = 0, startX = 0, startY = 0;
  double ctrlX = 0, ctrlY = 0;      // 直前の制御点（反射に使う）
  String cmd = 'M';
  String lastCmd = 'M';
  int i = 0;

  final RegExp letter = RegExp(r'^[A-Za-z]$');
  double n() => double.parse(bits[i++]);

  while (i < bits.length) {
    if (letter.hasMatch(bits[i])) {
      cmd = bits[i++];
      if (cmd == 'Z' || cmd == 'z') {
        path.close();
        x = startX;
        y = startY;
        lastCmd = cmd;
        continue;
      }
      if (i >= bits.length) break;
    }
    switch (cmd) {
      case 'M':
        x = n(); y = n(); path.moveTo(x, y); startX = x; startY = y; cmd = 'L';
        break;
      case 'm':
        x += n(); y += n(); path.moveTo(x, y); startX = x; startY = y; cmd = 'l';
        break;
      case 'L':
        x = n(); y = n(); path.lineTo(x, y);
        break;
      case 'l':
        x += n(); y += n(); path.lineTo(x, y);
        break;
      case 'H':
        x = n(); path.lineTo(x, y);
        break;
      case 'h':
        x += n(); path.lineTo(x, y);
        break;
      case 'V':
        y = n(); path.lineTo(x, y);
        break;
      case 'v':
        y += n(); path.lineTo(x, y);
        break;
      case 'C':
      case 'c':
        {
          final bool rel = cmd == 'c';
          final double x1 = (rel ? x : 0) + n(), y1 = (rel ? y : 0) + n();
          final double x2 = (rel ? x : 0) + n(), y2 = (rel ? y : 0) + n();
          final double ex = (rel ? x : 0) + n(), ey = (rel ? y : 0) + n();
          path.cubicTo(x1, y1, x2, y2, ex, ey);
          ctrlX = x2; ctrlY = y2; x = ex; y = ey;
          break;
        }
      case 'S':
      case 's':
        {
          final bool rel = cmd == 's';
          // 直前が三次曲線なら、その制御点を折り返す。そうでなければ今の点をそのまま使う。
          final bool smooth = <String>['C', 'c', 'S', 's'].contains(lastCmd);
          final double x1 = smooth ? 2 * x - ctrlX : x;
          final double y1 = smooth ? 2 * y - ctrlY : y;
          final double x2 = (rel ? x : 0) + n(), y2 = (rel ? y : 0) + n();
          final double ex = (rel ? x : 0) + n(), ey = (rel ? y : 0) + n();
          path.cubicTo(x1, y1, x2, y2, ex, ey);
          ctrlX = x2; ctrlY = y2; x = ex; y = ey;
          break;
        }
      case 'Q':
      case 'q':
        {
          final bool rel = cmd == 'q';
          final double x1 = (rel ? x : 0) + n(), y1 = (rel ? y : 0) + n();
          final double ex = (rel ? x : 0) + n(), ey = (rel ? y : 0) + n();
          path.quadraticBezierTo(x1, y1, ex, ey);
          ctrlX = x1; ctrlY = y1; x = ex; y = ey;
          break;
        }
      case 'T':
      case 't':
        {
          final bool rel = cmd == 't';
          final bool smooth = <String>['Q', 'q', 'T', 't'].contains(lastCmd);
          final double x1 = smooth ? 2 * x - ctrlX : x;
          final double y1 = smooth ? 2 * y - ctrlY : y;
          final double ex = (rel ? x : 0) + n(), ey = (rel ? y : 0) + n();
          path.quadraticBezierTo(x1, y1, ex, ey);
          ctrlX = x1; ctrlY = y1; x = ex; y = ey;
          break;
        }
      case 'A':
      case 'a':
        {
          final double rx = n(), ry = n();
          n();                                   // 回転（cutlog では常に 0）
          final bool largeArc = n() != 0;
          final bool sweep = n() != 0;
          if (cmd == 'A') { x = n(); y = n(); } else { x += n(); y += n(); }
          path.arcToPoint(
            Offset(x, y),
            radius: Radius.elliptical(rx, ry),
            largeArc: largeArc,
            clockwise: sweep,
          );
          break;
        }
      default:
        i++;                                     // 知らない字は読み飛ばす
    }
    lastCmd = cmd;
  }
  return path;
}
