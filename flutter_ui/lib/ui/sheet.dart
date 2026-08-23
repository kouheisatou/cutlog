// 下からせり上がる白い札（web の dialog.sheet > .panel）。
// ★ 中身が違うだけで、器はどれも同じ。器をここに1つだけ置き、
//   画面ごとの違いは「中に何を並べるか」だけにする。
import 'package:flutter/widgets.dart';

import '../design/icons.dart';
import '../design/text.dart';
import '../design/tokens.dart';

class Sheet extends StatelessWidget {
  const Sheet({super.key, required this.under, required this.children, this.wide = false});

  /// 下に見えている画面。札は、その上に薄い暗がりを挟んで乗る。
  final Widget under;

  final List<Widget> children;

  /// CSS: .wide-panel（詳細のシートだけ少し広く使う）
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Space sp = spaceOf(context);
    final double safeBottom = MediaQuery.paddingOf(context).bottom;

    return Stack(
      children: <Widget>[
        Positioned.fill(child: under),
        // CSS: dialog.sheet::backdrop { background: rgba(16,16,18,.5) }
        const Positioned.fill(child: ColoredBox(color: Color(0x80101012))),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 720 : 640),
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
                    // CSS: .panel-close { position: absolute; top: var(--s1); right: var(--s1) }
                    Positioned(
                      top: sp.s1,
                      right: sp.s1,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: Opacity(opacity: .7, child: Ic('close', color: c.ink)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
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

/// CSS: .panel-row input — 囲まず、下の1本だけ。中で伸びる。
class SheetField extends StatelessWidget {
  const SheetField({super.key, required this.hint, this.width, this.fontSize = 14});

  final String hint;

  /// ★ 伸ばさない。web の <input> は幅の指定が無ければブラウザの既定のまま置かれる。
  ///   幅は画面ごとに違うので、`shots/probe/*.json` で測った値を渡す。
  ///   勝手に伸ばすと、隣のボタンの位置がまとめて右へずれる。
  final double? width;

  /// 検索の入力だけ 16px（`#allSearch`）
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Widget box = Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.hair))),
      child: Text(
        hint,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Typo(c).panelInput.copyWith(color: c.mute, fontSize: fontSize),
      ),
    );
    return width == null ? Expanded(child: box) : SizedBox(width: width, child: box);
  }
}
