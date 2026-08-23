// サーバとのやりとりを、本物のサーバ相手に確かめる。
// ★ web ではブラウザが鍵（cookie）を持つが、iOS / Android では誰も持ってくれない。
//   ここが抜けていると、実機でだけ「ずっと 401」になる。目で見つけにくいので試しておく。
// ★ サーバが動いていないときは黙って飛ばす（開発中に邪魔をしない）。
import 'dart:io';

import 'package:cutlog/data/api.dart';
import 'package:cutlog/data/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _base = 'http://localhost:8787';

Future<bool> _serverUp() async {
  try {
    final HttpClient http = HttpClient();
    final HttpClientRequest req = await http.getUrl(Uri.parse('$_base/api/config'));
    final HttpClientResponse res = await req.close();
    await res.drain<void>();
    return res.statusCode == 200;
  } catch (_) {
    return false;
  }
}

void main() {
  setUp(() {
    // 端末に入れっぱなしにする場所は、試すあいだだけ空にしておく
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('鍵を預かって、次の求めに付けて回す', () async {
    if (!await _serverUp()) {
      markTestSkipped('サーバ（$_base）が動いていないので飛ばす');
      return;
    }

    final Api api = Api();

    // 入る前は取れない
    expect(await api.logs().then((_) => 'とれた').catchError((Object e) => e.toString()),
        contains('401'));

    final String? bad = await api.login('parity_shot', 'parity-shot-0000');
    expect(bad, isNull, reason: 'ログインできるはず');

    final List<LogItem> logs = await api.logs();
    expect(logs, isNotEmpty, reason: '鍵が回っていれば、ログが返る');

    // 出たら、また取れなくなる
    await api.logout();
    expect(await api.logs().then((_) => 'とれた').catchError((Object e) => e.toString()),
        contains('401'));
  });
}
