// このログの設定。web の #logSetScreen をそのまま写す。
// ★ ログに関わることは全部ここに集める（題・長さ・招待・参加者・共有・ゴミ箱）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../data/models.dart';
import '../design/text.dart';
import '../design/tokens.dart';
import '../ui/controls.dart';
import '../ui/flow.dart';
import '../ui/shell.dart';

class LogSetScreen extends StatefulWidget {
  const LogSetScreen({
    super.key,
    required this.log,
    required this.members,
    this.onBack,
    this.onSave,
    this.onRotate,
    this.onTrash,
  });

  final LogItem log;

  /// [表示名, オーナーかどうか] の並び
  final List<List<Object>> members;

  final VoidCallback? onBack;

  /// 題と長さを直す。だめならその訳が返る。
  final Future<String?> Function(String name, int seconds)? onSave;

  /// 招待コードを作り直す
  final Future<String?> Function()? onRotate;

  /// 消したカットを見る
  final VoidCallback? onTrash;

  @override
  State<LogSetScreen> createState() => _LogSetScreenState();
}

class _LogSetScreenState extends State<LogSetScreen> {
  late final TextEditingController _name = TextEditingController(text: widget.log.name);
  late final TextEditingController _seconds =
      TextEditingController(text: '${widget.log.cutSeconds}');
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _seconds.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() job, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    final String? bad = await job();
    if (!mounted) return;
    setState(() => _busy = false);
    toast(context, bad ?? done);
  }

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Typo t = Typo(c);
    final Space sp = spaceOf(context);
    final LogItem log = widget.log;

    return Opacity(
      opacity: _busy ? .5 : 1,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TopBar(children: <Widget>[
          IconBtn('back', onTap: widget.onBack),
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
                _Field(width: 220, controller: _name),
              ]), top: sp.s2, bottom: sp.s2),

              // 1カットの長さ
              Block(_row(<Widget>[
                _Label('1クリップの長さ', t),
                SizedBox(width: sp.s2),
                _Field(width: 72, controller: _seconds, digits: true),
                SizedBox(width: sp.s3),
                Text('秒', style: t.small),
              ]), top: sp.s2, bottom: sp.s2),

              // 既定の記録先にするか
              // ★ .check は高さの下限が 32px。行の高さも 1.2 で他より詰まっている。
              //   ここを他の行と同じにすると、以降の並びがまとめて上へ寄る。
              Block(
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 32),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      const _Check(),
                      SizedBox(width: sp.s1),
                      Text(upper('デフォルトでこのログに保存する'), style: t.check),
                    ],
                  ),
                ),
                top: sp.s2,
                bottom: sp.s2,
              ),

              Block(_row(<Widget>[
                PrimaryBtn('保存', onTap: () => _run(
                      () => widget.onSave!(
                        _name.text.trim(),
                        int.tryParse(_seconds.text.trim()) ?? log.cutSeconds,
                      ),
                      '保存しました',
                    )),
              ]), top: sp.s2, bottom: sp.s2),

              // 招待
              Block(_SectionHead('招待', t), top: sp.s5, bottom: sp.s1),
              Block(_row(<Widget>[
                Text(log.inviteCode ?? '', style: t.body.copyWith(letterSpacing: 2.7)),
                SizedBox(width: sp.s3),
                MiniBtn('コピー', icon: 'copy', onTap: () async {
                  await Clipboard.setData(ClipboardData(text: log.inviteCode ?? ''));
                  if (context.mounted) toast(context, 'コピーしました');
                }),
                SizedBox(width: sp.s3),
                MiniBtn('再生成', onTap: () => _run(widget.onRotate!, '作り直しました')),
              ]), top: sp.s2, bottom: sp.s2),

              // 参加者
              Block(_SectionHead('参加者', t, trailing: '${widget.members.length}人'),
                  top: sp.s5, bottom: sp.s1),
              Block(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.members
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
              Block(_row(<Widget>[
                TextBtn('削除したカットを表示', icon: 'trash', onTap: widget.onTrash),
              ]), top: sp.s2, bottom: sp.s2),
            ]),
          ),
        ),
      ],
      ),
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
  const _Field({required this.width, required this.controller, this.digits = false});

  final double width;
  final TextEditingController controller;
  final bool digits;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    return SizedBox(
      width: width,
      child: Container(
        // 高さは決め打ち。CSS の「余白 6 ＋ 行 23.8 ＋ 余白 6 ＋ 線 1」に合わせる。
        height: 36.8,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.hair))),
        child: TextField(
          controller: controller,
          keyboardType: digits ? TextInputType.number : TextInputType.text,
          style: Typo(c).panelInput,
          cursorColor: c.ink,
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
        ),
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
