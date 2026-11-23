/* Admin UI yordamchilari: xavfsiz HTML, holatlar (loading/empty/error), jadval + pagination, dialoglar, toast. */
(function () {
  const esc = v => v === null || v === undefined ? '' : String(v).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const fmtDate = v => { if (!v) return '—'; const d = new Date(v); return isNaN(d) ? esc(v) : d.toLocaleDateString('uz-UZ', { year: 'numeric', month: '2-digit', day: '2-digit' }); };
  const fmtDT = v => { if (!v) return '—'; const d = new Date(v); return isNaN(d) ? esc(v) : d.toLocaleString('uz-UZ', { year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' }); };
  const debounce = (fn, ms = 300) => { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; };

  // Holat belgilari — bir xil rang tizimi
  const LABELS = {
    workflow: { draft: ['Draft', ''], evidence_review: ['Evidence Review', 'b-amber'], instructor_review: ['Medical/Instructor Review', 'b-violet'], approved: ['Approved', 'b-blue'],
      published: ['Published', 'b-green'], review_required: ['Review Required', 'b-red'], deprecated: ['Deprecated', ''], archived: ['Archived', ''] },
    evidence: { current: ['Current', 'b-green'], review_due: ['Review Due', 'b-amber'], outdated: ['Outdated', 'b-red'], superseded: ['Superseded', 'b-red'],
      conflicting: ['Conflicting', 'b-red'], unknown: ['Unknown', 'b-amber'] },
    verification: { verified: ['Verified', 'b-green'], unverified: ['Unverified', 'b-amber'], failed: ['Failed', 'b-red'], not_applicable: ['N/A', ''] },
    source: { draft: ['Draft', ''], active: ['Active', 'b-green'], superseded: ['Superseded', 'b-red'], retracted: ['Retracted', 'b-red'], withdrawn: ['Withdrawn', 'b-red'], archived: ['Archived', ''] },
    course: { draft: ['Draft', ''], under_review: ['Under Review', 'b-amber'], approved: ['Approved', 'b-blue'], published: ['Published', 'b-green'], archived: ['Archived', ''] },
    employment: { active: ['Faol', 'b-green'], on_leave: ['Ta\'tilda', 'b-amber'], inactive: ['Nofaol', 'b-amber'], terminated: ['Ishdan ketgan', 'b-red'] },
    account: { active: ['Akkaunt faol', 'b-green'], pending: ['Tasdiq kutilmoqda', 'b-amber'], inactive: ['Inactive', 'b-amber'], deactivated: ['Deactivated', 'b-red'], rejected: ['Rad etilgan', 'b-red'] },
    decision: { approved: ['Approved', 'b-green'], changes_requested: ['Changes requested', 'b-amber'], rejected: ['Rejected', 'b-red'], mark_outdated: ['Marked outdated', 'b-red'],
      mark_conflicting: ['Marked conflicting', 'b-red'], deprecate_recommended: ['Deprecate tavsiya', ''] },
    generic: { active: ['Active', 'b-green'], inactive: ['Inactive', ''], published: ['Published', 'b-green'], draft: ['Draft', ''], archived: ['Archived', ''],
      assigned: ['Tayinlangan', 'b-blue'], in_progress: ['Jarayonda', 'b-amber'], completed: ['Tugallangan', 'b-green'], overdue: ['Muddati o\'tgan', 'b-red'], cancelled: ['Bekor', ''],
      open: ['Ochiq', 'b-amber'] },
  };
  const badge = (kind, v) => { if (v === null || v === undefined || v === '') return '<span class="badge">—</span>'; const m = (LABELS[kind] || {})[v] || [v, '']; return `<span class="badge ${m[1]}" data-status="${esc(v)}">${esc(m[0])}</span>`; };

  const skeleton = (n = 6) => '<div class="card">' + Array.from({ length: n }, (_, i) => `<div class="skel" style="width:${60 + (i * 7) % 40}%"></div>`).join('') + '</div>';
  const empty = (msg, sub = '') => `<div class="state" data-state="empty"><div class="ic">∅</div><div><b>${esc(msg)}</b></div>${sub ? `<div class="small">${esc(sub)}</div>` : ''}</div>`;
  const errorBox = (e) => `<div class="state err" data-state="error"><div class="ic">!</div><div><b>Xatolik</b></div><div class="small">${esc(e && e.message ? e.message : e)}</div></div>`;
  const denied = (what = 'Bu bo\'lim') => `<div class="card"><div class="state" data-state="denied"><div class="ic">🔒</div><div><b>${esc(what)} uchun ruxsat yo'q</b></div><div class="small">Rolingizda kerakli ruxsat mavjud emas. Server ham bu ma'lumotni qaytarmaydi.</div></div></div>`;

  // Jadval: columns [{h, r: row => html, cls}]
  function table(rows, columns, opt = {}) {
    if (!rows.length) return empty(opt.empty || 'Ma\'lumot topilmadi', opt.emptySub || '');
    return `<div class="tablewrap"><table class="t" data-table="${esc(opt.id || '')}"><thead><tr>${columns.map(c => `<th>${esc(c.h)}</th>`).join('')}</tr></thead><tbody>` +
      rows.map(r => `<tr${opt.href ? ` class="click" data-href="${esc(opt.href(r))}"` : ''}>${columns.map(c => `<td class="${c.cls || ''}">${c.r(r)}</td>`).join('')}</tr>`).join('') +
      `</tbody></table></div>`;
  }
  function pager(page, size, total) {
    const pages = Math.max(1, Math.ceil((total || 0) / size));
    return `<div class="pager" data-pager><span>${total ? (page * size + 1) + '–' + Math.min(total, (page + 1) * size) + ' / ' + total : '0'}</span>
      <button class="btn sm" data-page="${page - 1}" ${page <= 0 ? 'disabled' : ''}>‹ Oldingi</button>
      <span>${page + 1} / ${pages}</span>
      <button class="btn sm" data-page="${page + 1}" ${page + 1 >= pages ? 'disabled' : ''}>Keyingi ›</button></div>`;
  }

  // Toast
  function toast(msg, isErr) {
    let box = document.querySelector('.toast'); if (!box) { box = document.createElement('div'); box.className = 'toast'; document.body.appendChild(box); }
    const d = document.createElement('div'); d.textContent = msg; if (isErr) d.className = 'err'; d.setAttribute('data-toast', isErr ? 'error' : 'ok'); box.appendChild(d);
    setTimeout(() => d.remove(), isErr ? 7000 : 3500);
  }

  // Dialog: kritik amallar uchun tasdiq. fields: [{name,label,type:'text'|'textarea'|'select'|'check',options,required}]
  function dialog({ title, body = '', fields = [], okText = 'Tasdiqlash', danger = false }) {
    return new Promise(resolve => {
      const bg = document.createElement('div'); bg.className = 'modal-bg';
      bg.innerHTML = `<div class="modal" role="dialog" aria-modal="true" data-dialog><h3>${esc(title)}</h3>${body ? `<div class="muted small">${body}</div>` : ''}
        <form>${fields.map(f => f.type === 'check' ? `<label class="check"><input type="checkbox" name="${esc(f.name)}" ${f.required ? 'required' : ''}> <span>${esc(f.label)}</span></label>`
          : `<label>${esc(f.label)}${f.required ? ' *' : ''}</label>` + (f.type === 'textarea' ? `<textarea name="${esc(f.name)}" rows="3" ${f.required ? 'required' : ''}>${esc(f.value || '')}</textarea>`
          : f.type === 'select' ? `<select name="${esc(f.name)}" ${f.required ? 'required' : ''}>${(f.options || []).map(o => `<option value="${esc(o[0])}" ${o[0] === f.value ? 'selected' : ''}>${esc(o[1])}</option>`).join('')}</select>`
          : `<input name="${esc(f.name)}" type="${f.type || 'text'}" value="${esc(f.value || '')}" ${f.required ? 'required' : ''} ${f.pattern ? `pattern="${esc(f.pattern)}"` : ''} placeholder="${esc(f.placeholder || '')}">`)).join('')}
        <div class="small" data-err style="color:#b91c1c;margin-top:8px"></div>
        <div class="foot"><button type="button" class="btn" data-cancel>Bekor qilish</button><button type="submit" class="btn ${danger ? 'red' : 'primary'}" data-ok>${esc(okText)}</button></div></form></div>`;
      document.body.appendChild(bg);
      const form = bg.querySelector('form');
      const close = v => { bg.remove(); resolve(v); };
      bg.querySelector('[data-cancel]').onclick = () => close(null);
      bg.addEventListener('keydown', e => { if (e.key === 'Escape') close(null); });
      form.onsubmit = e => { e.preventDefault(); if (!form.reportValidity()) return; const out = {};
        fields.forEach(f => { const el = form.elements[f.name]; out[f.name] = f.type === 'check' ? el.checked : el.value.trim(); });
        const bad = fields.find(f => f.required && f.type !== 'check' && !out[f.name]); if (bad) { bg.querySelector('[data-err]').textContent = bad.label + ' majburiy'; return; }
        close(out); };
      const first = form.querySelector('input,textarea,select'); first && first.focus();
    });
  }

  // Sahifa registri (pages_*.js shu yerga yozadi; main.js ishga tushiradi)
  const routes = [];
  window.ADMIN = { routes, gen: 0, route(pattern, section, render) { routes.push({ re: new RegExp('^' + pattern.replace(/:(\w+)/g, '(?<$1>[^/]+)') + '$'), section, render }); }, go(h) { location.hash = h; } };
  window.UI = { esc, fmtDate, fmtDT, debounce, badge, LABELS, skeleton, empty, errorBox, denied, table, pager, toast, dialog };
})();
