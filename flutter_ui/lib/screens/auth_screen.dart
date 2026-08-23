// ログイン。web の #authScreen をそのまま写す。
// ★ 画面の真ん中に、幅 360 までの札を1枚だけ置く。囲みは作らない。
import 'package:flutter/widgets.dart';

import '../design/text.dart';
import '../design/tokens.dart';
import '../ui/controls.dart';
import '../ui/flow.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.onSubmit});

  /// ユーザー名とパスワードを渡す。うまくいかなければ、その訳が返る。
  final Future<String?> Function(String username, String password)? onSubmit;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _user = TextEditingController();
  final TextEditingController _pass = TextEditingController();
  bool signup = false;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || widget.onSubmit == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final String? bad = await widget.onSubmit!(_user.text.trim(), _pass.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = bad;
    });
  }

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
            // ★ 縦のマージンは重なって1つになる。いちばん下の入力の下マージン(16)と
            //   ボタンの上マージン(18)は、足すのではなく大きい方だけが残る。
            child: CssColumn(<Block>[
              // CSS: .brand — 等幅・字間 .22em・下に s5 の余白
              Block(Text('cutlog', style: t.brand), bottom: sp.s5),
              // CSS: .tabs { gap: var(--s3); margin: 0 0 var(--s4) }
              Block(
                Row(
                  children: <Widget>[
                    _Tab('ログイン', active: !signup, onTap: () => setState(() => signup = false)),
                    SizedBox(width: sp.s3),
                    _Tab('新規登録', active: signup, onTap: () => setState(() => signup = true)),
                  ],
                ),
                bottom: sp.s4,
              ),
              Block(LabeledField(label: 'ユーザー名', controller: _user), bottom: sp.s4),
              if (signup) Block(const LabeledField(label: '表示名'), bottom: sp.s4),
              Block(LabeledField(label: 'パスワード', obscure: true, controller: _pass), bottom: sp.s4),
              // CSS: .error { color: ink; font-size: 13px; margin: var(--s2) 0 0 }
              if (_error != null)
                Block(Text(_error!, style: t.body.copyWith(fontSize: 13)), top: sp.s2),
              // CSS: .btn.block { margin-top: var(--s3) }
              Block(
                PrimaryBtn(signup ? '新規登録' : 'ログイン', block: true, onTap: _submit),
                top: sp.s3,
              ),
            ], outer: false),
          ),
        ),
      ),
    );
  }
}

/// CSS: .tab — 選んでいる方だけ濃く、下に1本だけ線を引く。
class _Tab extends StatelessWidget {
  const _Tab(this.label, {required this.active, this.onTap});

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
      padding: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: active ? c.ink : const Color(0x00000000))),
      ),
        child: Text(
          upper(label),
          style: Typo(c).authTab.copyWith(color: active ? c.ink : c.mute),
        ),
      ),
    );
  }
}
