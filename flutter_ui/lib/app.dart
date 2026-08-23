// アプリの入口と、見比べ用の「直に行き先を指す口」。
// ★ #/shot/<名前> で、その画面だけを出せるようにしてある。
//   本物の web を同じ名前で撮って重ねるので、行き着く道が違うと比べられない。
//   ここが唯一の入口で、普段の行き来もこの上に載せる。
import 'package:flutter/material.dart';

import 'data/api.dart';
import 'data/models.dart';
import 'design/text.dart';
import 'design/tokens.dart';
import 'screens/logs_screen.dart';
import 'ui/shell.dart';

class CutlogApp extends StatelessWidget {
  const CutlogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'cutlog',
      debugShowCheckedModeBanner: false,
      home: _Root(),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mq = MediaQuery.of(context);
    final bool dark = mq.platformBrightness == Brightness.dark;

    return Skin(
      palette: dark ? Palette.darkMode : Palette.lightMode,
      space: Space.forWidth(mq.size.width),
      child: Builder(
        builder: (BuildContext context) => ColoredBox(
          color: colorsOf(context).paper,
          child: const _Host(),
        ),
      ),
    );
  }
}

/// いま出す画面を決める。まずは見比べのための直指しだけ。
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final Api _api = Api();
  List<LogItem>? _logs;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<LogItem> logs = await _api.logs();
      if (mounted) setState(() => _logs = logs);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// #/shot/<名前> を読み取る。無ければ最初の画面。
  String get _shot {
    final String f = Uri.base.fragment;
    final Match? m = RegExp(r'^/shot/([a-z0-9-]+)$').firstMatch(f);
    return m?.group(1) ?? 'logs';
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _Note('つながりません: $_error');
    if (_logs == null) return const SizedBox.shrink();

    switch (_shot) {
      case 'logs':
        return Screen(
          tab: 'logs',
          child: LogsScreen(logs: _logs!, mediaUrl: _api.mediaUrl),
        );
      default:
        return _Note('$_shot はまだ作っていません');
    }
  }
}

/// まだ作っていない画面の代わり。差が 100% として出るので、残りが一目で分かる。
class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center, style: Typo.of(context).empty),
      ),
    );
  }
}
