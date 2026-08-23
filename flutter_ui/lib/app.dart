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
import 'screens/map_screen.dart';
import 'screens/logset_screen.dart';
import 'screens/review_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sheets.dart';
import 'ui/shell.dart';

class CutlogApp extends StatelessWidget {
  const CutlogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'cutlog',
      debugShowCheckedModeBanner: false,
      // ★ 配色と余白は、道案内（Navigator）より外側で配る。
      //   札やダイアログは道案内の上に積まれるので、内側で配ると
      //   その中から見えず、中身が組み上がらないまま黙って消える。
      //   実際、それで「開くのに何も出ない札」になっていた。
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData mq = MediaQuery.of(context);
        final bool dark = mq.platformBrightness == Brightness.dark;
        return Skin(
          palette: dark ? Palette.darkMode : Palette.lightMode,
          space: Space.forWidth(mq.size.width),
          child: Builder(
            builder: (BuildContext context) => Material(
              // ★ 書く所（TextField）は Material の下に居ないと組み上がらない。
              //   見た目は足したくないので、透けたものを1枚だけ敷く。
              type: MaterialType.transparency,
              child: DefaultTextStyle(
                // ★ 敷かないと、字の指定が無い所に Flutter の目印（黄色い二重下線）が出る。
                style: Typo.of(context).body,
                child: ColoredBox(
                  color: colorsOf(context).paper,
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        );
      },
      home: const _Host(),
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
  bool _needAuth = false;

  // いまいる場所
  String _tab = 'logs';
  String _stack = 'logs';                 // ログのタブの中の深さ
  LogItem? _log;
  List<Cut> _logCuts = <Cut>[];
  Map<String, dynamic> _logDetail = <String, dynamic>{};
  String? _day;
  List<Cut> _dayCuts = <Cut>[];
  String _logFilter = '';                 // ログ一覧の絞り込み
  String _cutFilter = '';                 // カット一覧の絞り込み

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
    // 前に入ったときの鍵を思い出す（web ではブラウザが持っている）
    await _api.restore();
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
      if (_shot != null) {
        await _openLog(_target, quiet: true);
        _openShotSheet();
      }
    } catch (e) {
      if (!mounted) return;
      // 鍵が無い・切れているときは、ログインの画面を出す。それ以外は訳を出す。
      if (e.toString().contains('401')) {
        setState(() {
          _needAuth = true;
          _logs = <LogItem>[];
        });
      } else {
        setState(() => _error = e.toString());
      }
    }
  }

  Future<String?> _signIn(String username, String password) async {
    final String? bad = await _api.login(username, password);
    if (bad != null) return bad;
    if (!mounted) return null;
    setState(() {
      _needAuth = false;
      _logs = null;
    });
    await _load();
    return null;
  }

  /// 見比べのときだけ、指した札を自分で開く。
  /// ★ 札は標準の仕組みで押し出すので、絵に写すには実際に開いておく必要がある。
  void _openShotSheet() {
    final String? name = _shot;
    if (name == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (name) {
        case 'logs-add':
          _sheetLogAdd(context);
        case 'logs-search':
          openLogSearchSheet(context, initial: '', onSearch: (String _) {});
        case 'all-search':
          openSearchSheet(context, initial: '', onSearch: (String _) {});
        case 'cut':
          if (_cuts.isNotEmpty) _sheetCut(context, _cuts.first);
      }
    });
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

  // ── 札を開く ────────────────────────────────────────
  Future<void> _sheetLogAdd(BuildContext context) => openLogAddSheet(
        context,
        onCreate: (String name) async {
          final String? bad = await _api.createLog(name);
          if (bad == null) await _reload();
          return bad;
        },
        onJoin: (String code) async {
          final String? bad = await _api.joinLog(code);
          if (bad == null) await _reload();
          return bad;
        },
      );

  Future<void> _sheetCut(BuildContext context, Cut cut) => openCutSheet(
        context,
        cut: cut,
        mediaUrl: _api.mediaUrl,
        onDelete: () async {
          final String? bad = await _api.deleteCut(cut.id);
          if (bad == null) await _reload();
          return bad;
        },
        onComment: (String body) => _api.addComment(cut.id, body),
        onReact: (String emoji) => _api.react(cut.id, emoji),
      );

  /// 中身を取り直す（作った・消した・移した あとに呼ぶ）
  Future<void> _reload() async {
    final List<Object?> got = await Future.wait(<Future<Object?>>[
      _api.logs(), _api.allCuts(),
    ]);
    if (!mounted) return;
    setState(() {
      _logs = got[0]! as List<LogItem>;
      _cuts = got[1]! as List<Cut>;
    });
    if (_log != null) await _openLog(_log!, quiet: true);
  }

  void _selectTab(String tab) {
    if (tab == 'camera') {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (BuildContext _) => CaptureScreen(
          destination: _log?.name ?? _target.name,
          onClose: () => Navigator.of(context).maybePop(),
        ),
      ));
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
    if (_needAuth && _shot == null) return AuthScreen(onSubmit: _signIn);
    if (_logs == null) return const SizedBox.shrink();

    return _pageFor(_shot ?? _current);
  }

  /// タブと深さから、いまの画面の名前を出す
  String get _current {
    if (_tab != 'logs') return _tab;
    return _stack;
  }

  Widget _pageFor(String where) {
    switch (where) {
      case 'auth':
        return AuthScreen(onSubmit: _signIn);

      case 'review':
        final Cut? last = _cuts.isEmpty ? null : _cuts.first;
        return ReviewScreen(
          url: last == null ? '' : _api.mediaUrl(last.url),
          destination: last?.logName,
          onClose: () => Navigator.of(context).maybePop(),
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
          child: Padding(
            // CSS: .body.full { padding: 0 0 calc(57px + safe) } — 地図は下の帯以外を全部使う
            padding: EdgeInsets.only(bottom: 57 + MediaQuery.paddingOf(context).bottom),
            child: MapScreen(
              cuts: _cuts,
              mediaUrl: _api.mediaUrl,
              tileUrl: (_config['mapTileUrl'] as String?) ??
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            ),
          ),
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
        child: Builder(
          builder: (BuildContext context) => LogsScreen(
            logs: _visibleLogs,
            mediaUrl: _api.mediaUrl,
            onOpen: _openLog,
            onSearch: () => openLogSearchSheet(
              context,
              initial: _logFilter,
              onSearch: (String q) => setState(() => _logFilter = q),
            ),
            onAdd: () => _sheetLogAdd(context),
          ),
        ),
      );

  Widget _allScreen() => Screen(
        tab: 'all',
        onTab: _selectTab,
        child: Builder(
          builder: (BuildContext context) => AllScreen(
            cuts: _visibleCuts,
            mediaUrl: _api.mediaUrl,
            onOpen: (Cut c) => _sheetCut(context, c),
            onSearch: () => openSearchSheet(
              context,
              initial: _cutFilter,
              onSearch: (String q) => setState(() => _cutFilter = q),
            ),
          ),
        ),
      );

  /// 絞り込みの結果。空なら全部。
  List<LogItem> get _visibleLogs => _logFilter.isEmpty
      ? _logs!
      : _logs!.where((LogItem l) => l.name.contains(_logFilter)).toList();

  List<Cut> get _visibleCuts => _cutFilter.isEmpty
      ? _cuts
      : _cuts.where((Cut c) => (c.note ?? '').contains(_cutFilter)).toList();
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
