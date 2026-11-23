/* Savollar banki: ro'yxat, filtrlar, savol kartasi (Question / Options / Correct Answer / Explanation / Evidence / Review / Version History) va workflow amallari. */
(function () {
  const { esc, badge, table, empty, errorBox, skeleton, fmtDT, fmtDate, toast, dialog } = UI;
  const { listPage, lookup } = ADMINLIB;
  const Q_COLS = 'id,code,course_id,module_id,type,topic,specialty,difficulty,stem,workflow_status,evidence_status,draft_status,current_version,published_version,evidence_review_due_at,updated_at';
  const STATUS_TABS = [['', 'All'], ['draft', 'Draft'], ['evidence_review', 'Evidence Review'], ['medical_review', 'Medical Review'], ['approved', 'Approved'],
    ['published', 'Published'], ['review_required', 'Review Required'], ['deprecated', 'Deprecated'], ['archived', 'Archived']];
  const EV = [['unknown', 'Unknown'], ['current', 'Current'], ['review_due', 'Review Due'], ['outdated', 'Outdated'], ['superseded', 'Superseded'], ['conflicting', 'Conflicting']];
  const TYPES = { single: 'Bitta javob', multiple: 'Ko\'p javob', tf: 'To\'g\'ri/Noto\'g\'ri', match: 'Moslashtirish', case: 'Klinik holat', short: 'Qisqa javob', image: 'Rasm', ecg: 'EKG', lab: 'Lab' };
  const trunc = (s, n = 110) => { s = String(s || ''); return s.length > n ? s.slice(0, n) + '…' : s; };

  function qFilter(q) {
    const o = { eq: { course_id: q.course, difficulty: q.difficulty, evidence_status: q.ev, specialty: q.specialty }, search: { cols: ['stem', 'code', 'topic', 'id'], q: q.s } };
    if (q.topic) o.search2 = q.topic;
    if (q.st === 'medical_review') { o.eq.evidence_status = 'current'; o.in = { workflow_status: ['draft', 'evidence_review', 'instructor_review', 'approved'] }; }
    else if (q.st) o.eq.workflow_status = q.st;
    if (q.rv === 'needs_evidence') o.in = { ...(o.in || {}), evidence_status: ['unknown', 'review_due', 'outdated', 'superseded', 'conflicting'] };
    if (q.rv === 'needs_medical') { o.eq.evidence_status = 'current'; o.neq = { workflow_status: 'published' }; }
    if (q.rv === 'reviewed') { o.eq.evidence_status = 'current'; o.eq.workflow_status = 'published'; }
    if (q.topic) o.or = `topic.ilike.*${q.topic.replace(/[(),*%]/g, ' ')}*,subtopic.ilike.*${q.topic.replace(/[(),*%]/g, ' ')}*`;
    return o;
  }

  ADMIN.route('/questions', 'questions', async (el, ctx) => {
    const courses = await lookup('courses', 'title');
    const specs = await API.list('specialties', { select: 'code,name', all: true, count: false, order: ['name', true] }).catch(() => ({ rows: [] }));
    await listPage(el, ctx, {
      title: 'Savollar banki', id: 'questions', sub: 'Ro\'yxatda javob kalitlari yuklanmaydi. Savol kartasida "Correct Answer" faqat ruxsatli rollarga ochiladi (RLS).',
      actions: PERMS.can('question.create') ? `<a class="btn primary" href="#/questions/new" data-act="new-question">+ Yangi savol</a>` : '',
      chips: { key: 'st', items: STATUS_TABS, counts: async () => { const out = {}; await Promise.all(STATUS_TABS.map(async ([v]) => { const o = qFilter({ st: v }); out[v] = await API.count('questions', o).catch(() => '—'); })); return out; } },
      filters: [{ key: 's', type: 'search', label: 'Qidirish: matn, kod, mavzu…' },
        { key: 'course', type: 'select', label: 'Kurs', options: Object.entries(courses) },
        { key: 'specialty', type: 'select', label: 'Mutaxassislik', options: specs.rows.map(s => [s.code, s.name]) },
        { key: 'topic', type: 'search', label: 'Mavzu' },
        { key: 'difficulty', type: 'select', label: 'Qiyinlik', options: [['easy', 'Oson'], ['medium', 'O\'rta'], ['hard', 'Qiyin'], ['expert', 'Ekspert']] },
        { key: 'ev', type: 'select', label: 'Evidence status', options: EV },
        { key: 'rv', type: 'select', label: 'Review status', options: [['needs_evidence', 'Evidence review kerak'], ['needs_medical', 'Medical review / publish kutmoqda'], ['reviewed', 'Review\'dan o\'tgan, nashr qilingan']] }],
      load: q => API.list('questions', { select: Q_COLS, ...qFilter(q), order: ['updated_at', false], page: q.page, size: q.size }),
      href: x => '#/questions/' + encodeURIComponent(x.id),
      columns: [{ h: 'Savol', r: x => `<div>${esc(trunc(x.stem))}</div><div class="sub mono">${esc(x.code || x.id)} · v${x.current_version}${x.published_version ? ' (nashr: v' + x.published_version + ')' : ''}</div>` },
        { h: 'Kurs / mavzu', r: x => `${esc(courses[x.course_id] || x.course_id)}<div class="sub">${esc(x.topic || '')}</div>` },
        { h: 'Tur', r: x => `${esc(TYPES[x.type] || x.type)}<div class="sub">${esc(x.difficulty)}</div>` },
        { h: 'Workflow', r: x => badge('workflow', x.workflow_status) + (x.draft_status ? `<div class="sub">ishchi versiya: ${esc(x.draft_status)}</div>` : '') },
        { h: 'Evidence', r: x => badge('evidence', x.evidence_status) + (x.evidence_review_due_at ? `<div class="sub">muddat: ${fmtDate(x.evidence_review_due_at)}</div>` : '') }],
      empty: 'Savol topilmadi', emptySub: 'Filtrlarni o\'zgartiring yoki rolingiz bu savollarni ko\'ra olmaydi.',
    });
  });

  // ---------- Yangi savol (Draft; server majburan draft + unknown evidence qiladi) ----------
  ADMIN.route('/questions/new', 'questions', async (el, ctx) => {
    ctx.setTitle('Yangi savol');
    if (!PERMS.can('question.create')) { el.innerHTML = UI.denied('Savol yaratish'); return; }
    const courses = await lookup('courses', 'title');
    el.innerHTML = `<div class="adm-h"><div><h1>Yangi savol</h1><div class="sub">Yangi savol har doim <b>Draft</b> va <b>Unknown evidence</b> holatida yaratiladi (server qoidasi). Imtihonga faqat review'dan keyin kiradi.</div></div></div>
      <form class="card" data-qform><div class="grid g2"><div><label>Kurs *</label><select name="course_id" required>${Object.entries(courses).map(([k, v]) => `<option value="${esc(k)}">${esc(v)}</option>`).join('')}</select></div>
      <div><label>Tur *</label><select name="type"><option value="single">Bitta javob</option><option value="multiple">Ko'p javob</option><option value="tf">To'g'ri / Noto'g'ri</option></select></div>
      <div><label>Mavzu</label><input name="topic"></div><div><label>Qiyinlik</label><select name="difficulty"><option value="easy">Oson</option><option value="medium" selected>O'rta</option><option value="hard">Qiyin</option><option value="expert">Ekspert</option></select></div></div>
      <label>Savol matni *</label><textarea name="stem" rows="3" required></textarea>
      <label>Variantlar (har biri yangi qatorda) *</label><textarea name="options" rows="4" placeholder="A variant&#10;B variant&#10;C variant&#10;D variant"></textarea>
      <label>To'g'ri javob(lar) raqami (1 dan; ko'p javobda vergul bilan: 1,3) *</label><input name="answer" required placeholder="1">
      <label>Izoh (explanation)</label><textarea name="explanation" rows="2"></textarea>
      <div class="small" data-err style="color:#b91c1c;margin-top:8px"></div><div class="row" style="margin-top:12px"><button class="btn primary">Draft sifatida saqlash</button><a class="btn" href="#/questions">Bekor qilish</a></div></form>`;
    const f = el.querySelector('[data-qform]');
    f.onsubmit = async e => { e.preventDefault();
      const type = f.type.value; let options = type === 'tf' ? ['To\'g\'ri', 'Noto\'g\'ri'] : f.options.value.split('\n').map(s => s.trim()).filter(Boolean);
      const idx = f.answer.value.split(',').map(s => parseInt(s, 10) - 1).filter(n => !isNaN(n));
      const err = !f.stem.value.trim() ? 'Savol matni kerak' : options.length < 2 ? 'Kamida 2 variant' : !idx.length || idx.some(i => i < 0 || i >= options.length) ? 'To\'g\'ri javob raqami noto\'g\'ri' : type !== 'multiple' && idx.length > 1 ? 'Bitta javobli savolda bitta raqam' : '';
      if (err) { f.querySelector('[data-err]').textContent = err; return; }
      const id = 'Q' + Date.now().toString(36).toUpperCase();
      try {
        await API.insert('questions', { id, org_id: PERMS.state.profile.org_id, course_id: f.course_id.value, type, topic: f.topic.value.trim() || null, difficulty: f.difficulty.value,
          stem: f.stem.value.trim(), options, answer: type === 'multiple' ? idx : idx[0], explanation: f.explanation.value.trim() || null, status: 'draft', workflow_status: 'draft' });
        toast('Savol Draft sifatida saqlandi'); ADMIN.go('#/questions/' + encodeURIComponent(id));
      } catch (e2) { f.querySelector('[data-err]').textContent = API.friendly(e2).message; }
    };
  });

  // ---------- Savol kartasi ----------
  const TABS = [['question', 'Question'], ['options', 'Options'], ['answer', 'Correct Answer'], ['explanation', 'Explanation'], ['evidence', 'Evidence'], ['review', 'Review'], ['versions', 'Version History']];
  const canSeeAnswer = () => PERMS.any('question.edit', 'question.review', 'question.approve', 'question.publish');

  async function gateInfo(q) {
    // Faqat ma'lumot uchun (UI); haqiqiy tekshiruv — server trigger'i (question_workflow) va _q_exam_eligible
    const ev = await API.list('question_evidence', { select: 'evidence_source_id,relationship_type', eq: { question_id: q.id }, all: true, count: false }).catch(() => ({ rows: [] }));
    const srcIds = ev.rows.map(r => r.evidence_source_id);
    const srcs = srcIds.length ? (await API.list('evidence_sources', { select: 'id,status,verification_status', in: { id: srcIds }, all: true, count: false }).catch(() => ({ rows: [] }))).rows : [];
    const primaryVerified = ev.rows.some(r => r.relationship_type === 'primary_support' && srcs.find(s => s.id === r.evidence_source_id && s.verification_status === 'verified' && s.status === 'active'));
    const conflicts = ev.rows.some(r => r.relationship_type === 'conflicting_evidence') || srcs.some(s => ['superseded', 'retracted', 'withdrawn'].includes(s.status));
    const med = await API.list('question_reviews', { select: 'id', eq: { question_id: q.id, review_type: 'medical', decision: 'approved', version_no: q.current_version }, count: false }).catch(() => ({ rows: [] }));
    return [['Evidence holati = Current', q.evidence_status === 'current' || q.evidence_exempt], ['Tasdiqlangan (verified) asosiy manba', primaryVerified || q.evidence_exempt],
      ['Ziddiyatli / eskirgan manba yo\'q', !conflicts], ['Joriy versiya uchun Medical Review (klinik savol)', med.rows.length > 0 || q.evidence_exempt]];
  }

  ADMIN.route('/questions/:id', 'questions', async (el, ctx) => {
    const id = decodeURIComponent(ctx.params.id); const tab = ctx.query.tab || 'question';
    const q = await API.get('questions', 'id', id, 'id,code,org_id,course_id,module_id,type,topic,subtopic,specialty,difficulty,stem,options,image_url,workflow_status,evidence_status,draft_status,current_version,published_version,review_reason,last_evidence_reviewed_at,evidence_review_due_at,evidence_exempt,evidence_exempt_reason,ai_generated,clinical_setting,target_roles,target_level,learning_objective,guideline_topic,created_at,updated_at');
    if (!ctx.alive()) return;
    if (!q) { el.innerHTML = `<div class="card">${empty('Savol topilmadi yoki ko\'rish uchun ruxsat yo\'q', id)}</div>`; return; }
    ctx.setTitle('Savol ' + (q.code || q.id));
    const acts = [];
    if (PERMS.any('evidence.review', 'question.review')) acts.push(`<a class="btn primary" href="#/evidence/review/${encodeURIComponent(q.id)}" data-act="open-review">Review ochish</a>`);
    if (PERMS.can('question.edit') && q.workflow_status === 'draft') acts.push(`<button class="btn" data-act="to-evidence-review">Evidence review'ga yuborish</button>`);
    if (PERMS.can('question.publish') && (q.workflow_status !== 'published' || q.draft_status) && !['deprecated', 'archived'].includes(q.workflow_status)) acts.push(`<button class="btn green" data-act="publish">${q.draft_status ? 'Yangi versiyani nashr qilish' : 'Publish'}</button>`);
    if (PERMS.can('question.deprecate') && !['deprecated', 'archived'].includes(q.workflow_status)) acts.push(`<button class="btn red" data-act="deprecate">Deprecate</button>`);
    el.innerHTML = `<div class="adm-h"><div><div class="sub"><a href="#/questions">← Savollar banki</a></div><h1>${esc(q.code || q.id)}</h1>
      <div class="row" style="margin-top:6px">${badge('workflow', q.workflow_status)} ${badge('evidence', q.evidence_status)} <span class="badge">v${q.current_version}${q.published_version ? ' · nashr v' + q.published_version : ''}</span>${q.ai_generated ? ' <span class="badge b-violet">AI</span>' : ''}${q.review_reason ? ` <span class="small muted">sabab: ${esc(q.review_reason)}</span>` : ''}</div></div>
      <div class="act">${acts.join('')}</div></div>
      <div class="tabs">${TABS.map(([k, l]) => `<a href="#/questions/${encodeURIComponent(q.id)}?tab=${k}" class="${tab === k ? 'on' : ''}" data-tab="${k}">${l}${(k === 'answer' || k === 'explanation') && !canSeeAnswer() ? ' 🔒' : ''}</a>`).join('')}</div><div data-tab-body>${skeleton(3)}</div>`;
    const body = el.querySelector('[data-tab-body]');
    el.querySelectorAll('[data-act]').forEach(b => b.addEventListener('click', e => { const a = b.getAttribute('data-act'); if (a === 'open-review') return; e.preventDefault(); doAction(a, q, ctx); }));
    try { await renderTab(tab, q, body, ctx); } catch (e) { if (ctx.alive()) body.innerHTML = errorBox(API.friendly(e)); }
  });

  async function renderTab(tab, q, body, ctx) {
    if (tab === 'question') {
      body.innerHTML = `<div class="grid g2"><div class="card"><h3>Savol</h3><div class="qtext" data-stem>${esc(q.stem)}</div>${q.image_url ? `<div class="small muted">Rasm: ${esc(q.image_url)}</div>` : ''}</div>
        <div class="card"><h3>Metadata</h3><dl class="kv"><dt>Kurs</dt><dd>${esc(q.course_id)}</dd><dt>Modul</dt><dd>${esc(q.module_id || '—')}</dd><dt>Tur</dt><dd>${esc(TYPES[q.type] || q.type)}</dd>
        <dt>Mutaxassislik</dt><dd>${esc(q.specialty || '—')}</dd><dt>Mavzu / submavzu</dt><dd>${esc(q.topic || '—')} / ${esc(q.subtopic || '—')}</dd><dt>Qiyinlik</dt><dd>${esc(q.difficulty)}</dd>
        <dt>Klinik muhit</dt><dd>${esc(q.clinical_setting || '—')}</dd><dt>Target rol / daraja</dt><dd>${esc((q.target_roles || []).join(', ') || '—')} / ${esc(q.target_level || '—')}</dd>
        <dt>Learning objective</dt><dd>${esc(q.learning_objective || '—')}</dd><dt>Guideline mavzusi</dt><dd>${esc(q.guideline_topic || '—')}</dd>
        <dt>Oxirgi evidence review</dt><dd>${fmtDT(q.last_evidence_reviewed_at)}</dd><dt>Keyingi review muddati</dt><dd>${fmtDate(q.evidence_review_due_at)}</dd>
        <dt>Evidence'dan ozod</dt><dd>${q.evidence_exempt ? 'Ha — ' + esc(q.evidence_exempt_reason) : 'Yo\'q'}</dd><dt>Yangilangan</dt><dd>${fmtDT(q.updated_at)}</dd></dl></div></div>
        ${PERMS.can('question.publish') ? `<div class="card" style="margin-top:14px"><h3>Nashr shartlari (ma'lumot uchun — server baribir tekshiradi)</h3><div data-gates>${skeleton(2)}</div></div>` : ''}`;
      if (PERMS.can('question.publish')) { const g = await gateInfo(q); if (ctx.alive()) body.querySelector('[data-gates]').innerHTML = g.map(([l, ok]) => `<div class="row" style="padding:3px 0">${ok ? '✅' : '⬜'} ${esc(l)}</div>`).join(''); }
    } else if (tab === 'options') {
      const opts = Array.isArray(q.options) ? q.options : [];
      body.innerHTML = `<div class="card"><h3>Variantlar</h3>${opts.length ? opts.map((o, i) => `<div class="opt">${String.fromCharCode(65 + i)}. ${esc(Array.isArray(o) ? o.join(' ↔ ') : (typeof o === 'object' ? JSON.stringify(o) : o))}</div>`).join('') : empty('Variantlar yo\'q (qisqa javob turi)')}
        <div class="tiny">To'g'ri javob bu yerda belgilanmaydi — "Correct Answer" tabida (faqat ruxsatli rollar).</div></div>`;
    } else if (tab === 'answer' || tab === 'explanation') {
      if (!canSeeAnswer()) { body.innerHTML = UI.denied('To\'g\'ri javob / izoh'); return; }
      const a = await API.get('questions', 'id', q.id, 'answer,explanation,evidence,reading');
      if (!ctx.alive()) return;
      if (!a) { body.innerHTML = UI.denied('To\'g\'ri javob'); return; }
      const opts = Array.isArray(q.options) ? q.options : [];
      if (tab === 'answer') {
        const ans = a.answer; const idx = Array.isArray(ans) && q.type !== 'match' && q.type !== 'short' ? ans : typeof ans === 'number' ? [ans] : null;
        body.innerHTML = `<div class="card" data-answer><h3>To'g'ri javob</h3>${idx ? opts.map((o, i) => `<div class="opt ${idx.includes(i) ? 'ok' : ''}">${idx.includes(i) ? '✔ ' : ''}${String.fromCharCode(65 + i)}. ${esc(Array.isArray(o) ? o.join(' ↔ ') : o)}</div>`).join('')
          : `<pre class="mono">${esc(JSON.stringify(ans, null, 1))}</pre>`}<div class="tiny">Bu ma'lumot faqat ruxsatli admin/reviewer'ga serverdan yuklandi; xodim ilovasiga hech qachon yuborilmaydi.</div></div>`;
      } else body.innerHTML = `<div class="card"><h3>Izoh (explanation)</h3><div class="qtext">${esc(a.explanation || '—')}</div>${a.reading ? `<h3 style="margin-top:12px">O'qish uchun</h3><div class="qtext">${esc(a.reading)}</div>` : ''}${a.evidence ? `<h3 style="margin-top:12px">Eski matnli dalil (legacy)</h3><div class="qtext small">${esc(a.evidence)}</div><div class="tiny">Legacy matn — tasdiqlangan manba hisoblanmaydi.</div>` : ''}</div>`;
    } else if (tab === 'evidence') {
      await window.EVIDENCE.renderQuestionEvidence(q, body, ctx, false);
    } else if (tab === 'review') {
      const [rv, as] = await Promise.all([API.list('question_reviews', { select: 'id,version_no,review_type,reviewer_id,decision,internal_notes,created_at', eq: { question_id: q.id }, order: ['created_at', false], all: true, count: false }),
        API.list('question_review_assignments', { select: 'id,reviewer_id,review_type,status,due_at,created_at', eq: { question_id: q.id }, order: ['created_at', false], all: true, count: false }).catch(() => ({ rows: [] }))]);
      const ids = [...new Set([...rv.rows.map(r => r.reviewer_id), ...as.rows.map(r => r.reviewer_id)])];
      const ppl = ids.length ? Object.fromEntries((await API.list('profiles', { select: 'id,full_name,email,role', in: { id: ids }, all: true, count: false }).catch(() => ({ rows: [] }))).rows.map(p => [p.id, p])) : {};
      const who = id => ppl[id] ? esc(ppl[id].full_name || ppl[id].email) + `<div class="sub">${esc(PERMS.ROLE_LABEL[ppl[id].role] || '')}</div>` : `<span class="mono">${esc((id || '').slice(0, 8))}</span>`;
      body.innerHTML = `<div class="card"><h3>Review tarixi (o'zgarmas)</h3>${table(rv.rows, [{ h: 'Vaqt', r: x => fmtDT(x.created_at) }, { h: 'Tur', r: x => esc(x.review_type) }, { h: 'Versiya', r: x => 'v' + x.version_no },
        { h: 'Reviewer', r: x => who(x.reviewer_id) }, { h: 'Qaror', r: x => badge('decision', x.decision) }, { h: 'Ichki izoh', r: x => esc(x.internal_notes || '') }], { empty: 'Hali review qilinmagan', id: 'reviews' })}</div>
        <div class="card" style="margin-top:14px"><h3>Review tayinlovlari</h3>${table(as.rows, [{ h: 'Tur', r: x => esc(x.review_type) }, { h: 'Reviewer', r: x => who(x.reviewer_id) }, { h: 'Holat', r: x => badge('generic', x.status) }, { h: 'Muddat', r: x => fmtDate(x.due_at) }], { empty: 'Tayinlov yo\'q' })}</div>`;
    } else if (tab === 'versions') {
      const [v, p] = await Promise.all([API.list('question_versions', { select: 'id,version_no,change_reason,created_at,created_by', eq: { question_id: q.id }, order: ['version_no', false], all: true, count: false }),
        API.list('question_publications', { select: 'version_no,evidence_status,published_at', eq: { question_id: q.id }, order: ['published_at', true], all: true, count: false }).catch(() => ({ rows: [] }))]);
      const pubs = p.rows; const pubOf = n => pubs.find(x => x.version_no === n);
      const supersededAt = n => { const i = pubs.findIndex(x => x.version_no === n); return i >= 0 && pubs[i + 1] ? pubs[i + 1].published_at : null; };
      body.innerHTML = `<div class="card"><h3>Versiyalar (o'zgarmas snapshot'lar)</h3><div class="note" style="margin-bottom:10px">Tarixiy urinishlar o'zlari topshirilgan versiyani ko'rsatadi. Joriy versiya: v${q.current_version}; imtihonda xizmat qilayotgan: ${q.published_version ? 'v' + q.published_version : 'yo\'q'}.</div>
        ${table(v.rows, [{ h: 'Versiya', r: x => `<b>v${x.version_no}</b>${x.version_no === q.published_version ? ' ' + badge('workflow', 'published') : ''}${x.version_no === q.current_version && x.version_no !== q.published_version ? ' <span class="badge">ishchi</span>' : ''}` },
          { h: 'Yaratilgan', r: x => fmtDT(x.created_at) }, { h: 'Nashr qilingan', r: x => pubOf(x.version_no) ? fmtDT(pubOf(x.version_no).published_at) : '—' },
          { h: 'Nashrdagi evidence', r: x => pubOf(x.version_no) ? badge('evidence', pubOf(x.version_no).evidence_status) : '—' }, { h: 'Almashtirilgan', r: x => fmtDT(supersededAt(x.version_no)) }, { h: 'Sabab', r: x => esc(x.change_reason || '') }], { empty: 'Versiya yo\'q', id: 'versions' })}</div>`;
    }
  }

  async function doAction(a, q, ctx) {
    try {
      if (a === 'to-evidence-review') {
        if (!await dialog({ title: 'Evidence review\'ga yuborish', body: 'Savol "Evidence Review" bosqichiga o\'tadi. Imtihon yaroqliligi o\'zgarmaydi.', okText: 'Yuborish' })) return;
        await API.update('questions', 'id', q.id, { workflow_status: 'evidence_review' }); toast('Evidence review\'ga yuborildi');
      } else if (a === 'publish') {
        const r = await dialog({ title: 'Nashr qilish', body: 'Server nashr shartlarini tekshiradi: evidence current, tasdiqlangan asosiy manba, klinik savol uchun medical review. Shart bajarilmasa nashr rad etiladi.', fields: [{ name: 'ok', type: 'check', label: 'Savol mazmuni va manbalarini tekshirdim', required: true }], okText: 'Publish' });
        if (!r) return;
        await API.update('questions', 'id', q.id, q.published_version && q.draft_status ? { draft_status: 'publish' } : { workflow_status: 'published' }); toast('Nashr qilindi');
      } else if (a === 'deprecate') {
        const r = await dialog({ title: 'Deprecate', body: 'Savol yangi imtihonlardan chiqariladi. Tarixiy urinishlar va versiyalar o\'zgarmaydi.', danger: true, okText: 'Deprecate', fields: [{ name: 'ok', type: 'check', label: 'Tushunaman: bu savol yangi imtihonlarda ishlatilmaydi', required: true }] });
        if (!r) return;
        await API.update('questions', 'id', q.id, { workflow_status: 'deprecated' }); toast('Deprecated');
      }
      ADMIN.render();
    } catch (e) { toast(API.friendly(e).message, true); }
  }
  window.QBANK = { TYPES, trunc };
})();
