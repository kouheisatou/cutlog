// 画面の骨。web の .app / .topbar / .screen-body / .tabbar をそのまま写す。
import 'package:flutter/widgets.dart';

import '../design/icons.dart';
import '../design/text.dart';
import '../design/tokens.dart';

/// CSS: .icon-btn — 44px の四角。見た目は薄く（opacity .7）、押せる範囲は広く取る。
class IconBtn extends StatelessWidget {
  const IconBtn(this.icon, {super.key, this.onTap, this.size = 44, this.color, this.opacity = .7, this.iconSize = 17, this.strokeWidth = 1.6});

  final String icon;
  final VoidCallback? onTap;
  final double size;
  final Color? color;
  final double opacity;
  final double iconSize;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
          );
        }).toList(),
      ),
    );
  }
}

/// 画面ぜんぶ（中身＋下の帯）。帯は上に重ねる（CSS の position: fixed と同じ）。
class Screen extends StatelessWidget {
  const Screen({super.key, required this.child, this.tab, this.onTab});

  final Widget child;
  final String? tab;
  final ValueChanged<String>? onTab;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
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
