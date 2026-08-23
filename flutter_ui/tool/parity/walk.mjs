// 実際に触って、一通り動くかを確かめる。
// ★ 押した先が「正しい画面になったか」は、本物の絵と重ねて判で押す。
//   出た・出ないだけを見ると、似て非なる画面に着いても気づけない。
// ★ 押す所は CSS px（本物の DOM で測った値）。見た目が一致しているので、
//   同じ座標がそのまま使える。
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { launchChrome, Page, sleep } from './cdp.mjs';
import { calm, signIn } from './drive.mjs';
import { VIEWPORT } from './screens.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const outDir = resolve(here, '../../shots/walk');
const base = 'http://localhost:8788';

/** 下の帯の押しどころ（CSS px） */
const TAB = { camera: 39, all: 117, logs: 195, map: 273, settings: 351 };
const TAB_Y = 816;

async function tap(page, x, y) {
  for (const type of ['mousePressed', 'mouseReleased']) {
    await page.send('Input.dispatchMouseEvent', {
      type, x, y, button: 'left', clickCount: 1,
    });
  }
  await sleep(500);
}

const steps = [];

/** 手順を1つ進め、絵を残す。expect があれば本物と重ねて判を押す。 */
async function step(page, name, run, expect, allow) {
  const file = join(outDir, `${String(steps.length + 1).padStart(2, '0')}_${name}.png`);
  try {
    await run();
    await page.settle(500);
    await page.screenshot(file);
    steps.push({ name, ok: true, file, expect, allow });
    console.log(`✓ ${name}`);
  } catch (e) {
    await page.screenshot(file);
    steps.push({ name, ok: false, error: e.message, file, expect, allow });
    console.log(`✗ ${name} — ${e.message}`);
  }
}

async function main() {
  mkdirSync(outDir, { recursive: true });
  const { browser, close } = await launchChrome();
  const page = await Page.open(browser);

  try {
    await calm(page);
    await page.setViewport(VIEWPORT);
    await signIn(page, base);
    await page.goto(`${base}/`, { waitMs: 200 });
    await page.reload({ waitMs: 3500 });

    await step(page, 'ログ一覧', async () => {}, 'logs');

    await step(page, 'ログを追加の札を開く', () => tap(page, 352, 38), 'logs-add');
    await step(page, '外を押して閉じる', () => tap(page, 195, 120), 'logs');

    await step(page, 'ログを検索の札を開く', () => tap(page, 292, 38), 'logs-search');
    await step(page, '外を押して閉じる（検索）', () => tap(page, 195, 120), 'logs');

    // 4行目が「まいにち」（中身のあるログ）
    await step(page, 'ログを開く', () => tap(page, 195, 369), 'log');
    await step(page, 'ログの設定を開く', () => tap(page, 352, 38), 'logset');
    await step(page, 'ログへ戻る', () => tap(page, 38, 38), 'log');
    await step(page, 'ログ一覧へ戻る', () => tap(page, 38, 38), 'logs');

    await step(page, 'カット一覧へ移る', () => tap(page, TAB.all, TAB_Y), 'all');
    await step(page, 'カットの詳細を開く', () => tap(page, 60, 160), 'cut');
    await step(page, '外を押して閉じる（詳細）', () => tap(page, 195, 60), 'all');
    await step(page, '検索の札を開く', () => tap(page, 292, 38), 'all-search');
    await step(page, '外を押して閉じる（検索2）', () => tap(page, 195, 60), 'all');

    await step(page, 'マップへ移る', async () => {
      await tap(page, TAB.map, TAB_Y);
      await sleep(4000);
      // ★ 地図は web が Leaflet、こちらが flutter_map。束ね方も寄せ方も違うので
      //   絵は一致しない。ここは「地図の画面に着いたか」だけを見る。
    }, 'map', 60);

    await step(page, '設定へ移る', () => tap(page, TAB.settings, TAB_Y), 'settings');
    await step(page, 'ログ一覧へ戻る（タブ）', () => tap(page, TAB.logs, TAB_Y), 'logs');
  } finally {
    await close();
  }

  writeFileSync(join(outDir, '_report.json'), JSON.stringify(steps, null, 2));
  const bad = steps.filter((s) => !s.ok);
  console.log(`\n撮り終えました（${steps.length - bad.length}/${steps.length} 手順）。重ねた結果は次で出します。`);
}

main().catch((e) => { console.error(e); process.exit(1); });
