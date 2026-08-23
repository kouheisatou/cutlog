// 下からせり上がる札の中身。器（Sheet）は同じで、並べるものだけが違う。
import 'package:flutter/widgets.dart';

import '../data/models.dart';
import '../design/text.dart';
import '../design/tokens.dart';
import '../ui/controls.dart';
import '../ui/shell.dart';
import '../ui/flow.dart';
import '../ui/sheet.dart';

/// ログを追加（ログ一覧の右上から開く）
class LogAddSheet extends StatelessWidget {
  const LogAddSheet({super.key, required this.under});

  final Widget under;

  @override
  Widget build(BuildContext context) {
    final Space sp = spaceOf(context);
    return Sheet(
      under: under,
      children: <Widget>[
        CssColumn(<Block>[
          Block(const SheetTitle('ログを追加'), bottom: sp.s1),
          Block(const SheetHead('新しく作る'), top: sp.s5, bottom: sp.s2),
          Block(const SheetRow(children: <Widget>[
            SheetField(hint: 'ログのタイトル', width: 149),
            PrimaryBtn('作成'),
          ]), top: sp.s2, bottom: sp.s2),
          Block(const SheetHead('招待コードで参加する'), top: sp.s5, bottom: sp.s2),
          Block(const SheetRow(children: <Widget>[
            SheetField(hint: '招待コード', width: 149),
            TextBtn('参加'),
          ]), top: sp.s2, bottom: sp.s2),
        ]),
      ],
    );
  }
}

/// ログを検索（ログ一覧の右上から開く）
class LogSearchSheet extends StatelessWidget {
  const LogSearchSheet({super.key, required this.under});

  final Widget under;

  @override
  Widget build(BuildContext context) {
    final Space sp = spaceOf(context);
    return Sheet(
      under: under,
      children: <Widget>[
        CssColumn(<Block>[
          Block(const SheetTitle('ログを検索'), bottom: sp.s1),
          Block(const _LabeledRow(label: 'タイトル', hint: 'ログのタイトルを入力してください', width: 175),
              top: sp.s2, bottom: sp.s2),
          Block(const SheetActions(children: <Widget>[
            TextBtn('絞り込みをリセット'),
            PrimaryBtn('検索'),
          ]), top: sp.s5),
        ]),
      ],
    );
  }
}

/// 検索（カット一覧から開く）
class SearchSheet extends StatelessWidget {
  const SearchSheet({super.key, required this.under});

  final Widget under;

  @override
  Widget build(BuildContext context) {
    final Space sp = spaceOf(context);
    return Sheet(
      under: under,
      children: <Widget>[
        CssColumn(<Block>[
          Block(const SheetTitle('検索'), bottom: sp.s1),
          // #allSearch は幅 100%・字 16px。ほかの入力と違う。
          Block(const _LabeledRow(label: 'メモ', hint: 'メモのワードを入力してください', fontSize: 16),
              top: sp.s2, bottom: sp.s2),
          Block(const _LabeledRow(label: 'アップロードした人', hint: '全員', width: 62),
              top: sp.s2, bottom: sp.s2),
          Block(const SheetActions(children: <Widget>[
            TextBtn('絞り込みをリセット'),
            PrimaryBtn('検索'),
          ]), top: sp.s5),
        ]),
      ],
    );
  }
}

/// CSS: .panel-row label — 見出しと書く所を、同じ行に基線でそろえて並べる。
class _LabeledRow extends StatelessWidget {
  const _LabeledRow({required this.label, required this.hint, this.width, this.fontSize = 14});

  final String label;
  final String hint;
  final double? width;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final Space sp = spaceOf(context);
    // ★ CSS の .panel-row label は基線でそろえる。真ん中でそろえると、
    //   字の大きさが違うぶんだけ行の高さが変わってしまう。
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Text(upper(label), style: Typo.of(context).panelLabel),
        SizedBox(width: sp.s2),
        SheetField(hint: hint, width: width, fontSize: fontSize),
      ],
    );
  }
}

/// カットの詳細（どの画面からも、同じ札で開く）
/// ★ 詳しい値（大きさ・場所・ID など）は右上の調整から開く。ここでは畳んでおく。
class CutSheet extends StatelessWidget {
  const CutSheet({super.key, required this.under, required this.cut, required this.mediaUrl});

  final Widget under;
  final Cut cut;
  final String Function(String path) mediaUrl;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Typo t = Typo(c);
    final Space sp = spaceOf(context);
    final DateTime at = cut.localTime;
    final String title = '${at.year}.${_two(at.month)}.${_two(at.day)} '
        '${_two(at.hour)}:${_two(at.minute)}';

    return Sheet(
      under: under,
      wide: true,
      children: <Widget>[
        CssColumn(<Block>[
          // CSS: .detail-media — 寸法が分からないうちは 16:9 で置く
          Block(
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(color: c.paper2),
                child: cut.thumbUrl == null
                    ? null
                    : Image.network(mediaUrl(cut.thumbUrl!), fit: BoxFit.contain),
              ),
            ),
          ),

          // CSS: .detail-head — 撮った人・撮った時
          Block(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SizedBox(height: sp.s4),           // .eyebrow { margin: var(--s4) 0 var(--s1) }
                      Text(upper(cut.author ?? ''), style: t.eyebrow),
                      SizedBox(height: sp.s1),
                      // ★ .panel h2 が後に書かれているので、.detail h2 の 22px ではなく 12px が効く
                      Text(title, style: t.panelHead.copyWith(fontWeight: FontWeight.w700)),
                      SizedBox(height: sp.s1),
                    ],
                  ),
                ),
                SizedBox(width: sp.s2),
                const IconBtn('settings'),
              ],
            ),
          ),

          // CSS: .detail-actions { margin: var(--s3) 0 var(--s4) }
          Block(
            Row(children: <Widget>[
              const TextBtn('ダウンロード', icon: 'download'),
              SizedBox(width: sp.s3),
              const TextBtn('移動', icon: 'move'),
              SizedBox(width: sp.s3),
              const TextBtn('削除', icon: 'trash', danger: true),
            ]),
            top: sp.s3,
            bottom: sp.s4,
          ),

          // CSS: .reactions { margin: var(--s3) 0 }
          Block(
            Row(
              children: <Widget>[
                for (final String e in <String>['👍', '🎉', '😂', '🥺', '🔥']) ...<Widget>[
                  if (e != '👍') SizedBox(width: sp.s2),
                  Opacity(
                    opacity: .45,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text(e, style: t.body),
                    ),
                  ),
                ],
              ],
            ),
            top: sp.s3,
            bottom: sp.s3,
          ),

          // CSS: .comments の margin-top は s4 だが、中の h3 が s5 の上マージンを持ち、
          //   親を突き抜けて重なる（margin collapsing）。効くのは大きい方の s5。
          Block(const SheetHead('コメント'), top: sp.s5, bottom: sp.s2),
          Block(SheetRow(children: <Widget>[
            const SheetField(hint: 'コメントを書く', width: 149),
            const PrimaryBtn('送信'),
          ]), top: sp.s2, bottom: sp.s2),
        ]),
      ],
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
