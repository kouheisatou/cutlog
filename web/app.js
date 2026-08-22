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
  view: 'timeline',
  selected: new Set(),
  selectMode: false,
  activeCutId: null,
  calMonth: new Date(),
  dateFilter: null,
  mode: 'video',
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
  $('#settingsScreen').hidden = true;
  $('#authScreen').hidden = false;
}

// 画面は「ログ一覧（最上位）→ ログ → カットの詳細」の階層で切り替える。
// 設定はログ一覧と並ぶ画面である。
function showScreen(name) {
  $('#logsScreen').hidden = name !== 'logs';
  $('#app').hidden = name !== 'log';
  $('#settingsScreen').hidden = name !== 'settings';
}

async function showApp() {
  $('#authScreen').hidden = true;
  $('#whoami').textContent = `${state.user.displayName}（${state.user.username}）`;
  await loadLogs();
  showScreen('log');
  if (new URLSearchParams(location.search).get('capture')) openCapture();
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
  $('#logName').textContent = log.name;
  $('#logMeta').textContent = log.kind === 'private' ? '非公開' : `${members.length}人`;
  const sel = $('#authorFilter');
  sel.innerHTML = '<option value="">全員</option>'
    + members.map((m) => `<option value="${m.id}">${escapeHtml(m.display_name)}</option>`).join('');
  $('#tagFilter').value = '';
  await loadCuts();
}

async function loadCuts() {
  const params = new URLSearchParams();
  if (state.dateFilter) params.set('date', state.dateFilter);
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
function render() {
  $$('.seg').forEach((b) => {
    const on = b.dataset.view === state.view;
    b.classList.toggle('active', on);
    b.setAttribute('aria-selected', String(on));
  });
  $('#selectionBar').hidden = !state.selectMode;
  $('#selectionCount').textContent = `${state.selected.size}件`;
  const body = $('#listBody');
  body.innerHTML = '';
  if (state.view === 'calendar') renderCalendar(body);
  else if (state.view === 'grid') renderGrid(body);
  else renderTimeline(body);
}

function groupByDate(cuts) {
  const map = new Map();
  for (const c of cuts) {
    if (!map.has(c.localDate)) map.set(c.localDate, []);
    map.get(c.localDate).push(c);
  }
  return [...map.entries()].sort((a, b) => (a[0] < b[0] ? 1 : -1));
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

function cutRowEl(c) {
  const el = document.createElement('div');
  el.className = `cut-row${state.activeCutId === c.id ? ' active' : ''}`;
  if (state.activeCutId === c.id) el.setAttribute('aria-current', 'true');
  el.dataset.id = c.id;
  const timeLabel = fmtTime(c.takenAt, c.tzOffset);
  const pick = state.selectMode
    ? `<input type="checkbox" class="pick" tabindex="-1" ${state.selected.has(c.id) ? 'checked' : ''} />` : '';
  el.className += state.selectMode ? ' selecting' : '';
  if (state.selected.has(c.id)) el.className += ' picked';
  el.innerHTML = `
    ${pick}
    <div class="tc">${timeLabel}<span class="dot"></span></div>
    ${c.thumbUrl ? `<img class="frame" loading="lazy" src="${c.thumbUrl}" alt="" />` : '<div class="frame"></div>'}
    <div class="meta">
      <div class="n">${c.note ? escapeHtml(c.note) : escapeHtml(c.author || '')}</div>
      <div class="k">${c.kind === 'photo' ? 'PHOTO' : 'VIDEO'} · ${fmtBytes(c.bytes)}</div>
    </div>`;
  pressable(el, state.selectMode ? `${timeLabel} のカットを選ぶ` : `${timeLabel} のカットを開く`, (ev) => {
    if (state.selectMode) {
      toggleSelect(c.id);
      const box = el.querySelector('.pick');
      if (box && ev.target !== box) box.checked = state.selected.has(c.id);
      el.classList.toggle('picked', state.selected.has(c.id));
      return;
    }
    openDetail(c.id);
  });
  return el;
}

function emptyMessage() {
  const filtered = state.dateFilter || $('#search').value.trim() || $('#authorFilter').value || $('#tagFilter').value;
  return filtered ? '条件に合うカットはありません。' : 'まだカットがありません。';
}

function renderTimeline(body) {
  const groups = groupByDate(state.cuts);
  if (!groups.length) { body.innerHTML = `<div class="empty">${emptyMessage()}</div>`; return; }
  for (const [date, cuts] of groups) {
    const head = document.createElement('div');
    head.className = 'day-head';
    head.innerHTML = `<span>${date.replace(/-/g, '.')}</span><span class="muted">${String(cuts.length).padStart(2, '0')} cuts</span>`;
    const btn = document.createElement('button');
    btn.className = 'mini';
    btn.textContent = 'この日を選択';
    btn.addEventListener('click', () => {
      state.selectMode = true;
      $('#selectMode').checked = true;
      cuts.forEach((c) => state.selected.add(c.id));
      render();
    });
    head.appendChild(btn);
    body.appendChild(head);
    cuts.forEach((c) => body.appendChild(cutRowEl(c)));
  }
}

function renderGrid(body) {
  const wrap = document.createElement('div');
  wrap.className = 'grid-wrap';
  if (!state.cuts.length) { body.innerHTML = `<div class="empty">${emptyMessage()}</div>`; return; }
  for (const c of state.cuts) {
    const cell = document.createElement('div');
    cell.className = 'grid-cell';
    if (state.activeCutId === c.id) { cell.className += ' active'; cell.setAttribute('aria-current', 'true'); }
    const timeLabel = fmtTime(c.takenAt, c.tzOffset);
    cell.innerHTML = `
      ${c.thumbUrl ? `<img loading="lazy" src="${c.thumbUrl}" alt="" />` : ''}
      <span class="t">${timeLabel}</span>
      ${state.selectMode ? `<input type="checkbox" class="pick" tabindex="-1" ${state.selected.has(c.id) ? 'checked' : ''} />` : ''}`;
    pressable(cell, state.selectMode ? `${timeLabel} のカットを選ぶ` : `${timeLabel} のカットを開く`, (ev) => {
      if (state.selectMode) {
        toggleSelect(c.id);
        const box = cell.querySelector('.pick');
        if (box && ev.target !== box) box.checked = state.selected.has(c.id);
        return;
      }
      openDetail(c.id);
    });
    wrap.appendChild(cell);
  }
  body.appendChild(wrap);
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
    ${state.dateFilter ? `<button class="mini" id="calClear">${state.dateFilter} を解除</button>` : ''}`;
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
    if (state.dateFilter === date) el.className += ' on';
    if (!n) el.disabled = true;
    el.setAttribute('aria-label', `${m + 1}月${d}日、${n}カット`);
    const bars = Array.from({ length: Math.min(n, 6) }, () => '<i></i>').join('');
    el.innerHTML = `<span class="d">${String(d).padStart(2, '0')}</span><span class="bar">${bars}</span>`;
    el.addEventListener('click', async () => {
      state.dateFilter = state.dateFilter === date ? null : date;
      state.view = 'timeline';
      await loadCuts();
    });
    grid.appendChild(el);
  }
  wrap.appendChild(grid);
  body.appendChild(wrap);
  $('#calPrev').addEventListener('click', () => { state.calMonth = new Date(y, m - 1, 1); render(); });
  $('#calNext').addEventListener('click', () => { state.calMonth = new Date(y, m + 1, 1); render(); });
  $('#calClear')?.addEventListener('click', async () => { state.dateFilter = null; await loadCuts(); });
}

function toggleSelect(cutId) {
  if (state.selected.has(cutId)) state.selected.delete(cutId);
  else state.selected.add(cutId);
  $('#selectionCount').textContent = `${state.selected.size}件`;
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (m) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[m]));
}

// ── 詳細 ────────────────────────────────────────────────
async function openDetail(cutId) {
  state.activeCutId = cutId;
  $('#app').classList.add('detail-open');
  const { cut, reactions, myReactions, comments } = await api(`/cuts/${cutId}`);
  const el = $('#detail');
  $('#detailEmpty').hidden = true;
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
  render();

  $('#backToList').addEventListener('click', () => {
    $('#app').classList.remove('detail-open');
  });
  $('#dlBtn').addEventListener('click', () => { window.location.href = `${cut.url}?download=1`; });
  $('#shareOne').addEventListener('click', () => openPicker('share', [cut.id]));
  $('#moveOne').addEventListener('click', () => openMove([cut.id], cut.logId, { single: true }));
  $('#delBtn').addEventListener('click', async () => {
    if (!confirm('このカットを削除しますか。ゴミ箱から戻せます。')) return;
    await api(`/cuts/${cut.id}`, { method: 'DELETE' });
    toast('カットを削除しました');
    $('#detail').hidden = true;
    $('#detailEmpty').hidden = false;
    await loadCuts();
  });
  $$('.reaction', el).forEach((b) => b.addEventListener('click', async () => {
    await api(`/cuts/${cut.id}/reactions`, { method: 'POST', body: JSON.stringify({ emoji: b.dataset.emoji }) });
    openDetail(cut.id);
  }));
  $('#saveNote').addEventListener('click', async () => {
    await api(`/cuts/${cut.id}`, { method: 'PATCH', body: JSON.stringify({ note: $('#noteEdit').value }) });
    toast('メモを保存しました');
    await loadCuts();
  });
  $('#sendComment').addEventListener('click', async () => {
    const body = $('#commentInput').value.trim();
    if (!body) return;
    await api(`/cuts/${cut.id}/comments`, { method: 'POST', body: JSON.stringify({ body }) });
    openDetail(cut.id);
  });
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
  $('#capTimer').textContent = `${state.log?.cut_seconds || 3}秒`;
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
  const seconds = state.log?.cut_seconds || 3;
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
  if (!ids.length) { toast('カットが選ばれていません。「まとめて選択」をオンにしてから選んでください'); return; }
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
    row.className = 'pick-row';
    row.innerHTML = `<input type="checkbox" checked value="${c.id}" />
      ${c.thumbUrl ? `<img src="${c.thumbUrl}" alt="" />` : '<span></span>'}
      <span class="when">${c.localDate} ${fmtTime(c.takenAt, c.tzOffset)}</span>
      <span class="memo">${escapeHtml(c.note || c.author || '')}</span>`;
    list.appendChild(row);
  }
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
    body: JSON.stringify({ cutIds, style, label: state.dateFilter || 'まとめ' }),
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
  $('#app').classList.remove('detail-open');
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
  for (const l of state.logs) {
    const row = document.createElement('button');
    row.type = 'button';
    row.className = 'log-row';
    if (l.id === state.logId) row.setAttribute('aria-current', 'true');
    const info = l.kind === 'private'
      ? `<svg class="ic sm"><use href="#ic-lock"/></svg>非公開 / ${l.cut_count}カット`
      : `${l.cut_count}カット / ${l.member_count}人 / 招待コード <code>${l.invite_code}</code>`;
    row.innerHTML = `<strong>${escapeHtml(l.name)}</strong><span class="muted small">${info}</span>`;
    row.addEventListener('click', async () => {
      state.logId = l.id; state.selected.clear(); state.dateFilter = null;
      await loadLog();
      showScreen('log');
    });
    list.appendChild(row);
  }
}

// ── 設定（ログ一覧と並ぶ画面） ──────────────────────────
function openSettings() {
  $('#defaultLog').innerHTML = state.logs
    .map((l) => `<option value="${l.id}">${escapeHtml(l.name)}</option>`).join('');
  $('#defaultLog').value = state.defaultLogId || state.privateLogId || '';
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
$$('.seg').forEach((b) => b.addEventListener('click', () => { state.view = b.dataset.view; render(); }));
$('#selectMode').addEventListener('change', (e) => { state.selectMode = e.target.checked; render(); });
$('#selectAll').addEventListener('click', () => { state.cuts.forEach((c) => state.selected.add(c.id)); render(); });
$('#selectNone').addEventListener('click', () => { state.selected.clear(); render(); });
$('#exportBtn').addEventListener('click', () => openPicker('export'));
$('#shareBtn').addEventListener('click', () => openPicker('share'));
$('#renderBtn').addEventListener('click', () => openPicker('render'));
$('#moveBtn').addEventListener('click', () => {
  const ids = [...state.selected];
  if (!ids.length) { toast('カットが選ばれていません。「まとめて選択」をオンにしてから選んでください'); return; }
  openMove(ids, state.logId);
});
$('#renderOptions').addEventListener('input', () => { syncStyleFields(); updateStylePreview(); });
$('#defaultLog').addEventListener('change', async () => {
  const v = $('#defaultLog').value;
  const res = await api('/me', {
    method: 'PATCH',
    body: JSON.stringify({ defaultLogId: v === state.privateLogId ? null : v }),
  });
  state.defaultLogId = res.defaultLogId;
  toast('既定の記録先を保存しました');
});
initStyleForm();
$('#search').addEventListener('input', debounce(loadCuts, 350));
$('#authorFilter').addEventListener('change', loadCuts);
$('#tagFilter').addEventListener('change', loadCuts);
$('#captureBtn').addEventListener('click', openCapture);
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
$('#logTitleBtn').addEventListener('click', openLogs);
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
