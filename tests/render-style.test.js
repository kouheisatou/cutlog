// まとめ動画の見た目（src/lib/render-style.js）の単体テスト。ffmpegは動かさない。
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  normalizeStyle, DEFAULT_STYLE, SIZE_PRESETS, escapePath, drawTextFile, ffColor,
} from '../src/lib/render-style.js';

test('normalizeStyle({}) は既定値をそのまま返す', () => {
  assert.deepEqual(normalizeStyle({}), DEFAULT_STYLE);
});

test('範囲外の値は丸められる（fontSize・fps）', () => {
  const style = normalizeStyle({ fps: 1, time: { fontSize: 999 } });
  assert.equal(style.time.fontSize, 160);
  assert.equal(style.fps, 10);
});

test('範囲外の値は丸められる（fps上限・photoMs・title.seconds）', () => {
  const style = normalizeStyle({ fps: 999, photoMs: 100, title: { seconds: 99 } });
  assert.equal(style.fps, 60);
  assert.equal(style.photoMs, 300);
  assert.equal(style.title.seconds, 10);
});

test('幅と高さは必ず偶数になる（custom指定で奇数を渡す）', () => {
  const style = normalizeStyle({ size: 'custom', width: 241, height: 481 });
  assert.equal(style.width % 2, 0);
  assert.equal(style.height % 2, 0);
  assert.equal(style.width, 240);
  assert.equal(style.height, 480);
});

test('size: square でプリセットの寸法になる', () => {
  const style = normalizeStyle({ size: 'square', width: 100, height: 100 });
  assert.equal(style.width, SIZE_PRESETS.square.width);
  assert.equal(style.height, SIZE_PRESETS.square.height);
});

test('escapePath がWindowsの区切りを / に変え、ドライブレターのコロンを逃がす', () => {
  const BS = String.fromCharCode(92);
  assert.equal(escapePath(`C:${BS}Windows${BS}Fonts${BS}meiryo.ttc`), `C${BS}:/Windows/Fonts/meiryo.ttc`);
});

// ★利用者が書いた文字は text= に埋め込まず textfile= で渡す。
// 埋め込むと、メモに `a', 別のフィルタ` と書くだけでフィルタグラフから抜け出せる。
test('drawTextFile は文字を埋め込まず textfile= で渡す', () => {
  const out = drawTextFile('/tmp/x.txt', {
    position: 'tl', fontSize: 10, color: '#FFFFFF', box: false,
  }, { margin: 24 });
  assert.match(out, /textfile='\/tmp\/x\.txt'/);
  assert.doesNotMatch(out, /(^|:)text=/);
});

// ★expansion=none を外すと %{...} が展開され、% を含むメモが黙って描かれなくなる（実機で確認）
test('drawTextFile は expansion=none を必ず付ける', () => {
  const out = drawTextFile('/tmp/x.txt', {
    position: 'tl', fontSize: 10, color: '#FFFFFF', box: false,
  }, {});
  assert.match(out, /expansion=none/);
});

test('drawTextFile がtlで左上の座標を出す', () => {
  const out = drawTextFile('/tmp/x.txt', {
    position: 'tl', fontSize: 10, color: '#FFFFFF', box: false,
  }, { margin: 24 });
  assert.match(out, /x=24/);
  assert.match(out, /y=24/);
});

test('drawTextFile がbrで右下の座標を出す', () => {
  const out = drawTextFile('/tmp/x.txt', {
    position: 'br', fontSize: 10, color: '#FFFFFF', box: false,
  }, { margin: 24 });
  assert.match(out, /x=w-tw-24/);
  assert.match(out, /y=h-th-24/);
});

test('drawTextFile がbcで中央下の座標を出す', () => {
  const out = drawTextFile('/tmp/x.txt', {
    position: 'bc', fontSize: 10, color: '#FFFFFF', box: false,
  }, { margin: 24 });
  assert.match(out, /x=\(w-tw\)\/2/);
  assert.match(out, /y=h-th-24/);
});

test('drawTextFile は center を渡すと縦の中央に置く', () => {
  const out = drawTextFile('/tmp/x.txt', {
    position: 'tc', fontSize: 10, color: '#FFFFFF', box: false,
  }, { center: true });
  assert.match(out, /y=\(h-th\)\/2/);
});

test('ffColor が#付きの色を0x表記へ変える', () => {
  assert.equal(ffColor('#FFFFFF'), '0xFFFFFF');
});
