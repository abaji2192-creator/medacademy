-- 007c STAGING perf: 1000 xodim, 50 bo'lim, 100 lavozim, 50 mutaxassislik, 500 ko'nikma, 300 talab, 10 000 baholash.
-- Hammasi bitta tranzaksiyada, oxirida ROLLBACK (residue 0).
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
do $$ declare oa uuid; hd uuid; begin
  select org_id into oa from public.profiles where id = 'a0000000-0000-0000-0000-000000000003';
  select department_id into hd from public.employees where profile_id = 'a0000000-0000-0000-0000-000000000005';
  if oa is null or hd is null then raise exception 'perf: test identifikatorlari topilmadi'; end if;
  insert into perf_r values ('ctx', jsonb_build_object('org', oa, 'hd', hd));
end $$;
set local session_replication_role = replica;
insert into public.departments (org_id, name, code) select (select (v->>'org')::uuid from perf_r where k='ctx'), 'PD ' || d, 'P7CD' || d from generate_series(1, 49) d;
insert into public.positions (org_id, name, code, status) select (select (v->>'org')::uuid from perf_r where k='ctx'), 'PP ' || d, 'P7CP' || d, 'active' from generate_series(1, 100) d;
insert into public.specialties (org_id, name, code, status) select (select (v->>'org')::uuid from perf_r where k='ctx'), 'PS ' || d, 'P7CS' || d, 'active' from generate_series(1, 50) d;
create temp table dl on commit drop as select id, row_number() over (order by code) rn from public.departments where code like 'P7CD%' union all select (select (v->>'hd')::uuid from perf_r where k='ctx'), 50;
insert into public.employees (org_id, first_name, last_name, department_id, position_id, specialty_id, employment_status, employee_code)
  select (select (v->>'org')::uuid from perf_r where k='ctx'), 'P', 'E' || g, (select id from dl where rn = 1 + g % 50), (select id from public.positions where code = 'P7CP' || (1 + g % 100)), (select id from public.specialties where code = 'P7CS' || (1 + g % 50)), 'active', 'P7C_' || g from generate_series(1, 1000) g;
insert into public.skills (org_id, code, name, max_level) select (select (v->>'org')::uuid from perf_r where k='ctx'), 'P7C_SK' || s, 'Ko''nikma ' || s, 5 from generate_series(1, 500) s;
insert into public.competency_requirements (org_id, skill_id, target_type, department_id, required_level)
  select (select (v->>'org')::uuid from perf_r where k='ctx'), (select id from public.skills where code = 'P7C_SK' || r), 'department', (select id from dl where rn = 1 + r % 50), 1 + r % 5 from generate_series(1, 200) r;
insert into public.competency_requirements (org_id, skill_id, target_type, position_id, required_level)
  select (select (v->>'org')::uuid from perf_r where k='ctx'), (select id from public.skills where code = 'P7C_SK' || (200 + r)), 'position', (select id from public.positions where code = 'P7CP' || (1 + r % 100)), 1 + r % 5 from generate_series(1, 100) r;
insert into public.skill_assessments (org_id, skill_id, employee_id, assessor_id, level)
  select (select (v->>'org')::uuid from perf_r where k='ctx'), (select id from public.skills where code = 'P7C_SK' || (1 + (g * 7) % 300)), e.id, 'a0000000-0000-0000-0000-000000000003', g % 6
  from generate_series(1, 10000) g join lateral (select id from public.employees where employee_code = 'P7C_' || (1 + g % 1000)) e on true;
set local session_replication_role = origin;
analyze public.employees; analyze public.skills; analyze public.skill_assessments; analyze public.competency_requirements; analyze public.departments;
create temp table pe on commit drop as select row_number() over (order by employee_code) i, id from public.employees where employee_code like 'P7C_%' order by employee_code limit 20;
create temp table ph on commit drop as select row_number() over (order by employee_code) i, id from public.employees where employee_code like 'P7C_%' and department_id = (select (v->>'hd')::uuid from perf_r where k='ctx') limit 20;
grant select on pe, ph, dl to authenticated;
select pg_temp.bench('skill_listing_emp', 'a0000000-0000-0000-0000-000000000006', $q$select count(*) from (select id, code, name from public.skills where status = 'active' order by name limit 100) x$q$);
select pg_temp.bench('employee_summary_EM', 'a0000000-0000-0000-0000-000000000003', $q$select count(*) from public.employee_competency_summary((select id from pe where i = $i))$q$);
select pg_temp.bench('employee_summary_self', 'a0000000-0000-0000-0000-000000000006', $q$select count(*) from public.employee_competency_summary()$q$);
select pg_temp.bench('head_employee_summary', 'a0000000-0000-0000-0000-000000000005', $q$select count(*) from public.employee_competency_summary((select id from ph where i = $i))$q$);
select pg_temp.bench('department_summary_head', 'a0000000-0000-0000-0000-000000000005', $q$select public.department_competency_summary((select (v->>'hd')::uuid from perf_r where k = 'ctx'))$q$);
select pg_temp.bench('department_summary_EM_any', 'a0000000-0000-0000-0000-000000000003', $q$select public.department_competency_summary((select id from dl where rn = 7))$q$);
select pg_temp.bench('assessment_insert_EM', 'a0000000-0000-0000-0000-000000000003', $q$select public.record_skill_assessment((select id from pe where i = $i), (select id from public.skills where code = 'P7C_SK42'), $i % 6)$q$);
select pg_temp.bench('assessment_insert_head', 'a0000000-0000-0000-0000-000000000005', $q$select public.record_skill_assessment((select id from ph where i = $i), (select id from public.skills where code = 'P7C_SK42'), $i % 6)$q$);
select pg_temp.bench('rls_select_head', 'a0000000-0000-0000-0000-000000000005', $q$select count(*) from public.skill_assessments$q$);
insert into perf_r values ('sizes', jsonb_build_object('skills', (select count(*) from public.skills), 'assessments', (select count(*) from public.skill_assessments), 'reqs', (select count(*) from public.competency_requirements), 'emps', (select count(*) from public.employees)));
select jsonb_object_agg(k, v)::text as perf_007c from perf_r where k <> 'ctx';
rollback;
