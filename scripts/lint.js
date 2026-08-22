// 依存を増やさずに済む範囲の検査。
//   1. すべての .js が構文として通るか（node --check と同じ）
//   2. web/ のアセットに付けたバージョンのクエリが、ファイルの間でそろっているか
//   3. マイグレーションのSQLに連番の抜けや重複が無いか
//
// 使い方: npm run lint
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const problems = [];

function walk(dir, out = []) {
  for (const name of fs.readdirSync(dir)) {
    if (name === 'node_modules' || name.startsWith('.')) continue;
    const full = path.join(dir, name);
    const st = fs.statSync(full);
    if (st.isDirectory()) walk(full, out);
    else out.push(full);
  }
  return out;
}

const files = walk(ROOT);
const rel = (p) => path.relative(ROOT, p).replace(/\\/g, '/');

// 1. 構文
for (const f of files.filter((p) => p.endsWith('.js'))) {
  const code = fs.readFileSync(f, 'utf8');
  try {
    // ESモジュールとして構文だけを見る（実行はしない）
    new vm.SourceTextModule(code, { identifier: rel(f) });
  } catch (err) {
    if (err instanceof SyntaxError) problems.push(`${rel(f)}: 構文が通りません — ${err.message}`);
  }
}

// 2. アセットのバージョン
const versions = new Map();
for (const f of files.filter((p) => p.endsWith('.html'))) {
  const text = fs.readFileSync(f, 'utf8');
  for (const m of text.matchAll(/\?v=([0-9.]+)/g)) {
    if (!versions.has(m[1])) versions.set(m[1], []);
    versions.get(m[1]).push(rel(f));
  }
}
if (versions.size > 1) {
  const list = [...versions.entries()].map(([v, fs2]) => `${v}（${[...new Set(fs2)].join(', ')}）`).join(' / ');
  problems.push(`web のアセットのバージョンがそろっていません: ${list}`);
}

// 3. マイグレーションの連番
const migDir = path.join(ROOT, 'src', 'db', 'migrations');
if (fs.existsSync(migDir)) {
  const nums = fs.readdirSync(migDir)
    .filter((n) => n.endsWith('.sql'))
    .map((n) => ({ n, num: Number(n.slice(0, 3)) }))
    .sort((a, b) => a.num - b.num);
  nums.forEach((cur, i) => {
    if (cur.num !== i + 1) {
      problems.push(`マイグレーションの番号が連続していません: ${cur.n}（${i + 1} を期待しました）`);
    }
  });
}

if (problems.length) {
  for (const p of problems) console.error(`✗ ${p}`);
  console.error(`\n${problems.length}件の問題が見つかりました。`);
  process.exit(1);
}
console.log(`検査しました（.js ${files.filter((p) => p.endsWith('.js')).length}件）。問題はありません。`);
