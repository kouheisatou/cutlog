// カット一覧。web の #allScreen をそのまま写す。
// 写真のアプリのように、日付ごとに詰めて並べる。
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart';

import '../data/media.dart';
import '../data/models.dart';
import '../design/icons.dart';
import '../design/text.dart';
import '../design/tokens.dart';
import '../ui/controls.dart';
import '../ui/shell.dart';

class AllScreen extends StatefulWidget {
  const AllScreen({
    super.key,
    required this.cuts,
    required this.media,
    this.onOpen,
    this.onSearch,
    this.onAdd,
    this.filter = '',
    this.onExport,
    this.onMove,
    this.onDelete,
    this.title,
    this.onBack,
  });

  final List<Cut> cuts;
  final Media media;
  final ValueChanged<Cut>? onOpen;
  final VoidCallback? onSearch;
  final VoidCallback? onAdd;

  /// いま何で絞っているか。帯の文言に使う。
  final String filter;

  /// 選んだぶんをまとめて扱う
  final Future<void> Function(List<Cut> picked)? onExport;
  final Future<void> Function(List<Cut> picked)? onMove;
  final Future<void> Function(List<Cut> picked)? onDelete;

  /// 見出し（地図から来たときなど）。無ければ ふつうのカット一覧。
  final String? title;
  final VoidCallback? onBack;

  @override
  State<AllScreen> createState() => _AllScreenState();
}

class _AllScreenState extends State<AllScreen> {
  /// 長押しと見なすまでの時間。web と同じ 450ms。
  static const Duration _longPress = Duration(milliseconds: 450);

  /// 選んでいる最中か。0件になったら自動で抜ける。
  bool _picking = false;
  final Set<String> _picked = <String>{};

  List<Cut> get _pickedCuts =>
      widget.cuts.where((Cut c) => _picked.contains(c.id)).toList();

  void _startPicking(Cut c) {
    HapticFeedback.selectionClick();
    setState(() {
      _picking = true;
      _picked.add(c.id);
    });
  }

  void _tap(Cut c) {
    if (!_picking) {
      widget.onOpen?.call(c);
      return;
    }
    setState(() {
      if (_picked.contains(c.id)) {
        _picked.remove(c.id);
      } else {
        _picked.add(c.id);
      }
      // ★ 最後の1件を外したら選ぶのをやめる。バーだけ残ると出口が分からなくなる。
      if (_picked.isEmpty) _picking = false;
    });
  }

  void _endPicking() {
    setState(() {
      _picking = false;
      _picked.clear();
    });
  }

  Future<void> _run(Future<void> Function(List<Cut> picked)? job) async {
    if (job == null) return;
    final List<Cut> picked = _pickedCuts;
    if (picked.isEmpty) return;
    await job(picked);
    if (mounted) _endPicking();
  }

  @override
  Widget build(BuildContext context) {
    final double safeBottom = MediaQuery.paddingOf(context).bottom;

    // 日付ごとにまとめる。新しい日が上。
    final Map<String, List<Cut>> byDay = <String, List<Cut>>{};
    for (final Cut c in widget.cuts) {
      byDay.putIfAbsent(c.localDate, () => <Cut>[]).add(c);
    }
    final List<String> days = byDay.keys.toList()..sort((String a, String b) => b.compareTo(a));

    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < days.length; i++) {
      rows.add(_DayHead(date: days[i], count: byDay[days[i]]!.length, first: i == 0));
      rows.add(_PhotoGrid(
        cuts: byDay[days[i]]!,
        media: widget.media,
        picking: _picking,
        picked: _picked,
        onTap: _tap,
        onLongPress: _startPicking,
        longPress: _longPress,
      ));
    }

    final Palette c = colorsOf(context);
    final Space sp = spaceOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TopBar(children: <Widget>[
          if (widget.onBack != null) IconBtn('back', label: '戻る', onTap: widget.onBack),
          if (widget.title != null)
            Text(widget.title!, style: Typo(c).crumbCurrent)
          else
            const SizedBox.shrink(),
          const Spacer(),
          if (widget.title == null) ...<Widget>[
            IconBtn('search', label: '検索', onTap: widget.onSearch),
            IconBtn('plus', label: '取り込む', onTap: widget.onAdd),
          ],
        ]),

        // CSS: .filter-bar — いま何で絞っているか
        if (widget.filter.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(sp.s4, sp.s1, sp.s4, sp.s2),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text('メモ「${widget.filter}」　で絞りこみ中',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Typo(c).mini.copyWith(decoration: TextDecoration.none)),
                ),
                SizedBox(width: sp.s2),
                MiniBtn('解除', onTap: widget.onSearch),
              ],
            ),
          ),

        Expanded(
          child: widget.cuts.isEmpty
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(sp.s4),
                    child: Text(
                      widget.filter.isEmpty
                          ? 'まだカットがありません。カメラのタブから撮ってみてください。'
                          : '条件に合うカットはありません。',
                      textAlign: TextAlign.center,
                      style: Typo(c).empty,
                    ),
                  ),
                )
              : SingleChildScrollView(
                  // CSS: .list-body { padding-bottom: calc(64px + safe) }
                  padding: EdgeInsets.only(bottom: (_picking ? 128 : 64) + safeBottom),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
                ),
        ),

        // CSS: .action-bar — 選んでいるときだけ出る操作の帯
        if (_picking)
          Container(
            // ★ 下の帯は画面に貼り付いているので、そのぶんを空ける。
            //   空けないと操作の帯がタブの下へ潜って押せなくなる。
            padding: EdgeInsets.fromLTRB(sp.s4, sp.s2, sp.s4, sp.s2 + 57 + safeBottom),
            decoration: BoxDecoration(
              color: c.paper,
              border: Border(top: BorderSide(color: c.hair)),
            ),
            child: Wrap(
              spacing: sp.s2,
              runSpacing: sp.s1,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text('${_picked.length}件', style: Typo(c).mini.copyWith(decoration: TextDecoration.none)),
                MiniBtn('すべて選択', onTap: () => setState(() {
                      _picked.addAll(widget.cuts.map((Cut x) => x.id));
                    })),
                MiniBtn('書き出し', icon: 'download', onTap: () => _run(widget.onExport)),
                MiniBtn('移動', icon: 'move', onTap: () => _run(widget.onMove)),
                MiniBtn('削除', icon: 'trash', danger: true, onTap: () => _run(widget.onDelete)),
                MiniBtn('やめる', onTap: _endPicking),
              ],
            ),
          ),
      ],
    );
  }
}

/// CSS: .day-head — 線を引かず、余白で切る。日付だけ濃く、件数は薄く。
class _DayHead extends StatelessWidget {
  const _DayHead({required this.date, required this.count, required this.first});

  final String date;
  final int count;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Space sp = spaceOf(context);

    // CSS: padding は s5 s4 s2。ただし先頭だけ上を s2 に詰める。
    return Padding(
      padding: EdgeInsets.fromLTRB(sp.s4, first ? sp.s2 : sp.s5, sp.s4, sp.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Text(
            date.replaceAll('-', '.'),
            style: _headStyle(c).copyWith(color: c.ink, letterSpacing: 2),
          ),
          SizedBox(width: sp.s2),
          Text(
            upper('${count.toString().padLeft(2, '0')} cuts'),
            style: _headStyle(c),
          ),
        ],
      ),
    );
  }

  TextStyle _headStyle(Palette c) => TextStyle(
        color: c.mute,
        fontFamily: monoFamily,
        fontFamilyFallback: monoFallback,
        fontSize: 10,
        height: lineHeight,
        leadingDistribution: TextLeadingDistribution.even,
        letterSpacing: 10 * track,
      );
}

/// CSS: .photo-grid — repeat(auto-fill, minmax(88px, 1fr))、すきまは 2px。
class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({
    required this.cuts,
    required this.media,
    required this.picking,
    required this.picked,
    required this.onTap,
    required this.onLongPress,
    required this.longPress,
  });

  final List<Cut> cuts;
  final Media media;
  final bool picking;
  final Set<String> picked;
  final ValueChanged<Cut> onTap;
  final ValueChanged<Cut> onLongPress;
  final Duration longPress;

  static const double _gap = 2;
  static const double _min = 88;

  @override
  Widget build(BuildContext context) {
    final Space sp = spaceOf(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(sp.s4, 0, sp.s4, sp.s3),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          // auto-fill は「入るだけ詰める」。入る本数を出してから、余りを均す。
          final int cols = ((box.maxWidth + _gap) / (_min + _gap)).floor().clamp(1, 99);
          final double side = (box.maxWidth - _gap * (cols - 1)) / cols;

          final List<Widget> lines = <Widget>[];
          for (int i = 0; i < cuts.length; i += cols) {
            final List<Cut> line = cuts.sublist(i, (i + cols).clamp(0, cuts.length));
            lines.add(Row(
              children: <Widget>[
                for (int j = 0; j < line.length; j++) ...<Widget>[
                  if (j > 0) const SizedBox(width: _gap),
                  _PhotoCell(
                    cut: line[j],
                    side: side,
                    media: media,
                    picking: picking,
                    picked: picked.contains(line[j].id),
                    onTap: onTap,
                    onLongPress: onLongPress,
                    longPress: longPress,
                  ),
                ],
              ],
            ));
            if (i + cols < cuts.length) lines.add(const SizedBox(height: _gap));
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines);
        },
      ),
    );
  }
}

/// CSS: .photo-cell — 正方形。下に時刻とログ名を、暗がりの上に置く。
class _PhotoCell extends StatelessWidget {
  const _PhotoCell({
    required this.cut,
    required this.side,
    required this.media,
    required this.picking,
    required this.picked,
    required this.onTap,
    required this.onLongPress,
    required this.longPress,
  });

  final Cut cut;
  final double side;
  final Media media;
  final bool picking;
  final bool picked;
  final ValueChanged<Cut> onTap;
  final ValueChanged<Cut> onLongPress;
  final Duration longPress;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Typo t = Typo(c);

    return Semantics(
      button: true,
      selected: picked,
      label: picking
          ? '${cut.hhmm} を選ぶ'
          : '${cut.localDate} ${cut.hhmm} ${cut.logName ?? ''}',
      child: GestureDetector(
      onTap: () => onTap(cut),
      // ★ 長押しでまとめて選ぶ。web と同じ 450ms。
      onLongPress: () => onLongPress(cut),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
      width: side,
      height: side,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ColoredBox(color: c.paper2),
          if (cut.thumbUrl != null) CachedNetworkImage(imageUrl: media.url(cut.thumbUrl!), httpHeaders: media.headers, fit: BoxFit.cover),
          // CSS: .photo-cell .cap — 下から立ち上がる暗がりの上に、時刻とログ名を置く
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 12, 6, 4),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: <Color>[Color(0x8C000000), Color(0x00000000)],
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text(cut.hhmm, style: t.photoCap),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Opacity(
                      opacity: .75,
                      child: Text(cut.logName ?? '', style: t.photoCap,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // CSS: .photo-cell .tick — 選んでいるときだけ出る丸い印
          if (picking)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: picked ? c.sel : const Color(0x4D000000),
                  border: Border.all(
                    color: picked ? c.paper : const Color(0xD9FFFFFF),
                    width: 2,
                  ),
                ),
                child: picked
                    ? Center(child: Ic('check', size: 11, color: c.selInk, strokeWidth: 2.4))
                    : null,
              ),
            ),

          // 選ばれている升は、周りを囲って薄くする（cutlog は色を足さない）
          if (picked)
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0x33FFFFFF),
                  border: Border.all(color: c.sel, width: 3),
                ),
              ),
            ),
        ],
      ),
      ),
      ),
    );
  }
}
