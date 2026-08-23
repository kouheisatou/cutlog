// 設定。web の #settingsScreen をそのまま写す。
// ★ 帯を持たない画面なので、上の余白は自分で持つ（CSS の .screen-body.top）。
// ★ 見出しと行のあいだは、CSS のマージンが重なって1つになる。CssColumn がその規則を持つ。
import 'package:flutter/widgets.dart';

import '../data/models.dart';
import '../design/text.dart';
import '../design/tokens.dart';
import '../ui/controls.dart';
import '../ui/flow.dart';
import '../ui/shell.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.me,
    required this.pushHint,
    this.onLogout,
  });

  final Me me;

  /// 通知のキーが用意できているかの案内。サーバの返事をそのまま出す。
  final String pushHint;

  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Typo t = Typo(c);
    final Space sp = spaceOf(context);
    final String initial = me.displayName.isEmpty ? '?' : me.displayName.characters.first;

    return ScreenBody(
      child: CssColumn(<Block>[
        // CSS: .screen-body h2 { margin: var(--s5) 0 var(--s2) }。太さは h2 の既定（700）のまま。
        Block(_head(t, '撮影リマインダー'), top: sp.s5, bottom: sp.s2),

        Block(_row(sp, <Widget>[const Picker(value: '通知しない', width: 188)]), top: sp.s2, bottom: sp.s2),
        Block(_row(sp, <Widget>[
          const TextBtn('保存'),
          SizedBox(width: sp.s3),
          const TextBtn('許可'),
          SizedBox(width: sp.s3),
          const TextBtn('テスト送信'),
        ]), top: sp.s2, bottom: sp.s2),

        // <p> の既定のマージンは 1em（12px）。上は行のマージンと重なって 16 になる。
        if (pushHint.isNotEmpty)
          Block(Text(pushHint, style: t.small), top: 12, bottom: 12),

        Block(_head(t, 'アカウント'), top: sp.s5, bottom: sp.s2),

        // CSS: .avatar-row は gap が var(--s2)（他の .panel-row は var(--s3)）
        Block(_row(sp, <Widget>[
          Avatar(initial: initial, large: true),
          SizedBox(width: sp.s2),
          const TextBtn('アイコン画像を設定'),
          SizedBox(width: sp.s2),
          const TextBtn('削除'),
        ]), top: sp.s2, bottom: sp.s2),

        Block(_row(sp, <Widget>[
          Expanded(child: Text('\${me.displayName}（\${me.username}）', style: t.body.copyWith(color: c.mute))),
          const TextBtn('ログアウト'),
        ]), top: sp.s2, bottom: sp.s2),
      ]),
    );
  }

  Widget _head(Typo t, String label) => Text(
        upper(label),
        style: t.sectionHead.copyWith(fontWeight: FontWeight.w700),
      );

  Widget _row(Space sp, List<Widget> children) =>
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: children);
}
