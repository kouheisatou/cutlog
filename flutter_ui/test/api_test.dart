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

  test('作る・直す・移す・消す・戻す が一周する', () async {
    if (!await _serverUp()) {
      markTestSkipped('サーバ（$_base）が動いていないので飛ばす');
      return;
    }

    final Api api = Api();
    expect(await api.login('parity_shot', 'parity-shot-0000'), isNull);

    // ── ログを作って、名前と長さを直す ──────────────
    // ★ 毎回ちがう名前で作ると、試すたびにログが増えて見比べの中身が変わる。
    //   決まった名前のものを1つだけ使い回す。
    const String name = '試し（自動）';
    List<LogItem> logs = await api.logs();
    if (!logs.any((LogItem l) => l.name == name || l.name == '$name-2')) {
      expect(await api.createLog(name), isNull);
      logs = await api.logs();
    }
    final LogItem made =
        logs.firstWhere((LogItem l) => l.name == name || l.name == '$name-2');

    expect(await api.renameLog(made.id, name: '$name-2', cutSeconds: 5), isNull);
    logs = await api.logs();
    final LogItem after = logs.firstWhere((LogItem l) => l.id == made.id);
    expect(after.name, '$name-2');
    expect(after.cutSeconds, 5);

    // 名前は元へ戻しておく（次に試すときのために）
    expect(await api.renameLog(made.id, name: name, cutSeconds: 2), isNull);

    // 招待コードを作り直すと、前とは違うものになる
    final String? before = after.inviteCode;
    expect(await api.rotateInvite(made.id), isNull);
    final Map<String, dynamic> detail = await api.logDetail(made.id);
    expect((detail['log'] as Map<String, dynamic>)['invite_code'], isNot(before));

    // ── カットを移して、消して、戻す ────────────────
    final List<Cut> all = await api.allCuts(limit: 5);
    expect(all, isNotEmpty, reason: '見比べ用の中身が入っているはず');
    final Cut cut = all.first;
    final String home = cut.logId;

    expect(await api.moveCut(cut.id, made.id), isNull);
    expect((await api.cutsOfLog(made.id)).map((Cut c) => c.id), contains(cut.id));

    expect(await api.deleteCut(cut.id), isNull);
    expect((await api.trash(made.id)).map((Cut c) => c.id), contains(cut.id));

    expect(await api.restoreCut(cut.id), isNull);
    expect((await api.cutsOfLog(made.id)).map((Cut c) => c.id), contains(cut.id));

    // 元のログへ戻しておく（次に試すときのために散らかさない）
    expect(await api.moveCut(cut.id, home), isNull);

    // ── ひとことと反応 ──────────────────────────────
    expect(await api.addComment(cut.id, 'テストのひとこと'), isNull);
    expect(await api.react(cut.id, '👍'), isNull);
    expect(await api.react(cut.id, '👍'), isNull);      // もう一度で取り消し

    // ── 撮影リマインダー ────────────────────────────
    expect(await api.saveReminder(const Reminder(mode: 'hourly', fromHour: 8, toHour: 20, perDay: 4)),
        isNull);
    final Map<String, dynamic> mine = await api.meRaw();
    final Reminder saved = Reminder.fromJson(mine['reminder'] as Map<String, dynamic>?);
    expect(saved.mode, 'hourly');
    expect(saved.fromHour, 8);
    expect(saved.perDay, 4);
    // 元に戻す
    expect(await api.saveReminder(const Reminder()), isNull);
  });
}
