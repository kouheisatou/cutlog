// 撮影。web の #captureDialog をそのまま写す。
// ★ 横（16:9）で撮るのが基本。画面ごと回転させる作りはしない（縦持ちのとき帯状に潰れる）。
//   縦持ちでは撮れる範囲だけを見せ、操作は正しい向きのまま下に置く。
// ★ 文字と選択肢は置かない。進み具合はシャッターの輪だけで知らせる。
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../design/icons.dart';
import '../design/text.dart';
import '../design/tokens.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key, this.destination, this.preview, this.onClose});

  /// どのログへ入るか
  final String? destination;

  /// 端末のカメラの映像。無ければ黒いまま。
  final Widget? preview;

  final VoidCallback? onClose;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> with SingleTickerProviderStateMixin {
  /// 1カットの長さ。CSS の --cut-seconds（既定 2s）にあたる。
  static const Duration _cutLength = Duration(seconds: 2);

  /// よく使う倍率だけ。増やすと押しにくくなる。
  static const List<double> _stops = <double>[1, 2, 4];

  late final AnimationController _ring = AnimationController(vsync: this, duration: _cutLength);
  double _zoom = 1;

  bool get _recording => _ring.isAnimating;

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  void _shoot() {
    if (_recording) return;
    _ring.forward(from: 0);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final Space sp = spaceOf(context);
    final EdgeInsets safe = MediaQuery.paddingOf(context);

    return ColoredBox(
      color: camBackdrop,
      child: Stack(
        children: <Widget>[
          // CSS: .cam-stage — 撮れる範囲をそのまま見せる（縦持ちでは上下に黒が残る）
          Positioned.fill(
            child: ColoredBox(
              color: camBackdrop,
              child: widget.preview ?? const SizedBox.expand(),
            ),
          ),

          // CSS: .capture-top
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                sp.s3, safe.top > sp.s2 ? safe.top : sp.s2, sp.s3, sp.s2,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0x8C000000), Color(0x00000000)],
                ),
              ),
              child: Row(
                children: <Widget>[
                  _LightBtn('close', onTap: widget.onClose),
                  SizedBox(width: sp.s2),
                  if ((widget.destination ?? '').isNotEmpty) Flexible(child: _CapDest(widget.destination!)),
                  SizedBox(width: sp.s2),
                  const Spacer(),
                  if (!_recording) const _LightBtn('flip'),
                ],
              ),
            ),
          ),

          // CSS: .capture-controls — 操作は下にまとめる。指の届くところに、順番どおり。
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                sp.s3, sp.s3, sp.s3, safe.bottom > sp.s3 ? safe.bottom : sp.s3,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: <Color>[Color(0x99000000), Color(0x00000000)],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _ZoomRow(zoom: _zoom, stops: _stops, onZoom: (double v) => setState(() => _zoom = v)),
                  SizedBox(height: sp.s2),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Row(
                      children: <Widget>[
                        const Expanded(child: Align(alignment: Alignment.centerLeft, child: _FileChip())),
                        _Shutter(ring: _ring, recording: _recording, onTap: _shoot),
                        const Expanded(
                          child: Align(alignment: Alignment.centerRight, child: _Chip('動画', opacity: .55)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// CSS: .icon-btn.light — 白、少しだけ薄く。
class _LightBtn extends StatelessWidget {
  const _LightBtn(this.icon, {this.onTap});

  final String icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(child: Opacity(opacity: .9, child: Ic(icon, color: light))),
      ),
    );
  }
}

/// CSS: .cap-dest — 等幅ではなく地の書体。下線は 4px 下げる。
class _CapDest extends StatelessWidget {
  const _CapDest(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 32),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Opacity(
          opacity: .85,
          child: Text(
            '記録先 $name',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: light,
              fontFamily: sansFamily,
              fontSize: 11,
              height: lineHeight,
              leadingDistribution: TextLeadingDistribution.even,
              letterSpacing: tracking(11, .06),
              decoration: TextDecoration.underline,
              decorationColor: light,
            ),
          ),
        ),
      ),
    );
  }
}

/// CSS: .zoom-row — 倍率・つまみ・目印の順。
class _ZoomRow extends StatelessWidget {
  const _ZoomRow({required this.zoom, required this.stops, required this.onZoom});

  final double zoom;
  final List<double> stops;
  final ValueChanged<double> onZoom;

  /// 端末が寄れる範囲は 1 から始まらないことがあるので、いちばん引いた状態を 1.0 として見せる
  static String _label(double v) {
    final String s = ((v * 10).round() / 10).toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  @override
  Widget build(BuildContext context) {
    final Space sp = spaceOf(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Row(
        children: <Widget>[
          // CSS: .zoom-now
          Container(
            constraints: const BoxConstraints(minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: pillBackdrop, borderRadius: BorderRadius.circular(999)),
            child: Text(
              '${_label(zoom)}×',
              style: TextStyle(
                color: light,
                fontFamily: monoFamily,
                fontFamilyFallback: monoFallback,
                fontSize: 11,
                height: lineHeight,
                leadingDistribution: TextLeadingDistribution.even,
              ),
            ),
          ),
          SizedBox(width: sp.s2),
          // ★ 素の <input type=range> は写しきれない。Chrome の見え方に寄せてある。
          Expanded(child: _ZoomSlider(value: zoom, onChanged: onZoom)),
          SizedBox(width: sp.s2),
          // CSS: .zoom-stops
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (int i = 0; i < stops.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: 4),
                _Pill(
                  text: '${_label(stops[i])}×',
                  active: (stops[i] - zoom).abs() < .05,
                  onTap: () => onZoom(stops[i]),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// CSS: .zoom-stop — 34×28 の粒。選ばれているものだけ反転する。
class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.active, this.onTap});

  final String text;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minWidth: 34, minHeight: 28),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? light : pillBackdrop,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: active ? pillActiveInk : light,
            fontFamily: monoFamily,
            fontFamilyFallback: monoFallback,
            fontSize: 10,
            height: lineHeight,
            leadingDistribution: TextLeadingDistribution.even,
          ),
        ),
      ),
    );
  }
}

/// Chrome の range（accent-color:#fff）に寄せたつまみ。
class _ZoomSlider extends StatelessWidget {
  const _ZoomSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (DragUpdateDetails d) {
          final RenderBox box = context.findRenderObject()! as RenderBox;
          final double at = (d.localPosition.dx / box.size.width).clamp(0, 1);
          onChanged(1 + at * 3);
        },
        child: CustomPaint(painter: _SliderPainter((value - 1) / 3)),
      ),
    );
  }
}

class _SliderPainter extends CustomPainter {
  const _SliderPainter(this.at);

  final double at;

  @override
  void paint(Canvas canvas, Size size) {
    final double y = size.height / 2;
    const double track = 4;
    final RRect line = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, y - track / 2, size.width, track),
      const Radius.circular(2),
    );
    canvas.drawRRect(line, Paint()..color = const Color(0xFFE9E9ED));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, y - track / 2, size.width * at, track),
        const Radius.circular(2),
      ),
      Paint()..color = light,
    );
    canvas.drawCircle(Offset(size.width * at, y), 8, Paint()..color = light);
  }

  @override
  bool shouldRepaint(_SliderPainter old) => old.at != at;
}

/// CSS: .chip — 等幅・大文字・字間 .14em。落ち影で映像から浮かせる。
class _Chip extends StatelessWidget {
  const _Chip(this.text, {this.opacity = .8});

  final String text;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          upper(text),
          style: TextStyle(
            color: light,
            fontFamily: monoFamily,
            fontFamilyFallback: monoFallback,
            fontSize: 11,
            height: lineHeight,
            leadingDistribution: TextLeadingDistribution.even,
            letterSpacing: tracking(11, .14),
            shadows: <Shadow>[chipShadow],
          ),
        ),
      ),
    );
  }
}

/// CSS: .chip.file — 端末の動画から選ぶ。押せる範囲は 44px。
/// ★ .ic.sm には margin-right:8px が付くので、中身は中心より少し左に寄る。
///   web と並べたときにずれて見えるので、その 8px もそのまま持ってくる。
class _FileChip extends StatelessWidget {
  const _FileChip();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Opacity(
        opacity: .8,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Ic('plus', size: 13, color: light),
          ),
        ),
      ),
    );
  }
}

/// CSS: .shutter — 78px の丸。中の赤い粒は 58px。
/// 撮っているあいだ、外側の輪が時計回りに一周する。ちょうど1カットぶんの長さ。
class _Shutter extends StatelessWidget {
  const _Shutter({required this.ring, required this.recording, required this.onTap});

  final Animation<double> ring;
  final bool recording;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double dot = recording ? 26 : 58;
    final double radius = recording ? 6 : 29;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 78,
        height: 78,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Positioned.fill(
              child: AnimatedBuilder(
                animation: ring,
                builder: (BuildContext context, Widget? child) =>
                    CustomPaint(painter: _RingPainter(ring.value)),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.ease,
              width: dot,
              height: dot,
              decoration: BoxDecoration(color: shutterRed, borderRadius: BorderRadius.circular(radius)),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    // SVG は viewBox 100 のなかに r=45・stroke-width 6 で描かれている
    final double k = size.width / 100;
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double r = 45 * k;
    final double width = 6 * k;

    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = const Color(0x52FFFFFF),
    );

    if (progress <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      -math.pi / 2,                    // CSS 側は svg ごと -90deg 回してある
      2 * math.pi * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..color = light,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}
