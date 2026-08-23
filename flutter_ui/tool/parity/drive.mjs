// 「その画面まで連れて行く」ところだけを、撮る側と測る側で分け合う。
// ★ 撮った絵と測った数が別々の道で作られると、突き合わせても意味がなくなる。
import { sleep } from './cdp.mjs';
import { ACCOUNT } from './seed.mjs';

/** 動きを止めて、いつ開いても同じ絵・同じ数になるようにする */
export async function calm(page, { dark = false } = {}) {
  await page.send('Emulation.setEmulatedMedia', {
    features: [
      { name: 'prefers-reduced-motion', value: 'reduce' },
      { name: 'prefers-color-scheme', value: dark ? 'dark' : 'light' },
    ],
  });
}

export async function signIn(page, base) {
  await page.goto(`${base}/`, { waitMs: 300 });
  const status = await page.eval(`fetch('/api/auth/login', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: ${JSON.stringify(JSON.stringify({ username: ACCOUNT.username, password: ACCOUNT.password }))},
  }).then((r) => r.status)`);
  if (status !== 200) throw new Error(`ログインに失敗しました（${status}）`);
}

async function runSteps(page, steps) {
  for (const step of steps) {
    if (step.click) await page.click(step.click);
    // 「何番目か」ではなく「何と書いてあるか」で選ぶ。
    // ★ 並び順は中身で変わる。空のログを踏むと、その先の画面へ進めない。
    if (step.clickText) {
      const { sel, text } = step.clickText;
      const hit = await page.eval(`(() => {
        const el = [...document.querySelectorAll(${JSON.stringify(sel)})]
          .find((n) => n.textContent.includes(${JSON.stringify(text)}));
        if (!el) return false;
        el.click();
        return true;
      })()`, { awaitPromise: false });
      if (!hit) throw new Error(`「${text}」の行が見つかりません: ${sel}`);
    }
    if (step.wait) {
      const ok = await page.waitFor(step.wait);
      if (!ok) throw new Error(`出てきません: ${step.wait}`);
    }
    if (step.waitMs) await sleep(step.waitMs);
    if (step.eval) await page.eval(step.eval);
    await page.settle(120);
  }
}

/** 本物の web を、その画面の形にする */
export async function driveWeb(page, screen, base) {
  if (!screen.signedOut) await signIn(page, base);
  await page.goto(`${base}/`, { waitMs: 400 });
  await page.waitFor(screen.signedOut ? '#authScreen' : '#logsScreen');
  await runSteps(page, screen.steps);
  await page.settle(350);
}

/** Flutter 側は、行き先を名前で直に指せるようにしてある */
export async function driveFlutter(page, screen, base) {
  if (!screen.signedOut) await signIn(page, base);
  // ★ 行き先は問い合わせ（?shot=）で渡す。井桁の側は Flutter の道案内が書き換えてしまう。
  //   鍵を持たないまま動き出した1回目が残らないよう、行き先を決めてから必ず読み込み直す。
  await page.goto(`${base}/?shot=${screen.name}`, { waitMs: 200 });
  // 動画を読み込む画面があるので、その分だけ長めに待つ
  await page.reload({ waitMs: screen.flutterWaitMs ?? (screen.designOnly ? 4000 : 1800) });
  await page.settle(600);
}
