// 札が開いて、中身が実際に組み上がるかを確かめる。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cutlog/design/tokens.dart';
import 'package:cutlog/ui/sheet.dart';

void main() {
  testWidgets('札は開き、中身が見える大きさで組み上がる', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // ★ 本番と同じく、配色と余白は道案内より外側で配る
    await tester.pumpWidget(MaterialApp(
      builder: (BuildContext context, Widget? child) => Skin(
        palette: Palette.lightMode,
        space: Space.forWidth(390),
        child: child ?? const SizedBox.shrink(),
      ),
      home: Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () => openSheet<void>(context, children: <Widget>[
            const SizedBox(height: 120, child: Text('なかみ')),
          ]),
          child: const Text('ひらく'),
        ),
      ),
    ));

    await tester.tap(find.text('ひらく'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('なかみ'), findsOneWidget);
    final Size panel = tester.getSize(find.byType(SheetPanel));
    expect(panel.width, 390);
    expect(panel.height, greaterThan(120));
  });
}
