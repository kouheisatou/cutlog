// 決めた画面を、決めた大きさで、順番に撮っていく。
//   node shoot.mjs --target=web     --base=http://localhost:8787
//   node shoot.mjs --target=flutter --base=http://localhost:8788
// ★ web も Flutter も同じ Chrome・同じ画面の大きさ・同じ待ち方で撮る。
//   撮り方が違うと、差が「作りの違い」なのか「撮り方の違い」なのか分からなくなる。
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { launchChrome, Page } from './cdp.mjs';
import { calm, driveFlutter, driveWeb } from './drive.mjs';
import { SCREENS, VIEWPORT } from './screens.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const arg = (n, d) => (process.argv.find((a) => a.startsWith(`--${n}=`)) || `--${n}=${d}`).slice(n.length + 3);

const target = arg('target', 'web');
const base = arg('base', target === 'web' ? 'http://localhost:8787' : 'http://localhost:8788');
const outDir = resolve(here, '../../', arg('out', `shots/${target}`));
const only = arg('only', '');

async function main() {
  mkdirSync(outDir, { recursive: true });
  let list = only ? SCREENS.filter((s) => only.split(',').includes(s.name)) : SCREENS;
  // web を写さない画面（Flutter で組み直したもの）は、本物の側では撮らない
  if (target === 'web') list = list.filter((s) => !s.designOnly);
  const { browser, close } = await launchChrome();
  const report = [];

  try {
    for (const screen of list) {
      const page = await Page.open(browser);
      try {
        await calm(page);
        await page.setViewport(VIEWPORT);
        if (target === 'web') await driveWeb(page, screen, base);
        else await driveFlutter(page, screen, base);
        const file = join(outDir, `${screen.name}.png`);
        await page.screenshot(file);
        report.push({ name: screen.name, ok: true });
        console.log(`✓ ${screen.name}`);
      } catch (e) {
        report.push({ name: screen.name, ok: false, error: e.message });
        console.log(`✗ ${screen.name} — ${e.message}`);
      } finally {
        await browser.send('Target.closeTarget', { targetId: undefined }).catch(() => {});
      }
    }
  } finally {
    await close();
  }

  writeFileSync(join(outDir, '_report.json'), JSON.stringify(report, null, 2));
  const bad = report.filter((r) => !r.ok);
  console.log(`\n${report.length - bad.length}/${report.length} 枚 撮れました。`);
}

main().catch((e) => { console.error(e); process.exit(1); });
