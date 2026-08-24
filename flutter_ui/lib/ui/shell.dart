// 画面の骨。web の .app / .topbar / .screen-body / .tabbar をそのまま写す。
import 'dart:async';

import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/text.dart';
import '../design/tokens.dart';
import 'controls.dart';

/// CSS: .icon-btn — 44px の四角。見た目は薄く（opacity .7）、押せる範囲は広く取る。
class IconBtn extends StatelessWidget {
  const IconBtn(
    this.icon, {
    super.key,
    this.onTap,
    this.size = 44,
    this.color,
    this.opacity = .7,
    this.iconSize = 17,
    this.strokeWidth = 1.6,
    this.label,
  });

  final String icon;

  /// 読み上げ用の名前。無ければ印の名前をそのまま使う。
  final String? label;
  final VoidCallback? onTap;
  final double size;
  final Color? color;
  final double opacity;
  final double iconSize;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label ?? icon,
      enabled: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Opacity(
              opacity: opacity,
              child: Ic(icon, size: iconSize, color: color ?? colorsOf(context).ink, strokeWidth: strokeWidth),
            ),
          ),
        ),
      ),
    );
  }
}

/// CSS: .topbar（スマホ幅）— padding: max(s2, safeTop) s4 s1 / gap s2
class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final Space sp = spaceOf(context);
    final double safeTop = MediaQuery.paddingOf(context).top;

    final List<Widget> row = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) row.add(SizedBox(width: sp.s2));
      row.add(children[i]);
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(sp.s4, safeTop > sp.s2 ? safeTop : sp.s2, sp.s4, sp.s1),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: row),
    );
  }
}

/// CSS: .screen-body — 幅は 640 まで、中央寄せ。下は帯のぶんだけ空ける。
class ScreenBody extends StatelessWidget {
  const ScreenBody({super.key, required this.child, this.top = true, this.scroll = true});

  final Widget child;
  final bool top;      // .screen-body.top（帯を持たない画面は自分で上を空ける）
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final Space sp = spaceOf(context);
    final double safeTop = MediaQuery.paddingOf(context).top;
    final double safeBottom = MediaQuery.paddingOf(context).bottom;

    final EdgeInsets pad = EdgeInsets.fromLTRB(
      sp.s4,
      top ? (safeTop > sp.s3 ? safeTop : sp.s3) : sp.s2,
      sp.s4,
      64 + safeBottom,
    );

    // ★ CSS では .screen-body そのものが「幅 640 まで・中央寄せ・中だけ流れる」箱。
    //   中央寄せを流れる中に入れると、Flutter では高さが決まらなくなって画面ごと落ちる。
    //   囲いの順番も CSS と同じ（中央寄せ → 幅の上限 → 流れる → 余白）にそろえる。
    final Widget body = Padding(padding: pad, child: child);
    // ★ 中央寄せは横だけ。縦まで中央にすると、中身が画面の真ん中へ落ちる。
    //   CSS の margin: 0 auto は横だけの指定で、中身は上から積まれる。
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: scroll ? SingleChildScrollView(child: body) : body,
      ),
    );
  }
}

/// CSS: .tabbar — 下に貼り付く5つ。線は上に1本だけ。
class TabBarNav extends StatelessWidget {
  const TabBarNav({super.key, required this.current, this.onTap});

  final String current;
  final ValueChanged<String>? onTap;

  static const List<List<String>> items = <List<String>>[
    <String>['camera', 'camera', 'カメラ'],
    <String>['all', 'grid', 'カット一覧'],
    <String>['logs', 'list', 'ログ'],
    <String>['map', 'pin', 'マップ'],
    <String>['settings', 'settings', '設定'],
  ];

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Typo t = Typo(c);
    final double safeBottom = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: c.paper,
        border: Border(top: BorderSide(color: c.hair)),
      ),
      padding: EdgeInsets.only(bottom: safeBottom),
      child: Row(
        children: items.map((List<String> it) {
          final bool on = it[0] == current;
          return Expanded(
            child: Semantics(
              button: true,
              selected: on,
              label: it[2],
              child: GestureDetector(
              onTap: onTap == null ? null : () => onTap!(it[0]),
              behavior: HitTestBehavior.opaque,
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Ic(it[1], size: 21, color: on ? c.ink : c.mute, strokeWidth: on ? 1.9 : 1.6),
                    const SizedBox(height: 3),
                    Text(upper(it[2]), style: t.tabLabel.copyWith(color: on ? c.ink : c.mute)),
                  ],
                ),
              ),
            ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// 画面ぜんぶ（中身＋下の帯）。
/// ★ 器は Scaffold に任せる。知らせの帯（SnackBar）・切り欠きの逃げ・
///   下の帯の置き場所を、標準の仕組みが面倒を見てくれる。
/// ★ extendBody で、中身は帯の下まで敷く。CSS の position: fixed と同じ重なり方になる
///   （各画面はすでに下へ 64px の余白を持っている）。
class Screen extends StatelessWidget {
  const Screen({super.key, required this.child, this.tab, this.onTab});

  final Widget child;
  final String? tab;
  final ValueChanged<String>? onTab;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    // ★ Scaffold は使わない。web に出したとき、中身（body）が描かれず
    //   下の帯だけが画面の真ん中に残る形になった（端末では出ない）。
    //   知らせの帯（SnackBar）は MaterialApp が用意する ScaffoldMessenger から出せるので、
    //   Scaffold そのものは要らない。帯は CSS と同じく上に重ねる。
    return ColoredBox(
      color: c.paper,
      child: Stack(
        children: <Widget>[
          Positioned.fill(child: child),
          if (tab != null)
            Positioned(left: 0, right: 0, bottom: 0, child: TabBarNav(current: tab!, onTap: onTab)),
        ],
      ),
    );
  }
}

/// CSS: .crumbs — いまどこにいるかを、上から順に並べて出す。
/// 最後の1つ（いまの場所）だけ濃く、途中は道すじとして薄く置く。
class Crumbs extends StatelessWidget {
  const Crumbs({super.key, required this.items, this.onTap});

  final List<String> items;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Typo t = Typo(c);
    final List<Widget> out = <Widget>[];

    for (int i = 0; i < items.length; i++) {
      final bool last = i == items.length - 1;
      if (i > 0) {
        // CSS: .crumbs li + li::before { content: "/" }。地の書体・地の大きさのまま。
        out.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('/', style: t.body.copyWith(color: c.hair)),
        ));
      }
      out.add(Flexible(
        child: GestureDetector(
          onTap: last || onTap == null ? null : () => onTap!(i),
          behavior: HitTestBehavior.opaque,
          child: Text(
            items[i],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: last
                ? t.crumbCurrent
                : t.crumb.copyWith(
                    decoration: TextDecoration.underline,
                    decorationColor: c.hair,
                  ),
          ),
        ),
      ));
    }

    return Expanded(child: Row(mainAxisSize: MainAxisSize.min, children: out));
  }
}

// ── 知らせと確かめ ──────────────────────────────────────
// ★ 知らせは自分で重ねる。SnackBar は Scaffold の下にいることが前提で、
//   この作りには Scaffold が無いため、呼ぶたびに落ちていた。
//   重ねる場所（Overlay）は根のものを使う。札の上に出しても隠れない。

OverlayEntry? _note;
Timer? _noteTimer;

void _clearNote() {
  _noteTimer?.cancel();
  _noteTimer = null;
  if (_note?.mounted ?? false) _note!.remove();
  _note = null;
}

/// CSS: .toast — 反転した細い帯を下から出す。
void toast(BuildContext context, String message) {
  final OverlayState? layer = Overlay.maybeOf(context, rootOverlay: true);
  if (layer == null) return;

  final Palette c = colorsOf(context);
  final Space sp = spaceOf(context);
  final double safeBottom = MediaQuery.paddingOf(context).bottom;

  _clearNote();
  _note = OverlayEntry(
    builder: (BuildContext _) => Positioned(
      left: 0,
      right: 0,
      bottom: sp.s5 + safeBottom,
      child: IgnorePointer(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.9,
            ),
            child: Container(
              color: c.sel,
              padding: EdgeInsets.symmetric(horizontal: sp.s3, vertical: 12),
              child: Text(
                upper(message),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.selInk,
                  fontFamily: monoFamily,
                  fontFamilyFallback: monoFallback,
                  fontSize: 12,
                  height: 1.7,
                  leadingDistribution: TextLeadingDistribution.even,
                  letterSpacing: 0.96,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  layer.insert(_note!);
  _noteTimer = Timer(const Duration(seconds: 3), _clearNote);
}

/// 取り返しのつかないことをする前に、一度だけ確かめる。
Future<bool> confirm(BuildContext context, String question, String yes) async {
  final Palette c = colorsOf(context);
  final Typo t = Typo(c);
  final Space sp = spaceOf(context);

  final bool? ok = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0x80101012),
    builder: (BuildContext context) => Dialog(
      backgroundColor: c.paper,
      shape: const RoundedRectangleBorder(),
      child: Padding(
        padding: EdgeInsets.all(sp.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(question, style: t.body),
            SizedBox(height: sp.s5),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextBtn('やめる', onTap: () => Navigator.of(context).pop(false)),
                SizedBox(width: sp.s4),
                PrimaryBtn(yes, onTap: () => Navigator.of(context).pop(true)),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return ok ?? false;
}


/// 画面が入れ替わるときの、ほんの少しの動き。
/// ★ 奥へ進むときは下から、戻るときは上から出す。横へずらさない。
///   横だと、その間だけ画面より広くなって横に揺れる（web でそう決めている）。
class ScreenSwap extends StatelessWidget {
  const ScreenSwap({super.key, required this.depth, required this.child});

  /// いまの深さ。増えたら奥へ、減ったら戻り。
  final int depth;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (Widget w, Animation<double> t) {
        final bool forward = (w.key as ValueKey<int>?)?.value != null;
        return FadeTransition(
          opacity: t,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(0, forward ? 0.02 : -0.02),
              end: Offset.zero,
            ).animate(t),
            child: w,
          ),
        );
      },
      child: KeyedSubtree(key: ValueKey<int>(depth), child: child),
    );
  }
}
