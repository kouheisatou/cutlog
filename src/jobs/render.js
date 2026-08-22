// 1日のまとめ動画を作る。サーバのffmpegでつなぐ。
// 見た目（大きさ・収め方・時刻の焼き込み・メモ・表紙）は style で全部変えられる。
import path from 'node:path';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import { db } from '../db/index.js';
import { config, paths } from '../config.js';
import { storage, renderStorage } from '../storage/index.js';
import { run, id } from '../lib/util.js';
import { registerHandler } from './queue.js';
import {
  normalizeStyle, scaleFilters, drawTextFile, timeLabel, ffColor, FONT_CANDIDATES,
} from '../lib/render-style.js';

// 焼き込みに使うフォント。設定が無ければ、この環境にあるものを1つ選ぶ。
let fontFileCache = null;
function fontFile() {
  if (fontFileCache !== null) return fontFileCache;
  if (config.ffmpeg.fontFile) {
    fontFileCache = config.ffmpeg.fontFile;
    if (!fs.existsSync(fontFileCache)) {
      console.warn(`[render] RENDER_FONT_FILE が見つかりません: ${fontFileCache}`);
    }
    return fontFileCache;
  }
  fontFileCache = FONT_CANDIDATES.find((f) => fs.existsSync(f)) || '';
  if (!fontFileCache) {
    console.warn('[render] 焼き込みに使えるフォントが見つかりません。RENDER_FONT_FILE を設定してください。');
  }
  return fontFileCache;
}

const COMMON_OUT = ['-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23', '-pix_fmt', 'yuv420p'];
const COMMON_AUDIO = ['-c:a', 'aac', '-ar', '48000', '-ac', '2', '-movflags', '+faststart'];

// 描く文字はファイルへ書いて渡す（フィルタの書式へ埋め込まない）。
async function writeTextFile(stem, tag, text) {
  const file = path.join(paths.tmp, `${stem}_${tag}.txt`);
  await fsp.writeFile(file, String(text), 'utf8');
  return file;
}

async function normalize(cut, outFile, style, stem, index, logName = '') {
  const src = await storage.getPath(cut.storage_key);
  const photoSec = (style.photoMs / 1000).toFixed(3);
  // ffmpegは入力（-i）を出力オプション（-vf など）より先に並べる必要がある。
  // 写真は音が無いので、無音の入力をここで一緒に積む。
  const args = cut.kind === 'photo'
    ? ['-y', '-loop', '1', '-t', photoSec, '-i', src,
      '-f', 'lavfi', '-i', 'anullsrc=channel_layout=stereo:sample_rate=48000']
    : ['-y', '-i', src];

  const filters = scaleFilters(style);
  const opts = { fontFile: fontFile() };
  const textFiles = [];
  if (style.time.show) {
    const f = await writeTextFile(stem, `t${index}`, timeLabel(cut, style.time.format));
    textFiles.push(f);
    filters.push(drawTextFile(f, style.time, opts));
  }
  if (style.note.show && cut.note) {
    const f = await writeTextFile(stem, `n${index}`, cut.note.slice(0, 60));
    textFiles.push(f);
    // 時刻と同じ側に置くときは、重ならないように1段ずらす
    const sameEdge = style.time.show
      && style.time.position[0] === style.note.position[0];
    filters.push(drawTextFile(f, style.note, {
      ...opts,
      margin: sameEdge ? 24 + style.time.fontSize + 28 : 24,
    }));
  }
  // ログの題。画面で見えているものと同じ位置に焼き込む。
  if (style.logName.show && logName) {
    const f = await writeTextFile(stem, `g${index}`, String(logName).slice(0, 40));
    textFiles.push(f);
    filters.push(drawTextFile(f, style.logName, opts));
  }

  args.push('-vf', filters.join(','), ...COMMON_OUT);
  // 1カットの長さを揃えるとき（0なら元の長さのまま）
  if (cut.kind === 'video' && style.perCutMs > 0) {
    args.push('-t', (style.perCutMs / 1000).toFixed(3));
  }
  if (cut.kind === 'photo') args.push('-shortest');
  args.push(...COMMON_AUDIO, outFile);
  try {
    await run(config.ffmpeg.bin, args, { maxBuffer: 1024 * 1024 * 64 });
  } finally {
    await Promise.all(textFiles.map((f) => fsp.unlink(f).catch(() => {})));
  }
}

// 表紙の文字が画面の幅を超えないように、文字サイズを縮める。
// 全角はおよそ1文字ぶん、半角はその半分の幅を取る前提で見積もる。
function fitFontSize(text, fontSize, width) {
  const em = [...String(text)].reduce((n, ch) => n + (/[ -~]/.test(ch) ? 0.55 : 1), 0);
  if (em <= 0) return fontSize;
  const usable = width - 48;
  return Math.max(16, Math.min(fontSize, Math.floor(usable / em)));
}

// 先頭に置く表紙。単色の板に文字を1行だけ置く。
async function titleCard(outFile, style, stem) {
  const { width: w, height: h, fps } = style;
  const t = style.title;
  const label = { ...t, position: 'tc', box: false, fontSize: fitFontSize(t.text, t.fontSize, w) };
  const textFile = await writeTextFile(stem, 'title', t.text);
  const text = drawTextFile(textFile, label, { fontFile: fontFile(), center: true });
  try {
    await run(config.ffmpeg.bin, [
      '-y',
      '-f', 'lavfi', '-i', `color=c=${ffColor(t.background)}:s=${w}x${h}:d=${t.seconds}:r=${fps}`,
      '-f', 'lavfi', '-i', 'anullsrc=channel_layout=stereo:sample_rate=48000',
      '-vf', `${text},setsar=1`,
      '-shortest', ...COMMON_OUT, ...COMMON_AUDIO, outFile,
    ], { maxBuffer: 1024 * 1024 * 16 });
  } finally {
    await fsp.unlink(textFile).catch(() => {});
  }
}

async function renderTimeline(payload) {
  const { cutIds } = payload;
  // 古いジョブは burnTime だけを持っている。style へ寄せて読み替える。
  const style = normalizeStyle(payload.style || { time: { show: !!payload.burnTime } });

  const rows = [];
  for (const cid of cutIds) {
    // eslint-disable-next-line no-await-in-loop
    const c = await db.get('SELECT * FROM cuts WHERE id = ? AND deleted_at IS NULL', [cid]);
    if (c) rows.push(c);
  }
  if (!rows.length) throw new Error('カットがありません');
  // ログの題は、カットが入っているログから引く（画面の見え方と揃えるため）
  const logRow = await db.get('SELECT name FROM logs WHERE id = ?', [rows[0].log_id]);
  const logName = logRow?.name || '';
  rows.sort((a, b) => (a.taken_at < b.taken_at ? -1 : 1));
  if (style.order === 'reverse') rows.reverse();

  const stem = id('rd_');
  const parts = [];
  if (style.title.show && style.title.text) {
    const cover = path.join(paths.tmp, `${stem}_cover.mp4`);
    await titleCard(cover, style, stem);
    parts.push(cover);
  }
  for (const [i, c] of rows.entries()) {
    const part = path.join(paths.tmp, `${stem}_${i}.mp4`);
    // eslint-disable-next-line no-await-in-loop
    await normalize(c, part, style, stem, i, logName);
    parts.push(part);
  }
  const listFile = path.join(paths.tmp, `${stem}.txt`);
  await fsp.writeFile(listFile, parts.map((p) => `file '${p.replace(/\\/g, '/')}'`).join('\n'), 'utf8');
  const outName = `${stem}.mp4`;
  const outFile = path.join(paths.renders, outName);
  await run(config.ffmpeg.bin,
    ['-y', '-f', 'concat', '-safe', '0', '-i', listFile, '-c', 'copy', '-movflags', '+faststart', outFile],
    { maxBuffer: 1024 * 1024 * 64 });
  await Promise.all([...parts, listFile].map((p) => fsp.unlink(p).catch(() => {})));
  const size = await renderStorage.size(outName);
  return {
    filename: outName,
    url: `/api/renders/file/${outName}`,
    cutCount: rows.length,
    bytes: size,
    width: style.width,
    height: style.height,
  };
}

registerHandler('render_timeline', renderTimeline);

export { renderTimeline };
