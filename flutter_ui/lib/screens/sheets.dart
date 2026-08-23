// 下からせり上がる札の中身。器（SheetPanel）は同じで、並べるものだけが違う。
// ★ 閉じ方は標準の振る舞いに任せる。ここでは「何を並べるか」と「押したら何をするか」だけを書く。
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../design/text.dart';
import '../design/tokens.dart';
import '../ui/controls.dart';
import '../ui/flow.dart';
import '../ui/sheet.dart';
import '../ui/shell.dart';

/// ログを追加（ログ一覧の右上から開く）
Future<void> openLogAddSheet(
  BuildContext context, {
  required Future<String?> Function(String name) onCreate,
  required Future<String?> Function(String code) onJoin,
}) {
  final TextEditingController name = TextEditingController();
  final TextEditingController code = TextEditingController();

  return openSheet<void>(
    context,
    children: <Widget>[
      _Body(
        builder: (BuildContext context, _Report say) {
          final Space sp = spaceOf(context);
          return CssColumn(<Block>[
            Block(const SheetTitle('ログを追加'), bottom: sp.s1),
            Block(const SheetHead('新しく作る'), top: sp.s5, bottom: sp.s2),
            Block(SheetRow(children: <Widget>[
              SheetField(hint: 'ログのタイトル', width: 149, controller: name),
              PrimaryBtn('作成', onTap: () => say(context, () => onCreate(name.text.trim()))),
            ]), top: sp.s2, bottom: sp.s2),
            Block(const SheetHead('招待コードで参加する'), top: sp.s5, bottom: sp.s2),
            Block(SheetRow(children: <Widget>[
              SheetField(hint: '招待コード', width: 149, controller: code),
              TextBtn('参加', onTap: () => say(context, () => onJoin(code.text.trim()))),
            ]), top: sp.s2, bottom: sp.s2),
          ], outer: false);
        },
      ),
    ],
  );
}

/// ログを検索（ログ一覧の右上から開く）
Future<void> openLogSearchSheet(
  BuildContext context, {
  required String initial,
  required void Function(String q) onSearch,
}) {
  final TextEditingController q = TextEditingController(text: initial);

  return openSheet<void>(
    context,
    children: <Widget>[
      Builder(
        builder: (BuildContext context) {
          final Space sp = spaceOf(context);
          return CssColumn(<Block>[
            Block(const SheetTitle('ログを検索'), bottom: sp.s1),
            Block(_LabeledRow(label: 'タイトル', hint: 'ログのタイトルを入力してください', width: 175, controller: q),
                top: sp.s2, bottom: sp.s2),
            Block(SheetActions(children: <Widget>[
              TextBtn('絞り込みをリセット', onTap: () {
                onSearch('');
                Navigator.of(context).pop();
              }),
              PrimaryBtn('検索', onTap: () {
                onSearch(q.text.trim());
                Navigator.of(context).pop();
              }),
            ]), top: sp.s5),
          ], outer: false);
        },
      ),
    ],
  );
}

/// 検索（カット一覧から開く）
Future<void> openSearchSheet(
  BuildContext context, {
  required String initial,
  required void Function(String q) onSearch,
}) {
  final TextEditingController q = TextEditingController(text: initial);

  return openSheet<void>(
    context,
    children: <Widget>[
      Builder(
        builder: (BuildContext context) {
          final Space sp = spaceOf(context);
          return CssColumn(<Block>[
            Block(const SheetTitle('検索'), bottom: sp.s1),
            Block(_LabeledRow(label: 'メモ', hint: 'メモのワードを入力してください', fontSize: 16, controller: q),
                top: sp.s2, bottom: sp.s2),
            Block(const _LabeledRow(label: 'アップロードした人', hint: '全員', width: 62),
                top: sp.s2, bottom: sp.s2),
            Block(SheetActions(children: <Widget>[
              TextBtn('絞り込みをリセット', onTap: () {
                onSearch('');
                Navigator.of(context).pop();
              }),
              PrimaryBtn('検索', onTap: () {
                onSearch(q.text.trim());
                Navigator.of(context).pop();
              }),
            ]), top: sp.s5),
          ], outer: false);
        },
      ),
    ],
  );
}

/// カットの詳細（どの画面からも、同じ札で開く）
/// ★ 詳しい値（大きさ・場所・ID など）は右上の調整から開く。ここでは畳んでおく。
Future<void> openCutSheet(
  BuildContext context, {
  required Cut cut,
  required String Function(String path) mediaUrl,
  required Future<String?> Function() onDelete,
  required Future<String?> Function(String body) onComment,
  required Future<String?> Function(String emoji) onReact,
  List<String> myReactions = const <String>[],
}) {
  final TextEditingController body = TextEditingController();
  final DateTime at = cut.localTime;
  String two(int n) => n.toString().padLeft(2, '0');
  final String title =
      '${at.year}.${two(at.month)}.${two(at.day)} ${two(at.hour)}:${two(at.minute)}';

  return openSheet<void>(
    context,
    wide: true,
    children: <Widget>[
      _Body(
        builder: (BuildContext context, _Report say) {
          final Palette c = colorsOf(context);
          final Typo t = Typo(c);
          final Space sp = spaceOf(context);

          return CssColumn(<Block>[
            // CSS: .detail-media — 寸法が分からないうちは 16:9 で置く
            Block(
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(color: c.paper2),
                  child: cut.thumbUrl == null
                      ? null
                      : CachedNetworkImage(imageUrl: mediaUrl(cut.thumbUrl!), fit: BoxFit.contain),
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
                        SizedBox(height: sp.s4),   // .eyebrow { margin: var(--s4) 0 var(--s1) }
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
                TextBtn('削除', icon: 'trash', danger: true, onTap: () async {
                  final bool yes = await confirm(context, 'このカットを削除しますか？', '削除');
                  if (!yes || !context.mounted) return;
                  final String? bad = await onDelete();
                  if (!context.mounted) return;
                  if (bad != null) {
                    toast(context, bad);
                  } else {
                    Navigator.of(context).pop();
                  }
                }),
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
                    GestureDetector(
                      onTap: () => say(context, () => onReact(e), close: false),
                      behavior: HitTestBehavior.opaque,
                      child: Opacity(
                        opacity: myReactions.contains(e) ? 1 : .45,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Text(e, style: t.body),
                        ),
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
              SheetField(hint: 'コメントを書く', width: 149, controller: body),
              PrimaryBtn('送信', onTap: () {
                final String text = body.text.trim();
                if (text.isEmpty) return;
                body.clear();
                say(context, () => onComment(text), close: false);
              }),
            ]), top: sp.s2, bottom: sp.s2),
          ]);
        },
      ),
    ],
  );
}

/// うまくいったら閉じ、だめならその訳を出す——という繰り返しを1つにまとめたもの。
typedef _Report = void Function(
  BuildContext context,
  Future<String?> Function() run, {
  bool close,
});

class _Body extends StatefulWidget {
  const _Body({required this.builder});

  final Widget Function(BuildContext context, _Report say) builder;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  bool _busy = false;

  Future<void> _say(BuildContext context, Future<String?> Function() run, {bool close = true}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final String? bad = await run();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!context.mounted) return;
    if (bad != null) {
      toast(context, bad);
      return;
    }
    if (close) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: _busy ? .5 : 1,
      child: IgnorePointer(ignoring: _busy, child: widget.builder(context, _say)),
    );
  }
}

/// CSS: .panel-row label — 見出しと書く所を、同じ行に基線でそろえて並べる。
class _LabeledRow extends StatelessWidget {
  const _LabeledRow({
    required this.label,
    required this.hint,
    this.width,
    this.fontSize = 14,
    this.controller,
  });

  final String label;
  final String hint;
  final double? width;
  final double fontSize;
  final TextEditingController? controller;

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
        SheetField(hint: hint, width: width, fontSize: fontSize, controller: controller),
      ],
    );
  }
}
