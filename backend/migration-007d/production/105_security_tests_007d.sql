-- PRODUCTION (007d): 007d test to'plami (staging/007d_02_tests.sql aynan), ROLLBACK
-- Vaqtinchalik test identifikatorlari (Org B + test foydalanuvchilar, @test.local, parolsiz, tizimga kira olmaydi) FAQAT shu tranzaksiya ichida
-- yaratiladi va oxiridagi ROLLBACK bilan butunlay yo'qoladi (54/55 usuli). Doimiy akkaunt yaratilmaydi.
begin;
do $$ begin
  if not exists (select 1 from public.schema_migrations where version = '007d') then raise exception 'TO''XTATILDI: 007d qo''llanmagan'; end if;
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

-- ---- 007d test to'plami (staging/007d_02_tests.sql, faqat ichki 'begin;' olib tashlangan) ----
-- MedAcademy · 007d in-app notifications test to'plami (lokal PGlite va staging uchun bir xil fayl).
-- Mavjud test akkauntlari (staging) bilan; yangi auth akkaunt yaratilmaydi. Hammasi BITTA tranzaksiyada, oxirida ROLLBACK.
-- Har bir foydalanuvchi so'rovi haqiqiy RLS / trigger / RPC orqali JWT claim'lari bilan bajariladi.
do $$ begin
  if not exists (select 1 from public.schema_migrations where version = '007d') then raise exception '007d qo''llanmagan'; end if;
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
create function pg_temp.j(t text, k text) returns text language sql as $$ select case when t like '{%' then t::jsonb ->> k else t end $$;
create function pg_temp.sk(code text) returns uuid language sql security definer as $$ select id from public.skills where code = $1 and org_id = pg_temp.c('OA')::uuid $$;
create function pg_temp.dep(org text, code text) returns text language sql security definer as $$ select id::text from public.departments where org_id = pg_temp.c(org)::uuid and code = $2 $$;
create function pg_temp.mk(p text, code text, name text, maxl int default 5) returns text language sql as $$
  select pg_temp.rpc(pg_temp.u(p), format('public.upsert_skill(null, %L, %L, null, ''Klinik'', null, %s)', code, name, maxl)) $$;
create function pg_temp.asm(p text, e uuid, code text, lvl int) returns text language sql as $$
  select pg_temp.rpc(pg_temp.u(p), format('public.record_skill_assessment(%L, %L, %s, ''izoh'')', e, pg_temp.sk(code), lvl)) $$;
create function pg_temp.req(p text, code text, typ text, tgt text, lvl int) returns text language sql as $$
  select pg_temp.rpc(pg_temp.u(p), format('public.set_competency_requirement(%L, %L, %L, %s)', pg_temp.sk(code), typ, tgt, lvl)) $$;
create function pg_temp.sum(p text, e uuid, code text) returns text language sql as $$
  select pg_temp.rpc(pg_temp.u(p), format('(select coalesce(string_agg(coalesce(required_level::text, ''-'') || ''/'' || coalesce(achieved_level::text, ''-'') || ''/'' || status, '',''), ''none'') from public.employee_competency_summary(%L) where skill_code = %L)', e, code)) $$;
-- ---------- 007d yordamchilari ----------
create function pg_temp.nc(p text, typ text) returns int language sql security definer as $$
  select count(*)::int from public.notifications where recipient_id = pg_temp.u(p) and notification_type = typ $$;
create function pg_temp.nall(p text) returns int language sql security definer as $$ select count(*)::int from public.notifications where recipient_id = pg_temp.u(p) $$;
create function pg_temp.nid(p text, typ text) returns uuid language sql security definer as $$
  select id from public.notifications where recipient_id = pg_temp.u(p) and notification_type = typ order by created_at, id limit 1 $$;
create function pg_temp.unread(p text) returns int language sql security definer as $$ select count(*)::int from public.notifications where recipient_id = pg_temp.u(p) and read_at is null $$;

do $$ declare oa uuid := pg_temp.c('OA')::uuid; emp uuid; dep uuid; v text; r1 uuid; begin
  perform pg_temp.logout();
  emp := pg_temp.emp('EMP'); select department_id into dep from public.employees where id = emp;
  insert into t5ctx values ('EMPID', emp::text), ('DEP', dep::text);
  insert into t5ctx select 'BASE', json_build_object(
    'attempts_md5', (select md5(coalesce(string_agg(to_jsonb(a)::text, '' order by a.id), '')) from public.exam_attempts a),
    'certs_md5', (select md5(coalesce(string_agg(to_jsonb(c)::text, '' order by c.id), '')) from public.certificates c),
    'audit_ntf', (select count(*) from public.audit_logs where entity like 'notification%'),
    'emp_n', (select count(*) from public.notifications where recipient_id = pg_temp.u('EMP')),
    'emp2_n', (select count(*) from public.notifications where recipient_id = pg_temp.u('EMP2')))::text;
  perform pg_temp.sys(format($q$
    insert into public.courses (id, org_id, title, domain, status) values ('T7D_C1', %1$L, 'T7D kurs bir', 'ethics', 'published'), ('T7D_C2', %1$L, 'T7D kurs ikki', 'ethics', 'published'),
      ('T7D_C3', %1$L, 'T7D kurs uch', 'ethics', 'published');
    insert into public.learning_paths (org_id, code, title, status) values (%1$L, 'T7D_P1', 'T7D yo''nalish', 'published');
    insert into public.learning_path_courses (org_id, path_id, course_id, order_index, is_required)
      select %1$L, id, 'T7D_C2', 1, true from public.learning_paths where code = 'T7D_P1' and org_id = %1$L;
    insert into public.employees (org_id, employee_code, first_name, last_name, department_id, employment_status) values (%1$L, 'T7D_NOPROF', 'Akkauntsiz', 'Xodim', %2$L, 'active');
  $q$, oa, dep));
end $$;

-- ---------- E: hodisalar ----------
do $$ declare oa uuid := pg_temp.c('OA')::uuid; emp uuid := pg_temp.u('EMPID'); v text; begin
  perform pg_temp.sys(format($q$ insert into public.course_assignments (org_id, course_id, employee_id, status) values (%L, 'T7D_C1', %L, 'assigned') $q$, oa, emp));
  perform pg_temp.ok('E01', 'Events', 'Kurs tayinlash → aynan 1 ta course_assigned', '1', pg_temp.nc('EMP', 'course_assigned')::text);
  perform pg_temp.ok('E02', 'Events', 'Bildirishnoma mazmuni: sarlavha + kurs nomi, tegishli obyekt', 'Yangi kurs tayinlandi/T7D kurs bir/course_assignment',
    (select title || '/' || body || '/' || related_entity_type from public.notifications where id = pg_temp.nid('EMP', 'course_assigned')));
  perform pg_temp.sys(format($q$ update public.course_assignments set status = 'completed', completed_at = now() where employee_id = %L and course_id = 'T7D_C1' $q$, emp));
  perform pg_temp.ok('E03', 'Events', 'Kurs yakunlandi → aynan 1 ta course_completed', '1', pg_temp.nc('EMP', 'course_completed')::text);
  perform pg_temp.sys(format($q$ update public.course_assignments set updated_at = now() where employee_id = %L and course_id = 'T7D_C1' $q$, emp));
  perform pg_temp.ok('E04', 'Events', 'Yakunlangan tayinlashni qayta yangilash yangi bildirishnoma yaratmaydi', '1/1', pg_temp.nc('EMP', 'course_completed') || '/' || pg_temp.nc('EMP', 'course_assigned'));
  perform pg_temp.sys(format($q$ insert into public.course_assignments (org_id, course_id, employee_id, status) values (%L, 'T7D_C3', %L, 'cancelled') $q$, oa, emp));
  perform pg_temp.ok('E05', 'Events', 'Bekor qilingan holatda yaratilgan tayinlash bildirishnoma bermaydi', '1', pg_temp.nc('EMP', 'course_assigned')::text);
  perform pg_temp.ok('E06', 'Events', 'Akkauntsiz xodimga tayinlash — xatosiz, bildirishnoma yo''q', 'true/0',
    pg_temp.sysok(format($q$ insert into public.course_assignments (org_id, course_id, employee_id, status) select %L, 'T7D_C1', id, 'assigned' from public.employees where employee_code = 'T7D_NOPROF' $q$, oa))::text || '/' ||
    (select count(*) from public.notifications where related_entity_id in (select a.id::text from public.course_assignments a join public.employees e on e.id = a.employee_id where e.employee_code = 'T7D_NOPROF'))::text);
  v := pg_temp.rpc(pg_temp.u('EDU'), format('public.apply_learning_path((select id from public.learning_paths where code = ''T7D_P1''), ''employee'', %L, null)', emp));
  insert into t5ctx values ('APPLY1', v);
  perform pg_temp.ok('E07', 'Events', 'Yo''nalish tayinlash → 1 ta learning_path_assigned + yo''nalish kursi uchun course_assigned', '1/2',
    pg_temp.nc('EMP', 'learning_path_assigned') || '/' || pg_temp.nc('EMP', 'course_assigned'));
  v := pg_temp.rpc(pg_temp.u('EDU'), format('public.reapply_learning_path_assignment((select id from public.learning_path_assignments where path_id = (select id from public.learning_paths where code = ''T7D_P1'') and employee_id = %L))', emp));
  perform pg_temp.ok('E08', 'Idempotency', '007b reapply — dublikat bildirishnoma yo''q', '1/2', pg_temp.nc('EMP', 'learning_path_assigned') || '/' || pg_temp.nc('EMP', 'course_assigned'));
  v := pg_temp.rpc(pg_temp.u('EDU'), format('public.apply_learning_path((select id from public.learning_paths where code = ''T7D_P1''), ''employee'', %L, null)', emp));
  perform pg_temp.ok('E09', 'Idempotency', 'Bir xil yo''nalishni qayta apply — dublikat yo''q', '1/2', pg_temp.nc('EMP', 'learning_path_assigned') || '/' || pg_temp.nc('EMP', 'course_assigned'));
end $$;

do $$ declare emp uuid := pg_temp.u('EMPID'); v text; begin
  v := pg_temp.mk('EDU', 'T7D_SK', 'T7D EKG talqini', 5);
  v := pg_temp.req('EDU', 'T7D_SK', 'department', pg_temp.c('DEP'), 3);
  insert into t5ctx values ('REQ', v);
  v := pg_temp.asm('HEAD', emp, 'T7D_SK', 2);
  perform pg_temp.ok('E10', 'Events', 'Baholash → 1 ta skill_assessment_created; talab bajarilmagan → competency_achieved yo''q', '1/0',
    pg_temp.nc('EMP', 'skill_assessment_created') || '/' || pg_temp.nc('EMP', 'competency_achieved'));
  v := pg_temp.asm('HEAD', emp, 'T7D_SK', 3);
  perform pg_temp.ok('E11', 'Events', 'Talab birinchi marta qoplandi → 1 ta competency_achieved', '2/1',
    pg_temp.nc('EMP', 'skill_assessment_created') || '/' || pg_temp.nc('EMP', 'competency_achieved'));
  v := pg_temp.asm('HEAD', emp, 'T7D_SK', 4);
  perform pg_temp.ok('E12', 'Events', 'Yuqoriroq baholash — yangi competency_achieved yo''q', '3/1',
    pg_temp.nc('EMP', 'skill_assessment_created') || '/' || pg_temp.nc('EMP', 'competency_achieved'));
  v := pg_temp.asm('HEAD', emp, 'T7D_SK', 1);
  v := pg_temp.asm('HEAD', emp, 'T7D_SK', 3);
  perform pg_temp.ok('E13', 'Events', 'Pasayib qayta qoplansa — yana 1 ta competency_achieved (yangi hodisa)', '5/2',
    pg_temp.nc('EMP', 'skill_assessment_created') || '/' || pg_temp.nc('EMP', 'competency_achieved'));
  perform pg_temp.ok('E14', 'Content', 'Baholash bildirishnomasida baholovchi izohi yo''q, faqat daraja', 'Ko''nikma baholandi/T7D EKG talqini: 4 / 5/false',
    (select title || '/' || body || '/' || (body like '%izoh%' or metadata::text like '%izoh%')::text from public.notifications
      where recipient_id = pg_temp.u('EMP') and notification_type = 'skill_assessment_created' order by (metadata->>'level')::int desc limit 1));
  perform pg_temp.sys(format($q$ insert into public.certificates (id, org_id, user_id, course_id, course_title, score) values
     ('T7DCERT1', %1$L, %2$L, 'T7D_C1', 'T7D kurs bir', 97), ('T7DCERT2', %1$L, %2$L, 'T7D_C2', 'T7D kurs ikki', 88) $q$, pg_temp.c('OA'), pg_temp.u('EMP')));
  perform pg_temp.sys($q$ update public.certificates set revoked = true where id = 'T7DCERT2' $q$);
  perform pg_temp.ok('E15', 'Events', 'Sertifikat berildi → har sertifikatga 1 ta certificate_issued', '2', pg_temp.nc('EMP', 'certificate_issued')::text);
  perform pg_temp.ok('E16', 'Content', 'Sertifikat bildirishnomasida ball yo''q (body / metadata)', 'false',
    (select bool_or(coalesce(body, '') ~ '(97|88)' or metadata ? 'score') ::text from public.notifications where recipient_id = pg_temp.u('EMP') and notification_type = 'certificate_issued'));
  perform pg_temp.sys(format($q$ insert into public.certificates (id, org_id, user_id, course_id, course_title, revoked) values ('T7DCERT3', %L, %L, 'T7D_C3', 'T7D kurs uch', true) $q$, pg_temp.c('OA'), pg_temp.u('EMP')));
  perform pg_temp.ok('E17', 'Events', 'Bekor qilingan holda yaratilgan sertifikat — bildirishnoma yo''q', '2', pg_temp.nc('EMP', 'certificate_issued')::text);
  perform pg_temp.ok('E18', 'Events', 'Boshqa xodimlarga (EMP2) hech narsa yozilmagan', (pg_temp.c('BASE')::json ->> 'emp2_n'), pg_temp.nall('EMP2')::text);
end $$;

-- ---------- R: o'qish ----------
do $$ declare emp_n int := pg_temp.nall('EMP'); v text; c1 text; begin
  insert into t5ctx values ('EMPN', emp_n::text);
  perform pg_temp.ok('R01', 'Read', 'Xodim o''z bildirishnomalarini SELECT orqali ko''radi', emp_n::text, pg_temp.cnt(pg_temp.u('EMP'), 'select id from public.notifications')::text);
  perform pg_temp.ok('R02', 'Read', 'my_notifications(100) — o''zinikilar, eng yangisi birinchi', least(emp_n, 100)::text,
    pg_temp.rpc(pg_temp.u('EMP'), '(select count(*) from public.my_notifications(100))'));
  perform pg_temp.ok('R03', 'Read', 'Boshqa xodim (EMP2) EMP bildirishnomalarini ko''rmaydi', '0',
    pg_temp.cnt(pg_temp.u('EMP2'), format('select id from public.notifications where recipient_id = %L', pg_temp.u('EMP')))::text);
  perform pg_temp.ok('R04', 'Read', 'Boshqa tashkilot (BEMP / BADM) — 0', '0/0',
    pg_temp.cnt(pg_temp.u('BEMP'), format('select id from public.notifications where recipient_id = %L', pg_temp.u('EMP'))) || '/' ||
    pg_temp.cnt(pg_temp.u('BADM'), format('select id from public.notifications where recipient_id = %L', pg_temp.u('EMP'))));
  perform pg_temp.ok('R05', 'Role matrix', 'SA / EDU / HR / INS / HEAD / REV — boshqaning bildirishnomasini ko''rmaydi', '0/0/0/0/0/0',
    pg_temp.cnt(pg_temp.u('SA'), format('select id from public.notifications where recipient_id = %L', pg_temp.u('EMP'))) || '/' ||
    pg_temp.cnt(pg_temp.u('EDU'), format('select id from public.notifications where recipient_id = %L', pg_temp.u('EMP'))) || '/' ||
    pg_temp.cnt(pg_temp.u('HR'), format('select id from public.notifications where recipient_id = %L', pg_temp.u('EMP'))) || '/' ||
    pg_temp.cnt(pg_temp.u('INS'), format('select id from public.notifications where recipient_id = %L', pg_temp.u('EMP'))) || '/' ||
    pg_temp.cnt(pg_temp.u('HEAD'), format('select id from public.notifications where recipient_id = %L', pg_temp.u('EMP'))) || '/' ||
    pg_temp.cnt(pg_temp.u('REV'), format('select id from public.notifications where recipient_id = %L', pg_temp.u('EMP'))));
  perform pg_temp.ok('R06', 'Read', 'Anonim: SELECT va RPC rad etiladi', '-1/DENIED/DENIED',
    (select case when pg_temp.wa('select 1 from public.notifications limit 1') = 'DENIED' then '-1' else 'OPEN' end) || '/' ||
    pg_temp.rpca('(select count(*) from public.my_notifications())') || '/' || pg_temp.rpca('public.unread_notification_count()'));
  perform pg_temp.ok('R07', 'Read', 'Sahifalash: 3 + keyingi 3, kesishma yo''q, tartib saqlangan', '3/3/0/true',
    pg_temp.rpc(pg_temp.u('EMP'), '(select count(*) from public.my_notifications(3))') || '/' ||
    pg_temp.rpc(pg_temp.u('EMP'), '(with p1 as (select * from public.my_notifications(3)), l as (select created_at, id from p1 order by created_at, id limit 1) select count(*) from public.my_notifications(3, (select created_at from l), (select id from l)))') || '/' ||
    pg_temp.rpc(pg_temp.u('EMP'), '(with p1 as (select * from public.my_notifications(3)), l as (select created_at, id from p1 order by created_at, id limit 1) select count(*) from public.my_notifications(3, (select created_at from l), (select id from l)) p2 where p2.id in (select id from p1))') || '/' ||
    pg_temp.rpc(pg_temp.u('EMP'), '(with p1 as (select * from public.my_notifications(3)), l as (select created_at, id from p1 order by created_at, id limit 1) select bool_and((p2.created_at, p2.id) < ((select created_at from l), (select id from l))) from public.my_notifications(3, (select created_at from l), (select id from l)) p2)'));
  perform pg_temp.ok('R08', 'Read', 'Limit 1000 → 100 gacha cheklanadi; noto''g''ri kursor rad', 'true/DENIED',
    pg_temp.rpc(pg_temp.u('EMP'), '(select count(*) <= 100 from public.my_notifications(1000))') || '/' ||
    pg_temp.rpc(pg_temp.u('EMP'), '(select count(*) from public.my_notifications(5, now(), null))'));
  perform pg_temp.ok('R09', 'Read', 'unread_notification_count = haqiqiy o''qilmaganlar soni', pg_temp.unread('EMP')::text, pg_temp.rpc(pg_temp.u('EMP'), 'public.unread_notification_count()'));
  perform pg_temp.ok('R10', 'Read', 'Bildirishnomasiz foydalanuvchi (BEMP): ro''yxat 0, son 0', '0/0',
    pg_temp.rpc(pg_temp.u('BEMP'), '(select count(*) from public.my_notifications())') || '/' || pg_temp.rpc(pg_temp.u('BEMP'), 'public.unread_notification_count()'));
end $$;

-- ---------- W: to'g'ridan-to'g'ri yozish ----------
do $$ declare nid uuid := pg_temp.nid('EMP', 'course_assigned'); begin
  perform pg_temp.ok('W01', 'Write', 'Xodim to''g''ridan-to''g''ri INSERT — rad', 'DENIED', pg_temp.w(pg_temp.u('EMP'), format(
    'insert into public.notifications (org_id, recipient_id, notification_type, title, event_key) values (%L, %L, ''course_assigned'', ''X'', ''fake:1'')', pg_temp.c('OA'), pg_temp.u('EMP'))));
  perform pg_temp.ok('W02', 'Write', 'SA / EDU to''g''ridan-to''g''ri INSERT (boshqaga) — rad', 'DENIED/DENIED',
    pg_temp.w(pg_temp.u('SA'), format('insert into public.notifications (org_id, recipient_id, notification_type, title, event_key) values (%L, %L, ''course_assigned'', ''X'', ''fake:2'')', pg_temp.c('OA'), pg_temp.u('EMP'))) || '/' ||
    pg_temp.w(pg_temp.u('EDU'), format('insert into public.notifications (org_id, recipient_id, notification_type, title, event_key) values (%L, %L, ''course_assigned'', ''X'', ''fake:3'')', pg_temp.c('OA'), pg_temp.u('EMP'))));
  perform pg_temp.ok('W03', 'Write', 'Xodim o''z bildirishnomasini to''g''ridan-to''g''ri UPDATE (read_at ham) — rad', 'DENIED/DENIED',
    pg_temp.w(pg_temp.u('EMP'), format('update public.notifications set read_at = now() where id = %L', nid)) || '/' ||
    pg_temp.w(pg_temp.u('EMP'), format('update public.notifications set title = ''X'' where id = %L', nid)));
  perform pg_temp.ok('W04', 'Write', 'Xodim DELETE — rad', 'DENIED', pg_temp.w(pg_temp.u('EMP'), format('delete from public.notifications where id = %L', nid)));
  perform pg_temp.ok('W05', 'Immutability', 'Server darajasida ham title / body / recipient / type / org o''zgarmaydi', 'false/false/false/false/false',
    pg_temp.sysok(format('update public.notifications set title = ''X'' where id = %L', nid))::text || '/' ||
    pg_temp.sysok(format('update public.notifications set body = ''X'' where id = %L', nid))::text || '/' ||
    pg_temp.sysok(format('update public.notifications set recipient_id = %L where id = %L', pg_temp.u('EMP2'), nid))::text || '/' ||
    pg_temp.sysok(format('update public.notifications set notification_type = ''course_completed'' where id = %L', nid))::text || '/' ||
    pg_temp.sysok(format('update public.notifications set org_id = %L where id = %L', pg_temp.c('OB'), nid))::text);
  perform pg_temp.ok('W06', 'Immutability', 'Server darajasida DELETE va TRUNCATE rad', 'false/false',
    pg_temp.sysok(format('delete from public.notifications where id = %L', nid))::text || '/' || pg_temp.sysok('truncate public.notifications')::text);
  perform pg_temp.ok('W07', 'Immutability', 'event_key / created_at / metadata o''zgarmaydi', 'false/false/false',
    pg_temp.sysok(format('update public.notifications set event_key = ''x:1'' where id = %L', nid))::text || '/' ||
    pg_temp.sysok(format('update public.notifications set created_at = now() - interval ''1 day'' where id = %L', nid))::text || '/' ||
    pg_temp.sysok(format('update public.notifications set metadata = ''{"a":1}'' where id = %L', nid))::text);
  perform pg_temp.ok('W08', 'Write', 'Anonim INSERT / UPDATE / DELETE — rad', 'DENIED/DENIED/DENIED',
    pg_temp.wa(format('insert into public.notifications (org_id, recipient_id, notification_type, title, event_key) values (%L, %L, ''course_assigned'', ''X'', ''fake:4'')', pg_temp.c('OA'), pg_temp.u('EMP'))) || '/' ||
    pg_temp.wa(format('update public.notifications set read_at = now() where id = %L', nid)) || '/' || pg_temp.wa(format('delete from public.notifications where id = %L', nid)));
end $$;

-- ---------- M: o'qildi belgisi ----------
do $$ declare nid uuid := pg_temp.nid('EMP', 'course_assigned'); u0 int := pg_temp.unread('EMP'); e2 int := pg_temp.unread('EMP2'); begin
  perform pg_temp.ok('M01', 'Read status', 'O''z bildirishnomasini o''qildi — changed true, o''qilmaganlar −1', 'true/' || (u0 - 1),
    pg_temp.j(pg_temp.rpc(pg_temp.u('EMP'), format('public.mark_notification_read(%L)', nid)), 'changed') || '/' || pg_temp.unread('EMP'));
  perform pg_temp.ok('M02', 'Read status', 'Takroran o''qildi — changed false (idempotent), read_at o''zgarmaydi', 'false/true',
    pg_temp.j(pg_temp.rpc(pg_temp.u('EMP'), format('public.mark_notification_read(%L)', nid)), 'changed') || '/' ||
    (select (read_at is not null)::text from public.notifications where id = nid));
  perform pg_temp.ok('M03', 'Read status', 'O''qilmagan deb qaytarish (p_read=false)', 'true/' || u0,
    pg_temp.j(pg_temp.rpc(pg_temp.u('EMP'), format('public.mark_notification_read(%L, false)', nid)), 'changed') || '/' || pg_temp.unread('EMP'));
  perform pg_temp.ok('M04', 'Read status', 'Boshqa xodim (EMP2) / boshqa org (BEMP) / SA — EMP bildirishnomasini belgilay olmaydi', 'DENIED/DENIED/DENIED',
    pg_temp.rpc(pg_temp.u('EMP2'), format('public.mark_notification_read(%L)', nid)) || '/' ||
    pg_temp.rpc(pg_temp.u('BEMP'), format('public.mark_notification_read(%L)', nid)) || '/' || pg_temp.rpc(pg_temp.u('SA'), format('public.mark_notification_read(%L)', nid)));
  perform pg_temp.ok('M05', 'Read status', 'Anonim mark_notification_read / mark_all — rad', 'DENIED/DENIED',
    pg_temp.rpca(format('public.mark_notification_read(%L)', nid)) || '/' || pg_temp.rpca('public.mark_all_notifications_read()'));
  perform pg_temp.ok('M06', 'Read status', 'mark_all_notifications_read — faqat o''ziniki, qolgan 0; EMP2 o''zgarmaydi', u0 || '/0/' || e2,
    pg_temp.rpc(pg_temp.u('EMP'), 'public.mark_all_notifications_read()') || '/' || pg_temp.unread('EMP') || '/' || pg_temp.unread('EMP2'));
  perform pg_temp.ok('M07', 'Read status', 'mark_all takroran — 0', '0', pg_temp.rpc(pg_temp.u('EMP'), 'public.mark_all_notifications_read()'));
  perform pg_temp.ok('M08', 'Read status', 'Mavjud bo''lmagan id — rad', 'DENIED', pg_temp.rpc(pg_temp.u('EMP'), 'public.mark_notification_read(gen_random_uuid())'));
end $$;

-- ---------- D: dublikat / poyga ----------
do $$ declare i int; base int := pg_temp.nall('EMP'); begin
  for i in 1..20 loop
    perform pg_temp.sysok(format('insert into public.notifications (org_id, recipient_id, notification_type, title, event_key) values (%L, %L, ''course_assigned'', ''Race'', ''race:T7D'') on conflict (recipient_id, event_key) do nothing', pg_temp.c('OA'), pg_temp.u('EMP')));
  end loop;
  perform pg_temp.ok('D01', 'Race', '20 ta takroriy urinish (bir hodisa + bir qabul qiluvchi) → aynan 1', '1',
    (select count(*)::text from public.notifications where recipient_id = pg_temp.u('EMP') and event_key = 'race:T7D'));
  perform pg_temp.sysok(format('insert into public.notifications (org_id, recipient_id, notification_type, title, event_key) select %L, %L, ''course_assigned'', ''Race2'', ''race2:T7D'' from generate_series(1, 15) on conflict (recipient_id, event_key) do nothing', pg_temp.c('OA'), pg_temp.u('EMP')));
  perform pg_temp.ok('D02', 'Race', 'Bitta statement ichida 15 ta bir xil hodisa → aynan 1', '1',
    (select count(*)::text from public.notifications where recipient_id = pg_temp.u('EMP') and event_key = 'race2:T7D'));
  perform pg_temp.ok('D03', 'Race', 'ON CONFLICT siz takroriy INSERT unique cheklov bilan rad etiladi', 'false',
    pg_temp.sysok(format('insert into public.notifications (org_id, recipient_id, notification_type, title, event_key) values (%L, %L, ''course_assigned'', ''Race'', ''race:T7D'')', pg_temp.c('OA'), pg_temp.u('EMP')))::text);
  perform pg_temp.sys(format($q$ insert into public.course_assignments (org_id, course_id, employee_id, status) select %L, 'T7D_C3', %L, 'assigned' from generate_series(1, 1) $q$, pg_temp.c('OA'), pg_temp.u('EMPID')));
  perform pg_temp.ok('D04', 'Race', 'Har manba qatoriga bitta bildirishnoma (unique recipient + event_key indeksi mavjud)', 'true',
    (select (count(*) = count(distinct (recipient_id, event_key)))::text from public.notifications));
  perform pg_temp.ok('D05', 'Race', 'Unique indeks notifications_recipient_event_uq mavjud', '1',
    (select count(*)::text from pg_constraint where conname = 'notifications_recipient_event_uq' and contype = 'u'));
end $$;

-- ---------- V: invariantlar ----------
do $$ begin
  perform pg_temp.ok('V01', 'Invariants', 'anon execute faqat verify_certificate', 'verify_certificate',
    (select string_agg(p.proname, ',') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'EXECUTE')));
  perform pg_temp.ok('V02', 'Invariants', 'Ichki 007d funksiyalari authenticated uchun yopiq; 4 RPC ochiq', '0/4',
    (select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like '%\_007d' and has_function_privilege('authenticated', p.oid, 'EXECUTE')) || '/' ||
    (select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('my_notifications', 'unread_notification_count', 'mark_notification_read', 'mark_all_notifications_read')
       and has_function_privilege('authenticated', p.oid, 'EXECUTE') and not has_function_privilege('anon', p.oid, 'EXECUTE')));
  perform pg_temp.ok('V03', 'Invariants', 'Urinishlar o''zgarmagan; mavjud sertifikatlar o''zgarmagan', 'true/true',
    ((select md5(coalesce(string_agg(to_jsonb(a)::text, '' order by a.id), '')) from public.exam_attempts a) = (pg_temp.c('BASE')::json ->> 'attempts_md5'))::text || '/' ||
    ((select md5(coalesce(string_agg(to_jsonb(c)::text, '' order by c.id), '')) from public.certificates c where c.id not like 'T7DCERT%') = (pg_temp.c('BASE')::json ->> 'certs_md5'))::text);
  perform pg_temp.ok('V04', 'Invariants', 'CASCADE FK yo''q', '0', (select count(*)::text from pg_constraint where connamespace = 'public'::regnamespace and contype = 'f' and confdeltype = 'c'));
  perform pg_temp.ok('V05', 'Invariants', 'Jadvallar 49 (+1); RLS yoqilgan; authenticated/anon yozish grant''lari 0; policy faqat SELECT', '49/true/0/SELECT',
    (select count(*) from pg_tables where schemaname = 'public') || '/' || (select relrowsecurity::text from pg_class where oid = 'public.notifications'::regclass) || '/' ||
    (select count(*) from information_schema.role_table_grants where table_schema = 'public' and table_name = 'notifications' and grantee in ('anon','authenticated') and privilege_type <> 'SELECT') || '/' ||
    (select string_agg(distinct cmd, ',') from pg_policies where schemaname = 'public' and tablename = 'notifications'));
  perform pg_temp.ok('V06', 'Audit', 'Bildirishnoma yaratish / o''qish audit yozuvini yaratmaydi', (pg_temp.c('BASE')::json ->> 'audit_ntf'),
    (select count(*)::text from public.audit_logs where entity like 'notification%'));
  perform pg_temp.ok('V07', 'Content', 'Hech bir bildirishnomada maxfiy so''zlar yo''q (parol / token / kalit / javob)', '0',
    (select count(*)::text from public.notifications where (coalesce(title, '') || ' ' || coalesce(body, '') || ' ' || metadata::text) ~* '(password|parol|token|service_role|api[_ ]?key|correct|javob kaliti|answer)'));
  perform pg_temp.ok('V08', 'Content', 'metadata kalitlari oq ro''yxatda', '0',
    (select count(*)::text from public.notifications n, jsonb_object_keys(n.metadata) k where k not in ('course_id', 'due_date', 'path_id', 'skill_id', 'level', 'max_level', 'required_level')));
  perform pg_temp.ok('V09', 'Invariants', 'Yangi permission qo''shilmagan (notification.*)', '0', (select count(*)::text from public.permissions where key like 'notification%'));
end $$;

select line from (
  select 0 ord, 'SUMMARY 007d total ' || count(*) || ' / PASS ' || count(*) filter (where pass) || ' / FAIL ' || count(*) filter (where not pass) || coalesce(' :: ' || string_agg(id, ',' order by id) filter (where not pass), '') as line from t5
  union all select 1, id || ' ' || case when pass then 'PASS' else 'FAIL' end || ' [' || grp || '] ' || test || ' :: kutilgan=' || expected || ' :: natija=' || actual from t5) x order by ord, line;
select json_build_object('total', count(*), 'pass', count(*) filter (where pass), 'fail', count(*) filter (where not pass),
  'fail_ids', coalesce(json_agg(id || ' => ' || actual order by id) filter (where not pass), '[]'::json),
  'groups', (select json_object_agg(grp, n) from (select grp, count(*) || '/' || count(*) filter (where pass) n from t5 group by grp) g))::text as summary_007d from t5;
rollback;
