/* Phase 3 (007a / 007b): Learning Paths (apply / reapply / cancel — faqat RPC) va Course Progress (course_progress_summary).
   Hisob-kitob (status, progress %) faqat serverda: frontend backend qaytargan qiymatni ko'rsatadi, o'zi hisoblamaydi. */
(function () {
  const { esc, badge, table, empty, errorBox, skeleton, fmtDate, fmtDT, toast, dialog } = UI;
  const { listPage, lookup } = ADMINLIB;
  UI.LABELS.p3 = {
    active: ['Faol', 'b-green'], cancelled: ['Bekor qilingan', ''], not_started: ['Boshlanmagan', ''], in_progress: ['Jarayonda', 'b-blue'],
    completed: ['Tugallangan', 'b-green'], overdue: ['Muddati o\'tgan', 'b-red'], assigned: ['Tayinlangan', ''],
    achieved: ['Bajarilgan', 'b-green'], not_achieved: ['Bajarilmagan', 'b-red'], not_assessed: ['Baholanmagan', 'b-amber'],
    published: ['Published', 'b-green'], draft: ['Draft', ''], archived: ['Arxiv', ''],
  };
  const TARGETS = [['employee', 'Xodim'], ['department', 'Bo\'lim'], ['position', 'Lavozim'], ['specialty', 'Mutaxassislik'], ['role', 'Rol']];
  const TLABEL = Object.fromEntries(TARGETS);
  const ROLES = ['employee', 'department_head', 'instructor', 'hr', 'education_manager', 'medical_reviewer', 'content_author'];
  const learnTabs = cur => `<div class="tabs">${[['paths', 'Learning Paths'], ['progress', 'Course Progress']].filter(([k]) => PERMS.section(k === 'paths' ? 'learning_paths' : 'progress'))
    .map(([k, l]) => `<a href="#/learning/${k}" class="${k === cur ? 'on' : ''}">${l}</a>`).join('')}</div>`;
  const pct = v => `<div class="row" style="gap:8px;align-items:center"><div class="bar" style="flex:1;min-width:60px"><i style="width:${Math.max(0, Math.min(100, +v || 0))}%"></i></div><b>${esc(v)}%</b></div>`;

  // Nishon nomlari (lookup'lar keshlanadi; xodimlar — faqat kerakli ID'lar, bitta so'rov)
  async function targetNames(rows) {
    const [deps, pos, spec] = await Promise.all([lookup('departments', 'name'), lookup('positions', 'name'), lookup('specialties', 'name')]);
    const empIds = [...new Set(rows.filter(r => r.target_type === 'employee' && r.employee_id).map(r => r.employee_id))];
    const em = empIds.length ? Object.fromEntries((await API.list('employees', { select: 'id,first_name,last_name,employee_code', in: { id: empIds }, all: true, count: false })).rows
      .map(e => [e.id, [e.first_name, e.last_name].filter(Boolean).join(' ') || e.employee_code])) : {};
    return r => r.target_type === 'employee' ? (em[r.employee_id] || 'Xodim') : r.target_type === 'department' ? (deps[r.department_id] || '—')
      : r.target_type === 'position' ? (pos[r.position_id] || '—') : r.target_type === 'specialty' ? (spec[r.specialty_id] || '—') : (PERMS.ROLE_LABEL[r.target_role] || r.target_role);
  }

  // ---------------- Learning Paths ro'yxati ----------------
  ADMIN.route('/learning/paths', 'learning_paths', async (el, ctx) => {
    let counts = {};
    await listPage(el, ctx, {
      title: 'Learning Paths', id: 'learning_paths', top: learnTabs('paths'),
      sub: 'O\'quv yo\'nalishlari va ularning tayinlash qoidalari (007b). Tayinlash, qayta qo\'llash va bekor qilish faqat server RPC orqali.',
      filters: [{ key: 's', type: 'search', label: 'Nomi yoki kodi' }, { key: 'st', type: 'select', label: 'Holat', options: [['published', 'Published'], ['draft', 'Draft'], ['archived', 'Arxiv']] }],
      load: async q => {
        const r = await API.list('learning_paths', { select: 'id,code,title,status,updated_at', eq: { status: q.st }, search: { cols: ['title', 'code'], q: q.s }, order: ['title', true], page: q.page, size: q.size });
        const ids = r.rows.map(x => x.id);
        if (ids.length) {
          const [pc, pa] = await Promise.all([API.list('learning_path_courses', { select: 'path_id', in: { path_id: ids }, all: true, count: false }),
            API.list('learning_path_assignments', { select: 'path_id,status', in: { path_id: ids }, all: true, count: false }).catch(() => ({ rows: [] }))]);
          counts = {}; ids.forEach(i => counts[i] = { c: 0, a: 0, x: 0 });
          pc.rows.forEach(x => counts[x.path_id].c++); pa.rows.forEach(x => counts[x.path_id][x.status === 'active' ? 'a' : 'x']++);
        }
        return r;
      },
      href: x => '#/learning/paths/' + x.id,
      columns: [{ h: 'Yo\'nalish', r: x => `<b>${esc(x.title)}</b><div class="sub mono">${esc(x.code)}</div>` }, { h: 'Holat', r: x => badge('p3', x.status) },
        { h: 'Kurslar', r: x => `<b>${(counts[x.id] || {}).c || 0}</b>` }, { h: 'Faol qoidalar', r: x => `<b data-active>${(counts[x.id] || {}).a || 0}</b>` },
        { h: 'Bekor qilingan', r: x => `${(counts[x.id] || {}).x || 0}` }],
      empty: 'Learning path yo\'q',
    });
  });

  // ---------------- Learning Path tafsiloti ----------------
  ADMIN.route('/learning/paths/:id', 'learning_paths', async (el, ctx) => {
    const id = ctx.params.id;
    const p = await API.get('learning_paths', 'id', id, 'id,code,title,description,status');
    if (!ctx.alive()) return;
    if (!p) { el.innerHTML = `<div class="card">${empty('Learning path topilmadi yoki ruxsat yo\'q')}</div>`; return; }
    ctx.setTitle(p.title);
    const [pc, rules, courses] = await Promise.all([
      API.list('learning_path_courses', { select: 'course_id,order_index,is_required', eq: { path_id: id }, order: ['order_index', true], all: true, count: false }),
      API.list('learning_path_assignments', { select: 'id,target_type,employee_id,department_id,position_id,specialty_id,target_role,status,due_date,created_at,updated_at,cancelled_at,cancel_reason', eq: { path_id: id }, order: ['created_at', false], all: true, count: false }),
      lookup('courses', 'title')]);
    if (!ctx.alive()) return;
    const nameOf = await targetNames(rules.rows);
    const canManage = PERMS.can('learning_path.manage');
    el.innerHTML = `<div class="adm-h"><div><div class="sub"><a href="#/learning/paths">← Learning Paths</a></div><h1>${esc(p.title)}</h1><div class="row">${badge('p3', p.status)} <span class="small mono">${esc(p.code)}</span></div></div>
      <div class="act">${canManage && p.status === 'published' ? '<button class="btn primary" data-act="apply">+ Tayinlash</button>' : ''}</div></div>
      ${p.status !== 'published' ? '<div class="note warn">Faqat published yo\'nalishni tayinlash mumkin (server tekshiradi).</div>' : ''}
      <div class="grid g2"><div class="card"><h3>Kurslar (${pc.rows.length})</h3>${pc.rows.length ? pc.rows.map(c => `<div class="small row between" style="padding:3px 0"><span>${c.order_index}. ${esc(courses[c.course_id] || c.course_id)}</span>${c.is_required ? '<span class="badge b-blue">majburiy</span>' : '<span class="badge">ixtiyoriy</span>'}</div>`).join('') : empty('Kurs yo\'q')}</div>
      <div class="card"><h3>Eslatma</h3><div class="small muted">Qoidani bekor qilish allaqachon yaratilgan kurs tayinlashlarini avtomatik bekor qilmaydi (007b semantikasi). Qayta qo'llash faqat yetishmayotgan tayinlashlarni qo'shadi — dublikat yaratilmaydi.</div></div></div>
      <div class="card"><h3>Tayinlash qoidalari</h3>${table(rules.rows, [
        { h: 'Nishon', r: r => `<span class="badge">${esc(TLABEL[r.target_type] || r.target_type)}</span> <b>${esc(nameOf(r))}</b>` },
        { h: 'Holat', r: r => badge('p3', r.status) + (r.cancel_reason ? `<div class="tiny">${esc(r.cancel_reason)}</div>` : '') },
        { h: 'Muddat', r: r => fmtDate(r.due_date) }, { h: 'Yaratilgan', r: r => fmtDT(r.created_at) }, { h: 'Yangilangan', r: r => fmtDT(r.updated_at) },
        { h: '', r: r => canManage && r.status === 'active' ? `<button class="btn sm" data-reapply="${r.id}">Qayta qo'llash</button> <button class="btn sm red" data-cancel="${r.id}">Bekor qilish</button>` : '' }],
        { id: 'lpa_rules', empty: 'Tayinlash qoidasi yo\'q' })}</div>`;
    const run = async (fn, args, okMsg) => { try { const r = await API.rpc(fn, args); toast(okMsg(r || {})); ADMIN.render(); } catch (e) { toast(API.friendly(e).message, true); } };
    const btn = el.querySelector('[data-act=apply]');
    if (btn) btn.onclick = async () => {
      const t = await dialog({ title: 'Learning path tayinlash', body: 'Avval nishon turini tanlang.', fields: [{ name: 'type', label: 'Nishon turi', type: 'select', options: TARGETS, required: true }], okText: 'Davom etish' });
      if (!t) return;
      let options;
      if (t.type === 'role') options = ROLES.map(r => [r, PERMS.ROLE_LABEL[r] || r]);
      else if (t.type === 'employee') options = (await API.list('employees', { select: 'id,first_name,last_name,employee_code', eq: { employment_status: 'active' }, order: ['last_name', true], all: true, count: false })).rows
        .map(e => [e.id, [e.first_name, e.last_name].filter(Boolean).join(' ') + ' · ' + (e.employee_code || '')]);
      else options = Object.entries(await lookup(t.type === 'department' ? 'departments' : t.type === 'position' ? 'positions' : 'specialties', 'name'));
      if (!options.length) { toast('Tanlash uchun ' + TLABEL[t.type].toLowerCase() + ' topilmadi', true); return; }
      const f = await dialog({ title: 'Tayinlash: ' + TLABEL[t.type], body: `<b>${esc(p.title)}</b>`, fields: [{ name: 'target', label: TLABEL[t.type], type: 'select', options, required: true },
        { name: 'due', label: 'Muddat (ixtiyoriy)', type: 'date' }], okText: 'Tayinlash' });
      if (!f) return;
      await run('apply_learning_path', { p_path: id, p_target_type: t.type, p_target_id: f.target, p_due_date: f.due || null },
        r => `Tayinlandi: ${r.course_assignments_created ?? 0} ta yangi kurs tayinlash, ${r.employees_matched ?? 0} xodim` + (r.rule === 'existing' ? ' (qoida allaqachon mavjud edi)' : ''));
    };
    el.querySelectorAll('[data-reapply]').forEach(b => b.onclick = async () => {
      if (!await dialog({ title: 'Qayta qo\'llash', body: 'Qoida joriy xodimlar ro\'yxatiga qayta qo\'llanadi. Yetishmayotgan tayinlashlar qo\'shiladi, mavjudlari o\'zgarmaydi.', okText: 'Qayta qo\'llash' })) return;
      await run('reapply_learning_path_assignment', { p_assignment: b.getAttribute('data-reapply') }, r => `Qayta qo'llandi: ${r.course_assignments_created ?? 0} ta yangi tayinlash`);
    });
    el.querySelectorAll('[data-cancel]').forEach(b => b.onclick = async () => {
      const f = await dialog({ title: 'Qoidani bekor qilish', body: 'Mavjud kurs tayinlashlari bekor qilinmaydi.', fields: [{ name: 'reason', label: 'Sabab', type: 'textarea', required: true }], okText: 'Bekor qilish', danger: true });
      if (!f) return;
      await run('cancel_learning_path_assignment', { p_assignment: b.getAttribute('data-cancel'), p_reason: f.reason }, () => 'Qoida bekor qilindi');
    });
  });

  // ---------------- Course Progress (007a course_progress_summary) ----------------
  ADMIN.route('/learning/progress', 'progress', async (el, ctx) => {
    ctx.setTitle('Course Progress');
    const courses = await lookup('courses', 'title');
    const cur = ctx.query.course || '';
    el.innerHTML = `<div class="adm-h"><div><h1>Course Progress</h1><div class="sub">Kurs tugallanishi = barcha majburiy published darslar tugallangan (007a). Yakuniy imtihon / sertifikat — alohida (Imtihonlar bo'limi).</div></div></div>
      ${learnTabs('progress')}<div class="filters"><select data-f="course"><option value="">Kursni tanlang</option>${Object.entries(courses).map(([k, v]) => `<option value="${esc(k)}" ${k === cur ? 'selected' : ''}>${esc(v)}</option>`).join('')}</select></div>
      <div data-sum>${cur ? skeleton(3) : `<div class="card">${empty('Kursni tanlang', 'Server qamrovingiz bo\'yicha umumiy ko\'rsatkichlar ko\'rsatiladi')}</div>`}</div>
      <div class="card" style="padding:6px 8px" data-list ${cur ? '' : 'hidden'}>${skeleton(4)}</div>`;
    el.querySelector('[data-f=course]').onchange = e => { ctx.setQuery({ course: e.target.value }); ADMIN.render(); };
    if (!cur) return;
    const sumEl = el.querySelector('[data-sum]'), listEl = el.querySelector('[data-list]');
    try {
      const [s, rows] = await Promise.all([API.rpc('course_progress_summary', { p_course: cur }),
        API.list('course_assignments', { select: 'id,employee_id,status,due_date,assigned_at,completed_at', eq: { course_id: cur }, order: ['assigned_at', false], page: +(ctx.query.page || 0), size: 25 })]);
      if (!ctx.alive()) return;
      const k = (key, label, cls = '') => `<div class="kpi ${cls}" data-kpi="${key}"><div class="v">${esc(s[key] ?? 0)}</div><div class="l">${label}</div></div>`;
      sumEl.innerHTML = `<div class="card"><div class="row between"><h3>${esc(courses[cur] || cur)}</h3><span class="badge" data-scope>${esc(s.scope === 'organization' ? 'Tashkilot' : s.scope === 'department' ? 'O\'z bo\'limi' : s.scope === 'instructor' ? 'Instruktor kurslari' : s.scope || '')}</span></div>
        <div class="kpis">${k('assigned_count', 'Tayinlangan')}${k('completed_count', 'Tugallangan', 'green')}${k('in_progress_count', 'Jarayonda')}${k('not_started_count', 'Boshlanmagan')}${k('overdue_count', 'Muddati o\'tgan', 'red')}${k('cancelled_count', 'Bekor qilingan')}</div>
        <div class="small muted" style="margin-top:8px">Majburiy darslar: <b>${esc(s.total_required_lessons)}</b> · O'rtacha progress: <b data-avg>${esc(s.average_progress)}%</b> (server hisobi; optional va draft darslar kirmaydi)</div></div>`;
      const ids = rows.rows.map(x => x.employee_id);
      const em = ids.length ? Object.fromEntries((await API.list('employees', { select: 'id,first_name,last_name,employee_code', in: { id: ids }, all: true, count: false })).rows.map(e => [e.id, e])) : {};
      listEl.innerHTML = table(rows.rows, [
        { h: 'Xodim', r: x => em[x.employee_id] ? `<a href="#/compliance/employee/${x.employee_id}">${esc([em[x.employee_id].first_name, em[x.employee_id].last_name].filter(Boolean).join(' ') || em[x.employee_id].employee_code)}</a>` : '<span class="tiny">ko\'rinmaydi</span>' },
        { h: 'Tayinlash holati', r: x => badge('p3', x.status) }, { h: 'Muddat', r: x => fmtDate(x.due_date) }, { h: 'Tugallangan', r: x => fmtDate(x.completed_at) }],
        { id: 'progress_rows', empty: 'Bu kurs bo\'yicha tayinlash yo\'q' }) + (rows.count > 25 ? UI.pager(+(ctx.query.page || 0), 25, rows.count) : `<div class="pager">${rows.count} ta</div>`)
        + '<div class="tiny muted" style="padding:6px">Xodim bo\'yicha batafsil (dars progressi, compliance) — xodim nomini bosing.</div>';
      listEl.addEventListener('click', e => { const b = e.target.closest('[data-page]'); if (b && !b.disabled) { ctx.setQuery({ page: b.getAttribute('data-page') }); ADMIN.render(); } });
    } catch (e) { if (ctx.alive()) { sumEl.innerHTML = `<div class="card">${errorBox(API.friendly(e))}<button class="btn sm" data-retry>Qayta urinish</button></div>`; listEl.hidden = true;
      sumEl.querySelector('[data-retry]').onclick = () => ADMIN.render(); } }
  });
})();
