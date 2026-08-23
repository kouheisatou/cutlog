// 下からせり上がる札の中身。器（Sheet）は同じで、並べるものだけが違う。
import 'package:flutter/widgets.dart';

import '../design/text.dart';
import '../design/tokens.dart';
import '../ui/controls.dart';
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
