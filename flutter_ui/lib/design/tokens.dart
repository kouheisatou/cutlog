// cutlog の見た目の素（web/styles.css の :root と @media）を、そのまま Dart に写したもの。
// ★ 画面側に生の数値を書かず、必ずここを通す。
// ★ 余白の刻みは画面の幅で変わる。web は @media で書き換えているので、こちらも同じ所で折る。
//   これを忘れると、スマホの幅で全部の余白が広すぎる絵になる。
import 'package:flutter/widgets.dart';

// ── 色（--paper … --sel-ink）───────────────────────────
class Palette {
  const Palette({
    required this.paper,
    required this.paper2,
    required this.ink,
    required this.inkSoft,
    required this.mute,
    required this.hair,
    required this.sel,
    required this.selInk,
  });

  final Color paper;
  final Color paper2;
  final Color ink;
  final Color inkSoft;
  final Color mute;
  final Color hair;
  final Color sel;
  final Color selInk;

  static const Palette lightMode = Palette(
    paper: Color(0xFFFFFFFF),
    paper2: Color(0xFFF6F6F4),
    ink: Color(0xFF101012),
    inkSoft: Color(0xFF4A4B50),
    mute: Color(0xFF6E6E74),
    hair: Color(0xFFE8E8E5),
    sel: Color(0xFF101012),
    selInk: Color(0xFFFFFFFF),
  );

  static const Palette darkMode = Palette(
    paper: Color(0xFF0D0D0F),
    paper2: Color(0xFF17171A),
    ink: Color(0xFFF4F4F2),
    inkSoft: Color(0xFFB8B8B5),
    mute: Color(0xFF909096),
    hair: Color(0xFF232326),
    sel: Color(0xFFF4F4F2),
    selInk: Color(0xFF0D0D0F),
  );
}

// ── 余白の刻み（--s1 … --s6, --gutter）─────────────────
class Space {
  const Space(this.s1, this.s2, this.s3, this.s4, this.s5, this.s6, this.gutter);

  final double s1, s2, s3, s4, s5, s6, gutter;

  /// web の @media と同じ所で折る。狭い方が後から上書きする。
  factory Space.forWidth(double w) {
    double s3 = 24, s4 = 32, s5 = 48, s6 = 72, gutter = 92;
    if (w <= 1100) { s5 = 36; s6 = 56; }
    if (w <= 880) { gutter = 58; s3 = 18; s4 = 20; s5 = 28; s6 = 44; }
    if (w <= 480) { gutter = 46; s4 = 16; }
    return Space(8, 16, s3, s4, s5, s6, gutter);
  }
}

// ── 撮影の画面だけで使う色（黒地に白で固定）──────────
const Color camBackdrop = Color(0xFF000000);
const Color light = Color(0xFFFFFFFF);
const Color shutterRed = Color(0xFFE5484D);
const Color pillBackdrop = Color(0x80000000);
const Color pillActiveInk = Color(0xFF111111);
const Color reviewBackdrop = Color(0xE60D0D0F);

// ── 字 ────────────────────────────────────────────────
/// CSS の --mono（同梱の Roboto Mono）
const String monoFamily = 'Roboto Mono';
const List<String> monoFallback = <String>['Noto Sans JP'];

/// CSS の --sans（同梱の Noto Sans JP）
const String sansFamily = 'Noto Sans JP';
const List<String> sansFallback = <String>['Roboto Mono'];

/// body の line-height（数のまま子へ伝わる）
const double lineHeight = 1.7;

/// --track
const double track = .16;

/// CSS の em 指定の字間を px へ直す
double tracking(double fontSize, double em) => fontSize * em;

/// CSS の blur 半径（σ の 2 倍）を Flutter の blurRadius へ直す
double blurFromCss(double cssBlur) => (cssBlur / 2 - 0.5) / 0.57735;

/// chip の落ち影。CSS: 0 1px 4px rgba(0,0,0,.7)
final Shadow chipShadow = Shadow(
  offset: const Offset(0, 1),
  blurRadius: blurFromCss(4),
  color: const Color(0xB3000000),
);

// ── 画面ごとに配る ─────────────────────────────────────
class Skin extends InheritedWidget {
  const Skin({super.key, required this.palette, required this.space, required super.child});

  final Palette palette;
  final Space space;

  static Skin of(BuildContext context) {
    final Skin? s = context.dependOnInheritedWidgetOfExactType<Skin>();
    assert(s != null, 'Skin が上に居ません');
    return s!;
  }

  @override
  bool updateShouldNotify(Skin old) => old.palette != palette || old.space != space;
}

Palette colorsOf(BuildContext c) => Skin.of(c).palette;
Space spaceOf(BuildContext c) => Skin.of(c).space;
