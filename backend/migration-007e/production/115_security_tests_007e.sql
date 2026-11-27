-- PRODUCTION (007e): 007e test to'plami (staging/007e_02_tests.sql aynan), ROLLBACK
-- Vaqtinchalik test identifikatorlari (Org B + test foydalanuvchilar, @test.local, parolsiz, tizimga kira olmaydi) FAQAT shu tranzaksiya ichida
-- yaratiladi va oxiridagi ROLLBACK bilan butunlay yo'qoladi (54/55 usuli). Doimiy akkaunt yaratilmaydi.
begin;
do $$ begin
  if not exists (select 1 from public.schema_migrations where version = '007e') then raise exception 'TO''XTATILDI: 007e qo''llanmagan'; end if;
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

-- ---- 007e test to'plami (staging/007e_02_tests.sql, faqat ichki 'begin;' olib tashlangan) ----
-- MedAcademy · 007e compliance + competency matrix test to'plami (lokal PGlite va staging uchun bir xil fayl).
-- Mavjud test akkauntlari (staging) bilan; yangi auth akkaunt yaratilmaydi. Hammasi BITTA tranzaksiyada, oxirida ROLLBACK.
-- Har bir foydalanuvchi so'rovi haqiqiy RLS / trigger / RPC orqali JWT claim'lari bilan bajariladi.
do $$ begin
  if not exists (select 1 from public.schema_migrations where version = '007e') then raise exception '007e qo''llanmagan'; end if;
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
-- ---------- 007e yordamchilari ----------
create function pg_temp.dn(p text, lesson uuid) returns text language sql as $$
  select pg_temp.w(pg_temp.u(p), format('insert into public.lesson_progress (org_id, lesson_id, employee_id, status) values (%L, %L, %L, ''completed'') on conflict (lesson_id, employee_id) do update set status = ''completed''',
    (select org_id from public.lessons where id = lesson), lesson, pg_temp.emp(p))) $$;
create function pg_temp.etc(p text, e text) returns text language sql as $$   -- trening summary: req/done/inprog/notst/ovd/canc/pct
  select case when r like '{%' then (select x ->> 'total_required' || '/' || (x ->> 'completed') || '/' || (x ->> 'in_progress') || '/' || (x ->> 'not_started') || '/' ||
    (x ->> 'overdue') || '/' || (x ->> 'cancelled') || '/' || (x ->> 'compliance_percent') from (select r::jsonb -> 'summary' x) z) else r end
  from (select pg_temp.rpc(pg_temp.u(p), format('public.employee_training_compliance(%s)', coalesce(quote_literal(e), 'null'))) r) q $$;
create function pg_temp.ecm(p text, e text) returns text language sql as $$   -- kompetensiya summary: req/ach/gap/nas
  select case when r like '{%' then (select x ->> 'required' || '/' || (x ->> 'achieved') || '/' || (x ->> 'not_achieved') || '/' || (x ->> 'not_assessed')
    from (select r::jsonb -> 'summary' x) z) else r end
  from (select pg_temp.rpc(pg_temp.u(p), format('public.employee_competency_matrix(%s)', coalesce(quote_literal(e), 'null'))) r) q $$;
create function pg_temp.dcm(p text, d text) returns text language sql as $$
  select pg_temp.rpc(pg_temp.u(p), format('public.department_compliance_matrix(%s)', coalesce(quote_literal(d), 'null'))) $$;
create function pg_temp.side() returns text language sql security definer as $$
  select (select count(*) from public.notifications) || '/' || (select count(*) from public.audit_logs) || '/' || (select count(*) from public.course_assignments) || '/' ||
         (select count(*) from public.skill_assessments) || '/' || (select count(*) from public.competency_requirements) || '/' || (select count(*) from public.learning_path_assignments) $$;

do $$ declare oa uuid := pg_temp.c('OA')::uuid; ob uuid := pg_temp.c('OB')::uuid; emp uuid; dep uuid; pos uuid; begin
  perform pg_temp.logout();
  emp := pg_temp.emp('EMP'); select department_id, position_id into dep, pos from public.employees where id = emp;
  insert into t5ctx values ('EMPID', emp::text), ('EMP2ID', pg_temp.emp('EMP2')::text), ('BEMPID', pg_temp.emp('BEMP')::text), ('DEP', dep::text), ('POS', pos::text),
    ('DEP2', (select department_id::text from public.employees where id = pg_temp.emp('EMP2')));
  insert into t5ctx select 'BASE', json_build_object(
    'attempts_md5', (select md5(coalesce(string_agg(to_jsonb(a)::text, '' order by a.id), '')) from public.exam_attempts a),
    'certs_md5', (select md5(coalesce(string_agg(to_jsonb(c)::text, '' order by c.id), '')) from public.certificates c))::text;
  perform pg_temp.sys(format($q$
    insert into public.courses (id, org_id, title, domain, status) values ('T7E_C', %1$L, 'T7E asosiy', 'ethics', 'published'), ('T7E_ZERO', %1$L, 'T7E ixtiyoriy', 'ethics', 'published'),
      ('T7E_D', %1$L, 'T7E bir darslik', 'ethics', 'published'), ('T7E_E', %1$L, 'T7E muddati o''tgan', 'ethics', 'published'), ('T7E_F', %1$L, 'T7E bekor', 'ethics', 'published'),
      ('T7E_G', %1$L, 'T7E kelajak', 'ethics', 'published'), ('T7E_B', %2$L, 'T7E Org B', 'ethics', 'published');
    insert into public.course_modules (id, org_id, course_id, title, order_index, status) values
      ('T7E_M1', %1$L, 'T7E_C', 'M1', 1, 'published'), ('T7E_M2', %1$L, 'T7E_C', 'M2 draft', 2, 'draft'), ('T7E_MZ', %1$L, 'T7E_ZERO', 'MZ', 1, 'published'),
      ('T7E_MD', %1$L, 'T7E_D', 'MD', 1, 'published'), ('T7E_ME', %1$L, 'T7E_E', 'ME', 1, 'published'), ('T7E_MB', %2$L, 'T7E_B', 'MB', 1, 'published');
    insert into public.lessons (id, org_id, module_id, title, content_type, order_index, status, is_required) values
      ('7e000000-0000-0000-0000-000000000001', %1$L, 'T7E_M1', 'L1', 'text', 1, 'published', true),
      ('7e000000-0000-0000-0000-000000000002', %1$L, 'T7E_M1', 'L2', 'text', 2, 'published', true),
      ('7e000000-0000-0000-0000-000000000003', %1$L, 'T7E_M1', 'L3', 'text', 3, 'published', true),
      ('7e000000-0000-0000-0000-000000000004', %1$L, 'T7E_M1', 'Ixtiyoriy', 'text', 4, 'published', false),
      ('7e000000-0000-0000-0000-000000000005', %1$L, 'T7E_M1', 'Draft dars', 'text', 5, 'draft', true),
      ('7e000000-0000-0000-0000-000000000006', %1$L, 'T7E_M2', 'Draft modul darsi', 'text', 1, 'published', true),
      ('7e000000-0000-0000-0000-000000000011', %1$L, 'T7E_MZ', 'Faqat ixtiyoriy', 'text', 1, 'published', false),
      ('7e000000-0000-0000-0000-000000000021', %1$L, 'T7E_MD', 'D1', 'text', 1, 'published', true),
      ('7e000000-0000-0000-0000-000000000031', %1$L, 'T7E_ME', 'E1', 'text', 1, 'published', true),
      ('7e000000-0000-0000-0000-000000000041', %2$L, 'T7E_MB', 'B1', 'text', 1, 'published', true);
    insert into public.course_assignments (org_id, course_id, employee_id, due_date, status) values
      (%1$L, 'T7E_C', %3$L, current_date + 30, 'assigned'), (%1$L, 'T7E_ZERO', %3$L, null, 'assigned'), (%1$L, 'T7E_D', %3$L, current_date + 5, 'assigned'),
      (%1$L, 'T7E_E', %3$L, current_date - 1, 'assigned'), (%1$L, 'T7E_F', %3$L, current_date + 5, 'cancelled'), (%1$L, 'T7E_G', %3$L, current_date + 10, 'assigned'),
      (%1$L, 'T7E_C', %4$L, current_date - 3, 'assigned'),
      (%2$L, 'T7E_B', %5$L, null, 'assigned');
  $q$, oa, ob, emp, pg_temp.u('EMP2ID'), pg_temp.u('BEMPID')));
end $$;

-- ---------- T: trening compliance semantikasi ----------
do $$ declare v text; s0 text; begin
  insert into t5ctx values ('E0', pg_temp.etc('EMP', null));
  perform pg_temp.ok('T01', 'Training', 'Boshlang''ich: 5 faol (bekor qilingan alohida), hech biri tugallanmagan', '5/0/0/4/1/1/0.0',
    pg_temp.etc('EMP', null));
  v := pg_temp.dn('EMP', '7e000000-0000-0000-0000-000000000001');
  perform pg_temp.ok('T02', 'Training', 'Majburiy darsning 1/3 tugallandi → in_progress', '5/0/1/3/1/1/0.0', pg_temp.etc('EMP', null));
  v := pg_temp.dn('EMP', '7e000000-0000-0000-0000-000000000021');
  perform pg_temp.ok('T03', 'Training', 'Yagona majburiy dars tugallandi → completed (007a trigger), compliance 20%', '5/1/1/2/1/1/20.0', pg_temp.etc('EMP', null));
  v := pg_temp.dn('EMP', '7e000000-0000-0000-0000-000000000004');
  perform pg_temp.ok('T04', 'Training', 'Ixtiyoriy dars maxrajga kirmaydi (holat o''zgarmaydi)', '5/1/1/2/1/1/20.0', pg_temp.etc('EMP', null));
  perform pg_temp.ok('T05', 'Training', 'Draft dars / draft modul majburiy maxrajga kirmaydi (T7E_C: 3 dars)', '3/1/33/in_progress',
    (select x ->> 'total_required_lessons' || '/' || (x ->> 'completed_required_lessons') || '/' || (x ->> 'progress_percent') || '/' || (x ->> 'status')
     from jsonb_array_elements(pg_temp.rpc(pg_temp.u('EMP'), 'public.employee_training_compliance()')::jsonb -> 'courses') x where x ->> 'course_id' = 'T7E_C'));
  perform pg_temp.ok('T06', 'Training', 'Faqat ixtiyoriy darsli kurs (0 majburiy) — completed emas; muddat NULL → overdue emas', '0/not_started',
    (select x ->> 'total_required_lessons' || '/' || (x ->> 'status') from jsonb_array_elements(pg_temp.rpc(pg_temp.u('EMP'), 'public.employee_training_compliance()')::jsonb -> 'courses') x where x ->> 'course_id' = 'T7E_ZERO'));
  perform pg_temp.ok('T07', 'Training', 'Muddati o''tgan → overdue; kelajak muddat → not_started; bekor → cancelled', 'overdue/cancelled/not_started',
    (select string_agg(x ->> 'status', '/' order by x ->> 'course_id') from jsonb_array_elements(pg_temp.rpc(pg_temp.u('EMP'), 'public.employee_training_compliance()')::jsonb -> 'courses') x
      where x ->> 'course_id' in ('T7E_E', 'T7E_G', 'T7E_F') ) );
  perform pg_temp.ok('T08', 'Parity 007a', 'Har bir tayinlash holati / progress 007a my_learning_progress bilan aynan bir xil', '0',
    pg_temp.rpc(pg_temp.u('EMP'), '(select count(*) from ((select x ->> ''assignment_id'' a, x ->> ''status'' s, (x ->> ''progress_percent'')::int p, (x ->> ''total_required_lessons'')::int t from jsonb_array_elements(public.employee_training_compliance() -> ''courses'') x)
        except (select assignment_id::text, computed_status, progress_percent, total_required_lessons from public.my_learning_progress())) d) + (select count(*) from ((select assignment_id::text, computed_status, progress_percent, total_required_lessons from public.my_learning_progress())
        except (select x ->> ''assignment_id'', x ->> ''status'', (x ->> ''progress_percent'')::int, (x ->> ''total_required_lessons'')::int from jsonb_array_elements(public.employee_training_compliance() -> ''courses'') x)) d2)'));
  v := pg_temp.dn('EMP', '7e000000-0000-0000-0000-000000000002'); v := pg_temp.dn('EMP', '7e000000-0000-0000-0000-000000000003');
  v := pg_temp.dn('EMP', '7e000000-0000-0000-0000-000000000031');
  perform pg_temp.ok('T09', 'Training', 'Barcha majburiy darslar (overdue kurs ham) tugallansa → completed; 60%', '5/3/0/2/0/1/60.0', pg_temp.etc('EMP', null));
  perform pg_temp.ok('T10', 'Parity 007a', 'Kurs bo''yicha sonlar course_progress_summary (EDU) bilan bir xil (T7E_C: completed 1, overdue 1)', '1/1/0',
    (select (pg_temp.rpc(pg_temp.u('EDU'), 'public.course_progress_summary(''T7E_C'')')::jsonb ->> 'completed_count') || '/' ||
            (pg_temp.rpc(pg_temp.u('EDU'), 'public.course_progress_summary(''T7E_C'')')::jsonb ->> 'overdue_count') || '/' ||
            (pg_temp.rpc(pg_temp.u('EDU'), 'public.course_progress_summary(''T7E_C'')')::jsonb ->> 'in_progress_count')));
  perform pg_temp.ok('T11', 'Training', 'Tayinlashsiz xodim (INS) — bo''sh: 0 / compliance 0 (nolga bo''lish yo''q)', '0/0/0/0/0/0/0.0', pg_temp.etc('INS', null));
  perform pg_temp.ok('T12', 'Training', 'Boshqa xodim (EMP2): overdue kurs; o''z ma''lumoti', '1/0/0/0/1/0/0.0', pg_temp.etc('EMP2', null));
  perform pg_temp.ok('T13', 'Training', 'Kurs arxivlansa ham tayinlash hisobda qoladi (007a bilan bir xil: kurs statusi filtrlanmaydi)', 'true',
    (pg_temp.sysok($q$ update public.courses set status = 'archived' where id = 'T7E_G' $q$) and pg_temp.etc('EMP', null) = '5/3/0/2/0/1/60.0')::text);
end $$;

-- ---------- L: learning path orqali ----------
do $$ declare v text; begin
  perform pg_temp.sys(format($q$
    insert into public.courses (id, org_id, title, domain, status) values ('T7E_LP1', %1$L, 'T7E yo''nalish kursi', 'ethics', 'published');
    insert into public.learning_paths (org_id, code, title, status) values (%1$L, 'T7E_P', 'T7E yo''nalish', 'published');
    insert into public.learning_path_courses (org_id, path_id, course_id, order_index, is_required) select %1$L, id, 'T7E_LP1', 1, true from public.learning_paths where code = 'T7E_P';
  $q$, pg_temp.c('OA')));
  insert into t5ctx values ('SIDE0', pg_temp.side());
  v := pg_temp.rpc(pg_temp.u('EDU'), format('public.apply_learning_path((select id from public.learning_paths where code = ''T7E_P''), ''employee'', %L, current_date + 7)', pg_temp.u('EMPID')));
  perform pg_temp.ok('L01', 'Learning path', 'Yo''nalish orqali kelgan kurs compliance''ga qo''shiladi (007b course_assignment)', '6/3/0/3/0/1/50.0', pg_temp.etc('EMP', null));
  v := pg_temp.rpc(pg_temp.u('EDU'), format('public.reapply_learning_path_assignment((select id from public.learning_path_assignments where path_id = (select id from public.learning_paths where code = ''T7E_P'') and employee_id = %L))', pg_temp.u('EMPID')));
  v := pg_temp.rpc(pg_temp.u('EDU'), format('public.apply_learning_path((select id from public.learning_paths where code = ''T7E_P''), ''employee'', %L, current_date + 7)', pg_temp.u('EMPID')));
  perform pg_temp.ok('L02', 'Learning path', 'Reapply / takroriy apply — dublikat yo''q, compliance o''zgarmaydi', '6/3/0/3/0/1/50.0', pg_temp.etc('EMP', null));
end $$;

-- ---------- C: kompetensiya matritsasi ----------
do $$ declare v text; e uuid := pg_temp.u('EMPID'); begin
  v := pg_temp.mk('EDU', 'T7E_SK1', 'T7E EKG', 5); v := pg_temp.mk('EDU', 'T7E_SK2', 'T7E Reanimatsiya', 5);
  v := pg_temp.mk('EDU', 'T7E_SK3', 'T7E Mutaxassislik', 5); v := pg_temp.mk('EDU', 'T7E_SK4', 'T7E Arxiv', 5);
  perform pg_temp.ok('C01', 'Competency', 'Talablarsiz — matritsa bo''sh (0/0/0/0)', '0/0/0/0', pg_temp.ecm('EMP', null));
  v := pg_temp.req('EDU', 'T7E_SK1', 'department', pg_temp.c('DEP'), 3);
  v := pg_temp.req('EDU', 'T7E_SK1', 'position', pg_temp.c('POS'), 4);
  v := pg_temp.req('EDU', 'T7E_SK2', 'role', 'employee', 2);
  v := pg_temp.req('EDU', 'T7E_SK3', 'specialty', (select id::text from public.specialties where org_id = pg_temp.c('OA')::uuid limit 1), 2);
  v := pg_temp.req('EDU', 'T7E_SK4', 'department', pg_temp.c('DEP'), 1);
  v := pg_temp.rpc(pg_temp.u('EDU'), format('public.archive_skill(%L, ''T7E test'')', pg_temp.sk('T7E_SK4')));
  perform pg_temp.ok('C02', 'Competency', 'Bir skill ikki nishon orqali → bitta qator, required = max (4), 2 manba; arxiv skill chiqmaydi; mos kelmagan mutaxassislik chiqmaydi', '2/4/2',
    (select (r -> 'summary' ->> 'required') || '/' || (select x ->> 'required_level' || '/' || jsonb_array_length(x -> 'requirements') from jsonb_array_elements(r -> 'competencies') x where x ->> 'skill_code' = 'T7E_SK1')
     from (select pg_temp.rpc(pg_temp.u('EMP'), 'public.employee_competency_matrix()')::jsonb r) z));
  perform pg_temp.ok('C03', 'Competency', 'Baholashsiz → not_assessed (2 ta)', '2/0/0/2', pg_temp.ecm('EMP', null));
  v := pg_temp.asm('HEAD', e, 'T7E_SK1', 5);
  perform pg_temp.ok('C04', 'Competency', '5 ≥ 4 → achieved', '2/1/0/1', pg_temp.ecm('EMP', null));
  v := pg_temp.asm('HEAD', e, 'T7E_SK1', 3);
  perform pg_temp.ok('C05', 'Competency', 'So''nggi baholash pastroq (3 < 4) → not_achieved (gap), current 3 (oldingi 5 ustidan yozilmaydi — so''nggisi hal qiladi)', '2/0/1/1/3',
    pg_temp.ecm('EMP', null) || '/' || (select x ->> 'current_level' from jsonb_array_elements(pg_temp.rpc(pg_temp.u('EMP'), 'public.employee_competency_matrix()')::jsonb -> 'competencies') x where x ->> 'skill_code' = 'T7E_SK1'));
  v := pg_temp.asm('HEAD', e, 'T7E_SK2', 2);
  perform pg_temp.ok('C06', 'Parity 007c', 'Har skill bo''yicha required / current / status 007c employee_competency_summary bilan aynan bir xil', '0',
    pg_temp.rpc(pg_temp.u('EMP'), '(select count(*) from ((select x ->> ''skill_id'' s, (x ->> ''required_level'')::int r, (x ->> ''current_level'')::int c, x ->> ''status'' st from jsonb_array_elements(public.employee_competency_matrix() -> ''competencies'') x)
       except (select skill_id::text, required_level, achieved_level, status from public.employee_competency_summary() where status <> ''not_required'')) d) + (select count(*) from ((select skill_id::text, required_level, achieved_level, status from public.employee_competency_summary() where status <> ''not_required'')
       except (select x ->> ''skill_id'', (x ->> ''required_level'')::int, (x ->> ''current_level'')::int, x ->> ''status'' from jsonb_array_elements(public.employee_competency_matrix() -> ''competencies'') x)) d2)'));
  perform pg_temp.ok('C07', 'Competency', 'Bildirishnoma yaratilmagan gap uchun (competency_gap turi yo''q)', '0',
    (select count(*)::text from public.notifications where notification_type not in ('course_assigned','course_completed','learning_path_assigned','skill_assessment_created','competency_achieved','certificate_issued')));
  perform pg_temp.ok('C08', 'Competency', 'Matritsada baholovchi izohi / assessor_id yo''q', 'false',
    (pg_temp.rpc(pg_temp.u('EMP'), 'public.employee_competency_matrix()') ~ '(izoh|assessor|notes)')::text);
end $$;

-- ---------- S: qamrov / rol matritsasi ----------
do $$ declare e text := pg_temp.c('EMPID'); e2 text := pg_temp.c('EMP2ID'); be text := pg_temp.c('BEMPID'); begin
  perform pg_temp.ok('S01', 'Scope', 'Xodim: o''zi OK; boshqa xodim (EMP2) — trening / kompetensiya rad', 'OK/DENIED/DENIED',
    (case when pg_temp.etc('EMP', e) like '%/%' then 'OK' else 'X' end) || '/' || pg_temp.etc('EMP', e2) || '/' || pg_temp.ecm('EMP', e2));
  perform pg_temp.ok('S02', 'Scope', 'Department Head: o''z bo''limi OK; boshqa bo''lim / boshqa org rad (ikkala RPC)', 'OK/OK/DENIED/DENIED/DENIED/DENIED',
    (case when pg_temp.etc('HEAD', e) like '%/%' then 'OK' else 'X' end) || '/' || (case when pg_temp.ecm('HEAD', e) like '%/%' then 'OK' else 'X' end) || '/' ||
    pg_temp.etc('HEAD', e2) || '/' || pg_temp.ecm('HEAD', e2) || '/' || pg_temp.etc('HEAD', be) || '/' || pg_temp.ecm('HEAD', be));
  perform pg_temp.ok('S03', 'Scope', 'HR / EM / SA: tashkilot ichida OK (trening + kompetensiya)', 'OK/OK/OK/OK/OK/OK',
    (select string_agg(case when x like '%/%' then 'OK' else x end, '/' order by o) from (values (1, pg_temp.etc('HR', e2)), (2, pg_temp.ecm('HR', e2)), (3, pg_temp.etc('EDU', e2)),
      (4, pg_temp.ecm('EDU', e2)), (5, pg_temp.etc('SA', e2)), (6, pg_temp.ecm('SA', e2))) v(o, x)));
  perform pg_temp.ok('S04', 'Scope', 'HR / EM / SA: boshqa tashkilot xodimi — rad', 'DENIED/DENIED/DENIED/DENIED/DENIED/DENIED',
    pg_temp.etc('HR', be) || '/' || pg_temp.ecm('HR', be) || '/' || pg_temp.etc('EDU', be) || '/' || pg_temp.ecm('EDU', be) || '/' || pg_temp.etc('SA', be) || '/' || pg_temp.ecm('SA', be));
  perform pg_temp.ok('S05', 'Scope', 'Instructor / Medical Reviewer: boshqa xodim — rad; o''zi — OK', 'DENIED/DENIED/DENIED/DENIED/OK/OK',
    pg_temp.etc('INS', e) || '/' || pg_temp.ecm('INS', e) || '/' || pg_temp.etc('REV', e) || '/' || pg_temp.ecm('REV', e) || '/' ||
    (case when pg_temp.etc('INS', null) like '%/%' then 'OK' else 'X' end) || '/' || (case when pg_temp.etc('REV', null) like '%/%' then 'OK' else pg_temp.etc('REV', null) end));
  perform pg_temp.ok('S06', 'Scope', 'Org B admin (BADM) Org A xodimi — rad; Org B xodimi o''zini ko''radi', 'DENIED/DENIED/1/0/0/1/0/0/0.0',
    pg_temp.etc('BADM', e) || '/' || pg_temp.ecm('BADM', e) || '/' || pg_temp.etc('BEMP', null));
  perform pg_temp.ok('S07', 'Scope', 'Anonim: 3 RPC — rad', 'DENIED/DENIED/DENIED',
    pg_temp.rpca('public.employee_training_compliance()') || '/' || pg_temp.rpca('public.employee_competency_matrix()') || '/' || pg_temp.rpca('public.department_compliance_matrix()'));
  perform pg_temp.ok('S08', 'Scope', 'Mavjud bo''lmagan xodim ID — rad (ma''lumot oshkor qilinmaydi)', 'DENIED/DENIED',
    pg_temp.etc('HR', gen_random_uuid()::text) || '/' || pg_temp.ecm('HR', gen_random_uuid()::text));
  perform pg_temp.ok('S09', 'Scope', 'Bo''lim almashsa qamrov ham almashadi: EMP2 CARDIO ga o''tkazilsa HEAD ko''radi', 'true/OK',
    pg_temp.sysok(format('update public.employees set department_id = %L where id = %L', pg_temp.c('DEP'), e2))::text || '/' || (case when pg_temp.etc('HEAD', e2) like '%/%' then 'OK' else pg_temp.etc('HEAD', e2) end));
  perform pg_temp.sysok(format('update public.employees set department_id = %L where id = %L', pg_temp.c('DEP2'), e2));
  perform pg_temp.ok('S10', 'Scope', 'Qaytarilgandan keyin HEAD yana rad etiladi', 'DENIED', pg_temp.etc('HEAD', e2));
  perform pg_temp.ok('S11', 'Scope', 'Lavozim almashsa position talabi o''zgaradi (SK1 required 4 → 3)', 'true/3',
    pg_temp.sysok(format('update public.employees set position_id = null where id = %L', e))::text || '/' ||
    (select x ->> 'required_level' from jsonb_array_elements(pg_temp.rpc(pg_temp.u('EMP'), 'public.employee_competency_matrix()')::jsonb -> 'competencies') x where x ->> 'skill_code' = 'T7E_SK1'));
  perform pg_temp.sysok(format('update public.employees set position_id = %L where id = %L', pg_temp.c('POS'), e));
end $$;

-- ---------- D: bo'lim / tashkilot matritsasi ----------
do $$ declare n0 int; begin
  perform pg_temp.sysok(format('update public.employees set employment_status = ''inactive'' where id = %L', pg_temp.c('EMP2ID')));
  insert into t5ctx values ('D07B', ((pg_temp.dcm('EDU', null)::jsonb ->> 'employees')::int = (select count(*) from public.employees where org_id = pg_temp.c('OA')::uuid and employment_status in ('active','on_leave')))::text);
end $$;
do $$ declare r text; begin
  r := pg_temp.dcm('HEAD', pg_temp.c('DEP'));
  perform pg_temp.ok('D01', 'Department', 'HEAD o''z bo''limi: EMP qatori xodim summary bilan bir xil', pg_temp.etc('EMP', null),
    (select x -> 'training' ->> 'total_required' || '/' || (x -> 'training' ->> 'completed') || '/' || (x -> 'training' ->> 'in_progress') || '/' || (x -> 'training' ->> 'not_started') || '/' ||
       (x -> 'training' ->> 'overdue') || '/' || (x -> 'training' ->> 'cancelled') || '/' || (x -> 'training' ->> 'compliance_percent')
     from jsonb_array_elements(r::jsonb -> 'rows') x where x ->> 'employee_id' = pg_temp.c('EMPID')));
  perform pg_temp.ok('D02', 'Department', 'Bo''lim matritsasi kompetensiya qatori xodim matritsasi bilan bir xil', pg_temp.ecm('EMP', null),
    (select x -> 'competency' ->> 'required' || '/' || (x -> 'competency' ->> 'achieved') || '/' || (x -> 'competency' ->> 'not_achieved') || '/' || (x -> 'competency' ->> 'not_assessed')
     from jsonb_array_elements(r::jsonb -> 'rows') x where x ->> 'employee_id' = pg_temp.c('EMPID')));
  perform pg_temp.ok('D03', 'Department', 'HEAD: boshqa bo''lim / butun tashkilot — rad', 'DENIED/DENIED', pg_temp.dcm('HEAD', pg_temp.c('DEP2')) || '/' || pg_temp.dcm('HEAD', null));
  perform pg_temp.ok('D04', 'Department', 'HR / EM / SA: bo''lim va tashkilot darajasi OK', 'department/organization/organization/organization',
    (pg_temp.dcm('HR', pg_temp.c('DEP2'))::jsonb ->> 'scope') || '/' || (pg_temp.dcm('HR', null)::jsonb ->> 'scope') || '/' || (pg_temp.dcm('EDU', null)::jsonb ->> 'scope') || '/' || (pg_temp.dcm('SA', null)::jsonb ->> 'scope'));
  perform pg_temp.ok('D05', 'Department', 'Instructor / Medical Reviewer / Employee — rad', 'DENIED/DENIED/DENIED',
    pg_temp.dcm('INS', pg_temp.c('DEP')) || '/' || pg_temp.dcm('REV', pg_temp.c('DEP')) || '/' || pg_temp.dcm('EMP', pg_temp.c('DEP')));
  perform pg_temp.ok('D06', 'Department', 'Boshqa org (BADM) Org A bo''limi — rad; o''z tashkiloti — OK', 'DENIED/organization',
    pg_temp.dcm('BADM', pg_temp.c('DEP')) || '/' || (pg_temp.dcm('BADM', null)::jsonb ->> 'scope'));
  perform pg_temp.ok('D07', 'Department', 'Tashkilot darajasi: bo''limlar yig''indisi = jami; nofaol xodim kirmaydi', 'true/true',
    (select ((r2 -> 'training' ->> 'total_required')::int = (select sum((x ->> 'total_required')::int) from jsonb_array_elements(r2 -> 'departments') x))::text
     from (select pg_temp.dcm('EDU', null)::jsonb r2) z) || '/' ||
    pg_temp.c('D07B'));
  perform pg_temp.ok('D08', 'Training', 'Nofaol xodimning shaxsiy compliance''i HR uchun baribir ko''rinadi', '1/0/0/0/1/0/0.0', pg_temp.etc('HR', pg_temp.c('EMP2ID')));
  perform pg_temp.sysok(format('update public.employees set employment_status = ''active'' where id = %L', pg_temp.c('EMP2ID')));
end $$;

-- ---------- V: invariantlar / yon ta'sir ----------
do $$ declare s0 text := pg_temp.side(); v text; begin
  v := pg_temp.rpc(pg_temp.u('EMP'), 'public.employee_training_compliance()'); v := pg_temp.rpc(pg_temp.u('EMP'), 'public.employee_competency_matrix()');
  v := pg_temp.dcm('EDU', null); v := pg_temp.dcm('HEAD', pg_temp.c('DEP')); v := pg_temp.etc('HR', pg_temp.c('EMPID'));
  perform pg_temp.ok('V01', 'Side effects', 'O''qish RPC''lari bildirishnoma / audit / tayinlash / baholash / talab / yo''nalish yaratmaydi', s0, pg_temp.side());
  perform pg_temp.ok('V02', 'Invariants', 'anon execute faqat verify_certificate', 'verify_certificate',
    (select string_agg(p.proname, ',') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'EXECUTE')));
  perform pg_temp.ok('V03', 'Invariants', 'Ichki 007e funksiyalari authenticated uchun yopiq; 3 RPC ochiq; hammasi STABLE + search_path', '0/3/6/6',
    (select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like '%\_007e' and has_function_privilege('authenticated', p.oid, 'EXECUTE')) || '/' ||
    (select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('employee_training_compliance', 'employee_competency_matrix', 'department_compliance_matrix')
       and has_function_privilege('authenticated', p.oid, 'EXECUTE') and not has_function_privilege('anon', p.oid, 'EXECUTE')) || '/' ||
    (select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname like '%\_007e' or p.proname in ('employee_training_compliance', 'employee_competency_matrix', 'department_compliance_matrix')) and p.provolatile = 's') || '/' ||
    (select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname like '%\_007e' or p.proname in ('employee_training_compliance', 'employee_competency_matrix', 'department_compliance_matrix'))
       and p.prosecdef and array_to_string(p.proconfig, ',') like '%search_path=public%'));
  perform pg_temp.ok('V04', 'Invariants', 'Yangi jadval / view / trigger / permission yo''q (007e)', '0/0/0',
    (select count(*)::text from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname ~ '(compliance|matrix|007e)') || '/' ||
    (select count(*)::text from pg_trigger where tgname like '%007e%') || '/' || (select count(*)::text from public.permissions where key ~ '(compliance|matrix)'));
  perform pg_temp.ok('V05', 'Invariants', 'Urinishlar va sertifikatlar o''zgarmagan; CASCADE 0', 'true/true/0',
    ((select md5(coalesce(string_agg(to_jsonb(a)::text, '' order by a.id), '')) from public.exam_attempts a) = (pg_temp.c('BASE')::json ->> 'attempts_md5'))::text || '/' ||
    ((select md5(coalesce(string_agg(to_jsonb(c)::text, '' order by c.id), '')) from public.certificates c) = (pg_temp.c('BASE')::json ->> 'certs_md5'))::text || '/' ||
    (select count(*)::text from pg_constraint where connamespace = 'public'::regnamespace and contype = 'f' and confdeltype = 'c'));
  perform pg_temp.ok('V06', 'Invariants', 'Javoblarda maxfiy maydonlar yo''q (javob kaliti, parol, token, izoh)', 'false',
    ((pg_temp.rpc(pg_temp.u('EMP'), 'public.employee_training_compliance()') || pg_temp.rpc(pg_temp.u('EMP'), 'public.employee_competency_matrix()') || pg_temp.dcm('EDU', null))
      ~* '(correct|answer|password|token|service_role|internal_notes|izoh)')::text);
end $$;

select line from (
  select 0 ord, 'SUMMARY 007e total ' || count(*) || ' / PASS ' || count(*) filter (where pass) || ' / FAIL ' || count(*) filter (where not pass) || coalesce(' :: ' || string_agg(id, ',' order by id) filter (where not pass), '') as line from t5
  union all select 1, id || ' ' || case when pass then 'PASS' else 'FAIL' end || ' [' || grp || '] ' || test || ' :: kutilgan=' || expected || ' :: natija=' || actual from t5) x order by ord, line;
select json_build_object('total', count(*), 'pass', count(*) filter (where pass), 'fail', count(*) filter (where not pass),
  'fail_ids', coalesce(json_agg(id || ' => ' || actual order by id) filter (where not pass), '[]'::json),
  'groups', (select json_object_agg(grp, n) from (select grp, count(*) || '/' || count(*) filter (where pass) n from t5 group by grp) g))::text as summary_007e from t5;
rollback;
