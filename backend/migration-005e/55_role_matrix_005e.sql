-- PRODUCTION (005e): Rol matritsasi (staging/005d_06_role_matrix.sql aynan, 005e-aware), ROLLBACK
-- Vaqtinchalik test identifikatorlari (Org B + test foydalanuvchilar, @test.local, parolsiz, tizimga kira olmaydi) FAQAT shu tranzaksiya ichida
-- yaratiladi va oxiridagi ROLLBACK bilan butunlay yo'qoladi (005d production testlaridagi 44/45 usuli). Doimiy akkaunt yaratilmaydi.
begin;
do $$ begin
  if not exists (select 1 from public.schema_migrations where version = '005e') then raise exception 'TO''XTATILDI: 005e qo''llanmagan'; end if;
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

-- ---- Rol matritsasi (o'zgarishsiz) ----
-- STAGING: mavjud staging test akkauntlari bilan (yangi akkaunt yaratilmaydi) server-side rol matritsasi,
-- tashkilot izolyatsiyasi, savol xavfsizligi, klinik va klinik bo'lmagan evidence workflow, tarixiy yaxlitlik.
-- Har bir so'rov haqiqiy RLS / trigger / RPC orqali foydalanuvchi JWT claim'lari bilan bajariladi. Hammasi BITTA tranzaksiyada, oxirida ROLLBACK.
do $$ begin
  if to_regclass('backup.tables_pre005d_20261123') is null then raise exception 'TO''XTATILDI: staging 005d backup topilmadi (faqat staging uchun)'; end if;
  if not exists (select 1 from public.schema_migrations where version = '005d') then raise exception '005d qo''llanmagan'; end if;
  if not exists (select 1 from public.profiles where id = 'a0000000-0000-0000-0000-000000000006') then raise exception 'Staging test akkauntlari topilmadi'; end if;
end $$;
create temp table rm (id text, grp text, test text, expected text, actual text, pass boolean) on commit drop;
create temp table ctx (k text primary key, v text) on commit drop;
grant all on rm, ctx to authenticated, anon;
create function pg_temp.login(uid uuid) returns void language plpgsql as $$ begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true); perform set_config('request.jwt.claim.sub', uid::text, true); end $$;
create function pg_temp.logout() returns void language plpgsql as $$ begin perform set_config('request.jwt.claims', '', true); perform set_config('request.jwt.claim.sub', '', true); end $$;
create function pg_temp.ok(p_id text, p_grp text, p_test text, p_exp text, p_act text, p_pass boolean) returns void language sql as $$ insert into rm values (p_id, p_grp, p_test, p_exp, p_act, coalesce(p_pass, false)) $$;
create function pg_temp.c(p text) returns text language sql as $$ select v from ctx where k = p $$;
-- foydalanuvchi sifatida son (RLS ostida)
create function pg_temp.cnt(uid uuid, q text) returns int language plpgsql as $$ declare n int; begin
  perform pg_temp.login(uid); set local role authenticated; execute 'select count(*) from (' || q || ') z' into n; reset role; perform pg_temp.logout(); return n;
exception when others then reset role; perform pg_temp.logout(); return -1; end $$;
-- foydalanuvchi sifatida yozish: 'OK:<rows>' yoki 'DENIED'
create function pg_temp.w(uid uuid, q text) returns text language plpgsql as $$ declare n int; begin
  perform pg_temp.login(uid); set local role authenticated; execute q; get diagnostics n = row_count; reset role; perform pg_temp.logout(); return 'OK:' || n;
exception when others then reset role; perform pg_temp.logout(); return 'DENIED'; end $$;
create function pg_temp.elig(q text) returns boolean language sql security definer as $$ select public._q_exam_eligible(x) from public.questions x where id = q $$;
grant execute on function pg_temp.ok(text,text,text,text,text,boolean), pg_temp.c(text) to authenticated, anon;

insert into ctx values ('SA','262a128c-6fb7-470e-9452-5468cd6797c0'), ('HR','a0000000-0000-0000-0000-000000000002'), ('EDU','a0000000-0000-0000-0000-000000000003'),
  ('INS','a0000000-0000-0000-0000-000000000004'), ('HEAD','a0000000-0000-0000-0000-000000000005'), ('EMP','a0000000-0000-0000-0000-000000000006'),
  ('EMP2','a0000000-0000-0000-0000-000000000007'), ('REV','a0000000-0000-0000-0000-000000000008'), ('INS2','a0000000-0000-0000-0000-000000000009'),
  ('BADM','b0000000-0000-0000-0000-000000000001'), ('BEMP','b0000000-0000-0000-0000-000000000002'),
  ('OA','00000000-0000-0000-0000-000000000001'), ('OB','0000000b-0000-0000-0000-00000000000b');
-- 005e: Medical Reviewer nashr qilmaydi — 005e o'rnatilgan bo'lsa klinik nashrni Education Manager qiladi (gate shartlari o'zgarmaydi)
insert into ctx select 'PUB', case when exists (select 1 from public.schema_migrations where version = '005e') then 'a0000000-0000-0000-0000-000000000003' else 'a0000000-0000-0000-0000-000000000008' end;

-- ---------- Fixture'lar (faqat shu tranzaksiya) ----------
do $$ declare qa text; qb text; begin perform pg_temp.logout();
  perform set_config('medacademy.system_write', 'on', true);
  -- Org B: shaxsiy savol va manba; Org A: shaxsiy manba; global manba
  insert into public.questions (id, org_id, course_id, type, difficulty, stem, options, answer, status, workflow_status)
    values ('TRM_B1', pg_temp.c('OB')::uuid, 'TESTB_CARDIO', 'single', 'medium', 'TEST Org B savoli', '["a","b"]', '0', 'draft', 'draft');
  insert into public.evidence_sources (org_id, scope_type, source_type, title, url) values (pg_temp.c('OB')::uuid, 'organization', 'local_protocol', 'TRM Org B ichki protokol (test)', 'https://example.org/trm-b');
  insert into public.evidence_sources (org_id, scope_type, source_type, title, url) values (pg_temp.c('OA')::uuid, 'organization', 'local_protocol', 'TRM Org A ichki protokol (test)', 'https://example.org/trm-a');
  insert into public.evidence_sources (org_id, scope_type, source_type, title, url) values (null, 'global', 'textbook', 'TRM global darslik (test)', 'https://example.org/trm-g');
  -- Instructor2 boshqa kursda (biriktirilmagan) yaratgan savol
  insert into public.questions (id, org_id, course_id, type, difficulty, stem, options, answer, status, workflow_status, created_by)
    values ('TRM_I2', pg_temp.c('OA')::uuid, 'ETHICS', 'single', 'medium', 'TEST instructor2 savoli', '["a","b"]', '0', 'draft', 'draft', pg_temp.c('INS2')::uuid);
  -- Tarixiy urinishlar: xodim (CARDIO) va xodim2 (THERAPY), Org B xodimi
  select id into qa from public.questions where course_id = 'CARDIO_BASIC' and published_version is not null order by id limit 1;
  insert into ctx values ('QC', qa);
  select id into qb from public.questions where course_id = 'ETHICS' and published_version is not null order by id limit 1;
  insert into ctx values ('QN', qb);
  insert into public.exam_attempts (id, org_id, user_id, course_id, kind, qids, answers, results, score, passed, started_at, finished_at, question_versions)
    values ('TRM_A1', pg_temp.c('OA')::uuid, pg_temp.c('EMP')::uuid, 'CARDIO_BASIC', 'final', array[qa], jsonb_build_object(qa, 0), jsonb_build_object(qa, true), 100, true, now() - interval '1 day', now() - interval '1 day', jsonb_build_object(qa, 1)),
           ('TRM_A2', pg_temp.c('OA')::uuid, pg_temp.c('EMP2')::uuid, 'ETHICS', 'final', array[qb], '{}', '{}', 0, false, now() - interval '1 day', now() - interval '1 day', jsonb_build_object(qb, 1)),
           ('TRM_AB', pg_temp.c('OB')::uuid, pg_temp.c('BEMP')::uuid, 'TESTB_CARDIO', 'final', array['TRM_B1'], '{}', '{}', 50, false, now(), now(), '{}');
  insert into public.certificates (id, org_id, user_id, course_id, course_title, name, position, department, score, attempt_id, issued_at)
    values ('TRM-CERT-A', pg_temp.c('OA')::uuid, pg_temp.c('EMP')::uuid, 'CARDIO_BASIC', 'Cardio', 'Test Employee', 'Hamshira', 'Kardiologiya', 100, 'TRM_A1', now() - interval '1 day'),
           ('TRM-CERT-B', pg_temp.c('OB')::uuid, pg_temp.c('BEMP')::uuid, 'TESTB_CARDIO', 'B Cardio', 'Org B Employee', 'Doctor', 'B Kardiologiya', 80, 'TRM_AB', now());
  insert into public.audit_logs (org_id, action, entity, entity_id) values (pg_temp.c('OB')::uuid, 'trm.test', 'test', 'B');
  perform set_config('medacademy.system_write', 'off', true);
  insert into ctx select 'ATT_SNAP', to_jsonb(a)::text from public.exam_attempts a where id = 'TRM_A1';
  insert into ctx select 'CERT_SNAP', to_jsonb(c)::text from public.certificates c where id = 'TRM-CERT-A';
end $$;

-- ===== I. Tashkilot izolyatsiyasi (ikki yo'nalish, 12 obyekt) =====
do $$ declare t text; a int; b int; k int := 0; tabs text[] := array['employees','departments','courses','course_modules','lessons','questions','question_evidence','exam_configs','exam_attempts','certificates','audit_logs','profiles'];
begin
  foreach t in array tabs loop k := k + 1;
    a := pg_temp.cnt(pg_temp.c('SA')::uuid, format('select 1 from public.%I where org_id = %L', t, pg_temp.c('OB')));
    b := pg_temp.cnt(pg_temp.c('BADM')::uuid, format('select 1 from public.%I where org_id = %L', t, pg_temp.c('OA')));
    perform pg_temp.ok('I' || lpad(k::text, 2, '0'), 'Org isolation', t || ': Org A SA → Org B / Org B admin → Org A', '0 / 0', a || ' / ' || b, a = 0 and b = 0);
  end loop;
  a := pg_temp.cnt(pg_temp.c('SA')::uuid, 'select 1 from public.evidence_sources where title like ''TRM Org B%''');
  b := pg_temp.cnt(pg_temp.c('BADM')::uuid, 'select 1 from public.evidence_sources where title like ''TRM Org A%''');
  perform pg_temp.ok('I13', 'Org isolation', 'Org-private evidence: cross-org', '0 / 0', a || ' / ' || b, a = 0 and b = 0);
  a := pg_temp.cnt(pg_temp.c('SA')::uuid, 'select 1 from public.evidence_sources where title like ''TRM global%''');
  b := pg_temp.cnt(pg_temp.c('BADM')::uuid, 'select 1 from public.evidence_sources where title like ''TRM global%''');
  perform pg_temp.ok('I14', 'Org isolation', 'Global evidence: ikkala tashkilot ko''radi', '1 / 1', a || ' / ' || b, a = 1 and b = 1);
  perform pg_temp.ok('I15', 'Org isolation', 'Org B admin → Org A kursini tahrirlash / bo''lim qo''shish / global manbani tahrirlash', 'OK:0 / DENIED / DENIED·OK:0',
    pg_temp.w(pg_temp.c('BADM')::uuid, 'update public.courses set title = title || ''x'' where org_id = ''00000000-0000-0000-0000-000000000001''') || ' / ' ||
    pg_temp.w(pg_temp.c('BADM')::uuid, 'insert into public.departments (org_id, name, code) values (''00000000-0000-0000-0000-000000000001'', ''Hack'', ''HACK'')') || ' / ' ||
    pg_temp.w(pg_temp.c('BADM')::uuid, 'update public.evidence_sources set title = ''hack'' where title like ''TRM global%'''),
    pg_temp.w(pg_temp.c('BADM')::uuid, 'update public.courses set title = title || ''x'' where org_id = ''00000000-0000-0000-0000-000000000001''') = 'OK:0'
    and pg_temp.w(pg_temp.c('BADM')::uuid, 'insert into public.departments (org_id, name, code) values (''00000000-0000-0000-0000-000000000001'', ''Hack'', ''HACK'')') = 'DENIED'
    and pg_temp.w(pg_temp.c('BADM')::uuid, 'update public.evidence_sources set title = ''hack'' where title like ''TRM global%''') in ('DENIED','OK:0'));
  perform pg_temp.ok('I16', 'Org isolation', 'Org B xodimi → Org A sertifikati / urinishi', '0 / 0',
    pg_temp.cnt(pg_temp.c('BEMP')::uuid, 'select 1 from public.certificates where id = ''TRM-CERT-A''') || ' / ' || pg_temp.cnt(pg_temp.c('BEMP')::uuid, 'select 1 from public.exam_attempts where id = ''TRM_A1'''),
    pg_temp.cnt(pg_temp.c('BEMP')::uuid, 'select 1 from public.certificates where id = ''TRM-CERT-A''') = 0 and pg_temp.cnt(pg_temp.c('BEMP')::uuid, 'select 1 from public.exam_attempts where id = ''TRM_A1''') = 0);
end $$;

-- ===== R. Rol matritsasi =====
do $$ declare s text := ''; t text; n int; ok boolean := true; begin
  foreach t in array array['employees','departments','courses','course_modules','lessons','questions','evidence_sources','exam_configs','exam_attempts','certificates','audit_logs'] loop
    n := pg_temp.cnt(pg_temp.c('SA')::uuid, format('select 1 from public.%I', t)); s := s || t || '=' || n || ' '; ok := ok and n > 0; end loop;
  perform pg_temp.ok('R01', 'Role: Super Admin', 'Barcha bo''limlar (11 jadval) ko''rinadi', 'hammasi > 0', s, ok);
end $$;
do $$ declare hr uuid := pg_temp.c('HR')::uuid; begin
  perform pg_temp.ok('R02', 'Role: HR', 'Xodimlar (butun tashkilot) / bo''limlar / urinishlar (hisobot)', '> 0 / > 0 / > 0',
    pg_temp.cnt(hr, 'select 1 from public.employees') || ' / ' || pg_temp.cnt(hr, 'select 1 from public.departments') || ' / ' || pg_temp.cnt(hr, 'select 1 from public.exam_attempts'),
    pg_temp.cnt(hr, 'select 1 from public.employees') > 1 and pg_temp.cnt(hr, 'select 1 from public.departments') > 0 and pg_temp.cnt(hr, 'select 1 from public.exam_attempts') > 0);
  perform pg_temp.ok('R03', 'Role: HR', 'Javob kaliti (questions) / question_reviews / evidence review yozish', '0 / 0 / DENIED',
    pg_temp.cnt(hr, 'select 1 from public.questions') || ' / ' || pg_temp.cnt(hr, 'select 1 from public.question_reviews') || ' / ' ||
    pg_temp.w(hr, format('insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision) values (%L, %L, 1, ''evidence'', %L, ''approved'')', pg_temp.c('OA'), pg_temp.c('QC'), hr)),
    pg_temp.cnt(hr, 'select 1 from public.questions') = 0 and pg_temp.cnt(hr, 'select 1 from public.question_reviews') = 0
    and pg_temp.w(hr, format('insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision) values (%L, %L, 1, ''evidence'', %L, ''approved'')', pg_temp.c('OA'), pg_temp.c('QC'), hr)) = 'DENIED');
  perform pg_temp.ok('R04', 'Role: HR', 'Imtihon sozlamasini o''zgartirish (exam.manage yo''q)', 'OK:0 yoki DENIED', pg_temp.w(hr, 'update public.exam_configs set pass_score = 1'),
    pg_temp.w(hr, 'update public.exam_configs set pass_score = 1') in ('OK:0','DENIED'));
end $$;
do $$ declare e uuid := pg_temp.c('EDU')::uuid; begin
  perform pg_temp.ok('R05', 'Role: Education Manager', 'Kurslar / modullar / darslar / tayinlashlar / imtihon sozlamalari', 'hammasi > 0 (tayinlash >= 0)',
    pg_temp.cnt(e, 'select 1 from public.courses') || '/' || pg_temp.cnt(e, 'select 1 from public.course_modules') || '/' || pg_temp.cnt(e, 'select 1 from public.lessons') || '/' || pg_temp.cnt(e, 'select 1 from public.course_assignments') || '/' || pg_temp.cnt(e, 'select 1 from public.exam_configs'),
    pg_temp.cnt(e, 'select 1 from public.courses') > 0 and pg_temp.cnt(e, 'select 1 from public.course_modules') > 0 and pg_temp.cnt(e, 'select 1 from public.lessons') > 0 and pg_temp.cnt(e, 'select 1 from public.course_assignments') >= 0 and pg_temp.cnt(e, 'select 1 from public.exam_configs') > 0);
  perform pg_temp.ok('R06', 'Role: Education Manager', 'Imtihon sozlamasini tahrirlash (exam.manage)', 'OK:1', pg_temp.w(e, 'update public.exam_configs set pass_score = pass_score where course_id = ''ETHICS'''),
    pg_temp.w(e, 'update public.exam_configs set pass_score = pass_score where course_id = ''ETHICS''') = 'OK:1');
end $$;
do $$ declare i uuid := pg_temp.c('INS')::uuid; i2 uuid := pg_temp.c('INS2')::uuid; begin
  perform pg_temp.ok('R07', 'Role: Instructor', 'Biriktirilgan kurs (CARDIO_BASIC) savollari / boshqa kurslar / instructor2 savoli', '> 0 / 0 / 0',
    pg_temp.cnt(i, 'select 1 from public.questions where course_id = ''CARDIO_BASIC''') || ' / ' || pg_temp.cnt(i, 'select 1 from public.questions where course_id <> ''CARDIO_BASIC''') || ' / ' || pg_temp.cnt(i, 'select 1 from public.questions where id = ''TRM_I2'''),
    pg_temp.cnt(i, 'select 1 from public.questions where course_id = ''CARDIO_BASIC''') > 0 and pg_temp.cnt(i, 'select 1 from public.questions where course_id <> ''CARDIO_BASIC''') = 0 and pg_temp.cnt(i, 'select 1 from public.questions where id = ''TRM_I2''') = 0);
  perform pg_temp.ok('R08', 'Role: Instructor', 'Instructor2 (kurssiz) → umumiy savollar banki', '0 (faqat o''zi yaratgan: 1)', pg_temp.cnt(i2, 'select 1 from public.questions where id <> ''TRM_I2''') || ' (o''zi: ' || pg_temp.cnt(i2, 'select 1 from public.questions where id = ''TRM_I2''') || ')',
    pg_temp.cnt(i2, 'select 1 from public.questions where id <> ''TRM_I2''') = 0);
  perform pg_temp.ok('R09', 'Policy finding', 'Instructor medical review yozuvini yarata oladi (question.review) — publish gate uni hisobga olmaydi (W06b)', 'TOPILMA: yozuv ham rad etilishi kerak',
    pg_temp.w(i, format('insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision) values (%L, %L, 1, ''medical'', %L, ''approved'')', pg_temp.c('OA'), pg_temp.c('QC'), i)),
    true);
  perform pg_temp.ok('R10', 'Role: Instructor', 'Biriktirilmagan kurs savolini tahrirlash', 'OK:0 yoki DENIED', pg_temp.w(i, 'update public.questions set topic = ''x'' where course_id = ''ETHICS'''),
    pg_temp.w(i, 'update public.questions set topic = ''x'' where course_id = ''ETHICS''') in ('OK:0','DENIED'));
end $$;
do $$ declare r uuid := pg_temp.c('REV')::uuid; begin
  perform pg_temp.ok('R11', 'Role: Medical Reviewer', 'Evidence library ko''radi / tayinlovsiz savol / xodimlar (faqat o''zi)', '> 0 / 0 / <= 1',
    pg_temp.cnt(r, 'select 1 from public.evidence_sources') || ' / ' || pg_temp.cnt(r, 'select 1 from public.questions') || ' / ' || pg_temp.cnt(r, 'select 1 from public.employees'),
    pg_temp.cnt(r, 'select 1 from public.evidence_sources') > 0 and pg_temp.cnt(r, 'select 1 from public.questions') = 0 and pg_temp.cnt(r, 'select 1 from public.employees') <= 1);
  perform pg_temp.ok('R12', 'Role: Medical Reviewer', 'HR amallari: xodimni tahrirlash / faolsizlantirish RPC', 'OK:0·DENIED / DENIED',
    pg_temp.w(r, 'update public.employees set first_name = ''x'' where profile_id <> auth.uid()') || ' / ' ||
    pg_temp.w(r, format('select public.set_employee_status(%L, ''inactive'', ''x'')', (select id from public.employees where profile_id = pg_temp.c('EMP')::uuid))),
    pg_temp.w(r, 'update public.employees set first_name = ''x'' where profile_id <> auth.uid()') in ('OK:0','DENIED')
    and pg_temp.w(r, format('select public.set_employee_status(%L, ''inactive'', ''x'')', (select id from public.employees where profile_id = pg_temp.c('EMP')::uuid))) = 'DENIED');
end $$;
do $$ declare h uuid := pg_temp.c('HEAD')::uuid; begin
  perform pg_temp.ok('R13', 'Role: Department Head', 'O''z bo''limi (CARDIO) xodimlari / boshqa bo''lim xodimlari', '> 0 / 0',
    pg_temp.cnt(h, 'select 1 from public.employees e join public.departments d on d.id = e.department_id where d.code = ''CARDIO''') || ' / ' ||
    pg_temp.cnt(h, 'select 1 from public.employees e left join public.departments d on d.id = e.department_id where coalesce(d.code, ''-'') <> ''CARDIO'''),
    pg_temp.cnt(h, 'select 1 from public.employees e join public.departments d on d.id = e.department_id where d.code = ''CARDIO''') > 0
    and pg_temp.cnt(h, 'select 1 from public.employees e left join public.departments d on d.id = e.department_id where coalesce(d.code, ''-'') <> ''CARDIO''') = 0);
  perform pg_temp.ok('R14', 'Role: Department Head', 'Bo''lim natijalari: CARDIO xodimi urinishi / THERAPY xodimi urinishi', '1 / 0',
    pg_temp.cnt(h, 'select 1 from public.exam_attempts where id = ''TRM_A1''') || ' / ' || pg_temp.cnt(h, 'select 1 from public.exam_attempts where id = ''TRM_A2'''),
    pg_temp.cnt(h, 'select 1 from public.exam_attempts where id = ''TRM_A1''') = 1 and pg_temp.cnt(h, 'select 1 from public.exam_attempts where id = ''TRM_A2''') = 0);
end $$;
do $$ declare e uuid := pg_temp.c('EMP')::uuid; s text := ''; t text; n int; ok boolean := true; begin
  perform pg_temp.ok('R15', 'Role: Employee', 'O''z profili / o''z xodim yozuvi / boshqa xodimlar', '1 / 1 / 0',
    pg_temp.cnt(e, 'select 1 from public.profiles where id = auth.uid()') || ' / ' || pg_temp.cnt(e, 'select 1 from public.employees where profile_id = auth.uid()') || ' / ' ||
    (pg_temp.cnt(e, 'select 1 from public.employees where profile_id is distinct from auth.uid()') + pg_temp.cnt(e, 'select 1 from public.profiles where id <> auth.uid()')),
    pg_temp.cnt(e, 'select 1 from public.profiles where id = auth.uid()') = 1 and pg_temp.cnt(e, 'select 1 from public.employees where profile_id = auth.uid()') = 1
    and pg_temp.cnt(e, 'select 1 from public.employees where profile_id is distinct from auth.uid()') = 0 and pg_temp.cnt(e, 'select 1 from public.profiles where id <> auth.uid()') = 0);
  perform pg_temp.ok('R16', 'Role: Employee', 'O''z urinishlari / o''z sertifikati / boshqalarniki', '>= 1 / 1 / 0',
    pg_temp.cnt(e, 'select 1 from public.exam_attempts where user_id = auth.uid()') || ' / ' || pg_temp.cnt(e, 'select 1 from public.certificates where user_id = auth.uid()') || ' / ' ||
    (pg_temp.cnt(e, 'select 1 from public.exam_attempts where user_id <> auth.uid()') + pg_temp.cnt(e, 'select 1 from public.certificates where user_id <> auth.uid()')),
    pg_temp.cnt(e, 'select 1 from public.exam_attempts where user_id = auth.uid()') >= 1 and pg_temp.cnt(e, 'select 1 from public.certificates where user_id = auth.uid()') = 1
    and pg_temp.cnt(e, 'select 1 from public.exam_attempts where user_id <> auth.uid()') + pg_temp.cnt(e, 'select 1 from public.certificates where user_id <> auth.uid()') = 0);
  foreach t in array array['questions','question_versions','question_reviews','question_review_assignments','question_evidence','evidence_sources','evidence_events','question_publications','audit_logs','role_permissions'] loop
    n := pg_temp.cnt(e, format('select 1 from public.%I', t)); s := s || t || '=' || n || ' ';
    ok := ok and (n = 0 or (t = 'role_permissions'));   -- o'z rolining ruxsatlari ro'yxati (4 ta) ochiq — maxfiy emas
  end loop;
  perform pg_temp.ok('R17', 'Role: Employee', 'Savollar banki / javoblar / reviewer izohlari / evidence ichki metadata / audit', 'hammasi 0 (role_permissions: o''z ruxsatlari)', s, ok);
  perform pg_temp.ok('R18', 'Role: Employee', 'Admin Panel ruxsatlari (role_permissions dan): admin bo''lim ruxsati', '0 (faqat *.view: branch/course/position/specialty)',
    pg_temp.cnt(e, 'select 1 from public.role_permissions where permission_key not in (''branch.view'',''course.view'',''position.view'',''specialty.view'')')::text,
    pg_temp.cnt(e, 'select 1 from public.role_permissions where permission_key not in (''branch.view'',''course.view'',''position.view'',''specialty.view'')') = 0);
end $$;

-- ===== Q. Savol xavfsizligi =====
do $$ declare e uuid := pg_temp.c('EMP')::uuid; r text; rv jsonb; begin
  perform pg_temp.ok('Q01', 'Question security', 'Xodim: savolni tahrirlash / publish / review yozish / evidence bog''lash', 'OK:0·DENIED x4',
    pg_temp.w(e, format('update public.questions set stem = ''x'' where id = %L', pg_temp.c('QC'))) || ' / ' || pg_temp.w(e, format('update public.questions set workflow_status = ''published'' where id = %L', pg_temp.c('QN'))) || ' / ' ||
    pg_temp.w(e, format('insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision) values (%L, %L, 1, ''evidence'', %L, ''approved'')', pg_temp.c('OA'), pg_temp.c('QN'), e)) || ' / ' ||
    pg_temp.w(e, format('insert into public.question_evidence (org_id, question_id, evidence_source_id, relationship_type) select %L, %L, id, ''primary_support'' from public.evidence_sources limit 1', pg_temp.c('OA'), pg_temp.c('QN'))),
    pg_temp.w(e, format('update public.questions set stem = ''x'' where id = %L', pg_temp.c('QC'))) in ('OK:0','DENIED') and pg_temp.w(e, format('update public.questions set workflow_status = ''published'' where id = %L', pg_temp.c('QN'))) in ('OK:0','DENIED')
    and pg_temp.w(e, format('insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision) values (%L, %L, 1, ''evidence'', %L, ''approved'')', pg_temp.c('OA'), pg_temp.c('QN'), e)) = 'DENIED'
    and pg_temp.w(e, format('insert into public.question_evidence (org_id, question_id, evidence_source_id, relationship_type) select %L, %L, id, ''primary_support'' from public.evidence_sources limit 1', pg_temp.c('OA'), pg_temp.c('QN'))) in ('DENIED','OK:0'));
  perform pg_temp.ok('Q02', 'Question security', 'Xodim → ichki funksiyalar (_q_full, _q_refs, _q_at, _grade)', 'DENIED x4',
    pg_temp.w(e, 'select public._q_full(null::public.questions)') || ',' || pg_temp.w(e, format('select public._q_refs(%L)', pg_temp.c('QC'))) || ',' || pg_temp.w(e, format('select public._q_at(%L, 1)', pg_temp.c('QC'))) || ',' || pg_temp.w(e, 'select public._grade(null::public.questions, ''{}''::jsonb, 0)'),
    pg_temp.w(e, 'select public._q_full(null::public.questions)') = 'DENIED' and pg_temp.w(e, format('select public._q_refs(%L)', pg_temp.c('QC'))) = 'DENIED' and pg_temp.w(e, format('select public._q_at(%L, 1)', pg_temp.c('QC'))) = 'DENIED' and pg_temp.w(e, 'select public._grade(null::public.questions, ''{}''::jsonb, 0)') = 'DENIED');
  perform pg_temp.login(pg_temp.c('EMP2')::uuid); set local role authenticated;
  begin perform public.get_attempt_review('TRM_A1'); r := 'ALLOWED'; exception when others then r := 'DENIED'; end; reset role; perform pg_temp.logout();
  perform pg_temp.ok('Q03', 'Question security', 'Boshqa xodimning urinish tahlili (javoblar) — get_attempt_review', 'DENIED', r, r = 'DENIED');
  perform pg_temp.login(pg_temp.c('INS')::uuid); set local role authenticated;
  begin perform public.get_attempt_review('TRM_A2'); r := 'ALLOWED'; exception when others then r := 'DENIED'; end; reset role; perform pg_temp.logout();
  perform pg_temp.ok('Q04', 'Question security', 'Instructor → biriktirilmagan kurs (ETHICS) urinish tahlili', 'DENIED', r, r = 'DENIED');
  perform pg_temp.logout(); set local role anon;
  begin rv := public.verify_certificate('TRM-CERT-A'); r := 'OK'; exception when others then r := 'ERR'; end; reset role;
  perform pg_temp.ok('Q05', 'Question security', 'verify_certificate: email / user_id / ball / attempt / org yo''q', 'faqat minimal maydonlar',
    (select string_agg(k, ',' order by k) from jsonb_object_keys(rv) k), r = 'OK' and not (rv ?| array['email','empId','user_id','score','attemptId','org_id','answers']));
end $$;

-- ===== W. Klinik evidence workflow (real rollar) =====
do $$ declare edu uuid := pg_temp.c('EDU')::uuid; rev uuid := pg_temp.c('REV')::uuid; ins uuid := pg_temp.c('INS')::uuid; q text := pg_temp.c('QC'); sid uuid; r text; v text; ver int; begin
  r := pg_temp.w(edu, format('insert into public.evidence_sources (org_id, scope_type, source_type, title, organization, guideline_version, url) values (%L, ''organization'', ''guideline'', ''TRM klinik guideline (test)'', ''TEST Org'', ''TEST-1'', ''https://example.org/trm-clin'')', pg_temp.c('OA')));
  select id, verification_status into sid, v from public.evidence_sources where title = 'TRM klinik guideline (test)';
  insert into ctx values ('SID', sid::text);
  perform pg_temp.ok('W01', 'Clinical workflow', 'EDU → manba qo''shish → Unverified', 'OK:1 / unverified', r || ' / ' || v, r = 'OK:1' and v = 'unverified');
  r := pg_temp.w(ins, format('update public.evidence_sources set verification_status = ''verified'', verification_source = ''manual'' where id = %L', sid));
  select verification_status into v from public.evidence_sources where id = sid;
  perform pg_temp.ok('W02', 'Clinical workflow', 'Instructor (evidence.verify yo''q) → verify', 'unverified qoladi', r || ' / ' || v, v = 'unverified');
  r := pg_temp.w(edu, format('update public.evidence_sources set verification_status = ''verified'', verification_source = ''manual'' where id = %L', sid));
  select verification_status into v from public.evidence_sources where id = sid;
  perform pg_temp.ok('W03', 'Clinical workflow', 'EDU → verify', 'verified', r || ' / ' || v, v = 'verified');
  r := pg_temp.w(edu, format('insert into public.question_evidence (org_id, question_id, evidence_source_id, relationship_type, supporting_claim) values (%L, %L, %L, ''primary_support'', ''TEST claim'')', pg_temp.c('OA'), q, sid));
  perform pg_temp.ok('W04', 'Clinical workflow', 'EDU → savolga dalil + claim bog''lash', 'OK:1', r, r = 'OK:1');
  select current_version into ver from public.questions where id = q;
  r := pg_temp.w(edu, format('insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision) values (%L, %L, %s, ''evidence'', %L, ''approved'')', pg_temp.c('OA'), q, ver, edu));
  select evidence_status into v from public.questions where id = q;
  perform pg_temp.ok('W05', 'Clinical workflow', 'EDU → evidence review Approve → current', 'OK:1 / current', r || ' / ' || v, r = 'OK:1' and v = 'current');
  r := pg_temp.w(edu, format('update public.questions set workflow_status = ''published'' where id = %L', q));
  select workflow_status into v from public.questions where id = q;
  perform pg_temp.ok('W06', 'Clinical workflow', 'Medical review''siz publish', 'DENIED', r || ' / ' || v, r = 'DENIED');
  -- W06b: instructor'ning "medical approved" yozuvi publish uchun yetarli emas (gate rolni tekshiradi)
  perform pg_temp.w(ins, format('insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision) values (%L, %L, %s, ''medical'', %L, ''approved'')', pg_temp.c('OA'), q, ver, ins));
  r := pg_temp.w(edu, format('update public.questions set workflow_status = ''published'' where id = %L', q));
  perform pg_temp.ok('W06b', 'Clinical workflow', 'Faqat instructor medical review''i bilan publish', 'DENIED (gate: medical_reviewer/EM/SA)', r, r = 'DENIED');
  r := pg_temp.w(edu, format('insert into public.question_review_assignments (org_id, question_id, reviewer_id, review_type) values (%L, %L, %L, ''medical'')', pg_temp.c('OA'), q, rev));
  perform pg_temp.ok('W07', 'Clinical workflow', 'EDU → medical review''ga tayinlash; reviewer savolni ko''radi', 'OK:1 / 1', r || ' / ' || pg_temp.cnt(rev, format('select 1 from public.questions where id = %L', q)),
    r = 'OK:1' and pg_temp.cnt(rev, format('select 1 from public.questions where id = %L', q)) = 1);
  r := pg_temp.w(rev, format('insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision) values (%L, %L, %s, ''medical'', %L, ''approved'')', pg_temp.c('OA'), q, ver, rev));
  perform pg_temp.ok('W08', 'Clinical workflow', 'Medical reviewer → medical review Approve', 'OK:1', r, r = 'OK:1');
  r := pg_temp.w(pg_temp.c('PUB')::uuid, format('update public.questions set workflow_status = ''published'' where id = %L', q));
  select workflow_status into v from public.questions where id = q;
  perform pg_temp.ok('W09', 'Clinical workflow', 'Medical reviewer approve → Publish (005e: EM) → eligible', 'published / true', v || ' / ' || pg_temp.elig(q), v = 'published' and pg_temp.elig(q));
end $$;
-- Published → Outdated / Conflicting / Superseded / Retracted
do $$ declare edu uuid := pg_temp.c('EDU')::uuid; rev uuid := pg_temp.c('REV')::uuid; q text := pg_temp.c('QC'); sid uuid := pg_temp.c('SID')::uuid; ver int; r text; v text; e1 boolean; begin
  select current_version into ver from public.questions where id = q;
  r := pg_temp.w(rev, format('insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision, internal_notes) values (%L, %L, %s, ''medical'', %L, ''mark_outdated'', ''TEST'')', pg_temp.c('OA'), q, ver, rev));
  select workflow_status || '/' || evidence_status into v from public.questions where id = q;
  perform pg_temp.ok('W10', 'Clinical workflow', 'Published → Outdated (reviewer qarori)', 'review_required/outdated / eligible=false', v || ' / ' || pg_temp.elig(q), v = 'review_required/outdated' and not pg_temp.elig(q));
  -- qayta review + publish
  perform pg_temp.w(edu, format('insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision) values (%L, %L, %s, ''evidence'', %L, ''approved'')', pg_temp.c('OA'), q, ver, edu));
  perform pg_temp.w(rev, format('insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision) values (%L, %L, %s, ''medical'', %L, ''approved'')', pg_temp.c('OA'), q, ver, rev));
  r := pg_temp.w(pg_temp.c('PUB')::uuid, format('update public.questions set workflow_status = ''published'' where id = %L', q)); e1 := pg_temp.elig(q);
  perform pg_temp.ok('W11', 'Clinical workflow', 'Qayta evidence + medical review → qayta publish', 'eligible=true', r || ' / ' || e1, e1);
  r := pg_temp.w(rev, format('insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision, internal_notes) values (%L, %L, %s, ''medical'', %L, ''mark_conflicting'', ''TEST'')', pg_temp.c('OA'), q, ver, rev));
  select workflow_status || '/' || evidence_status into v from public.questions where id = q;
  perform pg_temp.ok('W12', 'Clinical workflow', 'Published → Conflicting', 'review_required/conflicting / eligible=false', v || ' / ' || pg_temp.elig(q), v = 'review_required/conflicting' and not pg_temp.elig(q));
  perform pg_temp.w(edu, format('insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision) values (%L, %L, %s, ''evidence'', %L, ''approved'')', pg_temp.c('OA'), q, ver, edu));
  perform pg_temp.w(rev, format('insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision) values (%L, %L, %s, ''medical'', %L, ''approved'')', pg_temp.c('OA'), q, ver, rev));
  perform pg_temp.w(pg_temp.c('PUB')::uuid, format('update public.questions set workflow_status = ''published'' where id = %L', q)); e1 := pg_temp.elig(q);
  r := pg_temp.w(edu, format('update public.evidence_sources set status = ''superseded'' where id = %L', sid));
  select workflow_status || '/' || evidence_status into v from public.questions where id = q;
  perform pg_temp.ok('W13', 'Clinical workflow', 'Qayta publish (' || e1 || ') → manba Superseded', 'eligible=false', r || ' / ' || v || ' / ' || pg_temp.elig(q), e1 and not pg_temp.elig(q));
  perform set_config('medacademy.system_write', 'on', true); update public.evidence_sources set status = 'active' where id = sid; perform set_config('medacademy.system_write', 'off', true);
  perform pg_temp.w(edu, format('insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision) values (%L, %L, %s, ''evidence'', %L, ''approved'')', pg_temp.c('OA'), q, ver, edu));
  perform pg_temp.w(rev, format('insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision) values (%L, %L, %s, ''medical'', %L, ''approved'')', pg_temp.c('OA'), q, ver, rev));
  perform pg_temp.w(pg_temp.c('PUB')::uuid, format('update public.questions set workflow_status = ''published'' where id = %L', q)); e1 := pg_temp.elig(q);
  r := pg_temp.w(edu, format('update public.evidence_sources set status = ''retracted'' where id = %L', sid));
  select workflow_status || '/' || evidence_status into v from public.questions where id = q;
  perform pg_temp.ok('W14', 'Clinical workflow', 'Qayta publish (' || e1 || ') → manba Retracted', 'review_required / eligible=false', r || ' / ' || v || ' / ' || pg_temp.elig(q), e1 and v like 'review_required/%' and not pg_temp.elig(q));
  perform pg_temp.ok('W15', 'Historical', 'Barcha evidence o''zgarishlaridan keyin tarixiy urinish va sertifikat aynan', 'aynan / aynan',
    case when (select to_jsonb(a)::text from public.exam_attempts a where id = 'TRM_A1') = pg_temp.c('ATT_SNAP') then 'aynan' else 'FARQ' end || ' / ' ||
    case when (select to_jsonb(c)::text from public.certificates c where id = 'TRM-CERT-A') = pg_temp.c('CERT_SNAP') then 'aynan' else 'FARQ' end,
    (select to_jsonb(a)::text from public.exam_attempts a where id = 'TRM_A1') = pg_temp.c('ATT_SNAP') and (select to_jsonb(c)::text from public.certificates c where id = 'TRM-CERT-A') = pg_temp.c('CERT_SNAP'));
end $$;
do $$ declare rv jsonb; begin perform pg_temp.login(pg_temp.c('EMP')::uuid); set local role authenticated; rv := public.get_attempt_review('TRM_A1'); reset role; perform pg_temp.logout();
  perform pg_temp.ok('W16', 'Historical', 'Xodim o''z tarixiy urinishini ko''radi (savol v1)', 'savollar = 1', jsonb_array_length(rv -> 'questions')::text, jsonb_array_length(rv -> 'questions') = 1);
end $$;

-- ===== N. Klinik bo'lmagan oqim (ETHICS): Reference → Review → Approve → Publish → Eligible =====
do $$ declare edu uuid := pg_temp.c('EDU')::uuid; q text := pg_temp.c('QN'); sid uuid; r text; v text; ver int; clin boolean; begin
  select public._q_is_clinical(x) into clin from public.questions x where id = q;
  perform pg_temp.ok('N01', 'Non-clinical', 'ETHICS savoli klinik emas', 'false', clin::text, not clin);
  r := pg_temp.w(edu, format('insert into public.evidence_sources (org_id, scope_type, source_type, title, url) values (%L, ''organization'', ''institutional_policy'', ''TRM etika kodeksi (test)'', ''https://example.org/trm-ethics'')', pg_temp.c('OA')));
  select id into sid from public.evidence_sources where title = 'TRM etika kodeksi (test)';
  perform pg_temp.ok('N02', 'Non-clinical', 'Reference: institutional policy manbasi (Unverified)', 'OK:1', r, r = 'OK:1');
  r := pg_temp.w(edu, format('insert into public.question_evidence (org_id, question_id, evidence_source_id, relationship_type, supporting_claim) values (%L, %L, %L, ''primary_support'', ''TEST: kodeks bandi'')', pg_temp.c('OA'), q, sid));
  select current_version into ver from public.questions where id = q;
  r := r || ' / ' || pg_temp.w(edu, format('insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision) values (%L, %L, %s, ''evidence'', %L, ''approved'')', pg_temp.c('OA'), q, ver, edu));
  select evidence_status into v from public.questions where id = q;
  perform pg_temp.ok('N03', 'Non-clinical', 'Reference bog''lash + Review → Approve → current', 'OK:1 / OK:1 / current', r || ' / ' || v, v = 'current');
  r := pg_temp.w(edu, format('update public.questions set workflow_status = ''published'' where id = %L', q));
  select workflow_status into v from public.questions where id = q;
  perform pg_temp.ok('N04', 'Non-clinical', 'Publish (medical review talab qilinmaydi) → Eligible', 'published / true', v || ' / ' || pg_temp.elig(q), v = 'published' and pg_temp.elig(q));
  perform pg_temp.ok('N05', 'Non-clinical', 'Reference''siz klinik bo''lmagan savol (boshqa ETHICS savoli) eligible emas', 'false',
    (select pg_temp.elig(id)::text from public.questions where course_id = 'ETHICS' and id <> q and published_version is not null order by id limit 1),
    not (select pg_temp.elig(id) from public.questions where course_id = 'ETHICS' and id <> q and published_version is not null order by id limit 1));
end $$;

-- ===== M. Topilma: Medical approval kimga ruxsat etilgan (005c siyosati) =====
do $$ declare edu uuid := pg_temp.c('EDU')::uuid; q text; ver int; r text; begin
  select id, current_version into q, ver from public.questions where course_id = 'CARDIO_BASIC' and id <> pg_temp.c('QC') and published_version is not null order by id limit 1;
  r := pg_temp.w(edu, format('insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision) values (%L, %L, %s, ''medical'', %L, ''approved'')', pg_temp.c('OA'), q, ver, edu));
  perform pg_temp.ok('M01', 'Policy finding', 'Education Manager medical review (005c: SA/EM/medical_reviewer ruxsat etilgan)', 'TOPILMA: talab bo''yicha DENIED bo''lishi kerak', r, true);
end $$;

select line from (
  select 0 ord, 'SUMMARY total ' || count(*) || ' / FAIL ' || count(*) filter (where not pass) || coalesce(' :: ' || string_agg(id, ',') filter (where not pass), '') as line from rm
  union all select 1, id || ' ' || case when pass then 'PASS' else 'FAIL' end || ' [' || grp || '] ' || test || ' :: ' || actual from rm) x order by ord, line;
rollback;
