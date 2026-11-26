-- PRODUCTION (007b): 007b test to'plami (staging/007b_02_tests.sql aynan), ROLLBACK
-- Vaqtinchalik test identifikatorlari (Org B + test foydalanuvchilar, @test.local, parolsiz, tizimga kira olmaydi) FAQAT shu tranzaksiya ichida
-- yaratiladi va oxiridagi ROLLBACK bilan butunlay yo'qoladi (54/55 usuli). Doimiy akkaunt yaratilmaydi.
begin;
do $$ begin
  if not exists (select 1 from public.schema_migrations where version = '007b') then raise exception 'TO''XTATILDI: 007b qo''llanmagan'; end if;
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

-- ---- 007b test to'plami (staging/007b_02_tests.sql, faqat ichki 'begin;' olib tashlangan) ----
-- MedAcademy · 007b learning path assignments test to'plami (lokal PGlite va staging uchun bir xil fayl).
-- Mavjud test akkauntlari (staging) bilan; yangi auth akkaunt yaratilmaydi. Hammasi BITTA tranzaksiyada, oxirida ROLLBACK.
-- Har bir foydalanuvchi so'rovi haqiqiy RLS / trigger / RPC orqali JWT claim'lari bilan bajariladi.
do $$ begin
  if not exists (select 1 from public.schema_migrations where version = '007b') then raise exception '007b qo''llanmagan'; end if;
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
create function pg_temp.sysok(q text) returns boolean language plpgsql as $$ begin
  perform pg_temp.logout(); execute q; return true; exception when others then return false; end $$;
create function pg_temp.emp(p text) returns uuid language sql security definer as $$ select id from public.employees where profile_id = pg_temp.u(p) $$;
create function pg_temp.rpc(uid uuid, q text) returns text language plpgsql as $$ declare v text; begin
  perform pg_temp.login(uid); set local role authenticated; execute 'select (' || q || ')::text' into v; reset role; perform pg_temp.logout(); return coalesce(v, 'NULL');
exception when others then reset role; perform pg_temp.logout(); insert into t5err (uid, q, err) values (uid::text, left(q, 160), sqlerrm); return 'DENIED'; end $$;
create function pg_temp.rpca(q text) returns text language plpgsql as $$ declare v text; begin
  set local role anon; execute 'select (' || q || ')::text' into v; reset role; return coalesce(v, 'NULL');
exception when others then reset role; return 'DENIED'; end $$;
create function pg_temp.pid(code text) returns uuid language sql security definer as $$ select id from public.learning_paths where code = $1 $$;
create function pg_temp.ap(p text, path text, typ text, tgt text, due date default null) returns text language sql as $$
  select pg_temp.rpc(pg_temp.u(p), format('public.apply_learning_path(%L, %L, %L, %L)', pg_temp.pid(path), typ, tgt, due)) $$;
create function pg_temp.j(t text, k text) returns text language sql as $$ select case when t like '{%' then t::jsonb ->> k else t end $$;
create function pg_temp.jx(t text) returns text language sql as $$ select case when t like '{%' then (t::jsonb ->> 'rule') || '/' || (t::jsonb ->> 'employees_matched') || '/' || (t::jsonb ->> 'course_assignments_created') else t end $$;
create function pg_temp.ca(e uuid, c text) returns text language sql security definer as $$ select coalesce(string_agg(status, ',' order by created_at), 'none') from public.course_assignments where employee_id = e and course_id = c $$;
create function pg_temp.dep(org text, code text) returns text language sql security definer as $$ select id::text from public.departments where org_id = pg_temp.c(org)::uuid and code = $2 $$;
create function pg_temp.rule(path text, key text) returns uuid language sql security definer as $$ select id from public.learning_path_assignments where path_id = pg_temp.pid(path) and target_key = key and status = 'active' $$;

do $$ declare oa uuid := pg_temp.c('OA')::uuid; ob uuid := pg_temp.c('OB')::uuid; begin
  perform pg_temp.logout();
  insert into t5ctx select 'BASE', json_build_object(
    'attempts_md5', (select md5(coalesce(string_agg(to_jsonb(a)::text, '' order by a.id), '')) from public.exam_attempts a),
    'certs_md5', (select md5(coalesce(string_agg(to_jsonb(c)::text, '' order by c.id), '')) from public.certificates c),
    'policies', (select count(*) from pg_policies where schemaname = 'public'))::text;
  perform pg_temp.sys(format($q$
    insert into public.courses (id, org_id, title, domain, status) values
      ('T7B_C1', %1$L, 'T7B kurs 1', 'ethics', 'published'), ('T7B_C2', %1$L, 'T7B kurs 2', 'ethics', 'published'),
      ('T7B_C3', %1$L, 'T7B ixtiyoriy', 'ethics', 'published'), ('T7B_CD', %1$L, 'T7B draft kurs', 'ethics', 'draft'),
      ('T7B_BC1', %2$L, 'T7B Org B kurs', 'ethics', 'published');
    insert into public.learning_paths (org_id, code, title, status) values
      (%1$L, 'T7B_P', 'T7B yo''nalish', 'published'), (%1$L, 'T7B_ARCH', 'T7B arxiv', 'archived'), (%1$L, 'T7B_DRAFT', 'T7B draft', 'draft'),
      (%2$L, 'T7B_PB', 'T7B Org B yo''nalish', 'published');
    insert into public.learning_path_courses (org_id, path_id, course_id, order_index, is_required) values
      (%1$L, (select id from public.learning_paths where code = 'T7B_P'), 'T7B_C1', 1, true),
      (%1$L, (select id from public.learning_paths where code = 'T7B_P'), 'T7B_C2', 2, true),
      (%1$L, (select id from public.learning_paths where code = 'T7B_P'), 'T7B_C3', 3, false),
      (%1$L, (select id from public.learning_paths where code = 'T7B_P'), 'T7B_CD', 4, true),
      (%1$L, (select id from public.learning_paths where code = 'T7B_ARCH'), 'T7B_C1', 1, true),
      (%2$L, (select id from public.learning_paths where code = 'T7B_PB'), 'T7B_BC1', 1, true);
    insert into public.positions (org_id, name, code, status) values (%1$L, 'T7B lavozim', 'T7B_POS', 'active'), (%2$L, 'T7B B lavozim', 'T7B_POSB', 'active');
    insert into public.specialties (org_id, name, code, status) values (%1$L, 'T7B mutaxassislik', 'T7B_SPEC', 'active'), (%2$L, 'T7B B mutaxassislik', 'T7B_SPECB', 'active');
    update public.employees set position_id = (select id from public.positions where code = 'T7B_POS'), specialty_id = (select id from public.specialties where code = 'T7B_SPEC') where id = %3$L;
    insert into public.employees (org_id, employee_code, first_name, last_name, department_id, employment_status) values
      (%1$L, 'T7B_INACT', 'Nofaol', 'Xodim', (select id from public.departments where org_id = %1$L and code = 'CARDIO'), 'inactive'),
      (%1$L, 'T7B_LEAVE', 'Ta''tildagi', 'Xodim', (select id from public.departments where org_id = %1$L and code = 'CARDIO'), 'on_leave');
    insert into public.course_assignments (org_id, course_id, employee_id, status, started_at, completed_at) values
      (%1$L, 'T7B_C1', %4$L, 'completed', now() - interval '2 days', now() - interval '1 day'),
      (%1$L, 'T7B_C2', %4$L, 'in_progress', now() - interval '1 day', null);
    insert into public.course_assignments (org_id, course_id, employee_id, status) values (%1$L, 'T7B_C1', %5$L, 'cancelled');
  $q$, oa, ob, pg_temp.emp('EMP'), pg_temp.emp('EMP2'), pg_temp.emp('HEAD')));
  insert into t5ctx select 'EMP2_C1', (select completed_at::text from public.course_assignments where employee_id = pg_temp.emp('EMP2') and course_id = 'T7B_C1');
end $$;

-- ===== A. Xodim nishoni + idempotentlik =====
do $$ declare r text; begin
  r := pg_temp.ap('EDU', 'T7B_P', 'employee', pg_temp.emp('EMP')::text);
  perform pg_temp.ok('A01', 'Employee target', 'EM: EMP ga tayinlash → qoida yaratildi, 1 xodim, 2 kurs (ixtiyoriy va draft kurs yo''q)', 'created/1/2', pg_temp.jx(r));
  perform pg_temp.ok('A02', 'Employee target', 'EMP kurslari: C1, C2 assigned; C3 (ixtiyoriy) va CD (draft) yo''q', 'assigned/assigned/none/none',
    pg_temp.ca(pg_temp.emp('EMP'), 'T7B_C1') || '/' || pg_temp.ca(pg_temp.emp('EMP'), 'T7B_C2') || '/' || pg_temp.ca(pg_temp.emp('EMP'), 'T7B_C3') || '/' || pg_temp.ca(pg_temp.emp('EMP'), 'T7B_CD'));
  perform pg_temp.ok('A03', 'Idempotency', 'Qayta chaqiruv → existing, 0 yangi', 'existing/1/0', pg_temp.jx(pg_temp.ap('EDU', 'T7B_P', 'employee', pg_temp.emp('EMP')::text)));
  perform pg_temp.ok('A04', 'Idempotency', 'Uchinchi chaqiruv → existing, 0 yangi', 'existing/1/0', pg_temp.jx(pg_temp.ap('EDU', 'T7B_P', 'employee', pg_temp.emp('EMP')::text)));
  perform pg_temp.ok('A05', 'Idempotency', 'Faqat bitta active qoida', '1', (select count(*)::text from public.learning_path_assignments where path_id = pg_temp.pid('T7B_P') and employee_id = pg_temp.emp('EMP')));
  perform pg_temp.ok('A06', 'Audit', 'assignment_created 1 ta, courses_applied 1 ta (takrorlarda yangi audit yo''q)', '1/1',
    (select count(*) filter (where action = 'learning_path.assignment_created') || '/' || count(*) filter (where action = 'learning_path.courses_applied') from public.audit_logs where entity_id = pg_temp.rule('T7B_P', pg_temp.emp('EMP')::text)::text));
  r := pg_temp.ap('EDU', 'T7B_P', 'employee', pg_temp.emp('EMP')::text, current_date + 30);
  perform pg_temp.ok('A07', 'Due date', 'Muddat bilan qayta → updated, 0 yangi kurs', 'updated/1/0', pg_temp.jx(r));
  perform pg_temp.ok('A08', 'Due date', 'assignment_updated audit 1; mavjud kurs tayinlashlari muddati o''zgarmagan (NULL)', '1/0',
    (select count(*) from public.audit_logs where action = 'learning_path.assignment_updated' and entity_id = pg_temp.rule('T7B_P', pg_temp.emp('EMP')::text)::text) || '/' ||
    (select count(*) from public.course_assignments where employee_id = pg_temp.emp('EMP') and course_id like 'T7B_%' and due_date is not null));
end $$;

-- ===== B–E. Bo'lim / lavozim / mutaxassislik / rol, takrorsiz =====
do $$ declare r text; n int; begin
  n := (select count(*) from public.employees where org_id = pg_temp.c('OA')::uuid and department_id = pg_temp.dep('OA', 'CARDIO')::uuid and employment_status in ('active', 'on_leave'));
  r := pg_temp.ap('EDU', 'T7B_P', 'department', pg_temp.dep('OA', 'CARDIO'), current_date + 14);
  perform pg_temp.ok('B01', 'Department target', 'Kardiologiya: barcha faol xodimlar mos keldi (nofaol yo''q)', 'created/' || n, split_part(pg_temp.jx(r), '/', 1) || '/' || split_part(pg_temp.jx(r), '/', 2));
  perform pg_temp.ok('B02', 'Department target', 'HEAD: C1 bekor qilingani saqlangan (qayta yaratilmagan), C2 yangi tayinlandi', 'cancelled/assigned',
    pg_temp.ca(pg_temp.emp('HEAD'), 'T7B_C1') || '/' || pg_temp.ca(pg_temp.emp('HEAD'), 'T7B_C2'));
  perform pg_temp.ok('B03', 'Department target', 'Yangi tayinlashlar qoida muddatini oldi; EMP ning eski tayinlashi o''zgarmadi', 'true/NULL',
    ((select due_date from public.course_assignments where employee_id = pg_temp.emp('HEAD') and course_id = 'T7B_C2') = current_date + 14)::text || '/' ||
    coalesce((select due_date::text from public.course_assignments where employee_id = pg_temp.emp('EMP') and course_id = 'T7B_C1'), 'NULL'));
  perform pg_temp.ok('B04', 'Inactive', 'Nofaol xodim (bo''lim a''zosi) tayinlanmadi', '0', (select count(*)::text from public.course_assignments ca join public.employees e on e.id = ca.employee_id where e.employee_code = 'T7B_INACT'));
  perform pg_temp.ok('B05', 'On leave', 'Ta''tildagi (on_leave) bo''lim xodimi qamrab olindi (C1, C2)', 'assigned/assigned',
    pg_temp.ca((select id from public.employees where employee_code = 'T7B_LEAVE'), 'T7B_C1') || '/' || pg_temp.ca((select id from public.employees where employee_code = 'T7B_LEAVE'), 'T7B_C2'));
  perform pg_temp.ok('C01', 'Position target', 'Lavozim: EMP mos, takror yo''q', 'created/1/0', pg_temp.jx(pg_temp.ap('EDU', 'T7B_P', 'position', (select id::text from public.positions where code = 'T7B_POS'))));
  perform pg_temp.ok('D01', 'Specialty target', 'Mutaxassislik: EMP mos, takror yo''q', 'created/1/0', pg_temp.jx(pg_temp.ap('EDU', 'T7B_P', 'specialty', (select id::text from public.specialties where code = 'T7B_SPEC'))));
  r := pg_temp.ap('EDU', 'T7B_P', 'role', 'employee');
  perform pg_temp.ok('E01', 'Role target', 'Rol employee: Org A faol employee-rolli xodimlar', 'created/' || (select count(*) from public.employees e join public.profiles p on p.id = e.profile_id where e.org_id = pg_temp.c('OA')::uuid and p.role = 'employee' and p.status = 'active' and e.employment_status in ('active','on_leave')),
    split_part(pg_temp.jx(r), '/', 1) || '/' || split_part(pg_temp.jx(r), '/', 2));
  perform pg_temp.ok('I01', 'No duplicates', 'EMP 4 qoidaga mos: C1 va C2 bo''yicha bittadan qator', '1/1',
    (select count(*) from public.course_assignments where employee_id = pg_temp.emp('EMP') and course_id = 'T7B_C1') || '/' || (select count(*) from public.course_assignments where employee_id = pg_temp.emp('EMP') and course_id = 'T7B_C2'));
  perform pg_temp.ok('I02', 'No duplicates', 'Butun tashkilot: xodim × kurs bo''yicha faol takror 0', '0',
    (select count(*)::text from (select employee_id, course_id from public.course_assignments where status <> 'cancelled' group by 1, 2 having count(*) > 1) x));
  perform pg_temp.ok('J01', 'Preserve', 'EMP2: C1 completed saqlangan (completed_at o''zgarmagan)', 'completed/true',
    pg_temp.ca(pg_temp.emp('EMP2'), 'T7B_C1') || '/' || ((select completed_at::text from public.course_assignments where employee_id = pg_temp.emp('EMP2') and course_id = 'T7B_C1') = pg_temp.c('EMP2_C1'))::text);
  perform pg_temp.ok('K01', 'Preserve', 'EMP2: C2 in_progress saqlangan', 'in_progress', pg_temp.ca(pg_temp.emp('EMP2'), 'T7B_C2'));
end $$;

-- ===== F/G/M/N/O. Rad etilishi kerak bo'lgan holatlar =====
do $$ begin
  perform pg_temp.ok('G01', 'Path status', 'Arxivlangan yo''nalish', 'DENIED', pg_temp.ap('EDU', 'T7B_ARCH', 'employee', pg_temp.emp('EMP')::text));
  perform pg_temp.ok('G02', 'Path status', 'Draft yo''nalish', 'DENIED', pg_temp.ap('EDU', 'T7B_DRAFT', 'employee', pg_temp.emp('EMP')::text));
  perform pg_temp.ok('F01', 'Cross-org', 'Org A yo''nalishi → Org B xodimi', 'DENIED', pg_temp.ap('EDU', 'T7B_P', 'employee', pg_temp.emp('BEMP')::text));
  perform pg_temp.ok('F02', 'Cross-org', 'Org A yo''nalishi → Org B bo''limi', 'DENIED', pg_temp.ap('EDU', 'T7B_P', 'department', pg_temp.dep('OB', 'CARDIO')));
  perform pg_temp.ok('F03', 'Cross-org', 'Org A yo''nalishi → Org B lavozimi', 'DENIED', pg_temp.ap('EDU', 'T7B_P', 'position', (select id::text from public.positions where code = 'T7B_POSB')));
  perform pg_temp.ok('F04', 'Cross-org', 'Org A yo''nalishi → Org B mutaxassisligi', 'DENIED', pg_temp.ap('EDU', 'T7B_P', 'specialty', (select id::text from public.specialties where code = 'T7B_SPECB')));
  perform pg_temp.ok('O01', 'Cross-org', 'Org A EM → Org B yo''nalishi', 'DENIED', pg_temp.ap('EDU', 'T7B_PB', 'employee', pg_temp.emp('EMP')::text));
  perform pg_temp.ok('O02', 'Cross-org', 'Org B admin → Org A yo''nalishi', 'DENIED', pg_temp.ap('BADM', 'T7B_P', 'employee', pg_temp.emp('BEMP')::text));
  perform pg_temp.ok('F05', 'Cross-org', 'Org B admin: o''z yo''nalishi rol employee → faqat Org B xodimlari', 'created/1/1', pg_temp.jx(pg_temp.ap('BADM', 'T7B_PB', 'role', 'employee')));
  perform pg_temp.ok('F06', 'Cross-org', 'Org A xodimlariga Org B kursi tayinlanmagan', '0', (select count(*)::text from public.course_assignments where course_id = 'T7B_BC1' and org_id = pg_temp.c('OA')::uuid));
  perform pg_temp.ok('M01', 'Validation', 'Nishon bo''sh', 'DENIED', pg_temp.ap('EDU', 'T7B_P', 'employee', ''));
  perform pg_temp.ok('M02', 'Validation', 'Noma''lum nishon turi', 'DENIED', pg_temp.ap('EDU', 'T7B_P', 'branch', pg_temp.emp('EMP')::text));
  perform pg_temp.ok('M03', 'Validation', 'Noto''g''ri UUID', 'DENIED', pg_temp.ap('EDU', 'T7B_P', 'department', 'not-a-uuid'));
  perform pg_temp.ok('M04', 'Validation', 'Noma''lum rol', 'DENIED', pg_temp.ap('EDU', 'T7B_P', 'role', 'janitor'));
  perform pg_temp.ok('M05', 'Validation', 'O''tgan muddat', 'DENIED', pg_temp.ap('EDU', 'T7B_P', 'employee', pg_temp.emp('EMP2')::text, current_date - 1));
  perform pg_temp.ok('M06', 'Validation', 'Mavjud bo''lmagan yo''nalish', 'DENIED', pg_temp.rpc(pg_temp.u('EDU'), format('public.apply_learning_path(%L, ''employee'', %L)', gen_random_uuid(), pg_temp.emp('EMP'))));
  perform pg_temp.ok('N01', 'Inactive', 'Nofaol xodimga to''g''ridan-to''g''ri', 'DENIED', pg_temp.ap('EDU', 'T7B_P', 'employee', (select id::text from public.employees where employee_code = 'T7B_INACT')));
end $$;

-- ===== P. Rollar =====
do $$ begin
  perform pg_temp.ok('P01', 'Role matrix', 'Super Admin → ruxsat (EMP2 ga yangi qoida)', 'created/1/0', pg_temp.jx(pg_temp.ap('SA', 'T7B_P', 'employee', pg_temp.emp('EMP2')::text)));
  perform pg_temp.ok('P02', 'Role matrix', 'HR (learning_path.manage yo''q)', 'DENIED', pg_temp.ap('HR', 'T7B_P', 'employee', pg_temp.emp('EMP2')::text));
  perform pg_temp.ok('P03', 'Role matrix', 'Department Head (o''z bo''limi ham — ruxsat yo''q)', 'DENIED', pg_temp.ap('HEAD', 'T7B_P', 'department', pg_temp.dep('OA', 'CARDIO')));
  perform pg_temp.ok('P04', 'Role matrix', 'Instructor', 'DENIED', pg_temp.ap('INS', 'T7B_P', 'employee', pg_temp.emp('EMP2')::text));
  perform pg_temp.ok('P05', 'Role matrix', 'Medical Reviewer', 'DENIED', pg_temp.ap('REV', 'T7B_P', 'employee', pg_temp.emp('EMP2')::text));
  perform pg_temp.ok('P06', 'Role matrix', 'Employee', 'DENIED', pg_temp.ap('EMP', 'T7B_P', 'employee', pg_temp.emp('EMP')::text));
  perform pg_temp.ok('P07', 'Role matrix', 'anon: apply', 'DENIED', pg_temp.rpca(format('public.apply_learning_path(%L, ''employee'', %L)', pg_temp.pid('T7B_P'), pg_temp.emp('EMP'))));
  perform pg_temp.ok('P08', 'Role matrix', 'Employee: reapply / cancel', 'DENIED/DENIED',
    pg_temp.rpc(pg_temp.u('EMP'), format('public.reapply_learning_path_assignment(%L)', pg_temp.rule('T7B_P', pg_temp.emp('EMP')::text))) || '/' ||
    pg_temp.rpc(pg_temp.u('EMP'), format('public.cancel_learning_path_assignment(%L, ''sabab test'')', pg_temp.rule('T7B_P', pg_temp.emp('EMP')::text))));
  perform pg_temp.ok('P09', 'Role matrix', 'anon: reapply / cancel', 'DENIED/DENIED',
    pg_temp.rpca(format('public.reapply_learning_path_assignment(%L)', pg_temp.rule('T7B_P', pg_temp.emp('EMP')::text))) || '/' ||
    pg_temp.rpca(format('public.cancel_learning_path_assignment(%L, ''sabab'')', pg_temp.rule('T7B_P', pg_temp.emp('EMP')::text))));
  perform pg_temp.ok('P10', 'Role matrix', 'Org B admin: Org A qoidasini reapply / cancel', 'DENIED/DENIED',
    pg_temp.rpc(pg_temp.u('BADM'), format('public.reapply_learning_path_assignment(%L)', pg_temp.rule('T7B_P', pg_temp.emp('EMP')::text))) || '/' ||
    pg_temp.rpc(pg_temp.u('BADM'), format('public.cancel_learning_path_assignment(%L, ''sabab test'')', pg_temp.rule('T7B_P', pg_temp.emp('EMP')::text))));
end $$;

-- ===== S. RLS va to'g'ridan-to'g'ri yozuv =====
do $$ begin
  perform pg_temp.ok('S01', 'RLS', 'Employee: qoidalarni ko''rmaydi', '0', pg_temp.cnt(pg_temp.u('EMP'), 'select 1 from public.learning_path_assignments')::text);
  perform pg_temp.ok('S02', 'RLS', 'EM: Org A qoidalari ko''rinadi (6), Org B qoidasi yo''q', '6', pg_temp.cnt(pg_temp.u('EDU'), 'select 1 from public.learning_path_assignments')::text);
  perform pg_temp.ok('S03', 'RLS', 'Head (assignment.view): o''z tashkiloti qoidalari (6)', '6', pg_temp.cnt(pg_temp.u('HEAD'), 'select 1 from public.learning_path_assignments')::text);
  perform pg_temp.ok('S04', 'RLS', 'Org B admin: faqat o''z qoidasi (1)', '1', pg_temp.cnt(pg_temp.u('BADM'), 'select 1 from public.learning_path_assignments')::text);
  perform pg_temp.ok('S05', 'RLS', 'MR: ko''rmaydi', '0', pg_temp.cnt(pg_temp.u('REV'), 'select 1 from public.learning_path_assignments')::text);
  perform pg_temp.ok('S06', 'RLS', 'anon SELECT', 'DENIED', pg_temp.wa('select 1 from public.learning_path_assignments'));
  perform pg_temp.ok('S07', 'RLS', 'EM to''g''ridan-to''g''ri INSERT (faqat RPC orqali)', 'DENIED',
    pg_temp.w(pg_temp.u('EDU'), format('insert into public.learning_path_assignments (org_id, path_id, target_type, target_role) values (%L, %L, ''role'', ''hr'')', pg_temp.c('OA'), pg_temp.pid('T7B_P'))));
  perform pg_temp.ok('S08', 'RLS', 'EM to''g''ridan-to''g''ri UPDATE / DELETE', 'DENIED/DENIED',
    pg_temp.w(pg_temp.u('EDU'), 'update public.learning_path_assignments set due_date = current_date + 100') || '/' || pg_temp.w(pg_temp.u('EDU'), 'delete from public.learning_path_assignments'));
  perform pg_temp.ok('S09', 'Constraint', 'Ikki nishonli qoida (SQL darajasida ham) rad', 'DENIED',
    (select case when x then 'OK' else 'DENIED' end from (select pg_temp.sysok(format('insert into public.learning_path_assignments (org_id, path_id, target_type, employee_id, target_role) values (%L, %L, ''employee'', %L, ''hr'')', pg_temp.c('OA'), pg_temp.pid('T7B_P'), pg_temp.emp('EMP2')))) z(x)));
  perform pg_temp.ok('S10', 'Constraint', 'SQL: Org A qoidasi → Org B xodimi (guard trigger)', 'DENIED',
    (select case when x then 'OK' else 'DENIED' end from (select pg_temp.sysok(format('insert into public.learning_path_assignments (org_id, path_id, target_type, employee_id) values (%L, %L, ''employee'', %L)', pg_temp.c('OA'), pg_temp.pid('T7B_P'), pg_temp.emp('BEMP')))) z(x)));
end $$;

-- ===== X/R. Bekor qilish, reapply, arxiv =====
do $$ declare rd uuid := pg_temp.rule('T7B_P', pg_temp.dep('OA', 'CARDIO')); before_ca int; newe uuid; begin
  before_ca := (select count(*) from public.course_assignments where course_id like 'T7B_%');
  perform pg_temp.sys(format($q$insert into public.employees (org_id, employee_code, first_name, last_name, department_id, employment_status) values (%L, 'T7B_NEW', 'Yangi', 'Xodim', %L, 'active')$q$, pg_temp.c('OA'), pg_temp.dep('OA', 'CARDIO')));
  newe := (select id from public.employees where employee_code = 'T7B_NEW');
  perform pg_temp.ok('R01', 'Reapply', 'Yangi kelgan bo''lim xodimi: reapply → 2 kurs (boshqalarga takror yo''q)', '2',
    pg_temp.j(pg_temp.rpc(pg_temp.u('EDU'), format('public.reapply_learning_path_assignment(%L)', rd)), 'course_assignments_created'));
  perform pg_temp.ok('R02', 'Reapply', 'Reapply qayta → 0', '0', pg_temp.j(pg_temp.rpc(pg_temp.u('EDU'), format('public.reapply_learning_path_assignment(%L)', rd)), 'course_assignments_created'));
  perform pg_temp.ok('X01', 'Cancel', 'Sababsiz bekor qilish', 'DENIED', pg_temp.rpc(pg_temp.u('EDU'), format('public.cancel_learning_path_assignment(%L, '''')', rd)));
  before_ca := (select count(*) from public.course_assignments where course_id like 'T7B_%' and status <> 'cancelled');
  perform pg_temp.ok('X02', 'Cancel', 'Sabab bilan bekor qilish', 'true', pg_temp.j(pg_temp.rpc(pg_temp.u('EDU'), format('public.cancel_learning_path_assignment(%L, ''Bo''''lim dasturi o''''zgardi'')', rd)), 'changed'));
  perform pg_temp.ok('X03', 'Cancel', 'Yaratilgan kurs tayinlashlari o''zgarmagan (bekor qilinmagan)', before_ca::text, (select count(*)::text from public.course_assignments where course_id like 'T7B_%' and status <> 'cancelled'));
  perform pg_temp.ok('X04', 'Cancel', 'Qayta bekor qilish → changed false; audit cancelled 1', 'false/1',
    pg_temp.j(pg_temp.rpc(pg_temp.u('EDU'), format('public.cancel_learning_path_assignment(%L, ''yana bir marta'')', rd)), 'changed') || '/' ||
    (select count(*) from public.audit_logs where action = 'learning_path.assignment_cancelled' and entity_id = rd::text));
  perform pg_temp.ok('X05', 'Cancel', 'Bekor qilingan qoidani reapply', 'DENIED', pg_temp.rpc(pg_temp.u('EDU'), format('public.reapply_learning_path_assignment(%L)', rd)));
  perform pg_temp.ok('X06', 'Cancel', 'SQL: bekor qilinganni qayta faollashtirish (guard)', 'DENIED',
    (select case when x then 'OK' else 'DENIED' end from (select pg_temp.sysok(format('update public.learning_path_assignments set status = ''active'', cancelled_at = null where id = %L', rd))) z(x)));
  perform pg_temp.ok('X07', 'Cancel', 'SQL: DELETE (guard)', 'DENIED',
    (select case when x then 'OK' else 'DENIED' end from (select pg_temp.sysok(format('delete from public.learning_path_assignments where id = %L', rd))) z(x)));
  perform pg_temp.ok('X08', 'Cancel', 'Yangi qoida yaratish mumkin (eski bekor qilingan) — takror kurs yo''q', 'created/0',
    split_part(pg_temp.jx(pg_temp.ap('EDU', 'T7B_P', 'department', pg_temp.dep('OA', 'CARDIO'))), '/', 1) || '/' || split_part(pg_temp.jx(pg_temp.ap('EDU', 'T7B_P', 'department', pg_temp.dep('OA', 'CARDIO'))), '/', 3));
  perform pg_temp.sys($q$update public.learning_paths set status = 'archived' where code = 'T7B_P'$q$);
  perform pg_temp.ok('G03', 'Path status', 'Yo''nalish arxivlangach reapply', 'DENIED', pg_temp.rpc(pg_temp.u('EDU'), format('public.reapply_learning_path_assignment(%L)', pg_temp.rule('T7B_P', pg_temp.emp('EMP')::text))));
  perform pg_temp.ok('G04', 'Path status', 'Arxivdan keyin mavjud kurs tayinlashlari saqlangan', 'assigned/assigned', pg_temp.ca(pg_temp.emp('EMP'), 'T7B_C1') || '/' || pg_temp.ca(newe, 'T7B_C2'));
  perform pg_temp.sys($q$update public.learning_paths set status = 'published' where code = 'T7B_P'$q$);
end $$;

-- ===== Q. 007a bilan moslik =====
do $$ declare e uuid := pg_temp.emp('EMP'); begin
  perform pg_temp.sys(format($q$
    insert into public.course_modules (id, org_id, course_id, title, order_index, status) values ('T7B_M1', %1$L, 'T7B_C1', 'M', 1, 'published');
    insert into public.lessons (id, org_id, module_id, title, content_type, order_index, status) values ('71000000-0000-0000-0000-000000000001', %1$L, 'T7B_M1', 'L', 'text', 1, 'published');
  $q$, pg_temp.c('OA')));
  perform pg_temp.w(pg_temp.u('EMP'), format('insert into public.lesson_progress (org_id, lesson_id, employee_id, status) values (%L, ''71000000-0000-0000-0000-000000000001'', %L, ''completed'')', pg_temp.c('OA'), e));
  perform pg_temp.ok('Q01', '007a compat', '007b yaratgan tayinlash 007a orqali tugallandi + course.completed 1', 'completed/1',
    pg_temp.ca(e, 'T7B_C1') || '/' || (select count(*) from public.audit_logs where action = 'course.completed' and new_value ->> 'course_id' = 'T7B_C1'));
  perform pg_temp.ok('Q02', '007a compat', 'my_learning_progress 007b kurslarini ko''rsatadi', '1/1/100/completed',
    pg_temp.rpc(pg_temp.u('EMP'), '(select total_required_lessons || ''/'' || completed_required_lessons || ''/'' || progress_percent || ''/'' || computed_status from public.my_learning_progress() where course_id = ''T7B_C1'')'));
end $$;

-- ===== I. Invariantlar =====
do $$ begin
  perform pg_temp.ok('V01', 'Invariants', 'anon EXECUTE faqat verify_certificate', 'verify_certificate',
    (select string_agg(p.proname, ',') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'EXECUTE')));
  perform pg_temp.ok('V02', 'Invariants', 'Ichki funksiyalar authenticated uchun yopiq', '0',
    (select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('guard_lpa_007b', '_lpa_apply_rule_007b', '_lpa_can_manage_007b') and has_function_privilege('authenticated', p.oid, 'EXECUTE')));
  perform pg_temp.ok('V03', 'Invariants', 'Policy soni: oldingi + 0 (007b policy migratsiyada)', (pg_temp.c('BASE')::json ->> 'policies'), (select count(*)::text from pg_policies where schemaname = 'public'));
  perform pg_temp.ok('V04', 'Invariants', 'Urinishlar / sertifikatlar o''zgarmagan', 'true/true',
    ((select md5(coalesce(string_agg(to_jsonb(a)::text, '' order by a.id), '')) from public.exam_attempts a) = (pg_temp.c('BASE')::json ->> 'attempts_md5'))::text || '/' ||
    ((select md5(coalesce(string_agg(to_jsonb(c)::text, '' order by c.id), '')) from public.certificates c) = (pg_temp.c('BASE')::json ->> 'certs_md5'))::text);
  perform pg_temp.ok('V05', 'Invariants', 'CASCADE FK yo''q', '0', (select count(*)::text from pg_constraint where connamespace = 'public'::regnamespace and contype = 'f' and confdeltype = 'c'));
  perform pg_temp.ok('V06', 'Invariants', 'Jadvallar 45 (+learning_path_assignments)', '45', (select count(*)::text from pg_tables where schemaname = 'public'));
  perform pg_temp.ok('V07', 'Invariants', 'RLS yoqilgan; anon/authenticated yozish grant yo''q', 'true/0',
    (select relrowsecurity::text from pg_class where oid = 'public.learning_path_assignments'::regclass) || '/' ||
    (select count(*) from information_schema.role_table_grants where table_schema = 'public' and table_name = 'learning_path_assignments' and grantee in ('anon','authenticated') and privilege_type <> 'SELECT'));
end $$;

select line from (
  select 0 ord, 'SUMMARY 007b total ' || count(*) || ' / PASS ' || count(*) filter (where pass) || ' / FAIL ' || count(*) filter (where not pass) || coalesce(' :: ' || string_agg(id, ',' order by id) filter (where not pass), '') as line from t5
  union all select 1, id || ' ' || case when pass then 'PASS' else 'FAIL' end || ' [' || grp || '] ' || test || ' :: kutilgan=' || expected || ' :: natija=' || actual from t5) x order by ord, line;
select json_build_object('total', count(*), 'pass', count(*) filter (where pass), 'fail', count(*) filter (where not pass),
  'fail_ids', coalesce(json_agg(id || ' => ' || actual order by id) filter (where not pass), '[]'::json),
  'groups', (select json_object_agg(grp, n) from (select grp, count(*) || '/' || count(*) filter (where pass) n from t5 group by grp) g))::text as summary_007b from t5;
rollback;
