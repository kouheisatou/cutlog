// アプリの入口と、画面の行き来。
// ★ 見比べのために `?shot=<名前>` で1枚だけ出せる口も残してある。
//   本物の web を同じ名前で撮って重ねるので、行き着く道が違うと比べられない。
import 'package:flutter/material.dart';

import 'data/api.dart';
import 'data/models.dart';
import 'design/text.dart';
import 'design/tokens.dart';
import 'screens/all_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/capture_screen.dart';
import 'screens/day_screen.dart';
import 'screens/log_screen.dart';
import 'screens/logs_screen.dart';
import 'screens/logset_screen.dart';
import 'screens/review_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sheets.dart';
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

/// いま出す画面を決める。
/// ★ 階層は web と同じ。「ログ一覧 → ログ → その日 / このログの設定」。
///   設定はログ一覧と並ぶ画面、カット一覧・マップは下のタブで並ぶ画面。
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final Api _api = Api();

  List<LogItem>? _logs;
  List<Cut> _cuts = <Cut>[];              // ログをまたいだ全部
  Me? _me;
  Map<String, dynamic> _config = <String, dynamic>{};
  String? _error;

  // いまいる場所
  String _tab = 'logs';
  String _stack = 'logs';                 // ログのタブの中の深さ
  LogItem? _log;
  List<Cut> _logCuts = <Cut>[];
  Map<String, dynamic> _logDetail = <String, dynamic>{};
  String? _day;
  List<Cut> _dayCuts = <Cut>[];
  String? _sheet;                         // 開いている札
  Cut? _cut;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 見比べのときだけ使う行き先。`?shot=logs` のように指す。
  String? get _shot => Uri.base.queryParameters['shot'];

  Future<void> _load() async {
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
      // 見比べのときは、決まったログを開いた状態にしておく
      if (_shot != null) await _openLog(_target, quiet: true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// 見比べで開くログ。中身があるものを選ぶ。
  LogItem get _target => _logs!.firstWhere(
        (LogItem l) => l.name == 'まいにち',
        orElse: () => _logs!.firstWhere((LogItem l) => l.cutCount > 0, orElse: () => _logs!.first),
      );

  String get _newestDay => _cuts.isEmpty ? '' : _cuts.first.localDate;

  /// web の設定画面と同じ文言。通知のキーが無いサーバでは、その旨だけを出す。
  String get _pushHint => _config['vapidPublicKey'] == null
      ? 'このサーバは通知のキー（VAPID）が未設定です。管理者が .env に設定すると使えます。'
      : '';

  // ── 行き来 ──────────────────────────────────────────
  Future<void> _openLog(LogItem log, {bool quiet = false}) async {
    final List<Cut> inLog = await _api.cutsOfLog(log.id);
    final Map<String, dynamic> detail = await _api.logDetail(log.id);
    if (!mounted) return;
    setState(() {
      _log = log;
      _logCuts = inLog;
      _logDetail = detail;
      if (!quiet) {
        _stack = 'log';
        _tab = 'logs';
      }
    });
  }

  Future<void> _openDay(String date) async {
    if (_log == null) return;
    final List<Cut> got = await _api.cutsOfLog(_log!.id, date: date);
    if (!mounted) return;
    setState(() {
      _day = date;
      _dayCuts = got..sort((Cut a, Cut b) => a.takenAt.compareTo(b.takenAt));
      _stack = 'day';
    });
  }

  void _selectTab(String tab) {
    if (tab == 'camera') {
      setState(() => _sheet = 'capture');
      return;
    }
    setState(() {
      _tab = tab;
      if (tab == 'logs') _stack = _stack == 'logs' ? 'logs' : _stack;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _Note('つながりません: $_error');
    if (_logs == null) return const SizedBox.shrink();

    final String where = _shot ?? _current;
    final Widget page = _pageFor(where);

    // 札は、いま見えている画面の上に重ねる
    switch (_sheet ?? (_shot != null && _isSheet(_shot!) ? _shot! : null)) {
      case 'logs-add':
        return LogAddSheet(under: page);
      case 'logs-search':
        return LogSearchSheet(under: page);
      case 'all-search':
        return SearchSheet(under: page);
      case 'cut':
        if (_cut != null) {
          return CutSheet(under: page, cut: _cut!, mediaUrl: _api.mediaUrl);
        }
        if (_cuts.isNotEmpty) {
          return CutSheet(under: page, cut: _cuts.first, mediaUrl: _api.mediaUrl);
        }
        return page;
      case 'capture':
        return CaptureScreen(
          destination: _log?.name ?? _target.name,
          onClose: () => setState(() => _sheet = null),
        );
      default:
        return page;
    }
  }

  bool _isSheet(String name) =>
      <String>['logs-add', 'logs-search', 'all-search', 'cut', 'capture'].contains(name);

  /// タブと深さから、いまの画面の名前を出す
  String get _current {
    if (_tab != 'logs') return _tab;
    return _stack;
  }

  Widget _pageFor(String where) {
    switch (where) {
      case 'auth':
        return const AuthScreen();

      case 'review':
        final Cut? last = _cuts.isEmpty ? null : _cuts.first;
        return ReviewScreen(
          url: last == null ? '' : _api.mediaUrl(last.url),
          destination: last?.logName,
          onClose: () => setState(() => _sheet = null),
        );

      case 'settings':
        return Screen(
          tab: 'settings',
          onTab: _selectTab,
          child: SettingsScreen(
            me: _me ?? Me(id: '', username: '', displayName: ''),
            pushHint: _pushHint,
          ),
        );

      case 'all':
      case 'all-search':
      case 'cut':
        return _allScreen();

      case 'map':
        return Screen(
          tab: 'map',
          onTab: _selectTab,
          child: const _Note('マップはこれから'),
        );

      case 'log':
        return Screen(
          tab: 'logs',
          onTab: _selectTab,
          child: LogScreen(
            log: _log ?? _target,
            cuts: _logCuts,
            onBack: () => setState(() => _stack = 'logs'),
            onDay: _openDay,
            onSettings: () => setState(() => _stack = 'logset'),
          ),
        );

      case 'logset':
        final List<dynamic> raw = (_logDetail['members'] as List<dynamic>?) ?? <dynamic>[];
        return LogSetScreen(
          log: LogItem.fromJson(<String, dynamic>{
            ...(_logDetail['log'] as Map<String, dynamic>? ?? <String, dynamic>{}),
            'cut_count': (_log ?? _target).cutCount,
          }),
          members: raw
              .map((dynamic m) => <Object>[
                    (m as Map<String, dynamic>)['display_name'] as String? ?? '',
                    m['role'] == 'owner',
                  ])
              .toList(),
          onBack: () => setState(() => _stack = 'log'),
        );

      case 'day':
        final List<Cut> day = _dayCuts.isNotEmpty
            ? _dayCuts
            : (_cuts.where((Cut c) => c.localDate == _newestDay).toList()
              ..sort((Cut a, Cut b) => a.takenAt.compareTo(b.takenAt)));
        return Screen(
          tab: 'logs',
          onTab: _selectTab,
          child: DayScreen(
            date: _day ?? _newestDay,
            cuts: day,
            mediaUrl: _api.mediaUrl,
            onBack: () => setState(() => _stack = 'log'),
          ),
        );

      case 'capture':
        return CaptureScreen(destination: _log?.name ?? _target.name);

      case 'logs':
      case 'logs-add':
      case 'logs-search':
      default:
        return _logsScreen();
    }
  }

  Widget _logsScreen() => Screen(
        tab: 'logs',
        onTab: _selectTab,
        child: LogsScreen(
          logs: _logs!,
          mediaUrl: _api.mediaUrl,
          onOpen: _openLog,
          onSearch: () => setState(() => _sheet = 'logs-search'),
          onAdd: () => setState(() => _sheet = 'logs-add'),
        ),
      );

  Widget _allScreen() => Screen(
        tab: 'all',
        onTab: _selectTab,
        child: AllScreen(
          cuts: _cuts,
          mediaUrl: _api.mediaUrl,
          onOpen: (Cut c) => setState(() {
            _cut = c;
            _sheet = 'cut';
          }),
          onSearch: () => setState(() => _sheet = 'all-search'),
        ),
      );
}

/// まだ作っていない画面の代わり。
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
