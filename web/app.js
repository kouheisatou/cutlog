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
  activeCutId: null,
  day: null,             // いま開いている日（YYYY-MM-DD）
  dayCuts: [],
  calMonth: new Date(),
  mode: 'video',
  // 下のタブ（camera は撮影を開くだけの動き。画面としては残らない）
  tab: 'logs',
  // 「ログ」タブの中でどこまで潜っているか（logs = 一覧、log = ログの中、settings = 設定）
  logsStack: 'logs',
  // 全カット（ログをまたいだ一覧）
  allCuts: [],
  allKind: '',
  activeAllCutId: null,
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
  $('#settingsScreen').hidden = true;
  $('#tabbar').hidden = true;
  $('#authScreen').hidden = false;
}

// 画面は「ログ一覧（最上位）→ ログ → カットの詳細」の階層で切り替える。
// 設定はログ一覧と並ぶ画面、全カットは下のタブで並ぶ画面である。
function showScreen(name) {
  $('#logsScreen').hidden = name !== 'logs';
  $('#app').hidden = name !== 'log';
  $('#logSetScreen').hidden = name !== 'logset';
  $('#dayScreen').hidden = name !== 'day';
  $('#allScreen').hidden = name !== 'all';
  $('#settingsScreen').hidden = name !== 'settings';
  // 画面から離れるときは、鳴っているものを止める
  if (name !== 'day' && play.playing) togglePlay();
  state.tab = name === 'all' ? 'all' : 'logs';
  if (name !== 'all') state.logsStack = name;
  renderTabbar();
  renderCrumbs();
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
  // ログのタブ。すでにログのタブにいるなら、一段上（ログ一覧）へ戻る。
  if (state.tab === 'logs' && state.logsStack !== 'logs') { await openLogs(); return; }
  if (state.logsStack === 'log' && state.log) { showScreen('log'); return; }
  if (state.logsStack === 'settings') { showScreen('settings'); return; }
  await openLogs();
}

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

function activeCutLabel(cut) {
  if (!cut) return null;
  return `${cut.localDate.replace(/-/g, '.')} ${fmtTime(cut.takenAt, cut.tzOffset)}`;
}

function renderCrumbs() {
  const toLogs = () => { openLogs(); };
  setCrumbs($('#logsCrumbs'), [{ label: 'ログ' }]);
  setCrumbs($('#settingsCrumbs'), [{ label: 'ログ', go: toLogs }, { label: '設定' }]);

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
  const openCut = state.dayCuts.find((c) => c.id === state.activeCutId);
  if ($('#dayScreen').classList.contains('detail-open') && openCut) {
    dayItems[2] = { label: state.day ? state.day.replace(/-/g, '.') : '—', go: () => closeDetailPane() };
    dayItems.push({ label: activeCutLabel(openCut) });
  }
  setCrumbs($('#dayCrumbs'), dayItems);

  const allItems = [{ label: '全カット' }];
  const openAll = state.allCuts.find((c) => c.id === state.activeAllCutId);
  if ($('#allScreen').classList.contains('detail-open') && openAll) {
    allItems[0] = { label: '全カット', go: () => closeAllDetail() };
    allItems.push({ label: openAll.logName || '—' }, { label: activeCutLabel(openAll) });
  }
  setCrumbs($('#allCrumbs'), allItems);
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
  const wrap = document.createElement('div');
  wrap.className = 'cal';
  const cur = state.calMonth;
  const y = cur.getFullYear();
  const m = cur.getMonth();
  const counts = new Map();
  for (const c of state.cuts) counts.set(c.localDate, (counts.get(c.localDate) || 0) + 1);
  const head = document.createElement('div');
  head.className = 'cal-head';
  head.innerHTML = `<button class="mini" id="calPrev" aria-label="前の月"><svg class="ic sm"><use href="#ic-prev"/></svg></button>
    <strong>${y}.${String(m + 1).padStart(2, '0')}</strong>
    <button class="mini" id="calNext" aria-label="次の月"><svg class="ic sm"><use href="#ic-next"/></svg></button>
    <div class="spacer"></div>
    <span class="muted small">${state.cuts.length}カット</span>`;
  wrap.appendChild(head);
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
  const today = new Date().toISOString().slice(0, 10);
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
    el.className = `cal-day${n ? ' has' : ''}${date === today ? ' today' : ''}`;
    if (state.day === date) el.className += ' on';
    if (!n) el.disabled = true;
    el.setAttribute('aria-label', `${m + 1}月${d}日、${n}カット`);
    const bars = Array.from({ length: Math.min(n, 6) }, () => '<i></i>').join('');
    el.innerHTML = `<span class="d">${String(d).padStart(2, '0')}</span><span class="bar">${bars}</span>`;
    el.addEventListener('click', () => openDay(date));
    grid.appendChild(el);
  }
  wrap.appendChild(grid);
  body.appendChild(wrap);
  $('#calPrev').addEventListener('click', () => { state.calMonth = new Date(y, m - 1, 1); render(); });
  $('#calNext').addEventListener('click', () => { state.calMonth = new Date(y, m + 1, 1); render(); });
}


function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (m) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[m]));
}

// ── 詳細 ────────────────────────────────────────────────
// 詳細は「ログの中」と「全カット」の2か所から開く。どちらの画面に描くかをここで決める。
const DETAIL_CTX = {
  day: {
    screen: '#dayScreen',
    detail: '#detail',
    empty: '#detailEmpty',
    setActive: (id) => { state.activeCutId = id; },
    rerender: () => renderDayList(),
    refresh: () => reloadDay(),
  },
  all: {
    screen: '#allScreen',
    detail: '#allDetail',
    empty: '#allDetailEmpty',
    setActive: (id) => { state.activeAllCutId = id; },
    rerender: () => renderAll(),
    refresh: () => loadAllCuts(),
  },
};

async function openDetail(cutId, ctxName = 'day') {
  const ctx = DETAIL_CTX[ctxName];
  ctx.setActive(cutId);
  $(ctx.screen).classList.add('detail-open');
  const { cut, reactions, myReactions, comments } = await api(`/cuts/${cutId}`);
  const el = $(ctx.detail);
  $(ctx.empty).hidden = true;
  el.hidden = false;
  const media = cut.kind === 'photo'
    ? `<img class="detail-media" src="${cut.url}" alt="" />`
    : `<video class="detail-media" src="${cut.url}" controls playsinline></video>`;
  el.innerHTML = `
    <button class="btn" id="backToList"><svg class="ic sm"><use href="#ic-back"/></svg>一覧へ戻る</button>
    ${media}
    <span class="eyebrow">${cut.kind === 'photo' ? 'PHOTO' : 'VIDEO'} · ${escapeHtml(cut.author || '')}</span>
    <h2>${cut.localDate.replace(/-/g, '.')} ${fmtTime(cut.takenAt, cut.tzOffset)}</h2>
    <div class="detail-actions">
      <button class="btn" id="dlBtn"><svg class="ic sm"><use href="#ic-download"/></svg>ダウンロード</button>
      <button class="btn" id="shareOne"><svg class="ic sm"><use href="#ic-share"/></svg>共有</button>
      <button class="btn" id="moveOne"><svg class="ic sm"><use href="#ic-move"/></svg>移動</button>
      <button class="btn danger" id="delBtn"><svg class="ic sm"><use href="#ic-trash"/></svg>削除</button>
    </div>
    <div class="reactions">
      ${['👍', '🎉', '😂', '🥺', '🔥'].map((e) => {
    const n = reactions.find((r) => r.emoji === e)?.n || 0;
    return `<button class="reaction${myReactions.includes(e) ? ' on' : ''}" data-emoji="${e}">${e} ${n || ''}</button>`;
  }).join('')}
    </div>
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
      <tr><td>ID</td><td class="small">${cut.id}</td></tr>
    </table>
    <div class="comments">
      <h3 class="small muted">コメント</h3>
      ${comments.map((c) => `<div class="comment"><strong>${escapeHtml(c.author)}</strong> ${escapeHtml(c.body)}</div>`).join('')}
      <div class="panel-row">
        <input id="commentInput" placeholder="コメントを書く" />
        <button class="btn" id="sendComment">送信</button>
      </div>
    </div>`;
  ctx.rerender();
  renderCrumbs();

  // 2つの詳細（ログの中・全カット）が同じidを持つので、必ずこの画面の中だけを探す。
  $('#backToList', el).addEventListener('click', () => {
    if (ctxName === 'all') closeAllDetail(); else closeDetailPane();
  });
  $('#dlBtn', el).addEventListener('click', () => { window.location.href = `${cut.url}?download=1`; });
  $('#shareOne', el).addEventListener('click', () => openPicker('share', [cut.id]));
  $('#moveOne', el).addEventListener('click', () => openMove([cut.id], cut.logId, { single: true }));
  $('#delBtn', el).addEventListener('click', async () => {
    if (!confirm('このカットを削除しますか。ゴミ箱から戻せます。')) return;
    await api(`/cuts/${cut.id}`, { method: 'DELETE' });
    toast('カットを削除しました');
    el.hidden = true;
    $(ctx.empty).hidden = false;
    ctx.setActive(null);
    $(ctx.screen).classList.remove('detail-open');
    await ctx.refresh();
    renderCrumbs();
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
      out.textContent = '外す';
      out.addEventListener('click', async () => {
        if (!confirm(`${m.display_name} をこのログから外しますか。`)) return;
        await api(`/logs/${state.logId}/members/${m.id}`, { method: 'DELETE' });
        toast('外しました');
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
  closeDetailPane();
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
  const shown = state.dayCuts.filter((c) => !c.hidden).length;
  $('#dayCount').textContent = `${shown} / ${state.dayCuts.length} クリップ　${fmtClock(play.total)}`;
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
        <span class="k">${c.kind === 'photo' ? 'PHOTO' : 'VIDEO'} · ${len}${c.hidden ? ' · 非表示' : ''}</span>
      </span>`;
    // 行を押すと、その位置から続きを流す
    const jump = document.createElement('button');
    jump.type = 'button';
    jump.className = 'clip-hit';
    jump.setAttribute('aria-label', `${t} から再生する`);
    jump.addEventListener('click', async () => {
      if (c.hidden) { toast('非表示のクリップです。目のしるしを押すと戻せます'); return; }
      const i = play.items.findIndex((it) => it.cut.id === c.id);
      if (i >= 0) await showClip(i, 0, true);
    });
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
    info.className = 'clip-info icon-btn';
    info.setAttribute('aria-label', `${t} の詳しい情報`);
    info.innerHTML = '<svg class="ic sm"><use href="#ic-search"/></svg>';
    info.addEventListener('click', (ev) => { ev.stopPropagation(); openDetail(c.id, 'day'); });
    row.append(jump, eye, info);
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
  $('#pvBadge').textContent = it
    ? `${play.idx + 1} / ${play.items.length}　${fmtTime(it.cut.takenAt, it.cut.tzOffset)}${it.cut.note ? `　${it.cut.note}` : ''}`
    : '';
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

async function openCapture() {
  const dlg = $('#captureDialog');
  dlg.showModal();
  $('#capTimer').textContent = `${state.log?.cut_seconds || 2}秒`;
  state.captureLogId = state.logId;
  updateCapDest();
  await startStream();
}

async function startStream() {
  stopStream();
  try {
    stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: facing, width: { ideal: 1080 }, height: { ideal: 1920 } },
      audio: state.mode === 'video',
    });
    $('#preview').srcObject = stream;
    $('#preview').hidden = false;
    $('#playback').hidden = true;
  } catch (err) {
    toast(`カメラを使えませんでした。ブラウザのカメラの許可を確認してください（${err.message}）`, 5000);
  }
}

function stopStream() {
  if (stream) stream.getTracks().forEach((t) => t.stop());
  stream = null;
}

function closeCapture() {
  stopStream();
  pending = null;
  $('#reviewBar').hidden = true;
  $('#playback').hidden = true;
  $('#preview').hidden = false;
  $('#captureDialog').close();
}

async function shoot() {
  if (!stream) return;
  if (state.mode === 'photo') {
    const video = $('#preview');
    const canvas = $('#snapCanvas');
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    canvas.getContext('2d').drawImage(video, 0, 0);
    const blob = await new Promise((r) => canvas.toBlob(r, 'image/jpeg', 0.92));
    pending = { blob, kind: 'photo', durationMs: null, mime: 'image/jpeg' };
    showReview(URL.createObjectURL(blob), 'photo');
    return;
  }
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
  const titles = { export: 'カットの書き出し', share: '共有リンクの作成', render: 'まとめ動画の作成' };
  const goLabels = { export: '書き出し', share: '作成', render: '作成' };
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
  toast('まとめ動画を作っています…');
  const poll = setInterval(async () => {
    const { job } = await api(`/jobs/${jobId}`);
    if (job.status === 'done') {
      clearInterval(poll);
      toast('まとめ動画ができました。ダウンロードを始めます');
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

function closeDetailPane() {
  state.activeCutId = null;
  $('#detail').hidden = true;
  $('#detailEmpty').hidden = false;
  $('#dayScreen').classList.remove('detail-open');
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
  if (!targets.length) { toast('移す先のログがありません。ログ一覧で作るか、参加してください'); return; }
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
    if (!to) { toast('移す先のログを選んでください'); return; }
    const toName = state.logs.find((l) => l.id === to)?.name || '';
    (async () => {
      try {
        if (single) {
          await api(`/cuts/${cutIds[0]}/move`, { method: 'POST', body: JSON.stringify({ logId: to }) });
          dlg.close();
          toast(`「${toName}」へ移しました`);
          closeDetailPane();
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
  $('#logsCount').textContent = `${state.logs.length} 件`;
  for (const l of state.logs) {
    const row = document.createElement('button');
    row.type = 'button';
    row.className = 'log-row';
    if (l.id === state.logId) row.setAttribute('aria-current', 'true');
    // 左に最後のカットの見本、真ん中に名前と中身、右に「入れる」印。
    const thumb = l.latestThumbUrl
      ? `<img src="${l.latestThumbUrl}" alt="" loading="lazy" />`
      : `<svg class="ic"><use href="#ic-${l.kind === 'private' ? 'lock' : 'film'}"/></svg>`;
    const bits = [`${l.cut_count}カット`];
    if (l.kind === 'private') bits.push('非公開');
    else bits.push(`${l.member_count}人`, `コード ${l.invite_code}`);
    if (l.latestTakenAt) bits.push(`最後 ${l.latestTakenAt.slice(0, 10).replace(/-/g, '.')}`);
    row.innerHTML = `
      <span class="log-thumb${l.latestThumbUrl ? '' : ' blank'}">${thumb}</span>
      <span class="log-main">
        <span class="log-name">${escapeHtml(l.name)}</span>
        <span class="log-sub">${bits.map(escapeHtml).join(' · ')}</span>
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
  if (state.allKind) params.set('kind', state.allKind);
  const q = $('#allSearch').value.trim();
  if (q) params.set('q', q);
  params.set('limit', '300');
  const { cuts } = await api(`/cuts?${params}`);
  state.allCuts = cuts;
  renderAll();
}

function renderAll() {
  $$('#allScreen .seg').forEach((b) => {
    const on = (b.dataset.kind || '') === state.allKind;
    b.classList.toggle('active', on);
    b.setAttribute('aria-selected', String(on));
  });
  const body = $('#allBody');
  body.innerHTML = '';
  if (!state.allCuts.length) {
    body.innerHTML = `<div class="empty">${$('#allSearch').value.trim() || state.allKind
      ? '条件に合うカットはありません。' : 'まだカットがありません。カメラのタブから撮ってみてください。'}</div>`;
    return;
  }
  // 日付でひとまとまりにして、その中は撮った順に並べる。
  const map = new Map();
  for (const c of state.allCuts) {
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
      if (state.activeAllCutId === c.id) { cell.className += ' active'; cell.setAttribute('aria-current', 'true'); }
      const timeLabel = fmtTime(c.takenAt, c.tzOffset);
      cell.innerHTML = `
        ${c.thumbUrl ? `<img loading="lazy" src="${c.thumbUrl}" alt="" />` : '<span class="ph"></span>'}
        ${c.kind === 'video' ? '<svg class="ic sm badge"><use href="#ic-film"/></svg>' : ''}
        <span class="cap"><span class="t">${timeLabel}</span><span class="lg">${escapeHtml(c.logName || '')}</span></span>`;
      pressable(cell, `${escapeHtml(c.logName || '')} ${timeLabel} のカットを開く`, () => openDetail(c.id, 'all'));
      wrap.appendChild(cell);
    }
    body.appendChild(wrap);
  }
}

function closeAllDetail() {
  $('#allScreen').classList.remove('detail-open');
  state.activeAllCutId = null;
  renderAll();
  renderCrumbs();
}

// ── 設定（ログ一覧と並ぶ画面） ──────────────────────────
function openSettings() {
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
      if (!confirm('この共有リンクを止めますか。リンクを知っている人は開けなくなります。')) return;
      await api(`/shares/${s.id}`, { method: 'DELETE' });
      toast('共有リンクを止めました');
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
$$('#allScreen .seg').forEach((b) => b.addEventListener('click', () => {
  state.allKind = b.dataset.kind || '';
  loadAllCuts();
}));
$('#allSearch').addEventListener('input', debounce(loadAllCuts, 350));
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
  if (!confirm('招待コードを作り直しますか。いまのコードでは入れなくなります。')) return;
  const { inviteCode } = await api(`/logs/${state.logId}/invite/rotate`, { method: 'POST' });
  $('#logSetInvite').textContent = inviteCode;
  await loadLogs();
  toast('作り直しました');
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
$$('.mode-toggle .chip').forEach((b) => b.addEventListener('click', async () => {
  state.mode = b.dataset.mode;
  $$('.mode-toggle .chip').forEach((x) => x.classList.toggle('active', x === b));
  await startStream();
}));
$('#fileInput').addEventListener('change', async (e) => {
  const file = e.target.files[0];
  if (!file) return;
  pending = {
    blob: file,
    kind: file.type.startsWith('image/') ? 'photo' : 'video',
    durationMs: null,
    mime: file.type,
    source: 'upload',
  };
  showReview(URL.createObjectURL(file), pending.kind);
});
$('#settingsBtn').addEventListener('click', openSettings);
$('#settingsBack').addEventListener('click', openLogs);
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
  showScreen('log');
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
