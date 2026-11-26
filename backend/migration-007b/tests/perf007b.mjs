// 007b perf: 1000 xodim (4 bo'lim) × 50 yo'nalish (har birida 5 majburiy kurs); qoida yaratish + qo'llash + idempotent qayta qo'llash
import { mk } from './lib005e.mjs';
const db = await mk(['staging/005e_00_backup.sql', 'migrations/005e_medical_review_authorization.sql', 'migrations/006a_audit_hardening.sql', 'migrations/006b_course_delete_hardening.sql', 'migrations/007a_learning_progress.sql', 'migrations/007b_learning_path_assignments.sql']);
const q = (s, p) => db.query(s, p);
const OA = (await q(`select org_id from public.profiles where id='262a128c-6fb7-470e-9452-5468cd6797c0'`)).rows[0].org_id;
const EDU = 'a0000000-0000-0000-0000-000000000003';
let t = performance.now();
await db.exec(`set session_replication_role = replica;
insert into public.departments (org_id, name, code) select '${OA}', 'Perf bo''lim ' || d, 'PERFD' || d from generate_series(1, 4) d;
insert into public.employees (org_id, first_name, last_name, department_id, employment_status, employee_code)
  select '${OA}', 'Perf', 'E' || g, (select id from public.departments where code = 'PERFD' || (1 + g % 4)), 'active', 'PERF7B_' || g from generate_series(1, 1000) g;
insert into public.courses (id, org_id, title, domain, status) select 'PERF7B_C' || c, '${OA}', 'Perf ' || c, 'ethics', 'published' from generate_series(1, 250) c;
insert into public.learning_paths (org_id, code, title, status) select '${OA}', 'PERF7B_P' || p, 'Perf yo''nalish ' || p, 'published' from generate_series(1, 50) p;
insert into public.learning_path_courses (org_id, path_id, course_id, order_index, is_required)
  select '${OA}', (select id from public.learning_paths where code = 'PERF7B_P' || p), 'PERF7B_C' || ((p - 1) * 5 + k), k, true from generate_series(1, 50) p, generate_series(1, 5) k;
set session_replication_role = origin; analyze;`);
const load = performance.now() - t;
await db.exec(`set role authenticated; select set_config('request.jwt.claims','{"sub":"${EDU}","role":"authenticated"}',false), set_config('request.jwt.claim.sub','${EDU}',false);`);
const paths = (await q(`select id, code from public.learning_paths where code like 'PERF7B_P%' order by code`)).rows;
const depts = (await q(`select id from public.departments where code like 'PERFD%' order by code`)).rows.map(r => r.id);
const stat = a => { const s = [...a].sort((x, y) => x - y); return { n: s.length, median_ms: +s[Math.floor(s.length / 2)].toFixed(1), p95_ms: +s[Math.min(s.length - 1, Math.ceil(s.length * 0.95) - 1)].toFixed(1), max_ms: +s[s.length - 1].toFixed(1) }; };
const first = [], again = [], roleT = []; let created = 0;
for (let i = 0; i < paths.length; i++) { const t0 = performance.now(); const r = (await q(`select public.apply_learning_path($1, 'department', $2)::text j`, [paths[i].id, depts[i % 4]])).rows[0].j; first.push(performance.now() - t0); created += JSON.parse(r).course_assignments_created; }
for (let i = 0; i < paths.length; i++) { const t0 = performance.now(); await q(`select public.apply_learning_path($1, 'department', $2)`, [paths[i].id, depts[i % 4]]); again.push(performance.now() - t0); }
let roleCreated = 0; for (let i = 0; i < 5; i++) { const t0 = performance.now(); const r = (await q(`select public.apply_learning_path($1, 'role', 'employee')::text j`, [paths[i].id])).rows[0].j; roleT.push(performance.now() - t0); roleCreated += JSON.parse(r).course_assignments_created; }
await db.exec('reset role');
const dup = (await q(`select count(*)::int n from (select employee_id, course_id from public.course_assignments where status <> 'cancelled' group by 1, 2 having count(*) > 1) x`)).rows[0].n;
const total = (await q(`select count(*)::int n from public.course_assignments where course_id like 'PERF7B_%'`)).rows[0].n;
const plan = (await q(`explain select 1 from public.course_assignments ca where ca.employee_id = '00000000-0000-0000-0000-000000000000' and ca.course_id = 'X'`)).rows.map(r => r['QUERY PLAN']).join(' | ').slice(0, 160);
console.log(JSON.stringify({ load_ms: Math.round(load), rules: paths.length, department_apply_first: stat(first), course_assignments_created: created, reapply_idempotent: stat(again), role_apply_overlap: { ...stat(roleT), created: roleCreated }, total_course_assignments: total, duplicates: dup, lookup_plan: plan }, null, 1));
