-- MedAcademy · 006a audit / delete hardening / eligibility RPC test to'plami (lokal PGlite va staging uchun bir xil fayl).
-- Mavjud test akkauntlari (staging) bilan; yangi auth akkaunt yaratilmaydi. Hammasi BITTA tranzaksiyada, oxirida ROLLBACK.
-- Har bir foydalanuvchi so'rovi haqiqiy RLS / trigger / RPC orqali JWT claim'lari bilan bajariladi.
begin;
do $$ begin
  if not exists (select 1 from public.schema_migrations where version = '006a') then raise exception '006a qo''llanmagan'; end if;
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
    'certs', (select count(*) from public.certificates), 'audit', (select count(*) from public.audit_logs),
    'policies', (select count(*) from pg_policies where schemaname = 'public'),
    'rls_tables', (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity),
    'ec', (select count(*) from public.exam_configs))::text;
  perform pg_temp.sys($q$insert into public.docs (collection, id, owner, org_id, data) values
      ('attempts', 'T6A-DOC', '262a128c-6fb7-470e-9452-5468cd6797c0', '00000000-0000-0000-0000-000000000001', '{}'),
      ('notifications', 'T6N-DOC', '262a128c-6fb7-470e-9452-5468cd6797c0', '00000000-0000-0000-0000-000000000001', '{}')$q$);
  perform pg_temp.sys($q$update public.questions set evidence_status = 'current', last_evidence_reviewed_at = now(), workflow_status = 'published', review_reason = null where id = 'Q001'$q$);
end $$;
create function pg_temp.lastaudit(p_action text, p_id text) returns jsonb language sql security definer as $$
  select to_jsonb(a) from public.audit_logs a where action = p_action and entity_id = p_id order by id desc limit 1 $$;
create function pg_temp.rpc(uid uuid, q text) returns text language plpgsql as $$ declare v text; begin
  perform pg_temp.login(uid); set local role authenticated; execute 'select (' || q || ')::text' into v; reset role; perform pg_temp.logout(); return coalesce(v, 'NULL');
exception when others then reset role; perform pg_temp.logout(); insert into t5err (uid, q, err) values (uid::text, left(q, 160), sqlerrm); return 'DENIED'; end $$;
create function pg_temp.rpca(q text) returns text language plpgsql as $$ declare v text; begin
  set local role anon; execute 'select (' || q || ')::text' into v; reset role; return coalesce(v, 'NULL');
exception when others then reset role; return 'DENIED'; end $$;

-- ===== A. audit_logs o'zgarmas =====
do $$ declare res text; begin
  perform pg_temp.ok('A01', 'Audit immutability', 'SA (API): audit_logs UPDATE', 'DENIED|OK:0', pg_temp.w(pg_temp.u('SA'), 'update public.audit_logs set action = ''x'''));
  perform pg_temp.ok('A02', 'Audit immutability', 'SA (API): audit_logs DELETE', 'DENIED|OK:0', pg_temp.w(pg_temp.u('SA'), 'delete from public.audit_logs'));
  perform pg_temp.ok('A03', 'Audit immutability', 'SA (API): soxta actor bilan audit INSERT', 'DENIED',
    pg_temp.w(pg_temp.u('SA'), format('insert into public.audit_logs (org_id, actor_id, action, entity) values (%L, %L, ''fake'', ''x'')', pg_temp.c('OA'), pg_temp.c('EMP'))));
  begin update public.audit_logs set action = 'x' where id = (select min(id) from public.audit_logs); res := 'ALLOWED'; exception when others then res := 'DENIED'; end;
  perform pg_temp.ok('A04', 'Audit immutability', 'Platforma SQL (owner): audit_logs UPDATE', 'DENIED', res);
  begin delete from public.audit_logs where id = (select min(id) from public.audit_logs); res := 'ALLOWED'; exception when others then res := 'DENIED'; end;
  perform pg_temp.ok('A05', 'Audit immutability', 'Platforma SQL (owner): audit_logs DELETE', 'DENIED', res);
  begin truncate public.audit_logs; res := 'ALLOWED'; exception when others then res := 'DENIED'; end;
  perform pg_temp.ok('A06', 'Audit immutability', 'Platforma SQL (owner): audit_logs TRUNCATE', 'DENIED', res);
  perform pg_temp.ok('A07', 'Audit immutability', 'anon: audit_logs SELECT', 'DENIED|OK:0', pg_temp.wa('select * from public.audit_logs'));
  perform pg_temp.ok('A08', 'Audit immutability', 'anon/authenticated INSERT/UPDATE/DELETE/TRUNCATE huquqlari audit_logs''da', '0',
    (select count(*)::text from information_schema.role_table_grants where table_schema = 'public' and table_name = 'audit_logs' and grantee in ('anon','authenticated') and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE')));
  perform pg_temp.ok('A09', 'Audit immutability', 'Employee: audit_logs ko''rmaydi', '0', pg_temp.cnt(pg_temp.u('EMP'), 'select 1 from public.audit_logs')::text);
end $$;

-- ===== B. Savol audit'i =====
do $$ declare a jsonb; begin
  perform pg_temp.ok('B01', 'Question audit', 'EM: nashrdan chiqarish (review_required)', 'OK:1', pg_temp.w(pg_temp.u('EDU'), 'update public.questions set workflow_status = ''review_required'' where id = ''Q001'''));
  a := pg_temp.lastaudit('question.unpublished', 'Q001');
  perform pg_temp.ok('B02', 'Question audit', 'question.unpublished: actor = EM (auth.uid), rol, eski/yangi holat', 'true',
    (a is not null and a ->> 'actor_id' = pg_temp.c('EDU') and a ->> 'actor_role' = 'education_manager' and a -> 'old_value' ->> 'workflow_status' = 'published'
     and a -> 'new_value' ->> 'workflow_status' = 'review_required')::text);
  perform pg_temp.ok('B03', 'Question audit', 'EM: qayta nashr (non-clinical, evidence current)', 'OK:1', pg_temp.pub(pg_temp.u('EDU'), 'Q001'));
  a := pg_temp.lastaudit('question.published', 'Q001');
  perform pg_temp.ok('B04', 'Question audit', 'question.published audit yozuvi (actor EM)', 'true', (a is not null and a ->> 'actor_id' = pg_temp.c('EDU'))::text);
  perform pg_temp.ok('B05', 'Question audit', 'Savol audit''ida matn / javob / izoh / evidence yo''q', 'false',
    (select bool_or(coalesce(old_value, '{}') ?| array['stem','answer','explanation','options','evidence','reading'] or coalesce(new_value, '{}') ?| array['stem','answer','explanation','options','evidence','reading'])::text
       from public.audit_logs where entity = 'question'));
  perform pg_temp.sys($q$update public.questions set evidence_status = 'review_due' where id = 'Q002'$q$);
  a := pg_temp.lastaudit('question.eligibility_changed', 'Q002');
  perform pg_temp.ok('B06', 'Question audit', 'Server (system) evidence o''zgarishi → question.eligibility_changed', 'true', (a is not null and a -> 'new_value' ->> 'evidence_status' = 'review_due')::text);
end $$;

-- ===== C. Kurs audit'i =====
do $$ declare a jsonb; begin
  perform pg_temp.ok('C01', 'Course audit', 'EM: kurs nomini o''zgartirish', 'OK:1', pg_temp.w(pg_temp.u('EDU'), 'update public.courses set title = title || '' (T6)'' where id = ''SALES'''));
  a := pg_temp.lastaudit('course.updated', 'SALES');
  perform pg_temp.ok('C02', 'Course audit', 'course.updated (actor EM, eski/yangi title)', 'true', (a is not null and a ->> 'actor_id' = pg_temp.c('EDU') and a -> 'new_value' ->> 'title' like '%(T6)')::text);
  perform pg_temp.ok('C03', 'Course audit', 'EM: kurs holatini archived qilish', 'OK:1', pg_temp.w(pg_temp.u('EDU'), 'update public.courses set status = ''archived'' where id = ''SALES'''));
  perform pg_temp.ok('C04', 'Course audit', 'course.archived audit yozuvi', 'true', (pg_temp.lastaudit('course.archived', 'SALES') is not null)::text);
  perform pg_temp.ok('C05', 'Course audit', 'Instructor: kursni o''zgartira olmaydi', 'DENIED|OK:0', pg_temp.w(pg_temp.u('INS'), 'update public.courses set title = ''x'' where id = ''CARDIO_BASIC'''));
end $$;

-- ===== D. Profil: rol / holat / bo'lim =====
do $$ declare a jsonb; begin
  perform pg_temp.ok('D01', 'Role change', 'SA: admin_set_profile_role sababsiz', 'DENIED', pg_temp.rpc(pg_temp.u('SA'), format('public.admin_set_profile_role(%L, ''medical_reviewer'', '''')', pg_temp.c('INS2'))));
  perform pg_temp.ok('D02', 'Role change', 'SA: instructor2 → medical_reviewer (sabab bilan)', 'ok', case when pg_temp.rpc(pg_temp.u('SA'), format('public.admin_set_profile_role(%L, ''medical_reviewer'', ''T6: lavozim o''''zgardi'')', pg_temp.c('INS2'))) like '%"new_role": "medical_reviewer"%' then 'ok' else 'fail' end);
  perform pg_temp.ok('D02b', 'Role change', 'instructor2 roli haqiqatan medical_reviewer', 'medical_reviewer', (select role from public.profiles where id = pg_temp.u('INS2')));
  a := pg_temp.lastaudit('profile.role_changed', pg_temp.c('INS2'));
  perform pg_temp.ok('D03', 'Role change', 'profile.role_changed: actor, eski/yangi rol, sabab, tashkilot', 'true',
    (a is not null and a ->> 'actor_id' = pg_temp.c('SA') and a -> 'old_value' ->> 'role' = 'instructor' and a -> 'new_value' ->> 'role' = 'medical_reviewer'
     and a -> 'new_value' ->> 'reason' like 'T6:%' and a ->> 'org_id' = pg_temp.c('OA'))::text);
  perform pg_temp.ok('D04', 'Role change', 'SA: o''z rolini o''zgartirish (PATCH)', 'DENIED', pg_temp.w(pg_temp.u('SA'), format('update public.profiles set role = ''hr'' where id = %L', pg_temp.c('SA'))));
  perform pg_temp.ok('D05', 'Role change', 'HR: o''z holatini o''zgartirish', 'DENIED', pg_temp.w(pg_temp.u('HR'), format('update public.profiles set status = ''inactive'' where id = %L', pg_temp.c('HR'))));
  perform pg_temp.ok('D06', 'Role change', 'HR: o''z rolini RPC orqali super_admin qilish', 'DENIED', pg_temp.rpc(pg_temp.u('HR'), format('public.admin_set_profile_role(%L, ''super_admin'', ''T6 self'')', pg_temp.c('HR'))));
  perform pg_temp.ok('D07', 'Role change', 'Employee: admin_set_profile_role', 'DENIED', pg_temp.rpc(pg_temp.u('EMP'), format('public.admin_set_profile_role(%L, ''hr'', ''T6 hack'')', pg_temp.c('EMP2'))));
  perform pg_temp.ok('D08', 'Role change', 'Org B admin: Org A foydalanuvchi rolini o''zgartirish', 'DENIED', pg_temp.rpc(pg_temp.u('BADM'), format('public.admin_set_profile_role(%L, ''hr'', ''T6 cross'')', pg_temp.c('EMP'))));
  perform pg_temp.ok('D09', 'Role change', 'Instructor: boshqa foydalanuvchi rolini PATCH', 'DENIED|OK:0', pg_temp.w(pg_temp.u('INS'), format('update public.profiles set role = ''hr'' where id = %L', pg_temp.c('EMP'))));
  perform pg_temp.ok('D10', 'Role change', 'HR: xodim holatini inactive (PATCH)', 'OK:1', pg_temp.w(pg_temp.u('HR'), format('update public.profiles set status = ''inactive'' where id = %L', pg_temp.c('EMP2'))));
  a := pg_temp.lastaudit('profile.status_changed', pg_temp.c('EMP2'));
  perform pg_temp.ok('D11', 'Role change', 'profile.status_changed (actor HR, active → inactive)', 'true', (a is not null and a ->> 'actor_id' = pg_temp.c('HR') and a -> 'new_value' ->> 'status' = 'inactive')::text);
  perform pg_temp.ok('D12', 'Role change', 'Profil audit''ida email / parol / token yo''q', 'false',
    (select coalesce(bool_or((coalesce(old_value, '{}') || coalesce(new_value, '{}')) ?| array['email','password','token','encrypted_password']), false)::text from public.audit_logs where entity = 'profile'));
end $$;

-- ===== E. exam_configs =====
do $$ declare a jsonb; begin
  perform pg_temp.ok('E01', 'Exam config', 'EM: time_min o''zgartirish', 'OK:1', pg_temp.w(pg_temp.u('EDU'), 'update public.exam_configs set time_min = time_min + 1 where course_id = ''ETHICS'''));
  a := pg_temp.lastaudit('exam_config.updated', 'ETHICS');
  perform pg_temp.ok('E02', 'Exam config', 'exam_config.updated audit (actor EM)', 'true', (a is not null and a ->> 'actor_id' = pg_temp.c('EDU'))::text);
  perform pg_temp.ok('E03', 'Exam config', 'EM: exam_configs DELETE', 'DENIED', pg_temp.w(pg_temp.u('EDU'), 'delete from public.exam_configs where course_id = ''ETHICS'''));
  perform pg_temp.ok('E04', 'Exam config', 'SA: exam_configs DELETE', 'DENIED', pg_temp.w(pg_temp.u('SA'), 'delete from public.exam_configs where course_id = ''COMM'''));
  perform pg_temp.ok('E05', 'Exam config', 'Employee: exam_configs UPDATE', 'DENIED|OK:0', pg_temp.w(pg_temp.u('EMP'), 'update public.exam_configs set pass_score = 1'));
  perform pg_temp.ok('E06', 'Exam config', 'exam_configs soni o''zgarmagan', (pg_temp.c('BASE')::json ->> 'ec'), (select count(*)::text from public.exam_configs));
end $$;

-- ===== F. docs =====
do $$ begin
  perform pg_temp.ok('F01', 'Docs delete', 'SA: docs (attempts) DELETE', 'DENIED', pg_temp.w(pg_temp.u('SA'), 'delete from public.docs where collection = ''attempts'' and id = ''T6A-DOC'''));
  perform pg_temp.ok('F02', 'Docs delete', 'EM: docs (audit) DELETE', 'DENIED|OK:0', pg_temp.w(pg_temp.u('EDU'), 'delete from public.docs where collection = ''audit'''));
  perform pg_temp.ok('F03', 'Docs delete', 'SA: docs (notifications) DELETE — tarixiy emas', 'OK:1', pg_temp.w(pg_temp.u('SA'), 'delete from public.docs where collection = ''notifications'' and id = ''T6N-DOC'''));
  perform pg_temp.ok('F04', 'Docs delete', 'Employee: docs DELETE', 'DENIED|OK:0', pg_temp.w(pg_temp.u('EMP'), 'delete from public.docs'));
  perform pg_temp.ok('F05', 'Docs delete', 'Tarixiy docs saqlangan (T6A-DOC)', '1', (select count(*)::text from public.docs where id = 'T6A-DOC'));
end $$;

-- ===== G. Sertifikat =====
do $$ declare a jsonb; begin
  perform pg_temp.sys(format($q$insert into public.certificates (id, org_id, user_id, course_id, course_title, name, position, department, score, attempt_id, issued_at)
    values ('T6-CERT', %L, %L, 'ETHICS', 'Etika', 'T6 Test', 'x', 'x', 90, null, now())$q$, pg_temp.c('OA'), pg_temp.c('EMP')));
  perform pg_temp.ok('G01', 'Certificate', 'certificate.issued audit yozuvi', 'true', (pg_temp.lastaudit('certificate.issued', 'T6-CERT') is not null)::text);
  perform pg_temp.ok('G02', 'Certificate', 'Instructor: revoke', 'DENIED', pg_temp.rpc(pg_temp.u('INS'), 'public.revoke_certificate(''T6-CERT'', ''T6 sabab'')'));
  perform pg_temp.ok('G03', 'Certificate', 'EM: revoke sababsiz (2 argument, bo''sh)', 'DENIED', pg_temp.rpc(pg_temp.u('EDU'), 'public.revoke_certificate(''T6-CERT'', '' '')'));
  perform pg_temp.ok('G04', 'Certificate', 'EM: revoke (sabab bilan)', 'true', pg_temp.rpc(pg_temp.u('EDU'), 'public.revoke_certificate(''T6-CERT'', ''T6: noto''''g''''ri berilgan'')'));
  a := pg_temp.lastaudit('certificate.revoked', 'T6-CERT');
  perform pg_temp.ok('G05', 'Certificate', 'certificate.revoked: actor EM, sabab', 'true', (a is not null and a ->> 'actor_id' = pg_temp.c('EDU') and a -> 'new_value' ->> 'reason' like 'T6:%')::text);
  begin update public.certificates set revoked = false where id = 'T6-CERT'; a := '"ALLOWED"'; exception when others then a := '"DENIED"'; end;
  perform pg_temp.ok('G06', 'Certificate', 'Revoke qaytarilmas (platforma SQL ham)', 'DENIED', a #>> '{}');
  perform pg_temp.ok('G07', 'Certificate', 'SA (API): sertifikat DELETE', 'DENIED|OK:0', pg_temp.w(pg_temp.u('SA'), 'delete from public.certificates where id = ''T6-CERT'''));
  perform pg_temp.ok('G08', 'Certificate', 'Eski 1-argumentli revoke_certificate ishlaydi (orqaga moslik)', 'false', pg_temp.rpc(pg_temp.u('EDU'), 'public.revoke_certificate(''NO-SUCH-CERT'')'));
end $$;

-- ===== H. Attempt reset tarixi =====
do $$ declare r1 timestamptz; begin
  perform pg_temp.ok('H01', 'Attempt reset', 'EM: reset #1 (sabab bilan)', 'true', pg_temp.rpc(pg_temp.u('EDU'), format('public.admin_reset_attempts(%L, ''ETHICS'', ''T6 reset 1'')', pg_temp.c('EMP'))));
  r1 := (select reset_at from public.attempt_resets where user_id = pg_temp.u('EMP') and course_id = 'ETHICS');
  perform pg_temp.ok('H02', 'Attempt reset', 'EM: reset #2 (eski 2-argumentli chaqiruv)', 'true', pg_temp.rpc(pg_temp.u('EDU'), format('public.admin_reset_attempts(%L, ''ETHICS'')', pg_temp.c('EMP'))));
  perform pg_temp.ok('H03', 'Attempt reset', 'Tarix: 2 ta hodisa saqlangan (overwrite yo''q)', '2', (select count(*)::text from public.attempt_reset_events where user_id = pg_temp.u('EMP') and course_id = 'ETHICS' and reset_by = pg_temp.u('EDU')));
  perform pg_temp.ok('H04', 'Attempt reset', '2-hodisa previous_reset_at = 1-hodisa vaqti; 1-hodisa sababi saqlangan', 'true',
    ((select previous_reset_at = r1 from public.attempt_reset_events where user_id = pg_temp.u('EMP') and course_id = 'ETHICS' and reset_by = pg_temp.u('EDU') order by id desc limit 1)
     and exists (select 1 from public.attempt_reset_events where user_id = pg_temp.u('EMP') and course_id = 'ETHICS' and reason = 'T6 reset 1'))::text);
  perform pg_temp.ok('H05', 'Attempt reset', 'attempt_resets: joriy holat bitta qator (exam engine semantikasi o''zgarmagan)', '1', (select count(*)::text from public.attempt_resets where user_id = pg_temp.u('EMP') and course_id = 'ETHICS'));
  perform pg_temp.ok('H06', 'Attempt reset', 'attempt.reset audit yozuvlari (2)', '2', (select count(*)::text from public.audit_logs where action = 'attempt.reset' and entity_id = pg_temp.c('EMP') || ':ETHICS'));
  perform pg_temp.ok('H07', 'Attempt reset', 'EM: reset tarixini UPDATE', 'DENIED|OK:0', pg_temp.w(pg_temp.u('EDU'), 'update public.attempt_reset_events set reason = ''x'''));
  perform pg_temp.ok('H08', 'Attempt reset', 'SA: reset tarixini DELETE', 'DENIED|OK:0', pg_temp.w(pg_temp.u('SA'), 'delete from public.attempt_reset_events'));
  perform pg_temp.ok('H10', 'Attempt reset', 'Instructor (ETHICS instruktori emas): reset', 'DENIED', pg_temp.rpc(pg_temp.u('INS'), format('public.admin_reset_attempts(%L, ''ETHICS'', ''x'')', pg_temp.c('EMP'))));
  perform pg_temp.ok('H11', 'Attempt reset', 'Employee: reset tarixini ko''radi (faqat o''zinikini)', 'true',
    (pg_temp.cnt(pg_temp.u('EMP'), 'select 1 from public.attempt_reset_events') >= 2 and pg_temp.cnt(pg_temp.u('EMP2'), format('select 1 from public.attempt_reset_events where user_id = %L', pg_temp.c('EMP'))) = 0)::text);
  perform pg_temp.ok('H12', 'Attempt reset', 'Org B admin: Org A xodimini reset', 'DENIED', pg_temp.rpc(pg_temp.u('BADM'), format('public.admin_reset_attempts(%L, ''ETHICS'', ''x'')', pg_temp.c('EMP'))));
  perform pg_temp.ok('H13', 'Attempt reset', 'Tarixiy urinishlar o''zgarmagan (md5)', 'true', ((select md5(coalesce(string_agg(to_jsonb(a)::text, '' order by a.id), '')) from public.exam_attempts a) = (pg_temp.c('BASE')::json ->> 'attempts_md5'))::text);
end $$;
do $$ declare res text; begin
  begin delete from public.attempt_reset_events; res := 'ALLOWED'; exception when others then res := 'DENIED'; end;
  perform pg_temp.ok('H09', 'Attempt reset', 'Platforma SQL (owner): reset tarixini DELETE', 'DENIED', res);
end $$;

-- ===== I. question_eligibility RPC =====
do $$ declare v text; j jsonb; begin
  v := pg_temp.rpc(pg_temp.u('EDU'), 'public.question_eligibility(''Q090'')');
  j := case when v like '{%' then v::jsonb end;
  perform pg_temp.ok('I01', 'Eligibility RPC', 'EM: klinik savol (CARDIO_BASIC)', 'true/true', coalesce((j ->> 'clinical') || '/' || (j ->> 'medical_review_required'), v));
  perform pg_temp.ok('I02', 'Eligibility RPC', 'eligible = _q_exam_eligible (server)', 'true', ((j ->> 'eligible') = pg_temp.elig('Q090'))::text);
  perform pg_temp.ok('I03', 'Eligibility RPC', 'Javobda matn / javob / izoh / variantlar / ichki izoh yo''q', 'false', coalesce((j ?| array['stem','answer','explanation','options','internal_notes','evidence','reading'])::text, 'NULL'));
  j := (select pg_temp.rpc(pg_temp.u('EDU'), 'public.question_eligibility(''Q073'')'))::jsonb;
  perform pg_temp.ok('I04', 'Eligibility RPC', 'RECEPTION_START: klinik emas, medical review talab qilinmaydi', 'false/false', (j ->> 'clinical') || '/' || (j ->> 'medical_review_required'));
  perform pg_temp.ok('I05', 'Eligibility RPC', 'Medical Reviewer: tayinlanmagan savol (ko''rish huquqi yo''q)', 'DENIED', pg_temp.rpc(pg_temp.u('REV'), 'public.question_eligibility(''Q090'')'));
  perform pg_temp.sys(format($q$insert into public.question_review_assignments (org_id, question_id, reviewer_id, review_type) values (%L, 'Q090', %L, 'medical')$q$, pg_temp.c('OA'), pg_temp.c('REV')));
  perform pg_temp.ok('I05b', 'Eligibility RPC', 'Medical Reviewer: tayinlangan savol', 'ok', case when pg_temp.rpc(pg_temp.u('REV'), 'public.question_eligibility(''Q090'')') like '{%' then 'ok' else 'DENIED' end);
  perform pg_temp.ok('I06', 'Eligibility RPC', 'Employee', 'DENIED', pg_temp.rpc(pg_temp.u('EMP'), 'public.question_eligibility(''Q090'')'));
  perform pg_temp.ok('I07', 'Eligibility RPC', 'HR (question.view yo''q)', 'DENIED', pg_temp.rpc(pg_temp.u('HR'), 'public.question_eligibility(''Q090'')'));
  perform pg_temp.ok('I08', 'Eligibility RPC', 'anon', 'DENIED', pg_temp.rpca('public.question_eligibility(''Q090'')'));
  perform pg_temp.ok('I09', 'Eligibility RPC', 'Org B admin: Org A savoli', 'DENIED', pg_temp.rpc(pg_temp.u('BADM'), 'public.question_eligibility(''Q090'')'));
  perform pg_temp.ok('I10', 'Eligibility RPC', 'Mavjud bo''lmagan savol', 'DENIED', pg_temp.rpc(pg_temp.u('EDU'), 'public.question_eligibility(''NO_SUCH_Q'')'));
end $$;

-- ===== J. Invariantlar =====
do $$ begin
  perform pg_temp.ok('J01', 'Invariants', 'anon EXECUTE funksiyalar (faqat verify_certificate)', 'verify_certificate',
    (select string_agg(p.proname, ',') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'EXECUTE')));
  perform pg_temp.ok('J02', 'Invariants', 'RLS policy soni: 006a''dan oldingi + 1 (attempt_reset_events_select; 007b qo''llangan bo''lsa +1 lpa_select_007b)', ((select detail::json ->> 'policies' from backup.security_pre006a where kind = 'counts')::int + 1 + (select count(*) from public.schema_migrations where version = '007b')::int + 3 * (select count(*) from public.schema_migrations where version = '007c')::int)::text,
    (select count(*)::text from pg_policies where schemaname = 'public'));
  perform pg_temp.ok('J03', 'Invariants', 'Yangi jadval RLS yoqilgan', 'true', (select relrowsecurity::text from pg_class where oid = 'public.attempt_reset_events'::regclass));
  perform pg_temp.ok('J04', 'Invariants', 'Trigger funksiyalari authenticated uchun EXECUTE emas', '0',
    (select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_audit006','audit_question_006a','audit_course_006a','audit_profile_006a','guard_profile_self_006a','audit_exam_config_006a','audit_certificate_006a')
       and has_function_privilege('authenticated', p.oid, 'EXECUTE')));
  perform pg_temp.ok('J05', 'Invariants', 'snapshot: fn_def / grant / counts', '1/1/1',
    (select count(*) filter (where kind = 'fn_def') || '/' || count(*) filter (where kind = 'grant') || '/' || count(*) filter (where kind = 'counts') from backup.security_pre006a));
  perform pg_temp.ok('J06', 'Invariants', '006a schema_migrations', '1', (select count(*)::text from public.schema_migrations where version = '006a'));
  perform pg_temp.ok('J07', 'Invariants', '006a trigger''lari soni (8 + audit_logs 2 + reset_events 2)', '12',
    (select count(*)::text from pg_trigger where not tgisinternal and (tgname like '%006a%' or tgname like 'audit_logs_%_trg' or tgname like 'attempt_reset_events_%_trg')));
end $$;

select line from (
  select 0 ord, 'SUMMARY 006a total ' || count(*) || ' / PASS ' || count(*) filter (where pass) || ' / FAIL ' || count(*) filter (where not pass) || coalesce(' :: ' || string_agg(id, ',' order by id) filter (where not pass), '') as line from t5
  union all select 1, id || ' ' || case when pass then 'PASS' else 'FAIL' end || ' [' || grp || '] ' || test || ' :: kutilgan=' || expected || ' :: natija=' || actual from t5) x order by ord, line;
select json_build_object('total', count(*), 'pass', count(*) filter (where pass), 'fail', count(*) filter (where not pass),
  'fail_ids', coalesce(json_agg(id || ' => ' || actual order by id) filter (where not pass), '[]'::json),
  'groups', (select json_object_agg(grp, n) from (select grp, count(*) || '/' || count(*) filter (where pass) n from t5 group by grp) g))::text as summary_006a from t5;
rollback;
