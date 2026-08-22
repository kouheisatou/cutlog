const token = location.pathname.split('/').pop();
const $ = (s) => document.querySelector(s);
const esc = (s) => String(s).replace(/[&<>"']/g, (m) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[m]));

async function meta() {
  const res = await fetch(`/api/public/${token}/meta`);
  if (!res.ok) { $('#shareTitle').textContent = 'この共有リンクは、期限切れか停止のため開けません。'; return null; }
  return res.json();
}

async function load(password) {
  const res = await fetch(`/api/public/${token}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ password }),
  });
  const data = await res.json();
  if (!res.ok) {
    $('#err').textContent = data.error;
    $('#err').hidden = false;
    return;
  }
  $('#gate').hidden = true;
  $('#viewer').hidden = false;
  $('#title').textContent = data.title;
  $('#count').textContent = `${data.cuts.length}カット`;
  const wrap = $('#items');
  wrap.innerHTML = '';
  let day = '';
  for (const c of data.cuts) {
    if (c.localDate !== day) {
      day = c.localDate;
      const h = document.createElement('div');
      h.className = 'day-head';
      h.innerHTML = `<span>${day.replace(/-/g, '.')}</span>`;
      wrap.appendChild(h);
    }
    const box = document.createElement('div');
    box.className = 'share-cut';
    const t = new Date(new Date(c.takenAt).getTime() - (c.tzOffset || 0) * 60000);
    const hhmm = `${String(t.getUTCHours()).padStart(2, '0')}:${String(t.getUTCMinutes()).padStart(2, '0')}`;
    box.innerHTML = `<div class="when">${hhmm}${c.note ? ` ・ ${esc(c.note)}` : ''}</div>`
      + (c.kind === 'photo'
        ? `<img class="detail-media" src="${c.url}" alt="" />`
        : `<video class="detail-media" src="${c.url}" controls playsinline></video>`)
      + (data.allowDownload ? `<div class="dl"><a class="btn" href="${c.url}&download=1">ダウンロード</a></div>` : '');
    wrap.appendChild(box);
  }
}

const m = await meta();
if (m) {
  $('#shareTitle').textContent = m.title;
  if (m.needPassword) {
    $('#pwForm').hidden = false;
    $('#pwForm').addEventListener('submit', (e) => { e.preventDefault(); load($('#pw').value); });
  } else {
    load('');
  }
}
