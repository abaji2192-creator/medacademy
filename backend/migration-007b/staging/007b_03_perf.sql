-- 007b STAGING perf: 1000 xodim (4 bo'lim) × 50 yo'nalish × 5 majburiy kurs. Hammasi bitta tranzaksiyada, oxirida ROLLBACK (residue 0).
begin;
create temp table perf_r (k text primary key, v jsonb) on commit drop;
do $$ declare oa uuid; begin
  select org_id into oa from public.profiles where id = 'a0000000-0000-0000-0000-000000000003';
  if oa is null then raise exception 'perf: EM test identifikatori topilmadi'; end if;
  insert into perf_r values ('ctx', jsonb_build_object('org', oa));
end $$;
set local session_replication_role = replica;
insert into public.departments (org_id, name, code) select (select (v->>'org')::uuid from perf_r where k='ctx'), 'Perf bo''lim ' || d, 'PERF7BD' || d from generate_series(1, 4) d;
insert into public.employees (org_id, first_name, last_name, department_id, employment_status, employee_code)
  select (select (v->>'org')::uuid from perf_r where k='ctx'), 'Perf', 'E' || g, (select id from public.departments where code = 'PERF7BD' || (1 + g % 4)), 'active', 'PERF7B_' || g from generate_series(1, 1000) g;
insert into public.courses (id, org_id, title, domain, status) select 'PERF7B_C' || c, (select (v->>'org')::uuid from perf_r where k='ctx'), 'Perf ' || c, 'ethics', 'published' from generate_series(1, 250) c;
insert into public.learning_paths (org_id, code, title, status) select (select (v->>'org')::uuid from perf_r where k='ctx'), 'PERF7B_P' || p, 'Perf yo''nalish ' || p, 'published' from generate_series(1, 50) p;
insert into public.learning_path_courses (org_id, path_id, course_id, order_index, is_required)
  select (select (v->>'org')::uuid from perf_r where k='ctx'), (select id from public.learning_paths where code = 'PERF7B_P' || p), 'PERF7B_C' || ((p - 1) * 5 + k), k, true from generate_series(1, 50) p, generate_series(1, 5) k;
set local session_replication_role = origin;
analyze public.employees; analyze public.course_assignments; analyze public.learning_path_courses; analyze public.learning_paths;
do $$ declare p record; i int := 0; t0 timestamptz; a float8[] := '{}'; b float8[] := '{}'; s float8[]; n int; created int := 0; r jsonb; d uuid[]; begin
  select array_agg(id order by code) into d from public.departments where code like 'PERF7BD%';
  perform set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', true);
  for p in select id from public.learning_paths where code like 'PERF7B_P%' order by code loop
    i := i + 1; set local role authenticated;
    t0 := clock_timestamp(); r := public.apply_learning_path(p.id, 'department', d[1 + (i - 1) % 4]::text); a := a || extract(epoch from clock_timestamp() - t0) * 1000;
    reset role; created := created + (r ->> 'course_assignments_created')::int;
  end loop;
  analyze public.course_assignments;
  i := 0;
  for p in select id from public.learning_paths where code like 'PERF7B_P%' order by code loop
    i := i + 1; set local role authenticated;
    t0 := clock_timestamp(); r := public.apply_learning_path(p.id, 'department', d[1 + (i - 1) % 4]::text); b := b || extract(epoch from clock_timestamp() - t0) * 1000;
    reset role;
  end loop;
  n := array_length(a, 1);
  select array_agg(x order by x) into s from unnest(a) x;
  insert into perf_r values ('apply_first', jsonb_build_object('n', n, 'median_ms', round(s[(n + 1) / 2]::numeric, 1), 'p95_ms', round(s[ceil(n * 0.95)::int]::numeric, 1), 'max_ms', round(s[n]::numeric, 1), 'created', created));
  select array_agg(x order by x) into s from unnest(b) x;
  insert into perf_r values ('reapply_idempotent', jsonb_build_object('n', n, 'median_ms', round(s[(n + 1) / 2]::numeric, 1), 'p95_ms', round(s[ceil(n * 0.95)::int]::numeric, 1), 'max_ms', round(s[n]::numeric, 1)));
  insert into perf_r values ('integrity', jsonb_build_object('total', (select count(*) from public.course_assignments where course_id like 'PERF7B_%'),
    'duplicates', (select count(*) from (select employee_id, course_id from public.course_assignments where status <> 'cancelled' group by 1, 2 having count(*) > 1) x)));
end $$;
select jsonb_object_agg(k, v)::text as perf_007b from perf_r where k <> 'ctx';
rollback;
