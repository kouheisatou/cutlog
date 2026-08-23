// 本物の画面から、座標と見た目の値をそのまま吸い出す。
// ★ 絵を見比べるだけでは「何 px ずれているか」が分からない。
//   DOM が実際に取った矩形と、ブラウザが決めた最終の値を写し取っておけば、
//   Flutter 側はその数字に合わせて書くだけでよくなる。目測が要らなくなる。
//   使い方: node probe.mjs --only=logs
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { launchChrome, Page } from './cdp.mjs';
import { calm, driveWeb } from './drive.mjs';
import { SCREENS, VIEWPORT } from './screens.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const arg = (n, d) => (process.argv.find((a) => a.startsWith(`--${n}=`)) || `--${n}=${d}`).slice(n.length + 3);

const base = arg('base', 'http://localhost:8787');
const outDir = resolve(here, '../../', arg('out', 'shots/probe'));
const only = arg('only', '');

// 拾う値。ここに無いものは Flutter 側でも使っていない。
const WANTED = [
  'display', 'position', 'flexDirection', 'alignItems', 'justifyContent', 'gap', 'rowGap', 'columnGap',
  'gridTemplateColumns', 'gridAutoRows', 'flexWrap',
  'width', 'height', 'minHeight', 'maxWidth', 'aspectRatio',
  'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft',
  'marginTop', 'marginRight', 'marginBottom', 'marginLeft',
  'borderTopWidth', 'borderRightWidth', 'borderBottomWidth', 'borderLeftWidth', 'borderTopColor', 'borderBottomColor',
  'borderRadius', 'backgroundColor', 'backgroundImage', 'color', 'opacity',
  'fontFamily', 'fontSize', 'fontWeight', 'lineHeight', 'letterSpacing', 'textTransform',
  'textAlign', 'textDecorationLine', 'textUnderlineOffset', 'textShadow', 'boxShadow',
  'objectFit', 'overflow', 'zIndex', 'transform',
];

const DUMP = `(() => {
  const wanted = ${JSON.stringify(WANTED)};
  const out = [];

  // その要素までの道すじ。あとで Flutter のどの部品に当たるか見分けるのに使う。
  function pathOf(el) {
    const bits = [];
    for (let n = el; n && n.nodeType === 1 && bits.length < 8; n = n.parentElement) {
      let s = n.tagName.toLowerCase();
      if (n.id) { bits.unshift(s + '#' + n.id); break; }
      if (n.className && typeof n.className === 'string') {
        s += '.' + n.className.trim().split(/\\s+/).join('.');
      }
      bits.unshift(s);
    }
    return bits.join(' > ');
  }

  function visible(el) {
    const r = el.getBoundingClientRect();
    if (r.width < 0.5 || r.height < 0.5) return false;
    if (r.bottom < 0 || r.top > innerHeight) return false;
    const cs = getComputedStyle(el);
    return cs.visibility !== 'hidden' && cs.display !== 'none' && cs.opacity !== '0';
  }

  const walk = (root) => {
    for (const el of root.querySelectorAll('*')) {
      if (el.closest('.sprite')) continue;      // 型紙は描かれない
      if (!visible(el)) continue;
      const r = el.getBoundingClientRect();
      const cs = getComputedStyle(el);
      const style = {};
      for (const k of wanted) {
        const v = cs[k];
        if (v && v !== 'none' && v !== 'normal' && v !== 'auto' && v !== '0px' && v !== 'rgba(0, 0, 0, 0)') {
          style[k] = v;
        }
      }
      // 直の子の文字だけを拾う（入れ子の文字を二度数えない）
      const own = [...el.childNodes]
        .filter((n) => n.nodeType === 3)
        .map((n) => n.textContent.trim())
        .filter(Boolean)
        .join(' ');
      out.push({
        path: pathOf(el),
        tag: el.tagName.toLowerCase(),
        text: own || undefined,
        rect: { x: +r.x.toFixed(2), y: +r.y.toFixed(2), w: +r.width.toFixed(2), h: +r.height.toFixed(2) },
        style,
      });
    }
  };

  walk(document);
  const dlg = document.querySelector('dialog[open]');
  return { viewport: { w: innerWidth, h: innerHeight }, openDialog: dlg ? dlg.id : null, nodes: out };
})()`;

async function main() {
  mkdirSync(outDir, { recursive: true });
  const list = (only ? SCREENS.filter((s) => only.split(',').includes(s.name)) : SCREENS)
    .filter((s) => !s.designOnly);
  const { browser, close } = await launchChrome();

  try {
    for (const screen of list) {
      const page = await Page.open(browser);
      try {
        await calm(page);
        await page.setViewport(VIEWPORT);
        await driveWeb(page, screen, base);
        const dump = await page.eval(DUMP, { awaitPromise: false });
        writeFileSync(join(outDir, `${screen.name}.json`), JSON.stringify(dump, null, 2));
        console.log(`✓ ${screen.name} — ${dump.nodes.length} 個`);
      } catch (e) {
        console.log(`✗ ${screen.name} — ${e.message}`);
      } finally {
        await browser.send('Target.closeTarget', { targetId: undefined }).catch(() => {});
      }
    }
  } finally {
    await close();
  }
}

main().catch((e) => { console.error(e); process.exit(1); });
