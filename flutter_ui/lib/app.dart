// アプリの入口と、見比べ用の「直に行き先を指す口」。
// ★ #/shot/<名前> で、その画面だけを出せるようにしてある。
//   本物の web を同じ名前で撮って重ねるので、行き着く道が違うと比べられない。
//   ここが唯一の入口で、普段の行き来もこの上に載せる。
import 'package:flutter/material.dart';

import 'data/api.dart';
import 'data/models.dart';
import 'design/text.dart';
import 'design/tokens.dart';
import 'screens/all_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/day_screen.dart';
import 'screens/log_screen.dart';
import 'screens/logs_screen.dart';
import 'screens/logset_screen.dart';
import 'screens/review_screen.dart';
import 'screens/settings_screen.dart';
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
        builder: (BuildContext context) => DefaultTextStyle(
          // ★ 敷かないと、字の指定が無い所に Flutter の目印（黄色い二重下線）が出る。
          //   CSS の body と同じものを一枚敷いて、そこから各所が上書きする形にする。
          style: Typo.of(context).body,
          child: ColoredBox(
            color: colorsOf(context).paper,
            child: const _Host(),
          ),
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
  List<Cut> _cuts = <Cut>[];
  List<Cut> _logCuts = <Cut>[];        // 見比べで開くログの中身
  Map<String, dynamic> _logDetail = <String, dynamic>{};
  Me? _me;
  Map<String, dynamic> _config = <String, dynamic>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // ログインの前に出す画面（#/shot/auth）では、鍵が要るものを取りに行かない。
    if (_shot == 'auth') {
      setState(() => _logs = <LogItem>[]);
      return;
    }
    try {
      final List<Object?> got = await Future.wait(<Future<Object?>>[
        _api.logs(), _api.me(), _api.config(), _api.allCuts(),
      ]);
      if (!mounted) return;
      setState(() {
        _logs = got[0]! as List<LogItem>;
        _me = got[1] as Me?;
        _config = got[2]! as Map<String, dynamic>;
        _cuts = got[3]! as List<Cut>;
      });
      // カレンダーは1つのログの中身で組む。見比べでは「まいにち」を開く。
      final LogItem target = _logs!.firstWhere(
        (LogItem l) => l.name == 'まいにち',
        orElse: () => _logs!.firstWhere((LogItem l) => l.cutCount > 0, orElse: () => _logs!.first),
      );
      final List<Cut> inLog = await _api.cutsOfLog(target.id);
      final Map<String, dynamic> detail = await _api.logDetail(target.id);
      if (mounted) {
        setState(() {
          _logCuts = inLog;
          _logDetail = detail;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// 見比べで開くログ。中身があるものを選ぶ。
  LogItem get _target => _logs!.firstWhere(
        (LogItem l) => l.name == 'まいにち',
        orElse: () => _logs!.firstWhere((LogItem l) => l.cutCount > 0, orElse: () => _logs!.first),
      );

  /// いちばん新しいカットの日。
  String get _newestDay => _cuts.isEmpty ? '' : _cuts.first.localDate;

  /// web の設定画面と同じ文言。通知のキーが無いサーバでは、その旨だけを出す。
  String get _pushHint => _config['vapidPublicKey'] == null
      ? 'このサーバは通知のキー（VAPID）が未設定です。管理者が .env に設定すると使えます。'
      : '';

  /// ?shot=<名前> を読み取る。無ければ最初の画面。
  /// ★ 井桁（#）の側は Flutter の道案内が自分のものとして書き換えてしまう。
  ///   こちらが指した行き先が消えるので、問い合わせ（?）の側に置く。
  String get _shot => Uri.base.queryParameters['shot'] ?? 'logs';

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _Note('つながりません: $_error');
    if (_logs == null) return const SizedBox.shrink();

    switch (_shot) {
      case 'auth':
        return const AuthScreen();
      case 'settings':
        return Screen(
          tab: 'settings',
          child: SettingsScreen(
            me: _me ?? Me(id: '', username: '', displayName: ''),
            pushHint: _pushHint,
          ),
        );
      case 'log':
        return Screen(tab: 'logs', child: LogScreen(log: _target, cuts: _logCuts));
      case 'logset':
        {
          final LogItem target = _target;
          final List<dynamic> raw = (_logDetail['members'] as List<dynamic>?) ?? <dynamic>[];
          return LogSetScreen(
            log: LogItem.fromJson(<String, dynamic>{
              ...(_logDetail['log'] as Map<String, dynamic>? ?? <String, dynamic>{}),
              'cut_count': target.cutCount,
            }),
            members: raw
                .map((dynamic m) => <Object>[
                      (m as Map<String, dynamic>)['display_name'] as String? ?? '',
                      m['role'] == 'owner',
                    ])
                .toList(),
          );
        }
      case 'day':
        {
          // いちばん新しい日を出す。見比べのときに中身が空だと形が分からない。
          final List<Cut> day = _cuts.where((Cut c) => c.localDate == _newestDay).toList()
            ..sort((Cut a, Cut b) => a.takenAt.compareTo(b.takenAt));
          return Screen(
            tab: 'logs',
            child: DayScreen(date: _newestDay, cuts: day, mediaUrl: _api.mediaUrl),
          );
        }
      case 'review':
        {
          // 撮ったばかりのものの代わりに、いちばん新しいカットを置いて形を確かめる
          final Cut? last = _cuts.isEmpty ? null : _cuts.first;
          return ReviewScreen(
            url: last == null ? '' : _api.mediaUrl(last.url),
            destination: last?.logName,
          );
        }
      case 'all':
        return Screen(
          tab: 'all',
          child: AllScreen(cuts: _cuts, mediaUrl: _api.mediaUrl),
        );
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
