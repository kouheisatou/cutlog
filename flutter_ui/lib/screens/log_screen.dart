// ログの画面（カレンダー）。web の #app をそのまま写す。
// ★ 枠を引かず、余白と点で示す。撮った日には点が並び、多い日ほど点が増える（最大6つ）。
import 'package:flutter/widgets.dart';

import '../data/models.dart';
import '../design/text.dart';
import '../design/tokens.dart';
import '../ui/shell.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key, required this.log, required this.cuts, this.onBack, this.onDay});

  final LogItem log;
  final List<Cut> cuts;
  final VoidCallback? onBack;
  final ValueChanged<String>? onDay;

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // いちばん新しい月が見えている所から始める。出したあとでないと動かせない。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Map<String, int> get _counts {
    final Map<String, int> out = <String, int>{};
    for (final Cut c in widget.cuts) {
      out[c.localDate] = (out[c.localDate] ?? 0) + 1;
    }
    return out;
  }

  /// 出す範囲は「いちばん古いカットの月」から「今月（それより後のカットがあればその月）」まで。
  /// ★ 記録が少ないうちでも流して見られるよう、少なくとも1年ぶんは並べる。
  ///   ここを縮めると、上下に流す手ざわりそのものが変わってしまう。
  List<DateTime> get _months {
    final DateTime today = DateTime.now();
    final DateTime floor = DateTime(today.year, today.month - 11);
    final List<String> dates = widget.cuts.map((Cut c) => c.localDate).toList()..sort();

    DateTime at = floor;
    if (dates.isNotEmpty) {
      final DateTime oldest = DateTime.parse('${dates.first.substring(0, 7)}-01');
      if (oldest.isBefore(floor)) at = oldest;
    }
    DateTime to = DateTime(today.year, today.month);
    if (dates.isNotEmpty) {
      final DateTime newest = DateTime.parse('${dates.last.substring(0, 7)}-01');
      if (newest.isAfter(to)) to = newest;
    }

    final List<DateTime> out = <DateTime>[];
    while (!at.isAfter(to) && out.length < 600) {
      out.add(at);
      at = DateTime(at.year, at.month + 1);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final Space sp = spaceOf(context);
    final Map<String, int> counts = _counts;
    final double safeBottom = MediaQuery.paddingOf(context).bottom;
    final List<DateTime> months = _months;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TopBar(children: <Widget>[
          IconBtn('back', onTap: widget.onBack),
          Crumbs(items: <String>['ログ', widget.log.name]),
          const IconBtn('settings'),
        ]),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                // CSS: .screen-body.wide { max-width: 860px }
                constraints: const BoxConstraints(maxWidth: 860),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(sp.s4, sp.s2, sp.s4, 64 + safeBottom),
                  child: Padding(
                    // CSS: .cal { padding: var(--s2) var(--s4) var(--s5) }
                    padding: EdgeInsets.fromLTRB(sp.s4, sp.s2, sp.s4, sp.s5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        for (int i = 0; i < months.length; i++) ...<Widget>[
                          // CSS: .cal-scroll { gap: var(--s5) }
                          if (i > 0) SizedBox(height: sp.s5),
                          _Month(month: months[i], counts: counts, onDay: widget.onDay),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Month extends StatelessWidget {
  const _Month({required this.month, required this.counts, this.onDay});

  final DateTime month;
  final Map<String, int> counts;
  final ValueChanged<String>? onDay;

  static const List<String> _dow = <String>['日', '月', '火', '水', '木', '金', '土'];
  static const double _gap = 4;      // ≤480px では 4px
  static const double _row = 44;     // grid-auto-rows

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Typo t = Typo(c);
    final Space sp = spaceOf(context);

    final String ym = '${month.year}-${month.month.toString().padLeft(2, '0')}';
    final int inMonth = counts.entries
        .where((MapEntry<String, int> e) => e.key.startsWith(ym))
        .fold(0, (int n, MapEntry<String, int> e) => n + e.value);

    final int days = DateTime(month.year, month.month + 1, 0).day;
    final int lead = DateTime(month.year, month.month, 1).weekday % 7;   // 日曜を 0 に

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          // CSS: .cal-month-head { margin: 0 0 var(--s2) }
          padding: EdgeInsets.only(bottom: sp.s2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text('${month.year}.${month.month.toString().padLeft(2, '0')}', style: t.calMonth),
              SizedBox(width: sp.s2),
              if (inMonth > 0) Text('$inMonthカット', style: t.small.copyWith(letterSpacing: 1.8)),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            final double cell = (box.maxWidth - _gap * 6) / 7;
            final List<Widget> cells = <Widget>[
              for (final String d in _dow)
                SizedBox(width: cell, height: _row, child: Center(child: Text(d, style: t.calDow))),
              for (int i = 0; i < lead; i++) SizedBox(width: cell, height: _row),
              for (int d = 1; d <= days; d++)
                _Day(
                  width: cell,
                  day: d,
                  date: '$ym-${d.toString().padLeft(2, '0')}',
                  count: counts['$ym-${d.toString().padLeft(2, '0')}'] ?? 0,
                  onTap: onDay,
                ),
            ];

            final List<Widget> rows = <Widget>[];
            for (int i = 0; i < cells.length; i += 7) {
              if (i > 0) rows.add(const SizedBox(height: _gap));
              rows.add(Row(
                children: <Widget>[
                  for (int j = i; j < i + 7 && j < cells.length; j++) ...<Widget>[
                    if (j > i) const SizedBox(width: _gap),
                    cells[j],
                  ],
                ],
              ));
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
          },
        ),
      ],
    );
  }
}

/// CSS: .cal-day — 数字の下に、撮った本数ぶんの点を並べる（多くても6つ）。
class _Day extends StatelessWidget {
  const _Day({required this.width, required this.day, required this.date, required this.count, this.onTap});

  final double width;
  final int day;
  final String date;
  final int count;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final bool has = count > 0;
    final DateTime now = DateTime.now();
    final bool today = date ==
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    return GestureDetector(
      onTap: has && onTap != null ? () => onTap!(date) : null,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: width,
        height: 44,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              day.toString().padLeft(2, '0'),
              style: Typo(c).calDay.copyWith(
                    color: has ? c.ink : c.mute,
                    decoration: today ? TextDecoration.underline : null,
                    decorationColor: has ? c.ink : c.mute,
                  ),
            ),
            const SizedBox(height: 5),
            SizedBox(
              height: 4,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (int i = 0; i < (count > 6 ? 6 : count); i++) ...<Widget>[
                    if (i > 0) const SizedBox(width: 3),
                    SizedBox(width: 4, height: 4, child: ColoredBox(color: c.ink)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
