// アプリの入口と、画面の行き来。
// ★ 見比べのために `?shot=<名前>` で1枚だけ出せる口も残してある。
//   本物の web を同じ名前で撮って重ねるので、行き着く道が違うと比べられない。
import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'data/api.dart';
import 'data/save.dart';
import 'package:image_picker/image_picker.dart' show ImagePicker, ImageSource;

import 'data/media.dart';
import 'data/place.dart';
import 'data/models.dart';
import 'data/push.dart';
import 'design/text.dart';
import 'design/tokens.dart';
import 'screens/all_screen.dart';
import 'screens/auth_screen.dart';
import 'package:camera/camera.dart' show XFile;

import 'screens/capture_screen.dart';
import 'screens/day_screen.dart';
import 'screens/log_screen.dart';
import 'screens/logs_screen.dart';
import 'screens/map_screen.dart';
import 'screens/logset_screen.dart';
import 'screens/review_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sheets.dart';
import 'ui/controls.dart';
import 'ui/flow.dart';
import 'ui/sheet.dart';
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
  late final Push _push = Push(_api);

  List<LogItem>? _logs;
  List<Cut> _cuts = <Cut>[];              // ログをまたいだ全部
  Me? _me;
  Reminder _reminder = const Reminder();
  String? _defaultLogId;        // 既定の保存先
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
  String _logQuery = '';                  // カレンダーのメモ検索
  String _logAuthor = '';                 // カレンダーの投稿者の絞り込み
  String _logTag = '';                    // カレンダーの札の絞り込み

  /// まとめ動画の見た目。前に使ったものをサーバが覚えている。
  Map<String, dynamic>? _renderStyle;
  List<Cut> _mapPick = <Cut>[];           // 地図で押した場所のカット
  String _cutFilter = '';                 // カット一覧の絞り込み（メモ）
  String _cutAuthor = '';                 // カット一覧の絞り込み（撮った人）

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
        _api.logs(), _api.meRaw(), _api.config(), _api.allCuts(),
      ]);
      if (!mounted) return;
      final Map<String, dynamic> mine = got[1]! as Map<String, dynamic>;
      setState(() {
        _logs = got[0]! as List<LogItem>;
        _me = Me.fromJson(mine['user'] as Map<String, dynamic>);
        _reminder = Reminder.fromJson(mine['reminder'] as Map<String, dynamic>?);
        _defaultLogId = mine['defaultLogId'] as String?;
      _renderStyle = mine['renderStyle'] as Map<String, dynamic>?;
        _config = got[2]! as Map<String, dynamic>;
        _cuts = got[3]! as List<Cut>;
      });
      // ★ 1つも無いと、撮ろうにも置き場所が無い。最初の1つだけ用意しておく。
      if (_logs!.isEmpty) {
        await _api.createLog('マイログ');
        final List<LogItem> again = await _api.logs();
        if (mounted) setState(() => _logs = again);
      }

      // 通知の受け取り口。サーバが出せる設えのときだけ用意する。
      // ★ ここで失敗しても、他の機能は止めない。
      if (_config['fcmEnabled'] == true && !kIsWeb) unawaited(_push.start());

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
          openSearchSheet(context, initial: '', onSearch: (String _, String _) {});
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
          if (bad != null) return bad;
          await _reload();
          if (!mounted) return null;
          // ★ 作ってすぐ撮れるようにする。作っただけで放り出さない（web と同じ）。
          final LogItem made = _logs!.firstWhere((LogItem l) => l.name == name,
              orElse: () => _target);
          setState(() {
            _log = made;
            _stack = 'log';
            _tab = 'logs';
          });
          WidgetsBinding.instance.addPostFrameCallback((_) => _openCapture());
          return null;
        },
        onJoin: (String code) async {
          final String? bad = await _api.joinLog(code);
          if (bad != null) return bad;
          await _reload();
          if (context.mounted) toast(context, 'ログに参加しました');
          return null;
        },
      );

  Future<void> _sheetCut(BuildContext context, Cut cut) => openCutSheet(
        context,
        cut: cut,
        media: _media,
        load: () => _api.cutDetail(cut.id),
        onDelete: () async {
          final String? bad = await _api.deleteCut(cut.id);
          if (bad == null) await _reload();
          return bad;
        },
        onComment: (String body) => _api.addComment(cut.id, body),
        onReact: (String emoji) => _api.react(cut.id, emoji),
        onNote: (String note) async {
          final String? bad = await _api.setNote(cut.id, note);
          if (bad == null) await _reload();
          return bad;
        },
        onDeleteComment: (String id) => _api.deleteComment(id),
        // ★ 端末の外へ渡す。アプリの中で保存先を選ばせるより、
        //   端末が持っている仕組みに任せたほうが迷わない。
        onDownload: (String url) async {
          final String? bad = await Saver(_api).save(url, _fileNameOf(cut));
          if (bad != null && context.mounted) toast(context, bad);
        },
        onMove: () => openMoveSheet(
          context,
          logs: _logs!,
          fromLogId: cut.logId,
          onMove: (String logId) async {
            final String? bad = await _api.moveCut(cut.id, logId);
            if (bad != null) return bad;
            await _reload();
            if (context.mounted) Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
            return null;
          },
        ),
      );

  /// 撮る → 確かめる → 残す。
  /// ★ 撮った直後に送らない。確かめる画面を挟むのは、撮り直しの余地を残すため。
  void _openCapture() {
    LogItem dest = _log ?? _target;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (BuildContext page) => StatefulBuilder(
        builder: (BuildContext page, void Function(void Function()) refresh) => CaptureScreen(
          destination: dest.name,
          cutSeconds: dest.cutSeconds,
          onClose: () => Navigator.of(page).maybePop(),
          onShot: (XFile file, int durationMs) => _openReview(dest, file, durationMs),
          // 記録先はこの撮影のあいだだけ。既定の保存先は変えない。
          onPickDest: () => openMoveSheet(
            page,
            logs: _logs!,
            fromLogId: '',
            title: 'この撮影の記録先',
            note: '撮るたびに、開いているログへ戻ります。',
            onMove: (String logId) async {
              refresh(() => dest = _logs!.firstWhere((LogItem l) => l.id == logId));
              return null;
            },
          ),
          onImport: () async {
            // まとめて取り込める。1本ずつ確かめてもらい、途中でやめたらそこで止める。
            final List<XFile> got = await ImagePicker().pickMultipleMedia();
            if (got.isEmpty || !page.mounted) return;
            for (final XFile f in got) {
              if (!mounted) return;
              final bool saved =
                  await _openReview(dest, f, 0, fromFile: true, closeAll: false);
              if (!saved) return;
            }
            if (mounted) {
              Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
            }
          },
        ),
      ),
    ));
  }

  /// 撮った（取り込んだ）ものを確かめる画面。しまったら true。
  /// ★ [closeAll] が false のときは、この画面だけ閉じて撮影の画面には戻さない。
  ///   まとめて取り込むときに、1本ごとに最初まで戻ってしまうのを避ける。
  Future<bool> _openReview(LogItem dest, XFile file, int durationMs,
      {bool fromFile = false, bool closeAll = true}) async {
    final bool? saved = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
      builder: (BuildContext sheet) => ReviewScreen(
        file: file,
        destination: dest.name,
        onRetake: () => Navigator.of(sheet).pop(false),
        onClose: () => Navigator.of(sheet).pop(false),
        onSave: (String note) async {
          final DateTime now = DateTime.now();
          // 撮った場所。取れなくても止めない。
          final Place? here = fromFile ? null : await askPlace();
          final String? bad = await _api.uploadCut(
            logId: dest.id,
            bytes: await file.readAsBytes(),
            filename: file.name.isEmpty ? 'cut.mp4' : file.name,
            mime: _mimeOf(file.name),
            meta: <String, dynamic>{
              'kind': _mimeOf(file.name).startsWith('image/') ? 'photo' : 'video',
              if (durationMs > 0) 'durationMs': durationMs,
              'takenAt': now.toUtc().toIso8601String(),
              'tzOffset': -now.timeZoneOffset.inMinutes,
              'source': fromFile ? 'upload' : 'camera',
              if (note.isNotEmpty) 'note': note,
              if (here != null) 'lat': here.lat,
              if (here != null) 'lon': here.lon,
              if (here != null) 'accuracy': here.accuracy,
            },
          );
          if (bad != null) return bad;
          await _reload();
          if (!sheet.mounted) return null;
          if (closeAll) {
            // 確かめる画面と撮影の画面を、まとめて畳む
            Navigator.of(sheet).popUntil((Route<dynamic> r) => r.isFirst);
          } else {
            Navigator.of(sheet).pop(true);
          }
          return null;
        },
      ),
    ));
    return saved ?? false;
  }

  /// 名前の末尾から中身の型を決める。分からなければ動画として扱う。
  String _mimeOf(String name) {
    final String n = name.toLowerCase();
    if (n.endsWith('.webm')) return 'video/webm';
    if (n.endsWith('.mov')) return 'video/quicktime';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.heic')) return 'image/heic';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    return 'video/mp4';
  }

  /// ゴミ箱。消したカットを戻せる。
  Future<void> _openTrash(BuildContext context) async {
    final List<Cut> gone = await _api.trash((_log ?? _target).id);
    if (!context.mounted) return;
    await openSheet<void>(
      context,
      children: <Widget>[
        Builder(
          builder: (BuildContext context) {
            final Space sp = spaceOf(context);
            return CssColumn(<Block>[
              Block(const SheetTitle('ゴミ箱'), bottom: sp.s1),
              if (gone.isEmpty)
                Block(Text('消したカットはありません。', style: Typo.of(context).small), top: sp.s2)
              else
                for (final Cut c in gone)
                  Block(
                    Row(children: <Widget>[
                      Expanded(
                        child: Text(
                          '\${c.localDate} \${c.hhmm}　\${c.note ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Typo.of(context).body.copyWith(fontSize: 14),
                        ),
                      ),
                      MiniBtn('戻す', onTap: () async {
                        final String? bad = await _api.restoreCut(c.id);
                        if (!context.mounted) return;
                        if (bad != null) {
                          toast(context, bad);
                          return;
                        }
                        Navigator.of(context).pop();
                        await _reload();
                      }),
                    ]),
                    top: sp.s1,
                    bottom: sp.s1,
                  ),
            ], outer: false);
          },
        ),
      ],
    );
  }

  /// カレンダーの中身を絞り込みつきで取り直す
  Future<void> _reloadLogCuts() async {
    final LogItem target = _log ?? _target;
    final String? id = _logAuthor.isEmpty
        ? null
        : ((_logDetail['members'] as List<dynamic>? ?? <dynamic>[])
                .cast<Map<String, dynamic>>()
                .firstWhere((Map<String, dynamic> m) => m['display_name'] == _logAuthor,
                    orElse: () => <String, dynamic>{})['id'] as String?);
    final List<Cut> got = await _api.cutsOfLog(
      target.id,
      query: _logQuery.isEmpty ? null : _logQuery,
      author: id,
      tag: _logTag.isEmpty ? null : _logTag,
    );
    if (mounted) setState(() => _logCuts = got);
  }

  /// 自分のことだけ取り直す（既定の保存先を変えたあとなど）
  Future<void> _loadMe() async {
    final Map<String, dynamic> mine = await _api.meRaw();
    if (!mounted) return;
    setState(() {
      _me = Me.fromJson(mine['user'] as Map<String, dynamic>);
      _reminder = Reminder.fromJson(mine['reminder'] as Map<String, dynamic>?);
      _defaultLogId = mine['defaultLogId'] as String?;
      _renderStyle = mine['renderStyle'] as Map<String, dynamic>?;
    });
  }

  /// 共有リンクの一覧
  Future<void> _openShares(BuildContext context) async {
    final List<ShareLink> got = await _api.shares((_log ?? _target).id);
    if (!context.mounted) return;
    await openSharesSheet(
      context,
      shares: got,
      onRevoke: (String id) async {
        final String? bad = await _api.revokeShare(id);
        if (bad == null && context.mounted) {
          Navigator.of(context).pop();
          toast(context, '共有リンクを停止しました');
        }
        return bad;
      },
      onCopy: (String url) async {
        await Clipboard.setData(ClipboardData(text: url));
        if (context.mounted) toast(context, 'コピーしました');
      },
    );
  }

  /// その日のぶんで共有リンクを作る
  Future<void> _shareDay(BuildContext context, List<Cut> day) async {
    if (day.isEmpty) {
      toast(context, 'この日にはカットがありません');
      return;
    }
    final (String? bad, String? url) = await _api.createShare(
      logId: (_log ?? _target).id,
      cutIds: day.map((Cut c) => c.id).toList(),
      title: _day ?? '共有',
    );
    if (!context.mounted) return;
    if (bad != null) {
      toast(context, bad);
      return;
    }
    await Clipboard.setData(ClipboardData(text: url ?? ''));
    if (context.mounted) toast(context, '共有リンクを作り、コピーしました');
  }

  /// その日のぶんでまとめ動画を作る。
  /// ★ 作るのに時間がかかるので、できたかどうかを 2 秒おきに見に行く。
  Future<void> _renderDay(BuildContext context, List<Cut> day) async {
    if (day.isEmpty) {
      toast(context, 'この日にはカットがありません');
      return;
    }
    // 前に使った見た目を出しておく。触らずに作ることもできる。
    final Map<String, dynamic>? style = await openRenderSheet(
      context,
      style: _renderStyle ?? <String, dynamic>{},
    );
    if (style == null || !context.mounted) return;
    _renderStyle = style;

    final (String? bad, String? jobId) = await _api.startRender(
      logId: (_log ?? _target).id,
      cutIds: day.map((Cut c) => c.id).toList(),
      label: _day ?? 'まとめ',
      style: style,
    );
    if (!context.mounted) return;
    if (bad != null || jobId == null) {
      toast(context, bad ?? '作れませんでした');
      return;
    }
    toast(context, '動画を作っています…');

    // 5 分見て終わらなければ諦める（延々と見に行かない）
    for (int i = 0; i < 150; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!context.mounted) return;
      try {
        final Map<String, dynamic> job = await _api.job(jobId);
        if (job['status'] == 'done') {
          final String? url = (job['result'] as Map<String, dynamic>?)?['url'] as String?;
          if (!context.mounted) return;
          toast(context, '動画ができました');
          if (url != null) {
            await Saver(_api).save(_api.mediaUrl(url), 'cutlog_${_day ?? 'matome'}.mp4');
          }
          return;
        }
        if (job['status'] == 'error') {
          if (context.mounted) toast(context, '作れませんでした: ${job['message'] ?? ''}');
          return;
        }
      } catch (_) {
        // 一度取れなくても、次の回に賭ける
      }
    }
    if (context.mounted) toast(context, '時間がかかっています。あとで確認してください');
  }

  /// その日の中身を取り直す
  Future<void> _reloadDay() async {
    if (_log == null || _day == null) {
      await _reload();
      return;
    }
    final List<Cut> got = await _api.cutsOfLog(_log!.id, date: _day!);
    if (!mounted) return;
    setState(() => _dayCuts = got..sort((Cut a, Cut b) => a.takenAt.compareTo(b.takenAt)));
  }

  /// まとめて消す。
  /// ★ 1件ずつ送り、失敗した分だけを知らせて残りは続ける。
  ///   途中で止めると「どこまで消えたか」が分からなくなる。
  Future<void> _deleteMany(BuildContext context, List<Cut> picked) async {
    final bool yes = await confirm(
      context,
      '${picked.length}件のカットを削除しますか。ゴミ箱から戻せます。',
      '削除',
    );
    if (!yes) return;

    int done = 0;
    for (final Cut c in picked) {
      final String? bad = await _api.deleteCut(c.id);
      if (bad == null) {
        done++;
      } else if (context.mounted) {
        toast(context, bad);
      }
    }
    await _reload();
    if (context.mounted) toast(context, '$done件を削除しました');
  }

  /// 持ち出すときの名前。中身に合った拡張子を付けないと、開けないことがある。
  String _fileNameOf(Cut cut) =>
      'cutlog_${cut.id}.${cut.kind == 'photo' ? 'jpg' : 'mp4'}';

  /// まとめて持ち出す。
  /// ★ カットはログをまたいで選べるが、書き出しはログ単位でしか作れない。
  ///   ログごとに分けて、それぞれ1つの zip にする。
  Future<void> _exportMany(BuildContext context, List<Cut> picked) async {
    final Map<String, List<String>> byLog = <String, List<String>>{};
    for (final Cut c in picked) {
      byLog.putIfAbsent(c.logId, () => <String>[]).add(c.id);
    }

    if (context.mounted) toast(context, '書き出しています…');
    int done = 0;
    for (final MapEntry<String, List<String>> e in byLog.entries) {
      final String? bad = await Saver(_api).save(
        _api.exportUrl(e.key, e.value),
        'cutlog_${e.key}.zip',
      );
      if (bad == null) {
        done += e.value.length;
      } else if (context.mounted) {
        toast(context, bad);
        return;
      }
    }
    if (context.mounted) toast(context, '$done件を書き出しました');
  }

  /// まとめて移す
  Future<void> _moveMany(BuildContext context, List<Cut> picked) async {
    await openMoveSheet(
      context,
      logs: _logs!,
      fromLogId: picked.first.logId,
      onMove: (String logId) async {
        int done = 0;
        String? last;
        for (final Cut c in picked) {
          final String? bad = await _api.moveCut(c.id, logId);
          if (bad == null) {
            done++;
          } else {
            last = bad;
          }
        }
        await _reload();
        if (done == 0) return last ?? '移せませんでした';
        if (context.mounted) {
          toast(context, done == picked.length
              ? '$done件を移しました'
              : '$done件を移しました。${picked.length - done}件は移せませんでした。');
        }
        return null;
      },
    );
  }

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
      _openCapture();
      return;
    }
    setState(() {
      _tab = tab;
      if (tab == 'logs') _stack = _stack == 'logs' ? 'logs' : _stack;
    });
  }

  @override
  Widget build(BuildContext context) {
    // ★ 白いまま止めない。つないでいる最中か、つまずいたのかを必ず出す。
    if (_error != null) {
      return _Trouble(
        message: _error!,
        where: _api.where,
        onRetry: () {
          setState(() {
            _error = null;
            _logs = null;
          });
          _load();
        },
      );
    }
    if (_needAuth && _shot == null) return AuthScreen(onSubmit: _signIn);
    if (_logs == null) return const _Waiting();

    final String where = _shot ?? _current;
    return ScreenSwap(depth: _depthOf(where), child: _pageFor(where));
  }

  /// 画面の深さ。web と同じく ログ一覧:0 → ログ:1 → その日/設定:2。
  int _depthOf(String where) => switch (where) {
        'log' => 1,
        'logset' || 'day' => 2,
        'maplist' => 1,
        _ => 0,
      };

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
          url: last == null ? null : _api.mediaUrl(last.url),
          headers: _api.mediaHeaders,
          destination: last?.logName,
          onClose: () => Navigator.of(context).maybePop(),
        );

      case 'settings':
        return Screen(
          tab: 'settings',
          onTab: _selectTab,
          child: Builder(
            builder: (BuildContext context) => SettingsScreen(
              me: _me ?? Me(id: '', username: '', displayName: ''),
              pushHint: _pushHint,
              reminder: _reminder,
              avatarUrl: _me?.avatarUrl == null ? null : _api.mediaUrl(_me!.avatarUrl!),
              avatarHeaders: _api.mediaHeaders,
              onEnablePush: () async {
                if (_config['fcmEnabled'] != true) {
                  return 'このサーバは通知の設定がまだ済んでいません。管理者にお問い合わせください';
                }
                return _push.start();
              },
              onPickAvatar: () async {
                final XFile? got =
                    await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512);
                if (got == null) return '選ばれませんでした';
                final String? bad = await _api.setAvatar(
                  await got.readAsBytes(),
                  got.name.isEmpty ? 'avatar.jpg' : got.name,
                  got.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg',
                );
                if (bad == null) await _loadMe();
                return bad;
              },
              onClearAvatar: () async {
                final String? bad = await _api.clearAvatar();
                if (bad == null) await _loadMe();
                return bad;
              },
              onSaveReminder: (Reminder r) async {
                final String? bad = await _api.saveReminder(r);
                if (bad == null && mounted) setState(() => _reminder = r);
                return bad;
              },
              onTestPush: _api.testPush,
              onLogout: () async {
                final bool yes = await confirm(context, 'ログアウトしますか？', 'ログアウト');
                if (!yes) return;
                await _api.logout();
                if (!mounted) return;
                setState(() {
                  _needAuth = true;
                  _logs = <LogItem>[];
                  _cuts = <Cut>[];
                  _tab = 'logs';
                  _stack = 'logs';
                });
              },
            ),
          ),
        );

      case 'all':
      case 'all-search':
      case 'cut':
        return _allScreen();

      case 'maplist':
        return Screen(
          tab: 'map',
          onTab: _selectTab,
          child: Builder(
            builder: (BuildContext context) => AllScreen(
              cuts: _mapPick,
              media: _media,
              title: 'この場所の${_mapPick.length}件',
              onBack: () => setState(() => _tab = 'map'),
              onOpen: (Cut c) => _sheetCut(context, c),
            ),
          ),
        );

      case 'map':
        return Screen(
          tab: 'map',
          onTab: _selectTab,
          child: Padding(
            // CSS: .body.full { padding: 0 0 calc(57px + safe) } — 地図は下の帯以外を全部使う
            padding: EdgeInsets.only(bottom: 57 + MediaQuery.paddingOf(context).bottom),
            child: Builder(
              builder: (BuildContext context) => MapScreen(
                cuts: _cuts,
                media: _media,
                tileUrl: (_config['mapTileUrl'] as String?) ??
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                onOpen: (List<Cut> here) => setState(() {
                  _mapPick = here..sort((Cut a, Cut b) => b.takenAt.compareTo(a.takenAt));
                  _tab = 'maplist';
                }),
              ),
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
            members: ((_logDetail['members'] as List<dynamic>?) ?? <dynamic>[])
                .map((dynamic m) => (m as Map<String, dynamic>)['display_name'] as String? ?? '')
                .where((String n) => n.isNotEmpty)
                .toList(),
            query: _logQuery,
            author: _logAuthor,
            tag: _logTag,
            onFilter: (String q, String author, String tag) async {
              setState(() {
                _logQuery = q;
                _logAuthor = author;
                _logTag = tag;
              });
              await _reloadLogCuts();
            },
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
          owner: _logDetail['role'] == 'owner',
          isDefault: _defaultLogId == (_log ?? _target).id,
          members: raw
              .map((dynamic m) => <Object>[
                    (m as Map<String, dynamic>)['id'] as String? ?? '',
                    m['display_name'] as String? ?? '',
                    m['role'] == 'owner',
                  ])
              .toList(),
          onRemoveMember: (String userId, String name) async {
            final String? bad = await _api.removeMember((_log ?? _target).id, userId);
            if (bad == null) await _openLog(_log ?? _target, quiet: true);
            return bad;
          },
          onDefault: (bool on) async {
            final String? bad = await _api.setDefaultLog(on ? (_log ?? _target).id : null);
            if (bad == null) await _loadMe();
            return bad;
          },
          onShares: () => _openShares(context),
          onBack: () => setState(() => _stack = 'log'),
          onSave: (String name, int seconds) async {
            final String? bad = await _api.renameLog(
              (_log ?? _target).id,
              name: name,
              cutSeconds: seconds,
            );
            if (bad == null) await _reload();
            return bad;
          },
          onRotate: () async {
            final String? bad = await _api.rotateInvite((_log ?? _target).id);
            if (bad == null) await _reload();
            return bad;
          },
          onTrash: () => _openTrash(context),
        );

      case 'day':
        final List<Cut> day = _dayCuts.isNotEmpty
            ? _dayCuts
            : (_cuts.where((Cut c) => c.localDate == _newestDay).toList()
              ..sort((Cut a, Cut b) => a.takenAt.compareTo(b.takenAt)));
        return Screen(
          tab: 'logs',
          onTab: _selectTab,
          child: Builder(
            builder: (BuildContext context) => DayScreen(
              date: _day ?? _newestDay,
              cuts: day,
              media: _media,
              cutSeconds: (_log ?? _target).cutSeconds,
              onBack: () => setState(() => _stack = 'log'),
              onToggleHidden: (Cut cut, bool hidden) async {
                final String? bad = await _api.setHidden(cut.id, hidden);
                if (bad != null) return bad;
                await _reloadDay();
                if (context.mounted) {
                  toast(context, hidden ? '非表示にしました' : '表示に戻しました');
                }
                return null;
              },
              onDetail: (Cut cut) => _sheetCut(context, cut),
              onComments: (Cut cut) => _sheetCut(context, cut),
              onShare: () => _shareDay(context, day),
              onRender: () => _renderDay(context, day),
            ),
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

  /// 絵や動画の取りに行き方。道とヘッダを組にして画面へ渡す。
  /// ★ ブラウザは cookie を勝手に付けるが、端末では誰も付けない。組にして渡し忘れを無くす。
  Media get _media => Media(_api.mediaUrl, _api.mediaHeaders);

  Widget _logsScreen() => Screen(
        tab: 'logs',
        onTab: _selectTab,
        child: Builder(
          builder: (BuildContext context) => LogsScreen(
            logs: _visibleLogs,
            media: _media,
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
            media: _media,
            filter: _cutFilterLabel,
            onOpen: (Cut c) => _sheetCut(context, c),
            onSearch: () => openSearchSheet(
              context,
              initial: _cutFilter,
              initialAuthor: _cutAuthor,
              authors: _authors,
              onSearch: (String q, String author) => setState(() {
                _cutFilter = q;
                _cutAuthor = author;
              }),
            ),
            onExport: (List<Cut> picked) => _exportMany(context, picked),
            onDelete: (List<Cut> picked) => _deleteMany(context, picked),
            onMove: (List<Cut> picked) => _moveMany(context, picked),
          ),
        ),
      );

  /// 絞り込みの結果。空なら全部。
  /// 絞り込みの結果。空なら全部。
  /// ★ 名前だけでなくオーナー名にも当てる（web と同じ）。
  List<LogItem> get _visibleLogs {
    if (_logFilter.isEmpty) return _logs!;
    final String q = _logFilter.toLowerCase();
    return _logs!
        .where((LogItem l) => '${l.name} ${l.ownerName ?? ''}'.toLowerCase().contains(q))
        .toList();
  }

  List<Cut> get _visibleCuts => _cuts
      .where((Cut c) => _cutFilter.isEmpty || (c.note ?? '').contains(_cutFilter))
      .where((Cut c) => _cutAuthor.isEmpty || c.userId == _cutAuthor)
      .toList();

  /// 撮った人の顔ぶれ。同じ人は一度だけ、出てきた順に並べる。
  /// ★ 絞ったあとの一覧から作ると候補が自分自身に縮むので、必ず全部から拾う。
  List<({String id, String label})> get _authors {
    final Map<String, String> seen = <String, String>{};
    for (final Cut c in _cuts) {
      if (c.userId.isEmpty) continue;
      seen.putIfAbsent(c.userId, () => (c.author ?? '').isEmpty ? c.userId : c.author!);
    }
    return seen.entries
        .map((MapEntry<String, String> e) => (id: e.key, label: e.value))
        .toList();
  }

  /// 帯に出す文言。web の paintAllFilter と同じ組み立て。
  String get _cutFilterLabel {
    final String who = _cutAuthor.isEmpty
        ? ''
        : _authors
                .where((({String id, String label}) a) => a.id == _cutAuthor)
                .map((({String id, String label}) a) => a.label)
                .firstOrNull ??
            '';
    return <String>[
      if (_cutFilter.isNotEmpty) 'メモ「$_cutFilter」',
      if (who.isNotEmpty) '$who のぶん',
    ].join('\u3000');
  }
}

/// つないでいる最中。
class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    return ColoredBox(
      color: c.paper,
      child: Center(child: Text(upper('つないでいます'), style: Typo(c).sectionHead)),
    );
  }
}

/// つまずいたとき。何が起きたか・どこへつなごうとしたか・もう一度、を出す。
/// ★ 訳を隠さない。手元のサーバへつなぐ使い方が多いので、
///   「どこへつなごうとしたか」が分かるだけで直せることが多い。
class _Trouble extends StatelessWidget {
  const _Trouble({required this.message, required this.where, required this.onRetry});

  final String message;
  final String where;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Typo t = Typo(c);
    final Space sp = spaceOf(context);

    return ColoredBox(
      color: c.paper,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(sp.s4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(upper('つながりません'), style: t.sectionHead),
              SizedBox(height: sp.s3),
              Text(message, textAlign: TextAlign.center, style: t.body.copyWith(fontSize: 13)),
              SizedBox(height: sp.s2),
              Text('つなぎ先 $where', textAlign: TextAlign.center, style: t.small),
              SizedBox(height: sp.s5),
              PrimaryBtn('もう一度', onTap: onRetry),
            ],
          ),
        ),
      ),
    );
  }
}

