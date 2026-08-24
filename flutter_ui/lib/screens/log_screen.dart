// ログの画面（カレンダー）。web の #app をそのまま写す。
// ★ 枠を引かず、余白と点で示す。撮った日には点が並び、多い日ほど点が増える（最大6つ）。
import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../design/icons.dart';
import '../design/text.dart';
import '../design/tokens.dart';
import '../ui/flow.dart';
import '../ui/sheet.dart';
import '../ui/shell.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({
    super.key,
    required this.log,
    required this.cuts,
    this.onBack,
    this.onDay,
    this.onSettings,
    this.members = const <String>[],
    this.query = '',
    this.author = '',
    this.onFilter,
  });

  final LogItem log;
  final List<Cut> cuts;
  final VoidCallback? onBack;
  final ValueChanged<String>? onDay;
  final VoidCallback? onSettings;

  /// 投稿者の候補（表示名）。先頭に「全員」を足して出す。
  final List<String> members;

  final String query;
  final String author;

  /// メモの語と投稿者で絞り込む
  final void Function(String q, String author)? onFilter;

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final ScrollController _scroll = ScrollController();
  late final TextEditingController _q = TextEditingController(text: widget.query);
  Timer? _typing;

  /// 打ち終わるのを少し待ってから絞る。1文字ごとに取りに行かない。
  void _onTyped(String v) {
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 350), () {
      widget.onFilter?.call(v.trim(), widget.author);
    });
  }

  Future<void> _pickAuthor() async {
    if (widget.onFilter == null) return;
    await openSheet<void>(
      context,
      children: <Widget>[
        Builder(
          builder: (BuildContext context) {
            final Space sp = spaceOf(context);
            return CssColumn(<Block>[
              Block(const SheetTitle('アップロードした人'), bottom: sp.s1),
              for (final String name in <String>['全員', ...widget.members])
                Block(
                  _Choice(
                    label: name,
                    on: name == '全員' ? widget.author.isEmpty : name == widget.author,
                    onTap: () {
                      widget.onFilter!(_q.text.trim(), name == '全員' ? '' : name);
                      Navigator.of(context).pop();
                    },
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
    _typing?.cancel();
    _q.dispose();
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
          IconBtn('back', label: 'ログ一覧へ戻る', onTap: widget.onBack),
          Crumbs(items: <String>['ログ', widget.log.name]),
          // CSS: .crumb-meta — 非公開か、何人いるか
          Text(
            widget.log.isPrivate ? '非公開' : '${widget.log.memberCount}人',
            style: Typo.of(context).small,
          ),
          IconBtn('settings', label: 'このログの設定', onTap: widget.onSettings),
        ]),

        // CSS: .list-toolbar — メモの語と投稿者で絞る
        Padding(
          padding: EdgeInsets.fromLTRB(sp.s4, sp.s1, sp.s4, sp.s2),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: TextField(
                    controller: _q,
                    style: Typo.of(context).body.copyWith(fontSize: 13),
                    cursorColor: colorsOf(context).ink,
                    textInputAction: TextInputAction.search,
                    onChanged: _onTyped,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'メモを検索',
                      hintStyle: Typo.of(context).body
                          .copyWith(fontSize: 13, color: colorsOf(context).mute),
                    ),
                  ),
                ),
              ),
              SizedBox(width: sp.s3),
              GestureDetector(
                onTap: _pickAuthor,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(widget.author.isEmpty ? '全員' : widget.author,
                        style: Typo.of(context).body
                            .copyWith(fontSize: 13, color: colorsOf(context).mute)),
                    const SizedBox(width: 4),
                    Ic('next', size: 11, color: colorsOf(context).mute),
                  ],
                ),
              ),
            ],
          ),
        ),
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

    return Semantics(
      button: has,
      label: '${date.substring(5).replaceAll('-', '月')}日、$count カット',
      child: GestureDetector(
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
      ),
    );
  }
}


/// 選ぶときの1行。選んでいるものだけ反転する。
class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Space sp = spaceOf(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.symmetric(horizontal: on ? sp.s2 : 0),
        color: on ? c.sel : null,
        child: Text(label,
            style: Typo(c).body.copyWith(fontSize: 14, color: on ? c.selInk : c.ink)),
      ),
    );
  }
}
