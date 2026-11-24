// 006a perf: question_eligibility(id) — har bir savol uchun bitta chaqiruv (EM sifatida) vs question_meta (butun org)
import { mk } from './lib005e.mjs';
const db = await mk(['staging/005e_00_backup.sql', 'migrations/005e_medical_review_authorization.sql', 'migrations/006a_audit_hardening.sql']);
const EDU = 'a0000000-0000-0000-0000-000000000003';
await db.exec(`set role authenticated; select set_config('request.jwt.claims', '{"sub":"${EDU}","role":"authenticated"}', false), set_config('request.jwt.claim.sub','${EDU}',false);`);
const ids = (await db.query(`select id from public.questions order by id`)).rows.map(r => r.id);
let t = performance.now(); let n = 0, bytes = 0;
for (const id of ids) { const r = await db.query(`select public.question_eligibility($1)::text j`, [id]).catch(() => null); if (r) { n++; bytes += r.rows[0].j.length; } }
const per = (performance.now() - t) / ids.length;
t = performance.now(); const m = (await db.query(`select public.question_meta()::text j`)).rows[0].j; const tm = performance.now() - t;
console.log(JSON.stringify({ questions: ids.length, eligibility_ok: n, eligibility_ms_per_call: +per.toFixed(2), eligibility_avg_bytes: Math.round(bytes / n), question_meta_ms: +tm.toFixed(1), question_meta_bytes: m.length }));
