// 007a perf: 1000 xodim × 50 kurs (10 majburiy dars/kurs) → 50 000 tayinlash, ~250 000 progress qatori
import { mk } from './lib005e.mjs';
const db = await mk(['staging/005e_00_backup.sql', 'migrations/005e_medical_review_authorization.sql', 'migrations/006a_audit_hardening.sql', 'migrations/006b_course_delete_hardening.sql', 'migrations/007a_learning_progress.sql']);
const q = s => db.query(s);
const OA = (await q(`select org_id from public.profiles where id='262a128c-6fb7-470e-9452-5468cd6797c0'`)).rows[0].org_id;
const ecols = (await q(`select column_name from information_schema.columns where table_schema='public' and table_name='employees' and is_nullable='NO' and column_default is null`)).rows.map(r => r.column_name);
const EMP = (await q(`select id, department_id from public.employees where profile_id='a0000000-0000-0000-0000-000000000006'`)).rows[0];
let t = performance.now();
await db.exec(`set session_replication_role = replica;
insert into public.employees (org_id, first_name, last_name, department_id, employment_status, employee_code)
  select '${OA}', 'Perf', 'E' || g, case when g % 4 = 0 then '${EMP.department_id}'::uuid else null end, 'active', 'PERF' || g from generate_series(1, 999) g;
insert into public.courses (id, org_id, title, domain, status) select 'PERF_' || c, '${OA}', 'Perf ' || c, 'ethics', 'published' from generate_series(1, 50) c;
insert into public.course_modules (id, org_id, course_id, title, order_index, status) select 'PERF_M' || c, '${OA}', 'PERF_' || c, 'M', 1, 'published' from generate_series(1, 50) c;
insert into public.lessons (org_id, module_id, title, content_type, order_index, status) select '${OA}', 'PERF_M' || c, 'L' || l, 'text', l, 'published' from generate_series(1, 50) c, generate_series(1, 10) l;
create temp table pe as select id from public.employees where employee_code like 'PERF%' union all select '${EMP.id}'::uuid;
insert into public.course_assignments (org_id, course_id, employee_id, due_date, status)
  select '${OA}', 'PERF_' || c, pe.id, current_date + ((c % 7) - 3), 'assigned' from pe, generate_series(1, 50) c;
insert into public.lesson_progress (org_id, lesson_id, employee_id, status)
  select '${OA}', l.id, pe.id, 'completed' from pe join public.course_assignments a on a.employee_id = pe.id and a.course_id like 'PERF_%'
  join public.course_modules m on m.course_id = a.course_id join public.lessons l on l.module_id = m.id
  where l.order_index <= (abs(hashtext(pe.id::text || a.course_id)) % 11);
set session_replication_role = origin; analyze;`);
const load = performance.now() - t;
const sizes = (await q(`select (select count(*) from public.course_assignments where course_id like 'PERF_%')::int a, (select count(*) from public.lesson_progress)::int p, (select count(*) from public.employees)::int e`)).rows[0];
const as = async (uid, sql, n = 5) => { await db.exec(`set role authenticated; select set_config('request.jwt.claims','{"sub":"${uid}","role":"authenticated"}',false), set_config('request.jwt.claim.sub','${uid}',false);`);
  const ts = []; let out; for (let i = 0; i < n; i++) { const t0 = performance.now(); out = await q(sql); ts.push(performance.now() - t0); } await db.exec('reset role'); ts.sort((a, b) => a - b); return { ms_median: +ts[Math.floor(n / 2)].toFixed(1), rows: out.rows.length, sample: JSON.stringify(out.rows[0]).slice(0, 160) }; };
const res = { load_ms: Math.round(load), sizes };
res.my_learning_progress_50 = await as('a0000000-0000-0000-0000-000000000006', `select * from public.my_learning_progress()`);
res.summary_SA_1000 = await as('262a128c-6fb7-470e-9452-5468cd6797c0', `select public.course_progress_summary('PERF_7')::text s`);
res.summary_HEAD_dept = await as('a0000000-0000-0000-0000-000000000005', `select public.course_progress_summary('PERF_7')::text s`);
// completion trigger: bitta xodim, oxirgi darsni tugatish (sys sifatida)
t = performance.now();
const lid = (await q(`select l.id from public.lessons l join public.course_modules m on m.id=l.module_id where m.course_id='PERF_3' and l.id not in (select lesson_id from public.lesson_progress where employee_id='${EMP.id}') order by l.order_index`)).rows.map(r => r.id);
for (const id of lid) await q(`insert into public.lesson_progress (org_id, lesson_id, employee_id, status) values ('${OA}', '${id}', '${EMP.id}', 'completed')`);
res.completion_trigger_ms_per_insert = lid.length ? +((performance.now() - t) / lid.length).toFixed(2) : 0;
res.completion = (await q(`select status, (select count(*) from public.audit_logs where action='course.completed' and entity_id = a.id::text)::int audits from public.course_assignments a where employee_id='${EMP.id}' and course_id='PERF_3'`)).rows[0];
res.plan_summary_uses_idx = (await q(`explain select 1 from public.lesson_progress where employee_id='${EMP.id}' and status='completed' and lesson_id = '${lid[0] || '00000000-0000-0000-0000-000000000000'}'`)).rows.map(r => r['QUERY PLAN']).join(' | ').slice(0, 200);
console.log(JSON.stringify(res, null, 1));
