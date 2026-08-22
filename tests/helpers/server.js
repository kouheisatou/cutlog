// 結合テストが共通で使う、サーバの起動と起動待ちのヘルパー。
//
// 起動待ちは固定の秒数で切らない。node:sqlite の読み込みやマイグレーションが重なると、
// 遅い環境では数秒〜十数秒かかることがあるため、healthz を短い間隔で叩き続け、
// 応答が返った時点で先へ進む。上限（既定60秒）に達したときは、
// 何が起きたのか分かるようにサーバの標準出力・標準エラーを添えて例外にする。
export function spawnServer(spawnFn, execPath, args, env) {
  const child = spawnFn(execPath, args, {
    env,
    // ignore にすると失敗時に手がかりが残らないので、pipe して溜めておく。
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let stdout = '';
  let stderr = '';
  child.stdout?.on('data', (d) => { stdout += d.toString(); });
  child.stderr?.on('data', (d) => { stderr += d.toString(); });
  child.getLogs = () => ({ stdout, stderr });
  return child;
}

export async function waitForHealthy(base, child, { timeoutMs = 60000, intervalMs = 200 } = {}) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeoutMs) {
    try {
      // eslint-disable-next-line no-await-in-loop
      const r = await fetch(`${base}/api/healthz`);
      if (r.ok) return;
    } catch { /* まだ起動していない。接続できるようになるまで待つ */ }
    // eslint-disable-next-line no-await-in-loop
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
  const { stdout, stderr } = child.getLogs ? child.getLogs() : { stdout: '', stderr: '' };
  throw new Error(
    `サーバが${timeoutMs}ms以内に起動しませんでした\n`
    + `--- サーバの標準出力 ---\n${stdout || '(なし)'}\n`
    + `--- サーバの標準エラー ---\n${stderr || '(なし)'}`,
  );
}
