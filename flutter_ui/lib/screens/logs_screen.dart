// ログ一覧（いちばん上の画面）。
// web の #logsScreen をそのまま写す。行のあいだにヘアラインを引き、
// 左に見本の絵、右に > を置く——という並びをそのまま持ってくる。
import 'package:flutter/widgets.dart';

import '../data/models.dart';
import '../design/icons.dart';
import '../design/text.dart';
import '../design/tokens.dart';
import '../ui/shell.dart';

class LogsScreen extends StatelessWidget {
  const LogsScreen({super.key, required this.logs, required this.mediaUrl, this.onOpen});

  final List<LogItem> logs;
  final String Function(String path) mediaUrl;
  final ValueChanged<LogItem>? onOpen;

  @override
  Widget build(BuildContext context) {
    final Space sp = spaceOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TopBar(children: <Widget>[
          const Spacer(),
          const IconBtn('search'),
          const IconBtn('plus'),
        ]),
        Expanded(
          child: ScreenBody(
            top: false,
            child: Container(
              // CSS: .logs-list { border-top: 1px solid hair; margin: 0 0 s3 }
              margin: EdgeInsets.only(bottom: sp.s3),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colorsOf(context).hair)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: logs
                    .map((LogItem l) => _LogRow(log: l, mediaUrl: mediaUrl, onTap: () => onOpen?.call(l)))
                    .toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// CSS: .log-row — 48px / 1fr / 16px の3列。行の高さは中身で決まる（下限 68px）。
class _LogRow extends StatelessWidget {
  const _LogRow({required this.log, required this.mediaUrl, this.onTap});

  final LogItem log;
  final String Function(String path) mediaUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final Typo t = Typo(c);
    final Space sp = spaceOf(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minHeight: 68),
        padding: EdgeInsets.symmetric(vertical: sp.s2, horizontal: 2),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.hair)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            _Thumb(log: log, mediaUrl: mediaUrl),
            SizedBox(width: sp.s2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(log.name, style: t.logName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(log.subtitle, style: t.logSub, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            SizedBox(width: sp.s2),
            // CSS: .log-chev は 16px の枠に、13px の印を左詰めで置く
            SizedBox(
              width: 16,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Ic('next', size: 13, color: c.mute),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// CSS: .log-thumb — 48px の四角。絵が無いときは、下地の上に印だけを置く。
class _Thumb extends StatelessWidget {
  const _Thumb({required this.log, required this.mediaUrl});

  final LogItem log;
  final String Function(String path) mediaUrl;

  @override
  Widget build(BuildContext context) {
    final Palette c = colorsOf(context);
    final String? url = log.latestThumbUrl;

    return Container(
      width: 48,
      height: 48,
      // ★ color と clipBehavior は同時に使えない（Container の決まり）。
      //   切り抜きたいので、下地は decoration の側に置く。
      decoration: BoxDecoration(color: c.paper2),
      clipBehavior: Clip.hardEdge,
      alignment: Alignment.center,
      child: url == null
          ? Ic(log.isPrivate ? 'lock' : 'film', size: 18, color: c.mute)
          : Image.network(mediaUrl(url), width: 48, height: 48, fit: BoxFit.cover),
    );
  }
}
