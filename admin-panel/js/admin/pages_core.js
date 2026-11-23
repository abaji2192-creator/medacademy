/* Umumiy ro'yxat sahifasi (filtr + qidiruv debounce + server-side pagination) va Dashboard / Audit. */
(function () {
  const { esc, badge, table, pager, empty, errorBox, skeleton, debounce, fmtDT } = UI;

  // cfg: {title, sub, actions, filters:[{key,type,label,options}], chips:{key,items,counts}, load(q)=>{rows,count}, columns, href, empty, size, onReady(el)}
  async function listPage(el, ctx, cfg) {
    const q = { page: +(ctx.query.page || 0), ...ctx.query };
    ctx.setTitle(cfg.title);
    el.innerHTML = `<div class="adm-h"><div><h1>${esc(cfg.title)}</h1>${cfg.sub ? `<div class="sub">${cfg.sub}</div>` : ''}</div><div class="act">${cfg.actions || ''}</div></div>
      ${cfg.top || ''}<div data-chips></div>
      <div class="filters">${(cfg.filters || []).map(f => f.type === 'search'
        ? `<input type="search" data-f="${esc(f.key)}" placeholder="${esc(f.label)}" value="${esc(q[f.key] || '')}">`
        : `<select data-f="${esc(f.key)}"><option value="">${esc(f.label)}: barchasi</option>${(f.options || []).map(o => `<option value="${esc(o[0])}" ${String(q[f.key] || '') === String(o[0]) ? 'selected' : ''}>${esc(o[1])}</option>`).join('')}</select>`).join('')}</div>
      <div class="card" style="padding:6px 8px" data-list>${skeleton()}</div>`;
    const listEl = el.querySelector('[data-list]');
    const chipsEl = el.querySelector('[data-chips]');
    const drawChips = (counts) => { if (!cfg.chips) return; const cur = q[cfg.chips.key] || '';
      chipsEl.innerHTML = `<div class="chips">${cfg.chips.items.map(([v, l]) => `<button class="chip ${cur === v ? 'on' : ''}" data-chip="${esc(v)}">${esc(l)}${counts && counts[v] !== undefined ? `<span class="n">${counts[v]}</span>` : ''}</button>`).join('')}</div>`; };
    drawChips();
    if (cfg.chips && cfg.chips.counts) cfg.chips.counts().then(c => { if (ctx.alive()) drawChips(c); }).catch(() => {});
    let seq = 0;
    const load = async () => {
      const my = ++seq; listEl.innerHTML = skeleton(4);
      try {
        const size = cfg.size || 25; const r = await cfg.load({ ...q, page: +q.page || 0, size });
        if (!ctx.alive() || my !== seq) return;
        listEl.innerHTML = table(r.rows, cfg.columns, { href: cfg.href, empty: cfg.empty, emptySub: cfg.emptySub, id: cfg.id }) + (r.count > size || (+q.page || 0) > 0 ? pager(+q.page || 0, size, r.count) : `<div class="pager">${r.count} ta</div>`);
        cfg.onReady && cfg.onReady(listEl, r);
      } catch (e) { if (ctx.alive() && my === seq) listEl.innerHTML = errorBox(API.friendly(e)); }
    };
    const setQ = patch => { Object.assign(q, patch); ctx.setQuery(patch); load(); };
    el.querySelectorAll('[data-f]').forEach(inp => {
      const k = inp.getAttribute('data-f');
      if (inp.tagName === 'INPUT') inp.addEventListener('input', debounce(() => setQ({ [k]: inp.value.trim(), page: 0 }), 300));
      else inp.addEventListener('change', () => setQ({ [k]: inp.value, page: 0 }));
    });
    chipsEl.addEventListener('click', e => { const b = e.target.closest('[data-chip]'); if (!b) return; setQ({ [cfg.chips.key]: b.getAttribute('data-chip'), page: 0 }); drawChips(); cfg.chips.counts && cfg.chips.counts().then(c => ctx.alive() && drawChips(c)).catch(() => {}); });
    listEl.addEventListener('click', e => { const b = e.target.closest('[data-page]'); if (b && !b.disabled) setQ({ page: +b.getAttribute('data-page') }); });
    await load();
    return { reload: load, q };
  }

  // Lookups (bo'lim/lavozim/mutaxassislik/kurs) — RLS doirasida, keshlanadi
  const cache = {};
  async function lookup(table, label = 'name', extra = {}) {
    const key = table + label; if (cache[key]) return cache[key];
    const r = await API.list(table, { select: 'id,' + label, all: true, count: false, order: [label, true], ...extra });
    cache[key] = Object.fromEntries(r.rows.map(x => [x.id, x[label]])); return cache[key];
  }
  const clearCache = () => Object.keys(cache).forEach(k => delete cache[k]);

  // ---------------- Dashboard ----------------
  ADMIN.route('/', 'dashboard', async (el, ctx) => {
    ctx.setTitle('Dashboard');
    const p = PERMS.state.profile;
    el.innerHTML = `<div class="adm-h"><div><h1>Dashboard</h1><div class="sub">Ko'rsatkichlar sizning ruxsat doirangiz bo'yicha (server RLS) hisoblanadi.</div></div></div>
      <div class="kpis" data-kpis>${Array.from({ length: 10 }, () => '<div class="kpi"><div class="skel"></div><div class="skel" style="width:60%"></div></div>').join('')}</div>
      <div class="grid g2"><div class="card"><h3>Evidence lifecycle</h3><div class="small muted">Education → Evidence → Review → Medical Validation → Publication → Monitoring → Update</div><div data-ev style="margin-top:10px"></div></div>
      <div class="card"><h3>Eslatma</h3><div class="note">Klinik savollar faqat <b>Evidence Review + Medical Review</b>dan keyin imtihonga kiradi. Yaroqlilikni server (<span class="mono">question_meta</span>) hisoblaydi — Admin Panel uni o'zgartira olmaydi.</div></div></div>`;
    const safe = async f => { try { return await f(); } catch (e) { return null; } };
    const K = [
      ['Employees', () => PERMS.section('employees') ? API.count('employees') : null, ''],
      ['Active Employees', () => PERMS.section('employees') ? API.count('employees', { eq: { employment_status: 'active' } }) : null, 'ok'],
      ['Courses', () => API.count('courses'), ''],
      ['Questions', () => PERMS.can('question.view') ? API.count('questions') : null, ''],
      ['Evidence Pending', () => PERMS.can('question.view') ? API.count('questions', { in: { evidence_status: ['unknown', 'review_due', 'outdated', 'superseded', 'conflicting'] } }) : null, 'warn'],
      ['Evidence Reviewed', () => PERMS.can('question.view') ? API.count('questions', { eq: { evidence_status: 'current' } }) : null, 'ok'],
      ['Review Due', () => PERMS.can('question.view') ? API.count('questions', { or: `evidence_status.eq.review_due,evidence_review_due_at.lte.${new Date().toISOString()}` }) : null, 'warn'],
      ['Eligible Questions', async () => { const m = await API.rpc('question_meta'); return Array.isArray(m) ? m.length : 0; }, ''],
      ['Exams', () => PERMS.can('exam.view') ? API.count('exam_configs') : null, ''],
      ['Certificates', () => API.count('certificates'), ''],
    ];
    const vals = await Promise.all(K.map(k => safe(k[1])));
    if (!ctx.alive()) return;
    el.querySelector('[data-kpis]').innerHTML = K.map((k, i) => `<div class="kpi ${vals[i] === 0 && k[0] === 'Eligible Questions' ? 'bad' : k[2]}" data-kpi="${esc(k[0])}"><div class="v">${vals[i] === null ? '—' : vals[i]}</div><div class="l">${esc(k[0])}${vals[i] === null ? ' <span class="tiny">(ruxsat yo\'q)</span>' : ''}</div></div>`).join('');
    if (PERMS.can('question.view')) {
      const st = ['unknown', 'review_due', 'outdated', 'superseded', 'conflicting', 'current'];
      const c = await Promise.all(st.map(s => safe(() => API.count('questions', { eq: { evidence_status: s } }))));
      if (ctx.alive()) el.querySelector('[data-ev]').innerHTML = st.map((s, i) => `<div class="row between" style="padding:4px 0">${badge('evidence', s)}<b>${c[i] ?? '—'}</b></div>`).join('') +
        (vals[7] === 0 ? `<div class="note warn" style="margin-top:8px">Hozir imtihonga yaroqli savol yo'q. Birinchi navbat: klinik bo'lmagan kurslar (Ethics → Communication → Reception → Sales) evidence review'i.</div>` : '');
    } else el.querySelector('[data-ev]').innerHTML = '<div class="small muted">Savollar banki sizning rolingizga ochiq emas.</div>';
  });

  // ---------------- Audit Logs ----------------
  ADMIN.route('/audit', 'audit', (el, ctx) => listPage(el, ctx, {
    title: 'Audit Logs', id: 'audit', sub: 'Faqat server yozgan jurnal (audit_logs). Klient tomonidagi faollik tarixi bu yerda ko\'rsatilmaydi.',
    filters: [{ key: 's', type: 'search', label: 'Amal yoki obyekt ID bo\'yicha qidirish' },
      { key: 'entity', type: 'select', label: 'Obyekt', options: ['employee', 'department', 'position', 'specialty', 'permission', 'question_evidence', 'question_reviews', 'evidence_sources', 'course_assignments', 'lessons', 'course_modules'].map(x => [x, x]) }],
    load: q => API.list('audit_logs', { select: 'id,actor_id,actor_role,action,entity,entity_id,created_at,new_value', eq: { entity: q.entity }, search: { cols: ['action', 'entity_id'], q: q.s }, order: ['created_at', false], page: q.page, size: q.size }),
    columns: [{ h: 'Vaqt', r: x => fmtDT(x.created_at) }, { h: 'Amal', r: x => `<b>${esc(x.action)}</b>` }, { h: 'Obyekt', r: x => `${esc(x.entity)} <div class="sub mono">${esc(x.entity_id || '')}</div>` },
      { h: 'Kim', r: x => `${esc(PERMS.ROLE_LABEL[x.actor_role] || x.actor_role || 'tizim')}<div class="sub mono">${esc((x.actor_id || '').slice(0, 8))}</div>` },
      { h: 'Izoh', r: x => esc(x.new_value && x.new_value.reason ? x.new_value.reason : '') }],
    empty: 'Audit yozuvlari yo\'q',
  }));

  window.ADMINLIB = { listPage, lookup, clearCache };
})();
