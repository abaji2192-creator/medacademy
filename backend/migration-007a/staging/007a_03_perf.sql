-- 007a STAGING perf: 1000 xodim × 50 kurs (10 majburiy dars/kurs), BARCHASI shu tranzaksiyada va oxirida ROLLBACK (residue 0).
-- Ommaviy yuklash vaqtida foydalanuvchi trigger'lari session_replication_role=replica bilan o'chiriladi (faqat yuklash uchun), keyin qayta yoqiladi.
begin;
create temp table perf_r (k text primary key, v jsonb) on commit drop;
do $$ declare oa uuid; ed uuid; dept uuid; begin
  select org_id into oa from public.profiles where id = '262a128c-6fb7-470e-9452-5468cd6797c0';
  select id, department_id into ed, dept from public.employees where profile_id = 'a0000000-0000-0000-0000-000000000006';
  if oa is null or ed is null then raise exception 'perf: test identifikatorlari topilmadi'; end if;
  insert into perf_r values ('ctx', jsonb_build_object('org', oa, 'emp', ed, 'dept', dept));
end $$;
set local session_replication_role = replica;
insert into public.employees (org_id, first_name, last_name, department_id, employment_status, employee_code)
  select (select (v->>'org')::uuid from perf_r where k='ctx'), 'Perf', 'E' || g, case when g % 4 = 0 then (select (v->>'dept')::uuid from perf_r where k='ctx') end, 'active', 'PERF7A_' || g from generate_series(1, 999) g;
insert into public.courses (id, org_id, title, domain, status) select 'PERF7A_' || c, (select (v->>'org')::uuid from perf_r where k='ctx'), 'Perf ' || c, 'ethics', 'published' from generate_series(1, 50) c;
insert into public.course_modules (id, org_id, course_id, title, order_index, status) select 'PERF7A_M' || c, (select (v->>'org')::uuid from perf_r where k='ctx'), 'PERF7A_' || c, 'M', 1, 'published' from generate_series(1, 50) c;
insert into public.lessons (org_id, module_id, title, content_type, order_index, status) select (select (v->>'org')::uuid from perf_r where k='ctx'), 'PERF7A_M' || c, 'L' || l, 'text', l, 'published' from generate_series(1, 50) c, generate_series(1, 10) l;
create temp table pe on commit drop as select id from public.employees where employee_code like 'PERF7A_%' union all select (select (v->>'emp')::uuid from perf_r where k='ctx');
insert into public.course_assignments (org_id, course_id, employee_id, due_date, status)
  select (select (v->>'org')::uuid from perf_r where k='ctx'), 'PERF7A_' || c, pe.id, current_date + ((c % 7) - 3), 'assigned' from pe, generate_series(1, 50) c;
insert into public.lesson_progress (org_id, lesson_id, employee_id, status)
  select a.org_id, l.id, pe.id, 'completed' from pe join public.course_assignments a on a.employee_id = pe.id and a.course_id like 'PERF7A_%'
  join public.course_modules m on m.course_id = a.course_id join public.lessons l on l.module_id = m.id
  where l.order_index <= (abs(hashtext(pe.id::text || a.course_id)) % 11);
set local session_replication_role = origin;
analyze public.lesson_progress; analyze public.course_assignments; analyze public.lessons; analyze public.course_modules; analyze public.employees;

create function pg_temp.bench(uid text, q text, n int) returns jsonb language plpgsql as $$
declare t0 timestamptz; ts float8[] := '{}'; i int; s float8[]; r text;
begin
  for i in 1..n loop
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', uid, true);
    set local role authenticated;
    t0 := clock_timestamp(); execute q into r; ts := ts || extract(epoch from clock_timestamp() - t0) * 1000;
    reset role;
  end loop;
  select array_agg(x order by x) into s from unnest(ts) x;
  return jsonb_build_object('n', n, 'median_ms', round(s[(n + 1) / 2]::numeric, 2), 'p95_ms', round(s[greatest(1, ceil(n * 0.95)::int)]::numeric, 2), 'max_ms', round(s[n]::numeric, 2), 'sample', left(r, 140));
end $$;
insert into perf_r values ('sizes', jsonb_build_object('assignments', (select count(*) from public.course_assignments where course_id like 'PERF7A_%'), 'progress', (select count(*) from public.lesson_progress), 'employees', (select count(*) from public.employees)));
insert into perf_r values ('my_learning_progress_50', pg_temp.bench('a0000000-0000-0000-0000-000000000006', 'select count(*)::text from public.my_learning_progress()', 20));
insert into perf_r values ('summary_SA_1000', pg_temp.bench('262a128c-6fb7-470e-9452-5468cd6797c0', 'select public.course_progress_summary(''PERF7A_7'')::text', 20));
insert into perf_r values ('summary_HEAD_dept', pg_temp.bench('a0000000-0000-0000-0000-000000000005', 'select public.course_progress_summary(''PERF7A_7'')::text', 20));
do $$ declare e uuid := (select (v->>'emp')::uuid from perf_r where k='ctx'); o uuid := (select (v->>'org')::uuid from perf_r where k='ctx'); l record; t0 timestamptz; ts float8[] := '{}'; s float8[]; n int; begin
  for l in select le.id from public.lessons le join public.course_modules m on m.id = le.module_id where m.course_id = 'PERF7A_3'
           and le.id not in (select lesson_id from public.lesson_progress where employee_id = e) order by le.order_index loop
    t0 := clock_timestamp(); insert into public.lesson_progress (org_id, lesson_id, employee_id, status) values (o, l.id, e, 'completed'); ts := ts || extract(epoch from clock_timestamp() - t0) * 1000;
  end loop;
  n := coalesce(array_length(ts, 1), 0); select array_agg(x order by x) into s from unnest(ts) x;
  insert into perf_r values ('completion_trigger', jsonb_build_object('inserts', n, 'median_ms', case when n > 0 then round(s[(n + 1) / 2]::numeric, 2) end, 'max_ms', case when n > 0 then round(s[n]::numeric, 2) end,
    'assignment_status', (select status from public.course_assignments where employee_id = e and course_id = 'PERF7A_3'),
    'course_completed_audits', (select count(*) from public.audit_logs a where a.action = 'course.completed' and a.entity_id = (select id::text from public.course_assignments where employee_id = e and course_id = 'PERF7A_3'))));
end $$;
select jsonb_object_agg(k, v)::text as perf_007a from perf_r where k <> 'ctx';
rollback;
