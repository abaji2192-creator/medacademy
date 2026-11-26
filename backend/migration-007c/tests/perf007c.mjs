// 007c perf: 1000 xodim, 50 bo'lim, 100 lavozim, 50 mutaxassislik, 500 ko'nikma, 300 talab, 10 000 baholash
import { mk } from './lib005e.mjs';
const db = await mk(['staging/005e_00_backup.sql', 'migrations/005e_medical_review_authorization.sql', 'migrations/006a_audit_hardening.sql', 'migrations/006b_course_delete_hardening.sql', 'migrations/007a_learning_progress.sql', 'migrations/007b_learning_path_assignments.sql', 'migrations/007c_skills_competency.sql']);
const q = (s, p) => db.query(s, p);
const OA = (await q(`select org_id from public.profiles where id='262a128c-6fb7-470e-9452-5468cd6797c0'`)).rows[0].org_id;
const EDU = 'a0000000-0000-0000-0000-000000000003', HEAD = 'a0000000-0000-0000-0000-000000000005', EMP = 'a0000000-0000-0000-0000-000000000006';
const headDept = (await q(`select department_id from public.employees where profile_id = '${HEAD}'`)).rows[0].department_id;
let t = performance.now();
await db.exec(`set session_replication_role = replica;
insert into public.departments (org_id, name, code) select '${OA}', 'PD ' || d, 'P7CD' || d from generate_series(1, 49) d;
insert into public.positions (org_id, name, code, status) select '${OA}', 'PP ' || d, 'P7CP' || d, 'active' from generate_series(1, 100) d;
insert into public.specialties (org_id, name, code, status) select '${OA}', 'PS ' || d, 'P7CS' || d, 'active' from generate_series(1, 50) d;
create temp table dl as select id, row_number() over (order by code) rn from public.departments where code like 'P7CD%' union all select '${headDept}'::uuid, 50;
insert into public.employees (org_id, first_name, last_name, department_id, position_id, specialty_id, employment_status, employee_code)
  select '${OA}', 'P', 'E' || g, (select id from dl where rn = 1 + g % 50), (select id from public.positions where code = 'P7CP' || (1 + g % 100)), (select id from public.specialties where code = 'P7CS' || (1 + g % 50)), 'active', 'P7C_' || g from generate_series(1, 1000) g;
insert into public.skills (org_id, code, name, max_level) select '${OA}', 'P7C_SK' || s, 'Ko''nikma ' || s, 5 from generate_series(1, 500) s;
insert into public.competency_requirements (org_id, skill_id, target_type, department_id, required_level)
  select '${OA}', (select id from public.skills where code = 'P7C_SK' || r), 'department', (select id from dl where rn = 1 + r % 50), 1 + r % 5 from generate_series(1, 200) r;
insert into public.competency_requirements (org_id, skill_id, target_type, position_id, required_level)
  select '${OA}', (select id from public.skills where code = 'P7C_SK' || (200 + r)), 'position', (select id from public.positions where code = 'P7CP' || (1 + r % 100)), 1 + r % 5 from generate_series(1, 100) r;
insert into public.skill_assessments (org_id, skill_id, employee_id, assessor_id, level)
  select '${OA}', (select id from public.skills where code = 'P7C_SK' || (1 + (g * 7) % 300)), e.id, '${EDU}', g % 6
  from generate_series(1, 10000) g join lateral (select id from public.employees where employee_code = 'P7C_' || (1 + g % 1000)) e on true;
set session_replication_role = origin; analyze;`);
const load = performance.now() - t;
const as = async (uid, sql, n = 20, params) => { await db.exec(`set role authenticated; select set_config('request.jwt.claims','{"sub":"${uid}","role":"authenticated"}',false), set_config('request.jwt.claim.sub','${uid}',false);`);
  const ts = []; let out; for (let i = 0; i < n; i++) { const t0 = performance.now(); out = await q(typeof sql === 'function' ? sql(i) : sql, params); ts.push(performance.now() - t0); } await db.exec('reset role'); ts.sort((a, b) => a - b);
  return { median_ms: +ts[Math.floor(n / 2)].toFixed(1), p95_ms: +ts[Math.ceil(n * 0.95) - 1].toFixed(1), max_ms: +ts[n - 1].toFixed(1), rows: out.rows.length }; };
const emps = (await q(`select id from public.employees where employee_code like 'P7C_%' order by employee_code limit 20`)).rows.map(r => r.id);
const headEmps = (await q(`select id from public.employees where department_id = '${headDept}' and employee_code like 'P7C_%' limit 20`)).rows.map(r => r.id);
const res = { load_ms: Math.round(load), sizes: (await q(`select (select count(*) from public.skills)::int skills, (select count(*) from public.skill_assessments)::int assessments, (select count(*) from public.competency_requirements)::int reqs, (select count(*) from public.employees)::int emps`)).rows[0] };
res.skill_listing_emp = await as(EMP, `select id, code, name from public.skills where status = 'active' order by name limit 100`);
res.employee_summary_EM = await as(EDU, i => `select * from public.employee_competency_summary('${emps[i % emps.length]}')`);
res.employee_summary_self = await as(EMP, `select * from public.employee_competency_summary()`);
res.head_employee_summary = await as(HEAD, i => `select * from public.employee_competency_summary('${headEmps[i % headEmps.length]}')`);
res.department_summary_head = await as(HEAD, `select public.department_competency_summary('${headDept}')`);
res.department_summary_EM_any = await as(EDU, `select public.department_competency_summary((select id from public.departments where code = 'P7CD7'))`);
const sk = (await q(`select id from public.skills where code = 'P7C_SK42'`)).rows[0].id;
res.assessment_insert_EM = await as(EDU, i => `select public.record_skill_assessment('${emps[i % emps.length]}', '${sk}', ${i % 6})`);
res.assessment_insert_head = await as(HEAD, i => `select public.record_skill_assessment('${headEmps[i % headEmps.length]}', '${sk}', ${i % 6})`);
res.rls_select_head = await as(HEAD, `select count(*) from public.skill_assessments`);
console.log(JSON.stringify(res, null, 1));
