/* Tashkilot: Xodimlar (ro'yxat + profil, faqat Deactivate — DELETE yo'q) va Bo'limlar / Lavozimlar / Mutaxassisliklar. */
(function () {
  const { esc, badge, table, empty, errorBox, skeleton, fmtDT, fmtDate, toast, dialog } = UI;
  const { listPage, lookup, clearCache } = ADMINLIB;
  const name = e => [e.first_name, e.last_name].filter(Boolean).join(' ') || e.employee_code;

  ADMIN.route('/employees', 'employees', async (el, ctx) => {
    const [dep, pos, spec] = await Promise.all([lookup('departments'), lookup('positions'), lookup('specialties')]);
    await listPage(el, ctx, {
      title: 'Xodimlar', id: 'employees', sub: PERMS.role() === 'department_head' ? 'Faqat o\'z bo\'limingiz (server RLS).' : 'Xodimlar o\'chirilmaydi — faqat faolsizlantiriladi (tarix saqlanadi).',
      filters: [{ key: 's', type: 'search', label: 'Ism, familiya yoki xodim kodi' }, { key: 'dep', type: 'select', label: 'Bo\'lim', options: Object.entries(dep) },
        { key: 'pos', type: 'select', label: 'Lavozim', options: Object.entries(pos) }, { key: 'spec', type: 'select', label: 'Mutaxassislik', options: Object.entries(spec) },
        { key: 'st', type: 'select', label: 'Holat', options: Object.entries(UI.LABELS.employment).map(([k, v]) => [k, v[0]]) }],
      load: async q => { const r = await API.list('employees', { select: 'id,employee_code,first_name,last_name,department_id,position_id,specialty_id,employment_status,profile_id,hire_date',
          eq: { department_id: q.dep, position_id: q.pos, specialty_id: q.spec, employment_status: q.st }, search: { cols: ['first_name', 'last_name', 'employee_code'], q: q.s }, order: ['first_name', true], page: q.page, size: q.size });
        const pids = r.rows.map(x => x.profile_id).filter(Boolean);
        const prof = pids.length ? Object.fromEntries((await API.list('profiles', { select: 'id,status,role,email', in: { id: pids }, all: true, count: false }).catch(() => ({ rows: [] }))).rows.map(p => [p.id, p])) : {};
        r.rows.forEach(x => { x._p = prof[x.profile_id]; }); return r; },
      href: x => '#/employees/' + x.id,
      columns: [{ h: 'Xodim', r: x => `<b>${esc(name(x))}</b><div class="sub mono">${esc(x.employee_code)}</div>` }, { h: 'Bo\'lim', r: x => esc(dep[x.department_id] || '—') },
        { h: 'Lavozim', r: x => esc(pos[x.position_id] || '—') }, { h: 'Mutaxassislik', r: x => esc(spec[x.specialty_id] || '—') },
        { h: 'Holat', r: x => badge('employment', x.employment_status) + (x._p ? ' ' + badge('account', x._p.status) : x.profile_id ? '' : ' <span class="tiny">akkauntsiz</span>') },
        { h: 'Rol', r: x => x._p ? esc(PERMS.ROLE_LABEL[x._p.role] || x._p.role) : '—' }],
      empty: 'Xodim topilmadi',
    });
  });

  const ETABS = [['overview', 'Overview'], ['courses', 'Courses'], ['exams', 'Exams'], ['assessments', 'Assessments'], ['skills', 'Skills'], ['certificates', 'Certificates'], ['activity', 'Activity'], ['performance', 'Performance']];
  ADMIN.route('/employees/:id', 'employees', async (el, ctx) => {
    const e = await API.get('employees', 'id', ctx.params.id, '*');
    if (!ctx.alive()) return;
    if (!e) { el.innerHTML = `<div class="card">${empty('Xodim topilmadi yoki ruxsat yo\'q')}</div>`; return; }
    const [dep, pos, spec] = await Promise.all([lookup('departments'), lookup('positions'), lookup('specialties')]);
    const p = e.profile_id ? await API.get('profiles', 'id', e.profile_id, 'id,email,full_name,role,status').catch(() => null) : null;
    if (!ctx.alive()) return;
    ctx.setTitle(name(e));
    const tab = ctx.query.tab || 'overview';
    const self = e.profile_id && e.profile_id === PERMS.state.profile.id;
    const acc = p ? p.status : null;
    const acts = [];
    if (!self && PERMS.can('employee.deactivate') && (e.employment_status === 'active' || e.employment_status === 'on_leave' || acc === 'active')) acts.push(`<button class="btn red" data-act="deactivate">Deactivate</button>`);
    if (!self && PERMS.can('employee.edit') && (e.employment_status === 'inactive' || ['inactive', 'deactivated'].includes(acc))) acts.push(`<button class="btn green" data-act="reactivate">Qayta faollashtirish</button>`);
    el.innerHTML = `<div class="adm-h"><div><div class="sub"><a href="#/employees">← Xodimlar</a></div><h1>${esc(name(e))}</h1>
      <div class="row">${badge('employment', e.employment_status)} ${p ? badge('account', p.status) : '<span class="badge">akkauntsiz</span>'} ${p ? `<span class="badge">${esc(PERMS.ROLE_LABEL[p.role] || p.role)}</span>` : ''}</div></div>
      <div class="act">${acts.join('')}</div></div>
      <div class="tabs">${ETABS.map(([k, l]) => `<a href="#/employees/${e.id}?tab=${k}" class="${tab === k ? 'on' : ''}">${l}</a>`).join('')}</div><div data-body>${skeleton(3)}</div>`;
    el.querySelectorAll('[data-act]').forEach(b => b.onclick = () => setStatus(e, p, b.getAttribute('data-act')));
    const body = el.querySelector('[data-body]');
    try {
      if (tab === 'overview') body.innerHTML = `<div class="card"><dl class="kv"><dt>Xodim kodi</dt><dd class="mono">${esc(e.employee_code)}</dd><dt>Bo'lim</dt><dd>${esc(dep[e.department_id] || '—')}</dd>
        <dt>Lavozim</dt><dd>${esc(pos[e.position_id] || '—')}</dd><dt>Mutaxassislik</dt><dd>${esc(spec[e.specialty_id] || '—')}</dd><dt>Ishga qabul</dt><dd>${fmtDate(e.hire_date)}</dd>
        <dt>Ishdan ketgan</dt><dd>${fmtDate(e.termination_date)}</dd><dt>Email</dt><dd>${esc(p ? p.email : '—')}</dd><dt>Yangilangan</dt><dd>${fmtDT(e.updated_at)}</dd></dl>
        <div class="note" style="margin-top:12px">Xodim yozuvi o'chirilmaydi. Deactivate qilinganda tizimga kirish va imtihon yopiladi; urinishlar, natijalar va sertifikatlar o'zgarishsiz saqlanadi.</div></div>`;
      else if (tab === 'courses') { const r = await API.list('course_assignments', { select: 'id,course_id,status,assigned_at,due_date,completed_at', eq: { employee_id: e.id }, order: ['assigned_at', false], all: true, count: false });
        const c = await lookup('courses', 'title');
        body.innerHTML = `<div class="card">${table(r.rows, [{ h: 'Kurs', r: x => esc(c[x.course_id] || x.course_id) }, { h: 'Holat', r: x => badge('generic', x.status) }, { h: 'Tayinlangan', r: x => fmtDate(x.assigned_at) }, { h: 'Muddat', r: x => fmtDate(x.due_date) }, { h: 'Tugallangan', r: x => fmtDate(x.completed_at) }], { empty: 'Kurs tayinlanmagan' })}</div>`; }
      else if (tab === 'exams' || tab === 'performance') {
        const r = e.profile_id ? await API.list('exam_attempts', { select: 'id,course_id,kind,score,passed,is_preview,started_at,finished_at', eq: { user_id: e.profile_id }, order: ['started_at', false], all: true, count: false }) : { rows: [] };
        const c = await lookup('courses', 'title'); const fin = r.rows.filter(x => x.finished_at && !x.is_preview);
        if (tab === 'exams') body.innerHTML = `<div class="card">${table(r.rows, [{ h: 'Kurs', r: x => esc(c[x.course_id] || x.course_id) + (x.is_preview ? ' <span class="badge">preview</span>' : '') }, { h: 'Tur', r: x => esc(x.kind) },
          { h: 'Ball', r: x => x.score === null ? '—' : Math.round(x.score) + '%' }, { h: 'Natija', r: x => x.finished_at ? (x.passed ? '<span class="badge b-green">O\'tdi</span>' : '<span class="badge b-red">O\'tmadi</span>') : '<span class="badge b-amber">Jarayonda</span>' },
          { h: 'Sana', r: x => fmtDT(x.finished_at || x.started_at) }], { empty: 'Imtihon urinishlari yo\'q' })}<div class="tiny">Javoblar bu ro'yxatda yuklanmaydi; urinishlar tarixiy yozuv sifatida o'zgarmaydi.</div></div>`;
        else { const avg = fin.length ? Math.round(fin.reduce((s, x) => s + (+x.score || 0), 0) / fin.length) : null; const pass = fin.length ? Math.round(100 * fin.filter(x => x.passed).length / fin.length) : null;
          body.innerHTML = `<div class="kpis"><div class="kpi"><div class="v">${fin.length}</div><div class="l">Yakunlangan imtihonlar</div></div><div class="kpi"><div class="v">${avg === null ? '—' : avg + '%'}</div><div class="l">O'rtacha ball</div></div><div class="kpi"><div class="v">${pass === null ? '—' : pass + '%'}</div><div class="l">O'tish ulushi</div></div></div><div class="note">Ko'rsatkichlar faqat server urinishlari asosida hisoblanadi (preview urinishlari hisobga olinmaydi).</div>`; } }
      else if (tab === 'certificates') { const r = e.profile_id ? await API.list('certificates', { select: 'id,course_title,score,issued_at,expires_at,revoked', eq: { user_id: e.profile_id }, order: ['issued_at', false], all: true, count: false }) : { rows: [] };
        body.innerHTML = `<div class="card">${table(r.rows, [{ h: 'Sertifikat', r: x => `<span class="mono">${esc(x.id)}</span>` }, { h: 'Kurs', r: x => esc(x.course_title) }, { h: 'Ball', r: x => x.score === null ? '—' : Math.round(x.score) + '%' },
          { h: 'Berilgan', r: x => fmtDate(x.issued_at) }, { h: 'Amal qiladi', r: x => fmtDate(x.expires_at) }, { h: 'Holat', r: x => x.revoked ? '<span class="badge b-red">Bekor qilingan</span>' : '<span class="badge b-green">Amalda</span>' }], { empty: 'Sertifikat yo\'q' })}
          <div class="tiny">Sertifikatdagi ism berilgan paytdagi holatda saqlanadi va profil o'zgarishi bilan o'zgarmaydi.</div></div>`; }
      else if (tab === 'activity') { if (!PERMS.can('audit.view')) { body.innerHTML = UI.denied('Audit faolligi'); return; }
        const r = await API.list('audit_logs', { select: 'action,actor_role,created_at,new_value', eq: { entity_id: e.id }, order: ['created_at', false], size: 50, count: false });
        body.innerHTML = `<div class="card">${table(r.rows, [{ h: 'Vaqt', r: x => fmtDT(x.created_at) }, { h: 'Amal', r: x => esc(x.action) }, { h: 'Kim', r: x => esc(PERMS.ROLE_LABEL[x.actor_role] || x.actor_role || 'tizim') }, { h: 'Sabab', r: x => esc(x.new_value && x.new_value.reason || '') }], { empty: 'Faollik yozuvi yo\'q' })}</div>`; }
      else body.innerHTML = `<div class="card"><div class="note warn">${tab === 'skills' ? 'Skills' : 'Assessments (amaliy baholash)'} hozircha xodim ilovasining hujjat (docs) qatlamida saqlanadi. Server jadvallariga o'tkazish 006c migratsiyasida taklif qilingan — shundan keyin bu yerda ko'rsatiladi.</div></div>`;
    } catch (e2) { if (ctx.alive()) body.innerHTML = errorBox(API.friendly(e2)); }
  });

  async function setStatus(e, p, act) {
    const fields = act === 'deactivate'
      ? [{ name: 'status', label: 'Yangi holat', type: 'select', value: 'inactive', options: [['inactive', 'Inactive — vaqtincha (HR qayta faollashtira oladi)'], ['deactivated', 'Deactivated — doimiy (qayta faollashtirish faqat Super Admin)']] },
         { name: 'reason', label: 'Sabab', type: 'textarea', required: true }, { name: 'ok', type: 'check', label: 'Xodim yozuvi, urinishlar va sertifikatlar saqlanadi; tizimga kirish yopiladi', required: true }]
      : [{ name: 'reason', label: 'Izoh', type: 'textarea' }];
    const r = await dialog({ title: act === 'deactivate' ? 'Xodimni faolsizlantirish' : 'Qayta faollashtirish', body: act === 'deactivate' ? 'O\'chirish (DELETE) yo\'q — faqat holat o\'zgaradi. Amal server audit jurnaliga yoziladi.' : 'Akkaunt qayta faollashtiriladi.', fields, danger: act === 'deactivate', okText: act === 'deactivate' ? 'Faolsizlantirish' : 'Faollashtirish' });
    if (!r) return;
    try { await API.rpc('set_employee_status', { p_employee: e.id, p_status: act === 'deactivate' ? r.status : 'active', p_reason: r.reason || null }); toast('Holat yangilandi'); ADMIN.render(); }
    catch (err) { toast(API.friendly(err).message, true); }
  }

  // ---------- Bo'limlar / Lavozimlar / Mutaxassisliklar ----------
  const ORG = { departments: ['Bo\'limlar', 'department.manage', 'department.view'], positions: ['Lavozimlar', 'position.manage', 'position.view'], specialties: ['Mutaxassisliklar', 'specialty.manage', 'specialty.view'] };
  ADMIN.route('/org/:kind', 'organization', async (el, ctx) => {
    const kind = ctx.params.kind; const cfg = ORG[kind]; if (!cfg) { el.innerHTML = `<div class="card">${empty('Bo\'lim topilmadi')}</div>`; return; }
    const tabs = `<div class="tabs">${Object.entries(ORG).map(([k, v]) => `<a href="#/org/${k}" class="${k === kind ? 'on' : ''}">${v[0]}</a>`).join('')}</div>`;
    const canManage = PERMS.can(cfg[1]);
    const h = await listPage(el, ctx, {
      title: cfg[0], id: 'org-' + kind, top: tabs, sub: 'O\'chirish yo\'q — keraksiz yozuv "Inactive" qilinadi (tarixiy bog\'lanishlar saqlanadi).',
      actions: canManage ? `<button class="btn primary" data-act="new">+ Qo'shish</button>` : '',
      filters: [{ key: 's', type: 'search', label: 'Nomi yoki kodi' }, { key: 'st', type: 'select', label: 'Holat', options: [['active', 'Active'], ['inactive', 'Inactive']] }],
      load: q => API.list(kind, { select: '*', eq: { status: q.st }, search: { cols: ['name', 'code'], q: q.s }, order: ['name', true], page: q.page, size: q.size }),
      columns: [{ h: 'Nomi', r: x => `<b>${esc(x.name)}</b>${x.description ? `<div class="sub">${esc(x.description)}</div>` : ''}` }, { h: 'Kod', r: x => `<span class="mono">${esc(x.code)}</span>` },
        ...(kind === 'positions' ? [{ h: 'Oila / akademiya', r: x => esc([x.family, x.academy].filter(Boolean).join(' / ') || '—') }] : []),
        { h: 'Holat', r: x => badge('generic', x.status) }, ...(canManage ? [{ h: '', r: x => `<button class="btn sm" data-edit="${esc(x.id)}">Tahrirlash</button>` }] : [])],
      empty: 'Yozuv yo\'q', onReady: (listEl, r) => listEl.querySelectorAll('[data-edit]').forEach(b => b.onclick = () => edit(kind, r.rows.find(x => x.id === b.getAttribute('data-edit')))),
    });
    const nb = el.querySelector('[data-act="new"]'); if (nb) nb.onclick = () => edit(kind, null);
    async function edit(k, row) {
      const r = await dialog({ title: row ? 'Tahrirlash' : 'Qo\'shish', fields: [{ name: 'name', label: 'Nomi', required: true, value: row && row.name }, { name: 'code', label: 'Kod (A-Z, 0-9, _ -)', required: true, value: row && row.code, pattern: '[A-Z0-9_-]{2,32}' },
        { name: 'description', label: 'Tavsif', type: 'textarea', value: row && row.description }, { name: 'status', label: 'Holat', type: 'select', value: row ? row.status : 'active', options: [['active', 'Active'], ['inactive', 'Inactive']] }], okText: 'Saqlash' });
      if (!r) return;
      try { const patch = { name: r.name, code: r.code, description: r.description || null, status: r.status };
        if (row) await API.update(k, 'id', row.id, patch); else await API.insert(k, { ...patch, org_id: PERMS.state.profile.org_id });
        clearCache(); toast('Saqlandi'); h.reload(); } catch (e) { toast(API.friendly(e).message, true); }
    }
  });
})();
