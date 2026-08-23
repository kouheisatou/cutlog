// ログイン。web の #authScreen をそのまま写す。
// ★ 画面の真ん中に、幅 360 までの札を1枚だけ置く。囲みは作らない。
import 'package:flutter/widgets.dart';

import '../design/text.dart';
import '../design/tokens.dart';
import '../ui/controls.dart';

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key, this.signup = false});

  /// 「新規登録」の側を選んでいるか
  final bool signup;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Typo t = Typo(c);
    final Space sp = spaceOf(context);

    return ColoredBox(
      color: c.paper,
      child: Padding(
        // CSS: .auth { display:grid; place-items:center; padding: var(--s4) }
        padding: EdgeInsets.all(sp.s4),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // CSS: .brand — 等幅・字間 .22em・下に s5 の余白
                Text('cutlog', style: t.brand),
                SizedBox(height: sp.s5),

                // CSS: .tabs { gap: var(--s3); margin: 0 0 var(--s4) }
                Row(
                  children: <Widget>[
                    _Tab('ログイン', active: !signup),
                    SizedBox(width: sp.s3),
                    _Tab('新規登録', active: signup),
                  ],
                ),
                SizedBox(height: sp.s4),

                const LabeledField(label: 'ユーザー名'),
                if (signup) const LabeledField(label: '表示名'),
                const LabeledField(label: 'パスワード', obscure: true),

                // CSS: .btn.block { margin-top: var(--s3) }
                Padding(
                  padding: EdgeInsets.only(top: sp.s3),
                  child: PrimaryBtn(signup ? '新規登録' : 'ログイン', block: true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// CSS: .tab — 選んでいる方だけ濃く、下に1本だけ線を引く。
class _Tab extends StatelessWidget {
  const _Tab(this.label, {required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);

    return Container(
      padding: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: active ? c.ink : const Color(0x00000000))),
      ),
      child: Text(
        upper(label),
        style: Typo(c).authTab.copyWith(color: active ? c.ink : c.mute),
      ),
    );
  }
}
