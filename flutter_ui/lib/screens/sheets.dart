// 下からせり上がる札の中身。器（SheetPanel）は同じで、並べるものだけが違う。
// ★ 閉じ方は標準の振る舞いに任せる。ここでは「何を並べるか」と「押したら何をするか」だけを書く。
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../data/media.dart';
import '../data/models.dart';
import '../design/icons.dart';
import '../design/text.dart';
import '../design/tokens.dart';
import '../ui/controls.dart';
import '../ui/flow.dart';
import '../ui/sheet.dart';
import '../ui/shell.dart';

/// ログを追加（ログ一覧の右上から開く）
Future<void> openLogAddSheet(
  BuildContext context, {
  required Future<String?> Function(String name) onCreate,
  required Future<String?> Function(String code) onJoin,
}) {
  final TextEditingController name = TextEditingController();
  final TextEditingController code = TextEditingController();

  return openSheet<void>(
    context,
    children: <Widget>[
      _Body(
        builder: (BuildContext context, _Report say) {
          final Space sp = spaceOf(context);
          return CssColumn(<Block>[
            Block(const SheetTitle('ログを追加'), bottom: sp.s1),
            Block(const SheetHead('新しく作る'), top: sp.s5, bottom: sp.s2),
            Block(SheetRow(children: <Widget>[
              SheetField(
                hint: 'ログのタイトル',
                width: 149,
                controller: name,
                onSubmit: () => say(context, () => onCreate(name.text.trim())),
              ),
              PrimaryBtn('作成', onTap: () => say(context, () => onCreate(name.text.trim()))),
            ]), top: sp.s2, bottom: sp.s2),
            Block(const SheetHead('招待コードで参加する'), top: sp.s5, bottom: sp.s2),
            Block(SheetRow(children: <Widget>[
              SheetField(
                hint: '招待コード',
                width: 149,
                controller: code,
                onSubmit: () => say(context, () => onJoin(code.text.trim())),
              ),
              TextBtn('参加', onTap: () => say(context, () => onJoin(code.text.trim()))),
            ]), top: sp.s2, bottom: sp.s2),
          ], outer: false);
        },
      ),
    ],
  );
}

/// ログを検索（ログ一覧の右上から開く）
Future<void> openLogSearchSheet(
  BuildContext context, {
  required String initial,
  required void Function(String q) onSearch,
}) {
  final TextEditingController q = TextEditingController(text: initial);

  return openSheet<void>(
    context,
    children: <Widget>[
      Builder(
        builder: (BuildContext context) {
          final Space sp = spaceOf(context);
          return CssColumn(<Block>[
            Block(const SheetTitle('ログを検索'), bottom: sp.s1),
            Block(_LabeledRow(label: 'タイトル', hint: 'ログのタイトルを入力してください', width: 175, controller: q),
                top: sp.s2, bottom: sp.s2),
            Block(SheetActions(children: <Widget>[
              TextBtn('絞り込みをリセット', onTap: () {
                onSearch('');
                Navigator.of(context).pop();
              }),
              PrimaryBtn('検索', onTap: () {
                onSearch(q.text.trim());
                Navigator.of(context).pop();
              }),
            ]), top: sp.s5),
          ], outer: false);
        },
      ),
    ],
  );
}

/// ひとつ選ぶだけの小さな板。Picker から呼ぶ。
/// ★ 選び直せる顔ぶれは呼ぶ側が決める。ここは並べて返すだけ。
Future<String?> openChoiceSheet(
  BuildContext context, {
  required String title,
  required List<({String id, String label})> options,
  required String current,
}) {
  return openSheet<String>(
    context,
    children: <Widget>[
      Builder(
        builder: (BuildContext context) {
          final Space sp = spaceOf(context);
          return CssColumn(<Block>[
            Block(SheetTitle(title), bottom: sp.s1),
            for (final ({String id, String label}) o in options)
              Block(
                _Choice(
                  label: o.label,
                  on: o.id == current,
                  onTap: () => Navigator.of(context).pop(o.id),
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

/// 選べる一行。選んでいるものには印を付ける。
class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.on, this.onTap});

  final String label;
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Typo t = Typo(c);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 44,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.body.copyWith(color: on ? c.ink : c.inkSoft)),
            ),
            if (on) Ic('check', size: 16, color: c.ink),
          ],
        ),
      ),
    );
  }
}

/// 検索（カット一覧から開く）
Future<void> openSearchSheet(
  BuildContext context, {
  required String initial,
  required void Function(String q, String author) onSearch,
  List<({String id, String label})> authors = const <({String id, String label})>[],
  String initialAuthor = '',
}) {
  final TextEditingController q = TextEditingController(text: initial);
  String author = initialAuthor;

  String nameOf(String id) =>
      authors.where((({String id, String label}) a) => a.id == id).map((({String id, String label}) a) => a.label).firstOrNull ?? '全員';

  return openSheet<void>(
    context,
    children: <Widget>[
      StatefulBuilder(
        builder: (BuildContext context, void Function(VoidCallback) redraw) {
          final Space sp = spaceOf(context);
          return CssColumn(<Block>[
            Block(const SheetTitle('検索'), bottom: sp.s1),
            Block(_LabeledRow(label: 'メモ', hint: 'メモのワードを入力してください', fontSize: 16, controller: q),
                top: sp.s2, bottom: sp.s2),
            // 撮った人で絞る。顔ぶれは、絞っていないときの一覧から拾ったもの。
            Block(
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text(upper('アップロードした人'), style: Typo.of(context).panelLabel),
                  SizedBox(width: sp.s2),
                  Expanded(
                    child: Picker(
                      value: nameOf(author),
                      width: 120,
                      onTap: authors.isEmpty
                          ? null
                          : () async {
                              final String? got = await openChoiceSheet(
                                context,
                                title: 'アップロードした人',
                                current: author,
                                options: <({String id, String label})>[
                                  (id: '', label: '全員'),
                                  ...authors,
                                ],
                              );
                              if (got != null) redraw(() => author = got);
                            },
                    ),
                  ),
                ],
              ),
              top: sp.s2,
              bottom: sp.s2,
            ),
            Block(SheetActions(children: <Widget>[
              TextBtn('絞り込みをリセット', onTap: () {
                onSearch('', '');
                Navigator.of(context).pop();
              }),
              PrimaryBtn('検索', onTap: () {
                onSearch(q.text.trim(), author);
                Navigator.of(context).pop();
              }),
            ]), top: sp.s5),
          ], outer: false);
        },
      ),
    ],
  );
}

/// カットの移動先を選ぶ。
/// ★ 移動すると、元のログで作った共有リンクからは外れる。取り返しがつくとはいえ
///   見えなくなる人が出るので、そのことを先に伝えてから選ばせる。
Future<void> openMoveSheet(
  BuildContext context, {
  required List<LogItem> logs,
  required String fromLogId,
  required Future<String?> Function(String logId) onMove,
  String title = 'カットの移動',
  String? note,
}) {
  return openSheet<void>(
    context,
    children: <Widget>[
      _Body(
        builder: (BuildContext context, _Report say) {
          final Palette c = colorsOf(context);
          final Space sp = spaceOf(context);
          return CssColumn(<Block>[
            Block(SheetTitle(title), bottom: sp.s1),
            Block(
              Text(note ?? '移動したカットは、移動元のログで作成した共有リンクから外れます。',
                  style: Typo(c).small),
              bottom: sp.s3,
            ),
            for (final LogItem l in logs)
              if (l.id != fromLogId)
                Block(
                  _MoveRow(log: l, onTap: () => say(context, () => onMove(l.id))),
                  top: 0,
                  bottom: 0,
                ),
          ], outer: false);
        },
      ),
    ],
  );
}

/// CSS: .move-row — 名前だけの1行。押すとそこへ移る。
class _MoveRow extends StatelessWidget {
  const _MoveRow({required this.log, required this.onTap});

  final LogItem log;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    return Semantics(
      button: true,
      label: log.name,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          // CSS: .move-row { padding: 8px 0; font-size: 14px }
          padding: const EdgeInsets.symmetric(vertical: 8),
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.centerLeft,
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(log.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Typo(c).body.copyWith(fontSize: 14)),
              ),
              Text('${log.cutCount}カット', style: Typo(c).small),
            ],
          ),
        ),
      ),
    );
  }
}

/// カットの詳細（どの画面からも、同じ札で開く）
/// ★ 詳しい値（大きさ・場所・ID など）は右上の調整から開く。ふだんは畳んでおく。
Future<void> openCutSheet(
  BuildContext context, {
  required Cut cut,
  required Media media,
  required Future<CutDetail> Function() load,
  required Future<String?> Function() onDelete,
  required Future<String?> Function(String body) onComment,
  required Future<String?> Function(String emoji) onReact,
  required Future<String?> Function(String note) onNote,
  required Future<String?> Function(String commentId) onDeleteComment,
  required void Function(String url) onDownload,
  VoidCallback? onMove,
}) {
  return openSheet<void>(
    context,
    wide: true,
    children: <Widget>[
      _CutBody(
        cut: cut,
        media: media,
        load: load,
        onDelete: onDelete,
        onComment: onComment,
        onReact: onReact,
        onNote: onNote,
        onDeleteComment: onDeleteComment,
        onDownload: onDownload,
        onMove: onMove,
      ),
    ],
  );
}

class _CutBody extends StatefulWidget {
  const _CutBody({
    required this.cut,
    required this.media,
    required this.load,
    required this.onDelete,
    required this.onComment,
    required this.onReact,
    required this.onNote,
    required this.onDeleteComment,
    required this.onDownload,
    this.onMove,
  });

  final Cut cut;
  final Media media;
  final Future<CutDetail> Function() load;
  final Future<String?> Function() onDelete;
  final Future<String?> Function(String body) onComment;
  final Future<String?> Function(String emoji) onReact;
  final Future<String?> Function(String note) onNote;
  final Future<String?> Function(String commentId) onDeleteComment;
  final void Function(String url) onDownload;
  final VoidCallback? onMove;

  @override
  State<_CutBody> createState() => _CutBodyState();
}

class _CutBodyState extends State<_CutBody> {
  final TextEditingController _comment = TextEditingController();
  late final TextEditingController _note = TextEditingController(text: widget.cut.note ?? '');
  CutDetail? _detail;
  bool _showMeta = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _comment.dispose();
    _note.dispose();
    _video?.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final CutDetail got = await widget.load();
      if (mounted) setState(() => _detail = got);
    } catch (_) {
      // 取れなくても、手元にあるぶんだけで出す
    }
  }

  Future<void> _run(Future<String?> Function() job, {String? done, bool close = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final String? bad = await job();
    if (!mounted) return;
    setState(() => _busy = false);
    if (bad != null) {
      toast(context, bad);
      return;
    }
    if (done != null) toast(context, done);
    if (close) {
      Navigator.of(context).pop();
    } else {
      await _refresh();
    }
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// 押されてから作る。押されるまでは作らない。
  VideoPlayerController? _video;
  bool _rolling = false;

  Future<void> _toggleVideo() async {
    final Cut cut = _detail?.cut ?? widget.cut;
    if (_video == null) {
      final VideoPlayerController next = VideoPlayerController.networkUrl(
        Uri.parse(media.url(cut.url)),
        httpHeaders: media.headers,
      );
      _video = next;
      await next.initialize();
      if (!mounted) {
        await next.dispose();
        return;
      }
      next.addListener(() {
        if (mounted) setState(() {});
      });
      await next.play();
      setState(() => _rolling = true);
      return;
    }
    if (_video!.value.isPlaying) {
      await _video!.pause();
    } else {
      await _video!.play();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Typo t = Typo(c);
    final Space sp = spaceOf(context);
    final Cut cut = _detail?.cut ?? widget.cut;
    final DateTime at = cut.localTime;
    final String title =
        '${at.year}.${_two(at.month)}.${_two(at.day)} ${_two(at.hour)}:${_two(at.minute)}';

    return Opacity(
      opacity: _busy ? .5 : 1,
      child: CssColumn(<Block>[
        // CSS: .detail-media — 寸法が分からないうちは 16:9 で置く
        Block(
          AspectRatio(
            aspectRatio: _detail != null && _detail!.width > 0 && _detail!.height > 0
                ? _detail!.width / _detail!.height
                : 16 / 9,
            child: Container(
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(color: c.paper2),
              // ★ 写真は敷いたまま。動画は押されてから流す。
              //   札を開いた瞬間に全部読みに行くと、一覧を見て回るだけで重くなる。
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (cut.thumbUrl != null && !_rolling)
                    Tn(media.url(cut.thumbUrl!),
                        headers: media.headers, fit: BoxFit.contain),
                  if (_video != null && _video!.value.isInitialized)
                    Center(
                      child: AspectRatio(
                        aspectRatio: _video!.value.aspectRatio,
                        child: VideoPlayer(_video!),
                      ),
                    ),
                  if (cut.kind != 'photo')
                    GestureDetector(
                      onTap: _toggleVideo,
                      behavior: HitTestBehavior.opaque,
                      child: Center(
                        child: _rolling && (_video?.value.isPlaying ?? false)
                            ? const SizedBox.shrink()
                            : Container(
                                width: 56,
                                height: 56,
                                alignment: Alignment.center,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0x8C000000),
                                ),
                                child: Ic('play',
                                    size: 22, color: const Color(0xFFFFFFFF)),
                              ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),

        // CSS: .detail-head — 撮った人・撮った時。右に詳しい値の開閉。
        Block(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SizedBox(height: sp.s4),
                    Text(upper(cut.author ?? ''), style: t.eyebrow),
                    SizedBox(height: sp.s1),
                    Text(title, style: t.panelHead.copyWith(fontWeight: FontWeight.w700)),
                    SizedBox(height: sp.s1),
                  ],
                ),
              ),
              SizedBox(width: sp.s2),
              IconBtn('settings',
                  label: '詳しい値を見る・直す',
                  onTap: () => setState(() => _showMeta = !_showMeta)),
            ],
          ),
        ),

        // CSS: .detail-actions { margin: var(--s3) 0 var(--s4) }
        Block(
          Wrap(
            spacing: sp.s3,
            runSpacing: sp.s1,
            children: <Widget>[
              TextBtn('ダウンロード', icon: 'download',
                  onTap: () => widget.onDownload('${media.url(cut.url)}?download=1')),
              TextBtn('移動', icon: 'move', onTap: widget.onMove),
              TextBtn('削除', icon: 'trash', danger: true, onTap: () async {
                final bool yes =
                    await confirm(context, 'このカットを削除しますか。ゴミ箱から戻せます。', '削除');
                if (!yes || !context.mounted) return;
                await _run(widget.onDelete, done: 'カットを削除しました', close: true);
              }),
            ],
          ),
          top: sp.s3,
          bottom: sp.s4,
        ),

        // 詳しい値。ふだんは畳んでおく。
        if (_showMeta) ...<Block>[
          Block(_meta(t, c, cut), top: sp.s2, bottom: sp.s2),
          Block(
            Row(children: <Widget>[
              Expanded(child: _NoteField(controller: _note)),
              SizedBox(width: sp.s3),
              TextBtn('保存', onTap: () => _run(() => widget.onNote(_note.text.trim()),
                  done: 'メモを保存しました')),
            ]),
            top: sp.s2,
            bottom: sp.s2,
          ),
        ],

        // CSS: .reactions { margin: var(--s3) 0 }
        Block(
          Wrap(
            spacing: sp.s2,
            children: <String>['👍', '🎉', '😂', '🥺', '🔥'].map((String e) {
              final int n = _detail?.reactions[e] ?? 0;
              final bool on = _detail?.mine.contains(e) ?? false;
              return GestureDetector(
                onTap: () => _run(() => widget.onReact(e)),
                behavior: HitTestBehavior.opaque,
                // ★ alignment は付けない。付けると幅いっぱいに広がって
                //   絵文字が縦に1つずつ並んでしまう（実機で踏んだ）。
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  color: on ? c.paper2 : null,
                  child: Center(
                    widthFactor: 1,
                    child: Opacity(
                      opacity: on ? 1 : .45,
                      child: Text(n > 0 ? '$e $n' : e, style: t.body),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          top: sp.s3,
          bottom: sp.s3,
        ),

        // コメント
        Block(const SheetHead('コメント'), top: sp.s5, bottom: sp.s2),
        if (_detail != null && _detail!.comments.isEmpty)
          Block(Text('まだコメントはありません。', style: t.small), top: 0, bottom: sp.s2),
        for (final Comment cm in _detail?.comments ?? <Comment>[])
          Block(
            // CSS: .comment — 顔と一緒に出す
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Avatar(
                  initial: cm.author.isEmpty ? '?' : cm.author.characters.first,
                  url: cm.avatarUrl == null ? null : media.url(cm.avatarUrl!),
                  headers: media.headers,
                ),
                SizedBox(width: sp.s2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(cm.author,
                          style: t.body.copyWith(fontSize: 12, color: c.inkSoft)),
                      Text(cm.body, style: t.body.copyWith(fontSize: 14)),
                    ],
                  ),
                ),
                MiniBtn('消す', onTap: () => _run(() => widget.onDeleteComment(cm.id))),
              ],
            ),
            top: sp.s1,
            bottom: sp.s1,
          ),
        Block(SheetRow(children: <Widget>[
          SheetField(
            hint: 'コメントを書く',
            width: 149,
            controller: _comment,
            onSubmit: () {
              final String text = _comment.text.trim();
              if (text.isEmpty) return;
              _comment.clear();
              _run(() => widget.onComment(text));
            },
          ),
          PrimaryBtn('送信', onTap: () {
            final String text = _comment.text.trim();
            if (text.isEmpty) return;
            _comment.clear();
            _run(() => widget.onComment(text));
          }),
        ]), top: sp.s2, bottom: sp.s2),
      ]),
    );
  }

  Media get media => widget.media;

  /// CSS: .kv — 左に薄い見出し、右に値。囲まない。
  Widget _meta(Typo t, Palette c, Cut cut) {
    final CutDetail? d = _detail;
    final DateTime at = cut.localTime;
    final int tz = -cut.tzOffset ~/ 60;
    final List<List<String>> rows = <List<String>>[
      <String>['撮影日時', '${at.year}/${at.month}/${at.day} ${_two(at.hour)}:${_two(at.minute)}'],
      <String>['日付', '${cut.localDate}（UTC${tz >= 0 ? '+' : ''}$tz）'],
      <String>['撮った人', cut.author ?? '—'],
      <String>['種類', cut.kind == 'photo' ? '写真' : '動画${d == null || d.mime.isEmpty ? '' : '（${d.mime}）'}'],
      <String>['タグ', (d?.tags ?? '').isEmpty ? '—' : d!.tags],
      <String>['長さ', cut.durationMs > 0 ? '${(cut.durationMs / 1000).toStringAsFixed(1)} 秒' : '—'],
      <String>['解像度', d == null || d.width == 0 ? '—' : '${d.width} × ${d.height}'],
      <String>['カメラ', d?.cameraName ?? '—'],
      <String>['撮影方法', d?.sourceName ?? '—'],
      <String>['サイズ', d == null || d.bytes == 0 ? '—' : d.size],
      <String>['チェックサム', (d?.checksum ?? '').isEmpty ? '—' : '${d!.checksum.substring(0, 16)}…'],
      <String>[
        '撮った場所',
        cut.lat == null || cut.lon == null
            ? '—'
            : '${cut.lat!.toStringAsFixed(5)}, ${cut.lon!.toStringAsFixed(5)}'
                '${d?.placeAccuracy == null ? '' : '（だいたい${d!.placeAccuracy!.round()}m）'}',
      ],
      <String>['ID', cut.id],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows
          .map((List<String> kv) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 120,
                      child: Text(upper(kv[0]),
                          style: t.small.copyWith(fontSize: 11, letterSpacing: 1.32)),
                    ),
                    Expanded(
                      child: Text(kv[1], style: t.body.copyWith(fontSize: 13)),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

/// メモを直す欄
class _NoteField extends StatelessWidget {
  const _NoteField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    return Container(
      height: 36.8,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.hair))),
      child: TextField(
        controller: controller,
        style: Typo(c).panelInput,
        cursorColor: c.ink,
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          hintText: 'メモ',
          hintStyle: Typo(c).panelInput.copyWith(color: c.mute),
        ),
      ),
    );
  }
}

/// うまくいったら閉じ、だめならその訳を出す——という繰り返しを1つにまとめたもの。
typedef _Report = void Function(
  BuildContext context,
  Future<String?> Function() run, {
  bool close,
});

class _Body extends StatefulWidget {
  const _Body({required this.builder});

  final Widget Function(BuildContext context, _Report say) builder;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  bool _busy = false;

  Future<void> _say(BuildContext context, Future<String?> Function() run, {bool close = true}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final String? bad = await run();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!context.mounted) return;
    if (bad != null) {
      toast(context, bad);
      return;
    }
    if (close) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: _busy ? .5 : 1,
      child: IgnorePointer(ignoring: _busy, child: widget.builder(context, _say)),
    );
  }
}

/// CSS: .panel-row label — 見出しと書く所を、同じ行に基線でそろえて並べる。
class _LabeledRow extends StatelessWidget {
  const _LabeledRow({
    required this.label,
    required this.hint,
    this.width,
    this.fontSize = 14,
    this.controller,
  });

  final String label;
  final String hint;
  final double? width;
  final double fontSize;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    final Space sp = spaceOf(context);
    // ★ CSS の .panel-row label は基線でそろえる。真ん中でそろえると、
    //   字の大きさが違うぶんだけ行の高さが変わってしまう。
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Text(upper(label), style: Typo.of(context).panelLabel),
        SizedBox(width: sp.s2),
        SheetField(hint: hint, width: width, fontSize: fontSize, controller: controller),
      ],
    );
  }
}


/// 共有リンクの一覧
/// ★ 停止しても行は消さない。停止したことが分かるようにしておく。
Future<void> openSharesSheet(
  BuildContext context, {
  required List<ShareLink> shares,
  required Future<String?> Function(String id) onRevoke,
  required void Function(String url) onCopy,
}) {
  return openSheet<void>(
    context,
    children: <Widget>[
      _Body(
        builder: (BuildContext context, _Report say) {
          final Palette c = colorsOf(context);
          final Typo t = Typo(c);
          final Space sp = spaceOf(context);
          return CssColumn(<Block>[
            Block(const SheetTitle('共有リンク'), bottom: sp.s1),
            if (shares.isEmpty)
              Block(Text('まだ共有リンクはありません。', style: t.small), top: sp.s2)
            else
              for (final ShareLink l in shares)
                Block(
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(l.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.body.copyWith(fontWeight: FontWeight.w600, fontSize: 14)),
                            Text(l.note, style: t.small),
                          ],
                        ),
                      ),
                      MiniBtn('コピー', icon: 'copy', onTap: () => onCopy(l.url)),
                      SizedBox(width: sp.s2),
                      MiniBtn('停止', onTap: () async {
                        final bool yes = await confirm(context,
                            'この共有リンクを停止しますか。リンクを知っている人も開けなくなります。', '停止');
                        if (!yes || !context.mounted) return;
                        say(context, () => onRevoke(l.id), close: false);
                      }),
                    ],
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


/// まとめ動画の見た目。
/// ★ 元の設定をまるごと預かって、変えたところだけ差し替えて返す。
///   ここに出していない細かい値（色や置き場所）を既定に戻さないため。
Future<Map<String, dynamic>?> openRenderSheet(
  BuildContext context, {
  required Map<String, dynamic> style,
}) {
  final Map<String, dynamic> draft = <String, dynamic>{...style};

  Map<String, dynamic> part(String key) =>
      <String, dynamic>{...((draft[key] as Map<String, dynamic>?) ?? <String, dynamic>{})};

  return openSheet<Map<String, dynamic>>(
    context,
    children: <Widget>[
      StatefulBuilder(
        builder: (BuildContext context, void Function(VoidCallback) redraw) {
          final Space sp = spaceOf(context);

          Widget pick(String label, String value, List<({String id, String label})> options,
              void Function(String) apply) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(upper(label), style: Typo.of(context).panelLabel),
                SizedBox(width: sp.s2),
                Expanded(
                  child: Picker(
                    value: options
                            .where((({String id, String label}) o) => o.id == value)
                            .map((({String id, String label}) o) => o.label)
                            .firstOrNull ??
                        value,
                    width: 140,
                    onTap: () async {
                      final String? got = await openChoiceSheet(context,
                          title: label, current: value, options: options);
                      if (got != null) redraw(() => apply(got));
                    },
                  ),
                ),
              ],
            );
          }

          Widget flag(String label, String key) {
            final Map<String, dynamic> m = part(key);
            return _Choice(
              label: label,
              on: m['show'] == true,
              onTap: () => redraw(() {
                draft[key] = <String, dynamic>{...m, 'show': m['show'] != true};
              }),
            );
          }

          final int per = (draft['perCutMs'] as num?)?.toInt() ?? 0;

          return CssColumn(<Block>[
            Block(const SheetTitle('まとめ動画の見た目'), bottom: sp.s1),
            Block(
              pick('大きさ', (draft['size'] as String?) ?? 'landscape',
                  const <({String id, String label})>[
                    (id: 'landscape', label: '横 1280×720'),
                    (id: 'portrait', label: '縦 720×1280'),
                    (id: 'square', label: '正方形 1080×1080'),
                  ], (String v) => draft['size'] = v),
              top: sp.s2, bottom: sp.s2),
            Block(
              pick('収め方', (draft['fit'] as String?) ?? 'contain',
                  const <({String id, String label})>[
                    (id: 'contain', label: '全部入れる（余白あり）'),
                    (id: 'cover', label: '画面いっぱい（切り抜き）'),
                  ], (String v) => draft['fit'] = v),
              top: sp.s2, bottom: sp.s2),
            Block(
              pick('1カットの長さ', '$per',
                  const <({String id, String label})>[
                    (id: '0', label: '元の長さのまま'),
                    (id: '2000', label: '2秒'),
                    (id: '3000', label: '3秒'),
                    (id: '5000', label: '5秒'),
                  ], (String v) => draft['perCutMs'] = int.parse(v)),
              top: sp.s2, bottom: sp.s2),
            Block(
              pick('並び', (draft['order'] as String?) ?? 'time',
                  const <({String id, String label})>[
                    (id: 'time', label: '撮った順'),
                    (id: 'reverse', label: '新しい順'),
                  ], (String v) => draft['order'] = v),
              top: sp.s2, bottom: sp.s2),
            Block(Text(upper('焼き込む'), style: Typo.of(context).panelLabel),
                top: sp.s3, bottom: sp.s1),
            Block(flag('時刻', 'time'), top: sp.s1, bottom: sp.s1),
            Block(flag('メモ', 'note'), top: sp.s1, bottom: sp.s1),
            Block(flag('ログ名', 'logName'), top: sp.s1, bottom: sp.s1),
            Block(SheetActions(children: <Widget>[
              TextBtn('やめる', onTap: () => Navigator.of(context).pop()),
              PrimaryBtn('この見た目で作る', onTap: () => Navigator.of(context).pop(draft)),
            ]), top: sp.s5),
          ], outer: false);
        },
      ),
    ],
  );
}
