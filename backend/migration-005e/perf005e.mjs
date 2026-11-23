// 005e performance: _q_exam_eligible / question_meta / review queue so'rovlari — 005d vs 005e (lokal PGlite, nisbiy)
import { mk } from './lib005e.mjs';
const SA = '262a128c-6fb7-470e-9452-5468cd6797c0', EDU = 'a0000000-0000-0000-0000-000000000003', EMP = 'a0000000-0000-0000-0000-000000000006';
async function bench(with5e) {
  const db = await mk(with5e ? ['migrations/005e_medical_review_authorization.sql'] : []);
  // 600 ta savolni "review'dan o'tgan" holatga keltirish + har biriga 3 ta review (evidence approved, medical approved x2)
  await db.exec(`select set_config('medacademy.system_write','on',false);
    insert into questions (id, org_id, course_id, type, difficulty, stem, options, answer, status, workflow_status)
      select 'PF' || g, '00000000-0000-0000-0000-000000000001', 'CARDIO_BASIC', 'single', 'medium', 'PERF ' || g, '["a","b"]', '0', 'draft', 'draft' from generate_series(1, 600) g;
    update questions set evidence_status = 'current', workflow_status = 'published' where id like 'PF%';
    insert into question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision)
      select org_id, id, 1, t, '${SA}', 'approved' from questions, unnest(array['instructor','medical','medical']) t where id like 'PF%';
    select set_config('medacademy.system_write','off',false); analyze;`);
  const as = async (uid, sql, n = 5) => { await db.exec(`select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', false); set role authenticated;`);
    const t0 = performance.now(); let r; for (let i = 0; i < n; i++) r = await db.query(sql); const ms = (performance.now() - t0) / n;
    await db.exec(`reset role; select set_config('request.jwt.claims','',false);`); return [ms.toFixed(1), r.rows.length ? Object.values(r.rows[0])[0] : null]; };
  return {
    eligible_all: await as(SA, `select count(*) from questions q where public._q_exam_eligible(q)`, 3).catch(e => 'ERR ' + e.message),
    question_meta: await as(EMP, `select jsonb_array_length(public.question_meta())`),
    bank_list_EM: await as(EDU, `select count(*) from questions where course_id = 'CARDIO_BASIC'`),
    review_queue_EM: await as(EDU, `select count(*) from question_reviews`),
    medical_queue_EM: await as(EDU, `select count(*) from question_review_assignments where review_type = 'medical' and status = 'open'`),
  };
}
const a = await bench(false), b = await bench(true);
console.log('so\'rov | 005d ms (natija) | 005e ms (natija)');
for (const k of Object.keys(a)) console.log(`${k} | ${a[k][0]} (${a[k][1]}) | ${b[k][0]} (${b[k][1]})`);
