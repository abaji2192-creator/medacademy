-- 007d STAGING perf: 1000 xodim (akkauntli), har biriga 100 ta → 100 000 bildirishnoma (+ fon). Trigger yuklamasi: 007b apply (1000 xodim × 5 kurs).
-- Hammasi bitta tranzaksiyada, oxirida ROLLBACK (residue 0). Vaqtinchalik auth/profiles qatorlari ham ROLLBACK bilan yo'qoladi.
begin;
create temp table perf_r (k text primary key, v jsonb) on commit drop;
grant all on perf_r to authenticated;
create function pg_temp.bench(k text, uid text, q text, n int default 20) returns void language plpgsql as $f$
declare t0 timestamptz; a float8[] := '{}'; s float8[]; i int; u text; begin
  for i in 1..n loop
    u := case when uid like 'PERF:%' then 'd7d00000-0000-0000-0000-' || lpad((split_part(uid, ':', 2)::int + i)::text, 12, '0') else uid end;
    perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', u, true);
    set local role authenticated;
    t0 := clock_timestamp(); execute replace(q, '$i', i::text); a := a || extract(epoch from clock_timestamp() - t0) * 1000;
    reset role;
  end loop;
  select array_agg(x order by x) into s from unnest(a) x;
  insert into perf_r values (k, jsonb_build_object('n', n, 'median_ms', round(s[(n + 1) / 2]::numeric, 1), 'p95_ms', round(s[ceil(n * 0.95)::int]::numeric, 1), 'max_ms', round(s[n]::numeric, 1)));
end $f$;
do $$ declare oa uuid; begin
  select org_id into oa from public.profiles where id = 'a0000000-0000-0000-0000-000000000003';
  if oa is null then raise exception 'perf: EM test identifikatori topilmadi'; end if;
  insert into perf_r values ('ctx', jsonb_build_object('org', oa));
end $$;
-- 1000 vaqtinchalik akkaunt (parolsiz, @test.local) + xodim
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  select ('d7d00000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         'perf7d-' || g || '@test.local', '{"full_name":"Perf 7D"}', now(), now() from generate_series(1, 1000) g;
update public.profiles set org_id = (select (v->>'org')::uuid from perf_r where k = 'ctx'), status = 'active', role = 'employee' where email like 'perf7d-%@test.local';
set local session_replication_role = replica;
insert into public.departments (org_id, name, code) select (select (v->>'org')::uuid from perf_r where k='ctx'), 'P7D bo''lim ' || d, 'P7DD' || d from generate_series(1, 4) d;
insert into public.employees (org_id, profile_id, first_name, last_name, department_id, employment_status, employee_code)
  select (select (v->>'org')::uuid from perf_r where k='ctx'), ('d7d00000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, 'P', 'E' || g,
         (select id from public.departments where code = 'P7DD' || (1 + g % 4)), 'active', 'P7D_' || g from generate_series(1, 1000) g;
insert into public.notifications (org_id, recipient_id, notification_type, title, body, related_entity_type, related_entity_id, event_key, created_at, read_at)
  select (select (v->>'org')::uuid from perf_r where k='ctx'), ('d7d00000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, 'course_assigned', 'Perf', 'Perf ' || k,
         'course', 'PERF', 'perf:' || k, now() - (k || ' minutes')::interval, case when k % 3 = 0 then now() end
  from generate_series(1, 1000) g, generate_series(1, 100) k;
insert into public.courses (id, org_id, title, domain, status) select 'PERF7D_C' || c, (select (v->>'org')::uuid from perf_r where k='ctx'), 'Perf ' || c, 'ethics', 'published' from generate_series(1, 5) c;
insert into public.learning_paths (org_id, code, title, status) select (select (v->>'org')::uuid from perf_r where k='ctx'), 'PERF7D_P', 'Perf yo''nalish', 'published';
insert into public.learning_path_courses (org_id, path_id, course_id, order_index, is_required)
  select (select (v->>'org')::uuid from perf_r where k='ctx'), (select id from public.learning_paths where code = 'PERF7D_P'), 'PERF7D_C' || k, k, true from generate_series(1, 5) k;
set local session_replication_role = origin;
analyze public.notifications; analyze public.employees; analyze public.profiles; analyze public.course_assignments;
select pg_temp.bench('list_first_page', 'PERF:0', $q$select count(*) from public.my_notifications(20)$q$);
select pg_temp.bench('list_page_3_cursor', 'PERF:0', $q$select count(*) from public.my_notifications(20, now() - interval '40 minutes', 'ffffffff-ffff-ffff-ffff-ffffffffffff')$q$);
select pg_temp.bench('list_unread_only', 'PERF:0', $q$select count(*) from public.my_notifications(20, null, null, true)$q$);
select pg_temp.bench('unread_count', 'PERF:0', $q$select public.unread_notification_count()$q$);
select pg_temp.bench('rls_select_own', 'PERF:0', $q$select count(*) from public.notifications$q$);
select pg_temp.bench('mark_read', 'PERF:0', $q$select public.mark_notification_read((select id from public.notifications where recipient_id = auth.uid() and read_at is null order by created_at desc limit 1))$q$);
select pg_temp.bench('mark_all_read', 'PERF:100', $q$select public.mark_all_notifications_read()$q$, 9);
-- trigger yuklamasi: 007b apply 1000 xodimga (4 bo'lim × ~250) × 5 kurs = 5000 tayinlash + 5000 course_assigned + 1000 learning_path_assigned
do $$ declare d record; t0 timestamptz; a float8[] := '{}'; s float8[]; n0 bigint; begin
  select count(*) into n0 from public.notifications;
  perform set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'a0000000-0000-0000-0000-000000000003', true);
  for d in select id from public.departments where code like 'P7DD%' order by code loop
    set local role authenticated;
    t0 := clock_timestamp(); perform public.apply_learning_path((select id from public.learning_paths where code = 'PERF7D_P'), 'department', d.id::text, null);
    a := a || extract(epoch from clock_timestamp() - t0) * 1000; reset role;
  end loop;
  select array_agg(x order by x) into s from unnest(a) x;
  insert into perf_r values ('lp_apply_with_notifications', jsonb_build_object('n', 4, 'median_ms', round(s[2]::numeric, 1), 'max_ms', round(s[4]::numeric, 1),
    'notifications_created', (select count(*) from public.notifications) - n0,
    'course_assigned', (select count(*) from public.notifications where notification_type = 'course_assigned' and event_key like 'course_assigned:%' and recipient_id::text like 'd7d00000-%'),
    'lp_assigned', (select count(*) from public.notifications where notification_type = 'learning_path_assigned' and recipient_id::text like 'd7d00000-%')));
  t0 := clock_timestamp();
  perform set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
  set local role authenticated;
  for d in select id from public.learning_path_assignments where path_id = (select id from public.learning_paths where code = 'PERF7D_P') loop
    perform public.reapply_learning_path_assignment(d.id);
  end loop;
  reset role;
  insert into perf_r values ('lp_reapply_idempotent', jsonb_build_object('total_ms', round((extract(epoch from clock_timestamp() - t0) * 1000)::numeric, 1),
    'new_notifications', (select count(*) from public.notifications) - n0 - (select (v->>'notifications_created')::bigint from perf_r where k = 'lp_apply_with_notifications')));
end $$;
insert into perf_r values ('sizes', jsonb_build_object('notifications', (select count(*) from public.notifications), 'recipients', (select count(distinct recipient_id) from public.notifications),
  'duplicates', (select count(*) from (select recipient_id, event_key from public.notifications group by 1, 2 having count(*) > 1) x)));
select jsonb_object_agg(k, v)::text as perf_007d from perf_r where k <> 'ctx';
rollback;
