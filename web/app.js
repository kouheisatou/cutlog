// cutlog のフロント。ビルド不要の素のESモジュールで書く（誰でも読んで直せるように）。
const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

const state = {
  config: null,
  user: null,
  logs: [],
  logId: null,
  log: null,
  members: [],
  cuts: [],
  selected: new Set(),   // 書き出しのモーダルの中だけで使う
  day: null,             // いま開いている日（YYYY-MM-DD）
  dayCuts: [],
  // 下のタブ（camera は撮影を開くだけの動き。画面としては残らない）
  tab: 'logs',
  // 「ログ」タブの中でどこまで潜っているか（logs = 一覧、log = ログの中、settings = 設定）
  logsStack: 'logs',
  // 全カット（ログをまたいだ一覧）
  allCuts: [],
  allAuthors: [],       // 検索でえらべる、上げた人の顔ぶれ
  mapPick: [],          // マップで押した場所に重なっていたカット
  commentCut: null,     // コメントを開いているクリップ
  detailCut: null,      // モーダルで開いているカット
  detailFrom: '',
};

// ── API ─────────────────────────────────────────────────
async function api(path, opts = {}) {
  const res = await fetch(`/api${path}`, {
    headers: opts.body instanceof FormData ? {} : { 'Content-Type': 'application/json' },
    ...opts,
  });
  if (res.status === 401) { state.user = null; showAuth(); throw new Error('ログインしてください'); }
  const text = await res.text();
  const data = text ? JSON.parse(text) : {};
  if (!res.ok) throw new Error(data.error || `エラー (${res.status})`);
  return data;
}

function toast(msg, ms = 2600) {
  const el = $('#toast');
  el.textContent = msg;
  el.hidden = false;
  clearTimeout(toast._t);
  toast._t = setTimeout(() => { el.hidden = true; }, ms);
}

const fmtTime = (iso, tz) => {
  const d = new Date(new Date(iso).getTime() - (tz || 0) * 60000);
  return `${String(d.getUTCHours()).padStart(2, '0')}:${String(d.getUTCMinutes()).padStart(2, '0')}`;
};
const fmtBytes = (n) => (n > 1024 * 1024 ? `${(n / 1024 / 1024).toFixed(1)} MB` : `${Math.round(n / 1024)} KB`);

// ── 起動 ────────────────────────────────────────────────
async function boot() {
  state.config = await api('/config');
  const iname = state.config.instanceName;
  $('#instanceName').textContent = iname && iname !== 'cutlog' ? iname : '';
  if (state.config.oidc.enabled) {
    $('#oidcBox').hidden = false;
    $('#oidcBtn').textContent = state.config.oidc.label;
  }
  $('#localBox').hidden = !state.config.localAuth;
  try {
    applyMe(await api('/me'));
    await showApp();
  } catch {
    showAuth();
  }
}

function applyMe(me) {
  state.user = me.user;
  state.reminder = me.reminder;
  state.privateLogId = me.privateLogId;
  state.defaultLogId = me.defaultLogId;
  state.renderStyle = me.renderStyle;
}

function showAuth() {
  $('#logsScreen').hidden = true;
  $('#app').hidden = true;
  $('#dayScreen').hidden = true;
  $('#logSetScreen').hidden = true;
  $('#allScreen').hidden = true;
  $('#mapScreen').hidden = true;
  $('#mapListScreen').hidden = true;
  $('#settingsScreen').hidden = true;
  $('#tabbar').hidden = true;
  $('#authScreen').hidden = false;
}

// 画面の深さ。奥へ進むときは右から、戻るときは左から出す。
// 同じ深さ（タブの行き来）は、そっと入れ替える。
const SCREEN_DEPTH = {
  logs: 0, all: 0, map: 0, settings: 0, log: 1, maplist: 1, logset: 2, day: 2,
};
let shownScreen = 'logs';

function animateScreen(name) {
  const el = {
    logs: '#logsScreen', log: '#app', logset: '#logSetScreen', day: '#dayScreen',
    all: '#allScreen', map: '#mapScreen', maplist: '#mapListScreen', settings: '#settingsScreen',
  }[name];
  const box = $(el);
  if (!box) return;
  const from = SCREEN_DEPTH[shownScreen] ?? 0;
  const to = SCREEN_DEPTH[name] ?? 0;
  const kind = to > from ? 'enter-fwd' : (to < from ? 'enter-back' : 'enter-fade');
  box.classList.remove('enter-fwd', 'enter-back', 'enter-fade');
  // いったん外してから付け直さないと、同じ動きが二度目に走らない
  void box.offsetWidth;
  box.classList.add(kind);
  box.addEventListener('animationend', () => box.classList.remove(kind), { once: true });
  shownScreen = name;
}

// 画面は「ログ一覧（最上位）→ ログ → カットの詳細」の階層で切り替える。
// 設定はログ一覧と並ぶ画面、全カットは下のタブで並ぶ画面である。
function showScreen(name) {
  if (name !== shownScreen) animateScreen(name);
  $('#logsScreen').hidden = name !== 'logs';
  $('#app').hidden = name !== 'log';
  $('#logSetScreen').hidden = name !== 'logset';
  $('#dayScreen').hidden = name !== 'day';
  $('#allScreen').hidden = name !== 'all';
  $('#mapScreen').hidden = name !== 'map';
  $('#mapListScreen').hidden = name !== 'maplist';
  $('#settingsScreen').hidden = name !== 'settings';
  // 画面から離れるときは、鳴っているものを止める
  if (name !== 'day' && play.playing) togglePlay();
  state.tab = { all: 'all', map: 'map', maplist: 'map', settings: 'settings' }[name] || 'logs';
  if (state.tab === 'logs') state.logsStack = name;
  renderTabbar();
  renderCrumbs();
  // カレンダーは、いちばん新しい月が見えている所から始める
  if (name === 'log') scrollCalendarToNewest();
}

async function showApp() {
  $('#authScreen').hidden = true;
  $('#tabbar').hidden = false;
  $('#whoami').textContent = `${state.user.displayName}（${state.user.username}）`;
  await loadLogs();
  // 最上位はログ一覧。ログインしたらまずここが出る。
  renderLogsList();
  showScreen('logs');
  if (new URLSearchParams(location.search).get('capture')) openCapture();
}

// ── 下のタブバー ────────────────────────────────────────
function renderTabbar() {
  $$('.tab-item').forEach((b) => {
    const on = b.dataset.tab === state.tab;
    b.classList.toggle('active', on);
    if (on) b.setAttribute('aria-current', 'page');
    else b.removeAttribute('aria-current');
  });
}

async function selectTab(tab) {
  if (tab === 'camera') { openCapture(); return; }
  if (tab === 'all') { await openAllCuts(); return; }
  if (tab === 'map') { await openMap(); return; }
  if (tab === 'settings') { openSettings(); return; }
  // ログのタブ。すでにログのタブにいるなら、一段上（ログ一覧）へ戻る。
  if (state.tab === 'logs' && state.logsStack !== 'logs') { await openLogs(); return; }
  if (state.logsStack === 'log' && state.log) { showScreen('log'); return; }
  if (state.logsStack === 'settings') { showScreen('settings'); return; }
  await openLogs();
}


// ── 左右にはらってタブを移る ────────────────────────────
// 目盛りをつまむ動きや、映像の上での二本指と喧嘩しないよう、
// 始まった場所と、横に大きく動いたかどうかで見分ける。
const TAB_ORDER = ['camera', 'all', 'logs', 'map', 'settings'];
const swipe = { x: 0, y: 0, t: 0, live: false };

function swipeStartOk(target) {
  if (document.querySelector('dialog[open]')) return false;
  return !target.closest('.scrub, .stage, input[type=range], video, .detail-pane, .pick-list, .map-host');
}

document.addEventListener('touchstart', (ev) => {
  if (ev.touches.length !== 1 || !swipeStartOk(ev.target)) { swipe.live = false; return; }
  swipe.x = ev.touches[0].clientX;
  swipe.y = ev.touches[0].clientY;
  swipe.t = ev.timeStamp;
  swipe.live = true;
}, { passive: true });

document.addEventListener('touchend', (ev) => {
  if (!swipe.live) return;
  swipe.live = false;
  const t = ev.changedTouches[0];
  const dx = t.clientX - swipe.x;
  const dy = t.clientY - swipe.y;
  const dt = ev.timeStamp - swipe.t;
  if (dt > 700 || Math.abs(dx) < 64 || Math.abs(dx) < Math.abs(dy) * 1.6) return;
  const now = TAB_ORDER.indexOf(state.tab);
  const next = TAB_ORDER[now + (dx < 0 ? 1 : -1)];
  if (next) selectTab(next);
}, { passive: true });

// ── パンくず ────────────────────────────────────────────
// いまどこにいるかを「上から順の道すじ」で出す。最後の1つがいまの場所。
function setCrumbs(el, items) {
  if (!el) return;
  el.innerHTML = '';
  const ol = document.createElement('ol');
  items.forEach((item, i) => {
    const li = document.createElement('li');
    const last = i === items.length - 1;
    if (last || !item.go) {
      const span = document.createElement('span');
      // 濃く出すのは最後（いまいる場所）だけ。途中は道すじとして薄く置く。
      span.className = last ? 'crumb current' : 'crumb';
      span.textContent = item.label;
      if (last) span.setAttribute('aria-current', 'page');
      li.appendChild(span);
    } else {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'crumb';
      btn.textContent = item.label;
      btn.addEventListener('click', item.go);
      li.appendChild(btn);
    }
    ol.appendChild(li);
  });
  el.appendChild(ol);
}

function renderCrumbs() {
  const toLogs = () => { openLogs(); };

  setCrumbs($('#logCrumbs'), [{ label: 'ログ', go: toLogs }, { label: state.log ? state.log.name : '—' }]);
  setCrumbs($('#logSetCrumbs'), [
    { label: 'ログ', go: toLogs },
    { label: state.log ? state.log.name : '—', go: () => showScreen('log') },
    { label: '設定' },
  ]);

  // その日の詳細。カットの詳しい画面をひらいているときは、もう一段深くなる。
  const toDay = () => { closeDay(); showScreen('log'); };
  const dayItems = [
    { label: 'ログ', go: toLogs },
    { label: state.log ? state.log.name : '—', go: toDay },
    { label: state.day ? state.day.replace(/-/g, '.') : '—' },
  ];
  setCrumbs($('#dayCrumbs'), dayItems);

  setCrumbs($('#allCrumbs'), []);

  // マップ：てっぺんでは出さない。潜ったときだけ道すじにする。
  const toMap = () => { state.mapPick = []; showScreen('map'); };
  setCrumbs($('#mapListCrumbs'), [
    { label: 'マップ', go: toMap },
    { label: `この場所の${state.mapPick.length}件` },
  ]);
}

async function loadLogs() {
  const { logs } = await api('/logs');
  state.logs = logs;
  if (!logs.length) {
    const { log } = await api('/logs', { method: 'POST', body: JSON.stringify({ name: 'マイログ' }) });
    state.logs = [log];
  }
  // 起動直後は既定の記録先を開く（何も指定しなければ撮ったカットがここへ入る、を画面でも保つ）。
  // 作成・参加の直後は、その場で選んだログ（state.logId）をそのまま使う。
  const wanted = state.logId || state.defaultLogId;
  state.logId = state.logs.some((l) => l.id === wanted) ? wanted : state.logs[0].id;
  await loadLog();
}

async function loadLog() {
  const { log, members, role } = await api(`/logs/${state.logId}`);
  state.log = log; state.members = members; state.role = role;
  $('#logMeta').textContent = log.kind === 'private' ? '非公開' : `${members.length}人`;
  renderCrumbs();
  const sel = $('#authorFilter');
  sel.innerHTML = '<option value="">全員</option>'
    + members.map((m) => `<option value="${m.id}">${escapeHtml(m.display_name)}</option>`).join('');
  $('#tagFilter').value = '';
  await loadCuts();
}

async function loadCuts() {
  const params = new URLSearchParams();
  const author = $('#authorFilter').value;
  if (author) params.set('author', author);
  const tag = $('#tagFilter').value;
  if (tag) params.set('tag', tag);
  const q = $('#search').value.trim();
  if (q) params.set('q', q);
  const { cuts } = await api(`/logs/${state.logId}/cuts?${params}`);
  state.cuts = cuts;
  if (!tag) rebuildTagOptions(cuts);
  render();
}

// このログで実際に使われているタグを、絞り込みの候補に出す。
// タグで絞っている間は候補を作り直さない（候補が自分自身に縮むため）。
function rebuildTagOptions(cuts) {
  const sel = $('#tagFilter');
  const tags = [...new Set(cuts.flatMap((c) => c.tags || []))].sort();
  const current = sel.value;
  sel.innerHTML = '<option value="">タグ</option>'
    + tags.map((t) => `<option value="${escapeHtml(t)}">${escapeHtml(t)}</option>`).join('');
  sel.value = tags.includes(current) ? current : '';
  sel.hidden = !tags.length;
}

// ── 一覧の描画 ──────────────────────────────────────────
// ログの画面はカレンダーだけ。日をひらくと、その日の詳細（つないだ再生）へ進む。
function render() {
  const body = $('#listBody');
  body.innerHTML = '';
  renderCalendar(body);
}


function pressable(el, label, fn) {
  el.setAttribute('role', 'button');
  el.tabIndex = 0;
  el.setAttribute('aria-label', label);
  el.addEventListener('click', fn);
  el.addEventListener('keydown', (ev) => {
    if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); fn(ev); }
  });
}





function renderCalendar(body) {
  const counts = new Map();
  for (const c of state.cuts) counts.set(c.localDate, (counts.get(c.localDate) || 0) + 1);

  // 月を1つずつめくるのではなく、縦に積んで上下に流して見られるようにする。
  // 出す範囲は「いちばん古いカットの月」から「今月（それより後のカットがあればその月）」まで。
  const dates = [...counts.keys()].sort();
  const today = new Date();
  // 記録が少ないうちでも流して見られるよう、少なくとも1年ぶんは並べる
  const floor = new Date(today.getFullYear(), today.getMonth() - 11, 1);
  const oldest = dates.length ? new Date(`${dates[0]}T00:00:00`) : today;
  const firstD = oldest < floor ? oldest : floor;
  const lastCut = dates.length ? new Date(`${dates[dates.length - 1]}T00:00:00`) : today;
  const lastD = lastCut > today ? lastCut : today;

  const wrap = document.createElement('div');
  wrap.className = 'cal cal-scroll';
  const todayStr = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;

  let y = firstD.getFullYear();
  let m = firstD.getMonth();
  let guard = 0;
  let jumpTo = null;
  while ((y < lastD.getFullYear() || (y === lastD.getFullYear() && m <= lastD.getMonth())) && guard++ < 600) {
    const month = document.createElement('section');
    month.className = 'cal-month';
    month.dataset.ym = `${y}-${String(m + 1).padStart(2, '0')}`;

    const head = document.createElement('div');
    head.className = 'cal-month-head';
    const inMonth = state.cuts.filter((c) => c.localDate.startsWith(month.dataset.ym)).length;
    head.innerHTML = `<strong>${y}.${String(m + 1).padStart(2, '0')}</strong>`
      + `<span class="muted small">${inMonth ? `${inMonth}カット` : ''}</span>`;
    month.appendChild(head);

    const grid = document.createElement('div');
    grid.className = 'cal-grid';
    for (const d of ['日', '月', '火', '水', '木', '金', '土']) {
      const el = document.createElement('div');
      el.className = 'cal-dow';
      el.textContent = d;
      grid.appendChild(el);
    }
    const first = new Date(y, m, 1);
    const days = new Date(y, m + 1, 0).getDate();
    for (let i = 0; i < first.getDay(); i += 1) {
      const el = document.createElement('div');
      el.className = 'cal-day empty';
      grid.appendChild(el);
    }
    for (let d = 1; d <= days; d += 1) {
      const date = `${y}-${String(m + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
      const n = counts.get(date) || 0;
      const el = document.createElement('button');
      el.type = 'button';
      el.className = `cal-day${n ? ' has' : ''}${date === todayStr ? ' today' : ''}`;
      if (state.day === date) el.className += ' on';
      if (!n) el.disabled = true;
      el.setAttribute('aria-label', `${m + 1}月${d}日、${n}カット`);
      const bars = Array.from({ length: Math.min(n, 6) }, () => '<i></i>').join('');
      el.innerHTML = `<span class="d">${String(d).padStart(2, '0')}</span><span class="bar">${bars}</span>`;
      el.addEventListener('click', () => openDay(date));
      grid.appendChild(el);
    }
    month.appendChild(grid);
    wrap.appendChild(month);
    jumpTo = month;
    m += 1;
    if (m > 11) { m = 0; y += 1; }
  }

  body.appendChild(wrap);
}

// いちばん新しい月が見えている所から始める。
// 画面が出てからでないと動かせないので、出したあとに呼ぶ。
function scrollCalendarToNewest() {
  const sb = $('#app .screen-body');
  if (!sb) return;
  // 画面を出した直後に呼ぶ。scrollHeight を読むと、その場で高さが決まるので、
  // フレームを待たずに合わせられる（待ちに頼ると、裏に回った画面では動かない）。
  const max = sb.scrollHeight - sb.clientHeight;
  if (max <= 0) return;
  const keep = sb.style.scrollBehavior;
  sb.style.scrollBehavior = 'auto';   // ここは滑らかに動かさず、その場で合わせる
  sb.scrollTop = max;
  sb.style.scrollBehavior = keep;
}


function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (m) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[m]));
}

// ── 詳細 ────────────────────────────────────────────────
// 詳細は、どの画面から開いても同じモーダルに出す。
// 文脈は「直したり消したりしたあと、何を取り直すか」を決めるためだけに使う。
const DETAIL_CTX = {
  day: { rerender: () => renderDayList(), refresh: () => reloadDay() },
  map: { rerender: () => drawMap(), refresh: () => loadMapCuts().then(drawMap) },
  all: { rerender: () => renderAll(), refresh: () => loadAllCuts() },
};

async function openDetail(cutId, ctxName = 'day') {
  const ctx = DETAIL_CTX[ctxName];
  state.detailFrom = ctxName;
  const { cut, reactions, myReactions, comments } = await api(`/cuts/${cutId}`);
  state.detailCut = cut;
  const el = $('#detail');
  if (!$('#cutDialog').open) $('#cutDialog').showModal();
  const media = cut.kind === 'photo'
    ? `<img class="detail-media" src="${cut.url}" alt="" />`
    : `<video class="detail-media" src="${cut.url}" controls playsinline></video>`;
  el.innerHTML = `
    ${media}
    <div class="detail-head">
      <div>
        <span class="eyebrow">${escapeHtml(cut.author || '')}</span>
        <h2>${cut.localDate.replace(/-/g, '.')} ${fmtTime(cut.takenAt, cut.tzOffset)}</h2>
      </div>
      <div class="spacer"></div>
      <button class="icon-btn" id="metaBtn" aria-expanded="false" aria-label="詳しい値を見る・直す">
        <svg class="ic"><use href="#ic-settings"/></svg>
      </button>
    </div>
    <div class="detail-actions">
      <button class="btn" id="dlBtn"><svg class="ic sm"><use href="#ic-download"/></svg>ダウンロード</button>
      <button class="btn" id="moveOne"><svg class="ic sm"><use href="#ic-move"/></svg>移動</button>
      <button class="btn danger" id="delBtn"><svg class="ic sm"><use href="#ic-trash"/></svg>削除</button>
    </div>
    <div class="reactions">
      ${['👍', '🎉', '😂', '🥺', '🔥'].map((e) => {
    const n = reactions.find((r) => r.emoji === e)?.n || 0;
    return `<button class="reaction${myReactions.includes(e) ? ' on' : ''}" data-emoji="${e}">${e} ${n || ''}</button>`;
  }).join('')}
    </div>
    <div id="metaBox" hidden>
    <label class="small muted" for="noteEdit">メモ</label>
    <div class="panel-row">
      <input id="noteEdit" value="${cut.note ? escapeHtml(cut.note) : ''}" placeholder="ひとこと" />
      <button class="btn" id="saveNote">保存</button>
    </div>
    <table class="kv">
      <tr><td>撮影日時</td><td>${new Date(cut.takenAt).toLocaleString('ja-JP')}</td></tr>
      <tr><td>日付</td><td>${cut.localDate}（UTC${cut.tzOffset <= 0 ? '+' : '-'}${Math.abs(cut.tzOffset) / 60}）</td></tr>
      <tr><td>撮った人</td><td>${escapeHtml(cut.author || '')}</td></tr>
      <tr><td>種類</td><td>${cut.kind === 'photo' ? '写真' : '動画'}（${cut.mime}）</td></tr>
      <tr><td>タグ</td><td>${cut.tags.length ? cut.tags.map(escapeHtml).join('、') : '—'}</td></tr>
      <tr><td>長さ</td><td>${cut.durationMs ? `${(cut.durationMs / 1000).toFixed(1)} 秒` : '—'}</td></tr>
      <tr><td>解像度</td><td>${cut.width && cut.height ? `${cut.width}×${cut.height}` : '—'}</td></tr>
      <tr><td>カメラ</td><td>${cut.facing === 'user' ? 'インカメラ' : cut.facing === 'environment' ? 'アウトカメラ' : '—'}</td></tr>
      <tr><td>撮影方法</td><td>${cut.source === 'upload' ? 'ファイルから取り込み' : 'その場で撮影'}</td></tr>
      <tr><td>サイズ</td><td>${fmtBytes(cut.bytes)}</td></tr>
      <tr><td>チェックサム</td><td class="small">${cut.checksum ? `${cut.checksum.slice(0, 16)}…` : '—'}</td></tr>
      <tr><td>撮った場所</td><td class="small">${cut.lat != null && cut.lon != null
        ? `${cut.lat.toFixed(5)}, ${cut.lon.toFixed(5)}${cut.placeAccuracy ? `（だいたい${Math.round(cut.placeAccuracy)}m）` : ''}`
        : '—'}</td></tr>
      <tr><td>ID</td><td class="small">${cut.id}</td></tr>
    </table>
    </div>
    <div class="comments">
      <h3 class="small muted">コメント</h3>
      ${comments.map((c) => `<div class="comment">
        ${avatarHtml(c.avatarUrl, c.author)}
        <div class="c-body"><strong>${escapeHtml(c.author)}</strong><span>${escapeHtml(c.body)}</span></div>
      </div>`).join('')}
      <div class="panel-row">
        <input id="commentInput" placeholder="コメントを書く" />
        <button class="btn" id="sendComment">送信</button>
      </div>
    </div>`;
  ctx.rerender();
  renderCrumbs();

  // 3つの詳細（ログの中・カット一覧・マップ）が同じidを持つので、必ずこの画面の中だけを探す。
  $('#dlBtn', el).addEventListener('click', () => { window.location.href = `${cut.url}?download=1`; });
  $('#metaBtn', el).addEventListener('click', () => {
    const box = $('#metaBox', el);
    box.hidden = !box.hidden;
    $('#metaBtn', el).setAttribute('aria-expanded', String(!box.hidden));
  });
  $('#moveOne', el).addEventListener('click', () => openMove([cut.id], cut.logId, { single: true }));
  $('#delBtn', el).addEventListener('click', async () => {
    if (!confirm('このカットを削除しますか。ゴミ箱から戻せます。')) return;
    await api(`/cuts/${cut.id}`, { method: 'DELETE' });
    toast('カットを削除しました');
    closeCutDetail();
    await ctx.refresh();
  });
  $$('.reaction', el).forEach((b) => b.addEventListener('click', async () => {
    await api(`/cuts/${cut.id}/reactions`, { method: 'POST', body: JSON.stringify({ emoji: b.dataset.emoji }) });
    openDetail(cut.id, ctxName);
  }));
  $('#saveNote', el).addEventListener('click', async () => {
    await api(`/cuts/${cut.id}`, { method: 'PATCH', body: JSON.stringify({ note: $('#noteEdit', el).value }) });
    toast('メモを保存しました');
    await ctx.refresh();
  });
  $('#sendComment', el).addEventListener('click', async () => {
    const body = $('#commentInput', el).value.trim();
    if (!body) return;
    await api(`/cuts/${cut.id}/comments`, { method: 'POST', body: JSON.stringify({ body }) });
    openDetail(cut.id, ctxName);
  });
}






// ── モーダル ────────────────────────────────────────────
// 外側を押しても、右上のばつを押しても閉じる。逃げ道を必ず用意する。
function wireModals() {
  $$('dialog.sheet').forEach((dlg) => {
    // 背景（dialog そのもの）を押したときだけ閉じる。中身の上での指の動きは拾わない。
    dlg.addEventListener('pointerdown', (ev) => { dlg.dataset.downOutside = String(ev.target === dlg); });
    dlg.addEventListener('click', (ev) => {
      if (ev.target === dlg && dlg.dataset.downOutside === 'true') closeModal(dlg);
    });
    $$('[data-close]', dlg).forEach((b) => b.addEventListener('click', () => closeModal(dlg)));
    if (dlg.id !== 'captureDialog') wireSheetDrag(dlg);
    // 開いたら、次の間に「せり上がった状態」へ切り替える。
    // 開いたこと自体を見張るので、どこから開かれても同じように動く。
    new MutationObserver(() => {
      if (dlg.open) { setTimeout(() => dlg.classList.add('in'), 0); settleSheet(dlg); }
      else {
        dlg.classList.remove('in');
        // 次に開くときのために、押さえていた指定を戻す
        const p2 = dlg.querySelector('.panel');
        if (p2) { p2.style.transition = ''; p2.style.transform = ''; }
      }
    }).observe(dlg, { attributes: true, attributeFilter: ['open'] });
  });
}

// せり上がりが走らない場（動きを止めている端末や、裏に回った画面）でも、
// 開いたシートが画面の外に取り残されないようにする。少し経っても出て来ていなければ、
// 動きを切って、その場で所定の位置へ置く。
function settleSheet(dlg) {
  const panel = dlg.querySelector('.panel');
  if (!panel) return;
  setTimeout(() => {
    if (!dlg.open) return;
    const r = panel.getBoundingClientRect();
    const shown = window.innerHeight - r.top;
    if (shown > r.height * 0.6) return;   // ちゃんと出ている
    // ここで動きを切ったままにする。戻すと、止まっていた動きが元の位置へ引き戻すことがある。
    // 閉じるときに指定を消すので、次に開くときはまたせり上がる。
    panel.style.transition = 'none';
    panel.style.transform = 'none';
  }, 420);
}

// シートを下へ払うと閉じる。中身を上下に読んでいる途中は掴まない
// （いちばん上まで戻っているときだけ、指の動きをシートの移動として受け取る）。
function wireSheetDrag(dlg) {
  const panel = dlg.querySelector('.panel');
  if (!panel) return;
  let from = null;
  panel.addEventListener('pointerdown', (ev) => {
    if (ev.target.closest('input, textarea, select, button, a, video, .scrub, .map-host')) return;
    if (panel.scrollTop > 0) return;
    from = { y: ev.clientY, id: ev.pointerId };
  });
  panel.addEventListener('pointermove', (ev) => {
    if (!from) return;
    const dy = ev.clientY - from.y;
    if (dy <= 0) { panel.style.transform = ''; return; }
    panel.style.transition = 'none';
    panel.style.transform = `translateY(${dy}px)`;
  });
  const end = (ev) => {
    if (!from) return;
    const dy = (ev.clientY ?? from.y) - from.y;
    from = null;
    panel.style.transition = '';
    panel.style.transform = '';
    if (dy > 110) closeModal(dlg);
  };
  panel.addEventListener('pointerup', end);
  panel.addEventListener('pointercancel', end);
}

// 閉じるときは、下へ沈んでから消す
function closeModal(dlg) {
  if (dlg.id === 'captureDialog') { closeCapture(); return; }
  const panel = dlg.querySelector('.panel');
  const reduce = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
  if (!panel || reduce) { dlg.close(); return; }
  dlg.classList.remove('in');
  let closed = false;
  const done = () => { if (closed) return; closed = true; dlg.close(); };
  panel.addEventListener('transitionend', done, { once: true });
  setTimeout(done, 300);   // 動きが起きなかったときの逃げ道
}

// どの閉じ方（ばつ・外側・Esc）でも後始末が走るよう、閉じたことそのものを見る
$('#cutDialog').addEventListener('close', () => {
  if (!state.detailCut) return;
  state.detailCut = null;
  state.detailFrom = '';
  $('#detail').innerHTML = '';
  renderDayList();
  renderCrumbs();
});

// ── マップ ──────────────────────────────────────────────
// 撮った場所を地図の上に出す。地図の絵（タイル）は決まった住所から <img> で取るだけなので、
// 外の道具を読み込まなくても動く。タイルの出どころはサーバの設定で変えられる。
const map = { z: 13, cx: 0, cy: 0, cuts: [], tileUrl: '', credit: '', ready: false };
const TILE = 256;

const lon2x = (lon, z) => ((lon + 180) / 360) * Math.pow(2, z);
const lat2y = (lat, z) => {
  const r = (lat * Math.PI) / 180;
  return ((1 - Math.log(Math.tan(r) + 1 / Math.cos(r)) / Math.PI) / 2) * Math.pow(2, z);
};

async function openMap() {
  showScreen('map');
  if (!map.cuts.length) await loadMapCuts();
  drawMap();
}

async function loadMapCuts() {
  const { cuts } = await api('/cuts?limit=500');
  map.cuts = cuts.filter((c) => c.lat != null && c.lon != null);
  $('#mapCount').textContent = `${map.cuts.length}件`;
  $('#mapEmpty').hidden = map.cuts.length > 0;
  map.tileUrl = state.config?.mapTileUrl || '';
  map.credit = state.config?.mapCredit || '';
  $('#mapCredit').textContent = map.credit;
  if (map.cuts.length && !map.ready) {
    // はじめは、撮った場所が全部入るところへ合わせる
    const lats = map.cuts.map((c) => c.lat);
    const lons = map.cuts.map((c) => c.lon);
    const midLat = (Math.min(...lats) + Math.max(...lats)) / 2;
    const midLon = (Math.min(...lons) + Math.max(...lons)) / 2;
    const span = Math.max(Math.max(...lats) - Math.min(...lats), Math.max(...lons) - Math.min(...lons));
    map.z = span > 0 ? Math.max(2, Math.min(16, Math.floor(Math.log2(360 / span)) - 1)) : 14;
    map.cx = lon2x(midLon, map.z);
    map.cy = lat2y(midLat, map.z);
    map.ready = true;
  }
}

// ピンは、近いものをまとめて1つにする（写真のアプリの地図と同じ考え方）。
// 縮めるとまとまり、広げると分かれる。まとまりを押すと、そこへ寄る。
const CLUSTER_PX = 68;

function clusterPins(pts, w, h) {
  const cells = new Map();
  for (const p of pts) {
    if (p.px < -60 || p.py < -60 || p.px > w + 60 || p.py > h + 60) continue;
    const key = `${Math.floor(p.px / CLUSTER_PX)},${Math.floor(p.py / CLUSTER_PX)}`;
    if (!cells.has(key)) cells.set(key, []);
    cells.get(key).push(p);
  }
  return [...cells.values()].map((group) => {
    // まとまりの位置は、中に入っているものの平均にする（格子の目が見えないように）
    const px = group.reduce((a, g) => a + g.px, 0) / group.length;
    const py = group.reduce((a, g) => a + g.py, 0) / group.length;
    // 見本は、いちばん新しいカットのものを使う
    const head = group.reduce((a, g) => (a.cut.takenAt > g.cut.takenAt ? a : g));
    return { px, py, group, head };
  });
}

function drawMap() {
  const host = $('#mapHost');
  const w = host.clientWidth || 640;
  const h = host.clientHeight || 480;
  const tiles = $('#mapTiles');
  const pins = $('#mapPins');
  tiles.innerHTML = '';
  pins.innerHTML = '';
  if (!map.cuts.length) return;

  // 画面の真ん中がどのタイルの、どの位置に当たるかを出す
  const left = map.cx * TILE - w / 2;
  const top = map.cy * TILE - h / 2;
  const n = Math.pow(2, map.z);

  if (map.tileUrl) {
    const x0 = Math.floor(left / TILE);
    const y0 = Math.floor(top / TILE);
    const x1 = Math.floor((left + w) / TILE);
    const y1 = Math.floor((top + h) / TILE);
    for (let x = x0; x <= x1; x += 1) {
      for (let y = y0; y <= y1; y += 1) {
        if (y < 0 || y >= n) continue;
        const img = document.createElement('img');
        img.className = 'tile';
        img.alt = '';
        img.src = map.tileUrl
          .replace('{z}', map.z).replace('{x}', ((x % n) + n) % n).replace('{y}', y);
        img.style.left = `${x * TILE - left}px`;
        img.style.top = `${y * TILE - top}px`;
        tiles.appendChild(img);
      }
    }
  }

  const pts = map.cuts.map((c) => ({
    cut: c,
    px: lon2x(c.lon, map.z) * TILE - left,
    py: lat2y(c.lat, map.z) * TILE - top,
  }));

  for (const cl of clusterPins(pts, w, h)) {
    const one = cl.group.length === 1;
    const pin = document.createElement('button');
    pin.type = 'button';
    pin.className = `map-pin${one ? '' : ' many'}`;
    pin.style.left = `${cl.px}px`;
    pin.style.top = `${cl.py}px`;
    const c = cl.head.cut;
    pin.setAttribute('aria-label', one
      ? `${c.localDate} ${fmtTime(c.takenAt, c.tzOffset)} のカット`
      : `このあたりの${cl.group.length}件`);
    pin.innerHTML = (c.thumbUrl ? `<img src="${c.thumbUrl}" alt="" />` : '<span></span>')
      + (one ? '' : `<span class="n">${cl.group.length}</span>`);
    pin.addEventListener('click', () => openCutsFromMap(cl.group.map((g) => g.cut)));
    pins.appendChild(pin);
  }
}

// 指や矢印で地図を動かす
function wireMapDrag() {
  const host = $('#mapHost');
  let from = null;
  host.addEventListener('pointerdown', (ev) => {
    if (ev.target.closest('.map-pin')) return;
    from = { x: ev.clientX, y: ev.clientY, cx: map.cx, cy: map.cy };
    host.classList.add('grabbing');
    try { host.setPointerCapture(ev.pointerId); } catch { /* 掴めない指もある */ }
  });
  host.addEventListener('pointermove', (ev) => {
    if (!from) return;
    map.cx = from.cx - (ev.clientX - from.x) / TILE;
    map.cy = from.cy - (ev.clientY - from.y) / TILE;
    drawMap();
  });
  const done = () => { from = null; host.classList.remove('grabbing'); };
  host.addEventListener('pointerup', done);
  host.addEventListener('pointercancel', done);
  // ホイールでも寄る・引く
  host.addEventListener('wheel', (ev) => {
    ev.preventDefault();
    mapZoom(ev.deltaY < 0 ? 1 : -1);
  }, { passive: false });
}

function mapZoom(d) {
  const z = Math.max(2, Math.min(18, map.z + d));
  if (z === map.z) return;
  const k = Math.pow(2, z - map.z);
  map.cx *= k;
  map.cy *= k;
  map.z = z;
  drawMap();
}

// 地図で押した所に重なっていたカットを、マップの1つ下に並べる。
// カット一覧のタブへは移らない（マップの中で潜っていく）。
function openCutsFromMap(cuts) {
  state.mapPick = cuts.slice().sort((a, b) => (a.takenAt < b.takenAt ? 1 : -1));
  renderMapList();
  showScreen('maplist');
}

function renderMapList() {
  const body = $('#mapListBody');
  body.innerHTML = '';
  const wrap = document.createElement('div');
  wrap.className = 'photo-grid';
  for (const c of state.mapPick) {
    const cell = document.createElement('div');
    cell.className = 'photo-cell';
    const t = fmtTime(c.takenAt, c.tzOffset);
    cell.innerHTML = `
      ${c.thumbUrl ? `<img loading="lazy" src="${c.thumbUrl}" alt="" />` : '<span class="ph"></span>'}
      <span class="cap"><span class="t">${t}</span><span class="lg">${escapeHtml(c.logName || '')}</span></span>`;
    pressable(cell, `${escapeHtml(c.logName || '')} ${t} のカットを開く`, () => openDetail(c.id, 'map'));
    wrap.appendChild(cell);
  }
  body.appendChild(wrap);
}



// ── コメント ────────────────────────────────────────────
// その日の並びから、クリップごとに開いて読み書きする。
async function openComments(cut) {
  state.commentCut = cut;
  $('#commentTitle').textContent = `${fmtTime(cut.takenAt, cut.tzOffset)} のコメント`;
  $('#commentBox').value = '';
  $('#commentList').innerHTML = '<span class="muted small">読み込んでいます…</span>';
  if (!$('#commentDialog').open) $('#commentDialog').showModal();
  await paintComments();
}

async function paintComments() {
  const cut = state.commentCut;
  if (!cut) return;
  const { comments } = await api(`/cuts/${cut.id}`);
  const box = $('#commentList');
  box.innerHTML = comments.length ? '' : '<span class="muted small">まだコメントはありません。</span>';
  for (const c of comments) {
    const row = document.createElement('div');
    row.className = 'comment';
    row.innerHTML = `${avatarHtml(c.avatarUrl, c.author)}
      <div class="c-body"><strong>${escapeHtml(c.author)}</strong><span>${escapeHtml(c.body)}</span></div>`;
    if (c.userId === state.user?.id) {
      const del = document.createElement('button');
      del.className = 'mini';
      del.textContent = '消す';
      del.addEventListener('click', async () => {
        await api(`/comments/${c.id}`, { method: 'DELETE' });
        await paintComments();
        await refreshCommentCounts();
      });
      row.appendChild(del);
    }
    box.appendChild(row);
  }
  // 数が変わっていれば、並びのしるしにも反映する
  const target = state.dayCuts.find((x) => x.id === cut.id);
  if (target) target.commentCount = comments.length;
  renderDayList();
}

async function refreshCommentCounts() {
  renderDayList();
}

// ── アカウントの顔 ──────────────────────────────────────
// 絵を置いていない人は、名前の頭文字で出す。
function avatarHtml(url, name, cls = '') {
  const initial = escapeHtml(String(name || '?').trim().slice(0, 1).toUpperCase());
  return url
    ? `<span class="avatar ${cls}"><img src="${url}" alt="" /></span>`
    : `<span class="avatar ${cls}">${initial}</span>`;
}

function paintMyAvatar() {
  const u = state.user;
  if (!u) return;
  $('#myAvatar').innerHTML = u.avatarUrl
    ? `<img src="${u.avatarUrl}?t=${Date.now()}" alt="" />`
    : escapeHtml(String(u.displayName || u.username || '?').trim().slice(0, 1).toUpperCase());
  $('#avatarClear').hidden = !u.avatarUrl;
}

// ── このログの設定 ──────────────────────────────────────
// ログに関わることは、全体の設定ではなくここに集める。
// 名前・1クリップの長さ・行き先の既定・招待コード・いる人・共有リンク・ゴミ箱。
function openLogSettings() {
  const l = state.log;
  if (!l) return;
  $('#logSetName').value = l.name;
  $('#logSetSeconds').value = Number(l.cut_seconds) || CLIP_SECONDS_DEFAULT;
  $('#logSetDefault').checked = (state.defaultLogId || state.privateLogId) === l.id;
  const owner = state.role === 'owner';
  $('#logSetName').disabled = !owner;
  $('#logSetSeconds').disabled = !owner;
  $('#logSetSave').disabled = !owner;
  $('#logSetRotate').disabled = !owner;
  const priv = l.kind === 'private';
  $('#logSetInviteRow').hidden = priv;
  $('#logSetInvite').textContent = l.invite_code || '';
  $('#logSetMemberCount').textContent = `${state.members.length}人`;
  renderLogMembers();
  $('#logSetTrashList').innerHTML = '';
  showScreen('logset');
}

function renderLogMembers() {
  const box = $('#logSetMembers');
  box.innerHTML = '';
  for (const m of state.members) {
    const row = document.createElement('div');
    row.className = 'member-row';
    const isOwner = m.id === state.log.owner_id;
    row.innerHTML = `<span class="n">${escapeHtml(m.display_name)}</span>
      <span class="muted small">${isOwner ? 'オーナー' : 'メンバー'}</span>`;
    if (state.role === 'owner' && !isOwner) {
      const out = document.createElement('button');
      out.className = 'mini';
      out.textContent = '除外';
      out.addEventListener('click', async () => {
        if (!confirm(`${m.display_name} をこのログから除外しますか。`)) return;
        await api(`/logs/${state.logId}/members/${m.id}`, { method: 'DELETE' });
        toast('除外しました');
        await loadLog();
        renderLogMembers();
        $('#logSetMemberCount').textContent = `${state.members.length}人`;
      });
      row.appendChild(out);
    }
    box.appendChild(row);
  }
}

async function saveLogSettings() {
  const name = $('#logSetName').value.trim();
  const cutSeconds = Math.min(30, Math.max(1, Number($('#logSetSeconds').value) || CLIP_SECONDS_DEFAULT));
  await api(`/logs/${state.logId}`, { method: 'PATCH', body: JSON.stringify({ name, cutSeconds }) });
  // 行き先の既定は利用者ごとの設定なので、こちらは /me へ送る
  const wantDefault = $('#logSetDefault').checked;
  const isDefault = (state.defaultLogId || state.privateLogId) === state.logId;
  if (wantDefault !== isDefault) {
    const to = wantDefault ? state.logId : state.privateLogId;
    const res = await api('/me', {
      method: 'PATCH',
      body: JSON.stringify({ defaultLogId: to === state.privateLogId ? null : to }),
    });
    state.defaultLogId = res.defaultLogId;
  }
  await loadLogs();
  await loadLog();
  toast('保存しました');
  openLogSettings();
}

async function showTrash() {
  const { cuts } = await api(`/logs/${state.logId}/trash`);
  const box = $('#logSetTrashList');
  box.innerHTML = cuts.length ? '' : '<span class="muted small">消したカットはありません。</span>';
  for (const c of cuts) {
    const row = document.createElement('div');
    row.className = 'member-row';
    row.innerHTML = `<span class="n">${c.localDate} ${fmtTime(c.takenAt, c.tzOffset)}　${escapeHtml(c.note || '')}</span>`;
    const back = document.createElement('button');
    back.className = 'mini';
    back.textContent = '戻す';
    back.addEventListener('click', async () => {
      await api(`/cuts/${c.id}/restore`, { method: 'POST' });
      toast('戻しました');
      await loadCuts();
      showTrash();
    });
    row.appendChild(back);
    box.appendChild(row);
  }
}

// ── その日の詳細 ────────────────────────────────────────
// つないだ再生と、その日のクリップの並び。
// ここでの「非表示」は選ぶことではなく、そのカットを出すかどうかの状態である。
// 書き出しに何を入れるかは、書き出しのモーダルで改めて選んでもらう。
function daysWithCuts() {
  return [...new Set(state.cuts.map((c) => c.localDate))].sort();
}

function visibleDayIds() {
  return state.dayCuts.filter((c) => !c.hidden).map((c) => c.id);
}

// 書き出しのモーダルには、非表示のぶんも並べる（そこで選び直せるように）
function dayIds() {
  return state.dayCuts.map((c) => c.id);
}

function updatePickCount() {
  const all = $$('#exportList input[type=checkbox]').length;
  $('#pickCount').textContent = `${$$('#exportList input:checked').length} / ${all} 件`;
}

function setPicks(on) {
  $$('#exportList input[type=checkbox]').forEach((i) => { i.checked = on; });
  updatePickCount();
}

async function openDay(date) {
  state.day = date;
  state.dayCuts = state.cuts
    .filter((c) => c.localDate === date)
    .sort((a, b) => (a.takenAt < b.takenAt ? -1 : 1));
  closeCutDetail();
  showScreen('day');
  renderDayList();
  $('#pvEmpty').hidden = true;
  stopPlayer();
  await buildPlaylist(state.dayCuts);
  renderScrub();
  const days = daysWithCuts();
  const i = days.indexOf(date);
  $('#dayPrevDay').disabled = i <= 0;
  $('#dayNextDay').disabled = i < 0 || i >= days.length - 1;
  if (play.items.length) {
    await showClip(0, 0, false);
  } else {
    $('#pvEmpty').hidden = false;
    paintProgress();
  }
  paintPlayBtn();
  renderCrumbs();
}

function closeDay() {
  stopPlayer();
  state.day = null;
  state.dayCuts = [];
}

async function stepDay(dir) {
  const days = daysWithCuts();
  const i = days.indexOf(state.day);
  const next = days[i + dir];
  if (!next) return;
  await openDay(next);
}

function markActiveClip() {
  const cur = play.items[play.idx]?.cut.id;
  $$('#dayList .clip-row').forEach((el) => {
    el.classList.toggle('now', el.dataset.id === cur);
  });
}

function renderDayList() {
  const list = $('#dayList');
  list.innerHTML = '';
  if (!state.dayCuts.length) {
    list.innerHTML = '<div class="empty">この日のカットはありません。</div>';
    return;
  }
  for (const c of state.dayCuts) {
    const row = document.createElement('div');
    row.className = `clip-row${c.hidden ? ' off' : ''}`;
    row.dataset.id = c.id;
    const t = fmtTime(c.takenAt, c.tzOffset);
    const shownMs = play.items.find((it) => it.cut.id === c.id)?.dur
      ?? (c.kind === 'photo' ? clipMs() : Math.min(clipMs(), Number(c.durationMs) || clipMs()));
    const len = `${(shownMs / 1000).toFixed(1)}秒`;
    row.innerHTML = `
      <span class="tc">${t}</span>
      <span class="thumb">${c.thumbUrl ? `<img loading="lazy" src="${c.thumbUrl}" alt="" />` : ''}</span>
      <span class="meta">
        <span class="n">${c.note ? escapeHtml(c.note) : escapeHtml(c.author || '')}</span>
        <span class="k">${len}${c.hidden ? ' · 非表示' : ''}</span>
      </span>`;
    // 行を押すと、その位置から続きを流す
    const jump = document.createElement('button');
    jump.type = 'button';
    jump.className = 'clip-hit';
    jump.setAttribute('aria-label', `${t} から再生する`);
    jump.addEventListener('click', async () => {
      if (c.hidden) { toast('非表示のクリップです。目のアイコンで表示に戻せます'); return; }
      const i = play.items.findIndex((it) => it.cut.id === c.id);
      if (i >= 0) await showClip(i, 0, true);
    });
    // コメントのしるし。押すと、そのクリップのコメントを読み書きできる。
    const cm = document.createElement('button');
    cm.type = 'button';
    cm.className = 'clip-comment icon-btn';
    cm.setAttribute('aria-label', `${t} のコメント`);
    cm.innerHTML = `<svg class="ic sm"><use href="#ic-comment"/></svg>${c.commentCount ? `<span class="n">${c.commentCount}</span>` : ''}`;
    cm.addEventListener('click', (ev) => { ev.stopPropagation(); openComments(c); });
    // 目のしるしで、出す・出さないを切り替える
    const eye = document.createElement('button');
    eye.type = 'button';
    eye.className = 'clip-eye icon-btn';
    eye.setAttribute('aria-label', c.hidden ? `${t} を表示に戻す` : `${t} を非表示にする`);
    eye.setAttribute('aria-pressed', String(!!c.hidden));
    eye.innerHTML = `<svg class="ic sm"><use href="#ic-${c.hidden ? 'eye-off' : 'eye'}"/></svg>`;
    eye.addEventListener('click', (ev) => { ev.stopPropagation(); toggleHidden(c); });
    // 情報のしるしで、そのカットの詳しい画面をひらく
    const info = document.createElement('button');
    info.type = 'button';
    info.className = 'clip-info mini';
    info.setAttribute('aria-label', `${t} の詳細`);
    info.textContent = '詳細';
    info.addEventListener('click', (ev) => { ev.stopPropagation(); openDetail(c.id, 'day'); });
    row.append(jump, cm, eye, info);
    list.appendChild(row);
  }
  markActiveClip();
}

// 非表示は残る状態なので、サーバへ預ける（同じログの人にも同じ見え方になる）
async function toggleHidden(cut) {
  const next = !cut.hidden;
  try {
    await api(`/cuts/${cut.id}`, { method: 'PATCH', body: JSON.stringify({ hidden: next }) });
  } catch (err) {
    toast(err.message);
    return;
  }
  cut.hidden = next;
  const inAll = state.cuts.find((c) => c.id === cut.id);
  if (inAll) inAll.hidden = next;
  toast(next ? '非表示にしました' : '表示に戻しました');
  // 出すものが変わったので、通しの時間軸を作り直す
  const keepId = play.items[play.idx]?.cut.id;
  const wasPlaying = play.playing;
  play.playing = false;
  cancelAnimationFrame(play.raf);
  await buildPlaylist(state.dayCuts);
  renderScrub();
  renderDayList();
  if (!play.items.length) {
    stopPlayer();
    $('#pvEmpty').hidden = false;
    paintProgress();
    paintPlayBtn();
    return;
  }
  $('#pvEmpty').hidden = true;
  const back = play.items.findIndex((it) => it.cut.id === keepId);
  await showClip(back >= 0 ? back : 0, 0, wasPlaying);
}

// ── つないだ再生 ────────────────────────────────────────
// その日のクリップを、1本の動画のように続けて出す。
// 作り直し（エンコード）はしない。<video> を2つ用意し、片方を出している間に
// もう片方へ次を読ませておいて、切れ目で入れ替える。写真は決めた秒数だけ出す。
const play = {
  items: [],        // [{ cut, start, dur }] 通しの時間軸に並べたもの
  total: 0,
  idx: -1,
  playing: false,
  muted: false,
  raf: null,
  photoAt: 0,       // 写真を出し始めた時刻（performance.now）
  photoDone: 0,     // 写真をすでに出した長さ（止めたぶんを足していく）
  front: 'A',       // いま前に出している <video>
};

const CLIP_SECONDS_DEFAULT = 2;
const vidEl = (k) => $(k === 'A' ? '#pvA' : '#pvB');
const frontEl = () => vidEl(play.front);
const backEl = () => vidEl(play.front === 'A' ? 'B' : 'A');
// 1クリップの長さ。写真も動画も同じだけ出す。ログごとに変えられる。
const clipMs = () => (Number(state.log?.cut_seconds) || CLIP_SECONDS_DEFAULT) * 1000;

const fmtClock = (ms) => {
  const t = Math.max(0, Math.round(ms / 1000));
  return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, '0')}`;
};

// 長さの分からない動画があると、通しの時間軸が作れない。
// 見えないところで頭出しだけ読ませて、実際の長さを測る。
async function measureDuration(url) {
  return new Promise((resolve) => {
    const v = document.createElement('video');
    v.preload = 'metadata';
    v.muted = true;
    const done = (ms) => { v.removeAttribute('src'); v.load?.(); resolve(ms); };
    const timer = setTimeout(() => done(0), 4000);
    v.addEventListener('loadedmetadata', () => {
      clearTimeout(timer);
      done(Number.isFinite(v.duration) ? Math.round(v.duration * 1000) : 0);
    }, { once: true });
    v.addEventListener('error', () => { clearTimeout(timer); done(0); }, { once: true });
    v.src = url;
  });
}

// 通しの時間軸を作る。どのクリップも同じ長さで並べる。
// 動画がその長さより短いときだけ、実際の長さに合わせる（黒いままにしないため）。
async function buildPlaylist(cuts) {
  const use = cuts.filter((c) => !c.hidden);
  const unit = clipMs();
  const items = [];
  let at = 0;
  for (const c of use) {
    let dur = unit;
    if (c.kind !== 'photo') {
      let real = Number(c.durationMs) || 0;
      if (!real) real = await measureDuration(c.url);
      if (real) dur = Math.min(unit, real);
    }
    items.push({ cut: c, start: at, dur });
    at += dur;
  }
  play.items = items;
  play.total = at;
}

function renderScrub() {
  const segs = $('#pvSegs');
  segs.innerHTML = '';
  if (!play.total) return;
  // クリップの切れ目を細い隙間で見せる。1本に見えつつ、区切りも分かるようにする。
  for (const it of play.items) {
    const seg = document.createElement('i');
    seg.style.width = `${(it.dur / play.total) * 100}%`;
    segs.appendChild(seg);
  }
  $('#pvScrub').setAttribute('aria-valuemax', String(Math.round(play.total / 1000)));
}

// いま通しで何ミリ秒めか
function currentGlobal() {
  if (play.idx < 0 || !play.items[play.idx]) return 0;
  const it = play.items[play.idx];
  if (it.cut.kind === 'photo') {
    const run = play.playing ? performance.now() - play.photoAt : 0;
    return it.start + Math.min(it.dur, play.photoDone + run);
  }
  const v = frontEl();
  const cur = Number.isFinite(v.currentTime) ? v.currentTime * 1000 : 0;
  return it.start + Math.min(it.dur, cur);
}

function paintProgress() {
  const g = currentGlobal();
  const pct = play.total ? (g / play.total) * 100 : 0;
  $('#pvHead').style.left = `${Math.max(0, Math.min(100, pct))}%`;
  $('#pvClock').textContent = `${fmtClock(g)} / ${fmtClock(play.total)}`;
  $('#pvScrub').setAttribute('aria-valuenow', String(Math.round(g / 1000)));
  const it = play.items[play.idx];
  // 左＝ログの題／中央＝メモ／右＝時刻。保存する動画と同じ並びにする。
  $('#ovLog').textContent = it ? (state.log?.name || '') : '';
  $('#ovNote').textContent = it ? (it.cut.note || '') : '';
  $('#ovTime').textContent = it ? fmtTime(it.cut.takenAt, it.cut.tzOffset) : '';
  $('#pvBadge').textContent = it ? `${play.idx + 1} / ${play.items.length}` : '';
  markActiveClip();
}

function loop() {
  cancelAnimationFrame(play.raf);
  const step = () => {
    paintProgress();
    const it = play.items[play.idx];
    if (it && play.playing) {
      if (it.cut.kind === 'photo') {
        // 写真は <video> の ended が来ないので、自分で終わりを見張る
        const run = play.photoDone + (performance.now() - play.photoAt);
        if (run >= it.dur) { nextClip(true); return; }
      } else if (frontEl().currentTime * 1000 >= it.dur - 30) {
        // 長い動画でも、決めた秒数で次へ送る
        nextClip(true); return;
      }
    }
    if (play.playing) play.raf = requestAnimationFrame(step);
  };
  play.raf = requestAnimationFrame(step);
}

// 次のクリップを、裏の <video> に先に読ませておく（切れ目を短くするため）
function preload(i) {
  const nx = play.items[i + 1];
  if (!nx || nx.cut.kind === 'photo') return;
  const b = backEl();
  if (b.dataset.cutId !== nx.cut.id) {
    b.dataset.cutId = nx.cut.id;
    b.src = nx.cut.url;
    b.muted = true;
    b.load();
  }
}

async function showClip(i, offsetMs = 0, autoplay = play.playing) {
  const it = play.items[i];
  if (!it) return;
  play.idx = i;
  const img = $('#pvImg');
  const a = $('#pvA'); const b = $('#pvB');

  if (it.cut.kind === 'photo') {
    a.pause(); b.pause();
    a.classList.remove('on'); b.classList.remove('on');
    img.src = it.cut.url;
    img.hidden = false;
    play.photoDone = Math.min(offsetMs, it.dur);
    play.photoAt = performance.now();
  } else {
    img.hidden = true;
    // 裏に読み込み済みならそれを前に出す。無ければ前のものを差し替える。
    let el = frontEl();
    if (backEl().dataset.cutId === it.cut.id) {
      play.front = play.front === 'A' ? 'B' : 'A';
      el = frontEl();
    } else if (el.dataset.cutId !== it.cut.id) {
      el.dataset.cutId = it.cut.id;
      el.src = it.cut.url;
      el.load();
    }
    const other = backEl();
    other.pause();
    other.classList.remove('on');
    el.classList.add('on');
    el.muted = play.muted;
    try {
      if (el.readyState < 1) await new Promise((r) => el.addEventListener('loadedmetadata', r, { once: true }));
      el.currentTime = Math.min(offsetMs, Math.max(0, it.dur - 60)) / 1000;
    } catch { /* 読めないときはそのまま先へ進む */ }
    if (autoplay) { try { await el.play(); } catch { /* 端末が止めたら手で押してもらう */ } }
  }
  preload(i);
  renderDayList();
  paintProgress();
  if (autoplay) { play.playing = true; loop(); }
  paintPlayBtn();
}

function paintPlayBtn() {
  const use = play.playing ? '#ic-pause' : '#ic-play';
  $('#pvPlay').querySelector('use').setAttribute('href', use);
  $('#pvPlay').setAttribute('aria-label', play.playing ? '一時停止' : '再生');
  $('#player').classList.toggle('playing', play.playing);
}

async function playFrom(globalMs) {
  if (!play.items.length) return;
  const ms = Math.max(0, Math.min(globalMs, play.total - 1));
  let i = play.items.findIndex((it) => ms < it.start + it.dur);
  if (i < 0) i = play.items.length - 1;
  await showClip(i, ms - play.items[i].start, play.playing);
}

async function togglePlay() {
  if (!play.items.length) return;
  if (play.playing) {
    play.playing = false;
    cancelAnimationFrame(play.raf);
    const it = play.items[play.idx];
    if (it?.cut.kind === 'photo') play.photoDone += performance.now() - play.photoAt;
    else frontEl().pause();
    paintPlayBtn();
    return;
  }
  play.playing = true;
  if (play.idx < 0) { await showClip(0, 0, true); return; }
  const it = play.items[play.idx];
  if (it.cut.kind === 'photo') {
    if (play.photoDone >= it.dur) play.photoDone = 0;
    play.photoAt = performance.now();
  } else {
    try { await frontEl().play(); } catch { /* 端末が止めたときは何もしない */ }
  }
  paintPlayBtn();
  loop();
}

async function nextClip(auto = false) {
  if (play.idx + 1 >= play.items.length) {
    // 最後まで来たら止めて、頭に戻しておく
    play.playing = false;
    cancelAnimationFrame(play.raf);
    if (auto) { await showClip(play.items.length - 1, play.items[play.items.length - 1].dur, false); }
    play.playing = false;
    paintPlayBtn();
    paintProgress();
    return;
  }
  await showClip(play.idx + 1, 0, play.playing || auto);
}

async function prevClip() {
  // 頭出しの作法：少し進んでいたらそのクリップの先頭へ、すぐなら1つ前へ
  const it = play.items[play.idx];
  const into = it ? currentGlobal() - it.start : 0;
  if (into > 1500 || play.idx <= 0) await showClip(Math.max(0, play.idx), 0, play.playing);
  else await showClip(play.idx - 1, 0, play.playing);
}

function stopPlayer() {
  play.playing = false;
  cancelAnimationFrame(play.raf);
  for (const k of ['A', 'B']) {
    const v = vidEl(k);
    v.pause();
    v.removeAttribute('src');
    delete v.dataset.cutId;
    v.load();
    v.classList.remove('on');
  }
  $('#pvImg').hidden = true;
  $('#pvImg').removeAttribute('src');
  play.items = []; play.total = 0; play.idx = -1;
}

function scrubToEvent(ev) {
  const r = $('#pvScrub').getBoundingClientRect();
  const x = (ev.touches?.[0]?.clientX ?? ev.clientX) - r.left;
  return (Math.max(0, Math.min(r.width, x)) / r.width) * play.total;
}

// ── 撮影 ────────────────────────────────────────────────
function updateCapDest() {
  const l = state.logs.find((x) => x.id === state.captureLogId);
  $('#capDest').textContent = l ? `記録先 ${l.name}` : '';
}

// この撮影の行き先を選ぶ。既定の記録先の設定は変えない。
function openDestChooser() {
  const dlg = $('#destDialog');
  $('#destList').innerHTML = state.logs.map((l) => `
    <button type="button" class="move-row dest-row${l.id === state.captureLogId ? ' active' : ''}" data-id="${l.id}">
      <strong>${escapeHtml(l.name)}</strong>
      ${l.kind === 'private' ? '<span class="muted small"><svg class="ic sm"><use href="#ic-lock"/></svg>非公開</span>' : ''}
    </button>`).join('');
  $$('#destList .dest-row').forEach((b) => b.addEventListener('click', () => {
    state.captureLogId = b.dataset.id;
    updateCapDest();
    dlg.close();
  }));
  dlg.showModal();
}

let stream = null;
let recorder = null;
let chunks = [];
let pending = null;
let facing = 'environment';

// 撮った場所。許してもらえたときだけ入る。断られても撮影は止めない。
let place = null;
function askPlace() {
  place = null;
  if (!navigator.geolocation) return;
  navigator.geolocation.getCurrentPosition(
    (pos) => {
      place = { lat: pos.coords.latitude, lon: pos.coords.longitude, accuracy: pos.coords.accuracy };
    },
    () => { place = null; },
    { enableHighAccuracy: true, timeout: 8000, maximumAge: 30000 },
  );
}

async function openCapture() {
  const dlg = $('#captureDialog');
  dlg.showModal();
  askPlace();
  $('#capTimer').textContent = `${state.log?.cut_seconds || 2}秒`;
  state.captureLogId = state.logId;
  updateCapDest();
  await startStream();
}

async function startStream() {
  stopStream();
  try {
    stream = await navigator.mediaDevices.getUserMedia({
      // 横向きを主にするので、横長で要求する
      video: { facingMode: facing, width: { ideal: 1920 }, height: { ideal: 1080 } },
      audio: true,
    });
    $('#preview').srcObject = stream;
    $('#preview').hidden = false;
    $('#playback').hidden = true;
    setupZoom();
  } catch (err) {
    toast(`カメラを使えませんでした。ブラウザのカメラの許可を確認してください（${err.message}）`, 5000);
  }
}

function stopStream() {
  if (stream) stream.getTracks().forEach((t) => t.stop());
  stream = null;
  zoom.track = null;
}

// ── ズーム ──────────────────────────────────────────────
// カメラ自体が寄れる端末では、その仕組みを使う（画がぼけない）。
// 使えない端末では、映像を拡大して見せる形にする。
const zoom = { track: null, min: 1, max: 1, step: 0.1, value: 1, native: false };

function setupZoom() {
  const track = stream?.getVideoTracks?.()[0] || null;
  zoom.track = track;
  const caps = track?.getCapabilities?.() || {};
  if (caps.zoom && caps.zoom.max > caps.zoom.min) {
    zoom.native = true;
    zoom.min = caps.zoom.min;
    zoom.max = caps.zoom.max;
    zoom.step = caps.zoom.step || (zoom.max - zoom.min) / 20 || 0.1;
    zoom.value = track.getSettings?.().zoom ?? zoom.min;
  } else {
    // 端末が寄れないときは、映した後の絵を切り出して寄せる
    zoom.native = false;
    zoom.min = 1;
    zoom.max = 4;
    zoom.step = 0.1;
    zoom.value = 1;
  }
  const sl = $('#zoomRange');
  sl.min = String(zoom.min);
  sl.max = String(zoom.max);
  sl.step = String(zoom.step);
  sl.value = String(zoom.value);
  paintZoom();
  renderZoomStops();
}

function renderZoomStops() {
  // よく使う倍率をすぐ押せるようにする（端末が出せる範囲に収まるものだけ）
  const box = $('#zoomStops');
  box.innerHTML = '';
  const wants = zoom.native ? [zoom.min, zoom.min * 2, zoom.min * 3, zoom.max] : [1, 2, 3, 4];
  const seen = new Set();
  for (const w of wants) {
    const v = Math.min(zoom.max, Math.max(zoom.min, w));
    const key = v.toFixed(1);
    if (seen.has(key)) continue;
    seen.add(key);
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'chip zoom-stop';
    b.dataset.zoom = String(v);
    b.textContent = `${zoomLabel(v)}×`;
    b.addEventListener('click', () => applyZoom(v));
    box.appendChild(b);
  }
  paintZoom();
}

// 端末が寄れる範囲は 1 から始まらないことがあるので、いちばん引いた状態を1.0として見せる
const zoomLabel = (v) => (Math.round((v / zoom.min) * 10) / 10).toFixed(1).replace(/\.0$/, '');

async function applyZoom(v) {
  const next = Math.min(zoom.max, Math.max(zoom.min, Number(v) || zoom.min));
  zoom.value = next;
  $('#zoomRange').value = String(next);
  if (zoom.native && zoom.track) {
    try {
      await zoom.track.applyConstraints({ advanced: [{ zoom: next }] });
    } catch { /* 受け付けない端末では、映像側で寄せる */ }
  }
  paintZoom();
}

function paintZoom() {
  const v = zoom.value;
  $('#zoomNow').textContent = `${zoomLabel(v)}×`;
  // 端末が寄れないときだけ、映像そのものを拡大する
  $('#preview').style.transform = zoom.native ? '' : `scale(${v})`;
  $$('.zoom-stop').forEach((b) => {
    b.classList.toggle('active', Math.abs(Number(b.dataset.zoom) - v) < (zoom.step || 0.1) / 2);
  });
  $('#zoomWrap').hidden = zoom.max <= zoom.min;
}

function closeCapture() {
  stopStream();
  pending = null;
  $('#reviewBar').hidden = true;
  $('#playback').hidden = true;
  $('#preview').hidden = false;
  $('#captureDialog').close();
}

// 撮るのは動画だけ。決めた秒数で自動的に止まる。
async function shoot() {
  if (!stream) return;
  const seconds = state.log?.cut_seconds || 2;
  const mime = ['video/mp4;codecs=h264,aac', 'video/webm;codecs=vp9,opus', 'video/webm']
    .find((m) => MediaRecorder.isTypeSupported(m)) || '';
  chunks = [];
  recorder = new MediaRecorder(stream, mime ? { mimeType: mime } : undefined);
  recorder.ondataavailable = (e) => { if (e.data.size) chunks.push(e.data); };
  recorder.onstop = () => {
    const blob = new Blob(chunks, { type: recorder.mimeType || 'video/webm' });
    pending = { blob, kind: 'video', durationMs: seconds * 1000, mime: blob.type };
    showReview(URL.createObjectURL(blob), 'video');
  };
  recorder.start();
  const btn = $('#shootBtn');
  btn.classList.add('recording');
  let left = seconds;
  $('#capTimer').textContent = `${left}`;
  const iv = setInterval(() => {
    left -= 1;
    $('#capTimer').textContent = `${Math.max(0, left)}`;
    if (left <= 0) {
      clearInterval(iv);
      btn.classList.remove('recording');
      if (recorder.state !== 'inactive') recorder.stop();
      $('#capTimer').textContent = `${seconds}秒`;
    }
  }, 1000);
}

function showReview(url, kind) {
  $('#reviewBar').hidden = false;
  if (kind === 'photo') {
    $('#preview').hidden = true;
    $('#playback').hidden = false;
    $('#playback').src = url;
  } else {
    $('#preview').hidden = true;
    $('#playback').hidden = false;
    $('#playback').src = url;
  }
}

async function saveCut() {
  if (!pending) return;
  const fd = new FormData();
  const ext = pending.kind === 'photo' ? 'jpg' : (pending.mime.includes('mp4') ? 'mp4' : 'webm');
  fd.append('file', pending.blob, `cut.${ext}`);
  fd.append('meta', JSON.stringify({
    kind: pending.kind,
    durationMs: pending.durationMs,
    takenAt: new Date().toISOString(),
    tzOffset: new Date().getTimezoneOffset(),
    facing,
    source: pending.source || 'camera',
    note: $('#noteInput').value.trim() || null,
    // 場所は分かったときだけ添える
    lat: place?.lat ?? null,
    lon: place?.lon ?? null,
    accuracy: place?.accuracy ?? null,
  }));
  const destId = state.captureLogId || state.logId;
  const destName = state.logs.find((l) => l.id === destId)?.name || '';
  toast('カットを保存しています…');
  await api(`/logs/${destId}/cuts`, { method: 'POST', body: fd });
  $('#noteInput').value = '';
  closeCapture();
  toast(`「${destName}」へ保存しました`);
  await loadCuts();
}

// ── 書き出し・共有・まとめ ─────────────────────────────
function openPicker(kind, presetIds) {
  const dlg = $('#exportDialog');
  const ids = presetIds || [...state.selected];
  if (!ids.length) { toast('この日にはカットがありません'); return; }
  const titles = { export: '元のファイルの書き出し', share: '共有リンクの作成', render: '動画を保存' };
  const goLabels = { export: '書き出し', share: '作成', render: '保存' };
  $('#exportTitle').textContent = titles[kind];
  $('#exportGo').textContent = goLabels[kind];
  $('#exportOptions').hidden = kind !== 'export';
  $('#shareOptions').hidden = kind !== 'share';
  $('#renderOptions').hidden = kind !== 'render';
  const list = $('#exportList');
  list.innerHTML = '';
  for (const cid of ids) {
    const c = state.cuts.find((x) => x.id === cid);
    if (!c) continue;
    const row = document.createElement('label');
    row.className = `pick-row${c.hidden ? ' off' : ''}`;
    row.innerHTML = `<input type="checkbox" ${c.hidden ? '' : 'checked'} value="${c.id}" />
      ${c.thumbUrl ? `<img src="${c.thumbUrl}" alt="" />` : '<span></span>'}
      <span class="when">${c.localDate} ${fmtTime(c.takenAt, c.tzOffset)}</span>
      <span class="memo">${escapeHtml(c.note || c.author || '')}${c.hidden ? '（非表示）' : ''}</span>`;
    list.appendChild(row);
  }
  $('#pickCount').textContent = `${$$('#exportList input:checked').length} / ${ids.length} 件`;
  if (kind === 'render') {
    $('#advBox').hidden = true;
    $('#advToggle').setAttribute('aria-expanded', 'false');
    $('#advToggle').textContent = '詳細設定を表示';
    const withNote = ids.map((cid) => state.cuts.find((c) => c.id === cid)).find((c) => c && c.note);
    state.pvNoteSample = withNote ? withNote.note.slice(0, 20) : 'ひとこと';
    fillStyleForm(state.renderStyle);
  }
  dlg.returnValue = '';
  dlg.showModal();
  // 実行の判定はcloseイベントに頼らず、フォームのsubmitで拾う（環境によりcloseが発火しないことがある）
  const form = dlg.querySelector('form');
  form.onsubmit = (ev) => {
    if (ev.submitter?.value !== 'ok') return;
    const chosen = $$('#exportList input:checked').map((i) => i.value);
    if (!chosen.length) { toast('カットを1つ以上選んでください'); return; }
    setTimeout(async () => {
      if (kind === 'export') await doExport(chosen);
      if (kind === 'share') await doShare(chosen);
      if (kind === 'render') await doRender(chosen);
    }, 0);
  };
}

async function doExport(cutIds) {
  toast('書き出しています…');
  const res = await fetch(`/api/logs/${state.logId}/export`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ cutIds, includeMetadata: $('#withMeta').checked }),
  });
  if (!res.ok) { toast('書き出せませんでした。もう一度お試しください'); return; }
  const blob = await res.blob();
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `cutlog_${Date.now()}.zip`;
  a.click();
  toast('書き出しました');
}

async function doShare(cutIds) {
  const { share } = await api(`/logs/${state.logId}/shares`, {
    method: 'POST',
    body: JSON.stringify({
      cutIds,
      title: $('#shareTitle').value || '共有',
      expiresAt: $('#shareExpires').value || null,
      password: $('#sharePassword').value || null,
      allowDownload: $('#allowDownload').checked,
    }),
  });
  const copied = await navigator.clipboard?.writeText(share.url).then(() => true).catch(() => false);
  toast(copied ? '共有リンクを作り、コピーしました' : `共有リンクを作りました: ${share.url}`, 6000);
}

async function doRender(cutIds) {
  const style = collectStyle();
  const { jobId, style: saved } = await api(`/logs/${state.logId}/renders`, {
    method: 'POST',
    body: JSON.stringify({ cutIds, style, label: state.day || 'まとめ' }),
  });
  if (saved) state.renderStyle = saved;
  toast('動画を作っています…');
  const poll = setInterval(async () => {
    const { job } = await api(`/jobs/${jobId}`);
    if (job.status === 'done') {
      clearInterval(poll);
      toast('動画ができました。ダウンロードを始めます');
      window.location.href = job.result.url;
    } else if (job.status === 'error') {
      clearInterval(poll);
      toast(`作れませんでした: ${job.message}`, 6000);
    }
  }, 2000);
}

// ── カットの付け替え ────────────────────────────────────
function cutLabel(cutId) {
  const c = state.cuts.find((x) => x.id === cutId);
  return c ? `${fmtTime(c.takenAt, c.tzOffset)} のカット` : cutId;
}

function closeCutDetail() {
  if ($('#cutDialog').open) { $('#cutDialog').close(); return; }
  state.detailCut = null;
  state.detailFrom = '';
  $('#detail').innerHTML = '';
  renderDayList();
  renderCrumbs();
}

// カットを直したり消したりしたあと、その日の中身を取り直して並べ直す
async function reloadDay() {
  await loadCuts();
  if (!state.day) return;
  const keepId = play.items[play.idx]?.cut.id;
  state.dayCuts = state.cuts
    .filter((c) => c.localDate === state.day)
    .sort((a, b) => (a.takenAt < b.takenAt ? -1 : 1));
  play.playing = false;
  cancelAnimationFrame(play.raf);
  await buildPlaylist(state.dayCuts);
  renderScrub();
  renderDayList();
  if (!play.items.length) { stopPlayer(); $('#pvEmpty').hidden = false; paintProgress(); paintPlayBtn(); return; }
  $('#pvEmpty').hidden = true;
  const back = play.items.findIndex((it) => it.cut.id === keepId);
  await showClip(back >= 0 ? back : 0, 0, false);
  paintPlayBtn();
}

function openMove(cutIds, fromLogId, { single = false } = {}) {
  const targets = state.logs.filter((l) => l.id !== fromLogId);
  if (!targets.length) { toast('移動先のログがありません。ログ一覧で作成するか、参加してください'); return; }
  const dlg = $('#moveDialog');
  $('#moveNote').hidden = false;
  $('#moveList').hidden = false;
  $('#moveGo').hidden = false;
  $('#moveCancel').textContent = 'キャンセル';
  const result = $('#moveResult');
  result.hidden = true;
  result.innerHTML = '';
  $('#moveList').innerHTML = targets.map((l, i) => `
    <label class="move-row">
      <input type="radio" name="moveTo" value="${l.id}" ${i === 0 ? 'checked' : ''} />
      <span class="name">${escapeHtml(l.name)}</span>
      ${l.kind === 'private' ? '<span class="muted small"><svg class="ic sm"><use href="#ic-lock"/></svg>非公開</span>' : ''}
    </label>`).join('');
  dlg.showModal();
  const form = dlg.querySelector('form');
  form.onsubmit = (ev) => {
    if (ev.submitter?.value !== 'ok') return;
    ev.preventDefault();
    const to = form.querySelector('input[name=moveTo]:checked')?.value;
    if (!to) { toast('移動先のログを選んでください'); return; }
    const toName = state.logs.find((l) => l.id === to)?.name || '';
    (async () => {
      try {
        if (single) {
          await api(`/cuts/${cutIds[0]}/move`, { method: 'POST', body: JSON.stringify({ logId: to }) });
          dlg.close();
          toast(`「${toName}」へ移しました`);
          closeCutDetail();
          await loadCuts();
          return;
        }
        const { moved, skipped } = await api(`/logs/${to}/cuts/move`, {
          method: 'POST', body: JSON.stringify({ cutIds }),
        });
        const lines = skipped.map((s) => `
          <div class="move-skip"><span class="when">${escapeHtml(cutLabel(s.cutId))}</span><span>${escapeHtml(s.reason)}</span></div>`);
        moved.forEach((cid) => state.selected.delete(cid));
        await loadCuts();
        if (!skipped.length) {
          dlg.close();
          toast(`${moved.length}件を「${toName}」へ移しました`);
          return;
        }
        $('#moveNote').hidden = true;
        $('#moveList').hidden = true;
        $('#moveGo').hidden = true;
        $('#moveCancel').textContent = '閉じる';
        result.hidden = false;
        result.innerHTML = `
          <p>${moved.length ? `${moved.length}件を「${escapeHtml(toName)}」へ移しました。` : ''}${skipped.length}件は移せませんでした。</p>
          ${lines.join('')}`;
      } catch (err) {
        toast(err.message, 5000);
      }
    })();
  };
}

// ── まとめ動画の見た目 ──────────────────────────────────
const POS_LABELS = { tl: '左上', tc: '上中央', tr: '右上', bl: '左下', bc: '下中央', br: '右下' };
const TIME_FORMAT_KEYS = ['HH:mm', 'HH:mm:ss', 'M/D HH:mm', 'YYYY-MM-DD HH:mm'];
const SIZE_PRESETS = { portrait: [720, 1280], square: [1080, 1080], landscape: [1280, 720] };
const FALLBACK_STYLE = {
  size: 'portrait', width: 720, height: 1280, fit: 'contain', background: '#000000',
  fps: 30, perCutMs: 0, photoMs: 2000, order: 'time',
  time: { show: true, format: 'HH:mm', position: 'br', fontSize: 36, color: '#FFFFFF', box: true, boxColor: '#000000', boxOpacity: 0.4 },
  note: { show: false, position: 'bc', fontSize: 28, color: '#FFFFFF', box: true, boxColor: '#000000', boxOpacity: 0.4 },
  title: { show: false, text: '', seconds: 2, fontSize: 64, color: '#FFFFFF', background: '#000000' },
};

function sampleTime(fmt, d = new Date()) {
  const p = (n) => String(n).padStart(2, '0');
  const hm = `${p(d.getHours())}:${p(d.getMinutes())}`;
  if (fmt === 'HH:mm:ss') return `${hm}:${p(d.getSeconds())}`;
  if (fmt === 'M/D HH:mm') return `${d.getMonth() + 1}/${d.getDate()} ${hm}`;
  if (fmt === 'YYYY-MM-DD HH:mm') return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${hm}`;
  return hm;
}

function initStyleForm() {
  $('#stTimeFormat').innerHTML = TIME_FORMAT_KEYS.map((k) => `<option value="${k}">${sampleTime(k)}</option>`).join('');
  const pos = Object.entries(POS_LABELS).map(([v, t]) => `<option value="${v}">${t}</option>`).join('');
  $('#stTimePos').innerHTML = pos;
  $('#stNotePos').innerHTML = pos;
}

function fillStyleForm(style) {
  const s = style || FALLBACK_STYLE;
  $('#stSize').value = s.size;
  $('#stW').value = s.width;
  $('#stH').value = s.height;
  $('#stFit').value = s.fit;
  $('#stBg').value = s.background;
  $('#stFps').value = s.fps;
  $('#stTrim').checked = s.perCutMs > 0;
  $('#stPer').value = s.perCutMs > 0 ? s.perCutMs / 1000 : 3;
  $('#stPhoto').value = s.photoMs / 1000;
  $('#stOrder').value = s.order;
  $('#stTimeShow').checked = s.time.show;
  $('#stTimeFormat').value = s.time.format;
  $('#stTimePos').value = s.time.position;
  $('#stTimeSize').value = s.time.fontSize;
  $('#stTimeColor').value = s.time.color;
  $('#stTimeBox').checked = s.time.box;
  $('#stTimeBoxColor').value = s.time.boxColor;
  $('#stTimeBoxOp').value = s.time.boxOpacity;
  $('#stNoteShow').checked = s.note.show;
  $('#stNotePos').value = s.note.position;
  $('#stNoteSize').value = s.note.fontSize;
  $('#stNoteColor').value = s.note.color;
  $('#stNoteBox').checked = s.note.box;
  $('#stNoteBoxColor').value = s.note.boxColor;
  $('#stNoteBoxOp').value = s.note.boxOpacity;
  $('#stTitleShow').checked = s.title.show;
  $('#stTitleText').value = s.title.text;
  $('#stTitleSec').value = s.title.seconds;
  $('#stTitleSize').value = s.title.fontSize;
  $('#stTitleColor').value = s.title.color;
  $('#stTitleBg').value = s.title.background;
  syncStyleFields();
  updateStylePreview();
}

function collectStyle() {
  const size = $('#stSize').value;
  const preset = SIZE_PRESETS[size];
  return {
    size,
    width: preset ? preset[0] : Number($('#stW').value) || 720,
    height: preset ? preset[1] : Number($('#stH').value) || 1280,
    fit: $('#stFit').value,
    background: $('#stBg').value,
    fps: Number($('#stFps').value) || 30,
    perCutMs: $('#stTrim').checked ? Math.round((Number($('#stPer').value) || 3) * 1000) : 0,
    photoMs: Math.round((Number($('#stPhoto').value) || 2) * 1000),
    order: $('#stOrder').value,
    time: {
      show: $('#stTimeShow').checked,
      format: $('#stTimeFormat').value,
      position: $('#stTimePos').value,
      fontSize: Number($('#stTimeSize').value) || 36,
      color: $('#stTimeColor').value,
      box: $('#stTimeBox').checked,
      boxColor: $('#stTimeBoxColor').value,
      boxOpacity: Number($('#stTimeBoxOp').value),
    },
    note: {
      show: $('#stNoteShow').checked,
      position: $('#stNotePos').value,
      fontSize: Number($('#stNoteSize').value) || 28,
      color: $('#stNoteColor').value,
      box: $('#stNoteBox').checked,
      boxColor: $('#stNoteBoxColor').value,
      boxOpacity: Number($('#stNoteBoxOp').value),
    },
    title: {
      show: $('#stTitleShow').checked,
      text: $('#stTitleText').value.slice(0, 60),
      seconds: Number($('#stTitleSec').value) || 2,
      fontSize: Number($('#stTitleSize').value) || 64,
      color: $('#stTitleColor').value,
      background: $('#stTitleBg').value,
    },
  };
}

function syncStyleFields() {
  const custom = $('#stSize').value === 'custom';
  $('#stWLabel').hidden = !custom;
  $('#stHLabel').hidden = !custom;
  $('#stPerLabel').hidden = !$('#stTrim').checked;
  $('#stTimeOpts').hidden = !$('#stTimeShow').checked;
  $('#stNoteOpts').hidden = !$('#stNoteShow').checked;
  $('#stTitleOpts').hidden = !$('#stTitleShow').checked;
}

function hexToRgba(hex, a) {
  const n = parseInt(String(hex).slice(1), 16);
  if (!Number.isFinite(n)) return `rgba(0,0,0,${a})`;
  /* eslint-disable no-bitwise */
  return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`;
  /* eslint-enable no-bitwise */
}

// 位置コード（tl〜br）をプレビューの絶対配置へ写す
function placePvText(el, pos, mx, my) {
  el.style.left = ''; el.style.right = ''; el.style.top = ''; el.style.bottom = ''; el.style.transform = '';
  if (pos[1] === 'l') el.style.left = `${mx}px`;
  else if (pos[1] === 'r') el.style.right = `${mx}px`;
  else { el.style.left = '50%'; el.style.transform = 'translateX(-50%)'; }
  if (pos[0] === 't') el.style.top = `${my}px`; else el.style.bottom = `${my}px`;
}

function styleText(el, text, fontSize, color, box, boxColor, boxOpacity, scale) {
  el.textContent = text;
  el.style.fontSize = `${Math.max(fontSize * scale, 4)}px`;
  el.style.color = color;
  el.style.background = box ? hexToRgba(boxColor, boxOpacity) : 'transparent';
  el.style.padding = box ? `${Math.max(10 * scale, 1)}px` : '0';
}

// 動画を作らずに、指定した比率・位置・文字サイズ・色をそのまま見せる
function updateStylePreview() {
  const s = collectStyle();
  const scale = 230 / Math.max(s.width, s.height);
  const w = Math.round(s.width * scale);
  const h = Math.round(s.height * scale);
  const main = $('#pvMainFrame');
  main.style.width = `${w}px`;
  main.style.height = `${h}px`;
  main.style.background = s.background;
  const base = 24 * scale;
  const t = $('#pvTime');
  t.hidden = !s.time.show;
  if (s.time.show) {
    styleText(t, sampleTime(s.time.format), s.time.fontSize, s.time.color,
      s.time.box, s.time.boxColor, s.time.boxOpacity, scale);
    placePvText(t, s.time.position, base, base);
  }
  const n = $('#pvNote');
  n.hidden = !s.note.show;
  if (s.note.show) {
    styleText(n, state.pvNoteSample || 'ひとこと', s.note.fontSize, s.note.color,
      s.note.box, s.note.boxColor, s.note.boxOpacity, scale);
    // 時刻と同じ辺に置くときは、サーバと同じだけ1段ずらす
    const sameEdge = s.time.show && s.time.position[0] === s.note.position[0];
    placePvText(n, s.note.position, base, sameEdge ? (24 + s.time.fontSize + 28) * scale : base);
  }
  const fig = $('#pvTitleFig');
  fig.hidden = !s.title.show;
  if (s.title.show) {
    const f = $('#pvTitleFrame');
    f.style.width = `${w}px`;
    f.style.height = `${h}px`;
    f.style.background = s.title.background;
    const tt = $('#pvTitleText');
    tt.textContent = s.title.text;
    tt.style.fontSize = `${Math.max(s.title.fontSize * scale, 4)}px`;
    tt.style.color = s.title.color;
  }
}

// ── ログ一覧（最上位の画面） ────────────────────────────
async function openLogs() {
  const { logs } = await api('/logs');
  state.logs = logs;
  renderLogsList();
  showScreen('logs');
}

function renderLogsList() {
  const list = $('#logsList');
  list.innerHTML = '';
  for (const l of state.logs) {
    const row = document.createElement('button');
    row.type = 'button';
    row.className = 'log-row';
    // 左に最後のカットの見本、真ん中に名前と中身、右に「入れる」印。
    const thumb = l.latestThumbUrl
      ? `<img src="${l.latestThumbUrl}" alt="" loading="lazy" />`
      : `<svg class="ic"><use href="#ic-${l.kind === 'private' ? 'lock' : 'film'}"/></svg>`;
    const bits = [`${l.cut_count}カット`];
    if (l.kind === 'private') bits.push('非公開');
    else bits.push(`${l.member_count}人`, l.ownerName || '');
    if (l.latestTakenAt) bits.push(`最後 ${l.latestTakenAt.slice(5, 10).replace('-', '.')}`);
    row.innerHTML = `
      <span class="log-thumb${l.latestThumbUrl ? '' : ' blank'}">${thumb}</span>
      <span class="log-main">
        <span class="log-name">${escapeHtml(l.name)}</span>
        <span class="log-sub">${bits.filter(Boolean).map(escapeHtml).join(' · ')}</span>
      </span>
      <svg class="ic sm log-chev"><use href="#ic-next"/></svg>`;
    row.addEventListener('click', async () => {
      state.logId = l.id; state.selected.clear(); closeDay();
      await loadLog();
      showScreen('log');
    });
    list.appendChild(row);
  }
}

// ── 全カット（ログをまたいだ一覧。写真のアプリのような並び） ──
async function openAllCuts() {
  showScreen('all');
  await loadAllCuts();
}

async function loadAllCuts() {
  const params = new URLSearchParams();
  const q = $('#allSearch').value.trim();
  if (q) params.set('q', q);
  const author = $('#allAuthor').value;
  if (author) params.set('author', author);
  params.set('limit', '300');
  const { cuts } = await api(`/cuts?${params}`);
  state.allCuts = cuts;
  // 絞っていないときの顔ぶれを覚えておく（絞ったあとも選び直せるように）
  if (!q && !author) {
    state.allAuthors = [...new Map(cuts.map((c) => [c.userId, c.author])).entries()]
      .map(([id, name]) => ({ id, name: name || id }));
  }
  renderAll();
}

// いま何で絞っているかを、一覧の上に出す
// いま何で絞っているかを、一覧の上に出す
function fillAuthorOptions() {
  const sel = $('#allAuthor');
  const keep = sel.value;
  sel.innerHTML = '<option value="">全員</option>'
    + state.allAuthors.map((a) => `<option value="${a.id}">${escapeHtml(a.name)}</option>`).join('');
  sel.value = keep;
}

function paintAllFilter() {
  const q = $('#allSearch').value.trim();
  const authorId = $('#allAuthor').value;
  const authorName = state.allAuthors.find((a) => a.id === authorId)?.name || '';
  const bits = [
    q ? `メモ「${q}」` : '',
    authorName ? `${authorName} のぶん` : '',
  ].filter(Boolean);
  $('#allFilterBar').hidden = !bits.length;
  $('#allFilterText').textContent = bits.length ? `${bits.join('　')}　で絞りこみ中` : '';
}

function renderAll() {
  paintAllFilter();
  const body = $('#allBody');
  body.innerHTML = '';
  const shown = state.allCuts;
  if (!shown.length) {
    body.innerHTML = `<div class="empty">${$('#allSearch').value.trim() || $('#allAuthor').value
      ? '条件に合うカットはありません。' : 'まだカットがありません。カメラのタブから撮ってみてください。'}</div>`;
    return;
  }
  // 日付でひとまとまりにして、その中は撮った順に並べる。
  const map = new Map();
  for (const c of shown) {
    if (!map.has(c.localDate)) map.set(c.localDate, []);
    map.get(c.localDate).push(c);
  }
  for (const [date, cuts] of map) {
    const head = document.createElement('div');
    head.className = 'day-head all-day-head';
    head.innerHTML = `<span>${date.replace(/-/g, '.')}</span>`
      + `<span class="muted">${String(cuts.length).padStart(2, '0')} cuts</span>`;
    body.appendChild(head);
    const wrap = document.createElement('div');
    wrap.className = 'photo-grid';
    for (const c of cuts) {
      const cell = document.createElement('div');
      cell.className = 'photo-cell';
      const timeLabel = fmtTime(c.takenAt, c.tzOffset);
      cell.innerHTML = `
        ${c.thumbUrl ? `<img loading="lazy" src="${c.thumbUrl}" alt="" />` : '<span class="ph"></span>'}
        <span class="cap"><span class="t">${timeLabel}</span><span class="lg">${escapeHtml(c.logName || '')}</span></span>`;
      pressable(cell, `${escapeHtml(c.logName || '')} ${timeLabel} のカットを開く`, () => openDetail(c.id, 'all'));
      wrap.appendChild(cell);
    }
    body.appendChild(wrap);
  }
}

// ── 設定（ログ一覧と並ぶ画面） ──────────────────────────
function openSettings() {
  paintMyAvatar();
  const r = state.reminder || {};
  $('#remMode').value = r.mode || 'off';
  $('#remTimes').value = r.times || '';
  $('#remFrom').value = r.from_hour ?? 9;
  $('#remTo').value = r.to_hour ?? 22;
  $('#remPer').value = r.per_day ?? 6;
  updateReminderFields();
  const isIOS = /iP(hone|ad|od)/.test(navigator.userAgent);
  const standalone = window.matchMedia?.('(display-mode: standalone)').matches || navigator.standalone === true;
  $('#pushHint').textContent = !state.config.vapidPublicKey
    ? 'このサーバは通知のキー（VAPID）が未設定です。管理者が .env に設定すると使えます。'
    : (isIOS && !standalone ? 'iPhoneでは、ホーム画面に追加したcutlogからだけ通知が届きます。' : '');
  showScreen('settings');
}

// ── 共有リンクの一覧（開いているログのもの） ────────────
async function openShareLinks() {
  const { shares } = await api(`/logs/${state.logId}/shares`);
  $('#shareList').innerHTML = shares.length ? '' : '<span class="muted small">まだ共有リンクはありません。</span>';
  for (const s of shares) {
    const row = document.createElement('div');
    row.className = 'share-item';
    row.innerHTML = `<div><strong>${escapeHtml(s.title)}</strong>
      <div class="muted small">${s.cutCount}カット ${s.hasPassword ? '・パスワードあり' : ''} ${s.revoked ? '・停止中' : ''}</div></div>`;
    const copy = document.createElement('button');
    copy.className = 'mini';
    copy.innerHTML = '<svg class="ic sm"><use href="#ic-copy"/></svg>コピー';
    copy.addEventListener('click', () => { navigator.clipboard?.writeText(s.url); toast('コピーしました'); });
    const del = document.createElement('button');
    del.className = 'mini';
    del.textContent = '停止';
    del.addEventListener('click', async () => {
      if (!confirm('この共有リンクを停止しますか。リンクを知っている人も開けなくなります。')) return;
      await api(`/shares/${s.id}`, { method: 'DELETE' });
      toast('共有リンクを停止しました');
      openShareLinks();
    });
    row.append(copy, del);
    $('#shareList').appendChild(row);
  }
  const dlg = $('#shareLinksDialog');
  if (!dlg.open) dlg.showModal();
}

function updateReminderFields() {
  const mode = $('#remMode').value;
  $('#remTimes').hidden = mode !== 'times';
  $('#remWindow').hidden = mode !== 'hourly' && mode !== 'random';
  $('#remPerLabel').hidden = mode !== 'random';
}

async function enablePush() {
  if (!state.config.vapidPublicKey) { toast('このサーバは通知の設定がまだ済んでいません。管理者にお問い合わせください'); return; }
  const perm = await Notification.requestPermission();
  if (perm !== 'granted') { toast('通知が許可されませんでした'); return; }
  const reg = await navigator.serviceWorker.ready;
  const sub = await reg.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: urlBase64ToUint8Array(state.config.vapidPublicKey),
  });
  await api('/push/subscribe', { method: 'POST', body: JSON.stringify({ subscription: sub }) });
  toast('通知を許可しました');
}

function urlBase64ToUint8Array(base64String) {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const raw = atob(base64);
  return Uint8Array.from([...raw].map((c) => c.charCodeAt(0)));
}

// ── イベント ────────────────────────────────────────────
// 端末の動画から取り込む（何本でも。行き先は既定の記録先）
$('#allAddInput').addEventListener('change', async (ev) => {
  const files = [...(ev.target.files || [])].filter((f) => f.type.startsWith('video/'));
  ev.target.value = '';
  if (!files.length) { toast('動画を選んでください'); return; }
  const destId = state.defaultLogId || state.privateLogId || state.logId;
  const destName = state.logs.find((l) => l.id === destId)?.name || '';
  toast(`${files.length}本を「${destName}」へ取り込んでいます…`, 6000);
  let done = 0;
  for (const file of files) {
    const fd = new FormData();
    fd.append('file', file, file.name);
    fd.append('meta', JSON.stringify({
      kind: 'video',
      // 端末に入っている撮影日時が分かればそれを使う。分からなければ今にする。
      takenAt: new Date(file.lastModified || Date.now()).toISOString(),
      tzOffset: new Date().getTimezoneOffset(),
      source: 'upload',
    }));
    try {
      // eslint-disable-next-line no-await-in-loop
      await api(`/logs/${destId}/cuts`, { method: 'POST', body: fd });
      done += 1;
    } catch (err) {
      toast(`${file.name}: ${err.message}`, 5000);
    }
  }
  toast(`${done}本を取り込みました`);
  await loadAllCuts();
  if (state.logId === destId) await loadCuts();
});
$$('.tab-item').forEach((b) => b.addEventListener('click', () => selectTab(b.dataset.tab)));
// その日の詳細：書き出し・共有・まとめ動画は、どれもモーダルで中身を選び直してもらう
$('#dayExport').addEventListener('click', () => openPicker('export', dayIds()));
$('#dayShare').addEventListener('click', () => openPicker('share', dayIds()));
$('#dayRender').addEventListener('click', () => openPicker('render', dayIds()));
$('#pickAll').addEventListener('click', () => setPicks(true));
$('#pickNone').addEventListener('click', () => setPicks(false));
$('#exportList').addEventListener('change', updatePickCount);
$('#dayBack').addEventListener('click', () => { closeDay(); showScreen('log'); });
$('#dayPrevDay').addEventListener('click', () => stepDay(-1));
$('#dayNextDay').addEventListener('click', () => stepDay(1));

// つないだ再生の操作
$('#pvPlay').addEventListener('click', togglePlay);
$('#pvTap').addEventListener('click', togglePlay);
$('#pvPrevClip').addEventListener('click', prevClip);
$('#pvNextClip').addEventListener('click', () => nextClip());
$('#pvMute').addEventListener('click', () => {
  play.muted = !play.muted;
  $('#pvA').muted = play.muted; $('#pvB').muted = play.muted;
  $('#pvMute').querySelector('use').setAttribute('href', play.muted ? '#ic-mute' : '#ic-sound');
  $('#pvMute').setAttribute('aria-label', play.muted ? '音を出す' : '音を消す');
});
$('#pvFull').addEventListener('click', () => {
  const st = $('#pvStage');
  if (document.fullscreenElement) document.exitFullscreen();
  else st.requestFullscreen?.().catch(() => toast('この端末では大きく表示できません'));
});
$('#pvScrub').addEventListener('pointerdown', (ev) => {
  if (!play.total) return;
  ev.preventDefault();
  try { $('#pvScrub').setPointerCapture(ev.pointerId); } catch { /* 合成された指の動きでは掴めないことがある */ }
  playFrom(scrubToEvent(ev));
  const move = (e) => playFrom(scrubToEvent(e));
  const up = () => {
    $('#pvScrub').removeEventListener('pointermove', move);
    window.removeEventListener('pointerup', up);
  };
  $('#pvScrub').addEventListener('pointermove', move);
  window.addEventListener('pointerup', up, { once: true });
});
$('#pvScrub').addEventListener('keydown', (ev) => {
  if (!play.total) return;
  const step = 5000;
  if (ev.key === 'ArrowRight') { ev.preventDefault(); playFrom(currentGlobal() + step); }
  if (ev.key === 'ArrowLeft') { ev.preventDefault(); playFrom(currentGlobal() - step); }
  if (ev.key === ' ' || ev.key === 'Enter') { ev.preventDefault(); togglePlay(); }
});
// 動画が終わったら次のクリップへ（つないで1本に見せるための要）
for (const id of ['#pvA', '#pvB']) {
  $(id).addEventListener('ended', () => { if (play.playing) nextClip(true); });
}
$('#renderOptions').addEventListener('input', () => { syncStyleFields(); updateStylePreview(); });

// このログの設定
$('#logSettingsBtn').addEventListener('click', openLogSettings);
$('#logSetBack').addEventListener('click', () => showScreen('log'));
$('#logSetSave').addEventListener('click', saveLogSettings);
$('#logSetTrash').addEventListener('click', showTrash);
$('#logSetCopyInvite').addEventListener('click', () => {
  navigator.clipboard?.writeText($('#logSetInvite').textContent);
  toast('招待コードをコピーしました');
});
$('#logSetRotate').addEventListener('click', async () => {
  if (!confirm('招待コードを再生成しますか。現在のコードでは参加できなくなります。')) return;
  const { inviteCode } = await api(`/logs/${state.logId}/invite/rotate`, { method: 'POST' });
  $('#logSetInvite').textContent = inviteCode;
  await loadLogs();
  toast('再生成しました');
});
initStyleForm();
$('#search').addEventListener('input', debounce(loadCuts, 350));
$('#authorFilter').addEventListener('change', loadCuts);
$('#tagFilter').addEventListener('change', loadCuts);
$('#capDest').addEventListener('click', openDestChooser);
$('#destCancel').addEventListener('click', () => $('#destDialog').close());
$('#closeCapture').addEventListener('click', closeCapture);
$('#flipCam').addEventListener('click', async () => {
  facing = facing === 'environment' ? 'user' : 'environment';
  await startStream();
});
$('#shootBtn').addEventListener('click', shoot);
$('#retakeBtn').addEventListener('click', async () => {
  pending = null; $('#reviewBar').hidden = true; await startStream();
});
$('#saveCutBtn').addEventListener('click', saveCut);
$('#zoomRange').addEventListener('input', (e) => applyZoom(e.target.value));
// 二本指でつまむと寄る・引く
let pinch0 = 0; let pinchZoom0 = 1;
$('#preview').addEventListener('touchstart', (ev) => {
  if (ev.touches.length !== 2) return;
  pinch0 = Math.hypot(ev.touches[0].clientX - ev.touches[1].clientX, ev.touches[0].clientY - ev.touches[1].clientY);
  pinchZoom0 = zoom.value;
}, { passive: true });
$('#preview').addEventListener('touchmove', (ev) => {
  if (ev.touches.length !== 2 || !pinch0) return;
  const d = Math.hypot(ev.touches[0].clientX - ev.touches[1].clientX, ev.touches[0].clientY - ev.touches[1].clientY);
  applyZoom(pinchZoom0 * (d / pinch0));
}, { passive: true });
$('#preview').addEventListener('touchend', () => { pinch0 = 0; }, { passive: true });
$('#fileInput').addEventListener('change', async (e) => {
  const file = e.target.files[0];
  if (!file) return;
  if (!file.type.startsWith('video/')) { toast('動画を選んでください'); e.target.value = ''; return; }
  pending = { blob: file, kind: 'video', durationMs: null, mime: file.type, source: 'upload' };
  showReview(URL.createObjectURL(file), 'video');
});
wireModals();
wireMapDrag();
$('#advToggle').addEventListener('click', () => {
  const box = $('#advBox');
  const open = box.hidden;
  box.hidden = !open;
  $('#advToggle').setAttribute('aria-expanded', String(open));
  $('#advToggle').textContent = open ? '詳細設定を隠す' : '詳細設定を表示';
});
$('#mapListBack').addEventListener('click', () => { state.mapPick = []; showScreen('map'); });
$('#commentSend').addEventListener('click', async () => {
  const body = $('#commentBox').value.trim();
  if (!body || !state.commentCut) return;
  await api(`/cuts/${state.commentCut.id}/comments`, { method: 'POST', body: JSON.stringify({ body }) });
  $('#commentBox').value = '';
  await paintComments();
});
$('#commentBox').addEventListener('keydown', (ev) => {
  if (ev.key === 'Enter') { ev.preventDefault(); $('#commentSend').click(); }
});
// カット一覧の検索は、虫めがねから開くモーダルで行う
$('#avatarInput').addEventListener('change', async (ev) => {
  const file = ev.target.files?.[0];
  ev.target.value = '';
  if (!file) return;
  const fd = new FormData();
  fd.append('file', file, file.name);
  try {
    const { user } = await api('/me/avatar', { method: 'POST', body: fd });
    state.user = user;
    paintMyAvatar();
    toast('アイコン画像を設定しました');
  } catch (err) { toast(err.message, 4000); }
});
$('#avatarClear').addEventListener('click', async () => {
  const { user } = await api('/me/avatar', { method: 'DELETE' });
  state.user = user;
  paintMyAvatar();
  toast('アイコン画像を削除しました');
});
$('#allSearchBtn').addEventListener('click', () => {
  fillAuthorOptions();
  $('#searchDialog').showModal();
  $('#allSearch').focus();
});
$('#searchGo').addEventListener('click', async () => {
  closeModal($('#searchDialog'));
  await loadAllCuts();
  paintAllFilter();
});
$('#searchClear').addEventListener('click', async () => {
  $('#allSearch').value = '';
  $('#allAuthor').value = '';
  closeModal($('#searchDialog'));
  await loadAllCuts();
  paintAllFilter();
});
$('#allSearch').addEventListener('keydown', (ev) => {
  if (ev.key === 'Enter') { ev.preventDefault(); $('#searchGo').click(); }
});
$('#allFilterClear').addEventListener('click', () => $('#searchClear').click());
$('#menuBtn').addEventListener('click', openLogs);
$('#shareLinksBtn').addEventListener('click', openShareLinks);
$('#closeShareLinks').addEventListener('click', () => $('#shareLinksDialog').close());
$('#createLog').addEventListener('click', async () => {
  const name = $('#newLogName').value.trim();
  if (!name) return;
  const { log } = await api('/logs', { method: 'POST', body: JSON.stringify({ name }) });
  state.logId = log.id;
  $('#newLogName').value = '';
  await loadLogs();
  // 作ってすぐ撮れるように、このログを開いた状態でカメラを出す
  // （loadLogs の中で新しいログが読み込まれ、行き先も秒数もそこに揃う）
  openCapture();
});
$('#joinLog').addEventListener('click', async () => {
  const code = $('#joinCode').value.trim();
  if (!code) return;
  const { log } = await api('/logs/join', { method: 'POST', body: JSON.stringify({ code }) });
  state.logId = log.id;
  await loadLogs();
  toast('ログに参加しました');
  showScreen('log');
});
$('#saveReminder').addEventListener('click', async () => {
  const { reminder } = await api('/reminders', {
    method: 'PUT',
    body: JSON.stringify({
      mode: $('#remMode').value,
      times: $('#remTimes').value,
      fromHour: Number($('#remFrom').value),
      toHour: Number($('#remTo').value),
      perDay: Number($('#remPer').value),
      tzOffset: new Date().getTimezoneOffset(),
    }),
  });
  state.reminder = reminder;
  toast('通知の設定を保存しました');
});
$('#remMode').addEventListener('change', updateReminderFields);
$('#enablePush').addEventListener('click', enablePush);
$('#testPush').addEventListener('click', async () => {
  const { sent } = await api('/push/test', { method: 'POST' });
  toast(sent ? 'テスト通知を送りました' : '送り先がありません。先に通知を許可してください');
});
$('#logoutBtn').addEventListener('click', async () => {
  await api('/auth/logout', { method: 'POST' });
  location.reload();
});

let authMode = 'login';
$('#tabLogin').addEventListener('click', () => switchAuth('login'));
$('#tabSignup').addEventListener('click', () => switchAuth('signup'));
function switchAuth(mode) {
  authMode = mode;
  $('#tabLogin').classList.toggle('active', mode === 'login');
  $('#tabSignup').classList.toggle('active', mode === 'signup');
  $('#displayNameField').hidden = mode !== 'signup';
  $('#authForm button').textContent = mode === 'login' ? 'ログイン' : '登録';
}
$('#authForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const fd = new FormData(e.target);
  const payload = Object.fromEntries(fd.entries());
  const err = $('#authError');
  err.hidden = true;
  try {
    await api(`/auth/${authMode}`, { method: 'POST', body: JSON.stringify(payload) });
    applyMe(await api('/me'));
    await showApp();
  } catch (ex) {
    err.textContent = ex.message;
    err.hidden = false;
  }
});

function debounce(fn, ms) {
  let t;
  return (...args) => { clearTimeout(t); t = setTimeout(() => fn(...args), ms); };
}

if ('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(() => {});

boot().catch((err) => {
  console.error(err);
  showAuth();
});
