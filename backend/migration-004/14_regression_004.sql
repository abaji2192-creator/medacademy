-- PRODUCTION Phase 1 regressiya (004 dan keyin). Hammasi bitta tranzaksiyada, oxirida ROLLBACK:
-- vaqtinchalik xodim, urinish va sertifikat bazada QOLMAYDI.
begin;
create temp table r004 (id text, test text, expected text, actual text, pass boolean) on commit drop;
grant all on r004 to authenticated, anon;
create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid::text, true);
end $$;
create function pg_temp.ok(p_id text, p_test text, p_exp text, p_act text, p_pass boolean) returns void language sql as $$
  insert into r004 values (p_id, p_test, p_exp, p_act, p_pass) $$;
grant execute on function pg_temp.ok(text,text,text,text,boolean) to authenticated, anon;

-- vaqtinchalik xodim (faqat shu tranzaksiya ichida)
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
values ('e0000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rollback-test@invalid.local', '{"full_name":"Rollback Test"}', now(), now());
update public.profiles set status = 'active', department = 'Terapiya', role = 'employee' where id = 'e0000000-0000-0000-0000-0000000000e1';

do $$ declare n int; r text; begin
  perform pg_temp.login('262a128c-6fb7-470e-9452-5468cd6797c0'); set local role authenticated;
  select count(*) into n from public.profiles where id = auth.uid(); select role into r from public.profiles where id = auth.uid();
  reset role; perform pg_temp.ok('P01', 'Login: admin sessiyasi o''z profilini o''qiydi', '1 / super_admin', n || ' / ' || r, n = 1 and r = 'super_admin');
end $$;
do $$ declare c int; d int; cf int; begin
  perform pg_temp.login('262a128c-6fb7-470e-9452-5468cd6797c0'); set local role authenticated;
  select count(*) into c from public.courses; select count(*) into d from public.docs; select count(*) into cf from public.exam_configs;
  reset role; perform pg_temp.ok('P02', 'Dashboard/Course list: admin kurslar, docs, configlarni ko''radi', '13 / >0 / 13', c || ' / ' || d || ' / ' || cf, c = 13 and d > 0 and cf = 13);
end $$;
do $$ declare c int; begin
  perform pg_temp.login('e0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
  select count(*) into c from public.courses; reset role;
  perform pg_temp.ok('P03', 'Course list: xodim kurslarni ko''radi', '13', c::text, c = 13);
end $$;
do $$ declare ini jsonb; begin
  perform pg_temp.login('e0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
  ini := public.start_exam('INITIAL', 'initial', null, '{"medical":"RESIDENT_START","ethics":"ETHICS","communication":"COMM","safety":"SAFETY","public_health":"PH","sales":"SALES"}'::jsonb, false);
  reset role;
  perform pg_temp.ok('P04', 'Initial Assessment start (12 savol, javobsiz, org A)', '12 / javob yo''q',
    jsonb_array_length(ini -> 'qids') || ' / ' || case when (select bool_and(not (q ? 'a')) from jsonb_array_elements(ini -> 'questions') q) then 'javob yo''q' else 'JAVOB BOR' end,
    jsonb_array_length(ini -> 'qids') = 12 and (select bool_and(not (q ? 'a')) from jsonb_array_elements(ini -> 'questions') q)
    and (select org_id from public.exam_attempts where id = ini ->> 'id') = '00000000-0000-0000-0000-000000000001');
end $$;
do $$ declare att jsonb; ans jsonb; sv boolean; res jsonb; ver jsonb; begin
  perform pg_temp.login('e0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
  att := public.start_exam('ETHICS', 'final', null, null, false);
  reset role;
  perform pg_temp.ok('P05', 'Exam start (ETHICS final)', 'urinish yaratildi, javob yo''q',
    coalesce(att ->> 'id', 'null') || ' / ' || jsonb_array_length(att -> 'questions') || ' savol',
    att ->> 'id' is not null and (select bool_and(not (q ? 'a')) from jsonb_array_elements(att -> 'questions') q));
  select jsonb_object_agg(q.id, case when q.type = 'match' then (select jsonb_object_agg((i - 1)::text, e) from jsonb_array_elements(q.answer) with ordinality x(e, i))
                                     when q.type = 'short' then q.answer -> 0 else q.answer end)
    into ans from public.questions q where q.id in (select jsonb_array_elements_text(att -> 'qids'));
  perform pg_temp.login('e0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
  sv := public.save_answers(att ->> 'id', ans);
  reset role;
  perform pg_temp.ok('P06', 'Answer save', 'true + saqlandi', sv::text || ' / ' || (select count(*) from jsonb_object_keys((select answers from public.exam_attempts where id = att ->> 'id'))),
    sv and (select answers from public.exam_attempts where id = att ->> 'id') = ans);
  perform pg_temp.login('e0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
  res := public.submit_exam(att ->> 'id', null);
  reset role;
  perform pg_temp.ok('P07', 'Exam submit (server baholash) → 100% + sertifikat', '100 / true / sertifikat',
    (res -> 'attempt' ->> 'score') || ' / ' || (res -> 'attempt' ->> 'passed') || ' / ' || coalesce(res -> 'certificate' ->> 'id', 'yo''q'),
    (res -> 'attempt' ->> 'score')::numeric = 100 and res -> 'certificate' ->> 'id' is not null);
  set local role anon; perform set_config('request.jwt.claims', '{"role":"anon"}', true); perform set_config('request.jwt.claim.sub', '', true);
  ver := public.verify_certificate(res -> 'certificate' ->> 'id');
  reset role;
  perform pg_temp.ok('P08', 'Certificate verification (anonim QR)', 'Amalda', coalesce(ver ->> 'status', 'null'), ver ->> 'status' = 'Amalda');
end $$;
do $$ declare q int; begin
  perform pg_temp.login('e0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
  select count(*) into q from public.questions; reset role;
  perform pg_temp.ok('P09', 'Correct-answer protection: xodim questions jadvalini ko''ra olmaydi', '0', q::text, q = 0);
end $$;
do $$ declare rv jsonb; begin
  perform pg_temp.login('e0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
  rv := public.get_attempt_review((select id from public.exam_attempts where user_id = '262a128c-6fb7-470e-9452-5468cd6797c0' limit 1));
  reset role; perform pg_temp.ok('P10', 'Xodim → admin urinishining review''i (javoblar)', 'DENIED', 'ALLOWED', rv is null);
exception when others then reset role; perform pg_temp.ok('P10', 'Xodim → admin urinishining review''i (javoblar)', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ declare n int; begin
  perform pg_temp.login('e0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
  select (select count(*) from public.profiles where id <> auth.uid()) + (select count(*) from public.exam_attempts where user_id <> auth.uid())
       + (select count(*) from public.certificates where user_id <> auth.uid()) + (select count(*) from public.employees where profile_id is distinct from auth.uid())
       + (select count(*) from public.docs where owner = '262a128c-6fb7-470e-9452-5468cd6797c0' and collection not in ('settings','questions_custom','exam_overrides')) into n;
  reset role; perform pg_temp.ok('P11', 'Employee isolation: xodim admin ma''lumotlarini ko''ra olmaydi', '0', n::text, n = 0);
end $$;
do $$ declare n int; begin
  perform pg_temp.login('e0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
  update public.profiles set full_name = 'X' where id = '262a128c-6fb7-470e-9452-5468cd6797c0'; get diagnostics n = row_count;
  reset role; perform pg_temp.ok('P12', 'Employee isolation: admin profilini UPDATE', '0 qator', n::text, n = 0);
end $$;
do $$ begin
  perform pg_temp.login('e0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
  update public.profiles set role = 'super_admin' where id = auth.uid();
  reset role; perform pg_temp.ok('P13', 'Role escalation: xodim o''ziga super_admin', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('P13', 'Role escalation: xodim o''ziga super_admin', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ begin
  perform pg_temp.login('e0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
  insert into public.role_permissions (org_id, role, permission_key) values (public.my_org(), 'employee', 'settings.manage');
  reset role; perform pg_temp.ok('P14', 'Role escalation: xodim o''z roliga ruxsat qo''shadi', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('P14', 'Role escalation: xodim o''z roliga ruxsat qo''shadi', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ declare t text; denied int := 0; total int := 0; begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true); perform set_config('request.jwt.claim.sub', '', true);
  foreach t in array array['organizations','branches','departments','positions','specialties','employees','permissions','role_permissions','audit_logs','profiles','docs','questions','exam_attempts','certificates','schema_migrations','courses','exam_configs','attempt_resets'] loop
    total := total + 1;
    begin set local role anon; execute format('select 1 from public.%I limit 1', t); reset role;
    exception when others then denied := denied + 1; reset role; end;
  end loop;
  perform pg_temp.ok('P15', 'RLS: anonim → 18 jadval', '18/18 DENIED', denied || '/' || total, denied = total);
end $$;
do $$ declare n int; e int; begin
  perform pg_temp.login('262a128c-6fb7-470e-9452-5468cd6797c0'); set local role authenticated;
  select count(*) into n from public.profiles; select count(*) into e from public.employees; reset role;
  perform pg_temp.ok('P16', 'RLS: Super Admin o''z tashkiloti profillari va xodimlarini ko''radi', 'profiles=2, employees=jami', n || ' / ' || e,
    n = 2 and e = (select count(*) from public.employees));
end $$;
select id, test, expected, actual, case when pass then 'PASS' else 'FAIL' end as result from r004 order by id;
rollback;
