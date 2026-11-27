/* Phase 3 (007c): Skills, Competency Requirements, Skill Assessments.
   Barcha yozish amallari faqat RPC orqali (upsert_skill / archive_skill / set_competency_requirement / archive_competency_requirement /
   record_skill_assessment). Baholash tarixi — faqat qo'shiladi (insert-only), tahrirlash/o'chirish UI'da yo'q. */
(function () {
  const { esc, badge, table, empty, errorBox, fmtDT, toast, dialog } = UI;
  const { listPage, lookup } = ADMINLIB;
  const TARGETS = [['department', 'Bo\'lim'], ['position', 'Lavozim'], ['specialty', 'Mutaxassislik'], ['role', 'Rol']];
  const TLABEL = Object.fromEntries(TARGETS);
  const ROLES = ['employee', 'department_head', 'instructor', 'hr', 'education_manager', 'medical_reviewer', 'content_author'];
  const tabs = cur => `<div class="tabs">${[['skills', 'Ko\'nikmalar'], ['requirements', 'Talablar'], ['assessments', 'Baholashlar']]
    .map(([k, l]) => `<a href="#/skills/${k}" class="${k === cur ? 'on' : ''}">${l}</a>`).join('')}</div>`;
  const rpc = async (fn, args, msg) => { try { await API.rpc(fn, args); ADMINLIB.clearCache && ADMINLIB.clearCache(); toast(msg); ADMIN.render(); return true; } catch (e) { toast(API.friendly(e).message, true); return false; } };
  const empName = e => [e.first_name, e.last_name].filter(Boolean).join(' ') || e.employee_code || 'Xodim';
  async function empMap(ids) {
    ids = [...new Set(ids.filter(Boolean))];
    if (!ids.length) return {};
    return Object.fromEntries((await API.list('employees', { select: 'id,first_name,last_name,employee_code', in: { id: ids }, all: true, count: false })).rows.map(e => [e.id, empName(e)]));
  }
  async function skillForm(s) {
    const spec = await lookup('specialties', 'name');
    return dialog({ title: s ? 'Ko\'nikmani tahrirlash' : 'Yangi ko\'nikma', fields: [
      { name: 'code', label: 'Kod', required: true, value: s && s.code, pattern: '[A-Za-z0-9_.\\-]{2,64}', placeholder: 'ECG_READING' },
      { name: 'name', label: 'Nomi', required: true, value: s && s.name },
      { name: 'category', label: 'Kategoriya', value: s && s.category },
      { name: 'specialty', label: 'Mutaxassislik', type: 'select', value: (s && s.specialty_id) || '', options: [['', '—'], ...Object.entries(spec)] },
      { name: 'max', label: 'Maksimal daraja (1–10)', type: 'number', required: true, value: String((s && s.max_level) || 5) },
      { name: 'description', label: 'Tavsif', type: 'textarea', value: s && s.description }], okText: 'Saqlash' });
  }
  const saveSkill = (id, f) => rpc('upsert_skill', { p_id: id || null, p_code: f.code, p_name: f.name, p_description: f.description || null, p_category: f.category || null,
    p_specialty: f.specialty || null, p_max_level: +f.max }, 'Ko\'nikma saqlandi');

  // ---------------- Ko'nikmalar ----------------
  ADMIN.route('/skills/skills', 'skills', async (el, ctx) => {
    const spec = await lookup('specialties', 'name');
    const canM = PERMS.can('skill.manage');
    await listPage(el, ctx, {
      title: 'Skills', id: 'skills', top: tabs('skills'), sub: 'Klinik ko\'nikmalar katalogi (007c). Arxivlangan ko\'nikma yangi talab va baholashda ishlatilmaydi.',
      actions: canM ? '<button class="btn primary" data-new-skill>+ Ko\'nikma</button>' : '',
      filters: [{ key: 's', type: 'search', label: 'Kod yoki nomi' }, { key: 'st', type: 'select', label: 'Holat', options: [['active', 'Faol'], ['archived', 'Arxiv']] }],
      load: q => API.list('skills', { select: 'id,code,name,description,category,specialty_id,max_level,status,updated_at', eq: { status: q.st }, search: { cols: ['name', 'code'], q: q.s }, order: ['name', true], page: q.page, size: q.size }),
      columns: [{ h: 'Ko\'nikma', r: x => `<b>${esc(x.name)}</b><div class="sub mono">${esc(x.code)}</div>` }, { h: 'Kategoriya', r: x => esc(x.category || '—') },
        { h: 'Mutaxassislik', r: x => esc(spec[x.specialty_id] || '—') }, { h: 'Maks.', r: x => `<b>${x.max_level}</b>` }, { h: 'Holat', r: x => badge('p3', x.status) },
        { h: '', r: x => canM && x.status === 'active' ? `<button class="btn sm" data-edit-skill="${x.id}">Tahrirlash</button> <button class="btn sm red" data-archive-skill="${x.id}">Arxivlash</button>` : '' }],
      empty: 'Ko\'nikma yo\'q',
    });
    const nb = el.querySelector('[data-new-skill]');
    if (nb) nb.onclick = async () => { const f = await skillForm(null); if (f) await saveSkill(null, f); };
    el.querySelector('[data-list]').addEventListener('click', async e => {
      const ed = e.target.closest('[data-edit-skill]'), ar = e.target.closest('[data-archive-skill]');
      if (ed) { const s = await API.get('skills', 'id', ed.getAttribute('data-edit-skill'), 'id,code,name,description,category,specialty_id,max_level'); const f = s && await skillForm(s); if (f) await saveSkill(s.id, f); }
      if (ar) { const f = await dialog({ title: 'Ko\'nikmani arxivlash', body: 'Mavjud baholash tarixi saqlanadi.', fields: [{ name: 'reason', label: 'Sabab', type: 'textarea', required: true }], okText: 'Arxivlash', danger: true });
        if (f) await rpc('archive_skill', { p_id: ar.getAttribute('data-archive-skill'), p_reason: f.reason }, 'Ko\'nikma arxivlandi'); }
    });
  });

  // ---------------- Competency Requirements ----------------
  ADMIN.route('/skills/requirements', 'skills', async (el, ctx) => {
    const [skills, deps, pos, spec] = await Promise.all([lookup('skills', 'name'), lookup('departments', 'name'), lookup('positions', 'name'), lookup('specialties', 'name')]);
    const canM = PERMS.can('competency.manage');
    const tname = r => r.target_type === 'department' ? deps[r.department_id] : r.target_type === 'position' ? pos[r.position_id] : r.target_type === 'specialty' ? spec[r.specialty_id] : (PERMS.ROLE_LABEL[r.target_role] || r.target_role);
    await listPage(el, ctx, {
      title: 'Competency Requirements', id: 'requirements', top: tabs('requirements'),
      sub: 'Bo\'lim / lavozim / mutaxassislik / rol uchun talab qilinadigan daraja. Bir nechta talab mos kelsa, server eng yuqorisini oladi.',
      actions: canM ? '<button class="btn primary" data-new-req>+ Talab</button>' : '',
      filters: [{ key: 'sk', type: 'select', label: 'Ko\'nikma', options: Object.entries(skills) }, { key: 'st', type: 'select', label: 'Holat', options: [['active', 'Faol'], ['archived', 'Arxiv']] }],
      load: q => API.list('competency_requirements', { select: 'id,skill_id,target_type,department_id,position_id,specialty_id,target_role,required_level,status,updated_at', eq: { skill_id: q.sk, status: q.st }, order: ['updated_at', false], page: q.page, size: q.size }),
      columns: [{ h: 'Ko\'nikma', r: x => `<b>${esc(skills[x.skill_id] || '—')}</b>` }, { h: 'Nishon', r: x => `<span class="badge">${esc(TLABEL[x.target_type])}</span> ${esc(tname(x) || '—')}` },
        { h: 'Talab darajasi', r: x => `<b data-level>${x.required_level}</b>` }, { h: 'Holat', r: x => badge('p3', x.status) }, { h: 'Yangilangan', r: x => fmtDT(x.updated_at) },
        { h: '', r: x => canM && x.status === 'active' ? `<button class="btn sm red" data-archive-req="${x.id}">Arxivlash</button>` : '' }],
      empty: 'Talab yo\'q',
    });
    const nb = el.querySelector('[data-new-req]');
    if (nb) nb.onclick = async () => {
      const active = (await API.list('skills', { select: 'id,name,max_level', eq: { status: 'active' }, order: ['name', true], all: true, count: false })).rows;
      if (!active.length) { toast('Avval faol ko\'nikma yarating', true); return; }
      const t = await dialog({ title: 'Kompetensiya talabi', fields: [{ name: 'skill', label: 'Ko\'nikma', type: 'select', required: true, options: active.map(s => [s.id, `${s.name} (maks. ${s.max_level})`]) },
        { name: 'type', label: 'Nishon turi', type: 'select', required: true, options: TARGETS }], okText: 'Davom etish' });
      if (!t) return;
      const options = t.type === 'role' ? ROLES.map(r => [r, PERMS.ROLE_LABEL[r] || r]) : Object.entries(t.type === 'department' ? deps : t.type === 'position' ? pos : spec);
      if (!options.length) { toast('Tanlash uchun ' + TLABEL[t.type].toLowerCase() + ' topilmadi', true); return; }
      const f = await dialog({ title: 'Talab: ' + TLABEL[t.type], body: 'Agar shu nishon uchun faol talab bo\'lsa, server darajasini yangilaydi.', fields: [{ name: 'target', label: TLABEL[t.type], type: 'select', required: true, options },
        { name: 'level', label: 'Talab darajasi', type: 'number', required: true, value: '3' }], okText: 'Saqlash' });
      if (f) await rpc('set_competency_requirement', { p_skill: t.skill, p_target_type: t.type, p_target_id: f.target, p_required_level: +f.level }, 'Talab saqlandi');
    };
    el.querySelector('[data-list]').addEventListener('click', async e => {
      const ar = e.target.closest('[data-archive-req]'); if (!ar) return;
      const f = await dialog({ title: 'Talabni arxivlash', fields: [{ name: 'reason', label: 'Sabab', type: 'textarea', required: true }], okText: 'Arxivlash', danger: true });
      if (f) await rpc('archive_competency_requirement', { p_id: ar.getAttribute('data-archive-req'), p_reason: f.reason }, 'Talab arxivlandi');
    });
  });

  // ---------------- Skill Assessments (insert-only tarix) ----------------
  ADMIN.route('/skills/assessments', 'skills', async (el, ctx) => {
    const skills = await lookup('skills', 'name');
    const canA = PERMS.can('skill.assess');
    let em = {};
    await listPage(el, ctx, {
      title: 'Skill Assessments', id: 'assessments', top: tabs('assessments'),
      sub: 'Baholash tarixi faqat qo\'shiladi — eski yozuvlar o\'zgartirilmaydi. Joriy daraja = eng so\'nggi baholash (server).',
      actions: canA ? '<button class="btn primary" data-new-asm>+ Baholash</button>' : '',
      filters: [{ key: 'sk', type: 'select', label: 'Ko\'nikma', options: Object.entries(skills) }],
      load: async q => { const r = await API.list('skill_assessments', { select: 'id,skill_id,employee_id,assessor_id,level,notes,assessed_at', eq: { skill_id: q.sk }, order: ['assessed_at', false], page: q.page, size: q.size });
        em = await empMap(r.rows.map(x => x.employee_id)); return r; },
      columns: [{ h: 'Xodim', r: x => `<a href="#/compliance/employee/${x.employee_id}">${esc(em[x.employee_id] || 'Xodim')}</a>` }, { h: 'Ko\'nikma', r: x => esc(skills[x.skill_id] || '—') },
        { h: 'Daraja', r: x => `<b>${x.level}</b>` }, { h: 'Izoh', r: x => `<span class="small">${esc(x.notes || '')}</span>` }, { h: 'Sana', r: x => fmtDT(x.assessed_at) }],
      empty: 'Baholash yo\'q',
    });
    const nb = el.querySelector('[data-new-asm]');
    if (nb) nb.onclick = async () => {
      const [act, emps] = await Promise.all([API.list('skills', { select: 'id,name,max_level', eq: { status: 'active' }, order: ['name', true], all: true, count: false }),
        API.list('employees', { select: 'id,first_name,last_name,employee_code', eq: { employment_status: 'active' }, order: ['last_name', true], all: true, count: false })]);
      if (!act.rows.length || !emps.rows.length) { toast('Faol ko\'nikma yoki ko\'rinadigan xodim yo\'q', true); return; }
      const f = await dialog({ title: 'Ko\'nikmani baholash', body: 'Server baholovchi huquqini va qamrovini tekshiradi (Department Head — faqat o\'z bo\'limi, o\'zini baholash taqiqlangan).', fields: [
        { name: 'emp', label: 'Xodim', type: 'select', required: true, options: emps.rows.map(e => [e.id, empName(e) + ' · ' + (e.employee_code || '')]) },
        { name: 'skill', label: 'Ko\'nikma', type: 'select', required: true, options: act.rows.map(s => [s.id, `${s.name} (0–${s.max_level})`]) },
        { name: 'level', label: 'Daraja', type: 'number', required: true, value: '0' }, { name: 'notes', label: 'Izoh', type: 'textarea' }], okText: 'Saqlash' });
      if (f) await rpc('record_skill_assessment', { p_employee: f.emp, p_skill: f.skill, p_level: +f.level, p_notes: f.notes || null }, 'Baholash qayd etildi');
    };
  });
  ADMIN.route('/skills', 'skills', async () => { location.replace('#/skills/skills'); });
})();
