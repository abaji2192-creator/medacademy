-- MedAcademy · Phase 3 Frontend STEP 3 — Admin Panel staging QA (server darajasi). UI chaqiradigan RPC'lar AYNAN frontend argumentlari bilan,
-- har bir rol uchun haqiqiy RLS / trigger / RPC orqali (JWT claim'lari). Yangi auth akkaunt / parol yo'q. Hammasi BITTA tranzaksiyada, oxirida ROLLBACK.
-- Har bir foydalanuvchi so'rovi haqiqiy RLS / trigger / RPC orqali JWT claim'lari bilan bajariladi.
begin;
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


-- ---------- Kontekst (mavjud staging ma'lumotlari; fixture yo'q) ----------
do $$ declare oa uuid := pg_temp.c('OA')::uuid; begin
  perform pg_temp.logout();
  insert into t5ctx values ('EMPID', pg_temp.emp('EMP')::text), ('EMP2ID', pg_temp.emp('EMP2')::text),
    ('DEP', (select department_id::text from public.employees where id = pg_temp.emp('EMP'))),
    ('DEP2', (select department_id::text from public.employees where id = pg_temp.emp('EMP2'))),
    ('HEADDEP', (select department_id::text from public.employees where id = pg_temp.emp('HEAD'))),
    ('PATH', (select lp.id::text from public.learning_paths lp where lp.org_id = oa and lp.status = 'published'
               and exists (select 1 from public.learning_path_courses c join public.courses co on co.id = c.course_id and co.status = 'published' where c.path_id = lp.id) order by lp.code limit 1)),
    ('SIDE0', pg_temp.side());
  insert into t5ctx values ('COURSE', (select c.course_id from public.learning_path_courses c where c.path_id = pg_temp.u('PATH') order by c.order_index limit 1));
  insert into t5ctx select 'BASE', json_build_object(
    'attempts_md5', (select md5(coalesce(string_agg(to_jsonb(a)::text, '' order by a.id), '')) from public.exam_attempts a),
    'certs_md5', (select md5(coalesce(string_agg(to_jsonb(c)::text, '' order by c.id), '')) from public.certificates c),
    'questions_md5', (select md5(coalesce(string_agg(to_jsonb(q)::text, '' order by q.id), '')) from public.questions q))::text;
end $$;
create function pg_temp.ca(e text) returns int language sql security definer as $$ select count(*)::int from public.course_assignments where employee_id = e::uuid $$;
create function pg_temp.ca_live(e text) returns int language sql security definer as $$ select count(*)::int from public.course_assignments where employee_id = e::uuid and status <> 'cancelled' $$;

-- ================= Learning Paths (pages_learning.js) =================
do $$ declare r text; c0 int; c1 int; rule uuid; begin
  perform pg_temp.okb('L00', 'Learning', 'Staging: published path + kurs topildi', 'bor', coalesce(pg_temp.c('PATH'), 'NULL'), pg_temp.c('PATH') is not null);
  c0 := pg_temp.ca(pg_temp.c('EMPID'));
  r := pg_temp.rpc(pg_temp.u('EDU'), format('public.apply_learning_path(%L, ''employee'', %L, null)', pg_temp.c('PATH'), pg_temp.c('EMPID')));
  c1 := pg_temp.ca(pg_temp.c('EMPID')); rule := nullif(pg_temp.j(r, 'assignment_id'), '')::uuid; insert into t5ctx values ('RULE', rule::text);
  perform pg_temp.okb('L01', 'Learning', 'EM apply_learning_path (UI argumentlari) → qoida yaratildi', 'created / +kurslar', pg_temp.j(r, 'rule') || ' / +' || (c1 - c0) || ' (resp ' || coalesce(pg_temp.j(r, 'course_assignments_created'), '?') || ')',
    pg_temp.j(r, 'rule') = 'created' and c1 - c0 = (pg_temp.j(r, 'course_assignments_created'))::int);
  r := pg_temp.rpc(pg_temp.u('EDU'), format('public.apply_learning_path(%L, ''employee'', %L, null)', pg_temp.c('PATH'), pg_temp.c('EMPID')));
  perform pg_temp.okb('L02', 'Learning', 'Takroriy apply idempotent', 'existing / 0 / +0', pg_temp.j(r, 'rule') || ' / ' || pg_temp.j(r, 'course_assignments_created') || ' / +' || (pg_temp.ca(pg_temp.c('EMPID')) - c1),
    pg_temp.j(r, 'rule') = 'existing' and pg_temp.j(r, 'course_assignments_created') = '0' and pg_temp.ca(pg_temp.c('EMPID')) = c1);
  r := pg_temp.rpc(pg_temp.u('EDU'), format('public.reapply_learning_path_assignment(%L)', rule));
  perform pg_temp.okb('L03', 'Learning', 'reapply dublikat yaratmaydi', '0 / +0', pg_temp.j(r, 'course_assignments_created') || ' / +' || (pg_temp.ca(pg_temp.c('EMPID')) - c1),
    pg_temp.j(r, 'course_assignments_created') = '0' and pg_temp.ca(pg_temp.c('EMPID')) = c1);
  c0 := pg_temp.ca_live(pg_temp.c('EMPID'));
  r := pg_temp.rpc(pg_temp.u('EDU'), format('public.cancel_learning_path_assignment(%L, ''STEP3 staging QA'')', rule));
  perform pg_temp.okb('L04', 'Learning', 'cancel: qoida cancelled, kurs tayinlashlari saqlanadi', 'cancelled / true / ' || c0,
    pg_temp.j(r, 'status') || ' / ' || pg_temp.j(r, 'changed') || ' / ' || pg_temp.ca_live(pg_temp.c('EMPID')), pg_temp.j(r, 'status') = 'cancelled' and pg_temp.ca_live(pg_temp.c('EMPID')) = c0);
  r := pg_temp.rpc(pg_temp.u('EDU'), format('public.cancel_learning_path_assignment(%L, ''yana'')', rule));
  perform pg_temp.ok('L05', 'Learning', 'Qayta cancel → changed=false', 'false', pg_temp.j(r, 'changed'));
  perform pg_temp.ok('L06', 'Learning', 'EM: qoidalar ro''yxati (UI select) ko''rinadi', '1', pg_temp.cnt(pg_temp.u('EDU'), format('select 1 from public.learning_path_assignments where id = %L', rule))::text);
  perform pg_temp.ok('L07', 'Learning', 'HR to''g''ridan-to''g''ri INSERT learning_path_assignments → rad', 'DENIED|OK:0',
    pg_temp.w(pg_temp.u('HR'), format('insert into public.learning_path_assignments (org_id, path_id, target_type, target_role) values (%L, %L, ''role'', ''employee'')', pg_temp.c('OA'), pg_temp.c('PATH'))));
  perform pg_temp.ok('L08', 'Learning', 'Department Head apply → rad', 'DENIED', pg_temp.rpc(pg_temp.u('HEAD'), format('public.apply_learning_path(%L, ''role'', ''employee'', null)', pg_temp.c('PATH'))));
  perform pg_temp.ok('L09', 'Learning', 'Employee apply → rad', 'DENIED', pg_temp.rpc(pg_temp.u('EMP'), format('public.apply_learning_path(%L, ''role'', ''employee'', null)', pg_temp.c('PATH'))));
  perform pg_temp.ok('L10', 'Learning', 'Instructor apply → rad', 'DENIED', pg_temp.rpc(pg_temp.u('INS'), format('public.apply_learning_path(%L, ''role'', ''employee'', null)', pg_temp.c('PATH'))));
  perform pg_temp.ok('L11', 'Learning', 'Org B admin → Org A path apply → rad', 'DENIED', pg_temp.rpc(pg_temp.u('BADM'), format('public.apply_learning_path(%L, ''role'', ''employee'', null)', pg_temp.c('PATH'))));
  perform pg_temp.ok('L12', 'Learning', 'Org B admin Org A path''ni ko''rmaydi', '0', pg_temp.cnt(pg_temp.u('BADM'), format('select 1 from public.learning_paths where id = %L', pg_temp.c('PATH')))::text);
end $$;

-- ================= Course Progress =================
do $$ declare r text; n int; begin
  r := pg_temp.rpc(pg_temp.u('EDU'), format('public.course_progress_summary(%L)', pg_temp.c('COURSE')));
  select count(*) into n from public.course_assignments where course_id = pg_temp.c('COURSE') and org_id = pg_temp.u('OA');
  perform pg_temp.okb('P01', 'Progress', 'EM course_progress_summary: assigned_count = server jadvali', n::text, pg_temp.j(r, 'assigned_count') || ' (scope ' || pg_temp.j(r, 'scope') || ')',
    pg_temp.j(r, 'assigned_count')::int in (n, n - coalesce(pg_temp.j(r, 'cancelled_count')::int, 0)));
  perform pg_temp.okb('P02', 'Progress', 'Statuslar yig''indisi = assigned (not_started+in_progress+completed)', pg_temp.j(r, 'assigned_count'),
    (pg_temp.j(r, 'not_started_count')::int + pg_temp.j(r, 'in_progress_count')::int + pg_temp.j(r, 'completed_count')::int)::text,
    pg_temp.j(r, 'not_started_count')::int + pg_temp.j(r, 'in_progress_count')::int + pg_temp.j(r, 'completed_count')::int <= pg_temp.j(r, 'assigned_count')::int);
  r := pg_temp.rpc(pg_temp.u('INS2'), format('public.course_progress_summary(%L)', pg_temp.c('COURSE')));
  perform pg_temp.okb('P03', 'Progress', 'Biriktirilmagan Instructor2 → rad yoki 0 (instructor scope)', 'DENIED|instructor', left(r, 60), r = 'DENIED' or pg_temp.j(r, 'scope') = 'instructor');
  perform pg_temp.ok('P04', 'Progress', 'Employee course_progress_summary → rad', 'DENIED', pg_temp.rpc(pg_temp.u('EMP'), format('public.course_progress_summary(%L)', pg_temp.c('COURSE'))));
  perform pg_temp.ok('P05', 'Progress', 'Anonim course_progress_summary → rad', 'DENIED', pg_temp.rpca(format('public.course_progress_summary(%L)', pg_temp.c('COURSE'))));
end $$;

-- ================= Skills / Requirements / Assessments (pages_skills.js) =================
do $$ declare r text; sk uuid; rq uuid; begin
  r := pg_temp.rpc(pg_temp.u('EDU'), 'public.upsert_skill(null, ''STEP3_ECG'', ''EKG talqini'', null, ''Kardiologiya'', null, 5)');
  sk := pg_temp.sk('STEP3_ECG'); insert into t5ctx values ('SK', sk::text);
  perform pg_temp.okb('S01', 'Skills', 'EM upsert_skill (yaratish)', 'active/5', coalesce((select status || '/' || max_level from public.skills where id = sk), r), (select status = 'active' and max_level = 5 from public.skills where id = sk));
  r := pg_temp.rpc(pg_temp.u('EDU'), format('public.upsert_skill(%L, ''STEP3_ECG'', ''EKG talqini (12 tarmoq)'', null, ''Kardiologiya'', null, 5)', sk));
  perform pg_temp.ok('S02', 'Skills', 'EM upsert_skill (tahrirlash)', 'EKG talqini (12 tarmoq)', (select name from public.skills where id = sk));
  perform pg_temp.ok('S03', 'Skills', 'Instructor upsert_skill → rad', 'DENIED', pg_temp.rpc(pg_temp.u('INS'), 'public.upsert_skill(null, ''STEP3_X'', ''Ruxsatsiz'', null, null, null, 5)'));
  perform pg_temp.ok('S04', 'Skills', 'Instructor skills ro''yxatini ko''radi (skill.view)', '1', pg_temp.cnt(pg_temp.u('INS'), format('select 1 from public.skills where id = %L', sk))::text);
  r := pg_temp.req('EDU', 'STEP3_ECG', 'department', pg_temp.c('DEP'), 3);
  rq := (select id from public.competency_requirements where skill_id = sk and status = 'active' limit 1); insert into t5ctx values ('RQ', rq::text);
  perform pg_temp.ok('S05', 'Skills', 'EM set_competency_requirement (bo''lim, 3)', '3', (select required_level::text from public.competency_requirements where id = rq));
  perform pg_temp.okb('S06', 'Skills', 'Baholashsiz → not_assessed', 'not_assessed', pg_temp.rpc(pg_temp.u('EDU'), format('(select c ->> ''status'' from jsonb_array_elements(public.employee_competency_matrix(%L) -> ''competencies'') c where c ->> ''skill_id'' = %L)', pg_temp.c('EMPID'), sk)),
    pg_temp.rpc(pg_temp.u('EDU'), format('(select c ->> ''status'' from jsonb_array_elements(public.employee_competency_matrix(%L) -> ''competencies'') c where c ->> ''skill_id'' = %L)', pg_temp.c('EMPID'), sk)) = 'not_assessed');
  perform pg_temp.asm('EDU', pg_temp.u('EMPID'), 'STEP3_ECG', 2);
  perform pg_temp.ok('S07', 'Skills', 'Daraja 2 < 3 → not_achieved', 'not_achieved', pg_temp.rpc(pg_temp.u('EDU'), format('(select c ->> ''status'' from jsonb_array_elements(public.employee_competency_matrix(%L) -> ''competencies'') c where c ->> ''skill_id'' = %L)', pg_temp.c('EMPID'), sk)));
  perform pg_temp.asm('EDU', pg_temp.u('EMPID'), 'STEP3_ECG', 4);
  perform pg_temp.ok('S08', 'Skills', 'Daraja 4 → achieved', 'achieved', pg_temp.rpc(pg_temp.u('EDU'), format('(select c ->> ''status'' from jsonb_array_elements(public.employee_competency_matrix(%L) -> ''competencies'') c where c ->> ''skill_id'' = %L)', pg_temp.c('EMPID'), sk)));
  perform pg_temp.ok('S09', 'Skills', 'Tarix insert-only: 2 yozuv (2,4)', '2,4', (select string_agg(level::text, ',' order by assessment_seq) from public.skill_assessments where skill_id = sk));
  perform pg_temp.ok('S10', 'Skills', 'EM skill_assessments UPDATE → rad / 0', 'DENIED|OK:0', pg_temp.w(pg_temp.u('EDU'), format('update public.skill_assessments set level = 9 where skill_id = %L', sk)));
  perform pg_temp.ok('S11', 'Skills', 'EM skill_assessments DELETE → rad / 0', 'DENIED|OK:0', pg_temp.w(pg_temp.u('EDU'), format('delete from public.skill_assessments where skill_id = %L', sk)));
  perform pg_temp.ok('S12', 'Skills', 'Tarix o''zgarmagan', '2,4', (select string_agg(level::text, ',' order by assessment_seq) from public.skill_assessments where skill_id = sk));
  perform pg_temp.okb('S13', 'Skills', 'Head boshqa bo''lim xodimini baholay olmaydi', 'DENIED',
    case when pg_temp.c('DEP2') is distinct from pg_temp.c('HEADDEP') then pg_temp.asm('HEAD', pg_temp.u('EMP2ID'), 'STEP3_ECG', 3) else 'SKIP(bir bo''lim)' end,
    pg_temp.c('DEP2') is not distinct from pg_temp.c('HEADDEP') or pg_temp.asm('HEAD', pg_temp.u('EMP2ID'), 'STEP3_ECG', 3) = 'DENIED');
  perform pg_temp.ok('S14', 'Skills', 'Employee record_skill_assessment → rad', 'DENIED', pg_temp.asm('EMP', pg_temp.u('EMP2ID'), 'STEP3_ECG', 3));
  r := pg_temp.rpc(pg_temp.u('EDU'), format('public.archive_competency_requirement(%L, ''STEP3'')', rq));
  perform pg_temp.ok('S15', 'Skills', 'archive_competency_requirement', 'archived', (select status from public.competency_requirements where id = rq));
  r := pg_temp.rpc(pg_temp.u('EDU'), format('public.archive_skill(%L, ''STEP3'')', sk));
  perform pg_temp.ok('S16', 'Skills', 'archive_skill (tarix saqlanadi)', 'archived/2', (select status from public.skills where id = sk) || '/' || (select count(*) from public.skill_assessments where skill_id = sk));
  perform pg_temp.ok('S17', 'Skills', 'Arxivlangan ko''nikmani baholab bo''lmaydi', 'DENIED', pg_temp.asm('EDU', pg_temp.u('EMPID'), 'STEP3_ECG', 3));
  perform pg_temp.ok('S18', 'Skills', 'Org B Org A ko''nikmasini ko''rmaydi', '0', pg_temp.cnt(pg_temp.u('BADM'), format('select 1 from public.skills where id = %L', sk))::text);
end $$;

-- ================= Compliance (pages_compliance.js) =================
do $$ declare r text; n int; begin
  r := pg_temp.dcm('EDU', null);
  select count(*) into n from public.employees where org_id = pg_temp.u('OA') and employment_status in ('active', 'on_leave');
  perform pg_temp.okb('C01', 'Compliance', 'EM tashkilot matritsasi: scope + xodimlar = server', 'organization/' || n, pg_temp.j(r, 'scope') || '/' || pg_temp.j(r, 'employees'),
    pg_temp.j(r, 'scope') = 'organization' and pg_temp.j(r, 'employees')::int = n and r::jsonb -> 'departments' is not null);
  perform pg_temp.okb('C02', 'Compliance', 'Bo''limlar kesimi yig''indisi = jami xodim', n::text, (select sum((d ->> 'employees')::int)::text from jsonb_array_elements(r::jsonb -> 'departments') d),
    (select sum((d ->> 'employees')::int) from jsonb_array_elements(r::jsonb -> 'departments') d) = n);
  r := pg_temp.dcm('EDU', pg_temp.c('DEP'));
  select count(*) into n from public.employees where department_id = pg_temp.u('DEP') and employment_status in ('active', 'on_leave');
  perform pg_temp.okb('C03', 'Compliance', 'Bo''lim filtri: rows = bo''lim xodimlari', n::text, coalesce(jsonb_array_length(r::jsonb -> 'rows')::text, r), jsonb_array_length(r::jsonb -> 'rows') = n);
  perform pg_temp.okb('C04', 'Compliance', 'HR tashkilot matritsasini ko''radi', 'organization', pg_temp.j(pg_temp.dcm('HR', null), 'scope'), pg_temp.j(pg_temp.dcm('HR', null), 'scope') = 'organization');
  perform pg_temp.ok('C05', 'Compliance', 'Head: tashkilot → rad', 'DENIED', pg_temp.dcm('HEAD', null));
  perform pg_temp.ok('C06', 'Compliance', 'Head: o''z bo''limi → department', 'department', pg_temp.j(pg_temp.dcm('HEAD', pg_temp.c('HEADDEP')), 'scope'));
  perform pg_temp.okb('C07', 'Compliance', 'Head: boshqa bo''lim (URL orqali urinish) → rad', 'DENIED',
    coalesce((select pg_temp.dcm('HEAD', d.id::text) from public.departments d where d.org_id = pg_temp.u('OA') and d.id::text is distinct from pg_temp.c('HEADDEP') limit 1), 'none'),
    (select pg_temp.dcm('HEAD', d.id::text) from public.departments d where d.org_id = pg_temp.u('OA') and d.id::text is distinct from pg_temp.c('HEADDEP') limit 1) = 'DENIED');
  perform pg_temp.ok('C08', 'Compliance', 'Instructor matritsa → rad', 'DENIED', pg_temp.dcm('INS', null));
  perform pg_temp.ok('C09', 'Compliance', 'Medical Reviewer matritsa → rad', 'DENIED', pg_temp.dcm('REV', null));
  perform pg_temp.ok('C10', 'Compliance', 'Employee matritsa → rad', 'DENIED', pg_temp.dcm('EMP', null));
  r := pg_temp.rpc(pg_temp.u('EDU'), format('public.employee_training_compliance(%L)', pg_temp.c('EMPID')));
  perform pg_temp.okb('C11', 'Compliance', 'Xodim trening: kurslar soni = course_assignments', pg_temp.ca(pg_temp.c('EMPID'))::text, coalesce(jsonb_array_length(r::jsonb -> 'courses')::text, r),
    jsonb_array_length(r::jsonb -> 'courses') = pg_temp.ca(pg_temp.c('EMPID')));
  perform pg_temp.okb('C12', 'Compliance', 'Trening statuslari ruxsat etilgan to''plamda', 'subset', (select string_agg(distinct c ->> 'status', ',') from jsonb_array_elements(r::jsonb -> 'courses') c),
    not exists (select 1 from jsonb_array_elements(r::jsonb -> 'courses') c where c ->> 'status' not in ('completed', 'in_progress', 'not_started', 'overdue', 'cancelled')));
  r := pg_temp.rpc(pg_temp.u('EDU'), format('public.employee_competency_matrix(%L)', pg_temp.c('EMPID')));
  perform pg_temp.okb('C13', 'Compliance', 'Kompetensiya statuslari: achieved/not_achieved/not_assessed', 'subset', coalesce((select string_agg(distinct c ->> 'status', ',') from jsonb_array_elements(r::jsonb -> 'competencies') c), 'bo''sh'),
    not exists (select 1 from jsonb_array_elements(r::jsonb -> 'competencies') c where c ->> 'status' not in ('achieved', 'not_achieved', 'not_assessed')));
  perform pg_temp.ok('C14', 'Compliance', 'Org B → Org A xodim trening → rad', 'DENIED', pg_temp.etc('BADM', pg_temp.c('EMPID')));
  perform pg_temp.ok('C15', 'Compliance', 'Org B → Org A kompetensiya → rad', 'DENIED', pg_temp.ecm('BADM', pg_temp.c('EMPID')));
  perform pg_temp.ok('C16', 'Compliance', 'Employee boshqa xodimni ko''ra olmaydi', 'DENIED', pg_temp.etc('EMP', pg_temp.c('EMP2ID')));
end $$;

-- ================= Notifications (bell / ro'yxat) =================
do $$ declare n0 int; n1 int; r text; nid uuid; p1 text; p2 text; begin
  n0 := pg_temp.rpc(pg_temp.u('EMP'), 'public.unread_notification_count()')::int;
  perform pg_temp.okb('N01', 'Notif', 'apply''dan keyin xodimda o''qilmagan bildirishnoma bor', '>0', n0::text, n0 > 0);
  p1 := pg_temp.rpc(pg_temp.u('EMP'), '(select string_agg(id::text, '','' order by created_at desc, id desc) from public.my_notifications(2, null, null, false))');
  select id into nid from public.notifications where id::text = split_part(p1, ',', 2);
  p2 := pg_temp.rpc(pg_temp.u('EMP'), format('(select coalesce(string_agg(id::text, '',''), '''') from public.my_notifications(2, %L, %L, false))', (select created_at from public.notifications where id = nid), nid));
  perform pg_temp.okb('N02', 'Notif', 'Keyset paging: 2-sahifa 1-sahifa bilan kesishmaydi', 'kesishma yo''q',
    (select count(*) from unnest(string_to_array(p1, ',')) a where a = any(string_to_array(p2, ',')))::text || ' kesishma',
    not exists (select 1 from unnest(string_to_array(p1, ',')) a where a = any(string_to_array(p2, ','))));
  select id into nid from public.notifications where recipient_id = pg_temp.u('EMP') and read_at is null order by created_at desc limit 1;
  r := pg_temp.rpc(pg_temp.u('EMP'), format('public.mark_notification_read(%L, true)', nid));
  n1 := pg_temp.rpc(pg_temp.u('EMP'), 'public.unread_notification_count()')::int;
  perform pg_temp.ok('N03', 'Notif', 'mark_notification_read → hisob -1', (n0 - 1)::text, n1::text);
  r := pg_temp.rpc(pg_temp.u('HR'), format('public.mark_notification_read(%L, false)', nid));
  perform pg_temp.ok('N04', 'Notif', 'Boshqa foydalanuvchi mark_notification_read → ta''sir yo''q', 'true', (select (read_at is not null)::text from public.notifications where id = nid));
  perform pg_temp.ok('N05', 'Notif', 'HR boshqaning bildirishnomasini UPDATE → 0 / rad', 'OK:0|DENIED', pg_temp.w(pg_temp.u('HR'), format('update public.notifications set read_at = null where id = %L', nid)));
  perform pg_temp.ok('N06', 'Notif', 'Bildirishnomani qo''lda INSERT → rad', 'DENIED', pg_temp.w(pg_temp.u('HR'), format('insert into public.notifications (org_id, recipient_id, notification_type, title, event_key) values (%L, %L, ''course_assigned'', ''x'', ''step3:forge'')', pg_temp.c('OA'), pg_temp.u('EMP'))));
  r := pg_temp.rpc(pg_temp.u('EMP'), 'public.mark_all_notifications_read()');
  perform pg_temp.ok('N07', 'Notif', 'mark_all_notifications_read → 0', '0', pg_temp.rpc(pg_temp.u('EMP'), 'public.unread_notification_count()'));
  perform pg_temp.ok('N08', 'Notif', 'Dublikat bildirishnoma yo''q (recipient, event_key)', '0', (select count(*)::text from (select recipient_id, event_key from public.notifications group by 1, 2 having count(*) > 1) z));
  perform pg_temp.ok('N09', 'Notif', 'Org B admin Org A bildirishnomalarini ko''rmaydi', '0', pg_temp.cnt(pg_temp.u('BADM'), format('select 1 from public.notifications where recipient_id = %L', pg_temp.u('EMP')))::text);
end $$;

-- ================= Anonim + integrity =================
do $$ begin
  perform pg_temp.ok('X01', 'Anon', 'anon department_compliance_matrix → rad', 'DENIED', pg_temp.rpca('public.department_compliance_matrix(null)'));
  perform pg_temp.ok('X02', 'Anon', 'anon employee_training_compliance → rad', 'DENIED', pg_temp.rpca(format('public.employee_training_compliance(%L)', pg_temp.c('EMPID'))));
  perform pg_temp.ok('X03', 'Anon', 'anon unread_notification_count → rad', 'DENIED', pg_temp.rpca('public.unread_notification_count()'));
  perform pg_temp.ok('X04', 'Anon', 'anon upsert_skill → rad', 'DENIED', pg_temp.rpca('public.upsert_skill(null, ''ANON_X'', ''x'', null, null, null, 5)'));
  perform pg_temp.ok('X05', 'Anon', 'anon apply_learning_path → rad', 'DENIED', pg_temp.rpca(format('public.apply_learning_path(%L, ''role'', ''employee'', null)', pg_temp.c('PATH'))));
  perform pg_temp.okb('X06', 'Anon', 'anon verify_certificate ishlaydi (contract buzilmagan)', 'ok', left(pg_temp.rpca('public.verify_certificate(''NOPE-000'')'), 60), pg_temp.rpca('public.verify_certificate(''NOPE-000'')') <> 'DENIED');
  perform pg_temp.okb('I01', 'Integrity', 'Exam attempts / sertifikatlar / savollar o''zgarmagan', 'teng', 'tekshirildi',
    (select md5(coalesce(string_agg(to_jsonb(a)::text, '' order by a.id), '')) from public.exam_attempts a) = (pg_temp.c('BASE')::jsonb ->> 'attempts_md5')
    and (select md5(coalesce(string_agg(to_jsonb(c)::text, '' order by c.id), '')) from public.certificates c) = (pg_temp.c('BASE')::jsonb ->> 'certs_md5')
    and (select md5(coalesce(string_agg(to_jsonb(q)::text, '' order by q.id), '')) from public.questions q) = (pg_temp.c('BASE')::jsonb ->> 'questions_md5'));
end $$;

select line from (
  select 0 ord, 'SUMMARY STEP3 total ' || count(*) || ' / PASS ' || count(*) filter (where pass) || ' / FAIL ' || count(*) filter (where not pass) || coalesce(' :: ' || string_agg(id, ',' order by id) filter (where not pass), '') as line from t5
  union all select 1, id || ' ' || case when pass then 'PASS' else 'FAIL' end || ' [' || grp || '] ' || test || ' :: kutilgan=' || expected || ' :: natija=' || actual from t5) x order by ord, line;
select json_build_object('total', count(*), 'pass', count(*) filter (where pass), 'fail', count(*) filter (where not pass),
  'fail_ids', coalesce(json_agg(id || ' => ' || actual order by id) filter (where not pass), '[]'::json),
  'groups', (select json_object_agg(grp, n) from (select grp, count(*) || '/' || count(*) filter (where pass) n from t5 group by grp) g))::text as summary_step3 from t5;
rollback;
