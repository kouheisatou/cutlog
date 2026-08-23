// このログの設定。web の #logSetScreen をそのまま写す。
// ★ ログに関わることは全部ここに集める（題・長さ・招待・参加者・共有・ゴミ箱）。
import 'package:flutter/widgets.dart';

import '../data/models.dart';
import '../design/text.dart';
import '../design/tokens.dart';
import '../ui/controls.dart';
import '../ui/flow.dart';
import '../ui/shell.dart';

class LogSetScreen extends StatelessWidget {
  const LogSetScreen({
    super.key,
    required this.log,
    required this.members,
    this.onBack,
  });

  final LogItem log;

  /// [表示名, オーナーかどうか] の並び
  final List<List<Object>> members;

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Typo t = Typo(c);
    final Space sp = spaceOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TopBar(children: <Widget>[
          IconBtn('back', onTap: onBack),
          Crumbs(items: <String>['ログ', log.name, '設定']),
        ]),
        Expanded(
          child: ScreenBody(
            top: false,
            child: CssColumn(<Block>[
              // 題
              Block(_row(<Widget>[
                _Label('タイトル', t),
                SizedBox(width: sp.s2),
                _Field(width: 220, value: log.name),
              ]), top: sp.s2, bottom: sp.s2),

              // 1カットの長さ
              Block(_row(<Widget>[
                _Label('1クリップの長さ', t),
                SizedBox(width: sp.s2),
                _Field(width: 72, value: '${log.cutSeconds}'),
                SizedBox(width: sp.s3),
                Text('秒', style: t.small),
              ]), top: sp.s2, bottom: sp.s2),

              // 既定の記録先にするか
              Block(_row(<Widget>[
                const _Check(),
                SizedBox(width: sp.s1),
                _Label('デフォルトでこのログに保存する', t),
              ]), top: sp.s2, bottom: sp.s2),

              Block(_row(<Widget>[const PrimaryBtn('保存')]), top: sp.s2, bottom: sp.s2),

              // 招待
              Block(_SectionHead('招待', t), top: sp.s5, bottom: sp.s1),
              Block(_row(<Widget>[
                Text(log.inviteCode ?? '', style: t.body.copyWith(letterSpacing: 2.7)),
                SizedBox(width: sp.s3),
                const MiniBtn('コピー', icon: 'copy'),
                SizedBox(width: sp.s3),
                const MiniBtn('再生成'),
              ]), top: sp.s2, bottom: sp.s2),

              // 参加者
              Block(_SectionHead('参加者', t, trailing: '${members.length}人'), top: sp.s5, bottom: sp.s1),
              Block(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: members
                      .map((List<Object> m) => _Member(name: m[0] as String, owner: m[1] as bool))
                      .toList(),
                ),
                top: 0,
                bottom: 0,
              ),

              // 共有リンク
              Block(_SectionHead('共有リンク', t), top: sp.s5, bottom: sp.s1),
              Block(_row(<Widget>[const TextBtn('共有リンクの一覧', icon: 'share')]), top: sp.s2, bottom: sp.s2),

              // ゴミ箱
              Block(_SectionHead('ゴミ箱', t), top: sp.s5, bottom: sp.s1),
              Block(_row(<Widget>[const TextBtn('削除したカットを表示', icon: 'trash')]), top: sp.s2, bottom: sp.s2),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _row(List<Widget> children) =>
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: children);
}

/// CSS: .panel-row label — 等幅・大文字・薄い色。
class _Label extends StatelessWidget {
  const _Label(this.text, this.t);

  final String text;
  final Typo t;

  @override
  Widget build(BuildContext context) => Text(upper(text), style: t.panelLabel);
}

/// CSS: .panel-row input — 囲まず、下の1本だけで書く場所を示す。
class _Field extends StatelessWidget {
  const _Field({required this.width, required this.value});

  final double width;
  final String value;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.hair))),
        child: Text(value, style: Typo(c).panelInput),
      ),
    );
  }
}

/// CSS: input[type=checkbox] — 16px の四角。既定の余白は入れない。
class _Check extends StatelessWidget {
  const _Check();

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    return SizedBox(
      width: 16,
      height: 16,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border.all(color: c.mute, width: 1.2)),
      ),
    );
  }
}

/// CSS: .section-head — 等幅・大文字・薄い色。太さは 400（h2 の既定から落としてある）。
class _SectionHead extends StatelessWidget {
  const _SectionHead(this.label, this.t, {this.trailing});

  final String label;
  final Typo t;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Text(upper(label), style: t.sectionHead),
        const Spacer(),
        if (trailing != null) Text(trailing!, style: t.sectionHead),
      ],
    );
  }
}

/// CSS: .member-row — 名前と役どころ。行のあいだにヘアラインを引く。
class _Member extends StatelessWidget {
  const _Member({required this.name, required this.owner});

  final String name;
  final bool owner;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Typo t = Typo(c);
    final Space sp = spaceOf(context);

    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: EdgeInsets.symmetric(vertical: sp.s1),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.hair))),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: t.body.copyWith(fontSize: 14)),
          ),
          SizedBox(width: sp.s2),
          Text(owner ? 'オーナー' : 'メンバー', style: t.small),
        ],
      ),
    );
  }
}
