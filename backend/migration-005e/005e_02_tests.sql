-- MedAcademy · 005e xavfsizlik test to'plami (lokal PGlite va staging uchun bir xil fayl).
-- Mavjud test akkauntlari (staging) bilan; yangi auth akkaunt yaratilmaydi. Hammasi BITTA tranzaksiyada, oxirida ROLLBACK.
-- Har bir foydalanuvchi so'rovi haqiqiy RLS / trigger / RPC orqali JWT claim'lari bilan bajariladi.
begin;
do $$ begin
  if not exists (select 1 from public.schema_migrations where version = '005e') then raise exception '005e qo''llanmagan'; end if;
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
do $$ declare i int; q text; begin
  perform pg_temp.logout();
  insert into t5ctx select 'BASE', json_build_object('attempts', (select count(*) from public.exam_attempts), 'certs', (select count(*) from public.certificates),
    'reviews', (select count(*) from public.question_reviews), 'qe', (select count(*) from public.question_evidence), 'qv', (select count(*) from public.question_versions),
    'att_md5', (select md5(coalesce(string_agg(to_jsonb(a)::text, '' order by a.id), '')) from public.exam_attempts a),
    'cert_md5', (select md5(coalesce(string_agg(to_jsonb(c)::text, '' order by c.id), '')) from public.certificates c),
    'rev_md5', (select md5(coalesce(string_agg(to_jsonb(r)::text, '' order by r.id), '')) from public.question_reviews r),
    'qv_md5', (select md5(coalesce(string_agg(to_jsonb(v)::text, '' order by v.question_id, v.version_no), '')) from public.question_versions v))::text;
  perform pg_temp.sys($q$
    insert into public.evidence_sources (org_id, scope_type, source_type, title, organization, guideline_version, url, verification_status, verification_source, verified_at)
      values ('00000000-0000-0000-0000-000000000001', 'organization', 'guideline', 'T5E Org A guideline (test)', 'T5E', '1', 'https://example.org/t5e-a', 'verified', 'manual', now()),
             ('00000000-0000-0000-0000-000000000001', 'organization', 'guideline', 'T5E Org A unverified (test)', 'T5E', '1', 'https://example.org/t5e-u', 'unverified', null, null),
             ('0000000b-0000-0000-0000-00000000000b', 'organization', 'guideline', 'T5E Org B guideline (test)', 'T5E', '1', 'https://example.org/t5e-b', 'verified', 'manual', now()),
             (null, 'global', 'textbook', 'T5E global darslik (test)', 'T5E', '1', 'https://example.org/t5e-g', 'verified', 'manual', now())$q$);
  insert into t5ctx select 'SRC_A', id::text from public.evidence_sources where title = 'T5E Org A guideline (test)';
  insert into t5ctx select 'SRC_U', id::text from public.evidence_sources where title = 'T5E Org A unverified (test)';
  insert into t5ctx select 'SRC_B', id::text from public.evidence_sources where title = 'T5E Org B guideline (test)';
  insert into t5ctx select 'SRC_G', id::text from public.evidence_sources where title = 'T5E global darslik (test)';
  -- Klinik (CARDIO_BASIC: instruktor biriktirilgan) va klinik bo'lmagan (ETHICS) test savollari
  for i in 1..24 loop
    q := 'T5E_C' || lpad(i::text, 2, '0');
    perform pg_temp.sys(format($q$insert into public.questions (id, org_id, course_id, type, difficulty, stem, options, answer, status, workflow_status)
      values (%L, '00000000-0000-0000-0000-000000000001', 'CARDIO_BASIC', 'single', 'medium', 'T5E klinik test savoli %s', '["a","b"]', '0', 'draft', 'draft');
      insert into public.question_evidence (org_id, question_id, evidence_source_id, relationship_type, supporting_claim) values ('00000000-0000-0000-0000-000000000001', %L, %L, 'primary_support', 'T5E');
      insert into public.question_review_assignments (org_id, question_id, reviewer_id, review_type) values ('00000000-0000-0000-0000-000000000001', %L, 'a0000000-0000-0000-0000-000000000008', 'medical')$q$,
      q, i, q, pg_temp.c('SRC_A'), q));
  end loop;
  for i in 1..6 loop
    q := 'T5E_N' || lpad(i::text, 2, '0');
    perform pg_temp.sys(format($q$insert into public.questions (id, org_id, course_id, type, difficulty, stem, options, answer, status, workflow_status)
      values (%L, '00000000-0000-0000-0000-000000000001', 'ETHICS', 'single', 'medium', 'T5E klinik bo''lmagan test savoli %s', '["a","b"]', '0', 'draft', 'draft')$q$, q, i));
  end loop;
  perform pg_temp.sys(format($q$insert into public.question_evidence (org_id, question_id, evidence_source_id, relationship_type, supporting_claim)
    select '00000000-0000-0000-0000-000000000001', id, %L, 'primary_support', 'T5E' from public.questions where id in ('T5E_N01','T5E_N03','T5E_N04','T5E_N05')$q$, pg_temp.c('SRC_A')));
  -- Org B klinik savoli
  perform pg_temp.sys(format($q$insert into public.questions (id, org_id, course_id, type, difficulty, stem, options, answer, status, workflow_status)
      values ('T5E_B1', '0000000b-0000-0000-0000-00000000000b', 'TESTB_CARDIO', 'single', 'medium', 'T5E Org B test savoli', '["a","b"]', '0', 'draft', 'draft');
      insert into public.question_evidence (org_id, question_id, evidence_source_id, relationship_type, supporting_claim) values ('0000000b-0000-0000-0000-00000000000b', 'T5E_B1', %L, 'primary_support', 'T5E');
      insert into public.question_review_assignments (org_id, question_id, reviewer_id, review_type) values ('0000000b-0000-0000-0000-00000000000b', 'T5E_B1', 'b0000000-0000-0000-0000-000000000002', 'medical')$q$, pg_temp.c('SRC_B')));
  -- Tarixiy urinish + sertifikat (o'zgarmasligi tekshiriladi)
  perform pg_temp.sys($q$
    insert into public.exam_attempts (id, org_id, user_id, course_id, kind, qids, answers, results, score, passed, started_at, finished_at, question_versions)
      values ('T5E_ATT', '00000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000006', 'CARDIO_BASIC', 'final', array['T5E_C20'], '{"T5E_C20":0}', '{"T5E_C20":true}', 100, true,
              now() - interval '1 day', now() - interval '1 day', '{"T5E_C20":1}');
    insert into public.certificates (id, org_id, user_id, course_id, course_title, name, position, department, score, attempt_id, issued_at)
      values ('T5E-CERT', '00000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000006', 'CARDIO_BASIC', 'Cardio', 'Test Employee', 'Hamshira', 'Kardiologiya', 100, 'T5E_ATT', now() - interval '1 day')$q$);
  insert into t5ctx select 'ATT_SNAP', to_jsonb(a)::text from public.exam_attempts a where id = 'T5E_ATT';
  insert into t5ctx select 'CERT_SNAP', to_jsonb(c)::text from public.certificates c where id = 'T5E-CERT';
end $$;
-- evidence tayyor (EM evidence approve) yordamchisi
create function pg_temp.evready(q text) returns text language sql as $$ select pg_temp.rv(pg_temp.u('EDU'), q, 'evidence', 'approved') $$;

-- ===== A. Ruxsat matritsasi (STEP 3) =====
do $$ declare r text; k int; begin
  perform pg_temp.ok('A01', 'Permission matrix', 'permissions: medical.review mavjud', '1', (select count(*)::text from public.permissions where key = 'medical.review'));
  perform pg_temp.ok('A02', 'Permission matrix', 'role_permissions: medical.review rollari (barcha tashkilotlar)', 'medical_reviewer',
    (select string_agg(distinct role, ',') from public.role_permissions where permission_key = 'medical.review'));
  perform pg_temp.ok('A03', 'Permission matrix', 'Har tashkilotda MR → medical.review (dublikatsiz)', 'true',
    ((select count(*) from public.role_permissions where permission_key = 'medical.review') = (select count(*) from public.organizations))::text);
  perform pg_temp.ok('A04', 'Permission matrix', 'medical_reviewer → question.publish qatorlari', '0',
    (select count(*)::text from public.role_permissions where role = 'medical_reviewer' and permission_key = 'question.publish'));
  perform pg_temp.ok('A05', 'Permission matrix', 'EM: evidence.review / evidence.verify / question.publish saqlanadi, medical.review yo''q', 'evidence.review,evidence.verify,question.publish',
    (select string_agg(permission_key, ',' order by permission_key) from public.role_permissions where org_id = pg_temp.u('OA') and role = 'education_manager'
       and permission_key in ('evidence.review','evidence.verify','question.publish','medical.review')));
  r := '';
  for k in 1..7 loop
    perform pg_temp.login(pg_temp.u((array['SA','REV','EDU','INS','HR','HEAD','EMP'])[k]));
    r := r || case when k > 1 then '/' else '' end || case when public.has_perm('medical.review') then 't' else 'f' end;
  end loop;
  perform pg_temp.ok('A06', 'Permission matrix', 'has_perm(medical.review): SA/MR/EM/INS/HR/HEAD/EMP', 't/t/f/f/f/f/f', r);
  perform pg_temp.logout();
  -- CHECK constraint: hatto SA (settings.manage) ham boshqa rolga berolmaydi
  r := pg_temp.w(pg_temp.u('SA'), format('insert into public.role_permissions (org_id, role, permission_key) values (%L, ''education_manager'', ''medical.review'')', pg_temp.c('OA')));
  perform pg_temp.ok('A07', 'Permission matrix', 'SA API: EM ga medical.review berish', 'DENIED', r);
  r := pg_temp.w(pg_temp.u('SA'), format('insert into public.role_permissions (org_id, role, permission_key) values (%L, ''instructor'', ''medical.review'')', pg_temp.c('OA')));
  perform pg_temp.ok('A08', 'Permission matrix', 'SA API: instructor ga medical.review berish', 'DENIED', r);
  r := pg_temp.w(pg_temp.u('SA'), format('insert into public.role_permissions (org_id, role, permission_key) values (%L, ''medical_reviewer'', ''question.publish'')', pg_temp.c('OA')));
  perform pg_temp.ok('A09', 'Permission matrix', 'SA API: MR ga question.publish qaytarish', 'DENIED', r);
  begin
    insert into public.role_permissions (org_id, role, permission_key) values (pg_temp.u('OA'), 'hr', 'medical.review'); r := 'ALLOWED';
  exception when check_violation then r := 'CHECK_VIOLATION'; end;
  perform pg_temp.ok('A10', 'Permission matrix', 'Platforma SQL: HR ga medical.review (CHECK constraint)', 'CHECK_VIOLATION', r);
  r := pg_temp.w(pg_temp.u('HR'), format('insert into public.role_permissions (org_id, role, permission_key) values (%L, ''hr'', ''question.publish'')', pg_temp.c('OA')));
  perform pg_temp.ok('A11', 'Permission matrix', 'HR API: o''ziga ruxsat qo''shish (settings.manage yo''q)', 'DENIED', r);
  -- Yangi tashkilot standart matritsasi (seed_org_defaults_005) — tranzaksiya ichida, ROLLBACK
  insert into public.organizations (id, name, code) values ('0000000e-0000-0000-0000-00000000005e', 'T5E temp org', 'T5ETMP');
  perform pg_temp.ok('A12', 'Permission matrix', 'Yangi tashkilot: MR → medical.review bor, question.publish yo''q; EM → medical.review yo''q', '1/0/0',
    (select count(*) filter (where role = 'medical_reviewer' and permission_key = 'medical.review') || '/' || count(*) filter (where role = 'medical_reviewer' and permission_key = 'question.publish')
       || '/' || count(*) filter (where role = 'education_manager' and permission_key = 'medical.review')
     from public.role_permissions where org_id = '0000000e-0000-0000-0000-00000000005e'));
  perform pg_temp.ok('A13', 'Permission matrix', 'anon: question_reviews INSERT / role_permissions INSERT', 'DENIED/DENIED',
    pg_temp.wa(format('insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision) values (%L, ''T5E_C01'', 1, ''medical'', %L, ''approved'')', pg_temp.c('OA'), pg_temp.c('REV')))
    || '/' || pg_temp.wa(format('insert into public.role_permissions (org_id, role, permission_key) values (%L, ''hr'', ''medical.review'')', pg_temp.c('OA'))));
end $$;

-- ===== B. Medical review yaratish (STEP 6): 7 rol, to'g'ridan-to'g'ri jadval (RLS + trigger) =====
do $$ begin
  perform pg_temp.ok('B01', 'Medical review creation', 'Super Admin → medical review', 'OK:1', pg_temp.rv(pg_temp.u('SA'), 'T5E_C01', 'medical', 'changes_requested'));
  perform pg_temp.ok('B02', 'Medical review creation', 'Medical Reviewer → medical review', 'OK:1', pg_temp.rv(pg_temp.u('REV'), 'T5E_C01', 'medical', 'changes_requested'));
  perform pg_temp.ok('B03', 'Medical review creation', 'Education Manager → medical review', 'DENIED', pg_temp.rv(pg_temp.u('EDU'), 'T5E_C01', 'medical', 'approved'));
  perform pg_temp.ok('B04', 'Medical review creation', 'Instructor (biriktirilgan kurs) → medical review', 'DENIED', pg_temp.rv(pg_temp.u('INS'), 'T5E_C01', 'medical', 'approved'));
  perform pg_temp.ok('B05', 'Medical review creation', 'Department Head → medical review', 'DENIED', pg_temp.rv(pg_temp.u('HEAD'), 'T5E_C01', 'medical', 'approved'));
  perform pg_temp.ok('B06', 'Medical review creation', 'HR → medical review', 'DENIED', pg_temp.rv(pg_temp.u('HR'), 'T5E_C01', 'medical', 'approved'));
  perform pg_temp.ok('B07', 'Medical review creation', 'Employee → medical review', 'DENIED', pg_temp.rv(pg_temp.u('EMP'), 'T5E_C01', 'medical', 'approved'));
  perform pg_temp.ok('B08', 'Medical review creation', 'Instructor review_type=instructor (approved) — ruxsat, lekin medical emas', 'OK:1', pg_temp.rv(pg_temp.u('INS'), 'T5E_C01', 'instructor', 'approved'));
  perform pg_temp.ok('B09', 'Medical review creation', 'Yozilgan rol (reviewer_role_at_creation): SA, MR, INS yozuvlari', 'instructor,medical_reviewer,super_admin',
    (select string_agg(distinct reviewer_role_at_creation, ',' order by reviewer_role_at_creation) from public.question_reviews where question_id = 'T5E_C01'));
  -- reviewer_id soxtalashtirish: INS MR nomidan instructor review yozadi → reviewer_id = INS
  perform pg_temp.w(pg_temp.u('INS'), format('insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision, internal_notes) values (%L, ''T5E_C01'', 1, ''instructor'', %L, ''approved'', ''T5E-spoof'')', pg_temp.c('OA'), pg_temp.c('REV')));
  perform pg_temp.ok('B10', 'Medical review creation', 'reviewer_id / rol soxtalashtirish (INS → MR nomidan)', 'a0000000-0000-0000-0000-000000000004/instructor',
    (select reviewer_id || '/' || reviewer_role_at_creation from public.question_reviews where internal_notes = 'T5E-spoof'));
  perform pg_temp.ok('B11', 'Medical review creation', 'MR → eski versiya (v0) uchun review', 'DENIED',
    pg_temp.w(pg_temp.u('REV'), format('insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision) values (%L, ''T5E_C01'', 0, ''medical'', %L, ''approved'')', pg_temp.c('OA'), pg_temp.c('REV'))));
  perform pg_temp.ok('B12', 'Medical review creation', 'HR → psychometric / editorial review', 'DENIED/DENIED',
    pg_temp.rv(pg_temp.u('HR'), 'T5E_C01', 'psychometric', 'approved') || '/' || pg_temp.rv(pg_temp.u('HR'), 'T5E_C01', 'editorial', 'approved'));
  perform pg_temp.ok('B13', 'Medical review creation', 'MR tayinlanmagan savol (ko''rinmaydi) → medical review (0 qator yoki rad)', 'DENIED|OK:0',
    pg_temp.w(pg_temp.u('REV'), format('insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision) select org_id, id, current_version, ''medical'', %L, ''approved'' from public.questions where id = %L',
      pg_temp.c('REV'), (select id from public.questions where course_id = 'CARDIO_BASIC' and id not like 'T5E%' order by id limit 1))) || '');
  -- RPC yo'li: authenticated chaqira oladigan funksiyalardan hech biri question_reviews'ga yozmaydi / ruxsat bermaydi
  perform pg_temp.ok('B14', 'Medical review creation', 'RPC: authenticated EXECUTE + question_reviews INSERT qiluvchi funksiyalar', '0',
    (select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and p.prorettype <> 'trigger'::regtype
       and has_function_privilege('authenticated', p.oid, 'execute') and p.prosrc ilike '%insert into public.question_reviews%'));
  perform pg_temp.ok('B15', 'Medical review creation', 'RPC: authenticated _q_latest_review() ni chaqira olmaydi (internal)', 'false',
    has_function_privilege('authenticated', 'public._q_latest_review(text,int,text)', 'execute')::text);
end $$;

-- ===== C. Evidence review va manba tekshiruvi (STEP 11, Qaror 4) =====
do $$ begin
  perform pg_temp.ok('C01', 'Evidence review', 'EM → evidence review (approved) → evidence_status', 'OK:1 current',
    pg_temp.evready('T5E_C02') || ' ' || split_part(pg_temp.st('T5E_C02'), '/', 2));
  perform pg_temp.ok('C02', 'Evidence review', 'EM → manba tekshiruvi (verification_status = verified)', 'OK:1',
    pg_temp.w(pg_temp.u('EDU'), format('update public.evidence_sources set verification_status = ''verified'', verification_source = ''manual'' where id = %L', pg_temp.c('SRC_U'))));
  perform pg_temp.ok('C03', 'Evidence review', 'Instructor → evidence review', 'DENIED', pg_temp.rv(pg_temp.u('INS'), 'T5E_C03', 'evidence', 'approved'));
  perform pg_temp.ok('C04', 'Evidence review', 'Instructor → manba tekshiruvi', 'DENIED',
    pg_temp.w(pg_temp.u('INS'), format('update public.evidence_sources set verification_status = ''unverified'' where id = %L', pg_temp.c('SRC_U'))));
  perform pg_temp.ok('C05', 'Evidence review', 'MR → evidence review (evidence.review saqlanadi)', 'OK:1', pg_temp.rv(pg_temp.u('REV'), 'T5E_C03', 'evidence', 'approved'));
  perform pg_temp.ok('C06', 'Evidence review', 'HR / HEAD / EMP → evidence review', 'DENIED/DENIED/DENIED',
    pg_temp.rv(pg_temp.u('HR'), 'T5E_C03', 'evidence', 'approved') || '/' || pg_temp.rv(pg_temp.u('HEAD'), 'T5E_C03', 'evidence', 'approved') || '/' || pg_temp.rv(pg_temp.u('EMP'), 'T5E_C03', 'evidence', 'approved'));
end $$;

-- ===== D. Klinik nashr guard va oxirgi qaror mantiqi (STEP 7–9) =====
do $$ begin
  -- D01: medical review'siz
  perform pg_temp.evready('T5E_C04');
  perform pg_temp.ok('D01', 'Publish guard', 'Klinik: evidence OK, medical review YO''Q → EM publish', 'DENIED', pg_temp.pub(pg_temp.u('EDU'), 'T5E_C04'));
  -- D02: MR approve → EM publish
  perform pg_temp.evready('T5E_C05'); perform pg_temp.rv(pg_temp.u('REV'), 'T5E_C05', 'medical', 'approved');
  perform pg_temp.ok('D02', 'Publish guard', 'Klinik: MR approved → EM publish → yaroqli', 'OK:1 true', pg_temp.pub(pg_temp.u('EDU'), 'T5E_C05') || ' ' || pg_temp.elig('T5E_C05'));
  -- D03: Approved → Rejected
  perform pg_temp.evready('T5E_C06'); perform pg_temp.rv(pg_temp.u('REV'), 'T5E_C06', 'medical', 'approved'); perform pg_temp.rv(pg_temp.u('REV'), 'T5E_C06', 'medical', 'rejected');
  perform pg_temp.ok('D03', 'Latest decision', 'Approved → Rejected → EM publish', 'DENIED false', pg_temp.pub(pg_temp.u('EDU'), 'T5E_C06') || ' ' || pg_temp.elig('T5E_C06'));
  -- D04: Rejected → Approved
  perform pg_temp.evready('T5E_C07'); perform pg_temp.rv(pg_temp.u('REV'), 'T5E_C07', 'medical', 'rejected'); perform pg_temp.rv(pg_temp.u('REV'), 'T5E_C07', 'medical', 'approved');
  perform pg_temp.ok('D04', 'Latest decision', 'Rejected → Approved → EM publish → yaroqli', 'OK:1 true', pg_temp.pub(pg_temp.u('EDU'), 'T5E_C07') || ' ' || pg_temp.elig('T5E_C07'));
  -- D05: Approved → Approved
  perform pg_temp.evready('T5E_C08'); perform pg_temp.rv(pg_temp.u('REV'), 'T5E_C08', 'medical', 'approved'); perform pg_temp.rv(pg_temp.u('SA'), 'T5E_C08', 'medical', 'approved');
  perform pg_temp.ok('D05', 'Latest decision', 'Approved → Approved (MR, SA) → EM publish → yaroqli', 'OK:1 true', pg_temp.pub(pg_temp.u('EDU'), 'T5E_C08') || ' ' || pg_temp.elig('T5E_C08'));
  -- D06: Approved → changes_requested
  perform pg_temp.evready('T5E_C09'); perform pg_temp.rv(pg_temp.u('REV'), 'T5E_C09', 'medical', 'approved'); perform pg_temp.rv(pg_temp.u('REV'), 'T5E_C09', 'medical', 'changes_requested');
  perform pg_temp.ok('D06', 'Latest decision', 'Approved → Changes requested → EM publish', 'DENIED', pg_temp.pub(pg_temp.u('EDU'), 'T5E_C09'));
  -- D07: MR publish (barcha shartlar bajarilgan)
  perform pg_temp.evready('T5E_C10'); perform pg_temp.rv(pg_temp.u('REV'), 'T5E_C10', 'medical', 'approved');
  perform pg_temp.ok('D07', 'MR cannot publish', 'MR approved → MR o''zi publish', 'DENIED', pg_temp.pub(pg_temp.u('REV'), 'T5E_C10'));
  perform pg_temp.ok('D08', 'MR cannot publish', 'MR: legacy status=approved / draft_status=publish', 'DENIED/DENIED',
    pg_temp.w(pg_temp.u('REV'), 'update public.questions set status = ''approved'' where id = ''T5E_C10''') || '/' || pg_temp.w(pg_temp.u('REV'), 'update public.questions set draft_status = ''publish'' where id = ''T5E_C10'''));
  perform pg_temp.ok('D09', 'Publish guard', 'Xuddi shu savol → SA publish', 'OK:1 true', pg_temp.pub(pg_temp.u('SA'), 'T5E_C10') || ' ' || pg_temp.elig('T5E_C10'));
  perform pg_temp.ok('D10', 'MR cannot publish', 'MR: nashr qilingan savolni nashrdan chiqarish (draft / deprecated / archived / review_required)', 'DENIED/DENIED/DENIED/DENIED',
    pg_temp.w(pg_temp.u('REV'), 'update public.questions set workflow_status = ''draft'' where id = ''T5E_C10''') || '/' ||
    pg_temp.w(pg_temp.u('REV'), 'update public.questions set workflow_status = ''deprecated'' where id = ''T5E_C10''') || '/' ||
    pg_temp.w(pg_temp.u('REV'), 'update public.questions set status = ''archived'' where id = ''T5E_C10''') || '/' ||
    pg_temp.w(pg_temp.u('REV'), 'update public.questions set workflow_status = ''review_required'' where id = ''T5E_C10'''));
  -- D11: SA medical approve → EM publish
  perform pg_temp.evready('T5E_C11'); perform pg_temp.rv(pg_temp.u('SA'), 'T5E_C11', 'medical', 'approved');
  perform pg_temp.ok('D11', 'Publish guard', 'SA medical approved → EM publish', 'OK:1', pg_temp.pub(pg_temp.u('EDU'), 'T5E_C11'));
  -- D12: nashrdan keyin MR rad etadi → review_required, yaroqsiz, qayta nashr yo'q
  perform pg_temp.ok('D12', 'Latest decision', 'Nashr qilingan (D02) → MR rejected → holat / yaroqlilik', 'OK:1 review_required/current/medical_rejected false',
    pg_temp.rv(pg_temp.u('REV'), 'T5E_C05', 'medical', 'rejected') || ' ' || pg_temp.st('T5E_C05') || ' ' || pg_temp.elig('T5E_C05'));
  perform pg_temp.ok('D13', 'Latest decision', 'Rad etilgandan keyin EM qayta publish', 'DENIED', pg_temp.pub(pg_temp.u('EDU'), 'T5E_C05'));
  -- D14: versiya: v1 nashr (D04), kontent o'zgaradi → v2; v1 tasdig'i v2 uchun hisoblanmaydi; v1 imtihonda qoladi
  perform pg_temp.w(pg_temp.u('EDU'), 'update public.questions set stem = stem || '' (v2)'' where id = ''T5E_C07''');
  perform pg_temp.ok('D14', 'Latest decision', 'v2 draft: v1 tasdig''i bilan v2 ni publish (draft_status=publish) / v1 yaroqli qoladimi', 'DENIED true',
    pg_temp.w(pg_temp.u('EDU'), 'update public.questions set draft_status = ''publish'' where id = ''T5E_C07''') || ' ' || pg_temp.elig('T5E_C07'));
  perform pg_temp.rv(pg_temp.u('REV'), 'T5E_C07', 'medical', 'approved');
  perform pg_temp.ok('D15', 'Latest decision', 'v2 uchun MR approved → EM publish v2 → published_version', 'OK:1 2',
    pg_temp.w(pg_temp.u('EDU'), 'update public.questions set draft_status = ''publish'' where id = ''T5E_C07''') || ' ' || pg_temp.pv('T5E_C07'));
  -- D16: himoya qatlami — tizim SQL bilan medical review'siz "published" qilingan klinik savol yangi imtihonga kirmaydi
  perform pg_temp.evready('T5E_C12'); perform pg_temp.sys('update public.questions set workflow_status = ''published'' where id = ''T5E_C12''');
  perform pg_temp.ok('D16', 'Eligibility', 'Klinik, published, evidence current, medical review YO''Q → _q_exam_eligible', 'false', pg_temp.elig('T5E_C12'));
  -- D17: verified bo'lmagan manba
  perform pg_temp.sys(format('insert into public.question_evidence (org_id, question_id, evidence_source_id, relationship_type, supporting_claim) values (%L, ''T5E_C21'', (select id from public.evidence_sources where title = ''T5E Org A unverified (test)''), ''primary_support'', ''T5E'');
    delete from public.question_evidence where question_id = ''T5E_C21'' and evidence_source_id = %L', pg_temp.c('OA'), pg_temp.c('SRC_A')));
  perform pg_temp.sys(format('update public.evidence_sources set verification_status = ''unverified'', verified_at = null where id = %L', pg_temp.c('SRC_U')));
  perform pg_temp.evready('T5E_C21'); perform pg_temp.rv(pg_temp.u('REV'), 'T5E_C21', 'medical', 'approved');
  perform pg_temp.ok('D17', 'Publish guard', 'Klinik: manba verified EMAS (medical approved bor) → EM publish', 'DENIED', pg_temp.pub(pg_temp.u('EDU'), 'T5E_C21'));
end $$;

-- ===== E. Rol tarixi (STEP 5): tarixiy rol hozirgi ruxsat bermaydi =====
do $$ begin
  -- E01: 005e'dan oldingi uslubdagi instruktor "medical" yozuvi (platforma SQL; rol = instructor) → hisoblanmaydi
  perform pg_temp.evready('T5E_C13');
  perform pg_temp.sys(format('insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision, internal_notes) values (%L, ''T5E_C13'', 1, ''medical'', %L, ''approved'', ''T5E-legacy'')', pg_temp.c('OA'), pg_temp.c('INS')));
  perform pg_temp.ok('E01', 'Role history', 'Instruktor davridagi medical approved → EM publish', 'DENIED', pg_temp.pub(pg_temp.u('EDU'), 'T5E_C13'));
  -- E02: instruktor keyin medical_reviewer bo'ladi → eski yozuv baribir hisoblanmaydi (P20)
  perform pg_temp.sys(format('update public.profiles set role = ''medical_reviewer'' where id = %L', pg_temp.c('INS')));
  perform pg_temp.ok('E02', 'Role history', 'Keyin rol medical_reviewer''ga o''zgardi → EM publish (eski yozuv)', 'DENIED', pg_temp.pub(pg_temp.u('EDU'), 'T5E_C13'));
  perform pg_temp.sys(format('update public.profiles set role = ''instructor'' where id = %L', pg_temp.c('INS')));
  -- E03: rolsiz (005e'dan oldingi) yozuv simulyatsiyasi: reviewer_role_at_creation = NULL bo'lishi mumkin emas → guard platforma SQL'ida joriy rolni yozadi
  perform pg_temp.ok('E03', 'Role history', 'Eski yozuv saqlanadi va o''zgarmas (rol: instructor)', 'instructor',
    (select reviewer_role_at_creation from public.question_reviews where internal_notes = 'T5E-legacy'));
  -- E04: MR tasdiqlaydi, keyin MR rolini yo'qotadi → tarixiy yozuv o'zgarmaydi (yozilgan paytda vakolatli edi)
  perform pg_temp.evready('T5E_C14'); perform pg_temp.rv(pg_temp.u('REV'), 'T5E_C14', 'medical', 'approved');
  perform pg_temp.sys(format('update public.profiles set role = ''instructor'' where id = %L', pg_temp.c('REV')));
  perform pg_temp.ok('E04', 'Role history', 'MR approved, keyin MR → instructor: tarixiy rol / EM publish', 'medical_reviewer OK:1',
    (select reviewer_role_at_creation from public.question_reviews where question_id = 'T5E_C14' and review_type = 'medical') || ' ' || pg_temp.pub(pg_temp.u('EDU'), 'T5E_C14'));
  -- E05: endi instructor bo'lgan sobiq MR yangi medical review yoza olmaydi
  perform pg_temp.ok('E05', 'Role history', 'Sobiq MR (hozir instructor) → yangi medical review', 'DENIED', pg_temp.rv(pg_temp.u('REV'), 'T5E_C14', 'medical', 'rejected'));
  perform pg_temp.sys(format('update public.profiles set role = ''medical_reviewer'' where id = %L', pg_temp.c('REV')));
  -- E06: faolsiz profil (status inactive) medical review yoza olmaydi
  perform pg_temp.sys(format('update public.profiles set status = ''inactive'' where id = %L', pg_temp.c('REV')));
  perform pg_temp.ok('E06', 'Role history', 'MR profili inactive → medical review', 'DENIED', pg_temp.rv(pg_temp.u('REV'), 'T5E_C14', 'medical', 'approved'));
  perform pg_temp.sys(format('update public.profiles set status = ''active'' where id = %L', pg_temp.c('REV')));
end $$;

-- ===== F. Klinik bo'lmagan oqim (STEP 9) =====
do $$ begin
  perform pg_temp.evready('T5E_N01');
  perform pg_temp.ok('F01', 'Non-clinical', 'ETHICS: evidence approved, medical review''siz → EM publish → yaroqli', 'OK:1 true', pg_temp.pub(pg_temp.u('EDU'), 'T5E_N01') || ' ' || pg_temp.elig('T5E_N01'));
  perform pg_temp.ok('F02', 'Non-clinical', 'ETHICS: EM evidence_exempt → publish → yaroqli (manbasiz)', 'OK:1 OK:1 true',
    pg_temp.w(pg_temp.u('EDU'), 'update public.questions set evidence_exempt = true, evidence_exempt_reason = ''T5E: institutsional etika kodeksi (test)'' where id = ''T5E_N02''') || ' ' || pg_temp.pub(pg_temp.u('EDU'), 'T5E_N02') || ' ' || pg_temp.elig('T5E_N02'));
  perform pg_temp.evready('T5E_N03');
  perform pg_temp.sys(format('insert into public.question_review_assignments (org_id, question_id, reviewer_id, review_type) values (%L, ''T5E_N03'', %L, ''evidence'')', pg_temp.c('OA'), pg_temp.c('REV')));
  perform pg_temp.ok('F03', 'Non-clinical', 'ETHICS: MR (tayinlangan, savolni ko''radi) publish → holat', 'DENIED draft', pg_temp.pub(pg_temp.u('REV'), 'T5E_N03') || ' ' || pg_temp.wf('T5E_N03'));
  perform pg_temp.ok('F04', 'Non-clinical', 'ETHICS: dalilsiz va ozod qilinmagan → EM publish', 'DENIED', pg_temp.pub(pg_temp.u('EDU'), 'T5E_N06'));
  perform pg_temp.ok('F05', 'Non-clinical', 'Klinik emas deb hisoblanadigan kurslar (domain bo''yicha, mavjud siyosat)', 'COMM,ETHICS,SALES',
    (select string_agg(c.id, ',' order by c.id) from public.courses c where c.org_id = pg_temp.u('OA') and c.id in ('ETHICS','COMM','SALES','RECEPTION_START')
       and not (c.domain = any (coalesce((select p.clinical_domains from public.content_policies p where p.org_id = c.org_id), '{medical,public_health,safety}'::text[])))));
  perform pg_temp.ok('F06', 'Non-clinical', 'Klinik savol dalildan ozod qilinmaydi (EM)', 'DENIED', pg_temp.w(pg_temp.u('EDU'), 'update public.questions set evidence_exempt = true, evidence_exempt_reason = ''T5E: klinik savolni ozod qilishga urinish'' where id = ''T5E_C15'''));
end $$;

-- ===== G. Evidence rad etish (Qaror 3, STEP 10) =====
do $$ declare n_qe int; n_rev int; begin
  -- G01: nashr qilingan klinik savol (D08 → T5E_C08) evidence rejected → yaroqsiz
  select count(*) into n_qe from public.question_evidence where question_id = 'T5E_C08';
  perform pg_temp.ok('G01', 'Evidence rejection', 'Published klinik (yaroqli) → EM evidence rejected → holat / yaroqlilik', 'OK:1 review_required/review_due/evidence_rejected false',
    pg_temp.rv(pg_temp.u('EDU'), 'T5E_C08', 'evidence', 'rejected') || ' ' || pg_temp.st('T5E_C08') || ' ' || pg_temp.elig('T5E_C08'));
  perform pg_temp.ok('G02', 'Evidence rejection', 'Savol, dalil bog''lanishlari, review yozuvlari saqlandi', '1/' || n_qe || '/true',
    (select count(*)::text from public.questions where id = 'T5E_C08') || '/' || (select count(*)::text from public.question_evidence where question_id = 'T5E_C08') || '/' ||
    (exists (select 1 from public.question_reviews where question_id = 'T5E_C08' and review_type = 'evidence' and decision = 'rejected')
     and exists (select 1 from public.question_reviews where question_id = 'T5E_C08' and review_type = 'evidence' and decision = 'approved'))::text);
  perform pg_temp.ok('G03', 'Evidence rejection', 'evidence_events: rad etish hodisasi (audit)', '1',
    (select count(*)::text from public.evidence_events where question_id = 'T5E_C08' and details ->> 'decision' = 'evidence_rejected'));
  perform pg_temp.ok('G04', 'Evidence rejection', 'Rad etilgandan keyin EM publish (medical approved hali bor)', 'DENIED', pg_temp.pub(pg_temp.u('EDU'), 'T5E_C08'));
  perform pg_temp.ok('G05', 'Evidence rejection', 'Yangi evidence approved → EM publish → yaroqli (Rejected → Approved)', 'OK:1 OK:1 true',
    pg_temp.evready('T5E_C08') || ' ' || pg_temp.pub(pg_temp.u('EDU'), 'T5E_C08') || ' ' || pg_temp.elig('T5E_C08'));
  -- G06: klinik bo'lmagan, ozod qilingan, nashr qilingan (F02) → evidence rejected → yaroqsiz, qayta nashr yo'q
  perform pg_temp.ok('G06', 'Evidence rejection', 'Non-clinical exempt published → evidence rejected → holat / yaroqlilik / qayta publish', 'OK:1 review_required/unknown/evidence_rejected false DENIED',
    pg_temp.rv(pg_temp.u('EDU'), 'T5E_N02', 'evidence', 'rejected') || ' ' || pg_temp.st('T5E_N02') || ' ' || pg_temp.elig('T5E_N02') || ' ' || pg_temp.pub(pg_temp.u('EDU'), 'T5E_N02'));
  -- G07: draft savolda evidence rejected → nashr qilinmaydi
  perform pg_temp.evready('T5E_N04'); perform pg_temp.rv(pg_temp.u('EDU'), 'T5E_N04', 'evidence', 'rejected');
  perform pg_temp.ok('G07', 'Evidence rejection', 'Draft (ETHICS): approved → rejected → EM publish', 'DENIED', pg_temp.pub(pg_temp.u('EDU'), 'T5E_N04'));
  -- G08: evidence "changes_requested" — Qaror 3 faqat "rejected"ni qamraydi: holat o'zgarmaydi (hujjatlashtirilgan)
  perform pg_temp.evready('T5E_N05'); perform pg_temp.pub(pg_temp.u('EDU'), 'T5E_N05');
  perform pg_temp.ok('G08', 'Evidence rejection', 'Published ETHICS → evidence changes_requested → holat (o''zgarmaydi)', 'OK:1 published/current/- true',
    pg_temp.rv(pg_temp.u('EDU'), 'T5E_N05', 'evidence', 'changes_requested') || ' ' || pg_temp.st('T5E_N05') || ' ' || pg_temp.elig('T5E_N05'));
end $$;

-- ===== H. Instruktor hujum yo'llari (STEP 11) — nashr qilingan, yaroqli klinik savol T5E_C11 (D11) =====
do $$ declare v text; begin
  perform pg_temp.ok('H00', 'Instructor bypass', 'Boshlang''ich holat: T5E_C11 published / yaroqli', 'published/current/- true', pg_temp.st('T5E_C11') || ' ' || pg_temp.elig('T5E_C11'));
  perform pg_temp.ok('H01', 'Instructor bypass', 'medical "mark_outdated"', 'DENIED', pg_temp.rv(pg_temp.u('INS'), 'T5E_C11', 'medical', 'mark_outdated'));
  perform pg_temp.ok('H02', 'Instructor bypass', 'instructor "mark_conflicting"', 'DENIED', pg_temp.rv(pg_temp.u('INS'), 'T5E_C11', 'instructor', 'mark_conflicting'));
  perform pg_temp.ok('H03', 'Instructor bypass', 'editorial / psychometric "mark_outdated"', 'DENIED/DENIED',
    pg_temp.rv(pg_temp.u('INS'), 'T5E_C11', 'editorial', 'mark_outdated') || '/' || pg_temp.rv(pg_temp.u('INS'), 'T5E_C11', 'psychometric', 'mark_conflicting'));
  perform pg_temp.ok('H04', 'Instructor bypass', 'workflow_status = review_required', 'DENIED', pg_temp.w(pg_temp.u('INS'), 'update public.questions set workflow_status = ''review_required'' where id = ''T5E_C11'''));
  perform pg_temp.ok('H05', 'Instructor bypass', 'workflow_status = draft / deprecated / archived; status = archived / draft', 'DENIED/DENIED/DENIED/DENIED/DENIED',
    pg_temp.w(pg_temp.u('INS'), 'update public.questions set workflow_status = ''draft'' where id = ''T5E_C11''') || '/' ||
    pg_temp.w(pg_temp.u('INS'), 'update public.questions set workflow_status = ''deprecated'' where id = ''T5E_C11''') || '/' ||
    pg_temp.w(pg_temp.u('INS'), 'update public.questions set workflow_status = ''archived'' where id = ''T5E_C11''') || '/' ||
    pg_temp.w(pg_temp.u('INS'), 'update public.questions set status = ''archived'' where id = ''T5E_C11''') || '/' ||
    pg_temp.w(pg_temp.u('INS'), 'update public.questions set status = ''draft'' where id = ''T5E_C11'''));
  perform pg_temp.ok('H06', 'Instructor bypass', 'evidence review rejected / approved', 'DENIED/DENIED', pg_temp.rv(pg_temp.u('INS'), 'T5E_C11', 'evidence', 'rejected') || '/' || pg_temp.rv(pg_temp.u('INS'), 'T5E_C11', 'evidence', 'approved'));
  perform pg_temp.ok('H07', 'Instructor bypass', 'medical review rejected', 'DENIED', pg_temp.rv(pg_temp.u('INS'), 'T5E_C11', 'medical', 'rejected'));
  perform pg_temp.ok('H08', 'Instructor bypass', 'evidence_status / review_reason to''g''ridan-to''g''ri', 'DENIED/DENIED',
    pg_temp.w(pg_temp.u('INS'), 'update public.questions set evidence_status = ''outdated'' where id = ''T5E_C11''') || '/' || pg_temp.w(pg_temp.u('INS'), 'update public.questions set review_reason = ''x'' where id = ''T5E_C11'''));
  perform pg_temp.ok('H09', 'Instructor bypass', 'evidence_exempt / published_version / current_version', 'DENIED/DENIED/DENIED',
    pg_temp.w(pg_temp.u('INS'), 'update public.questions set evidence_exempt = true, evidence_exempt_reason = ''T5E: instruktor urinishi (test)'' where id = ''T5E_C11''') || '/' ||
    pg_temp.w(pg_temp.u('INS'), 'update public.questions set published_version = null where id = ''T5E_C11''') || '/' ||
    pg_temp.w(pg_temp.u('INS'), 'update public.questions set current_version = 9 where id = ''T5E_C11'''));
  perform pg_temp.ok('H10', 'Instructor bypass', 'conflicting_evidence bog''lash / bog''lanish turini o''zgartirish / bog''lanishni o''chirish', 'DENIED/DENIED/OK:0',
    pg_temp.w(pg_temp.u('INS'), format('insert into public.question_evidence (question_id, evidence_source_id, relationship_type, supporting_claim) values (''T5E_C11'', %L, ''conflicting_evidence'', ''x'')', pg_temp.c('SRC_U'))) || '/' ||
    pg_temp.w(pg_temp.u('INS'), 'update public.question_evidence set relationship_type = ''conflicting_evidence'' where question_id = ''T5E_C11''') || '/' ||
    pg_temp.w(pg_temp.u('INS'), 'delete from public.question_evidence where question_id = ''T5E_C11'''));
  perform pg_temp.ok('H11', 'Instructor bypass', 'Manbani retracted / superseded qilish; supersedes_id bilan yangi manba', 'DENIED/DENIED/DENIED',
    pg_temp.w(pg_temp.u('INS'), format('update public.evidence_sources set status = ''retracted'' where id = %L', pg_temp.c('SRC_A'))) || '/' ||
    pg_temp.w(pg_temp.u('INS'), format('update public.evidence_sources set status = ''superseded'' where id = %L', pg_temp.c('SRC_A'))) || '/' ||
    pg_temp.w(pg_temp.u('INS'), format('insert into public.evidence_sources (org_id, scope_type, source_type, title, url, supersedes_id) values (%L, ''organization'', ''guideline'', ''T5E hack'', ''https://example.org/h'', %L)', pg_temp.c('OA'), pg_temp.c('SRC_A'))));
  perform pg_temp.ok('H12', 'Instructor bypass', 'Boshqa savolni publish / draft_status=publish / legacy status=approved', 'DENIED/DENIED/DENIED',
    pg_temp.pub(pg_temp.u('INS'), 'T5E_C04') || '/' || pg_temp.w(pg_temp.u('INS'), 'update public.questions set draft_status = ''publish'' where id = ''T5E_C04''') || '/' ||
    pg_temp.w(pg_temp.u('INS'), 'update public.questions set status = ''approved'' where id = ''T5E_C04'''));
  perform pg_temp.ok('H13', 'Instructor bypass', 'review_assignments yaratish (o''zini MR sifatida)', 'DENIED',
    pg_temp.w(pg_temp.u('INS'), format('insert into public.question_review_assignments (org_id, question_id, reviewer_id, review_type) values (%L, ''T5E_C11'', %L, ''medical'')', pg_temp.c('OA'), pg_temp.c('INS'))));
  perform pg_temp.ok('H14', 'Instructor bypass', 'Kontent tahriri (yangi draft versiya) — v1 imtihonda qoladi', 'OK:1 true 1',
    pg_temp.w(pg_temp.u('INS'), 'update public.questions set stem = stem || '' (ins)'' where id = ''T5E_C11''') || ' ' || pg_temp.elig('T5E_C11') || ' ' || pg_temp.pv('T5E_C11'));
  perform pg_temp.ok('H15', 'Instructor bypass', 'Yakuniy holat: T5E_C11 published / yaroqli (hech bir yo''l ta''sir qilmadi)', 'published/current/- true', pg_temp.st('T5E_C11') || ' ' || pg_temp.elig('T5E_C11'));
  -- Instruktor draft savolga dalil qo'sha oladi (normal ish oqimi buzilmagan)
  perform pg_temp.ok('H16', 'Instructor bypass', 'Normal oqim: instruktor DRAFT savolga dalil bog''laydi', 'OK:1',
    pg_temp.w(pg_temp.u('INS'), format('insert into public.question_evidence (question_id, evidence_source_id, relationship_type, supporting_claim) values (''T5E_C16'', %L, ''additional_support'', ''T5E'')', pg_temp.c('SRC_G'))));
end $$;

-- ===== I. Education Manager (STEP 11) =====
do $$ begin
  perform pg_temp.ok('I01', 'Education Manager', 'EM medical review (approved / rejected)', 'DENIED/DENIED', pg_temp.rv(pg_temp.u('EDU'), 'T5E_C17', 'medical', 'approved') || '/' || pg_temp.rv(pg_temp.u('EDU'), 'T5E_C17', 'medical', 'rejected'));
  perform pg_temp.evready('T5E_C17'); perform pg_temp.rv(pg_temp.u('EDU'), 'T5E_C17', 'instructor', 'approved');
  perform pg_temp.ok('I02', 'Education Manager', 'EM yolg''iz: evidence + instructor approved → publish (P08 yopildi)', 'DENIED', pg_temp.pub(pg_temp.u('EDU'), 'T5E_C17'));
  perform pg_temp.ok('I03', 'Education Manager', 'EM medical review_assignment yaratadi (MR ga)', 'OK:1',
    pg_temp.w(pg_temp.u('EDU'), format('insert into public.question_review_assignments (org_id, question_id, reviewer_id, review_type) values (%L, ''T5E_N06'', %L, ''medical'')', pg_temp.c('OA'), pg_temp.c('REV'))));
  perform pg_temp.ok('I04', 'Education Manager', 'EM nashr qilingan savolni review_required''ga qaytaradi (evidence.review)', 'OK:1', pg_temp.w(pg_temp.u('EDU'), 'update public.questions set workflow_status = ''review_required'' where id = ''T5E_C10'''));
  perform pg_temp.ok('I05', 'Education Manager', 'EM evidence "mark_outdated" (evidence review turi)', 'OK:1 review_required/outdated/mark_outdated',
    pg_temp.rv(pg_temp.u('EDU'), 'T5E_C11', 'evidence', 'mark_outdated') || ' ' || pg_temp.st('T5E_C11'));
  perform pg_temp.ok('I06', 'Education Manager', 'EM instructor-turi "mark_conflicting"', 'DENIED', pg_temp.rv(pg_temp.u('EDU'), 'T5E_C18', 'instructor', 'mark_conflicting'));
  perform pg_temp.ok('I07', 'Education Manager', 'EM manbani retracted qiladi (evidence.review) → bog''langan published savollar review_required', 'OK:1 review_required',
    pg_temp.w(pg_temp.u('EDU'), format('update public.evidence_sources set status = ''retracted'' where id = %L', pg_temp.c('SRC_A'))) || ' ' || pg_temp.wf('T5E_C14'));
end $$;

-- ===== X. Tashkilot izolyatsiyasi (STEP 12): Org B foydalanuvchisi navbat bilan MR / EM / Instructor =====
do $$ begin
  perform pg_temp.ok('X01', 'Org isolation', 'Org A MR → Org B savoliga medical review', 'DENIED', pg_temp.rv(pg_temp.u('REV'), 'T5E_B1', 'medical', 'approved'));
  perform pg_temp.ok('X02', 'Org isolation', 'Org A EM → Org B savoliga evidence review', 'DENIED', pg_temp.rv(pg_temp.u('EDU'), 'T5E_B1', 'evidence', 'approved'));
  perform pg_temp.ok('X03', 'Org isolation', 'Org A EM → Org B savolini publish (o''zgarmaydi)', 'OK:0 draft', pg_temp.pub(pg_temp.u('EDU'), 'T5E_B1') || ' ' || pg_temp.wf('T5E_B1'));
  perform pg_temp.ok('X04', 'Org isolation', 'Org A EM → Org A savoliga Org B manbasini bog''lash', 'DENIED',
    pg_temp.w(pg_temp.u('EDU'), format('insert into public.question_evidence (question_id, evidence_source_id, relationship_type, supporting_claim) values (''T5E_C19'', %L, ''primary_support'', ''x'')', pg_temp.c('SRC_B'))));
  perform pg_temp.ok('X05', 'Org isolation', 'Org A SA → Org B review / manba / savolni ko''rish', '0/0/0',
    pg_temp.cnt(pg_temp.u('SA'), 'select 1 from public.question_reviews where org_id = ''0000000b-0000-0000-0000-00000000000b''') || '/' ||
    pg_temp.cnt(pg_temp.u('SA'), 'select 1 from public.evidence_sources where title = ''T5E Org B guideline (test)''') || '/' ||
    pg_temp.cnt(pg_temp.u('SA'), 'select 1 from public.questions where id = ''T5E_B1'''));
  perform pg_temp.ok('X06', 'Org isolation', 'Global manba: Org A EM va Org B SA ko''radi', '1/1',
    pg_temp.cnt(pg_temp.u('EDU'), 'select 1 from public.evidence_sources where title = ''T5E global darslik (test)''') || '/' ||
    pg_temp.cnt(pg_temp.u('BADM'), 'select 1 from public.evidence_sources where title = ''T5E global darslik (test)'''));
  -- Org B: BEMP → medical_reviewer
  perform pg_temp.sys(format('update public.profiles set role = ''medical_reviewer'' where id = %L', pg_temp.c('BEMP')));
  perform pg_temp.ok('X07', 'Org isolation', 'Org B MR → Org A savoliga medical review', 'DENIED', pg_temp.rv(pg_temp.u('BEMP'), 'T5E_C19', 'medical', 'approved'));
  perform pg_temp.ok('X08', 'Org isolation', 'Org B MR → Org A review''larini o''qish', '0', pg_temp.cnt(pg_temp.u('BEMP'), 'select 1 from public.question_reviews where org_id = ''00000000-0000-0000-0000-000000000001''')::text);
  perform pg_temp.ok('X09', 'Org isolation', 'Org B MR (tayinlangan) → Org B savoliga evidence + medical review', 'OK:1/OK:1',
    pg_temp.rv(pg_temp.u('BEMP'), 'T5E_B1', 'evidence', 'approved') || '/' || pg_temp.rv(pg_temp.u('BEMP'), 'T5E_B1', 'medical', 'approved'));
  perform pg_temp.ok('X10', 'Org isolation', 'Org B MR → Org B savolini publish', 'DENIED', pg_temp.pub(pg_temp.u('BEMP'), 'T5E_B1'));
  -- Org B: BEMP → education_manager
  perform pg_temp.sys(format('update public.profiles set role = ''education_manager'' where id = %L', pg_temp.c('BEMP')));
  perform pg_temp.ok('X11', 'Org isolation', 'Org B EM → Org A savolini publish / Org A review o''qish', 'OK:0/0',
    pg_temp.pub(pg_temp.u('BEMP'), 'T5E_C11') || '/' || pg_temp.cnt(pg_temp.u('BEMP'), 'select 1 from public.question_reviews where org_id = ''00000000-0000-0000-0000-000000000001'''));
  perform pg_temp.ok('X12', 'Org isolation', 'Org B EM → Org B savolini publish (Org B MR approved) → yaroqli', 'OK:1 true', pg_temp.pub(pg_temp.u('BEMP'), 'T5E_B1') || ' ' || pg_temp.elig('T5E_B1'));
  perform pg_temp.ok('X13', 'Org isolation', 'Org B EM → medical review', 'DENIED', pg_temp.rv(pg_temp.u('BEMP'), 'T5E_B1', 'medical', 'rejected'));
  -- Org B: BEMP → instructor
  perform pg_temp.sys(format('update public.profiles set role = ''instructor'' where id = %L', pg_temp.c('BEMP')));
  perform pg_temp.ok('X14', 'Org isolation', 'Org B instructor → Org A savoliga mark_outdated / workflow o''zgartirish', 'DENIED/OK:0',
    pg_temp.rv(pg_temp.u('BEMP'), 'T5E_C19', 'evidence', 'mark_outdated') || '/' || pg_temp.w(pg_temp.u('BEMP'), 'update public.questions set workflow_status = ''review_required'' where id = ''T5E_C19'''));
  perform pg_temp.sys(format('update public.profiles set role = ''employee'' where id = %L', pg_temp.c('BEMP')));
  perform pg_temp.ok('X15', 'Org isolation', 'Org B SA (BADM) → Org A savoliga medical review', 'DENIED', pg_temp.rv(pg_temp.u('BADM'), 'T5E_C19', 'medical', 'approved'));
end $$;

-- ===== Y. Tarixiy o'zgarmaslik (STEP 13) =====
do $$ declare b json := pg_temp.c('BASE')::json; res text; begin
  perform pg_temp.ok('Y01', 'Historical immutability', 'Test urinishi (T5E_ATT) o''zgarmagan', 'true', ((select to_jsonb(a)::text from public.exam_attempts a where id = 'T5E_ATT') = pg_temp.c('ATT_SNAP'))::text);
  perform pg_temp.ok('Y02', 'Historical immutability', 'Test sertifikati (T5E-CERT) o''zgarmagan', 'true', ((select to_jsonb(c)::text from public.certificates c where id = 'T5E-CERT') = pg_temp.c('CERT_SNAP'))::text);
  perform pg_temp.ok('Y03', 'Historical immutability', 'Mavjud urinishlar / sertifikatlar (md5, fixture''siz)', 'true/true',
    ((select md5(coalesce(string_agg(to_jsonb(a)::text, '' order by a.id), '')) from public.exam_attempts a where a.id <> 'T5E_ATT') = b ->> 'att_md5')::text || '/' ||
    ((select md5(coalesce(string_agg(to_jsonb(c)::text, '' order by c.id), '')) from public.certificates c where c.id <> 'T5E-CERT') = b ->> 'cert_md5')::text);
  perform pg_temp.ok('Y04', 'Historical immutability', 'Mavjud (fixture''dan oldingi) review''lar va savol versiyalari (md5)', 'true/true',
    ((select md5(coalesce(string_agg(to_jsonb(r)::text, '' order by r.id), '')) from public.question_reviews r where r.question_id not like 'T5E%') = b ->> 'rev_md5')::text || '/' ||
    ((select md5(coalesce(string_agg(to_jsonb(v)::text, '' order by v.question_id, v.version_no), '')) from public.question_versions v where v.question_id not like 'T5E%') = b ->> 'qv_md5')::text);
  begin update public.question_reviews set decision = 'approved' where question_id = 'T5E_C06'; res := 'ALLOWED'; exception when others then res := 'DENIED'; end;
  perform pg_temp.ok('Y05', 'Historical immutability', 'question_reviews UPDATE (hatto platforma SQL)', 'DENIED', res);
  begin delete from public.question_reviews where question_id = 'T5E_C06'; res := 'ALLOWED'; exception when others then res := 'DENIED'; end;
  perform pg_temp.ok('Y06', 'Historical immutability', 'question_reviews DELETE (hatto platforma SQL)', 'DENIED', res);
  begin update public.question_reviews set reviewer_role_at_creation = 'medical_reviewer' where internal_notes = 'T5E-legacy'; res := 'ALLOWED'; exception when others then res := 'DENIED'; end;
  perform pg_temp.ok('Y07', 'Historical immutability', 'reviewer_role_at_creation ni keyin o''zgartirish', 'DENIED', res);
  begin update public.question_versions set stem = 'x' where question_id = 'T5E_C07' and version_no = 1; res := 'ALLOWED'; exception when others then res := 'DENIED'; end;
  perform pg_temp.ok('Y08', 'Historical immutability', 'question_versions (v1) tahriri', 'DENIED', res);
  perform pg_temp.ok('Y09', 'Historical immutability', 'T5E_C07 versiyalari saqlangan (v1, v2)', '1,2', (select string_agg(version_no::text, ',' order by version_no) from public.question_versions where question_id = 'T5E_C07'));
  perform pg_temp.ok('Y10', 'Historical immutability', 'Rad etilgan evidence holatida ham T5E_C20 urinishi (v1) baholangan natija o''zgarmagan', 'true/100',
    ((select results ->> 'T5E_C20' from public.exam_attempts where id = 'T5E_ATT') = 'true')::text || '/' || (select score::text from public.exam_attempts where id = 'T5E_ATT'));
end $$;

-- ===== Z. Idempotentlik va migratsiya holati =====
do $$ begin
  perform pg_temp.ok('Z01', 'Idempotency', 'snapshot: fn_def / policy / role_perm / counts', '7/2/' || (select count(*) from backup.security_pre005e where kind = 'role_perm') || '/1',
    (select count(*) filter (where kind = 'fn_def') || '/' || count(*) filter (where kind = 'policy') || '/' || count(*) filter (where kind = 'role_perm') || '/' || count(*) filter (where kind = 'counts') from backup.security_pre005e));
  perform pg_temp.ok('Z02', 'Idempotency', 'role_permissions_005e_chk / reviewer_role_chk / latest_idx soni', '1/1/1',
    (select count(*) from pg_constraint where conname = 'role_permissions_005e_chk') || '/' || (select count(*) from pg_constraint where conname = 'question_reviews_reviewer_role_chk')
    || '/' || (select count(*) from pg_indexes where indexname = 'question_reviews_latest_idx'));
  perform pg_temp.ok('Z03', 'Idempotency', 'anon EXECUTE funksiyalar (005d: faqat verify_certificate)', '1', (select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')));
  perform pg_temp.ok('Z04', 'Idempotency', 'question_reviews RLS: medical.review hisobga olingan, INSERT org tekshiruvi', 'true/true',
    (select (with_check ilike '%medical.review%' and with_check ilike '%my_org()%')::text from pg_policies where tablename = 'question_reviews' and policyname = 'question_reviews_insert') || '/' ||
    (select (qual ilike '%medical.review%')::text from pg_policies where tablename = 'question_reviews' and policyname = 'question_reviews_select'));
end $$;

select line from (
  select 0 ord, 'SUMMARY 005e total ' || count(*) || ' / PASS ' || count(*) filter (where pass) || ' / FAIL ' || count(*) filter (where not pass) || coalesce(' :: ' || string_agg(id, ',' order by id) filter (where not pass), '') as line from t5
  union all select 1, id || ' ' || case when pass then 'PASS' else 'FAIL' end || ' [' || grp || '] ' || test || ' :: kutilgan=' || expected || ' :: natija=' || actual from t5) x order by ord, line;
select json_build_object('total', count(*), 'pass', count(*) filter (where pass), 'fail', count(*) filter (where not pass),
  'fail_ids', coalesce(json_agg(id || ' => ' || actual order by id) filter (where not pass), '[]'::json),
  'groups', (select json_object_agg(grp, n) from (select grp, count(*) || '/' || count(*) filter (where pass) n from t5 group by grp) g))::text as summary_005e from t5;
rollback;
