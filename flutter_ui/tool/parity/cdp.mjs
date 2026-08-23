// ヘッドレス Chrome を、外の道具に頼らず直に動かす。
// ★ puppeteer などを入れずに済ませたい。Node 22 には WebSocket が最初から入っているので、
//   DevTools Protocol へ直接つなげば、起動・移動・押す・撮るまで全部まかなえる。
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** Chrome が debugging の口を開けるまで待つ */
async function waitForEndpoint(port, timeoutMs = 20000) {
  const until = Date.now() + timeoutMs;
  while (Date.now() < until) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}/json/version`);
      if (res.ok) return (await res.json()).webSocketDebuggerUrl;
    } catch { /* まだ開いていない */ }
    await sleep(120);
  }
  throw new Error(`Chrome が ${timeoutMs}ms 以内に応答しませんでした（port ${port}）`);
}

export async function launchChrome({ port = 9333 } = {}) {
  const profile = mkdtempSync(join(tmpdir(), 'cutlog-parity-'));
  const proc = spawn(CHROME, [
    '--headless=new',
    `--remote-debugging-port=${port}`,
    `--user-data-dir=${profile}`,
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-extensions',
    '--disable-background-timer-throttling',
    '--disable-renderer-backgrounding',
    '--hide-scrollbars',            // 影の幅ぶん絵がずれるのを防ぐ
    '--force-color-profile=srgb',   // 端末ごとの色の寄りを止める
    '--font-render-hinting=none',
    // 撮影の画面を出すため、カメラは作り物の映像で代わりをさせる
    '--use-fake-ui-for-media-stream',
    '--use-fake-device-for-media-stream',
    'about:blank',
  ], { stdio: 'ignore' });

  const browserWs = await waitForEndpoint(port);
  const browser = await connect(browserWs);

  return {
    browser,
    async close() {
      try { browser.close(); } catch { /* 既に閉じている */ }
      proc.kill('SIGTERM');
      await sleep(200);
      try { rmSync(profile, { recursive: true, force: true }); } catch { /* 消えていればよい */ }
    },
  };
}

/** ひとつの WebSocket に、返事待ちの帳簿を持たせただけの薄い包み */
async function connect(url) {
  const ws = new WebSocket(url);
  await new Promise((res, rej) => {
    ws.addEventListener('open', res, { once: true });
    ws.addEventListener('error', rej, { once: true });
  });

  let seq = 0;
  const waiting = new Map();
  const listeners = new Set();

  ws.addEventListener('message', (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id != null && waiting.has(msg.id)) {
      const { resolve, reject } = waiting.get(msg.id);
      waiting.delete(msg.id);
      if (msg.error) reject(new Error(`${msg.error.message} (${JSON.stringify(msg.error.data ?? '')})`));
      else resolve(msg.result);
      return;
    }
    for (const fn of listeners) fn(msg);
  });

  return {
    send(method, params = {}, sessionId) {
      const id = ++seq;
      return new Promise((resolve, reject) => {
        waiting.set(id, { resolve, reject });
        ws.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }));
      });
    },
    on(fn) { listeners.add(fn); return () => listeners.delete(fn); },
    close() { ws.close(); },
  };
}

/** 1枚のタブ。ここに「開く・押す・待つ・撮る」だけを置く。 */
export class Page {
  constructor(browser, sessionId) {
    this.browser = browser;
    this.sessionId = sessionId;
  }

  static async open(browser) {
    const { targetId } = await browser.send('Target.createTarget', { url: 'about:blank' });
    const { sessionId } = await browser.send('Target.attachToTarget', { targetId, flatten: true });
    const page = new Page(browser, sessionId);
    await page.send('Page.enable');
    await page.send('Runtime.enable');
    await page.send('Network.enable');
    return page;
  }

  send(method, params) { return this.browser.send(method, params, this.sessionId); }

  /** 端末の画面の大きさ。web も Flutter も同じ数字で撮る。 */
  setViewport({ width, height, scale = 3, mobile = true }) {
    return this.send('Emulation.setDeviceMetricsOverride', {
      width, height, deviceScaleFactor: scale, mobile,
      screenWidth: width, screenHeight: height,
    });
  }

  async goto(url, { waitMs = 0 } = {}) {
    const done = new Promise((resolve) => {
      const off = this.browser.on((msg) => {
        if (msg.sessionId === this.sessionId && msg.method === 'Page.loadEventFired') { off(); resolve(); }
      });
      setTimeout(() => { off(); resolve(); }, 20000);   // 出ない作りの頁もあるので、待ちきりにしない
    });
    await this.send('Page.navigate', { url });
    await done;
    if (waitMs) await sleep(waitMs);
  }

  /** 頁の中で式を1つ動かし、値を持ち帰る */
  async eval(expression, { awaitPromise = true } = {}) {
    const res = await this.send('Runtime.evaluate', {
      expression, awaitPromise, returnByValue: true, userGesture: true,
    });
    if (res.exceptionDetails) {
      throw new Error(res.exceptionDetails.exception?.description || res.exceptionDetails.text);
    }
    return res.result.value;
  }

  /** その札が出てくるまで待つ（出なければ諦めて false） */
  async waitFor(selector, { timeoutMs = 8000, visible = true } = {}) {
    const until = Date.now() + timeoutMs;
    while (Date.now() < until) {
      const ok = await this.eval(`(() => {
        const el = document.querySelector(${JSON.stringify(selector)});
        if (!el) return false;
        if (!${visible}) return true;
        const r = el.getBoundingClientRect();
        return r.width > 0 && r.height > 0;
      })()`, { awaitPromise: false });
      if (ok) return true;
      await sleep(100);
    }
    return false;
  }

  /** 押す。押せる形になるまで待ってから押す。 */
  async click(selector, { timeoutMs = 8000 } = {}) {
    if (!(await this.waitFor(selector, { timeoutMs }))) {
      throw new Error(`押すものが見つかりません: ${selector}`);
    }
    await this.eval(`document.querySelector(${JSON.stringify(selector)}).click()`, { awaitPromise: false });
  }

  /** 動きが終わって絵が落ち着くのを待つ */
  async settle(ms = 450) {
    await this.eval('new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)))');
    await sleep(ms);
  }

  /** 読み込み直す。ハッシュだけ変えても頁は入れ替わらないので、ここで確実に入れ替える。 */
  async reload({ waitMs = 0 } = {}) {
    const done = new Promise((resolve) => {
      const off = this.browser.on((msg) => {
        if (msg.sessionId === this.sessionId && msg.method === 'Page.loadEventFired') { off(); resolve(); }
      });
      setTimeout(() => { off(); resolve(); }, 20000);
    });
    await this.send('Page.reload', { ignoreCache: true });
    await done;
    if (waitMs) await sleep(waitMs);
  }

  async screenshot(path) {
    const { data } = await this.send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
    writeFileSync(path, Buffer.from(data, 'base64'));
    return path;
  }

  close() { return this.browser.send('Target.closeTarget', { targetId: undefined }, undefined).catch(() => {}); }
}

export { sleep };
