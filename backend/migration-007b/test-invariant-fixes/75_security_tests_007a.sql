-- PRODUCTION (007a): 007a test to'plami (staging/007a_02_tests.sql aynan), ROLLBACK
-- Vaqtinchalik test identifikatorlari (Org B + test foydalanuvchilar, @test.local, parolsiz, tizimga kira olmaydi) FAQAT shu tranzaksiya ichida
-- yaratiladi va oxiridagi ROLLBACK bilan butunlay yo'qoladi (54/55 usuli). Doimiy akkaunt yaratilmaydi.
begin;
do $$ begin
  if not exists (select 1 from public.schema_migrations where version = '007a') then raise exception 'TO''XTATILDI: 007a qo''llanmagan'; end if;
  if exists (select 1 from auth.users where id::text like 'a0000000-%' or id::text like 'b0000000-%' or email like '%@test.local')
     or exists (select 1 from public.organizations where id = '0000000b-0000-0000-0000-00000000000b') then
    raise exception 'TO''XTATILDI: test identifikatorlari bazada allaqachon bor (kutilmagan holat)';
  end if;
end $$;
-- ---- Tranzaksiya ichidagi vaqtinchalik muhit (tests/004_test_setup.sql + tests/005_test_setup.sql, production-rad etish bloki olib tashlangan) ----
-- 004 test muhiti (FAQAT local/staging). Production'da ishga tushirilmaydi.
-- Org B + 8 ta test foydalanuvchi (parolsiz, faqat SQL orqali; tizimga kira olmaydi).


insert into public.organizations (id, name, code) values ('0000000b-0000-0000-0000-00000000000b', 'Test Org B', 'TESTB') on conflict (id) do nothing;
insert into public.branches (org_id, name, code) values ('0000000b-0000-0000-0000-00000000000b', 'B asosiy filial', 'MAIN') on conflict (org_id, code) do nothing;
insert into public.departments (org_id, branch_id, name, code)
  select '0000000b-0000-0000-0000-00000000000b', b.id, 'B Kardiologiya', 'CARDIO' from public.branches b
  where b.org_id = '0000000b-0000-0000-0000-00000000000b' and b.code = 'MAIN'
on conflict (org_id, code) do nothing;
insert into public.positions (org_id, name, code, family) values ('0000000b-0000-0000-0000-00000000000b', 'B Doctor', 'DOCTOR', 'doctor') on conflict (org_id, code) do nothing;
insert into public.specialties (org_id, name, code) values ('0000000b-0000-0000-0000-00000000000b', 'B Kardiologiya', 'CARDIOLOGY') on conflict (org_id, code) do nothing;

insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
 ('a0000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t-hr@test.local','{"full_name":"Test HR"}',now(),now()),
 ('a0000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t-edu@test.local','{"full_name":"Test Education Manager"}',now(),now()),
 ('a0000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t-instructor@test.local','{"full_name":"Test Instructor"}',now(),now()),
 ('a0000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t-head@test.local','{"full_name":"Test Dept Head"}',now(),now()),
 ('a0000000-0000-0000-0000-000000000006','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t-emp@test.local','{"full_name":"Test Employee"}',now(),now()),
 ('a0000000-0000-0000-0000-000000000007','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t-emp2@test.local','{"full_name":"Test Employee Therapy"}',now(),now()),
 ('b0000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t-b-admin@test.local','{"full_name":"Org B Admin"}',now(),now()),
 ('b0000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t-b-emp@test.local','{"full_name":"Org B Employee"}',now(),now())
on conflict (id) do nothing;

update public.profiles set status = 'active', role = 'hr', department = 'Ma''muriyat' where id = 'a0000000-0000-0000-0000-000000000002';
update public.profiles set status = 'active', role = 'education_manager', department = 'Ma''muriyat' where id = 'a0000000-0000-0000-0000-000000000003';
update public.profiles set status = 'active', role = 'instructor', department = 'Terapiya' where id = 'a0000000-0000-0000-0000-000000000004';
update public.profiles set status = 'active', role = 'department_head', department = 'Kardiologiya' where id = 'a0000000-0000-0000-0000-000000000005';
update public.profiles set status = 'active', role = 'employee', department = 'Kardiologiya' where id = 'a0000000-0000-0000-0000-000000000006';
update public.profiles set status = 'active', role = 'employee', department = 'Terapiya' where id = 'a0000000-0000-0000-0000-000000000007';
update public.profiles set status = 'active', role = 'super_admin', org_id = '0000000b-0000-0000-0000-00000000000b', department = 'B Kardiologiya' where id = 'b0000000-0000-0000-0000-000000000001';
update public.profiles set status = 'active', role = 'employee', org_id = '0000000b-0000-0000-0000-00000000000b', department = 'B Kardiologiya' where id = 'b0000000-0000-0000-0000-000000000002';

insert into public.employees (org_id, profile_id, employee_code, first_name, last_name, branch_id, department_id, position_id)
select p.org_id, p.id, 'T-' || right(p.id::text, 2), split_part(p.full_name, ' ', 1), split_part(p.full_name, ' ', 2),
       (select id from public.branches where org_id = p.org_id and code = 'MAIN'),
       (select id from public.departments where org_id = p.org_id and code = v.dept),
       (select id from public.positions where org_id = p.org_id and code = v.pos)
from public.profiles p
join (values ('a0000000-0000-0000-0000-000000000002','ADMIN','ADMINISTRATOR'), ('a0000000-0000-0000-0000-000000000003','ADMIN','ADMINISTRATOR'),
             ('a0000000-0000-0000-0000-000000000004','THERAPY','HEAD_NURSE'), ('a0000000-0000-0000-0000-000000000005','CARDIO','SENIOR_DOCTOR'),
             ('a0000000-0000-0000-0000-000000000006','CARDIO','DOCTOR'), ('a0000000-0000-0000-0000-000000000007','THERAPY','NURSE'),
             ('b0000000-0000-0000-0000-000000000001','CARDIO','DOCTOR'), ('b0000000-0000-0000-0000-000000000002','CARDIO','DOCTOR')) as v(uid, dept, pos)
  on p.id = v.uid::uuid
where not exists (select 1 from public.employees e where e.profile_id = p.id);


-- 005 test muhiti (FAQAT local/staging). 004_test_setup.sql dan keyin ishga tushiriladi.
-- Test manbalari aniq "TEST" deb belgilangan; haqiqiy nashr sifatida ko'rsatilmaydi.


-- Medical reviewer (org A) va biriktirilmagan ikkinchi instruktor
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
  ('a0000000-0000-0000-0000-000000000008', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'reviewer@test.local', '{"full_name":"Test Reviewer"}', now(), now()),
  ('a0000000-0000-0000-0000-000000000009', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'instructor2@test.local', '{"full_name":"Test Instructor2"}', now(), now())
on conflict (id) do nothing;
update public.profiles set status = 'active', role = 'medical_reviewer', department = 'Kardiologiya' where id = 'a0000000-0000-0000-0000-000000000008';
update public.profiles set status = 'active', role = 'instructor', department = 'Terapiya' where id = 'a0000000-0000-0000-0000-000000000009';
insert into public.employees (org_id, profile_id, employee_code, first_name, department_id)
select '00000000-0000-0000-0000-000000000001', v.pid, v.code, v.fn, (select id from public.departments where org_id = '00000000-0000-0000-0000-000000000001' and code = v.dep)
from (values ('a0000000-0000-0000-0000-000000000008'::uuid, 'T-08', 'Reviewer', 'CARDIO'), ('a0000000-0000-0000-0000-000000000009'::uuid, 'T-09', 'Instructor2', 'THERAPY')) v(pid, code, fn, dep)
on conflict do nothing;

-- Instruktor a…04 faqat CARDIO_BASIC kursiga biriktiriladi
insert into public.course_instructors (org_id, course_id, employee_id)
select '00000000-0000-0000-0000-000000000001', 'CARDIO_BASIC', e.id from public.employees e where e.profile_id = 'a0000000-0000-0000-0000-000000000004'
on conflict do nothing;

-- Org B: alohida kontent
insert into public.courses (id, org_id, title, domain, status, code) values ('TESTB_CARDIO', '0000000b-0000-0000-0000-00000000000b', 'B Cardio (test)', 'medical', 'published', 'B_CARDIO')
on conflict (id) do nothing;
insert into public.exam_configs (course_id, org_id, question_count, time_min, pass_score, max_attempts) values ('TESTB_CARDIO', '0000000b-0000-0000-0000-00000000000b', 1, 10, 80, 3)
on conflict (course_id) do nothing;
insert into public.course_modules (id, org_id, course_id, title, order_index, status) values ('TESTB_M1', '0000000b-0000-0000-0000-00000000000b', 'TESTB_CARDIO', 'B modul', 1, 'published')
on conflict (id) do nothing;
insert into public.lessons (org_id, module_id, title, content, order_index, status)
select '0000000b-0000-0000-0000-00000000000b', 'TESTB_M1', 'B dars', 'test', 1, 'published'
where not exists (select 1 from public.lessons where module_id = 'TESTB_M1');
insert into public.questions (id, org_id, course_id, module_id, type, topic, stem, options, answer, explanation, status, workflow_status)
values ('TESTB_Q1', '0000000b-0000-0000-0000-00000000000b', 'TESTB_CARDIO', 'TESTB_M1', 'single', 'Test', 'B test savol?', '["A","B"]', '0', 'test', 'approved', 'published')
on conflict (id) do nothing;
insert into public.evidence_sources (org_id, scope_type, source_type, title, organization)
select '0000000b-0000-0000-0000-00000000000b', 'organization', 'hospital_sop', 'TEST — Org B ichki SOP (sinov uchun, haqiqiy nashr emas)', 'Test Org B'
where not exists (select 1 from public.evidence_sources where title like 'TEST — Org B%');
insert into public.learning_paths (org_id, code, title, status) values ('0000000b-0000-0000-0000-00000000000b', 'B_PATH', 'B path', 'published')
on conflict (org_id, code) do nothing;

-- Global test manbasi (faqat SQL orqali; API'dan global yozib bo'lmaydi)
insert into public.evidence_sources (org_id, scope_type, source_type, title, organization)
select null, 'global', 'textbook', 'TEST — global darslik (sinov uchun, haqiqiy nashr emas)', 'Test Publisher'
where not exists (select 1 from public.evidence_sources where title like 'TEST — global%');

-- ---- 007a test to'plami (staging/007a_02_tests.sql, faqat ichki 'begin;' olib tashlangan) ----
-- MedAcademy · 007a learning progress test to'plami (lokal PGlite va staging uchun bir xil fayl).
-- Mavjud test akkauntlari (staging) bilan; yangi auth akkaunt yaratilmaydi. Hammasi BITTA tranzaksiyada, oxirida ROLLBACK.
-- Har bir foydalanuvchi so'rovi haqiqiy RLS / trigger / RPC orqali JWT claim'lari bilan bajariladi.
do $$ begin
  if not exists (select 1 from public.schema_migrations where version = '007a') then raise exception '007a qo''llanmagan'; end if;
  if not exists (select 1 from public.profiles where id = 'a0000000-0000-0000-0000-000000000008') then raise exception 'Test akkauntlari topilmadi (faqat test/staging muhiti)'; end if;
  if exists (select 1 from public.profiles where id = 'a0000000-0000-0000-0000-000000000008' and email not like '%@test.local') then raise exception 'Test akkaunti emas'; end if;
end $$;
create temp table t5 (id text, grp text, test text, expected text, actual text, pass boolean) on commit drop;
create temp table t5ctx (k text primary key, v text) on commit drop;
create temp table t5err (id serial, uid text, q text, err text) on commit drop;
grant all on t5, t5ctx, t5err to authenticated, anon;
grant usage, select on sequence t5err_id_seq to authenticated, anon;
create function pg_temp.login(uid uuid) returns void language plpgsql as $$ begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true); perform set_config('request.jwt.claim.sub', uid::text, true); end $$;
create function pg_temp.logout() returns void language plpgsql as $$ begin perform set_config('request.jwt.claims', '', true); perform set_config('request.jwt.claim.sub', '', true); end $$;
create function pg_temp.c(p text) returns text language sql as $$ select v from t5ctx where k = p $$;
create function pg_temp.u(p text) returns uuid language sql as $$ select v::uuid from t5ctx where k = p $$;
-- natija: actual expected bilan teng (yoki '|' bilan ajratilgan variantlardan biri)
create function pg_temp.ok(p_id text, p_grp text, p_test text, p_exp text, p_act text) returns void language sql as $$
  insert into t5 values (p_id, p_grp, p_test, p_exp, coalesce(p_act, 'NULL'), coalesce(p_act, 'NULL') = any (string_to_array(p_exp, '|'))) $$;
create function pg_temp.okb(p_id text, p_grp text, p_test text, p_exp text, p_act text, p_pass boolean) returns void language sql as $$
  insert into t5 values (p_id, p_grp, p_test, p_exp, coalesce(p_act, 'NULL'), coalesce(p_pass, false)) $$;
-- foydalanuvchi sifatida son
create function pg_temp.cnt(uid uuid, q text) returns int language plpgsql as $$ declare n int; begin
  perform pg_temp.login(uid); set local role authenticated; execute 'select count(*) from (' || q || ') z' into n; reset role; perform pg_temp.logout(); return n;
exception when others then reset role; perform pg_temp.logout(); return -1; end $$;
-- foydalanuvchi sifatida yozish: 'OK:<rows>' yoki 'DENIED'
create function pg_temp.w(uid uuid, q text) returns text language plpgsql as $$ declare n int; begin
  perform pg_temp.login(uid); set local role authenticated; execute q; get diagnostics n = row_count; reset role; perform pg_temp.logout(); return 'OK:' || n;
exception when others then reset role; perform pg_temp.logout(); insert into t5err (uid, q, err) values (uid::text, left(q, 160), sqlerrm); return 'DENIED'; end $$;
create function pg_temp.wa(q text) returns text language plpgsql as $$ declare n int; begin
  set local role anon; execute q; get diagnostics n = row_count; reset role; return 'OK:' || n;
exception when others then reset role; return 'DENIED'; end $$;
create function pg_temp.sys(q text) returns void language plpgsql as $$ begin
  perform pg_temp.logout(); perform set_config('medacademy.system_write', 'on', true); execute q; perform set_config('medacademy.system_write', 'off', true); end $$;
create function pg_temp.elig(q text) returns text language sql security definer as $$ select public._q_exam_eligible(x)::text from public.questions x where id = q $$;
create function pg_temp.st(q text) returns text language sql as $$ select workflow_status || '/' || evidence_status || '/' || coalesce(review_reason, '-') from public.questions where id = q $$;
create function pg_temp.pv(q text) returns text language sql as $$ select coalesce(published_version::text, 'NULL') from public.questions where id = q $$;
create function pg_temp.wf(q text) returns text language sql as $$ select workflow_status from public.questions where id = q $$;
create function pg_temp.ver(q text) returns int language sql as $$ select current_version from public.questions where id = q $$;
create function pg_temp.org(q text) returns text language sql as $$ select org_id::text from public.questions where id = q $$;
-- review yozish (literal qiymatlar bilan — RLS ko'rinmaslik "OK:0" emas, aniq DENIED beradi)
create function pg_temp.rv(uid uuid, q text, typ text, p_dec text) returns text language sql as $$
  select pg_temp.w(uid, format('insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision, internal_notes) values (%L, %L, %s, %L, %L, %L, ''T5E'')',
                                pg_temp.org(q), q, pg_temp.ver(q), typ, uid, p_dec)) $$;
create function pg_temp.pub(uid uuid, q text) returns text language sql as $$
  select pg_temp.w(uid, format('update public.questions set workflow_status = ''published'' where id = %L', q)) $$;
grant execute on function pg_temp.ok(text,text,text,text,text), pg_temp.okb(text,text,text,text,text,boolean), pg_temp.c(text), pg_temp.u(text) to authenticated, anon;

insert into t5ctx values ('SA','262a128c-6fb7-470e-9452-5468cd6797c0'), ('HR','a0000000-0000-0000-0000-000000000002'), ('EDU','a0000000-0000-0000-0000-000000000003'),
  ('INS','a0000000-0000-0000-0000-000000000004'), ('HEAD','a0000000-0000-0000-0000-000000000005'), ('EMP','a0000000-0000-0000-0000-000000000006'),
  ('EMP2','a0000000-0000-0000-0000-000000000007'), ('REV','a0000000-0000-0000-0000-000000000008'), ('INS2','a0000000-0000-0000-0000-000000000009'),
  ('BADM','b0000000-0000-0000-0000-000000000001'), ('BEMP','b0000000-0000-0000-0000-000000000002'),
  ('OA','00000000-0000-0000-0000-000000000001'), ('OB','0000000b-0000-0000-0000-00000000000b');



-- ---------- Fixture'lar (faqat shu tranzaksiya; ROLLBACK) ----------
create function pg_temp.emp(p text) returns text language sql security definer as $$ select id::text from public.employees where profile_id = pg_temp.u(p) $$;
create function pg_temp.rpc(uid uuid, q text) returns text language plpgsql as $$ declare v text; begin
  perform pg_temp.login(uid); set local role authenticated; execute 'select (' || q || ')::text' into v; reset role; perform pg_temp.logout(); return coalesce(v, 'NULL');
exception when others then reset role; perform pg_temp.logout(); insert into t5err (uid, q, err) values (uid::text, left(q, 160), sqlerrm); return 'DENIED'; end $$;
create function pg_temp.rpca(q text) returns text language plpgsql as $$ declare v text; begin
  set local role anon; execute 'select (' || q || ')::text' into v; reset role; return coalesce(v, 'NULL');
exception when others then reset role; return 'DENIED'; end $$;
-- xodimning o'z progress qatori (kurs bo'yicha) — "total/done/pct/status"
create function pg_temp.mp(p text, c text) returns text language sql as $$
  select pg_temp.rpc(pg_temp.u(p), format('(select coalesce(string_agg(total_required_lessons || ''/'' || completed_required_lessons || ''/'' || progress_percent || ''/'' || computed_status, '','' order by course_id), ''none'') from public.my_learning_progress() where course_id = %L)', c)) $$;
create function pg_temp.done(p text, lesson uuid) returns text language sql as $$
  select pg_temp.w(pg_temp.u(p), format('insert into public.lesson_progress (org_id, lesson_id, employee_id, status) values (%L, %L, %L, ''completed'') on conflict (lesson_id, employee_id) do update set status = ''completed''',
    (select org_id from public.lessons where id = lesson), lesson, pg_temp.emp(p))) $$;
create function pg_temp.sum(p text, c text, k text) returns text language sql as $$
  select case when r like '{%' then (r::jsonb ->> k) else r end from (select pg_temp.rpc(pg_temp.u(p), format('public.course_progress_summary(%L)', c)) r) x $$;

do $$ begin
  perform pg_temp.logout();
  insert into t5ctx select 'BASE', json_build_object(
    'attempts_md5', (select md5(coalesce(string_agg(to_jsonb(a)::text, '' order by a.id), '')) from public.exam_attempts a),
    'certs_md5', (select md5(coalesce(string_agg(to_jsonb(c)::text, '' order by c.id), '')) from public.certificates c),
    'policies', (select md5(string_agg(tablename || '.' || policyname || ':' || cmd || ':' || coalesce(qual, '-') || ':' || coalesce(with_check, '-'), '|' order by tablename, policyname)) from pg_policies where schemaname = 'public'))::text;
  perform pg_temp.sys(format($q$
    insert into public.courses (id, org_id, title, domain, status) values ('T7A_C', %1$L, 'T7A kurs', 'ethics', 'published'), ('T7A_ZERO', %1$L, 'T7A ixtiyoriy', 'ethics', 'published'), ('T7A_B', %2$L, 'T7A Org B', 'ethics', 'published');
    insert into public.course_modules (id, org_id, course_id, title, order_index, status) values
      ('T7A_M1', %1$L, 'T7A_C', 'M1', 1, 'published'), ('T7A_M2', %1$L, 'T7A_C', 'M2', 2, 'published'), ('T7A_M3', %1$L, 'T7A_C', 'M3 (draft)', 3, 'draft'),
      ('T7A_MZ', %1$L, 'T7A_ZERO', 'MZ', 1, 'published'), ('T7A_MB', %2$L, 'T7A_B', 'MB', 1, 'published');
    insert into public.lessons (id, org_id, module_id, title, content_type, order_index, status, is_required)
      select ('70000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, %1$L, case when g <= 5 then 'T7A_M1' else 'T7A_M2' end, 'L' || g, 'text', g, 'published', true from generate_series(1, 10) g;
    insert into public.lessons (id, org_id, module_id, title, content_type, order_index, status, is_required) values
      ('70000000-0000-0000-0000-000000000011', %1$L, 'T7A_M2', 'Ixtiyoriy', 'text', 11, 'published', false),
      ('70000000-0000-0000-0000-000000000012', %1$L, 'T7A_M2', 'Draft dars', 'text', 12, 'draft', true),
      ('70000000-0000-0000-0000-000000000013', %1$L, 'T7A_M3', 'Draft modul darsi', 'text', 1, 'published', true),
      ('70000000-0000-0000-0000-000000000021', %1$L, 'T7A_MZ', 'Faqat ixtiyoriy', 'text', 1, 'published', false),
      ('70000000-0000-0000-0000-000000000031', %2$L, 'T7A_MB', 'B1', 'text', 1, 'published', true),
      ('70000000-0000-0000-0000-000000000032', %2$L, 'T7A_MB', 'B2', 'text', 2, 'published', true);
    insert into public.course_assignments (org_id, course_id, employee_id, due_date, status) values
      (%1$L, 'T7A_C', %3$L, current_date + 30, 'assigned'),
      (%1$L, 'T7A_C', %4$L, current_date - 1, 'assigned'),
      (%1$L, 'T7A_ZERO', %3$L, null, 'assigned'),
      (%1$L, 'T7A_ZERO', %4$L, current_date, 'assigned'),
      (%2$L, 'T7A_B', %5$L, current_date + 5, 'assigned');
    insert into public.course_assignments (org_id, course_id, employee_id, due_date, status) values (%1$L, 'CARDIO_BASIC', %4$L, current_date - 10, 'cancelled');
  $q$, pg_temp.c('OA'), pg_temp.c('OB'), pg_temp.emp('EMP'), pg_temp.emp('EMP2'), pg_temp.emp('BEMP')));
end $$;

-- ===== P. my_learning_progress va progress formulasi =====
do $$ declare a0 int; begin
  perform pg_temp.ok('P01', 'Progress', 'EMP: boshlang''ich holat (draft dars/modul va ixtiyoriy dars maxrajda yo''q)', '10/0/0/not_started', pg_temp.mp('EMP', 'T7A_C'));
  perform pg_temp.ok('P02', 'Progress', 'EMP: 1 dars tugallandi (API orqali)', 'OK:1', pg_temp.done('EMP', '70000000-0000-0000-0000-000000000001'));
  perform pg_temp.ok('P03', 'Progress', '1/10 → 10%, in_progress', '10/1/10/in_progress', pg_temp.mp('EMP', 'T7A_C'));
  perform pg_temp.ok('P04', 'Progress', 'course_assignments holati in_progress (mavjud trigger)', 'in_progress', (select status from public.course_assignments where course_id = 'T7A_C' and employee_id = pg_temp.emp('EMP')::uuid));
  perform pg_temp.done('EMP', ('70000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid) from generate_series(2, 9) g;
  perform pg_temp.ok('P05', 'Progress', '9/10 → 90%', '10/9/90/in_progress', pg_temp.mp('EMP', 'T7A_C'));
  perform pg_temp.done('EMP', '70000000-0000-0000-0000-000000000011');
  perform pg_temp.ok('P06', 'Progress', 'Ixtiyoriy dars tugallanishi foizni o''zgartirmaydi', '10/9/90/in_progress', pg_temp.mp('EMP', 'T7A_C'));
  perform pg_temp.ok('P07', 'Progress', 'Hali kurs tugallanmagan, audit yo''q', '0', (select count(*)::text from public.audit_logs where action = 'course.completed' and new_value ->> 'course_id' = 'T7A_C'));
  perform pg_temp.done('EMP', '70000000-0000-0000-0000-000000000010');
  perform pg_temp.ok('P08', 'Progress', '10/10 → 100%, completed', '10/10/100/completed', pg_temp.mp('EMP', 'T7A_C'));
  perform pg_temp.ok('P09', 'Completion', 'course_assignments → completed, completed_at qo''yildi', 'completed/true',
    (select status || '/' || (completed_at is not null)::text from public.course_assignments where course_id = 'T7A_C' and employee_id = pg_temp.emp('EMP')::uuid));
  perform pg_temp.ok('P10', 'Completion', 'course.completed audit: 1 ta, actor = xodim, eski holat in_progress', '1/true',
    (select count(*) || '/' || bool_and(actor_id::text = pg_temp.c('EMP') and old_value ->> 'status' = 'in_progress' and new_value ->> 'status' = 'completed')::text
       from public.audit_logs where action = 'course.completed' and new_value ->> 'course_id' = 'T7A_C'));
  a0 := (select count(*) from public.audit_logs);
  perform pg_temp.mp('EMP', 'T7A_C'); perform pg_temp.mp('EMP', 'T7A_C'); perform pg_temp.sum('SA', 'T7A_C', 'assigned_count');
  perform pg_temp.ok('P11', 'Completion', 'O''qish RPC''lari audit yozmaydi (qayta chaqiruvlar)', a0::text, (select count(*)::text from public.audit_logs));
  perform pg_temp.w(pg_temp.u('EMP'), 'update public.lesson_progress set status = ''completed'', progress_percent = 100 where lesson_id = ''70000000-0000-0000-0000-000000000010''');
  perform pg_temp.done('EMP', '70000000-0000-0000-0000-000000000005');
  perform pg_temp.ok('P12', 'Completion', 'Idempotentlik: qayta belgilashda takroriy course.completed yo''q', '1', (select count(*)::text from public.audit_logs where action = 'course.completed' and new_value ->> 'course_id' = 'T7A_C'));
  perform pg_temp.ok('P13', 'Completion', 'Sertifikat yaratilmagan (tugallash ≠ sertifikat)', (pg_temp.c('BASE')::json ->> 'certs_md5'),
    (select md5(coalesce(string_agg(to_jsonb(c)::text, '' order by c.id), '')) from public.certificates c));
end $$;

-- ===== Z. Chegaraviy holatlar =====
do $$ begin
  perform pg_temp.ok('Z01', 'Edge', 'Majburiy darssiz kurs: 0/0/0, not_started', '0/0/0/not_started', pg_temp.mp('EMP', 'T7A_ZERO'));
  perform pg_temp.done('EMP', '70000000-0000-0000-0000-000000000021');
  perform pg_temp.ok('Z02', 'Edge', 'Faqat ixtiyoriy dars tugallandi → avtomatik tugallash YO''Q (in_progress)', '0/0/0/in_progress', pg_temp.mp('EMP', 'T7A_ZERO'));
  perform pg_temp.ok('Z03', 'Edge', 'Majburiy darssiz kurs tayinlashi completed bo''lmagan', 'in_progress', (select status from public.course_assignments where course_id = 'T7A_ZERO' and employee_id = pg_temp.emp('EMP')::uuid));
  perform pg_temp.ok('Z04', 'Edge', 'Muddati o''tgan (kecha) → overdue', '10/0/0/overdue', pg_temp.mp('EMP2', 'T7A_C'));
  perform pg_temp.ok('Z05', 'Edge', 'Muddat bugun → overdue EMAS', '0/0/0/not_started', pg_temp.mp('EMP2', 'T7A_ZERO'));
  perform pg_temp.ok('Z06', 'Edge', 'Bekor qilingan (muddati o''tgan) → cancelled, overdue emas', '0/0/0/cancelled',
    regexp_replace(pg_temp.mp('EMP2', 'CARDIO_BASIC'), '^[0-9]+/0/0/', '0/0/0/'));
  perform pg_temp.ok('Z07', 'Edge', 'Overdue bazaga yozilmagan (status assigned qolgan)', 'assigned', (select status from public.course_assignments where course_id = 'T7A_C' and employee_id = pg_temp.emp('EMP2')::uuid));
  perform pg_temp.ok('Z08', 'Edge', 'Progress qatori yo''q dars → 0 sifatida hisoblanadi (xato yo''q)', '10/0/0/overdue', pg_temp.mp('EMP2', 'T7A_C'));
  perform pg_temp.ok('Z09', 'Edge', 'Takroriy progress qatori (lesson_id, employee_id) unique — ikkinchi INSERT rad', 'DENIED',
    pg_temp.w(pg_temp.u('EMP2'), format('insert into public.lesson_progress (org_id, lesson_id, employee_id, status) values (%L, %L, %L, ''in_progress''), (%L, %L, %L, ''in_progress'')',
      pg_temp.c('OA'), '70000000-0000-0000-0000-000000000001', pg_temp.emp('EMP2'), pg_temp.c('OA'), '70000000-0000-0000-0000-000000000001', pg_temp.emp('EMP2'))));
  perform pg_temp.sys($q$update public.courses set status = 'archived' where id = 'T7A_C'$q$);
  perform pg_temp.ok('Z10', 'Edge', 'Arxivlangan kurs: tarixiy progress ko''rinishda qoladi', '10/10/100/completed', pg_temp.mp('EMP', 'T7A_C'));
  perform pg_temp.sys($q$update public.courses set status = 'published' where id = 'T7A_C'$q$);
end $$;

-- ===== S. Xavfsizlik: my_learning_progress =====
do $$ begin
  perform pg_temp.ok('S01', 'Security', 'EMP faqat o''z tayinlashlarini ko''radi (2 ta)', 'T7A_C,T7A_ZERO',
    pg_temp.rpc(pg_temp.u('EMP'), '(select string_agg(course_id, '','' order by course_id) from public.my_learning_progress())'));
  perform pg_temp.ok('S02', 'Security', 'EMP2 ro''yxatida EMP tayinlashi yo''q (o''zinikilari 3 ta)', 'CARDIO_BASIC,T7A_C,T7A_ZERO',
    pg_temp.rpc(pg_temp.u('EMP2'), '(select string_agg(course_id, '','' order by course_id) from public.my_learning_progress())'));
  perform pg_temp.ok('S03', 'Security', 'Org B xodimi faqat Org B kursini ko''radi', 'T7A_B', pg_temp.rpc(pg_temp.u('BEMP'), '(select string_agg(course_id, '','') from public.my_learning_progress())'));
  perform pg_temp.ok('S04', 'Security', 'anon: my_learning_progress', 'DENIED', pg_temp.rpca('(select count(*) from public.my_learning_progress())'));
  perform pg_temp.ok('S05', 'Security', 'Javobda faqat ruxsat etilgan maydonlar (12 ta, ichki maydonsiz)', 'assigned_at,assignment_id,assignment_status,completed_at,completed_required_lessons,computed_status,course_id,course_title,due_date,last_activity_at,progress_percent,total_required_lessons',
    pg_temp.rpc(pg_temp.u('EMP'), '(select string_agg(k, '','' order by k) from (select jsonb_object_keys(to_jsonb(t)) k from public.my_learning_progress() t limit 12) x)'));
  perform pg_temp.ok('S06', 'Security', 'EMP: boshqa xodim tayinlashini to''g''ridan-to''g''ri SELECT (RLS)', '0',
    pg_temp.cnt(pg_temp.u('EMP'), format('select 1 from public.course_assignments where employee_id = %L', pg_temp.emp('EMP2')))::text);
  perform pg_temp.ok('S07', 'Security', 'EMP: boshqa xodim progressini SELECT (RLS)', '0',
    pg_temp.cnt(pg_temp.u('EMP2'), format('select 1 from public.lesson_progress where employee_id = %L', pg_temp.emp('EMP')))::text);
  perform pg_temp.ok('S08', 'Security', 'EMP: boshqa xodim nomidan progress yozish', 'DENIED|OK:0',
    pg_temp.w(pg_temp.u('EMP'), format('insert into public.lesson_progress (org_id, lesson_id, employee_id, status) values (%L, %L, %L, ''completed'')', pg_temp.c('OA'), '70000000-0000-0000-0000-000000000002', pg_temp.emp('EMP2'))));
  perform pg_temp.sys(format($q$update public.employees set employment_status = 'inactive' where id = %L$q$, pg_temp.emp('EMP2')));
  perform pg_temp.ok('S09', 'Security', 'Nofaol xodim: bo''sh ro''yxat (xatosiz)', 'NULL', pg_temp.rpc(pg_temp.u('EMP2'), '(select string_agg(course_id, '','') from public.my_learning_progress())'));
  perform pg_temp.sys(format($q$update public.employees set employment_status = 'active' where id = %L$q$, pg_temp.emp('EMP2')));
end $$;

-- ===== R. course_progress_summary: rollar va doira =====
do $$ begin
  perform pg_temp.ok('R01', 'Summary', 'SA: tashkilot doirasi (2 tayinlash: 1 completed, 1 overdue)', 'organization/2/1/1/0/10',
    pg_temp.sum('SA', 'T7A_C', 'scope') || '/' || pg_temp.sum('SA', 'T7A_C', 'assigned_count') || '/' || pg_temp.sum('SA', 'T7A_C', 'completed_count') || '/' || pg_temp.sum('SA', 'T7A_C', 'overdue_count') || '/' || pg_temp.sum('SA', 'T7A_C', 'not_started_count') || '/' || pg_temp.sum('SA', 'T7A_C', 'total_required_lessons'));
  perform pg_temp.ok('R02', 'Summary', 'SA: o''rtacha progress (100 + 0) / 2', '50.0', pg_temp.sum('SA', 'T7A_C', 'average_progress'));
  perform pg_temp.ok('R03', 'Summary', 'EM: tashkilot doirasi', 'organization/2', pg_temp.sum('EDU', 'T7A_C', 'scope') || '/' || pg_temp.sum('EDU', 'T7A_C', 'assigned_count'));
  perform pg_temp.ok('R04', 'Summary', 'HR: tashkilot doirasi', 'organization/2', pg_temp.sum('HR', 'T7A_C', 'scope') || '/' || pg_temp.sum('HR', 'T7A_C', 'assigned_count'));
  perform pg_temp.ok('R05', 'Summary', 'Department Head (Kardiologiya): faqat o''z bo''limi (EMP)', 'department/1/1/0', pg_temp.sum('HEAD', 'T7A_C', 'scope') || '/' || pg_temp.sum('HEAD', 'T7A_C', 'assigned_count') || '/' || pg_temp.sum('HEAD', 'T7A_C', 'completed_count') || '/' || pg_temp.sum('HEAD', 'T7A_C', 'overdue_count'));
  perform pg_temp.ok('R06', 'Summary', 'Instructor: o''z kursi bo''lmagan kurs', 'DENIED', pg_temp.sum('INS', 'T7A_C', 'scope'));
  perform pg_temp.ok('R07', 'Summary', 'Instructor: o''z kursi (CARDIO_BASIC)', 'course_instructor', pg_temp.sum('INS', 'CARDIO_BASIC', 'scope'));
  perform pg_temp.ok('R08', 'Summary', 'Medical Reviewer', 'DENIED', pg_temp.sum('REV', 'T7A_C', 'scope'));
  perform pg_temp.ok('R09', 'Summary', 'Employee', 'DENIED', pg_temp.sum('EMP', 'T7A_C', 'scope'));
  perform pg_temp.ok('R10', 'Summary', 'anon', 'DENIED', pg_temp.rpca('public.course_progress_summary(''T7A_C'')'));
  perform pg_temp.ok('R11', 'Summary', 'Org B admin: Org A kursi', 'DENIED', pg_temp.sum('BADM', 'T7A_C', 'scope'));
  perform pg_temp.ok('R12', 'Summary', 'Org B admin: o''z kursi', 'organization/1', pg_temp.sum('BADM', 'T7A_B', 'scope') || '/' || pg_temp.sum('BADM', 'T7A_B', 'assigned_count'));
  perform pg_temp.ok('R13', 'Summary', 'Org A Head: Org B kursi', 'DENIED', pg_temp.sum('HEAD', 'T7A_B', 'scope'));
  perform pg_temp.ok('R14', 'Summary', 'Bekor qilingan tayinlash alohida hisoblanadi', '1/0', pg_temp.sum('SA', 'CARDIO_BASIC', 'cancelled_count') || '/' || pg_temp.sum('SA', 'CARDIO_BASIC', 'overdue_count'));
  perform pg_temp.ok('R15', 'Summary', 'Mavjud bo''lmagan kurs', 'DENIED', pg_temp.sum('SA', 'NO_SUCH_COURSE', 'scope'));
end $$;

-- ===== I. Invariantlar =====
do $$ begin
  perform pg_temp.ok('I01', 'Invariants', 'anon EXECUTE (faqat verify_certificate)', 'verify_certificate',
    (select string_agg(p.proname, ',') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'EXECUTE')));
  perform pg_temp.ok('I02', 'Invariants', 'Ichki funksiyalar authenticated uchun EXECUTE emas', '0',
    (select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_lp_course_stats_007a', '_lp_status_007a', 'lesson_progress_completion_007a') and has_function_privilege('authenticated', p.oid, 'EXECUTE')));
  perform pg_temp.ok('I03', 'Invariants', 'RLS policy''lari o''zgarmagan', 'true',
    ((select md5(string_agg(tablename || '.' || policyname || ':' || cmd || ':' || coalesce(qual, '-') || ':' || coalesce(with_check, '-'), '|' order by tablename, policyname)) from pg_policies where schemaname = 'public') = (pg_temp.c('BASE')::json ->> 'policies'))::text);
  perform pg_temp.ok('I04', 'Invariants', 'Tarixiy urinishlar o''zgarmagan', 'true', ((select md5(coalesce(string_agg(to_jsonb(a)::text, '' order by a.id), '')) from public.exam_attempts a) = (pg_temp.c('BASE')::json ->> 'attempts_md5'))::text);
  perform pg_temp.ok('I05', 'Invariants', 'Yangi jadval yo''q (public jadvallar 44; 007b qo''llangan bo''lsa +1 learning_path_assignments)', (44 + (select count(*) from public.schema_migrations where version = '007b'))::text, (select count(*)::text from pg_tables where schemaname = 'public'));
  perform pg_temp.ok('I06', 'Invariants', 'lessons.is_required: NOT NULL DEFAULT true', 'NO/true', (select is_nullable || '/' || column_default from information_schema.columns where table_schema = 'public' and table_name = 'lessons' and column_name = 'is_required'));
  perform pg_temp.ok('I07', 'Invariants', 'CASCADE FK yo''q', '0', (select count(*)::text from pg_constraint where connamespace = 'public'::regnamespace and contype = 'f' and confdeltype = 'c'));
  perform pg_temp.ok('I08', 'Invariants', '007a schema_migrations / trigger', '1/1', (select count(*) from public.schema_migrations where version = '007a') || '/' || (select count(*) from pg_trigger where tgname = 'lesson_progress_completion_007a_trg'));
end $$;

select line from (
  select 0 ord, 'SUMMARY 007a total ' || count(*) || ' / PASS ' || count(*) filter (where pass) || ' / FAIL ' || count(*) filter (where not pass) || coalesce(' :: ' || string_agg(id, ',' order by id) filter (where not pass), '') as line from t5
  union all select 1, id || ' ' || case when pass then 'PASS' else 'FAIL' end || ' [' || grp || '] ' || test || ' :: kutilgan=' || expected || ' :: natija=' || actual from t5) x order by ord, line;
select json_build_object('total', count(*), 'pass', count(*) filter (where pass), 'fail', count(*) filter (where not pass),
  'fail_ids', coalesce(json_agg(id || ' => ' || actual order by id) filter (where not pass), '[]'::json),
  'groups', (select json_object_agg(grp, n) from (select grp, count(*) || '/' || count(*) filter (where pass) n from t5 group by grp) g))::text as summary_007a from t5;
rollback;
