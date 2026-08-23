// CSS のクラスごとの「字の指定」を、そのまま持ってくる。
// ★ line-height は Flutter と CSS で行の余りの配り方が違う。
//   CSS は上下に半分ずつ配る。Flutter の既定は書体の言い分どおりに配る（proportional）。
//   そのままだと 1行ごとに数 px ずつ縦がずれていくので、必ず even にそろえる。
import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// CSS と同じ行の組み方をする土台
TextStyle _base({
  required double fontSize,
  required Color color,
  double? lineHeightPx,
  FontWeight weight = FontWeight.w400,
  double letterSpacing = 0,
  bool mono = false,
  TextDecoration? decoration,
  Color? decorationColor,
  List<Shadow>? shadows,
}) {
  return TextStyle(
    color: color,
    fontSize: fontSize,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: (lineHeightPx ?? fontSize * lineHeight) / fontSize,
    leadingDistribution: TextLeadingDistribution.even,
    fontFamily: mono ? monoFamily : sansFamily,
    fontFamilyFallback: mono ? monoFallback : sansFallback,
    decoration: decoration,
    decorationColor: decorationColor,
    shadows: shadows,
  );
}

/// 画面ごとの色を渡して、CSS のクラス名と同じ名前で引く。
class Typo {
  Typo(this.c);

  final Palette c;

  static Typo of(BuildContext ctx) => Typo(colorsOf(ctx));

  /// body — system-ui 15px / 1.7 / .012em
  TextStyle get body => _base(fontSize: 15, color: c.ink, letterSpacing: 0.18);

  /// .log-name — 15px 600 .01em
  TextStyle get logName => _base(fontSize: 15, color: c.ink, weight: FontWeight.w600, letterSpacing: 0.15);

  /// .log-sub — mono 11px .04em / mute
  TextStyle get logSub => _base(fontSize: 11, color: c.mute, letterSpacing: 0.44, mono: true);

  /// .tab-item span — mono 9px .1em 大文字
  TextStyle get tabLabel => _base(fontSize: 9, color: c.mute, letterSpacing: 0.9, mono: true);

  /// .crumb — mono 11px（スマホ幅）.1em / mute
  TextStyle get crumb => _base(fontSize: 11, color: c.mute, letterSpacing: 1.1, mono: true, lineHeightPx: 24);

  /// .crumb.current — 濃く、太く
  TextStyle get crumbCurrent => crumb.copyWith(color: c.ink, fontWeight: FontWeight.w600);

  /// .section-head / .panel h3 / .screen-body h2 — mono 11px .18em mute 大文字
  TextStyle get sectionHead => _base(fontSize: 11, color: c.mute, letterSpacing: 1.98, mono: true);

  /// .panel h2 — mono 12px .2em 大文字
  TextStyle get panelHead => _base(fontSize: 12, color: c.ink, letterSpacing: 2.4, mono: true);

  /// .btn — mono 11px --track 大文字
  TextStyle get btn => _base(fontSize: 11, color: c.ink, letterSpacing: 11 * track, mono: true,
      decoration: TextDecoration.underline, decorationColor: c.mute);

  /// .mini — mono 10px --track mute 大文字
  TextStyle get mini => _base(fontSize: 10, color: c.mute, letterSpacing: 10 * track, mono: true,
      decoration: TextDecoration.underline, decorationColor: c.mute);

  /// .muted.small
  TextStyle get small => _base(fontSize: 12, color: c.mute, letterSpacing: 0.144);

  /// .empty — 13px .06em mute / 行は 2.1
  TextStyle get empty => _base(fontSize: 13, color: c.mute, letterSpacing: 0.78, lineHeightPx: 13 * 2.1);

  /// .cut-row .tc / .clip-row .tc — 12px .06em
  TextStyle get timeCode => _base(fontSize: 12, color: c.inkSoft, letterSpacing: 0.72, mono: true);

  /// .clip-row .n — 14px
  TextStyle get clipName => _base(fontSize: 14, color: c.ink, letterSpacing: 0.168);

  /// .clip-row .k — mono 10px .08em mute
  TextStyle get clipKind => _base(fontSize: 10, color: c.mute, letterSpacing: 0.8, mono: true);

  /// .cal-day .d — mono 11px mute
  TextStyle get calDay => _base(fontSize: 11, color: c.mute, mono: true);

  /// .cal-dow — 10px .1em mute
  TextStyle get calDow => _base(fontSize: 10, color: c.mute, letterSpacing: 1);

  /// .cal-month-head strong — mono 13px 600 .12em
  TextStyle get calMonth => _base(fontSize: 13, color: c.ink, weight: FontWeight.w600, letterSpacing: 1.56, mono: true);

  /// .brand — 等幅 20px 500 .22em（大文字にはしない）
  /// ★ .brand は等幅の一覧に入っている。地の書体で出すと字幅がまるごと変わる。
  TextStyle get brand =>
      _base(fontSize: 20, color: c.ink, weight: FontWeight.w500, letterSpacing: 4.4, mono: true);

  /// .form label — mono 11px .14em mute 大文字
  TextStyle get formLabel => _base(fontSize: 11, color: c.mute, letterSpacing: 1.54, mono: true);

  /// .form input — 16px .02em
  TextStyle get formInput => _base(fontSize: 16, color: c.ink, letterSpacing: 0.32);

  /// .tab（ログイン画面の切り替え）— 11px mute
  TextStyle get authTab => _base(fontSize: 11, color: c.mute, letterSpacing: 1.76, mono: true);

  /// .check — mono 11px .12em mute 大文字。行の高さだけ 1.2（他より詰まっている）
  TextStyle get check => _base(fontSize: 11, color: c.mute, letterSpacing: 1.32, mono: true,
      lineHeightPx: 11 * 1.2);

  /// .panel-row label — mono 11px .12em mute 大文字
  TextStyle get panelLabel => _base(fontSize: 11, color: c.mute, letterSpacing: 1.32, mono: true);

  /// .panel-row input — 14px
  TextStyle get panelInput => _base(fontSize: 14, color: c.ink, letterSpacing: 0.168);

  /// .photo-cell .cap — mono 10px .04em 白
  TextStyle get photoCap => _base(fontSize: 10, color: light, letterSpacing: 0.4, mono: true);

  /// .chip — mono 11px .14em 白 大文字
  TextStyle get chip => _base(fontSize: 11, color: light, letterSpacing: 1.54, mono: true, shadows: <Shadow>[chipShadow]);
}

/// CSS の text-transform: uppercase。
/// ★ 日本語には効かないが、英数字の並びは大文字になる。
///   ここを通さないと「CUTLOG」が「cutlog」のまま出て、字幅ごと変わってしまう。
String upper(String s) => s.toUpperCase();
