// 画面の器（Scaffold）が、端末いっぱいに広がるかを確かめる。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cutlog/design/tokens.dart';
import 'package:cutlog/ui/shell.dart';

void main() {
  testWidgets('画面は 390x844 いっぱいに広がり、帯は下に着く', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Skin(
        palette: Palette.lightMode,
        space: Space.forWidth(390),
        child: const Screen(
          tab: 'logs',
          child: Column(children: <Widget>[Text('うえ'), Spacer(), Text('した')]),
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(Screen)), const Size(390, 844));
    // 下の帯は、いちばん下に居る
    expect(tester.getBottomLeft(find.byType(TabBarNav)).dy, closeTo(844, 0.5));
  });

  testWidgets('本番と同じ包み方でも広がる', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Skin(
        palette: Palette.lightMode,
        space: Space.forWidth(390),
        child: Builder(
          builder: (BuildContext context) => Material(
            type: MaterialType.transparency,
            child: DefaultTextStyle(
              style: const TextStyle(fontSize: 15),
              child: ColoredBox(
                color: colorsOf(context).paper,
                child: const Screen(
                  tab: 'logs',
                  child: Column(children: <Widget>[Text('うえ'), Spacer(), Text('した')]),
                ),
              ),
            ),
          ),
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(Screen)), const Size(390, 844));
  });
}
