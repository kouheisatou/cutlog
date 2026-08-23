// 画面が組み上がるかを、実際の端末の大きさで確かめる。
// ★ web のリリースは例外の中身が潰れて読めない。ここで同じ木を組んで、素の言い分を見る。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cutlog/data/models.dart';
import 'package:cutlog/design/tokens.dart';
import 'package:cutlog/screens/logs_screen.dart';
import 'package:cutlog/ui/shell.dart';

LogItem _log(String name, {int cuts = 4, String? thumb}) => LogItem(
      id: 'l_$name', name: name, kind: name == 'プライベート' ? 'private' : 'shared',
      cutCount: cuts, memberCount: 1, ownerName: '見比べ',
      latestThumbUrl: thumb, latestTakenAt: '2026-08-23T00:00:00.000Z',
      cutSeconds: 2, inviteCode: 'abc',
    );

Widget _host(Widget child) => MediaQuery(
      data: const MediaQueryData(size: Size(390, 844)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Skin(
          palette: Palette.lightMode,
          space: Space.forWidth(390),
          child: child,
        ),
      ),
    );

void main() {
  testWidgets('ログ一覧が 390x844 で組み上がる', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(Screen(
      tab: 'logs',
      child: LogsScreen(
        logs: <LogItem>[_log('プライベート', cuts: 0), _log('仕事のメモ', cuts: 3), _log('まいにち')],
        mediaUrl: (String p) => p,
      ),
    )));

    expect(tester.takeException(), isNull);

    // 本物の DOM で測った値と突き合わせる（tool/parity で吸い出した数字）。
    // 行の間隔は 81px（上下の余白 16 ＋ 見本 48 ＋ 線 1）。
    final double a = tester.getTopLeft(find.text('仕事のメモ')).dy;
    final double b = tester.getTopLeft(find.text('まいにち')).dy;
    expect(b - a, closeTo(81, 0.5));
    // 名前の左端は 82px（16 余白 ＋ 2 ＋ 見本 48 ＋ すきま 16）
    expect(tester.getTopLeft(find.text('まいにち')).dx, closeTo(82, 0.5));
  });
}
