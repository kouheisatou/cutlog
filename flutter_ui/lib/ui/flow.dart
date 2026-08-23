// CSS の「縦のマージンは隣り合うと重なって1つになる」を、そのまま作る。
// ★ これを知らずに上下へ余白を付けると、行を重ねるたびに間が倍になり、
//   画面の下へ行くほどずれが積み上がる。cutlog は余白で組む作りなので、ここが要になる。
import 'package:flutter/widgets.dart';

/// 1つの塊と、その上下のマージン。
class Block {
  const Block(this.child, {this.top = 0, this.bottom = 0});

  final Widget child;
  final double top;
  final double bottom;
}

/// 塊を縦に積む。間は max(上の下マージン, 下の上マージン)。
/// ★ いちばん外側の上下も既定では入れる。親が余白（padding）を持っていれば
///   そこで重なりが止まるので、CSS でも外側のマージンはそのまま残るため。
///   親が余白を持たず重なってほしいときだけ outer: false にする。
class CssColumn extends StatelessWidget {
  const CssColumn(this.blocks, {super.key, this.crossAxisAlignment = CrossAxisAlignment.stretch, this.outer = true});

  final List<Block> blocks;
  final CrossAxisAlignment crossAxisAlignment;
  final bool outer;

  @override
  Widget build(BuildContext context) {
    final List<Widget> out = <Widget>[];
    double? prevBottom;

    for (final Block b in blocks) {
      if (prevBottom == null) {
        if (outer && b.top > 0) out.add(SizedBox(height: b.top));
      } else {
        final double gap = prevBottom > b.top ? prevBottom : b.top;
        if (gap > 0) out.add(SizedBox(height: gap));
      }
      out.add(b.child);
      prevBottom = b.bottom;
    }
    if (outer && prevBottom != null && prevBottom > 0) out.add(SizedBox(height: prevBottom));

    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: out,
    );
  }
}
