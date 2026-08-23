// カット一覧。web の #allScreen をそのまま写す。
// 写真のアプリのように、日付ごとに詰めて並べる。
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

import '../data/models.dart';
import '../design/text.dart';
import '../design/tokens.dart';
import '../ui/shell.dart';

class AllScreen extends StatelessWidget {
  const AllScreen({
    super.key,
    required this.cuts,
    required this.mediaUrl,
    this.onOpen,
    this.onSearch,
  });

  final List<Cut> cuts;
  final String Function(String path) mediaUrl;
  final ValueChanged<Cut>? onOpen;
  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context) {
    final double safeBottom = MediaQuery.paddingOf(context).bottom;

    // 日付ごとにまとめる。新しい日が上。
    final Map<String, List<Cut>> byDay = <String, List<Cut>>{};
    for (final Cut c in cuts) {
      byDay.putIfAbsent(c.localDate, () => <Cut>[]).add(c);
    }
    final List<String> days = byDay.keys.toList()..sort((String a, String b) => b.compareTo(a));

    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < days.length; i++) {
      rows.add(_DayHead(date: days[i], count: byDay[days[i]]!.length, first: i == 0));
      rows.add(_PhotoGrid(cuts: byDay[days[i]]!, mediaUrl: mediaUrl, onOpen: onOpen));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TopBar(children: <Widget>[
          const Spacer(),
          IconBtn('search', onTap: onSearch),
          const IconBtn('plus'),
        ]),
        Expanded(
          child: SingleChildScrollView(
            // CSS: .list-body { padding-bottom: calc(64px + safe) }
            padding: EdgeInsets.only(bottom: 64 + safeBottom),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
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
  const _PhotoGrid({required this.cuts, required this.mediaUrl, this.onOpen});

  final List<Cut> cuts;
  final String Function(String path) mediaUrl;
  final ValueChanged<Cut>? onOpen;

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
                  _PhotoCell(cut: line[j], side: side, mediaUrl: mediaUrl, onOpen: onOpen),
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
  const _PhotoCell({required this.cut, required this.side, required this.mediaUrl, this.onOpen});

  final Cut cut;
  final double side;
  final String Function(String path) mediaUrl;
  final ValueChanged<Cut>? onOpen;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Typo t = Typo(c);

    return Semantics(
      button: true,
      label: '${cut.localDate} ${cut.hhmm} ${cut.logName ?? ''}',
      child: GestureDetector(
      onTap: onOpen == null ? null : () => onOpen!(cut),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
      width: side,
      height: side,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ColoredBox(color: c.paper2),
          if (cut.thumbUrl != null) CachedNetworkImage(imageUrl: mediaUrl(cut.thumbUrl!), fit: BoxFit.cover),
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
        ],
      ),
      ),
      ),
    );
  }
}
