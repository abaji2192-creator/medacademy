/* Evidence: Review Queue, Review workspace (Question → Evidence → Claim → Review → Decision), Evidence Library, manba kartasi.
   Soxta ma'lumot yo'q: yangi manba har doim "Unverified"; "Verified" faqat evidence.verify ruxsati bilan, inson tasdig'i orqali. */
(function () {
  const { esc, badge, table, empty, errorBox, skeleton, fmtDT, fmtDate, toast, dialog } = UI;
  const { listPage, lookup } = ADMINLIB;
  const SRC_TYPES = ['guideline', 'systematic_review', 'meta_analysis', 'randomized_controlled_trial', 'cohort_study', 'case_control_study', 'observational_study', 'narrative_review',
    'textbook', 'hospital_sop', 'local_protocol', 'institutional_policy', 'professional_standard', 'expert_consensus', 'other'];
  const REL = [['primary_support', 'Asosiy dalil (primary support)'], ['additional_support', 'Qo\'shimcha dalil'], ['background', 'Fon ma\'lumot'], ['conflicting_evidence', 'Ziddiyatli dalil']];
  const QUEUE = [['unknown', 'Unknown'], ['review_required', 'Review Required'], ['current', 'Current'], ['review_due', 'Review Due'], ['outdated', 'Outdated'],
    ['superseded', 'Superseded'], ['conflicting', 'Conflicting'], ['retracted', 'Retracted'], ['unverified', 'Unverified']];

  // Navbat filtri → savollar so'rovi (retracted/unverified — bog'langan manba holati bo'yicha)
  async function queueFilter(f) {
    if (!f || f === 'unknown') return { eq: { evidence_status: 'unknown' } };
    if (f === 'review_required') return { eq: { workflow_status: 'review_required' } };
    if (['current', 'review_due', 'outdated', 'superseded', 'conflicting'].includes(f)) return { eq: { evidence_status: f } };
    const src = await API.list('evidence_sources', { select: 'id', ...(f === 'retracted' ? { in: { status: ['retracted', 'withdrawn'] } } : { eq: { verification_status: 'unverified' } }), all: true, count: false });
    if (!src.rows.length) return { in: { id: [] } };
    const qe = await API.list('question_evidence', { select: 'question_id', in: { evidence_source_id: src.rows.map(s => s.id) }, all: true, count: false });
    return { in: { id: [...new Set(qe.rows.map(r => r.question_id))] } };
  }

  ADMIN.route('/evidence/queue', 'evidence_queue', async (el, ctx) => {
    const courses = await lookup('courses', 'title');
    const kpi = async () => { const out = {}; await Promise.all(QUEUE.map(async ([v]) => { out[v] = await API.count('questions', await queueFilter(v)).catch(() => '—'); })); return out; };
    const counts = await kpi(); if (!ctx.alive()) return;
    const top = `<div class="kpis">${[['unknown', 'Unknown evidence', 'warn'], ['review_required', 'Review Required', 'bad'], ['review_due', 'Review Due', 'warn'], ['current', 'Current', 'ok'], ['conflicting', 'Conflicting', 'bad'], ['unverified', 'Unverified manbali', 'warn']]
      .map(([k, l, c]) => `<div class="kpi ${c}" data-kpi="${k}"><div class="v">${counts[k]}</div><div class="l">${esc(l)}</div></div>`).join('')}</div>`;
    if (!ctx.query.f) ctx.query.f = 'unknown';
    await listPage(el, ctx, {
      title: 'Evidence Review Queue', id: 'queue', top,
      sub: 'Oddiy oqim: <b>Question → Evidence → Claim → Review → Decision</b>. Qatorni oching.',
      chips: { key: 'f', items: QUEUE, counts: async () => counts },
      filters: [{ key: 's', type: 'search', label: 'Savol matni yoki kodi' }, { key: 'course', type: 'select', label: 'Kurs', options: Object.entries(courses) },
        { key: 'sort', type: 'select', label: 'Tartib', options: [['due', 'Review muddati (yaqini oldin)'], ['updated', 'Oxirgi o\'zgarish'], ['reviewed', 'Oxirgi review (eskisi oldin)']] }],
      load: async q => { const o = await queueFilter(q.f); o.eq = { ...(o.eq || {}), course_id: q.course }; o.search = { cols: ['stem', 'code', 'id'], q: q.s };
        const order = q.sort === 'updated' ? ['updated_at', false] : q.sort === 'reviewed' ? ['last_evidence_reviewed_at', true] : ['evidence_review_due_at', true];
        return API.list('questions', { select: 'id,code,course_id,topic,stem,workflow_status,evidence_status,last_evidence_reviewed_at,evidence_review_due_at,review_reason,updated_at', ...o, order, page: q.page, size: q.size }); },
      href: x => '#/evidence/review/' + encodeURIComponent(x.id),
      columns: [{ h: 'Savol', r: x => `${esc(QBANK.trunc(x.stem, 90))}<div class="sub mono">${esc(x.code || x.id)}</div>` }, { h: 'Kurs', r: x => esc(courses[x.course_id] || x.course_id) },
        { h: 'Evidence', r: x => badge('evidence', x.evidence_status) + (x.review_reason ? `<div class="sub">${esc(x.review_reason)}</div>` : '') }, { h: 'Workflow', r: x => badge('workflow', x.workflow_status) },
        { h: 'Oxirgi review', r: x => fmtDate(x.last_evidence_reviewed_at) }, { h: 'Muddat', r: x => fmtDate(x.evidence_review_due_at) },
        { h: '', r: x => `<a class="btn sm" href="#/evidence/review/${encodeURIComponent(x.id)}" data-act="open">Ochish</a>` }],
      empty: 'Bu navbatda savol yo\'q',
    });
  });

  // ---------- Savolga bog'langan dalillar (savol kartasi va review workspace) ----------
  async function renderQuestionEvidence(q, box, ctx, editable) {
    const ev = await API.list('question_evidence', { select: 'id,evidence_source_id,relationship_type,citation_text,supporting_claim,section_reference,recommendation_class,level_of_evidence,created_at', eq: { question_id: q.id }, all: true, count: false });
    const ids = ev.rows.map(r => r.evidence_source_id);
    const src = ids.length ? Object.fromEntries((await API.list('evidence_sources', { select: 'id,title,source_type,organization,guideline_name,guideline_version,publication_year,publication_date,doi,pmid,url,status,verification_status,evidence_level,scope_type', in: { id: ids }, all: true, count: false })).rows.map(s => [s.id, s])) : {};
    if (!ctx.alive()) return;
    const canDetach = editable && PERMS.can('evidence.review');
    box.innerHTML = `<div class="card" data-evidence-list><h3>Bog'langan dalillar</h3>${ev.rows.length ? ev.rows.map(r => { const s = src[r.evidence_source_id] || {};
      return `<div class="opt" data-ev-row="${esc(r.id)}"><div class="row between"><b>${esc(s.title || 'Manba (ko\'rish uchun ruxsat yo\'q)')}</b><span>${badge('verification', s.verification_status)} ${badge('source', s.status)}</span></div>
        <div class="small muted">${esc(REL.find(x => x[0] === r.relationship_type)?.[1] || r.relationship_type)} · ${esc(s.source_type || '')}${s.organization ? ' · ' + esc(s.organization) : ''}${s.guideline_version ? ' · versiya ' + esc(s.guideline_version) : ''}${s.publication_year ? ' · ' + s.publication_year : ''}</div>
        <div class="small">${s.doi ? 'DOI: <span class="mono">' + esc(s.doi) + '</span> ' : ''}${s.pmid ? 'PMID: <span class="mono">' + esc(s.pmid) + '</span> ' : ''}${s.url ? `<a href="${esc(s.url)}" target="_blank" rel="noopener noreferrer">havola</a>` : ''}${!s.doi && !s.pmid && !s.url ? '<span class="tiny">Identifikator yo\'q</span>' : ''}</div>
        ${r.supporting_claim ? `<div style="margin-top:6px"><span class="tiny">Da'vo (claim):</span> ${esc(r.supporting_claim)}</div>` : ''}${r.citation_text ? `<div class="small muted">Iqtibos: ${esc(r.citation_text)}</div>` : ''}
        ${canDetach ? `<button class="btn sm" data-detach="${esc(r.id)}" style="margin-top:6px">Uzish</button>` : ''}</div>`; }).join('') : empty('Dalil bog\'lanmagan', 'Klinik savol uchun kamida bitta tasdiqlangan asosiy manba kerak.')}</div>`;
    box.querySelectorAll('[data-detach]').forEach(b => b.onclick = async () => {
      if (!await dialog({ title: 'Dalilni uzish', body: 'Bog\'lanish o\'chiriladi (manbaning o\'zi kutubxonada qoladi). Savol evidence holati server tomonidan qayta hisoblanadi.', danger: true, okText: 'Uzish' })) return;
      try { await API.remove('question_evidence', 'id', b.getAttribute('data-detach')); toast('Uzildi'); ADMIN.render(); } catch (e) { toast(API.friendly(e).message, true); }
    });
  }

  // ---------- 005e: savol holati (oxirgi qaror semantikasi; yaroqlilik — server javobi) ----------
  const DEFAULT_CLINICAL = ['medical', 'public_health', 'safety'];
  const MED_ROLES = ['medical_reviewer', 'super_admin'];
  async function reviewStatus(q) {
    const [course, pol, rv, elig] = await Promise.all([
      API.get('courses', 'id', q.course_id, 'id,domain').catch(() => null),
      API.list('content_policies', { select: 'clinical_domains,clinical_requires_medical_review', size: 1, count: false }).catch(() => ({ rows: [] })),
      API.list('question_reviews', { select: 'id,review_type,version_no,decision,reviewer_id,reviewer_role_at_creation,review_seq,created_at,internal_notes', eq: { question_id: q.id }, order: ['review_seq', false], all: true, count: false }).catch(() => ({ rows: [] })),
      // 006a: bitta savol uchun server RPC (question_eligibility); mavjud bo'lmasa (006a'gacha) — question_meta
      API.rpc('question_eligibility', { p_question: q.id }).catch(() => null)]);
    const meta = elig ? null : await API.rpc('question_meta').catch(() => null);
    const p = pol.rows[0] || {};
    const domains = Array.isArray(p.clinical_domains) && p.clinical_domains.length ? p.clinical_domains : DEFAULT_CLINICAL;
    const clinical = !!(course && domains.includes(course.domain));
    const medRequired = elig ? !!elig.medical_review_required : clinical && p.clinical_requires_medical_review !== false;
    const rows = rv.rows;   // review_seq bo'yicha kamayish tartibida (oxirgisi birinchi)
    const latestEvidence = rows.find(r => r.review_type === 'evidence') || null;
    const validMed = v => rows.find(r => r.review_type === 'medical' && r.version_no === v && MED_ROLES.includes(r.reviewer_role_at_creation)) || null;
    const latestMedical = validMed(q.current_version);
    const latestMedicalPublished = q.published_version ? validMed(q.published_version) : null;
    const eligible = elig ? !!elig.eligible : Array.isArray(meta) ? meta.some(m => m.id === q.id) : null;   // serverning _q_exam_eligible natijasi
    const evBlocked = latestEvidence && ['rejected', 'changes_requested'].includes(latestEvidence.decision);
    let reason = q.review_reason || null;
    if (!reason && evBlocked) reason = 'evidence_' + latestEvidence.decision;
    if (!reason && medRequired && latestMedical && latestMedical.decision !== 'approved') reason = 'medical_' + latestMedical.decision;
    return { course, clinical: elig ? !!elig.clinical : clinical, medRequired, source: elig ? 'question_eligibility' : 'question_meta', rows, latestEvidence, latestMedical, latestMedicalPublished, eligible, evBlocked, reason };
  }
  const decisionBadge = r => r ? badge('decision', r.decision) : '<span class="badge">—</span>';
  async function statusPanel(q, st) {
    const last = st.rows[0] || null;
    const ppl = last ? await API.list('profiles', { select: 'id,full_name,email', in: { id: [last.reviewer_id] }, all: true, count: false }).catch(() => ({ rows: [] })) : { rows: [] };
    const who = last ? (ppl.rows[0] ? esc(ppl.rows[0].full_name || ppl.rows[0].email) : `<span class="mono">${esc((last.reviewer_id || '').slice(0, 8))}</span>`) : '—';
    const medCell = !st.medRequired ? `<span class="badge" data-med="not_required">Not required</span> <span class="small muted">klinik emas kurs${st.course ? ' (' + esc(st.course.domain) + ')' : ''}</span>`
      : st.latestMedical ? decisionBadge(st.latestMedical) + ` <span class="small muted">v${st.latestMedical.version_no}</span>` : '<span class="badge b-amber" data-med="pending">Kutilmoqda</span>';
    const elig = st.eligible === null ? '<span class="badge">Noma\'lum</span>' : st.eligible ? '<span class="badge b-green" data-eligible="true">✓ ELIGIBLE</span>' : '<span class="badge b-red" data-eligible="false">✕ INELIGIBLE</span>';
    return `<div class="card" data-status-panel><h3>Question status</h3><dl class="kv">
      <dt>Evidence</dt><dd>${badge('evidence', q.evidence_status)} ${st.latestEvidence ? '· oxirgi qaror: ' + decisionBadge(st.latestEvidence) : ''}</dd>
      <dt>Medical Review</dt><dd data-med-cell>${medCell}</dd>
      <dt>Exam eligibility (yangi imtihonlar)</dt><dd>${elig} <span class="tiny" data-elig-src="${esc(st.source)}">server: ${esc(st.source)}</span></dd>
      <dt>Sabab</dt><dd>${st.reason ? badge('reason', st.reason) : '—'}</dd>
      <dt>Oxirgi qaror</dt><dd>${last ? esc(last.review_type) + ' · ' + decisionBadge(last) + ' · v' + last.version_no : '—'}</dd>
      <dt>Reviewer</dt><dd>${who}</dd>
      <dt>Reviewer roli (yozilgan paytda)</dt><dd>${last ? esc(PERMS.ROLE_LABEL[last.reviewer_role_at_creation] || last.reviewer_role_at_creation || 'qayd etilmagan (005e oldi)') : '—'}</dd>
      <dt>Oxirgi o'zgarish</dt><dd>${last ? fmtDT(last.created_at) : '—'}</dd></dl>
      <div class="tiny">Faqat joriy versiya (v${q.current_version}) uchun oxirgi qaror hisobga olinadi; eski versiya tasdig'i yangi versiyaga o'tmaydi. Server baribir qayta tekshiradi.</div></div>`;
  }

  // ---------- Review workspace ----------
  ADMIN.route('/evidence/review/:id', 'evidence_queue', async (el, ctx) => {
    const id = decodeURIComponent(ctx.params.id);
    const q = await API.get('questions', 'id', id, 'id,code,course_id,type,topic,stem,options,workflow_status,evidence_status,current_version,published_version,draft_status,evidence_review_due_at,last_evidence_reviewed_at,review_reason');
    if (!ctx.alive()) return;
    if (!q) { el.innerHTML = `<div class="card">${empty('Savol topilmadi yoki ruxsat yo\'q', id)}</div>`; return; }
    ctx.setTitle('Review: ' + (q.code || q.id));
    const stage = q.workflow_status === 'published' && !q.draft_status ? 4 : q.evidence_status === 'current' ? 3 : 1;
    const st = await reviewStatus(q); if (!ctx.alive()) return;
    const canEv = PERMS.can('evidence.review'), canMed = PERMS.canMedicalReview() && st.medRequired;
    el.innerHTML = `<div class="adm-h"><div><div class="sub"><a href="#/evidence/queue">← Review Queue</a> · <a href="#/questions/${encodeURIComponent(q.id)}">Savol kartasi</a></div><h1>Review: ${esc(q.code || q.id)}</h1>
      <div class="steps">${['1. Question', '2. Evidence', '3. Claim', '4. Review', '5. Decision'].map((s, i) => `<span class="${i < stage ? 'done' : i === stage ? 'cur' : ''}">${s}</span>`).join('')}</div>
      <div class="row">${badge('workflow', q.workflow_status)} ${badge('evidence', q.evidence_status)} <span class="badge">v${q.current_version}</span></div></div></div>
      <div class="grid g2"><div><div class="card"><h3>1. Savol</h3><div class="qtext">${esc(q.stem)}</div>${(Array.isArray(q.options) ? q.options : []).map((o, i) => `<div class="opt">${String.fromCharCode(65 + i)}. ${esc(Array.isArray(o) ? o.join(' ↔ ') : o)}</div>`).join('')}
        <div class="small"><a href="#/questions/${encodeURIComponent(q.id)}?tab=answer">To'g'ri javobni ko'rish →</a></div></div>
        <div style="margin-top:14px" data-ev></div>
        ${PERMS.can('evidence.manage') ? `<div class="card" style="margin-top:14px"><h3>2–3. Dalil va da'vo (claim) bog'lash</h3>
          <form data-attach><label>Manba (Evidence Library'dan qidirish)</label><input type="search" data-src-q placeholder="Sarlavha, tashkilot, DOI…"><select name="source" required data-src-sel><option value="">— manba tanlang —</option></select>
          <div class="tiny">Kerakli manba yo'qmi? <a href="#/evidence/library/new">Kutubxonaga qo'shing</a> (Unverified holatda yaratiladi).</div>
          <label>Bog'lanish turi</label><select name="rel">${REL.map(r => `<option value="${r[0]}">${esc(r[1])}</option>`).join('')}</select>
          <label>Qo'llab-quvvatlanadigan da'vo (supporting claim) *</label><textarea name="claim" rows="2" required placeholder="Manbada aynan nima deyilgani (o'z so'zlaringiz bilan)"></textarea>
          <label>Bo'lim / sahifa (section reference)</label><input name="section"><div class="small" data-err style="color:#b91c1c"></div>
          <button class="btn primary" style="margin-top:10px">Bog'lash</button></form></div>` : ''}</div>
      <div><div data-status>${await statusPanel(q, st)}</div>
        <div class="card" style="margin-top:14px"><h3>4–5. Review va qaror</h3>${!st.medRequired ? `<div class="note" data-med-not-required>Medical Review talab qilinmaydi (klinik emas kurs).</div>` : ''}${canEv || canMed ? `<form data-review>
          <label>Review turi</label><select name="type">${canEv ? '<option value="evidence">Evidence review</option>' : ''}${canMed ? '<option value="medical">Medical review (klinik tasdiq)</option>' : ''}</select>
          <label>Qaror</label><select name="decision"></select>
          <label class="check"><input type="checkbox" name="c1"> <span>Manba(lar)ni asl nusxada tekshirdim (DOI/PMID/guideline versiyasi)</span></label>
          <label class="check"><input type="checkbox" name="c2"> <span>Savol va to'g'ri javob manbadagi tavsiyaga mos</span></label>
          <label class="check"><input type="checkbox" name="c3"> <span>Manba joriy (superseded / retracted emas)</span></label>
          <label data-notes-label>Ichki izoh (faqat reviewer'lar ko'radi)</label><textarea name="notes" rows="3"></textarea>
          <div class="small" data-err style="color:#b91c1c"></div><button class="btn primary" style="margin-top:10px">Qarorni yuborish</button>
          <div class="tiny" style="margin-top:6px">Evidence holati faqat server tomonidan review natijasiga qarab o'zgaradi (to'g'ridan-to'g'ri o'zgartirib bo'lmaydi).</div></form>`
        : `<div class="note">Sizda review qilish ruxsati yo'q.</div>`}</div>
        ${PERMS.canAssignReview() && st.medRequired ? `<div class="card" style="margin-top:14px"><h3>Medical review'ga yuborish</h3><form data-assign><label>Medical reviewer</label><select name="rev" data-rev-sel><option value="">yuklanmoqda…</option></select>
          <label>Muddat</label><input type="date" name="due"><button class="btn" style="margin-top:10px">Tayinlash</button></form></div>` : ''}
        <div class="card" style="margin-top:14px"><h3>Review tarixi</h3><div data-hist>${skeleton(2)}</div></div></div></div>`;
    await renderQuestionEvidence(q, el.querySelector('[data-ev]'), ctx, true);
    // review tarixi
    el.querySelector('[data-hist]').innerHTML = st.rows.length ? st.rows.map(x => `<div class="row between small" style="padding:4px 0" data-hist-row><span>${esc(x.review_type)} · v${x.version_no} · ${fmtDT(x.created_at)} · <span class="muted">${esc(PERMS.ROLE_LABEL[x.reviewer_role_at_creation] || x.reviewer_role_at_creation || '—')}</span></span>${badge('decision', x.decision)}</div>`).join('') : empty('Hali review yo\'q');
    // manba qidiruvi
    const af = el.querySelector('[data-attach]');
    if (af) {
      const sel = af.querySelector('[data-src-sel]');
      const search = UI.debounce(async s => { try { const r = await API.list('evidence_sources', { select: 'id,title,organization,guideline_version,verification_status,status', search: { cols: ['title', 'organization', 'doi', 'guideline_name'], q: s }, in: { status: ['active', 'draft'] }, order: ['title', true], size: 30, count: false });
        sel.innerHTML = '<option value="">— manba tanlang —</option>' + r.rows.map(x => `<option value="${esc(x.id)}">${esc(x.title)}${x.guideline_version ? ' (' + esc(x.guideline_version) + ')' : ''} — ${esc(UI.LABELS.verification[x.verification_status]?.[0] || x.verification_status)}</option>`).join('');
        if (!r.rows.length) sel.innerHTML = '<option value="">Manba topilmadi — kutubxonaga qo\'shing</option>'; } catch (e) { sel.innerHTML = '<option value="">' + esc(API.friendly(e).message) + '</option>'; } }, 300);
      af.querySelector('[data-src-q]').addEventListener('input', e => search(e.target.value)); search('');
      af.onsubmit = async e => { e.preventDefault(); const err = af.querySelector('[data-err]'); err.textContent = '';
        if (!af.source.value) { err.textContent = 'Manba tanlang'; return; } if (!af.claim.value.trim()) { err.textContent = 'Da\'vo (claim) majburiy'; return; }
        try { await API.insert('question_evidence', { org_id: PERMS.state.profile.org_id, question_id: q.id, evidence_source_id: af.source.value, relationship_type: af.rel.value,
          supporting_claim: af.claim.value.trim(), section_reference: af.section.value.trim() || null }); toast('Dalil bog\'landi'); ADMIN.render(); } catch (e2) { err.textContent = API.friendly(e2).message; } };
    }
    const rf = el.querySelector('[data-review]');
    // 005e: qaror turlari review turiga bog'liq (mark_* faqat evidence; medical — approved / rejected / changes_requested)
    const DEC = { evidence: ['approved', 'changes_requested', 'rejected', 'mark_outdated', 'mark_conflicting'], medical: ['approved', 'rejected', 'changes_requested'] };
    const DEC_LABEL = { approved: 'Approve', changes_requested: 'Request changes', rejected: 'Reject', mark_outdated: 'Mark outdated (manba eskirgan)', mark_conflicting: 'Mark conflicting (ziddiyatli dalil)' };
    const syncDec = () => { const t = rf.type.value; rf.decision.innerHTML = (DEC[t] || []).map(d => `<option value="${d}">${esc(DEC_LABEL[d])}</option>`).join('');
      rf.querySelector('[data-notes-label]').textContent = t === 'medical' ? 'Sabab (majburiy)' : 'Ichki izoh (faqat reviewer\'lar ko\'radi)'; };
    if (rf) { syncDec(); rf.type.addEventListener('change', syncDec); }
    if (rf) rf.onsubmit = async e => { e.preventDefault(); const err = rf.querySelector('[data-err]'); err.textContent = '';
      const dec = rf.decision.value, type = rf.type.value;
      if (!(DEC[type] || []).includes(dec)) { err.textContent = 'Bu review turi uchun qaror mavjud emas'; return; }
      if (dec === 'approved' && !(rf.c1.checked && rf.c2.checked && rf.c3.checked)) { err.textContent = 'Approve uchun uchala tekshiruv belgilanishi shart'; return; }
      if ((type === 'medical' || dec !== 'approved') && !rf.notes.value.trim()) { err.textContent = type === 'medical' ? 'Medical review uchun sabab majburiy' : 'Bu qaror uchun ichki izoh (sabab) majburiy'; return; }
      const medNote = type === 'medical' ? '<div class="note warn" style="margin-top:8px">Bu medical review qarori klinik savolning <b>yangi imtihonlarga</b> yaroqliligiga ta\'sir qiladi (This medical review decision affects eligibility for future clinical exams).</div>' : '';
      if (!await dialog({ title: 'Qarorni tasdiqlash', body: `${esc(type === 'medical' ? 'Medical' : 'Evidence')} review: <b>${esc(UI.LABELS.decision[dec][0])}</b> (v${q.current_version}). Review yozuvlari o'zgarmas.${medNote}`, okText: 'Yuborish', danger: dec !== 'approved' })) return;
      try { await API.insert('question_reviews', { org_id: PERMS.state.profile.org_id, question_id: q.id, version_no: q.current_version, review_type: type, reviewer_id: PERMS.state.profile.id, decision: dec,
        internal_notes: rf.notes.value.trim() || null, checklist: { source_checked: rf.c1.checked, answer_matches: rf.c2.checked, source_current: rf.c3.checked } });
        toast('Review saqlandi'); ADMIN.render(); } catch (e2) { err.textContent = API.friendly(e2).message; } };
    const asf = el.querySelector('[data-assign]');
    if (asf) {
      API.list('profiles', { select: 'id,full_name,email', eq: { role: 'medical_reviewer', status: 'active' }, all: true, count: false })
        .then(r => { asf.querySelector('[data-rev-sel]').innerHTML = r.rows.length ? r.rows.map(p => `<option value="${esc(p.id)}">${esc(p.full_name || p.email)}</option>`).join('') : '<option value="">Medical reviewer yo\'q</option>'; })
        .catch(() => { asf.querySelector('[data-rev-sel]').innerHTML = '<option value="">ro\'yxat mavjud emas</option>'; });
      asf.onsubmit = async e => { e.preventDefault(); if (!asf.rev.value) return toast('Reviewer tanlang', true);
        try { await API.insert('question_review_assignments', { org_id: PERMS.state.profile.org_id, question_id: q.id, reviewer_id: asf.rev.value, review_type: 'medical', due_at: asf.due.value || null });
          toast('Medical review tayinlandi'); ADMIN.render(); } catch (e2) { toast(API.friendly(e2).message, true); } };
    }
  });

  // ---------- Evidence Library ----------
  const SRC_COLS = 'id,title,source_type,organization,authors,publication_year,journal,doi,pmid,url,guideline_name,guideline_version,publication_date,evidence_level,status,verification_status,scope_type,origin';
  ADMIN.route('/evidence/library', 'evidence_library', (el, ctx) => listPage(el, ctx, {
    title: 'Evidence Library', id: 'library', sub: 'Global (platforma) va tashkilot manbalari. Tekshirilmagan manba har doim <b>Unverified</b> deb ko\'rsatiladi.',
    actions: PERMS.can('evidence.manage') ? `<a class="btn primary" href="#/evidence/library/new" data-act="new-source">+ Manba qo'shish</a>` : '',
    filters: [{ key: 's', type: 'search', label: 'Sarlavha, tashkilot, jurnal, DOI, PMID' }, { key: 'type', type: 'select', label: 'Turi', options: SRC_TYPES.map(t => [t, t]) },
      { key: 'status', type: 'select', label: 'Holat', options: Object.entries(UI.LABELS.source).map(([k, v]) => [k, v[0]]) },
      { key: 'ver', type: 'select', label: 'Tekshiruv', options: Object.entries(UI.LABELS.verification).map(([k, v]) => [k, v[0]]) },
      { key: 'scope', type: 'select', label: 'Doira', options: [['global', 'Global'], ['organization', 'Tashkilot']] }],
    load: q => API.list('evidence_sources', { select: SRC_COLS, eq: { source_type: q.type, status: q.status, verification_status: q.ver, scope_type: q.scope }, search: { cols: ['title', 'organization', 'journal', 'doi', 'pmid', 'guideline_name'], q: q.s }, order: ['title', true], page: q.page, size: q.size }),
    href: x => '#/evidence/library/' + x.id,
    columns: [{ h: 'Manba', r: x => `<b>${esc(x.title)}</b><div class="sub">${esc(x.organization || (x.authors || []).slice(0, 3).join(', ') || '—')}${x.journal ? ' · ' + esc(x.journal) : ''}</div>` },
      { h: 'Turi', r: x => esc(x.source_type) + `<div class="sub">${esc(x.scope_type === 'global' ? 'Global' : 'Tashkilot')}</div>` },
      { h: 'Yil / versiya', r: x => `${esc(x.publication_year || '—')}${x.guideline_version ? `<div class="sub">v ${esc(x.guideline_version)}</div>` : ''}` },
      { h: 'Identifikator', r: x => `${x.doi ? '<div class="mono">DOI ' + esc(x.doi) + '</div>' : ''}${x.pmid ? '<div class="mono">PMID ' + esc(x.pmid) + '</div>' : ''}${!x.doi && !x.pmid ? (x.url ? 'URL' : '—') : ''}` },
      { h: 'Evidence level', r: x => esc(x.evidence_level || 'Unknown') }, { h: 'Holat', r: x => badge('source', x.status) + ' ' + badge('verification', x.verification_status) }],
    empty: 'Manbalar hali qo\'shilmagan', emptySub: 'Platforma hech qanday manbani o\'ylab topmaydi — manbalarni faqat haqiqiy nashr asosida qo\'shing.',
  }));

  ADMIN.route('/evidence/library/new', 'evidence_library', async (el, ctx) => {
    ctx.setTitle('Yangi manba');
    if (!PERMS.can('evidence.manage')) { el.innerHTML = UI.denied('Manba qo\'shish'); return; }
    el.innerHTML = `<div class="adm-h"><div><div class="sub"><a href="#/evidence/library">← Evidence Library</a></div><h1>Yangi manba</h1><div class="sub">Manba <b>Unverified</b> holatda yaratiladi. Faqat haqiqatda mavjud nashr ma'lumotlarini kiriting — taxminiy DOI/PMID kiritmang.</div></div></div>
      <form class="card" data-sform><div class="grid g2">
      <div><label>Sarlavha *</label><input name="title" required minlength="4"></div><div><label>Turi *</label><select name="source_type">${SRC_TYPES.map(t => `<option value="${t}">${t}</option>`).join('')}</select></div>
      <div><label>Tashkilot (guideline uchun majburiy)</label><input name="organization" placeholder="masalan, guideline chiqargan jamiyat"></div><div><label>Mualliflar (vergul bilan)</label><input name="authors"></div>
      <div><label>Nashr yili</label><input name="publication_year" type="number" min="1800" max="2100"></div><div><label>Jurnal</label><input name="journal"></div>
      <div><label>DOI</label><input name="doi" placeholder="10.xxxx/…" pattern="10\\.[0-9]{4,9}/\\S+"></div><div><label>PMID</label><input name="pmid" pattern="[0-9]{1,9}"></div>
      <div><label>URL</label><input name="url" type="url" placeholder="https://…"></div><div><label>Guideline nomi</label><input name="guideline_name"></div>
      <div><label>Guideline versiyasi (guideline uchun majburiy)</label><input name="guideline_version"></div><div><label>Nashr sanasi</label><input name="publication_date" type="date"></div>
      <div><label>Evidence level (manbada ko'rsatilgan bo'lsa)</label><input name="evidence_level" placeholder="bo'sh qoldirilsa: Unknown"></div>
      <div><label>Yurisdiksiya</label><select name="jurisdiction"><option value="international">Xalqaro</option><option value="regional">Mintaqaviy</option><option value="national">Milliy</option><option value="local">Mahalliy</option><option value="institutional">Muassasa</option></select></div></div>
      <div class="small" data-err style="color:#b91c1c;margin-top:8px"></div><div class="row" style="margin-top:12px"><button class="btn primary">Saqlash (Unverified)</button><a class="btn" href="#/evidence/library">Bekor qilish</a></div></form>`;
    const f = el.querySelector('[data-sform]');
    f.onsubmit = async e => { e.preventDefault(); if (!f.reportValidity()) return;
      const v = n => f[n].value.trim() || null;
      const row = { org_id: PERMS.state.profile.org_id, scope_type: 'organization', title: v('title'), source_type: f.source_type.value, organization: v('organization'),
        authors: (f.authors.value || '').split(',').map(s => s.trim()).filter(Boolean), publication_year: f.publication_year.value ? +f.publication_year.value : null, journal: v('journal'),
        doi: v('doi'), pmid: v('pmid'), url: v('url'), guideline_name: v('guideline_name'), guideline_version: v('guideline_version'), publication_date: v('publication_date'),
        evidence_level: v('evidence_level'), jurisdiction: f.jurisdiction.value, status: 'active', verification_status: 'unverified', origin: 'manual' };
      try { const s = await API.insert('evidence_sources', row); toast('Manba qo\'shildi (Unverified)'); ADMIN.go('#/evidence/library/' + s.id); }
      catch (e2) { f.querySelector('[data-err]').textContent = API.friendly(e2).message; } };
  });

  ADMIN.route('/evidence/library/:id', 'evidence_library', async (el, ctx) => {
    const s = await API.get('evidence_sources', 'id', ctx.params.id, '*');
    if (!ctx.alive()) return;
    if (!s) { el.innerHTML = `<div class="card">${empty('Manba topilmadi yoki ruxsat yo\'q')}</div>`; return; }
    ctx.setTitle(s.title);
    const own = s.scope_type === 'organization';
    const acts = [];
    if (own && PERMS.can('evidence.verify') && s.verification_status !== 'verified') acts.push(`<button class="btn green" data-act="verify">Verify (tekshirildi)</button>`);
    if (own && PERMS.can('evidence.manage') && PERMS.can('evidence.review') && s.status === 'active') acts.push(`<button class="btn" data-act="superseded">Superseded deb belgilash</button><button class="btn red" data-act="retracted">Retracted deb belgilash</button>`);
    const links = await API.list('question_evidence', { select: 'question_id,relationship_type', eq: { evidence_source_id: s.id }, all: true, count: false }).catch(() => ({ rows: [] }));
    if (!ctx.alive()) return;
    el.innerHTML = `<div class="adm-h"><div><div class="sub"><a href="#/evidence/library">← Evidence Library</a></div><h1>${esc(s.title)}</h1><div class="row">${badge('source', s.status)} ${badge('verification', s.verification_status)} <span class="badge">${esc(s.scope_type === 'global' ? 'Global' : 'Tashkilot')}</span></div></div><div class="act">${acts.join('')}</div></div>
      ${!own ? '<div class="note" style="margin-bottom:12px">Global manba — faqat platforma kutubxonasi orqali o\'zgaradi (API orqali yozib bo\'lmaydi).</div>' : ''}
      <div class="grid g2"><div class="card"><h3>Ma'lumotlar</h3><dl class="kv"><dt>Turi</dt><dd>${esc(s.source_type)}</dd><dt>Tashkilot</dt><dd>${esc(s.organization || '—')}</dd><dt>Mualliflar</dt><dd>${esc((s.authors || []).join(', ') || '—')}</dd>
        <dt>Nashr yili / sanasi</dt><dd>${esc(s.publication_year || '—')} / ${fmtDate(s.publication_date)}</dd><dt>Jurnal</dt><dd>${esc(s.journal || '—')}</dd><dt>DOI</dt><dd class="mono">${esc(s.doi || '—')}</dd><dt>PMID</dt><dd class="mono">${esc(s.pmid || '—')}</dd>
        <dt>URL</dt><dd>${s.url ? `<a href="${esc(s.url)}" target="_blank" rel="noopener noreferrer">${esc(s.url)}</a>` : '—'}</dd><dt>Guideline</dt><dd>${esc(s.guideline_name || '—')} ${s.guideline_version ? '(versiya ' + esc(s.guideline_version) + ')' : ''}</dd>
        <dt>Evidence level</dt><dd>${esc(s.evidence_level || 'Unknown')}${s.evidence_level_basis ? ' · ' + esc(s.evidence_level_basis) : ''}</dd><dt>Tier</dt><dd>${esc(s.evidence_tier || '—')}</dd>
        <dt>Kelib chiqishi</dt><dd>${esc(s.origin)}</dd><dt>Tekshiruv</dt><dd>${s.verification_status === 'verified' ? esc(s.verification_source) + ' · ' + fmtDT(s.verified_at) : 'Not verified'}</dd></dl></div>
        <div class="card"><h3>Bog'langan savollar (${links.rows.length})</h3>${links.rows.length ? links.rows.map(r => `<div class="row between small" style="padding:3px 0"><a href="#/questions/${encodeURIComponent(r.question_id)}" class="mono">${esc(r.question_id)}</a><span>${esc(r.relationship_type)}</span></div>`).join('') : empty('Hech qaysi savolga bog\'lanmagan')}</div></div>`;
    el.querySelectorAll('[data-act]').forEach(b => b.onclick = async () => { const a = b.getAttribute('data-act');
      try {
        if (a === 'verify') {
          const r = await dialog({ title: 'Manbani tasdiqlash (Verify)', body: 'Faqat identifikatorni (DOI / PMID / guideline versiyasi / URL) asl manbada shaxsan tekshirgan bo\'lsangiz tasdiqlang. Kim va qachon tasdiqlagani server tomonidan yoziladi.',
            fields: [{ name: 'ok', type: 'check', label: 'Asl manbani ochib, ma\'lumotlar mosligini tekshirdim', required: true }], okText: 'Verify' });
          if (!r) return; await API.update('evidence_sources', 'id', s.id, { verification_status: 'verified', verification_source: 'manual' });
        } else {
          const r = await dialog({ title: a === 'retracted' ? 'Retracted' : 'Superseded', danger: true, body: 'Bu manbaga tayangan savollar avtomatik <b>Review Required</b> holatiga o\'tadi va yangi imtihonlardan chiqadi. Tarixiy urinishlar o\'zgarmaydi.',
            fields: [{ name: 'ok', type: 'check', label: 'Tushunaman', required: true }], okText: 'Belgilash' });
          if (!r) return; await API.update('evidence_sources', 'id', s.id, { status: a });
        }
        toast('Saqlandi'); ADMIN.render();
      } catch (e) { toast(API.friendly(e).message, true); } });
  });

  window.EVIDENCE = { renderQuestionEvidence, reviewStatus, statusPanel };
})();
