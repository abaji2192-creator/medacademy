/* Ta'lim (kurslar → modullar → darslar, tayinlashlar, instruktorlar) va Imtihonlar (sozlamalar, urinishlar, natijalar). */
(function () {
  const { esc, badge, table, empty, errorBox, skeleton, fmtDT, fmtDate, toast, dialog } = UI;
  const { listPage, lookup, clearCache } = ADMINLIB;
  const COURSE_FLOW = { draft: ['under_review'], under_review: ['approved', 'draft'], approved: ['published', 'draft'], published: ['archived'], archived: ['draft'] };
  const eduTabs = cur => `<div class="tabs">${[['courses', 'Kurslar'], ['assignments', 'Tayinlashlar'], ['instructors', 'Instruktorlar']].map(([k, l]) => `<a href="#/edu/${k}" class="${k === cur ? 'on' : ''}">${l}</a>`).join('')}</div>`;

  async function eligibleByCourse() { const m = await API.rpc('question_meta').catch(() => []); const out = {}; (Array.isArray(m) ? m : []).forEach(x => { out[x.course] = (out[x.course] || 0) + 1; }); return out; }

  ADMIN.route('/edu/courses', 'education', async (el, ctx) => {
    const elig = await eligibleByCourse();
    await listPage(el, ctx, {
      title: 'Kurslar', id: 'courses', top: eduTabs('courses'), sub: 'Kurs → Modul → Dars → Quiz → Klinik holat → Yakuniy imtihon.',
      chips: { key: 'st', items: [['', 'Barchasi'], ['draft', 'Draft'], ['under_review', 'Under Review'], ['approved', 'Approved'], ['published', 'Published'], ['archived', 'Archived']] },
      filters: [{ key: 's', type: 'search', label: 'Kurs nomi yoki kodi' }, { key: 'domain', type: 'select', label: 'Soha', options: [['medical', 'Tibbiy'], ['ethics', 'Etika'], ['communication', 'Kommunikatsiya'], ['safety', 'Xavfsizlik'], ['public_health', 'Jamoat salomatligi'], ['sales', 'Sotuv/servis']] }],
      load: q => API.list('courses', { select: 'id,code,title,domain,status,valid_months,updated_at', eq: { status: q.st, domain: q.domain }, search: { cols: ['title', 'code', 'id'], q: q.s }, order: ['title', true], page: q.page, size: q.size }),
      href: x => '#/edu/courses/' + encodeURIComponent(x.id),
      columns: [{ h: 'Kurs', r: x => `<b>${esc(x.title)}</b><div class="sub mono">${esc(x.code || x.id)}</div>` }, { h: 'Soha', r: x => esc(x.domain) }, { h: 'Holat', r: x => badge('course', x.status) },
        { h: 'Yaroqli savollar', r: x => `<b>${elig[x.id] || 0}</b>` }, { h: 'Amal muddati', r: x => x.valid_months + ' oy' }],
      empty: 'Kurs yo\'q',
    });
  });

  ADMIN.route('/edu/courses/:id', 'education', async (el, ctx) => {
    const id = decodeURIComponent(ctx.params.id);
    const c = await API.get('courses', 'id', id, '*');
    if (!ctx.alive()) return;
    if (!c) { el.innerHTML = `<div class="card">${empty('Kurs topilmadi yoki ruxsat yo\'q')}</div>`; return; }
    ctx.setTitle(c.title);
    const [mods, cfg, elig] = await Promise.all([API.list('course_modules', { select: 'id,title,order_index,status', eq: { course_id: id }, order: ['order_index', true], all: true, count: false }),
      API.get('exam_configs', 'course_id', id, '*').catch(() => null), eligibleByCourse()]);
    const lessons = mods.rows.length ? (await API.list('lessons', { select: 'id,module_id,title,content_type,order_index,status,estimated_minutes', in: { module_id: mods.rows.map(m => m.id) }, order: ['order_index', true], all: true, count: false })).rows : [];
    if (!ctx.alive()) return;
    const canStatus = PERMS.can('course.publish') || PERMS.can('course.edit');
    const next = (COURSE_FLOW[c.status] || []).filter(s => s !== 'published' || PERMS.can('course.publish'));
    el.innerHTML = `<div class="adm-h"><div><div class="sub"><a href="#/edu/courses">← Kurslar</a></div><h1>${esc(c.title)}</h1><div class="row">${badge('course', c.status)} <span class="badge">${esc(c.domain)}</span> <span class="small muted">Yaroqli savollar: <b>${elig[id] || 0}</b>${cfg ? ' / imtihon uchun kerak: ' + cfg.question_count : ''}</span></div></div>
      <div class="act">${canStatus ? next.map(s => `<button class="btn ${s === 'published' ? 'green' : ''}" data-status="${s}">→ ${esc(UI.LABELS.course[s][0])}</button>`).join('') : ''}</div></div>
      <div class="grid g2"><div class="card"><h3>Tuzilma: modullar va darslar</h3>${mods.rows.length ? mods.rows.map(m => `<div class="opt"><div class="row between"><b>${m.order_index}. ${esc(m.title)}</b>${badge('generic', m.status)}</div>
        ${lessons.filter(l => l.module_id === m.id).map(l => `<div class="small row between" style="padding:2px 0 2px 14px"><span>${esc(l.title)} <span class="tiny">${esc(l.content_type)} · ${l.estimated_minutes} daq</span></span>${badge('generic', l.status)}</div>`).join('') || '<div class="tiny" style="padding-left:14px">Dars yo\'q</div>'}</div>`).join('') : empty('Modul yo\'q')}</div>
      <div class="card"><h3>Yakuniy imtihon</h3>${cfg ? `<dl class="kv"><dt>Savollar soni</dt><dd>${cfg.question_count}</dd><dt>Davomiyligi</dt><dd>${cfg.time_min} daqiqa</dd><dt>O'tish bali</dt><dd>${cfg.pass_score}%</dd><dt>Urinishlar</dt><dd>${cfg.max_attempts}</dd><dt>Qayta topshirish</dt><dd>${cfg.retake_days} kundan keyin</dd></dl>
        ${(elig[id] || 0) < cfg.question_count ? `<div class="note warn" style="margin-top:10px">Imtihonga yaroqli savollar yetarli emas (${elig[id] || 0}/${cfg.question_count}). Xodimlar imtihonni boshlay olmaydi — server tekshiradi.</div>` : '<div class="note" style="margin-top:10px">Yaroqli savollar yetarli.</div>'}` : empty('Imtihon sozlamasi yo\'q')}</div></div>`;
    el.querySelectorAll('[data-status]').forEach(b => b.onclick = async () => { const s = b.getAttribute('data-status');
      if (s === 'published' && cfg && (elig[id] || 0) < cfg.question_count) { if (!await dialog({ title: 'Diqqat', body: `Kursda imtihonga yaroqli savollar yetarli emas (${elig[id] || 0}/${cfg.question_count}). Kurs nashr qilinadi, lekin yakuniy imtihon server tomonidan bloklanadi.`, okText: 'Baribir nashr qilish' })) return; }
      else if (!await dialog({ title: 'Kurs holatini o\'zgartirish', body: `${esc(UI.LABELS.course[c.status][0])} → <b>${esc(UI.LABELS.course[s][0])}</b>`, okText: 'Tasdiqlash' })) return;
      try { await API.update('courses', 'id', id, { status: s }); clearCache(); toast('Kurs holati yangilandi'); ADMIN.render(); } catch (e) { toast(API.friendly(e).message, true); } });
  });

  ADMIN.route('/edu/assignments', 'education', async (el, ctx) => {
    const courses = await lookup('courses', 'title');
    const h = await listPage(el, ctx, {
      title: 'Tayinlashlar', id: 'assignments', top: eduTabs('assignments'),
      actions: PERMS.can('assignment.manage') ? `<button class="btn primary" data-act="assign">+ Kurs tayinlash</button>` : '',
      filters: [{ key: 'course', type: 'select', label: 'Kurs', options: Object.entries(courses) }, { key: 'st', type: 'select', label: 'Holat', options: ['assigned', 'in_progress', 'completed', 'overdue', 'cancelled'].map(s => [s, UI.LABELS.generic[s][0]]) }],
      load: async q => { const r = await API.list('course_assignments', { select: 'id,course_id,employee_id,status,assigned_at,due_date,completed_at', eq: { course_id: q.course, status: q.st }, order: ['assigned_at', false], page: q.page, size: q.size });
        const ids = r.rows.map(x => x.employee_id); const em = ids.length ? Object.fromEntries((await API.list('employees', { select: 'id,first_name,last_name,employee_code', in: { id: ids }, all: true, count: false }).catch(() => ({ rows: [] }))).rows.map(e => [e.id, e])) : {};
        r.rows.forEach(x => x._e = em[x.employee_id]); return r; },
      columns: [{ h: 'Xodim', r: x => x._e ? `<a href="#/employees/${x._e.id}">${esc([x._e.first_name, x._e.last_name].filter(Boolean).join(' ') || x._e.employee_code)}</a>` : '<span class="tiny">ko\'rinmaydi</span>' },
        { h: 'Kurs', r: x => esc(courses[x.course_id] || x.course_id) }, { h: 'Holat', r: x => badge('generic', x.status) }, { h: 'Tayinlangan', r: x => fmtDate(x.assigned_at) }, { h: 'Muddat', r: x => fmtDate(x.due_date) }],
      empty: 'Tayinlash yo\'q',
    });
    const b = el.querySelector('[data-act="assign"]');
    if (b) b.onclick = async () => {
      const em = await API.list('employees', { select: 'id,first_name,last_name,employee_code', eq: { employment_status: 'active' }, order: ['first_name', true], all: true, count: false }).catch(() => ({ rows: [] }));
      const r = await dialog({ title: 'Kurs tayinlash', fields: [{ name: 'course', label: 'Kurs', type: 'select', required: true, options: Object.entries(courses) },
        { name: 'emp', label: 'Xodim', type: 'select', required: true, options: em.rows.map(e => [e.id, [e.first_name, e.last_name].filter(Boolean).join(' ') + ' (' + e.employee_code + ')']) }, { name: 'due', label: 'Muddat', type: 'date' }], okText: 'Tayinlash' });
      if (!r) return;
      try { await API.insert('course_assignments', { org_id: PERMS.state.profile.org_id, course_id: r.course, employee_id: r.emp, due_date: r.due || null }); toast('Tayinlandi'); h.reload(); } catch (e) { toast(API.friendly(e).message, true); }
    };
  });

  ADMIN.route('/edu/instructors', 'education', async (el, ctx) => {
    const courses = await lookup('courses', 'title');
    const h = await listPage(el, ctx, {
      title: 'Instruktorlar', id: 'instructors', top: eduTabs('instructors'), sub: 'Instruktor faqat biriktirilgan kurslar kontentini ko\'radi va tahrirlaydi (server RLS).',
      actions: PERMS.can('instructor.assign') ? `<button class="btn primary" data-act="add">+ Instruktor biriktirish</button>` : '',
      filters: [{ key: 'course', type: 'select', label: 'Kurs', options: Object.entries(courses) }],
      load: async q => { const r = await API.list('course_instructors', { select: 'id,course_id,employee_id,status,assigned_at', eq: { course_id: q.course }, order: ['assigned_at', false], page: q.page, size: q.size });
        const ids = r.rows.map(x => x.employee_id); const em = ids.length ? Object.fromEntries((await API.list('employees', { select: 'id,first_name,last_name,employee_code', in: { id: ids }, all: true, count: false }).catch(() => ({ rows: [] }))).rows.map(e => [e.id, e])) : {};
        r.rows.forEach(x => x._e = em[x.employee_id]); return r; },
      columns: [{ h: 'Instruktor', r: x => x._e ? esc([x._e.first_name, x._e.last_name].filter(Boolean).join(' ')) : '<span class="tiny">—</span>' }, { h: 'Kurs', r: x => esc(courses[x.course_id] || x.course_id) },
        { h: 'Holat', r: x => badge('generic', x.status) }, { h: 'Biriktirilgan', r: x => fmtDate(x.assigned_at) }],
      empty: 'Instruktor biriktirilmagan',
    });
    const b = el.querySelector('[data-act="add"]');
    if (b) b.onclick = async () => {
      const em = await API.list('employees', { select: 'id,first_name,last_name,employee_code,profile_id', eq: { employment_status: 'active' }, order: ['first_name', true], all: true, count: false }).catch(() => ({ rows: [] }));
      const r = await dialog({ title: 'Instruktor biriktirish', fields: [{ name: 'course', label: 'Kurs', type: 'select', required: true, options: Object.entries(courses) }, { name: 'emp', label: 'Xodim', type: 'select', required: true, options: em.rows.map(e => [e.id, [e.first_name, e.last_name].filter(Boolean).join(' ') + ' (' + e.employee_code + ')']) }], okText: 'Biriktirish' });
      if (!r) return;
      try { await API.insert('course_instructors', { org_id: PERMS.state.profile.org_id, course_id: r.course, employee_id: r.emp }); toast('Biriktirildi'); h.reload(); } catch (e) { toast(API.friendly(e).message, true); }
    };
  });

  // ---------- Imtihonlar ----------
  const examTabs = cur => `<div class="tabs">${[['configs', 'Imtihon sozlamalari'], ['attempts', 'Urinishlar'], ['results', 'Natijalar']].map(([k, l]) => `<a href="#/exams/${k}" class="${k === cur ? 'on' : ''}">${l}</a>`).join('')}</div>`;
  ADMIN.route('/exams/configs', 'exams', async (el, ctx) => {
    const [courses, elig] = await Promise.all([API.list('courses', { select: 'id,title,status', all: true, count: false }), eligibleByCourse()]);
    const cmap = Object.fromEntries(courses.rows.map(c => [c.id, c]));
    const canEdit = PERMS.can('exam.manage');
    const h = await listPage(el, ctx, {
      title: 'Imtihon sozlamalari', id: 'exam-configs', top: examTabs('configs'),
      sub: 'Imtihon faqat yetarli <b>yaroqli</b> savol bo\'lganda ishlaydi. Yaroqlilikni server hisoblaydi (published + current evidence).',
      filters: [{ key: 's', type: 'search', label: 'Kurs' }],
      load: async q => { const r = await API.list('exam_configs', { select: '*', order: ['course_id', true], page: q.page, size: q.size });
        if (q.s) r.rows = r.rows.filter(x => (cmap[x.course_id]?.title || x.course_id).toLowerCase().includes(q.s.toLowerCase())); return r; },
      columns: [{ h: 'Kurs', r: x => `<b>${esc(cmap[x.course_id]?.title || x.course_id)}</b><div class="sub">${badge('course', cmap[x.course_id]?.status)}</div>` },
        { h: 'Holat', r: x => (elig[x.course_id] || 0) >= x.question_count && cmap[x.course_id]?.status === 'published' ? '<span class="badge b-green" data-exam-state="ready">Tayyor</span>' : `<span class="badge b-red" data-exam-state="blocked">Bloklangan</span><div class="sub">yaroqli ${elig[x.course_id] || 0}/${x.question_count}</div>` },
        { h: 'Savollar', r: x => x.question_count }, { h: 'Davomiylik', r: x => x.time_min + ' daq' }, { h: 'O\'tish bali', r: x => x.pass_score + '%' }, { h: 'Urinishlar', r: x => x.max_attempts },
        ...(canEdit ? [{ h: '', r: x => `<button class="btn sm" data-edit="${esc(x.course_id)}">Tahrirlash</button>` }] : [])],
      empty: 'Imtihon sozlamasi yo\'q',
      onReady: (listEl, r) => listEl.querySelectorAll('[data-edit]').forEach(b => b.onclick = async () => { const x = r.rows.find(y => y.course_id === b.getAttribute('data-edit'));
        const v = await dialog({ title: 'Imtihon sozlamasi: ' + (cmap[x.course_id]?.title || x.course_id), fields: [
          { name: 'question_count', label: 'Savollar soni', type: 'number', value: x.question_count, required: true }, { name: 'time_min', label: 'Davomiylik (daqiqa)', type: 'number', value: x.time_min, required: true },
          { name: 'pass_score', label: 'O\'tish bali (%)', type: 'number', value: x.pass_score, required: true }, { name: 'max_attempts', label: 'Maksimal urinishlar', type: 'number', value: x.max_attempts, required: true },
          { name: 'retake_days', label: 'Qayta topshirish (kun)', type: 'number', value: x.retake_days, required: true }], okText: 'Saqlash' });
        if (!v) return;
        try { await API.update('exam_configs', 'course_id', x.course_id, { question_count: +v.question_count, time_min: +v.time_min, pass_score: +v.pass_score, max_attempts: +v.max_attempts, retake_days: +v.retake_days }); toast('Saqlandi'); h.reload(); }
        catch (e) { toast(API.friendly(e).message, true); } }),
    });
  });

  ADMIN.route('/exams/attempts', 'exams', async (el, ctx) => {
    const courses = await lookup('courses', 'title');
    await listPage(el, ctx, {
      title: 'Imtihon urinishlari', id: 'attempts', top: examTabs('attempts'), sub: 'Tarixiy yozuvlar — o\'zgartirib yoki o\'chirib bo\'lmaydi. Javoblar bu ro\'yxatda yuklanmaydi.',
      filters: [{ key: 'course', type: 'select', label: 'Kurs', options: Object.entries(courses) }, { key: 'kind', type: 'select', label: 'Tur', options: [['final', 'Yakuniy'], ['module', 'Modul'], ['initial', 'Boshlang\'ich']] },
        { key: 'res', type: 'select', label: 'Natija', options: [['true', 'O\'tdi'], ['false', 'O\'tmadi']] }],
      load: async q => { const r = await API.list('exam_attempts', { select: 'id,user_id,course_id,kind,score,passed,is_preview,started_at,finished_at', eq: { course_id: q.course, kind: q.kind, passed: q.res }, order: ['started_at', false], page: q.page, size: q.size });
        const ids = [...new Set(r.rows.map(x => x.user_id))]; const pp = ids.length ? Object.fromEntries((await API.list('profiles', { select: 'id,full_name,email', in: { id: ids }, all: true, count: false }).catch(() => ({ rows: [] }))).rows.map(p => [p.id, p])) : {};
        r.rows.forEach(x => x._p = pp[x.user_id]); return r; },
      columns: [{ h: 'Xodim', r: x => esc(x._p ? x._p.full_name || x._p.email : (x.user_id || '').slice(0, 8)) }, { h: 'Kurs', r: x => esc(courses[x.course_id] || x.course_id) + (x.is_preview ? ' <span class="badge">preview</span>' : '') },
        { h: 'Tur', r: x => esc(x.kind) }, { h: 'Ball', r: x => x.score === null ? '—' : Math.round(x.score) + '%' },
        { h: 'Natija', r: x => x.finished_at ? (x.passed ? '<span class="badge b-green">O\'tdi</span>' : '<span class="badge b-red">O\'tmadi</span>') : '<span class="badge b-amber">Jarayonda</span>' }, { h: 'Sana', r: x => fmtDT(x.finished_at || x.started_at) }],
      empty: 'Urinish yo\'q',
    });
  });

  ADMIN.route('/exams/results', 'exams', async (el, ctx) => {
    ctx.setTitle('Natijalar');
    const [courses, r] = await Promise.all([lookup('courses', 'title'), API.list('exam_attempts', { select: 'course_id,score,passed,finished_at,is_preview,kind', is: { is_preview: false }, all: true, max: 4999, count: false })]);
    if (!ctx.alive()) return;
    const agg = {}; r.rows.filter(x => x.finished_at && x.kind === 'final').forEach(x => { const a = agg[x.course_id] = agg[x.course_id] || { n: 0, p: 0, s: 0 }; a.n++; if (x.passed) a.p++; a.s += +x.score || 0; });
    const rows = Object.entries(agg).map(([c, a]) => ({ c, ...a }));
    el.innerHTML = `<div class="adm-h"><div><h1>Natijalar</h1><div class="sub">Yakuniy imtihonlar bo'yicha (preview urinishlarsiz), sizning ruxsat doirangizda.</div></div></div>${examTabs('results')}
      <div class="card">${table(rows, [{ h: 'Kurs', r: x => esc(courses[x.c] || x.c) }, { h: 'Urinishlar', r: x => x.n }, { h: 'O\'tganlar', r: x => x.p }, { h: 'O\'tish ulushi', r: x => Math.round(100 * x.p / x.n) + '%' }, { h: 'O\'rtacha ball', r: x => Math.round(x.s / x.n) + '%' }], { empty: 'Yakunlangan yakuniy imtihon yo\'q', id: 'results' })}</div>`;
  });
})();
