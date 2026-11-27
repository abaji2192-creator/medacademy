-- 007e STAGING perf: 1000 xodim (50 bo'lim, 100 lavozim, 50 mutaxassislik), 20 kurs × 5 majburiy dars, 20 000 tayinlash,
-- ~100 000 lesson_progress, 500 ko'nikma, 300 talab, 10 000 baholash. Bitta tranzaksiya, oxirida ROLLBACK (residue 0).
begin;
create temp table perf_r (k text primary key, v jsonb) on commit drop;
grant all on perf_r to authenticated;
create function pg_temp.bench(k text, uid text, q text, n int default 20) returns void language plpgsql as $f$
declare t0 timestamptz; a float8[] := '{}'; s float8[]; i int; begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid, true);
  for i in 1..n loop
    set local role authenticated;
    t0 := clock_timestamp(); execute replace(q, '$i', i::text); a := a || extract(epoch from clock_timestamp() - t0) * 1000;
    reset role;
  end loop;
  select array_agg(x order by x) into s from unnest(a) x;
  insert into perf_r values (k, jsonb_build_object('n', n, 'median_ms', round(s[(n + 1) / 2]::numeric, 1), 'p95_ms', round(s[ceil(n * 0.95)::int]::numeric, 1), 'max_ms', round(s[n]::numeric, 1)));
end $f$;
do $$ declare oa uuid; hd uuid; ee uuid; begin
  select org_id into oa from public.profiles where id = 'a0000000-0000-0000-0000-000000000003';
  select department_id into hd from public.employees where profile_id = 'a0000000-0000-0000-0000-000000000005';
  select id into ee from public.employees where profile_id = 'a0000000-0000-0000-0000-000000000006';
  if oa is null or hd is null or ee is null then raise exception 'perf: test identifikatorlari topilmadi'; end if;
  insert into perf_r values ('ctx', jsonb_build_object('org', oa, 'hd', hd, 'emp', ee));
end $$;
set local session_replication_role = replica;
insert into public.departments (org_id, name, code) select (select (v->>'org')::uuid from perf_r where k='ctx'), 'PD ' || d, 'P7ED' || d from generate_series(1, 49) d;
insert into public.positions (org_id, name, code, status) select (select (v->>'org')::uuid from perf_r where k='ctx'), 'PP ' || d, 'P7EP' || d, 'active' from generate_series(1, 100) d;
insert into public.specialties (org_id, name, code, status) select (select (v->>'org')::uuid from perf_r where k='ctx'), 'PS ' || d, 'P7ES' || d, 'active' from generate_series(1, 50) d;
create temp table dl on commit drop as select id, row_number() over (order by code) rn from public.departments where code like 'P7ED%' union all select (select (v->>'hd')::uuid from perf_r where k='ctx'), 50;
insert into public.employees (org_id, first_name, last_name, department_id, position_id, specialty_id, employment_status, employee_code)
  select (select (v->>'org')::uuid from perf_r where k='ctx'), 'P', 'E' || g, (select id from dl where rn = 1 + g % 50), (select id from public.positions where code = 'P7EP' || (1 + g % 100)),
         (select id from public.specialties where code = 'P7ES' || (1 + g % 50)), 'active', 'P7E_' || g from generate_series(1, 1000) g;
create temp table pe on commit drop as select row_number() over (order by employee_code) i, id from public.employees where employee_code like 'P7E_%';
insert into pe select 1001, (select (v->>'emp')::uuid from perf_r where k='ctx');
insert into public.courses (id, org_id, title, domain, status) select 'P7E_C' || c, (select (v->>'org')::uuid from perf_r where k='ctx'), 'Perf kurs ' || c, 'ethics', 'published' from generate_series(1, 20) c;
insert into public.course_modules (id, org_id, course_id, title, order_index, status) select 'P7E_M' || c, (select (v->>'org')::uuid from perf_r where k='ctx'), 'P7E_C' || c, 'M', 1, 'published' from generate_series(1, 20) c;
insert into public.lessons (id, org_id, module_id, title, content_type, order_index, status, is_required)
  select ('7e7e0000-0000-0000-' || lpad(c::text, 4, '0') || '-' || lpad(l::text, 12, '0'))::uuid, (select (v->>'org')::uuid from perf_r where k='ctx'), 'P7E_M' || c, 'L' || l, 'text', l, 'published', l <= 5
  from generate_series(1, 20) c, generate_series(1, 6) l;
insert into public.course_assignments (org_id, course_id, employee_id, due_date, status, assigned_at)
  select (select (v->>'org')::uuid from perf_r where k='ctx'), 'P7E_C' || c, pe.id, current_date + ((pe.i + c) % 40 - 10)::int, case when (pe.i + c) % 17 = 0 then 'cancelled' else 'assigned' end, now()
  from pe, generate_series(1, 20) c;
insert into public.lesson_progress (org_id, lesson_id, employee_id, status)
  select (select (v->>'org')::uuid from perf_r where k='ctx'), ('7e7e0000-0000-0000-' || lpad(c::text, 4, '0') || '-' || lpad(l::text, 12, '0'))::uuid, pe.id, 'completed'
  from pe, generate_series(1, 20) c, generate_series(1, 6) l where l = 6 or (pe.i + c) % 4 <> 0 or l <= 1 + (pe.i * 7 + c) % 5;
insert into public.skills (org_id, code, name, max_level) select (select (v->>'org')::uuid from perf_r where k='ctx'), 'P7E_SK' || s, 'Ko''nikma ' || s, 5 from generate_series(1, 500) s;
insert into public.competency_requirements (org_id, skill_id, target_type, department_id, required_level)
  select (select (v->>'org')::uuid from perf_r where k='ctx'), (select id from public.skills where code = 'P7E_SK' || r), 'department', (select id from dl where rn = 1 + r % 50), 1 + r % 5 from generate_series(1, 200) r;
insert into public.competency_requirements (org_id, skill_id, target_type, position_id, required_level)
  select (select (v->>'org')::uuid from perf_r where k='ctx'), (select id from public.skills where code = 'P7E_SK' || (200 + r)), 'position', (select id from public.positions where code = 'P7EP' || (1 + r % 100)), 1 + r % 5 from generate_series(1, 100) r;
insert into public.skill_assessments (org_id, skill_id, employee_id, assessor_id, level)
  select (select (v->>'org')::uuid from perf_r where k='ctx'), (select id from public.skills where code = 'P7E_SK' || (1 + (g * 7) % 300)), pe.id, 'a0000000-0000-0000-0000-000000000003', g % 6
  from generate_series(1, 10000) g join pe on pe.i = 1 + g % 1000;
set local session_replication_role = origin;
analyze public.employees; analyze public.course_assignments; analyze public.lesson_progress; analyze public.lessons; analyze public.course_modules;
analyze public.skills; analyze public.skill_assessments; analyze public.competency_requirements; analyze public.departments;
create temp table ph on commit drop as select row_number() over (order by employee_code) i, id from public.employees where employee_code like 'P7E_%' and department_id = (select (v->>'hd')::uuid from perf_r where k='ctx');
grant select on pe, ph, dl, perf_r to authenticated;
select pg_temp.bench('my_training_compliance', 'a0000000-0000-0000-0000-000000000006', $q$select public.employee_training_compliance()$q$);
select pg_temp.bench('my_competency_matrix', 'a0000000-0000-0000-0000-000000000006', $q$select public.employee_competency_matrix()$q$);
select pg_temp.bench('employee_training_compliance_EM', 'a0000000-0000-0000-0000-000000000003', $q$select public.employee_training_compliance((select id from pe where i = $i * 37))$q$);
select pg_temp.bench('employee_competency_matrix_EM', 'a0000000-0000-0000-0000-000000000003', $q$select public.employee_competency_matrix((select id from pe where i = $i * 37))$q$);
select pg_temp.bench('employee_training_compliance_head', 'a0000000-0000-0000-0000-000000000005', $q$select public.employee_training_compliance((select id from ph where i = 1 + $i % 20))$q$);
select pg_temp.bench('department_matrix_head', 'a0000000-0000-0000-0000-000000000005', $q$select public.department_compliance_matrix((select (v->>'hd')::uuid from perf_r where k = 'ctx'))$q$);
select pg_temp.bench('department_matrix_EM', 'a0000000-0000-0000-0000-000000000003', $q$select public.department_compliance_matrix((select id from dl where rn = 1 + $i % 49))$q$);
select pg_temp.bench('organization_matrix_EM_1000', 'a0000000-0000-0000-0000-000000000003', $q$select public.department_compliance_matrix()$q$, 10);
insert into perf_r values ('sizes', jsonb_build_object('employees', (select count(*) from public.employees), 'course_assignments', (select count(*) from public.course_assignments),
  'lesson_progress', (select count(*) from public.lesson_progress), 'skills', (select count(*) from public.skills), 'requirements', (select count(*) from public.competency_requirements),
  'assessments', (select count(*) from public.skill_assessments), 'notifications', (select count(*) from public.notifications)));
select jsonb_object_agg(k, v)::text as perf_007e from perf_r where k <> 'ctx';
rollback;
