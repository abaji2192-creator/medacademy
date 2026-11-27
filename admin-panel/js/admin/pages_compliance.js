/* Phase 3 (007e + 007d): Training Compliance, Competency Matrix, bo'lim matritsasi va in-app Notifications.
   Barcha foizlar va statuslar serverda hisoblanadi (employee_training_compliance / employee_competency_matrix / department_compliance_matrix).
   Frontend hech qanday "ball" o'ylab topmaydi: kompetensiya statusi faqat achieved / not_achieved / not_assessed. */
(function () {
  const { esc, badge, table, empty, errorBox, skeleton, fmtDate, fmtDT, toast } = UI;
  const { lookup } = ADMINLIB;
  const tabs = cur => `<div class="tabs">${[['department', 'Bo\'lim matritsasi'], ['employee', 'Xodim bo\'yicha']]
    .map(([k, l]) => `<a href="#/compliance/${k}" class="${k === cur ? 'on' : ''}">${l}</a>`).join('')}</div>`;
  const pct = v => `<div class="row" style="gap:8px;align-items:center"><div class="bar" style="flex:1;min-width:60px"><i style="width:${Math.max(0, Math.min(100, +v || 0))}%"></i></div><b>${esc(v)}%</b></div>`;
  const retryBox = (el, e) => { el.innerHTML = `<div class="card" data-error>${errorBox(API.friendly(e))}<button class="btn sm" data-retry>Qayta urinish</button></div>`;
    el.querySelector('[data-retry]').onclick = () => ADMIN.render(); };
  const isHead = () => PERMS.role() === 'department_head';

  // ---------------- Bo'lim / tashkilot matritsasi ----------------
  ADMIN.route('/compliance/department', 'compliance', async (el, ctx) => {
    ctx.setTitle('Training Compliance');
    const deps = await lookup('departments', 'name');
    const myDep = isHead() ? ((await API.list('employees', { select: 'department_id', eq: { profile_id: PERMS.state.profile.id }, all: true, count: false })).rows[0] || {}).department_id : null;
    const cur = ctx.query.dep || (isHead() ? (myDep || '') : '');
    el.innerHTML = `<div class="adm-h"><div><h1>Training Compliance</h1><div class="sub">Majburiy trening va kompetensiya talablari bajarilishi. Hisob — serverda (007e).</div></div></div>
      ${tabs('department')}<div class="filters"><select data-f="dep" ${isHead() ? 'disabled' : ''}>${isHead() ? '' : '<option value="">Butun tashkilot (bo\'limlar kesimida)</option>'}
      ${Object.entries(deps).map(([k, v]) => `<option value="${esc(k)}" ${k === cur ? 'selected' : ''}>${esc(v)}</option>`).join('')}</select></div><div data-body>${skeleton(5)}</div>`;
    el.querySelector('[data-f=dep]').onchange = e => { ctx.setQuery({ dep: e.target.value }); ADMIN.render(); };
    const body = el.querySelector('[data-body]');
    if (isHead() && !cur) { body.innerHTML = `<div class="card">${empty('Bo\'limingiz aniqlanmadi', 'Department Head faqat o\'z bo\'limini ko\'radi')}</div>`; return; }
    try {
      const m = await API.rpc('department_compliance_matrix', { p_department: cur || null });
      if (!ctx.alive()) return;
      const t = m.training || {}, c = m.competency || {};
      const kpi = (k, v, l, cls = '') => `<div class="kpi ${cls}" data-kpi="${k}"><div class="v">${esc(v ?? 0)}</div><div class="l">${l}</div></div>`;
      let html = `<div class="card"><div class="row between"><h3>${esc(cur ? (deps[cur] || 'Bo\'lim') : 'Butun tashkilot')}</h3><span class="badge" data-scope>${m.scope === 'organization' ? 'Tashkilot' : 'Bo\'lim'} · ${esc(m.employees)} xodim</span></div>
        <div class="kpis">${kpi('compliance_percent', (t.compliance_percent ?? 0) + '%', 'Trening compliance', 'green')}${kpi('completed', t.completed, 'Tugallangan')}${kpi('total_required', t.total_required, 'Majburiy jami')}
        ${kpi('overdue', t.overdue, 'Muddati o\'tgan', 'red')}${kpi('fully', t.fully_compliant_employees, 'To\'liq bajargan xodim')}
        ${kpi('c_achieved', c.achieved, 'Kompetensiya bajarilgan', 'green')}${kpi('c_gap', c.not_achieved, 'Bajarilmagan', 'red')}${kpi('c_nas', c.not_assessed, 'Baholanmagan', 'amber')}</div></div>`;
      if (m.departments) html += `<div class="card"><h3>Bo'limlar kesimida</h3>${table(m.departments, [
        { h: 'Bo\'lim', r: d => d.department_id ? `<a href="#/compliance/department?dep=${d.department_id}">${esc(d.department || '—')}</a>` : '<span class="muted">Bo\'limsiz</span>' },
        { h: 'Xodim', r: d => esc(d.employees) }, { h: 'Compliance', r: d => pct(d.compliance_percent) }, { h: 'Tugallangan / jami', r: d => `${esc(d.completed)} / ${esc(d.total_required)}` },
        { h: 'Muddati o\'tgan', r: d => +d.overdue ? `<b style="color:#b91c1c">${esc(d.overdue)}</b>` : '0' },
        { h: 'Kompetensiya', r: d => `<span class="badge b-green">${esc(d.competency_achieved)}</span> <span class="badge b-red">${esc(d.competency_not_achieved)}</span> <span class="badge b-amber">${esc(d.competency_not_assessed)}</span>` }],
        { id: 'dept_matrix', empty: 'Bo\'lim yo\'q' })}</div>`;
      if (m.rows) html += `<div class="card"><h3>Xodimlar</h3>${table(m.rows, [
        { h: 'Xodim', r: x => `<a href="#/compliance/employee/${x.employee_id}"><b>${esc(x.employee_name || x.employee_code)}</b></a><div class="sub mono">${esc(x.employee_code || '')}</div>` },
        { h: 'Compliance', r: x => pct(x.training.compliance_percent) }, { h: 'Tugallangan / jami', r: x => `${x.training.completed} / ${x.training.total_required}` },
        { h: 'Jarayonda', r: x => x.training.in_progress }, { h: 'Muddati o\'tgan', r: x => +x.training.overdue ? `<b style="color:#b91c1c">${x.training.overdue}</b>` : '0' },
        { h: 'Kompetensiya', r: x => `<span class="badge b-green" title="bajarilgan">${x.competency.achieved}</span> <span class="badge b-red" title="bajarilmagan">${x.competency.not_achieved}</span> <span class="badge b-amber" title="baholanmagan">${x.competency.not_assessed}</span>` }],
        { id: 'dept_rows', empty: 'Bu bo\'limda faol xodim yo\'q' })}</div>`;
      body.innerHTML = html;
    } catch (e) { if (ctx.alive()) retryBox(body, e); }
  });

  // ---------------- Xodim tanlash ----------------
  ADMIN.route('/compliance/employee', 'compliance', async (el, ctx) => {
    ctx.setTitle('Xodim compliance');
    const s = ctx.query.s || '';
    el.innerHTML = `<div class="adm-h"><div><h1>Xodim bo'yicha</h1><div class="sub">Trening compliance va kompetensiya matritsasi — xodimni tanlang.</div></div></div>${tabs('employee')}
      <div class="filters"><input type="search" data-f="s" placeholder="Ism yoki kod" value="${esc(s)}"></div><div class="card" style="padding:6px 8px" data-list>${skeleton(4)}</div>`;
    const inp = el.querySelector('[data-f=s]'); let tm;
    inp.oninput = () => { clearTimeout(tm); tm = setTimeout(() => { ctx.setQuery({ s: inp.value, page: '' }); ADMIN.render(); }, 350); };
    const list = el.querySelector('[data-list]');
    try {
      const page = +(ctx.query.page || 0);
      const r = await API.list('employees', { select: 'id,first_name,last_name,employee_code,department_id,employment_status', search: { cols: ['first_name', 'last_name', 'employee_code'], q: s }, order: ['last_name', true], page, size: 25 });
      const deps = await lookup('departments', 'name');
      if (!ctx.alive()) return;
      list.innerHTML = table(r.rows, [{ h: 'Xodim', r: x => `<a href="#/compliance/employee/${x.id}"><b>${esc([x.first_name, x.last_name].filter(Boolean).join(' ') || x.employee_code)}</b></a><div class="sub mono">${esc(x.employee_code || '')}</div>` },
        { h: 'Bo\'lim', r: x => esc(deps[x.department_id] || '—') }, { h: 'Holat', r: x => badge('generic', x.employment_status) }], { id: 'cmp_emps', empty: 'Xodim topilmadi' }) + UI.pager(page, 25, r.count);
      list.addEventListener('click', e => { const b = e.target.closest('[data-page]'); if (b && !b.disabled) { ctx.setQuery({ page: b.getAttribute('data-page') }); ADMIN.render(); } });
    } catch (e) { if (ctx.alive()) retryBox(list, e); }
  });

  // ---------------- Xodim tafsiloti: trening + kompetensiya ----------------
  ADMIN.route('/compliance/employee/:id', 'compliance', async (el, ctx) => {
    const id = ctx.params.id;
    el.innerHTML = `<div class="adm-h"><div><div class="sub"><a href="#/compliance/employee">← Xodimlar</a></div><h1 data-name>Xodim</h1><div class="sub" data-meta></div></div></div>
      <div data-tr>${skeleton(4)}</div><div data-cm>${skeleton(3)}</div>`;
    const [tr, cm] = await Promise.allSettled([API.rpc('employee_training_compliance', { p_employee: id }), API.rpc('employee_competency_matrix', { p_employee: id })]);
    if (!ctx.alive()) return;
    const emp = (tr.value || cm.value || {}).employee;
    if (emp) { ctx.setTitle(emp.employee_name || 'Xodim'); el.querySelector('[data-name]').textContent = emp.employee_name || emp.employee_code;
      el.querySelector('[data-meta]').innerHTML = [emp.employee_code, emp.department, emp.position, emp.specialty].filter(Boolean).map(esc).join(' · '); }
    const trEl = el.querySelector('[data-tr]'), cmEl = el.querySelector('[data-cm]');
    if (tr.status === 'rejected') retryBox(trEl, tr.reason); else {
      const s = tr.value.summary;
      trEl.innerHTML = `<div class="card"><div class="row between"><h3>Trening compliance</h3><span data-tpct>${pct(s.compliance_percent)}</span></div>
        <div class="small muted">Majburiy: <b>${s.total_required}</b> · Tugallangan: <b>${s.completed}</b> · Jarayonda: ${s.in_progress} · Boshlanmagan: ${s.not_started} · Muddati o'tgan: <b style="color:#b91c1c">${s.overdue}</b> · Bekor qilingan: ${s.cancelled}</div>
        ${table(tr.value.courses, [{ h: 'Kurs', r: c => `<b>${esc(c.course_title || c.course_id)}</b>` }, { h: 'Holat', r: c => badge('p3', c.status) },
          { h: 'Progress', r: c => pct(c.progress_percent) + `<div class="tiny">${c.completed_required_lessons} / ${c.total_required_lessons} majburiy dars</div>` },
          { h: 'Muddat', r: c => fmtDate(c.due_date) }, { h: 'Tugallangan', r: c => fmtDate(c.completed_at) }], { id: 'emp_courses', empty: 'Majburiy kurs tayinlanmagan' })}</div>`;
    }
    if (cm.status === 'rejected') retryBox(cmEl, cm.reason); else {
      const s = cm.value.summary;
      cmEl.innerHTML = `<div class="card"><div class="row between"><h3>Kompetensiya matritsasi</h3><span class="small">Talab: <b>${s.required}</b> · <span class="badge b-green">${s.achieved} bajarilgan</span> <span class="badge b-red">${s.not_achieved} bajarilmagan</span> <span class="badge b-amber">${s.not_assessed} baholanmagan</span></span></div>
        ${table(cm.value.competencies, [{ h: 'Ko\'nikma', r: c => `<b>${esc(c.skill_name)}</b><div class="sub mono">${esc(c.skill_code)}</div>` },
          { h: 'Talab', r: c => `<b>${c.required_level}</b> / ${c.max_level}` }, { h: 'Joriy daraja', r: c => c.current_level == null ? '<span class="muted">—</span>' : `<b>${c.current_level}</b>` },
          { h: 'Holat', r: c => badge('p3', c.status) }, { h: 'Oxirgi baholash', r: c => fmtDT(c.latest_assessment_at) },
          { h: 'Manba', r: c => (c.requirements || []).map(q => `<span class="badge" title="daraja ${esc(q.required_level)}">${esc(q.target_type)}</span>`).join(' ') }],
          { id: 'emp_competencies', empty: 'Bu xodim uchun kompetensiya talabi yo\'q' })}</div>`;
    }
  });
  ADMIN.route('/compliance', 'compliance', async () => { location.replace('#/compliance/department'); });

  // ---------------- Notifications (007d) ----------------
  const NT = { course_assigned: 'Kurs tayinlandi', course_completed: 'Kurs tugallandi', learning_path_assigned: 'Learning path', skill_assessment_created: 'Baholash',
    competency_achieved: 'Kompetensiya', certificate_issued: 'Sertifikat' };
  async function refreshBell() {
    const b = document.querySelector('[data-bell-count]'); if (!b) return;
    try { const n = await API.rpc('unread_notification_count', {}); b.textContent = n > 99 ? '99+' : String(n || 0); b.hidden = !n; } catch (e) { b.hidden = true; }
  }
  window.NOTIF = { refreshBell };
  ADMIN.route('/notifications', 'notifications', async (el, ctx) => {
    ctx.setTitle('Bildirishnomalar');
    const unread = ctx.query.u === '1';
    el.innerHTML = `<div class="adm-h"><div><h1>Bildirishnomalar</h1><div class="sub">Faqat sizga tegishli bildirishnomalar (007d). O'qilgan deb belgilash — faqat RPC orqali.</div></div>
      <div class="act"><button class="btn" data-all>Barchasini o'qilgan qilish</button></div></div>
      <div class="chips"><button class="chip ${unread ? '' : 'on'}" data-u="">Barchasi</button><button class="chip ${unread ? 'on' : ''}" data-u="1">O'qilmagan</button></div>
      <div class="card" style="padding:6px 8px" data-list>${skeleton(4)}</div><div class="pager"><button class="btn sm" data-more hidden>Yana yuklash</button></div>`;
    const list = el.querySelector('[data-list]'), more = el.querySelector('[data-more]');
    let rows = [], cursor = null;
    el.querySelectorAll('[data-u]').forEach(b => b.onclick = () => { ctx.setQuery({ u: b.getAttribute('data-u') }); ADMIN.render(); });
    const draw = () => {
      list.innerHTML = rows.length ? rows.map(n => `<div class="notif ${n.read_at ? '' : 'unread'}" data-notif="${n.id}" style="padding:8px;border-bottom:1px solid var(--line,#e5e7eb)">
        <div class="row between"><b>${esc(n.title)}</b><span class="tiny">${fmtDT(n.created_at)}</span></div>
        <div class="small">${esc(n.body || '')}</div><div class="row between"><span class="badge">${esc(NT[n.notification_type] || n.notification_type)}</span>
        <button class="btn sm" data-toggle="${n.id}" data-read="${n.read_at ? '0' : '1'}">${n.read_at ? 'O\'qilmagan qilish' : 'O\'qildi'}</button></div></div>`).join('')
        : empty(unread ? 'O\'qilmagan bildirishnoma yo\'q' : 'Bildirishnoma yo\'q');
    };
    const load = async () => {
      try {
        const page = await API.rpc('my_notifications', { p_limit: 20, p_before_created: cursor ? cursor.created_at : null, p_before_id: cursor ? cursor.id : null, p_unread_only: unread });
        if (!ctx.alive()) return;
        rows = rows.concat(page || []); cursor = rows[rows.length - 1] || null; more.hidden = !page || page.length < 20; draw();
      } catch (e) { if (ctx.alive()) retryBox(list, e); }
    };
    more.onclick = load;
    list.addEventListener('click', async e => {
      const b = e.target.closest('[data-toggle]'); if (!b) return;
      try { await API.rpc('mark_notification_read', { p_id: b.getAttribute('data-toggle'), p_read: b.getAttribute('data-read') === '1' });
        const n = rows.find(x => x.id === b.getAttribute('data-toggle')); n.read_at = b.getAttribute('data-read') === '1' ? new Date().toISOString() : null;
        if (unread && n.read_at) rows = rows.filter(x => x !== n); draw(); refreshBell(); } catch (err) { toast(API.friendly(err).message, true); }
    });
    el.querySelector('[data-all]').onclick = async () => {
      try { const n = await API.rpc('mark_all_notifications_read', {}); toast(`${n || 0} ta bildirishnoma o'qilgan deb belgilandi`); refreshBell(); ADMIN.render(); } catch (err) { toast(API.friendly(err).message, true); }
    };
    await load(); refreshBell();
  });
})();
