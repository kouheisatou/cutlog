// 押すもの・書くもの。CSS の .btn / .mini / .form / .panel-row の見た目をそのまま持つ。
// ★ cutlog は「囲まない」作り。押せることは、下線と余白だけで示す。
//   ここで枠を足すと、画面ぜんぶの手ざわりが変わってしまう。
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/text.dart';
import '../design/tokens.dart';

/// CSS: .btn — 等幅・大文字・下線。押せる高さは 44px を確保する。
class TextBtn extends StatelessWidget {
  const TextBtn(this.label, {super.key, this.onTap, this.icon, this.block = false, this.danger = false});

  final String label;
  final VoidCallback? onTap;
  final String? icon;
  final bool block;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Typo t = Typo(c);
    final TextStyle style = t.btn.copyWith(color: danger ? const Color(0xFFC0392B) : c.ink);

    final Widget row = Row(
      mainAxisSize: block ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: block ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Ic(icon!, size: 13, color: style.color),
          SizedBox(width: spaceOf(context).s1),      // CSS: .ic.sm { margin-right: var(--s1) }
        ],
        Text(upper(label), style: style),
      ],
    );

    // ★ 名前を付ける。読み上げに要るのはもちろん、
    //   絵で描く画面を外から掴んで試すときの手がかりにもなる。
    return Semantics(
      button: true,
      label: label,
      enabled: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Align(
            alignment: Alignment.center,
            widthFactor: block ? null : 1,
            child: row,
          ),
        ),
      ),
    );
  }
}

/// CSS: .btn.primary — 強調は反転（黒地に白）で行う。色は足さない。
class PrimaryBtn extends StatelessWidget {
  const PrimaryBtn(this.label, {super.key, this.onTap, this.block = false});

  final String label;
  final VoidCallback? onTap;
  final bool block;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Space sp = spaceOf(context);

    final Widget box = Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: EdgeInsets.symmetric(horizontal: sp.s3, vertical: 10),
      alignment: Alignment.center,
      color: c.sel,
      child: Text(upper(label), style: Typo(c).btn.copyWith(color: c.selInk, decoration: TextDecoration.none)),
    );

    return Semantics(
      button: true,
      label: label,
      enabled: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: block ? SizedBox(width: double.infinity, child: box) : IntrinsicWidth(child: box),
      ),
    );
  }
}

/// CSS: .mini — .btn より一回り小さい。薄い色で置く。
class MiniBtn extends StatelessWidget {
  const MiniBtn(this.label, {super.key, this.onTap, this.icon, this.danger = false, this.primary = false});

  final String label;
  final VoidCallback? onTap;
  final String? icon;
  final bool danger;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Space sp = spaceOf(context);
    final TextStyle style = Typo(c).mini.copyWith(
          color: primary ? c.selInk : (danger ? const Color(0xFFC0392B) : c.mute),
          decoration: primary ? TextDecoration.none : TextDecoration.underline,
        );

    final Widget row = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Ic(icon!, size: 13, color: style.color),
          SizedBox(width: sp.s1),
        ],
        Text(upper(label), style: style),
      ],
    );

    return Semantics(
      button: true,
      label: label,
      enabled: onTap != null,
      child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: primary
          // CSS: .mini.primary { background: sel; padding: 6px var(--s2) }
          ? Container(
              color: c.sel,
              padding: EdgeInsets.symmetric(horizontal: sp.s2, vertical: 6),
              child: row,
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 24, minWidth: 24),
              child: Align(alignment: Alignment.center, widthFactor: 1, child: row),
            ),
      ),
    );
  }
}

/// CSS: .form label ＋ .form input — 見出しを上に置き、書く所は下の1本で示す。
class LabeledField extends StatelessWidget {
  const LabeledField({super.key, required this.label, this.obscure = false, this.controller});

  final String label;
  final bool obscure;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Typo t = Typo(c);
    final Space sp = spaceOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(upper(label), style: t.formLabel),
        SizedBox(height: sp.s1),                       // CSS: .form input { margin-top: var(--s1) }
        // ★ 高さは決め打ちにする。TextField は書体の言い分で高さを決めるので、
        //   CSS の「余白 6 ＋ 行 27.2 ＋ 余白 6 ＋ 線 1」に合わない。
        Container(
          height: 40.2,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.hair)),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscure,
            style: t.formInput,
            cursorColor: c.ink,
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ],
    );
  }
}

/// CSS: .avatar — 丸く切った顔。絵が無いときは名前の1文字を置く。
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.initial, this.url, this.large = false});

  final String initial;
  final String? url;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final double size = large ? 64 : 30;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.paper2, shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      child: url != null
          ? CachedNetworkImage(imageUrl: url!, width: size, height: size, fit: BoxFit.cover)
          : Text(
              initial,
              style: TextStyle(
                color: c.inkSoft,
                fontFamily: monoFamily,
                fontFamilyFallback: monoFallback,
                fontSize: large ? 22 : 12,
                height: lineHeight,
                leadingDistribution: TextLeadingDistribution.even,
              ),
            ),
    );
  }
}

/// CSS: .panel-row select — 選ぶところ。下の1本だけで示し、右に小さな印を置く。
class Picker extends StatelessWidget {
  const Picker({super.key, required this.value, required this.width});

  final String value;
  final double width;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);

    return Container(
      width: width,
      height: 35,
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.hair)),
      ),
      child: Text(value, style: Typo(c).panelInput),
    );
  }
}
