-- PRODUCTION (006b): 006b test to'plami (staging/006b_02_tests.sql aynan), ROLLBACK
-- Vaqtinchalik test identifikatorlari (Org B + test foydalanuvchilar, @test.local, parolsiz, tizimga kira olmaydi) FAQAT shu tranzaksiya ichida
-- yaratiladi va oxiridagi ROLLBACK bilan butunlay yo'qoladi (54/55 usuli). Doimiy akkaunt yaratilmaydi.
begin;
do $$ begin
  if not exists (select 1 from public.schema_migrations where version = '006b') then raise exception 'TO''XTATILDI: 006b qo''llanmagan'; end if;
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

-- ---- 006b test to'plami (staging/006b_02_tests.sql, o'zgarishsiz) ----
-- MedAcademy · 006b kurs DELETE hardening test to'plami (lokal PGlite va staging uchun bir xil fayl).
-- Mavjud test akkauntlari (staging) bilan; yangi auth akkaunt yaratilmaydi. Hammasi BITTA tranzaksiyada, oxirida ROLLBACK.
-- Har bir foydalanuvchi so'rovi haqiqiy RLS / trigger / RPC orqali JWT claim'lari bilan bajariladi.
do $$ begin
  if not exists (select 1 from public.schema_migrations where version = '006b') then raise exception '006b qo''llanmagan'; end if;
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
do $$ begin
  perform pg_temp.logout();
  insert into t5ctx select 'BASE', json_build_object(
    'attempts_md5', (select md5(coalesce(string_agg(to_jsonb(a)::text, '' order by a.id), '')) from public.exam_attempts a),
    'certs_md5', (select md5(coalesce(string_agg(to_jsonb(c)::text, '' order by c.id), '')) from public.certificates c),
    'courses', (select count(*) from public.courses),
    'policies', (select md5(string_agg(tablename || '.' || policyname || ':' || cmd || ':' || coalesce(qual, '-') || ':' || coalesce(with_check, '-'), '|' order by tablename, policyname)) from pg_policies where schemaname = 'public'))::text;
  -- Bog'liqliksiz (FK himoyasi yo'q) test kursi — eng xavfli holat: FK RESTRICT to'xtatmaydi
  perform pg_temp.sys(format($q$insert into public.courses (id, org_id, title, domain, status) values ('T6B_EMPTY', %L, 'T6B bo''sh kurs', 'ethics', 'published')$q$, pg_temp.c('OA')));
  perform pg_temp.sys(format($q$insert into public.courses (id, org_id, title, domain, status) values ('T6B_ORGB', %L, 'T6B Org B kursi', 'ethics', 'draft')$q$, pg_temp.c('OB')));
  perform pg_temp.sys(format($q$insert into public.certificates (id, org_id, user_id, course_id, course_title, name, position, department, score, attempt_id, issued_at)
    values ('T6B-CERT', %L, %L, 'T6B_EMPTY', 'T6B bo''sh kurs', 'T6B Test', 'x', 'x', 90, null, now())$q$, pg_temp.c('OA'), pg_temp.c('EMP')));
end $$;
create function pg_temp.lastaudit(p_action text, p_id text) returns jsonb language sql security definer as $$
  select to_jsonb(a) from public.audit_logs a where action = p_action and entity_id = p_id order by id desc limit 1 $$;
create function pg_temp.rpc(uid uuid, q text) returns text language plpgsql as $$ declare v text; begin
  perform pg_temp.login(uid); set local role authenticated; execute 'select (' || q || ')::text' into v; reset role; perform pg_temp.logout(); return coalesce(v, 'NULL');
exception when others then reset role; perform pg_temp.logout(); insert into t5err (uid, q, err) values (uid::text, left(q, 160), sqlerrm); return 'DENIED'; end $$;
create function pg_temp.rpca(q text) returns text language plpgsql as $$ declare v text; begin
  set local role anon; execute 'select (' || q || ')::text' into v; reset role; return coalesce(v, 'NULL');
exception when others then reset role; return 'DENIED'; end $$;

-- ===== K. Kursni o'chirish =====
do $$ declare res text; begin
  perform pg_temp.ok('K01', 'Course delete', 'SA (API): bog''liqliksiz kursni DELETE', 'DENIED', pg_temp.w(pg_temp.u('SA'), 'delete from public.courses where id = ''T6B_EMPTY'''));
  perform pg_temp.ok('K02', 'Course delete', 'EM (API): kursni DELETE', 'DENIED', pg_temp.w(pg_temp.u('EDU'), 'delete from public.courses where id = ''T6B_EMPTY'''));
  perform pg_temp.ok('K03', 'Course delete', 'Instructor (API): kursni DELETE', 'DENIED|OK:0', pg_temp.w(pg_temp.u('INS'), 'delete from public.courses where id = ''CARDIO_BASIC'''));
  perform pg_temp.ok('K04', 'Course delete', 'HR (API): kursni DELETE', 'DENIED|OK:0', pg_temp.w(pg_temp.u('HR'), 'delete from public.courses where id = ''T6B_EMPTY'''));
  perform pg_temp.ok('K05', 'Course delete', 'Employee (API): kursni DELETE', 'DENIED|OK:0', pg_temp.w(pg_temp.u('EMP'), 'delete from public.courses where id = ''T6B_EMPTY'''));
  perform pg_temp.ok('K06', 'Course delete', 'anon: kursni DELETE', 'DENIED|OK:0', pg_temp.wa('delete from public.courses where id = ''T6B_EMPTY'''));
  perform pg_temp.ok('K07', 'Course delete', 'Org B admin: Org A kursini DELETE', 'DENIED|OK:0', pg_temp.w(pg_temp.u('BADM'), 'delete from public.courses where id = ''T6B_EMPTY'''));
  perform pg_temp.ok('K08', 'Course delete', 'Org B admin: o''z (Org B) kursini DELETE', 'DENIED', pg_temp.w(pg_temp.u('BADM'), 'delete from public.courses where id = ''T6B_ORGB'''));
  perform pg_temp.ok('K09', 'Course delete', 'SA (API): barcha kurslarni DELETE', 'DENIED', pg_temp.w(pg_temp.u('SA'), 'delete from public.courses'));
  perform pg_temp.ok('K10', 'Course delete', 'Kurslar soni o''zgarmagan (fixture''lar bilan)', ((pg_temp.c('BASE')::json ->> 'courses')::int + 2)::text, (select count(*)::text from public.courses));
end $$;

-- ===== L. Arxivlash (sababli RPC va to'g'ridan-to'g'ri UPDATE) =====
do $$ declare a jsonb; begin
  perform pg_temp.ok('L01', 'Course archive', 'SA: admin_set_course_status sababsiz', 'DENIED', pg_temp.rpc(pg_temp.u('SA'), 'public.admin_set_course_status(''T6B_EMPTY'', ''archived'', '' '')'));
  perform pg_temp.ok('L02', 'Course archive', 'SA: noto''g''ri holat', 'DENIED', pg_temp.rpc(pg_temp.u('SA'), 'public.admin_set_course_status(''T6B_EMPTY'', ''deleted'', ''T6B test'')'));
  perform pg_temp.ok('L03', 'Course archive', 'SA: arxivlash (sabab bilan)', 'ok', case when pg_temp.rpc(pg_temp.u('SA'), 'public.admin_set_course_status(''T6B_EMPTY'', ''archived'', ''T6B: kurs eskirgan'')') like '%"new_status": "archived"%' then 'ok' else 'fail' end);
  a := pg_temp.lastaudit('course.archived', 'T6B_EMPTY');
  perform pg_temp.ok('L04', 'Course archive', 'course.archived audit: eski/yangi holat, actor SA, tashkilot, sabab', 'true',
    (a is not null and a -> 'old_value' ->> 'status' = 'published' and a -> 'new_value' ->> 'status' = 'archived' and a ->> 'actor_id' = pg_temp.c('SA')
     and a ->> 'org_id' = pg_temp.c('OA') and a -> 'new_value' ->> 'reason' like 'T6B:%')::text);
  perform pg_temp.ok('L05', 'Course archive', 'EM: qayta nashr (published) sabab bilan', 'ok', case when pg_temp.rpc(pg_temp.u('EDU'), 'public.admin_set_course_status(''T6B_EMPTY'', ''published'', ''T6B: qayta faollashtirildi'')') like '%"new_status": "published"%' then 'ok' else 'fail' end);
  perform pg_temp.ok('L06', 'Course archive', 'course.published audit (actor EM)', 'true', ((pg_temp.lastaudit('course.published', 'T6B_EMPTY') ->> 'actor_id') = pg_temp.c('EDU'))::text);
  perform pg_temp.ok('L07', 'Course archive', 'EM: to''g''ridan-to''g''ri UPDATE status = archived (mavjud oqim saqlangan)', 'OK:1', pg_temp.w(pg_temp.u('EDU'), 'update public.courses set status = ''archived'' where id = ''T6B_EMPTY'''));
  perform pg_temp.ok('L08', 'Course archive', 'Instructor: admin_set_course_status', 'DENIED', pg_temp.rpc(pg_temp.u('INS'), 'public.admin_set_course_status(''CARDIO_BASIC'', ''archived'', ''T6B x'')'));
  perform pg_temp.ok('L09', 'Course archive', 'HR: admin_set_course_status', 'DENIED', pg_temp.rpc(pg_temp.u('HR'), 'public.admin_set_course_status(''T6B_EMPTY'', ''archived'', ''T6B x'')'));
  perform pg_temp.ok('L10', 'Course archive', 'Employee: admin_set_course_status', 'DENIED', pg_temp.rpc(pg_temp.u('EMP'), 'public.admin_set_course_status(''T6B_EMPTY'', ''archived'', ''T6B x'')'));
  perform pg_temp.ok('L11', 'Course archive', 'anon: admin_set_course_status', 'DENIED', pg_temp.rpca('public.admin_set_course_status(''T6B_EMPTY'', ''archived'', ''T6B x'')'));
  perform pg_temp.ok('L12', 'Course archive', 'Org B admin: Org A kursini arxivlash', 'DENIED', pg_temp.rpc(pg_temp.u('BADM'), 'public.admin_set_course_status(''T6B_EMPTY'', ''draft'', ''T6B cross'')'));
  perform pg_temp.ok('L13', 'Course archive', 'EM: kurs yaratish (INSERT) ishlaydi', 'OK:1', pg_temp.w(pg_temp.u('EDU'), format('insert into public.courses (id, org_id, title, domain, status) values (''T6B_NEW'', %L, ''T6B yangi'', ''ethics'', ''draft'')', pg_temp.c('OA'))));
  perform pg_temp.ok('L14', 'Course archive', 'EM: kurs tahriri (title) ishlaydi', 'OK:1', pg_temp.w(pg_temp.u('EDU'), 'update public.courses set title = ''T6B yangi (2)'' where id = ''T6B_NEW'''));
  perform pg_temp.ok('L15', 'Course archive', 'EM: yangi yaratilgan kursni ham DELETE qilib bo''lmaydi', 'DENIED', pg_temp.w(pg_temp.u('EDU'), 'delete from public.courses where id = ''T6B_NEW'''));
end $$;

-- ===== M. Tarix saqlanishi =====
do $$ declare res text; begin
  perform pg_temp.ok('M01', 'Course history', 'Arxivlangan kurs sertifikati saqlangan', '1', (select count(*)::text from public.certificates where id = 'T6B-CERT' and course_id = 'T6B_EMPTY'));
  perform pg_temp.ok('M02', 'Course history', 'Tarixiy urinishlar o''zgarmagan (md5)', 'true', ((select md5(coalesce(string_agg(to_jsonb(a)::text, '' order by a.id), '')) from public.exam_attempts a) = (pg_temp.c('BASE')::json ->> 'attempts_md5'))::text);
  perform pg_temp.ok('M03', 'Course history', 'Kurs audit yozuvlari saqlangan (archived/published)', 'true', (select count(*) >= 3 from public.audit_logs where entity = 'course' and entity_id = 'T6B_EMPTY')::text);
  perform pg_temp.ok('M04', 'Course history', 'Arxivlangan kurs fizik mavjud', 'archived', (select status from public.courses where id = 'T6B_EMPTY'));
  perform pg_temp.ok('M05', 'Course history', 'RLS policy''lari o''zgarmagan (courses_write saqlangan)', 'true',
    ((select md5(string_agg(tablename || '.' || policyname || ':' || cmd || ':' || coalesce(qual, '-') || ':' || coalesce(with_check, '-'), '|' order by tablename, policyname)) from pg_policies where schemaname = 'public') = (pg_temp.c('BASE')::json ->> 'policies'))::text);
  begin delete from public.courses where id = 'T6B_ORGB'; res := 'OK'; exception when others then res := 'DENIED'; end;
  perform pg_temp.ok('M06', 'Course history', 'Platforma SQL (texnik xizmat, non-API): bog''liqliksiz kurs DELETE ruxsat etilgan va audit qilinadi', 'OK/true', res || '/' || (pg_temp.lastaudit('course.deleted', 'T6B_ORGB') is not null)::text);
  perform pg_temp.ok('M07', 'Invariants', 'anon EXECUTE (faqat verify_certificate)', 'verify_certificate',
    (select string_agg(p.proname, ',') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'EXECUTE')));
  perform pg_temp.ok('M08', 'Invariants', 'guard_course_delete_006b authenticated uchun EXECUTE emas', 'false', (select has_function_privilege('authenticated', 'public.guard_course_delete_006b()'::regprocedure, 'EXECUTE')::text));
  perform pg_temp.ok('M09', 'Invariants', '006b schema_migrations / trigger', '1/1', (select count(*) from public.schema_migrations where version = '006b') || '/' || (select count(*) from pg_trigger where tgname = 'courses_no_delete_006b_trg'));
end $$;

select line from (
  select 0 ord, 'SUMMARY 006b total ' || count(*) || ' / PASS ' || count(*) filter (where pass) || ' / FAIL ' || count(*) filter (where not pass) || coalesce(' :: ' || string_agg(id, ',' order by id) filter (where not pass), '') as line from t5
  union all select 1, id || ' ' || case when pass then 'PASS' else 'FAIL' end || ' [' || grp || '] ' || test || ' :: kutilgan=' || expected || ' :: natija=' || actual from t5) x order by ord, line;
select json_build_object('total', count(*), 'pass', count(*) filter (where pass), 'fail', count(*) filter (where not pass),
  'fail_ids', coalesce(json_agg(id || ' => ' || actual order by id) filter (where not pass), '[]'::json),
  'groups', (select json_object_agg(grp, n) from (select grp, count(*) || '/' || count(*) filter (where pass) n from t5 group by grp) g))::text as summary_006b from t5;
rollback;
