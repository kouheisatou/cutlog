// 下からせり上がる白い札（web の dialog.sheet > .panel）。
// ★ 中身が違うだけで、器はどれも同じ。器をここに1つだけ置き、
//   画面ごとの違いは「中に何を並べるか」だけにする。
// ★ 重ね描きを自前でやるのはやめた。Flutter の標準の札に載せると、
//   下へ払って閉じる・外を押して閉じる・戻るで閉じる、が最初から付いてくる。
//   自前だと、そのどれも自分で書く羽目になり、実際に閉じられない札になっていた。
import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/text.dart';
import '../design/tokens.dart';

/// 札を開く。閉じ方（払う・外を押す・戻る）は標準の振る舞いに任せる。
Future<T?> openSheet<T>(
  BuildContext context, {
  required List<Widget> children,
  bool wide = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    // CSS: dialog.sheet::backdrop { background: rgba(16,16,18,.5) }
    barrierColor: const Color(0x80101012),
    backgroundColor: const Color(0x00000000),
    elevation: 0,
    // 中身の高さぶんだけ立ち上がる（画面の半分で止めない）
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext context) => SheetPanel(wide: wide, children: children),
  );
}

/// 札そのもの。角と影と掴み手と閉じるボタンだけを持つ。
class SheetPanel extends StatelessWidget {
  const SheetPanel({super.key, required this.children, this.wide = false});

  final List<Widget> children;

  /// CSS: .wide-panel（詳細の札だけ少し広く使う）
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Space sp = spaceOf(context);
    final double safeBottom = MediaQuery.paddingOf(context).bottom;

    // ★ 横だけ中央に寄せ、縦は中身の高さのまま。Center にすると
    //   札が画面の高さいっぱいに広がり、中身が真ん中に浮いてしまう。
    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: wide ? 720 : 640,
          // CSS: .panel { max-height: 88dvh }
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: c.paper,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                offset: const Offset(0, -8),
                blurRadius: blurFromCss(40),
                color: const Color(0x38000000),
              ),
            ],
          ),
          // ★ 閉じるボタンは札の角から測る（CSS の position:absolute は
          //   余白の外側、札そのものの角を基準にする）。余白の内側に置くと 16px 下がる。
          child: Stack(
            children: <Widget>[
              Padding(
                padding: EdgeInsets.fromLTRB(
                  sp.s4, sp.s4, sp.s4, safeBottom > sp.s4 ? safeBottom : sp.s4,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      // CSS: .panel::before — 掴むところ。ここを下へ払うと閉じる。
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: c.hair,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      SizedBox(height: sp.s3),
                      ...children,
                    ],
                  ),
                ),
              ),
              // CSS: .panel-close { position: absolute; top: var(--s1); right: var(--s1) }
              Positioned(
                top: sp.s1,
                right: sp.s1,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Opacity(opacity: .7, child: Ic('close', color: c.ink)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// CSS: .panel h2 — 12px・字間 .2em・太字。右は閉じるボタンのぶんだけ空ける。
class SheetTitle extends StatelessWidget {
  const SheetTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 52),
      child: Text(
        upper(text),
        style: Typo.of(context).panelHead.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// CSS: .panel h3 — 11px・字間 .18em・薄い色・太字。
class SheetHead extends StatelessWidget {
  const SheetHead(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        upper(text),
        style: Typo.of(context).sectionHead.copyWith(fontWeight: FontWeight.w700),
      );
}

/// CSS: .panel-row — 横に並べる。すきまは s3。
class SheetRow extends StatelessWidget {
  const SheetRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final Space sp = spaceOf(context);
    final List<Widget> out = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) out.add(SizedBox(width: sp.s3));
      out.add(children[i]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: out);
  }
}

/// CSS: .panel-actions — 右へ寄せる。すきまは s4、上に s5。
class SheetActions extends StatelessWidget {
  const SheetActions({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final Space sp = spaceOf(context);
    final List<Widget> out = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) out.add(SizedBox(width: sp.s4));
      out.add(children[i]);
    }
    return Row(mainAxisAlignment: MainAxisAlignment.end, children: out);
  }
}

/// CSS: .panel-row input — 囲まず、下の1本だけ。
class SheetField extends StatelessWidget {
  const SheetField({
    super.key,
    required this.hint,
    this.width,
    this.fontSize = 14,
    this.controller,
    this.obscure = false,
  });

  final String hint;

  /// ★ 伸ばさない。web の <input> は幅の指定が無ければブラウザの既定のまま置かれる。
  ///   幅は画面ごとに違うので、`shots/probe/*.json` で測った値を渡す。
  ///   勝手に伸ばすと、隣のボタンの位置がまとめて右へずれる。
  final double? width;

  /// 検索の入力だけ 16px（`#allSearch`）
  final double fontSize;

  final TextEditingController? controller;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final TextStyle style = Typo(c).panelInput.copyWith(fontSize: fontSize);

    final Widget box = Container(
      // 高さは決め打ち。TextField は書体の言い分で高さを決めるので、CSS の
      // 「余白 6 ＋ 行 ＋ 余白 6 ＋ 線 1」に合わない。
      height: 6 + fontSize * lineHeight + 6 + 1,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.hair))),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: style,
        cursorColor: c.ink,
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          hintText: hint,
          hintStyle: style.copyWith(color: c.mute),
        ),
      ),
    );
    return width == null ? Expanded(child: box) : SizedBox(width: width, child: box);
  }
}
