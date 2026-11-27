-- MedAcademy · 007c skills + competency test to'plami (lokal PGlite va staging uchun bir xil fayl).
-- Mavjud test akkauntlari (staging) bilan; yangi auth akkaunt yaratilmaydi. Hammasi BITTA tranzaksiyada, oxirida ROLLBACK.
-- Har bir foydalanuvchi so'rovi haqiqiy RLS / trigger / RPC orqali JWT claim'lari bilan bajariladi.
begin;
do $$ begin
  if not exists (select 1 from public.schema_migrations where version = '007c') then raise exception '007c qo''llanmagan'; end if;
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

do $$ declare oa uuid := pg_temp.c('OA')::uuid; ob uuid := pg_temp.c('OB')::uuid; begin
  perform pg_temp.logout();
  insert into t5ctx select 'BASE', json_build_object(
    'attempts_md5', (select md5(coalesce(string_agg(to_jsonb(a)::text, '' order by a.id), '')) from public.exam_attempts a),
    'certs_md5', (select md5(coalesce(string_agg(to_jsonb(c)::text, '' order by c.id), '')) from public.certificates c),
    'ca_md5', (select md5(coalesce(string_agg(to_jsonb(c)::text, '' order by c.id), '')) from public.course_assignments c),
    'lpa_md5', (select md5(coalesce(string_agg(to_jsonb(c)::text, '' order by c.id), '')) from public.learning_path_assignments c))::text;
  perform pg_temp.sys(format($q$
    insert into public.positions (org_id, name, code, status) values (%1$L, 'T7C lavozim', 'T7C_POS', 'active');
    insert into public.specialties (org_id, name, code, status) values (%1$L, 'T7C mutaxassislik', 'T7C_SPEC', 'active'), (%2$L, 'T7C B mutaxassislik', 'T7C_SPECB', 'active');
    update public.employees set position_id = (select id from public.positions where code = 'T7C_POS') where id = %3$L;
    insert into public.employees (org_id, employee_code, first_name, last_name, department_id, employment_status) values
      (%1$L, 'T7C_INACT', 'Nofaol', 'Xodim', (select id from public.departments where org_id = %1$L and code = 'CARDIO'), 'inactive');
  $q$, oa, ob, pg_temp.emp('EMP')));
end $$;

-- ===== K. Ko'nikma katalogi =====
do $$ declare r text; begin
  r := pg_temp.mk('EDU', 'T7C_ECG', 'EKG talqini', 5);
  perform pg_temp.ok('K01', 'Skill catalog', 'EM: ko''nikma yaratish', 'created', pg_temp.j(r, 'state'));
  perform pg_temp.ok('K02', 'Skill catalog', 'Takror kod (tashkilot ichida)', 'DENIED', pg_temp.mk('EDU', 'T7C_ECG', 'Boshqa', 5));
  perform pg_temp.ok('K03', 'Skill catalog', 'Tahrirlash → updated', 'updated',
    pg_temp.j(pg_temp.rpc(pg_temp.u('EDU'), format('public.upsert_skill(%L, null, ''EKG talqini (12 tarmoq)'', null, ''Klinik'', null, 5)', pg_temp.sk('T7C_ECG'))), 'state'));
  perform pg_temp.ok('K04', 'Skill catalog', 'Bir xil qiymatlar → unchanged (audit yo''q)', 'unchanged',
    pg_temp.j(pg_temp.rpc(pg_temp.u('EDU'), format('public.upsert_skill(%L, null, ''EKG talqini (12 tarmoq)'', null, ''Klinik'', null, 5)', pg_temp.sk('T7C_ECG'))), 'state'));
  perform pg_temp.ok('K05', 'Audit', 'skill.created 1, skill.updated 1', '1/1',
    (select count(*) filter (where action = 'skill.created') || '/' || count(*) filter (where action = 'skill.updated') from public.audit_logs where entity_id = pg_temp.sk('T7C_ECG')::text));
  perform pg_temp.ok('K06', 'Skill catalog', 'Kodni o''zgartirish', 'DENIED', pg_temp.rpc(pg_temp.u('EDU'), format('public.upsert_skill(%L, ''T7C_NEW'', ''X'', null, null, null, 5)', pg_temp.sk('T7C_ECG'))));
  perform pg_temp.ok('K07', 'Skill catalog', 'max_level 11', 'DENIED', pg_temp.mk('EDU', 'T7C_BAD', 'Noto''g''ri', 11));
  perform pg_temp.ok('K08', 'Skill catalog', 'Org B mutaxassisligi bilan', 'DENIED',
    pg_temp.rpc(pg_temp.u('EDU'), format('public.upsert_skill(null, ''T7C_XB'', ''Cross'', null, null, %L, 5)', (select id from public.specialties where code = 'T7C_SPECB'))));
  perform pg_temp.ok('K09', 'Role matrix', 'HR / Head / Instructor / MR / Employee: ko''nikma yaratish', 'DENIED/DENIED/DENIED/DENIED/DENIED',
    pg_temp.mk('HR', 'T7C_H', 'X') || '/' || pg_temp.mk('HEAD', 'T7C_D', 'X') || '/' || pg_temp.mk('INS', 'T7C_I', 'X') || '/' || pg_temp.mk('REV', 'T7C_R', 'X') || '/' || pg_temp.mk('EMP', 'T7C_E', 'X'));
  perform pg_temp.ok('K10', 'Role matrix', 'anon: ko''nikma yaratish', 'DENIED', pg_temp.rpca('public.upsert_skill(null, ''T7C_A'', ''X'')'));
  perform pg_temp.ok('K11', 'Role matrix', 'SA: ko''nikma yaratish', 'created', pg_temp.j(pg_temp.mk('SA', 'T7C_CPR', 'Yurak-o''pka reanimatsiyasi', 4), 'state'));
  perform pg_temp.ok('K12', 'Cross-org', 'Org B admin: shu kod bilan o''z tashkilotida (kod tashkilot ichida unique)', 'created', pg_temp.j(pg_temp.mk('BADM', 'T7C_ECG', 'Org B EKG'), 'state'));
  perform pg_temp.mk('EDU', 'T7C_OLD', 'Arxivlanadigan', 5);
end $$;

-- ===== A. Baholash =====
do $$ declare r text; begin
  r := pg_temp.asm('EDU', pg_temp.emp('EMP'), 'T7C_ECG', 3);
  perform pg_temp.ok('A01', 'Assessment', 'EM → EMP, daraja 3', '3', pg_temp.j(r, 'level'));
  perform pg_temp.ok('A02', 'Assessment', 'assessor_id = EM (soxta actor emas), audit 1', 'true/1',
    ((select assessor_id from public.skill_assessments where id = pg_temp.j(r, 'assessment_id')::uuid) = pg_temp.u('EDU'))::text || '/' ||
    (select count(*) from public.audit_logs where action = 'skill.assessment_created' and entity_id = pg_temp.j(r, 'assessment_id')));
  perform pg_temp.ok('A03', 'Department scope', 'Head → o''z bo''limi xodimi (EMP, Kardiologiya)', '2', pg_temp.j(pg_temp.asm('HEAD', pg_temp.emp('EMP'), 'T7C_CPR', 2), 'level'));
  perform pg_temp.ok('A04', 'Department scope', 'Head → boshqa bo''lim xodimi (EMP2, Terapiya)', 'DENIED', pg_temp.asm('HEAD', pg_temp.emp('EMP2'), 'T7C_ECG', 3));
  perform pg_temp.ok('A05', 'Assessment', 'SA → EMP2', '4', pg_temp.j(pg_temp.asm('SA', pg_temp.emp('EMP2'), 'T7C_ECG', 4), 'level'));
  perform pg_temp.ok('A06', 'Role matrix', 'HR / Instructor / MR / Employee baholashi', 'DENIED/DENIED/DENIED/DENIED',
    pg_temp.asm('HR', pg_temp.emp('EMP'), 'T7C_ECG', 3) || '/' || pg_temp.asm('INS', pg_temp.emp('EMP'), 'T7C_ECG', 3) || '/' || pg_temp.asm('REV', pg_temp.emp('EMP'), 'T7C_ECG', 3) || '/' || pg_temp.asm('EMP', pg_temp.emp('EMP2'), 'T7C_ECG', 3));
  perform pg_temp.ok('A07', 'Assessment', 'O''zini baholash (Head — o''zi ham xodim)', 'DENIED', pg_temp.asm('HEAD', pg_temp.emp('HEAD'), 'T7C_ECG', 5));
  perform pg_temp.ok('A08', 'Assessment', 'Daraja > max_level / manfiy', 'DENIED/DENIED', pg_temp.asm('EDU', pg_temp.emp('EMP'), 'T7C_ECG', 6) || '/' || pg_temp.asm('EDU', pg_temp.emp('EMP'), 'T7C_ECG', -1));
  perform pg_temp.ok('A09', 'Assessment', 'Mavjud bo''lmagan ko''nikma / xodim', 'DENIED/DENIED',
    pg_temp.rpc(pg_temp.u('EDU'), format('public.record_skill_assessment(%L, %L, 3)', pg_temp.emp('EMP'), gen_random_uuid())) || '/' ||
    pg_temp.rpc(pg_temp.u('EDU'), format('public.record_skill_assessment(%L, %L, 3)', gen_random_uuid(), pg_temp.sk('T7C_ECG'))));
  perform pg_temp.ok('A10', 'Cross-org', 'EM → Org B xodimi; Org B admin → Org A xodimi', 'DENIED/DENIED',
    pg_temp.asm('EDU', pg_temp.emp('BEMP'), 'T7C_ECG', 3) || '/' ||
    pg_temp.rpc(pg_temp.u('BADM'), format('public.record_skill_assessment(%L, (select id from public.skills where code = ''T7C_ECG'' and org_id = %L), 3)', pg_temp.emp('EMP'), pg_temp.c('OB'))));
  perform pg_temp.ok('A11', 'Assessment', 'Nofaol xodim', 'DENIED', pg_temp.asm('EDU', (select id from public.employees where employee_code = 'T7C_INACT'), 'T7C_ECG', 3));
  perform pg_temp.ok('A12', 'Role matrix', 'anon baholash', 'DENIED', pg_temp.rpca(format('public.record_skill_assessment(%L, %L, 3)', pg_temp.emp('EMP'), pg_temp.sk('T7C_ECG'))));
  perform pg_temp.asm('EDU', pg_temp.emp('EMP'), 'T7C_ECG', 2);
  perform pg_temp.ok('A13', 'History', 'Takror baholash ruxsat (tarix): EMP × ECG 2 qator', '2',
    (select count(*)::text from public.skill_assessments where employee_id = pg_temp.emp('EMP') and skill_id = pg_temp.sk('T7C_ECG')));
end $$;

-- ===== I. O'zgarmaslik =====
do $$ declare aid uuid := (select id from public.skill_assessments where employee_id = pg_temp.emp('EMP') order by created_at limit 1); begin
  perform pg_temp.ok('I01', 'Immutability', 'EM to''g''ridan-to''g''ri UPDATE / DELETE / INSERT (grant yo''q)', 'DENIED/DENIED/DENIED',
    pg_temp.w(pg_temp.u('EDU'), format('update public.skill_assessments set level = 5 where id = %L', aid)) || '/' ||
    pg_temp.w(pg_temp.u('EDU'), format('delete from public.skill_assessments where id = %L', aid)) || '/' ||
    pg_temp.w(pg_temp.u('EDU'), format('insert into public.skill_assessments (org_id, skill_id, employee_id, assessor_id, level) values (%L, %L, %L, %L, 5)', pg_temp.c('OA'), pg_temp.sk('T7C_ECG'), pg_temp.emp('EMP'), pg_temp.u('SA'))));
  perform pg_temp.ok('I02', 'Immutability', 'SQL (superuser) UPDATE / DELETE / TRUNCATE — trigger rad', 'DENIED/DENIED/DENIED',
    (select case when pg_temp.sysok(format('update public.skill_assessments set level = 5 where id = %L', aid)) then 'OK' else 'DENIED' end) || '/' ||
    (select case when pg_temp.sysok(format('delete from public.skill_assessments where id = %L', aid)) then 'OK' else 'DENIED' end) || '/' ||
    (select case when pg_temp.sysok('truncate public.skill_assessments') then 'OK' else 'DENIED' end));
  perform pg_temp.ok('I03', 'Immutability', 'SQL: boshqa tashkilot baholovchisi bilan INSERT (guard)', 'DENIED',
    (select case when pg_temp.sysok(format('insert into public.skill_assessments (org_id, skill_id, employee_id, assessor_id, level) values (%L, %L, %L, %L, 3)', pg_temp.c('OA'), pg_temp.sk('T7C_ECG'), pg_temp.emp('EMP'), pg_temp.u('BADM'))) then 'OK' else 'DENIED' end));
  perform pg_temp.ok('I04', 'Immutability', 'Baholash darajasi o''zgarmagan', '3', (select level::text from public.skill_assessments where id = aid));
  perform pg_temp.ok('I05', 'Immutability', 'Mavjud baholashdan past max_level o''rnatib bo''lmaydi', 'DENIED',
    pg_temp.rpc(pg_temp.u('EDU'), format('public.upsert_skill(%L, null, ''EKG talqini (12 tarmoq)'', null, ''Klinik'', null, 2)', pg_temp.sk('T7C_ECG'))));
end $$;

-- ===== C. Kompetensiya talablari =====
do $$ declare rid text; begin
  rid := pg_temp.j(pg_temp.req('EDU', 'T7C_ECG', 'department', pg_temp.dep('OA', 'CARDIO'), 3), 'requirement_id');
  perform pg_temp.ok('C01', 'Requirement', 'EM: Kardiologiya bo''limi, ECG ≥ 3 → created', 'true', (rid is not null and rid <> 'DENIED')::text);
  perform pg_temp.ok('C02', 'Requirement', 'Bir xil → unchanged', 'unchanged', pg_temp.j(pg_temp.req('EDU', 'T7C_ECG', 'department', pg_temp.dep('OA', 'CARDIO'), 3), 'state'));
  perform pg_temp.ok('C03', 'Requirement', 'Daraja 4 → updated', 'updated', pg_temp.j(pg_temp.req('EDU', 'T7C_ECG', 'department', pg_temp.dep('OA', 'CARDIO'), 4), 'state'));
  perform pg_temp.ok('C04', 'Audit', 'created 1, updated 1', '1/1',
    (select count(*) filter (where action = 'competency_requirement.created') || '/' || count(*) filter (where action = 'competency_requirement.updated') from public.audit_logs where entity_id = rid));
  perform pg_temp.ok('C05', 'Requirement', 'Lavozim talabi (ECG ≥ 2) va rol talabi (CPR ≥ 3, employee)', 'created/created',
    pg_temp.j(pg_temp.req('EDU', 'T7C_ECG', 'position', (select id::text from public.positions where code = 'T7C_POS'), 2), 'state') || '/' ||
    pg_temp.j(pg_temp.req('EDU', 'T7C_CPR', 'role', 'employee', 3), 'state'));
  perform pg_temp.ok('C06', 'Role matrix', 'HR / Head / Instructor / Employee: talab', 'DENIED/DENIED/DENIED/DENIED',
    pg_temp.req('HR', 'T7C_ECG', 'role', 'hr', 2) || '/' || pg_temp.req('HEAD', 'T7C_ECG', 'department', pg_temp.dep('OA', 'CARDIO'), 2) || '/' ||
    pg_temp.req('INS', 'T7C_ECG', 'role', 'hr', 2) || '/' || pg_temp.req('EMP', 'T7C_ECG', 'role', 'hr', 2));
  perform pg_temp.ok('C07', 'Cross-org', 'Org B bo''limi / mutaxassisligi', 'DENIED/DENIED',
    pg_temp.req('EDU', 'T7C_ECG', 'department', pg_temp.dep('OB', 'CARDIO'), 2) || '/' || pg_temp.req('EDU', 'T7C_ECG', 'specialty', (select id::text from public.specialties where code = 'T7C_SPECB'), 2));
  perform pg_temp.ok('C08', 'Requirement', 'Daraja > max / 0 / noma''lum tur / noto''g''ri UUID', 'DENIED/DENIED/DENIED/DENIED',
    pg_temp.req('EDU', 'T7C_ECG', 'role', 'hr', 6) || '/' || pg_temp.req('EDU', 'T7C_ECG', 'role', 'hr', 0) || '/' ||
    pg_temp.req('EDU', 'T7C_ECG', 'branch', 'x', 2) || '/' || pg_temp.req('EDU', 'T7C_ECG', 'department', 'not-a-uuid', 2));
  perform pg_temp.ok('C09', 'Constraint', 'SQL: ikki nishonli talab rad', 'DENIED',
    (select case when pg_temp.sysok(format('insert into public.competency_requirements (org_id, skill_id, target_type, department_id, target_role, required_level) values (%L, %L, ''department'', %L, ''hr'', 2)', pg_temp.c('OA'), pg_temp.sk('T7C_ECG'), pg_temp.dep('OA', 'CARDIO'))) then 'OK' else 'DENIED' end));
end $$;

-- ===== S. Kompetensiya holati va ko'rish doirasi =====
do $$ declare a0 int; begin
  perform pg_temp.ok('S01', 'Threshold', 'EMP ECG: talab max(4 bo''lim, 2 lavozim) = 4; so''nggi baholash 2 → not_achieved', '4/2/not_achieved', pg_temp.sum('EMP', null, 'T7C_ECG'));
  perform pg_temp.asm('EDU', pg_temp.emp('EMP'), 'T7C_ECG', 4);
  perform pg_temp.ok('S02', 'Threshold', 'Yangi baholash 4 → achieved; tarix 3 qator', '4/4/achieved/3',
    pg_temp.sum('EMP', null, 'T7C_ECG') || '/' || (select count(*) from public.skill_assessments where employee_id = pg_temp.emp('EMP') and skill_id = pg_temp.sk('T7C_ECG')));
  perform pg_temp.ok('S03', 'Threshold', 'EMP CPR: rol talabi 3, baholash 2 → not_achieved', '3/2/not_achieved', pg_temp.sum('EMP', null, 'T7C_CPR'));
  perform pg_temp.ok('S04', 'Threshold', 'EMP2 (Terapiya, employee roli): CPR talab 3, baholash yo''q → not_assessed; ECG talab yo''q, baholangan → not_required', '3/-/not_assessed;-/4/not_required',
    pg_temp.sum('EMP2', null, 'T7C_CPR') || ';' || pg_temp.sum('EMP2', null, 'T7C_ECG'));
  perform pg_temp.ok('S05', 'Scope', 'EMP → EMP2 kompetensiyasi', 'DENIED', pg_temp.sum('EMP', pg_temp.emp('EMP2'), 'T7C_ECG'));
  perform pg_temp.ok('S06', 'Scope', 'Head → EMP (o''z bo''limi) / EMP2 (boshqa)', '4/4/achieved;DENIED', pg_temp.sum('HEAD', pg_temp.emp('EMP'), 'T7C_ECG') || ';' || pg_temp.sum('HEAD', pg_temp.emp('EMP2'), 'T7C_ECG'));
  perform pg_temp.ok('S07', 'Scope', 'HR / EM → EMP2', '-/4/not_required;-/4/not_required', pg_temp.sum('HR', pg_temp.emp('EMP2'), 'T7C_ECG') || ';' || pg_temp.sum('EDU', pg_temp.emp('EMP2'), 'T7C_ECG'));
  perform pg_temp.ok('S08', 'Scope', 'Instructor / MR / Org B admin → EMP', 'DENIED/DENIED/DENIED',
    pg_temp.sum('INS', pg_temp.emp('EMP'), 'T7C_ECG') || '/' || pg_temp.sum('REV', pg_temp.emp('EMP'), 'T7C_ECG') || '/' || pg_temp.sum('BADM', pg_temp.emp('EMP'), 'T7C_ECG'));
  perform pg_temp.ok('S09', 'Scope', 'anon: xodim kompetensiyasi', 'DENIED', pg_temp.rpca(format('(select count(*) from public.employee_competency_summary(%L))', pg_temp.emp('EMP'))));
  perform pg_temp.ok('D01', 'Department summary', 'EM: Kardiologiya — ECG talab qilinganlar / achieved', 'true',
    (pg_temp.rpc(pg_temp.u('EDU'), format('public.department_competency_summary(%L)', pg_temp.dep('OA', 'CARDIO'))) like '{%')::text);
  perform pg_temp.ok('D02', 'Department summary', 'Head: o''z bo''limi OK / Terapiya DENIED', 'true/DENIED',
    (pg_temp.rpc(pg_temp.u('HEAD'), format('public.department_competency_summary(%L)', pg_temp.dep('OA', 'CARDIO'))) like '{%')::text || '/' ||
    pg_temp.rpc(pg_temp.u('HEAD'), format('public.department_competency_summary(%L)', pg_temp.dep('OA', 'THERAPY'))));
  perform pg_temp.ok('D03', 'Department summary', 'Instructor / Employee / Org B admin / anon', 'DENIED/DENIED/DENIED/DENIED',
    pg_temp.rpc(pg_temp.u('INS'), format('public.department_competency_summary(%L)', pg_temp.dep('OA', 'CARDIO'))) || '/' ||
    pg_temp.rpc(pg_temp.u('EMP'), format('public.department_competency_summary(%L)', pg_temp.dep('OA', 'CARDIO'))) || '/' ||
    pg_temp.rpc(pg_temp.u('BADM'), format('public.department_competency_summary(%L)', pg_temp.dep('OA', 'CARDIO'))) || '/' ||
    pg_temp.rpca(format('public.department_competency_summary(%L)', pg_temp.dep('OA', 'CARDIO'))));
  a0 := (select count(*) from public.audit_logs);
  perform pg_temp.sum('EMP', null, 'T7C_ECG'); perform pg_temp.sum('HR', pg_temp.emp('EMP'), 'T7C_ECG');
  perform pg_temp.rpc(pg_temp.u('EDU'), format('public.department_competency_summary(%L)', pg_temp.dep('OA', 'CARDIO')));
  perform pg_temp.ok('D04', 'Audit', 'O''qish (summary) audit yozmaydi', a0::text, (select count(*)::text from public.audit_logs));
end $$;

-- ===== R. RLS =====
do $$ begin
  perform pg_temp.ok('R01', 'RLS', 'EMP: faqat o''z baholashlari', (select count(*)::text from public.skill_assessments where employee_id = pg_temp.emp('EMP')),
    pg_temp.cnt(pg_temp.u('EMP'), 'select 1 from public.skill_assessments')::text);
  perform pg_temp.ok('R02', 'RLS', 'EMP2: EMP baholashlarini ko''rmaydi', '0', pg_temp.cnt(pg_temp.u('EMP2'), format('select 1 from public.skill_assessments where employee_id = %L', pg_temp.emp('EMP')))::text);
  perform pg_temp.ok('R03', 'RLS', 'Head: faqat Kardiologiya baholashlari (EMP2 ko''rinmaydi)', '0', pg_temp.cnt(pg_temp.u('HEAD'), format('select 1 from public.skill_assessments where employee_id = %L', pg_temp.emp('EMP2')))::text);
  perform pg_temp.ok('R04', 'RLS', 'HR: tashkilotdagi barcha baholashlar', (select count(*)::text from public.skill_assessments where org_id = pg_temp.c('OA')::uuid),
    pg_temp.cnt(pg_temp.u('HR'), 'select 1 from public.skill_assessments')::text);
  perform pg_temp.ok('R05', 'RLS', 'Instructor / MR: baholashlar 0', '0/0', pg_temp.cnt(pg_temp.u('INS'), 'select 1 from public.skill_assessments') || '/' || pg_temp.cnt(pg_temp.u('REV'), 'select 1 from public.skill_assessments'));
  perform pg_temp.ok('R06', 'RLS', 'Org B admin: Org A baholashlari / ko''nikmalari 0', '0/0',
    pg_temp.cnt(pg_temp.u('BADM'), format('select 1 from public.skill_assessments where org_id = %L', pg_temp.c('OA'))) || '/' || pg_temp.cnt(pg_temp.u('BADM'), format('select 1 from public.skills where org_id = %L', pg_temp.c('OA'))));
  perform pg_temp.ok('R07', 'RLS', 'EMP: tashkilot katalogi ko''rinadi (Org B ko''nikmasi yo''q)', 'true/0',
    (pg_temp.cnt(pg_temp.u('EMP'), 'select 1 from public.skills') >= 3)::text || '/' || pg_temp.cnt(pg_temp.u('EMP'), format('select 1 from public.skills where org_id = %L', pg_temp.c('OB'))));
  perform pg_temp.ok('R08', 'RLS', 'anon: skills / skill_assessments / competency_requirements', 'DENIED/DENIED/DENIED',
    pg_temp.wa('select 1 from public.skills') || '/' || pg_temp.wa('select 1 from public.skill_assessments') || '/' || pg_temp.wa('select 1 from public.competency_requirements'));
  perform pg_temp.ok('R09', 'RLS', 'EM: skills / requirements to''g''ridan-to''g''ri INSERT / UPDATE / DELETE', 'DENIED/DENIED/DENIED/DENIED',
    pg_temp.w(pg_temp.u('EDU'), format('insert into public.skills (org_id, code, name) values (%L, ''T7C_DIRECT'', ''X'')', pg_temp.c('OA'))) || '/' ||
    pg_temp.w(pg_temp.u('EDU'), 'update public.skills set name = ''X''') || '/' ||
    pg_temp.w(pg_temp.u('EDU'), 'delete from public.competency_requirements') || '/' ||
    pg_temp.w(pg_temp.u('EDU'), 'update public.competency_requirements set required_level = 1'));
end $$;

-- ===== X. Arxivlash =====
do $$ begin
  perform pg_temp.req('EDU', 'T7C_OLD', 'role', 'employee', 2);
  perform pg_temp.ok('X01', 'Archive', 'Sababsiz arxivlash', 'DENIED', pg_temp.rpc(pg_temp.u('EDU'), format('public.archive_skill(%L, '''')', pg_temp.sk('T7C_OLD'))));
  perform pg_temp.ok('X02', 'Archive', 'Sabab bilan → changed; takror → false', 'true/false',
    pg_temp.j(pg_temp.rpc(pg_temp.u('EDU'), format('public.archive_skill(%L, ''Katalog yangilandi'')', pg_temp.sk('T7C_OLD'))), 'changed') || '/' ||
    pg_temp.j(pg_temp.rpc(pg_temp.u('EDU'), format('public.archive_skill(%L, ''yana'')', pg_temp.sk('T7C_OLD'))), 'changed'));
  perform pg_temp.ok('X03', 'Archive', 'Arxivlangan ko''nikma: baholash / talab rad; xodim xulosasida yo''q', 'DENIED/DENIED/none',
    pg_temp.asm('EDU', pg_temp.emp('EMP'), 'T7C_OLD', 1) || '/' || pg_temp.req('EDU', 'T7C_OLD', 'role', 'hr', 2) || '/' || pg_temp.sum('EMP', null, 'T7C_OLD'));
  perform pg_temp.ok('X04', 'Archive', 'SQL: qayta faollashtirish / DELETE (guard)', 'DENIED/DENIED',
    (select case when pg_temp.sysok(format('update public.skills set status = ''active'', archived_at = null where id = %L', pg_temp.sk('T7C_OLD'))) then 'OK' else 'DENIED' end) || '/' ||
    (select case when pg_temp.sysok(format('delete from public.skills where id = %L', pg_temp.sk('T7C_OLD'))) then 'OK' else 'DENIED' end));
  insert into t5ctx select 'X05', pg_temp.j(pg_temp.rpc(pg_temp.u('EDU'), format('public.archive_competency_requirement(%L, ''Eskirgan talab'')',
      (select id from public.competency_requirements where skill_id = pg_temp.sk('T7C_ECG') and target_type = 'position'))), 'changed');
  perform pg_temp.ok('X05', 'Archive', 'Talabni arxivlash (sabab bilan) va audit', 'true/1', pg_temp.c('X05') || '/' || (select count(*) from public.audit_logs where action = 'competency_requirement.archived'));
  perform pg_temp.ok('X06', 'Archive', 'Audit skill.archived 1', '1', (select count(*)::text from public.audit_logs where action = 'skill.archived' and entity_id = pg_temp.sk('T7C_OLD')::text));
end $$;

-- ===== N. Yangi tashkilot ruxsatlari =====
do $$ begin
  perform pg_temp.sys($q$insert into public.organizations (id, name) values ('0000007c-0000-0000-0000-00000000007c', 'T7C yangi tashkilot')$q$);
  perform pg_temp.ok('N01', 'Permissions', 'Yangi tashkilot: 007c rol ruxsatlari avtomatik (8 ta)', '8',
    (select count(*)::text from public.role_permissions where org_id = '0000007c-0000-0000-0000-00000000007c' and permission_key in ('skill.view','skill.manage','skill.assess','competency.manage')));
  perform pg_temp.ok('N02', 'Permissions', 'Mavjud tashkilotlarda: EM 4, Head 2 (view+assess), HR 1, Instructor 1, MR 0, Employee 0', '4/2/1/1/0/0',
    (select string_agg(n::text, '/' order by o) from (values ('education_manager', 1), ('department_head', 2), ('hr', 3), ('instructor', 4), ('medical_reviewer', 5), ('employee', 6)) r(role, o)
      cross join lateral (select count(*) n from public.role_permissions rp where rp.org_id = pg_temp.c('OA')::uuid and rp.role = r.role and rp.permission_key in ('skill.view','skill.manage','skill.assess','competency.manage')) c));
end $$;

-- ===== V. Invariantlar =====
do $$ begin
  perform pg_temp.ok('V01', 'Invariants', 'anon EXECUTE faqat verify_certificate', 'verify_certificate',
    (select string_agg(p.proname, ',') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'EXECUTE')));
  perform pg_temp.ok('V02', 'Invariants', 'Ichki 007c funksiyalari authenticated uchun yopiq (RLS predikati _sk_my_dept_employees_007c bundan mustasno)', '0',
    (select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_sk_seed_perms_007c','seed_org_skill_perms_007c','guard_skill_007c','guard_skill_assessment_007c','guard_skill_assessment_truncate_007c','guard_competency_req_007c','_sk_can_view_employee_007c','_sk_emp_competency_007c') and has_function_privilege('authenticated', p.oid, 'EXECUTE')));
  perform pg_temp.ok('V03', 'Invariants', 'Urinishlar / sertifikatlar / kurs tayinlashlari / yo''nalish qoidalari o''zgarmagan', 'true/true/true/true',
    ((select md5(coalesce(string_agg(to_jsonb(a)::text, '' order by a.id), '')) from public.exam_attempts a) = (pg_temp.c('BASE')::json ->> 'attempts_md5'))::text || '/' ||
    ((select md5(coalesce(string_agg(to_jsonb(c)::text, '' order by c.id), '')) from public.certificates c) = (pg_temp.c('BASE')::json ->> 'certs_md5'))::text || '/' ||
    ((select md5(coalesce(string_agg(to_jsonb(c)::text, '' order by c.id), '')) from public.course_assignments c) = (pg_temp.c('BASE')::json ->> 'ca_md5'))::text || '/' ||
    ((select md5(coalesce(string_agg(to_jsonb(c)::text, '' order by c.id), '')) from public.learning_path_assignments c) = (pg_temp.c('BASE')::json ->> 'lpa_md5'))::text);
  perform pg_temp.ok('V04', 'Invariants', 'CASCADE FK yo''q', '0', (select count(*)::text from pg_constraint where connamespace = 'public'::regnamespace and contype = 'f' and confdeltype = 'c'));
  perform pg_temp.ok('V05', 'Invariants', 'Jadvallar 48 (+3); RLS 3/3; yozish grant''lari 0', (48 + (select count(*) from public.schema_migrations where version = '007d'))::text || '/3/0',
    (select count(*) from pg_tables where schemaname = 'public') || '/' ||
    (select count(*) from pg_class where oid in ('public.skills'::regclass, 'public.skill_assessments'::regclass, 'public.competency_requirements'::regclass) and relrowsecurity) || '/' ||
    (select count(*) from information_schema.role_table_grants where table_schema = 'public' and table_name in ('skills','skill_assessments','competency_requirements') and grantee in ('anon','authenticated') and privilege_type <> 'SELECT'));
end $$;

select line from (
  select 0 ord, 'SUMMARY 007c total ' || count(*) || ' / PASS ' || count(*) filter (where pass) || ' / FAIL ' || count(*) filter (where not pass) || coalesce(' :: ' || string_agg(id, ',' order by id) filter (where not pass), '') as line from t5
  union all select 1, id || ' ' || case when pass then 'PASS' else 'FAIL' end || ' [' || grp || '] ' || test || ' :: kutilgan=' || expected || ' :: natija=' || actual from t5) x order by ord, line;
select json_build_object('total', count(*), 'pass', count(*) filter (where pass), 'fail', count(*) filter (where not pass),
  'fail_ids', coalesce(json_agg(id || ' => ' || actual order by id) filter (where not pass), '[]'::json),
  'groups', (select json_object_agg(grp, n) from (select grp, count(*) || '/' || count(*) filter (where pass) n from t5 group by grp) g))::text as summary_007c from t5;
rollback;
