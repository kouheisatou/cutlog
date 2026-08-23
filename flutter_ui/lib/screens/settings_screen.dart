// 設定。web の #settingsScreen をそのまま写す。
// ★ 帯を持たない画面なので、上の余白は自分で持つ（CSS の .screen-body.top）。
// ★ 見出しと行のあいだは、CSS のマージンが重なって1つになる。CssColumn がその規則を持つ。
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../design/text.dart';
import '../design/tokens.dart';
import '../ui/controls.dart';
import '../ui/flow.dart';
import '../ui/sheet.dart';
import '../ui/shell.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.me,
    required this.pushHint,
    required this.reminder,
    this.onLogout,
    this.onSaveReminder,
    this.onTestPush,
  });

  final Me me;

  /// 通知のキーが用意できているかの案内。サーバの返事をそのまま出す。
  final String pushHint;

  final Reminder reminder;

  final VoidCallback? onLogout;

  /// 撮影リマインダーを保存する。だめならその訳が返る。
  final Future<String?> Function(Reminder r)? onSaveReminder;

  /// 試しに1通送る
  final Future<String?> Function()? onTestPush;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Reminder _rem = widget.reminder;
  late final TextEditingController _times = TextEditingController(text: widget.reminder.times);
  late final TextEditingController _from =
      TextEditingController(text: '${widget.reminder.fromHour}');
  late final TextEditingController _to = TextEditingController(text: '${widget.reminder.toHour}');
  late final TextEditingController _per = TextEditingController(text: '${widget.reminder.perDay}');
  bool _busy = false;

  @override
  void dispose() {
    _times.dispose();
    _from.dispose();
    _to.dispose();
    _per.dispose();
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

  /// 通知のしかたを選ぶ。web は <select>。こちらは同じ言い回しの札で選ばせる。
  Future<void> _pickMode() async {
    await openSheet<void>(
      context,
      children: <Widget>[
        Builder(
          builder: (BuildContext context) {
            final Space sp = spaceOf(context);
            return CssColumn(<Block>[
              Block(const SheetTitle('通知のしかた'), bottom: sp.s1),
              for (final MapEntry<String, String> e in Reminder.names.entries)
                Block(
                  _Choice(
                    label: e.value,
                    on: e.key == _rem.mode,
                    onTap: () {
                      setState(() => _rem = _rem.copyWith(mode: e.key));
                      Navigator.of(context).pop();
                    },
                  ),
                  top: sp.s1,
                  bottom: sp.s1,
                ),
            ], outer: false);
          },
        ),
      ],
    );
  }

  Reminder get _edited => _rem.copyWith(
        times: _times.text.trim(),
        fromHour: int.tryParse(_from.text.trim()) ?? _rem.fromHour,
        toHour: int.tryParse(_to.text.trim()) ?? _rem.toHour,
        perDay: int.tryParse(_per.text.trim()) ?? _rem.perDay,
      );

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Typo t = Typo(c);
    final Space sp = spaceOf(context);
    final String initial =
        widget.me.displayName.isEmpty ? '?' : widget.me.displayName.characters.first;

    return Opacity(
      opacity: _busy ? .5 : 1,
      child: ScreenBody(
        child: CssColumn(<Block>[
          // CSS: .screen-body h2 { margin: var(--s5) 0 var(--s2) }。太さは h2 の既定（700）のまま。
          Block(_head(t, '撮影リマインダー'), top: sp.s5, bottom: sp.s2),

          Block(_row(<Widget>[Picker(value: _rem.name, width: 188, onTap: _pickMode)]),
              top: sp.s2, bottom: sp.s2),

          // 決めた時刻に通知するときだけ、時刻の並びを書く欄を出す
          if (_rem.needsTimes)
            Block(_row(<Widget>[_Num(width: 188, controller: _times, hint: '09:00,12:00,18:00')]),
                top: sp.s2, bottom: sp.s2),

          // 毎時・ランダムのときだけ、何時から何時まで・1日の回数を出す
          if (_rem.needsWindow)
            Block(
              Wrap(
                spacing: sp.s3,
                runSpacing: sp.s2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  _Labelled(label: '何時から', child: _Num(width: 64, controller: _from)),
                  _Labelled(label: '何時まで', child: _Num(width: 64, controller: _to)),
                  _Labelled(label: '1日の回数', child: _Num(width: 64, controller: _per)),
                ],
              ),
              top: sp.s2,
              bottom: sp.s2,
            ),

          Block(_row(<Widget>[
            TextBtn('保存', onTap: () => _run(() => widget.onSaveReminder!(_edited), '保存しました')),
            SizedBox(width: sp.s3),
            const TextBtn('許可'),
            SizedBox(width: sp.s3),
            TextBtn('テスト送信', onTap: () => _run(widget.onTestPush!, '送りました')),
          ]), top: sp.s2, bottom: sp.s2),

          // <p> の既定のマージンは 1em（12px）。上は行のマージンと重なって 16 になる。
          if (widget.pushHint.isNotEmpty)
            Block(Text(widget.pushHint, style: t.small), top: 12, bottom: 12),

          Block(_head(t, 'アカウント'), top: sp.s5, bottom: sp.s2),

          // CSS: .avatar-row は gap が var(--s2)（他の .panel-row は var(--s3)）
          Block(_row(<Widget>[
            Avatar(initial: initial, large: true),
            SizedBox(width: sp.s2),
            const TextBtn('アイコン画像を設定'),
            SizedBox(width: sp.s2),
            const TextBtn('削除'),
          ]), top: sp.s2, bottom: sp.s2),

          Block(_row(<Widget>[
            Expanded(
              child: Text('${widget.me.displayName}（${widget.me.username}）',
                  style: t.body.copyWith(color: c.mute)),
            ),
            TextBtn('ログアウト', onTap: widget.onLogout),
          ]), top: sp.s2, bottom: sp.s2),
        ]),
      ),
    );
  }

  Widget _head(Typo t, String label) => Text(
        upper(label),
        style: t.sectionHead.copyWith(fontWeight: FontWeight.w700),
      );

  Widget _row(List<Widget> children) =>
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: children);
}

/// CSS: .panel-row label — 見出しと欄を、基線でそろえて並べる。
class _Labelled extends StatelessWidget {
  const _Labelled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Space sp = spaceOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Text(upper(label), style: Typo.of(context).panelLabel),
        SizedBox(width: sp.s2),
        child,
      ],
    );
  }
}

/// CSS: .panel-row input — 囲まず、下の1本だけ。
class _Num extends StatelessWidget {
  const _Num({required this.width, required this.controller, this.hint = ''});

  final double width;
  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final TextStyle style = Typo(c).panelInput;
    return SizedBox(
      width: width,
      child: Container(
        height: 36.8,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.hair))),
        child: TextField(
          controller: controller,
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
      ),
    );
  }
}

/// 選ぶときの1行。選んでいるものだけ反転する（cutlog は色を足さない）。
class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Space sp = spaceOf(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.symmetric(horizontal: on ? sp.s2 : 0),
        color: on ? c.sel : null,
        child: Text(
          label,
          style: Typo(c).body.copyWith(fontSize: 14, color: on ? c.selInk : c.ink),
        ),
      ),
    );
  }
}
