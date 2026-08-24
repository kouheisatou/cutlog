// 書いたものそのものを見張る。
// ★ Dart の文字列に埋める `${...}` を、直そうとして `\${...}` と書いてしまうと、
//   そのまま画面に「${c.hhmm}」と出る。組み立ては通り、動かすまで気づかない。
//   実際にゴミ箱の行がそうなっていた。同じ間違いを二度しないよう、ここで止める。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('埋め込みを打ち消した書き方（\\\$｛）が混ざっていない', () {
    final List<String> bad = <String>[];
    for (final FileSystemEntity f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final List<String> lines = f.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains(r'\$')) bad.add('${f.path}:${i + 1}  ${lines[i].trim()}');
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });
}
