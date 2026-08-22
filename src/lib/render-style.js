// まとめ動画の見た目。SetLogは見た目が固定だが、cutlogはここを全部変えられるようにする。
// 既定値・入力の丸め・ffmpegのフィルタ組み立てを、この1ファイルに閉じ込める。

export const SIZE_PRESETS = {
  portrait: { width: 720, height: 1280 },
  square: { width: 1080, height: 1080 },
  landscape: { width: 1280, height: 720 },
};

export const POSITIONS = ['tl', 'tc', 'tr', 'bl', 'bc', 'br'];

export const TIME_FORMATS = {
  'HH:mm': (d) => d.toISOString().slice(11, 16),
  'HH:mm:ss': (d) => d.toISOString().slice(11, 19),
  'M/D HH:mm': (d) => `${Number(d.toISOString().slice(5, 7))}/${Number(d.toISOString().slice(8, 10))} ${d.toISOString().slice(11, 16)}`,
  'YYYY-MM-DD HH:mm': (d) => `${d.toISOString().slice(0, 10)} ${d.toISOString().slice(11, 16)}`,
};

export const DEFAULT_STYLE = {
  size: 'landscape',
  width: 1280,
  height: 720,
  fit: 'contain',            // contain=全部入れて余白を足す / cover=画面いっぱいに切り抜く
  background: '#000000',
  fps: 30,
  perCutMs: 0,               // 0 なら元の長さのまま
  photoMs: 2000,             // 写真1枚を映す長さ
  order: 'time',             // time=撮った順 / reverse=新しい順
  time: {
    show: true,
    format: 'HH:mm',
    position: 'br',
    fontSize: 36,
    color: '#FFFFFF',
    box: true,
    boxColor: '#000000',
    boxOpacity: 0.4,
  },
  note: {
    show: false,
    position: 'bc',
    fontSize: 28,
    color: '#FFFFFF',
    box: true,
    boxColor: '#000000',
    boxOpacity: 0.4,
  },
  title: {
    show: false,
    text: '',
    seconds: 2,
    fontSize: 64,
    color: '#FFFFFF',
    background: '#000000',
  },
};

const clamp = (v, lo, hi, fallback) => {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(hi, Math.max(lo, Math.round(n)));
};

const hex = (v, fallback) => (/^#[0-9a-fA-F]{6}$/.test(String(v || '')) ? String(v).toUpperCase() : fallback);

const pick = (v, list, fallback) => (list.includes(v) ? v : fallback);

function normalizeText(part, base) {
  const src = part || {};
  return {
    show: src.show === undefined ? base.show : !!src.show,
    format: base.format ? pick(src.format, Object.keys(TIME_FORMATS), base.format) : undefined,
    position: pick(src.position, POSITIONS, base.position),
    fontSize: clamp(src.fontSize, 12, 160, base.fontSize),
    color: hex(src.color, base.color),
    box: src.box === undefined ? base.box : !!src.box,
    boxColor: hex(src.boxColor, base.boxColor),
    boxOpacity: Math.min(1, Math.max(0, Number.isFinite(Number(src.boxOpacity)) ? Number(src.boxOpacity) : base.boxOpacity)),
  };
}

// 利用者から来た値を、安全な範囲に丸めて完全な形にする。
export function normalizeStyle(input) {
  const src = input && typeof input === 'object' ? input : {};
  const size = pick(src.size, [...Object.keys(SIZE_PRESETS), 'custom'], DEFAULT_STYLE.size);
  const preset = SIZE_PRESETS[size];
  const style = {
    size,
    width: preset ? preset.width : clamp(src.width, 240, 2160, DEFAULT_STYLE.width),
    height: preset ? preset.height : clamp(src.height, 240, 3840, DEFAULT_STYLE.height),
    fit: pick(src.fit, ['contain', 'cover'], DEFAULT_STYLE.fit),
    background: hex(src.background, DEFAULT_STYLE.background),
    fps: clamp(src.fps, 10, 60, DEFAULT_STYLE.fps),
    perCutMs: clamp(src.perCutMs, 0, 60000, DEFAULT_STYLE.perCutMs),
    photoMs: clamp(src.photoMs, 300, 15000, DEFAULT_STYLE.photoMs),
    order: pick(src.order, ['time', 'reverse'], DEFAULT_STYLE.order),
    time: normalizeText(src.time, DEFAULT_STYLE.time),
    note: normalizeText(src.note, DEFAULT_STYLE.note),
    title: {
      show: !!(src.title && src.title.show),
      text: String(src.title?.text || '').slice(0, 60),
      seconds: Math.min(10, Math.max(1, Number(src.title?.seconds) || DEFAULT_STYLE.title.seconds)),
      fontSize: clamp(src.title?.fontSize, 16, 200, DEFAULT_STYLE.title.fontSize),
      color: hex(src.title?.color, DEFAULT_STYLE.title.color),
      background: hex(src.title?.background, DEFAULT_STYLE.title.background),
    },
  };
  // 幅と高さは偶数にする（H.264が奇数を受け付けない）
  style.width -= style.width % 2;
  style.height -= style.height % 2;
  delete style.note.format;
  return style;
}

// ★利用者が書いた文字（メモ・表紙の文言）は text= に埋め込まない。
// ffmpegのフィルタの書式には3段の逃がし方があり、1文字でも取りこぼすと
// フィルタグラフから抜け出せてしまう。文字はファイルへ書き、textfile= で渡す。
const BS = String.fromCharCode(92);

// ffmpegのフィルタへパスを渡すときの逃がし方。
// パスはこちらが作るので、対象は Windows の区切りとドライブレターだけである。
export function escapePath(p) {
  return String(p).split(BS).join('/').split(':').join(BS + ':');
}

// ffmpegは #RRGGBB ではなく 0xRRGGBB を期待する
export const ffColor = (color) => `0x${String(color).replace('#', '')}`;
const alpha = (color, opacity) => `${ffColor(color)}@${opacity}`;

export function positionExpr(pos, margin) {
  const x = {
    tl: `${margin}`, bl: `${margin}`,
    tc: '(w-tw)/2', bc: '(w-tw)/2',
    tr: `w-tw-${margin}`, br: `w-tw-${margin}`,
  }[pos];
  const y = pos.startsWith('t') ? `${margin}` : `h-th-${margin}`;
  return { x, y };
}

// fontfile を渡さないと、fontconfig を持たないffmpegでは drawtext が起動できない。
// 環境変数の指定が無いときは、よくある場所から順に探す。
export const FONT_CANDIDATES = [
  '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  '/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc',
  '/System/Library/Fonts/Helvetica.ttc',
  'C:/Windows/Fonts/meiryo.ttc',
  'C:/Windows/Fonts/msgothic.ttc',
  'C:/Windows/Fonts/arial.ttf',
];

// 1つの文字レイヤーを drawtext のフィルタ文字列にする。
// 描く文字は textFile が指すファイルの中身である。
export function drawTextFile(textFile, opt, { fontFile = '', margin = 24, center = false } = {}) {
  const { x, y } = positionExpr(opt.position, margin);
  const parts = [
    `textfile='${escapePath(textFile)}'`,
    'reload=0',
    // ★これを外すと %{...} が展開され、% を含む文字が黙って描かれなくなる
    'expansion=none',
    `x=${x}`,
    `y=${center ? '(h-th)/2' : y}`,
    `fontsize=${opt.fontSize}`,
    `fontcolor=${ffColor(opt.color)}`,
  ];
  if (opt.box) {
    parts.push('box=1', `boxcolor=${alpha(opt.boxColor, opt.boxOpacity)}`, 'boxborderw=10');
  }
  if (fontFile) parts.push(`fontfile='${escapePath(fontFile)}'`);
  return `drawtext=${parts.join(':')}`;
}

// 拡大縮小の仕方（余白を足すか、切り抜くか）。
export function scaleFilters(style) {
  const { width: w, height: h, background } = style;
  if (style.fit === 'cover') {
    return [
      `scale=${w}:${h}:force_original_aspect_ratio=increase`,
      `crop=${w}:${h}`,
      'setsar=1',
      `fps=${style.fps}`,
    ];
  }
  return [
    `scale=${w}:${h}:force_original_aspect_ratio=decrease`,
    `pad=${w}:${h}:(ow-iw)/2:(oh-ih)/2:color=${ffColor(background)}`,
    'setsar=1',
    `fps=${style.fps}`,
  ];
}

export function timeLabel(cut, format) {
  const local = new Date(new Date(cut.taken_at).getTime() - (cut.tz_offset || 0) * 60000);
  return (TIME_FORMATS[format] || TIME_FORMATS['HH:mm'])(local);
}
