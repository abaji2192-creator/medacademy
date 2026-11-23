-- STAGING: 005 regressiya (production 24_regression_005.sql bilan bir xil testlar) — 005d qo'llangan holatda. ROLLBACK bilan.
-- Staging farqi: staging'dagi pre005 backup 005 recovery siklidan keyin olingan va question_versions ustunini o'z ichiga oladi,
-- shuning uchun X26 ikkala tomonda ham question_versions'siz solishtiriladi (production faylida o'zgarish yo'q).
-- PRODUCTION regressiya (005 dan keyin). Hammasi BITTA tranzaksiyada, oxirida ROLLBACK:
-- vaqtinchalik xodim/instruktor/Org B, "review simulyatsiyasi", manba, urinish va sertifikat bazada QOLMAYDI.
begin;
create temp table r005 (id text, grp text, test text, expected text, actual text, pass boolean) on commit drop;
grant all on r005 to authenticated, anon;
create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid::text, true);
end $$;
create function pg_temp.logout() returns void language plpgsql as $$
begin perform set_config('request.jwt.claims', '', true); perform set_config('request.jwt.claim.sub', '', true); end $$;
create function pg_temp.ok(p_id text, p_grp text, p_test text, p_exp text, p_act text, p_pass boolean) returns void language sql as $$
  insert into r005 values (p_id, p_grp, p_test, p_exp, p_act, p_pass) $$;
grant execute on function pg_temp.ok(text,text,text,text,text,boolean) to authenticated, anon;

-- Vaqtinchalik foydalanuvchilar (faqat shu tranzaksiyada)
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
  ('e0000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rollback-emp@invalid.local', '{"full_name":"Rollback Emp"}', now(), now()),
  ('e0000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rollback-inst@invalid.local', '{"full_name":"Rollback Inst"}', now(), now()),
  ('e0000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rollback-orgb@invalid.local', '{"full_name":"Rollback OrgB"}', now(), now());
update public.profiles set status = 'active', role = 'employee', department = 'Terapiya' where id = 'e0000000-0000-0000-0000-0000000000e1';
update public.profiles set status = 'active', role = 'instructor', department = 'Terapiya' where id = 'e0000000-0000-0000-0000-0000000000e2';
insert into public.employees (org_id, profile_id, employee_code, first_name, department_id)
select '00000000-0000-0000-0000-000000000001', v.pid, v.code, 'Rollback', (select id from public.departments where org_id = '00000000-0000-0000-0000-000000000001' and code = 'THERAPY')
from (values ('e0000000-0000-0000-0000-0000000000e1'::uuid, 'RB-E1'), ('e0000000-0000-0000-0000-0000000000e2'::uuid, 'RB-E2')) v(pid, code) on conflict do nothing;
insert into public.course_instructors (org_id, course_id, employee_id)
select '00000000-0000-0000-0000-000000000001', 'CARDIO_BASIC', id from public.employees where profile_id = 'e0000000-0000-0000-0000-0000000000e2';
insert into public.organizations (id, name, code) values ('0000000b-0000-0000-0000-0000000000b0', 'Rollback Org B', 'RBORGB');
update public.profiles set org_id = '0000000b-0000-0000-0000-0000000000b0', role = 'super_admin', status = 'active' where id = 'e0000000-0000-0000-0000-0000000000b1';

-- ===== Phase 1 (siyosatdan oldin: unknown evidence) =====
do $$ declare n int; r text; begin perform pg_temp.logout();
  perform pg_temp.login('262a128c-6fb7-470e-9452-5468cd6797c0'); set local role authenticated;
  select count(*), max(role) into n, r from public.profiles where id = auth.uid(); reset role;
  perform pg_temp.ok('X01', 'Phase 1', 'Login: admin sessiyasi o''z profilini o''qiydi', '1 / super_admin', n || ' / ' || r, n = 1 and r = 'super_admin');
end $$;
do $$ declare c int; d int; f int; m int; l int; begin perform pg_temp.logout();
  perform pg_temp.login('262a128c-6fb7-470e-9452-5468cd6797c0'); set local role authenticated;
  select count(*) into c from public.courses; select count(*) into d from public.docs; select count(*) into f from public.exam_configs;
  select count(*) into m from public.course_modules; select count(*) into l from public.lessons; reset role;
  perform pg_temp.ok('X02', 'Phase 1', 'Dashboard: admin kurslar/docs/configlar + kurs tuzilmasi', '13 / >0 / 13 / 34 / 47', c || ' / ' || d || ' / ' || f || ' / ' || m || ' / ' || l, c = 13 and d > 0 and f = 13 and m = 34 and l = 47);
end $$;
do $$ declare c int; l int; begin perform pg_temp.logout();
  perform pg_temp.login('e0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
  select count(*) into c from public.courses; select count(*) into l from public.lessons; reset role;
  perform pg_temp.ok('X03', 'Phase 1', 'Course list: xodim kurslar va darslarni ko''radi', '13 / 47', c || ' / ' || l, c = 13 and l = 47);
end $$;
do $$ declare m int; begin perform pg_temp.logout();
  perform pg_temp.login('e0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
  select jsonb_array_length(public.question_meta()) into m;
  begin
    perform public.start_exam('INITIAL', 'initial', null, '{"medical":"RESIDENT_START","ethics":"ETHICS","communication":"COMM","safety":"SAFETY","public_health":"PH","sales":"SALES"}'::jsonb, false);
    reset role; perform pg_temp.ok('X04', 'Evidence', 'Unknown evidence → initial assessment bloklangan (yangi siyosat)', 'DENIED', 'ALLOWED', false);
  exception when others then reset role; perform pg_temp.ok('X04', 'Evidence', 'Unknown evidence → initial assessment bloklangan (yangi siyosat)', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true);
  end;
  perform pg_temp.ok('X05', 'Evidence', 'Unknown evidence savollar yangi imtihon tanloviga kirmaydi (question_meta)', '0', m::text, m = 0);
  begin perform pg_temp.login('e0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
    perform public.start_exam('ETHICS', 'final', null, null, false); reset role;
    perform pg_temp.ok('X06', 'Evidence', 'Unknown evidence → kurs imtihoni (ETHICS) bloklangan', 'DENIED', 'ALLOWED', false);
  exception when others then reset role; perform pg_temp.ok('X06', 'Evidence', 'Unknown evidence → kurs imtihoni (ETHICS) bloklangan', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end;
end $$;

-- ===== Faqat shu tranzaksiyada: Org A savollari "review'dan o'tgan" deb simulyatsiya (ROLLBACK) =====
do $$ begin perform pg_temp.logout();
  perform set_config('medacademy.system_write', 'on', true);
  update public.questions set evidence_status = 'current', last_evidence_reviewed_at = now(), workflow_status = 'published'
   where org_id = '00000000-0000-0000-0000-000000000001' and published_version is not null;
  -- 005e o'rnatilgan bo'lsa: simulyatsiya tibbiy tasdiqni ham o'z ichiga oladi (Super Admin, nashr qilingan versiya, klinik savollar)
  if exists (select 1 from public.schema_migrations where version = '005e') then
    insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision, internal_notes)
    select q.org_id, q.id, q.published_version, 'medical', '262a128c-6fb7-470e-9452-5468cd6797c0', 'approved', 'TEST simulyatsiya (005e)'
      from public.questions q where q.org_id = '00000000-0000-0000-0000-000000000001' and q.published_version is not null and public._q_is_clinical(q);
  end if;
  perform set_config('medacademy.system_write', 'off', true);
end $$;

do $$ declare ini jsonb; begin perform pg_temp.logout();
  perform pg_temp.login('e0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
  ini := public.start_exam('INITIAL', 'initial', null, '{"medical":"RESIDENT_START","ethics":"ETHICS","communication":"COMM","safety":"SAFETY","public_health":"PH","sales":"SALES"}'::jsonb, false);
  reset role;
  perform pg_temp.ok('X07', 'Phase 1', 'Initial assessment (review''dan o''tgan bank bilan): 12 savol, javobsiz', '12 / javob yo''q',
    jsonb_array_length(ini -> 'qids') || ' / ' || case when (select bool_and(not (q ? 'a')) from jsonb_array_elements(ini -> 'questions') q) then 'javob yo''q' else 'JAVOB BOR' end,
    jsonb_array_length(ini -> 'qids') = 12 and (select bool_and(not (q ? 'a')) from jsonb_array_elements(ini -> 'questions') q));
end $$;
do $$ declare att jsonb; ans jsonb; sv boolean; res jsonb; ver jsonb; begin perform pg_temp.logout();
  perform pg_temp.login('e0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
  att := public.start_exam('ETHICS', 'final', null, null, false); reset role;
  perform pg_temp.ok('X08', 'Phase 1', 'Exam start (ETHICS): javob/manba/izoh yo''q, versiyalar qayd etildi', 'true',
    ((select bool_and(not (q ? 'a') and not (q ? 'refs') and not (q ? 'e')) from jsonb_array_elements(att -> 'questions') q)
      and (select count(*) from jsonb_object_keys((select question_versions from public.exam_attempts where id = att ->> 'id'))) = jsonb_array_length(att -> 'qids'))::text,
    (select bool_and(not (q ? 'a') and not (q ? 'refs') and not (q ? 'e')) from jsonb_array_elements(att -> 'questions') q)
      and (select count(*) from jsonb_object_keys((select question_versions from public.exam_attempts where id = att ->> 'id'))) = jsonb_array_length(att -> 'qids'));
  select jsonb_object_agg(q.id, case when q.type = 'match' then (select jsonb_object_agg((i - 1)::text, e) from jsonb_array_elements(q.answer) with ordinality x(e, i))
                                     when q.type = 'short' then q.answer -> 0 else q.answer end)
    into ans from public.questions q where q.id in (select jsonb_array_elements_text(att -> 'qids'));
  perform pg_temp.login('e0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
  sv := public.save_answers(att ->> 'id', ans); reset role;
  perform pg_temp.ok('X09', 'Phase 1', 'Answer save', 'true', sv::text, sv and (select answers from public.exam_attempts where id = att ->> 'id') = ans);
  perform pg_temp.login('e0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
  res := public.submit_exam(att ->> 'id', null); reset role;
  perform pg_temp.ok('X10', 'Phase 1', 'Submit: server baholash 100% + sertifikat', '100 / true / sertifikat',
    (res -> 'attempt' ->> 'score') || ' / ' || (res -> 'attempt' ->> 'passed') || ' / ' || coalesce(res -> 'certificate' ->> 'id', 'yo''q'),
    (res -> 'attempt' ->> 'score')::numeric = 100 and res -> 'certificate' ->> 'id' is not null);
  perform pg_temp.ok('X11', 'Phase 1', 'Result: izoh + tasdiqlangan manbalar ro''yxati; ichki izohlar yo''q', 'true',
    (select bool_and((q ? 'e') and (q ? 'refs') and q::text not like '%supporting_claim%' and q::text not like '%internal_notes%') from jsonb_array_elements(res -> 'questions') q)::text,
    (select bool_and((q ? 'e') and (q ? 'refs') and q::text not like '%supporting_claim%' and q::text not like '%internal_notes%') from jsonb_array_elements(res -> 'questions') q));
  perform pg_temp.logout(); set local role anon;
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  ver := public.verify_certificate(res -> 'certificate' ->> 'id'); reset role;
  perform pg_temp.ok('X12', 'Phase 1', 'Certificate verification (anonim QR)', 'Amalda', coalesce(ver ->> 'status', 'null'), ver ->> 'status' = 'Amalda');
  -- tarixiy yaxlitlik uchun keyinroq tekshiriladi
  perform set_config('medacademy.rb_attempt', att ->> 'id', true);
  perform set_config('medacademy.rb_cert', res -> 'certificate' ->> 'id', true);
end $$;

-- ===== Security =====
do $$ declare t text; denied int := 0; total int := 0; begin perform pg_temp.logout();
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  for t in select tablename from pg_tables where schemaname = 'public' order by 1 loop
    total := total + 1;
    begin set local role anon; execute format('select 1 from public.%I limit 1', t); reset role;
    exception when others then denied := denied + 1; reset role; end;
  end loop;
  perform pg_temp.ok('X13', 'Security', 'Anonim → barcha public jadvallar', total || '/' || total || ' DENIED', denied || '/' || total, denied = total);
end $$;
do $$ declare n int; begin perform pg_temp.logout();
  perform pg_temp.login('e0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
  select (select count(*) from public.profiles where id <> auth.uid()) + (select count(*) from public.exam_attempts where user_id <> auth.uid())
       + (select count(*) from public.employees where profile_id is distinct from auth.uid()) + (select count(*) from public.course_assignments where employee_id <> public.my_employee_id())
       + (select count(*) from public.lesson_progress where employee_id <> public.my_employee_id()) + (select count(*) from public.certificates where user_id <> auth.uid()) into n;
  reset role; perform pg_temp.ok('X14', 'Security', 'Employee → boshqa xodim (profil, urinish, tayinlash, progress, sertifikat)', '0', n::text, n = 0);
end $$;
do $$ declare n int; begin perform pg_temp.logout();
  perform pg_temp.login('e0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
  select (select count(*) from public.questions) + (select count(*) from public.question_versions) + (select count(*) from public.question_publications) into n;
  reset role; perform pg_temp.ok('X15', 'Security', 'Employee → to''g''ri javob (questions, question_versions, publications)', '0', n::text, n = 0);
end $$;
do $$ declare s uuid; n int; a int; begin perform pg_temp.logout();
  perform pg_temp.login('262a128c-6fb7-470e-9452-5468cd6797c0'); set local role authenticated;
  insert into public.evidence_sources (org_id, source_type, title, organization, guideline_name, guideline_version, url, verification_status, verification_source)
    values (public.my_org(), 'guideline', 'ROLLBACK TEST guideline (sinov, haqiqiy emas)', 'TEST', 'TEST', '2026', 'https://example.org/rollback-test', 'verified', 'manual') returning id into s;
  insert into public.question_evidence (org_id, question_id, evidence_source_id, relationship_type, supporting_claim)
    values (public.my_org(), (select qids[1] from public.exam_attempts where id = current_setting('medacademy.rb_attempt')), s, 'primary_support', 'ICHKI izoh');
  insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision, internal_notes)
    values (public.my_org(), 'Q005', 1, 'medical', auth.uid(), 'changes_requested', 'ICHKI review izohi');
  select count(*) into a from public.question_evidence;
  reset role;
  perform pg_temp.login('e0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
  select (select count(*) from public.evidence_sources) + (select count(*) from public.question_evidence) + (select count(*) from public.question_reviews) into n;
  reset role;
  perform pg_temp.ok('X16', 'Evidence', 'Question → evidence bog''lanishi (admin ko''radi)', '1', a::text, a = 1);
  perform pg_temp.ok('X17', 'Security', 'Employee → evidence manbalari / ichki izohlar / review', '0', n::text, n = 0);
end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('e0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
  update public.profiles set role = 'medical_reviewer' where id = auth.uid();
  reset role; perform pg_temp.ok('X18', 'Security', 'Employee → role escalation (medical_reviewer)', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('X18', 'Security', 'Employee → role escalation (medical_reviewer)', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('e0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
  update public.profiles set role = 'super_admin' where id = auth.uid();
  reset role; perform pg_temp.ok('X19', 'Security', 'Employee → role escalation (super_admin)', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('X19', 'Security', 'Employee → role escalation (super_admin)', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ declare n int; c int; begin perform pg_temp.logout();
  perform pg_temp.login('e0000000-0000-0000-0000-0000000000e2'); set local role authenticated;
  select count(*) into n from public.questions where course_id <> 'CARDIO_BASIC';
  select count(*) into c from public.questions where course_id = 'CARDIO_BASIC';
  begin perform public.get_attempt_review(current_setting('medacademy.rb_attempt')); reset role;
    perform pg_temp.ok('X20', 'Security', 'Instructor → biriktirilmagan kurs (savollar / urinish review)', '0 / DENIED', n || ' / ALLOWED', false);
  exception when others then reset role;
    perform pg_temp.ok('X20', 'Security', 'Instructor → biriktirilmagan kurs (savollar / urinish review)', '0 / DENIED', n || ' / DENIED', n = 0);
  end;
  perform pg_temp.ok('X21', 'Security', 'Instructor → biriktirilgan kurs savollari (CARDIO_BASIC)', '11', c::text, c = 11);
end $$;
do $$ declare n int; begin perform pg_temp.logout();
  perform pg_temp.login('e0000000-0000-0000-0000-0000000000b1'); set local role authenticated;
  select (select count(*) from public.questions where org_id <> public.my_org()) + (select count(*) from public.course_modules where org_id <> public.my_org())
       + (select count(*) from public.lessons where org_id <> public.my_org()) + (select count(*) from public.evidence_sources where org_id <> public.my_org())
       + (select count(*) from public.exam_attempts where org_id <> public.my_org()) + (select count(*) from public.profiles where org_id <> public.my_org())
       + (select count(*) from public.courses where org_id <> public.my_org()) + (select count(*) from public.learning_paths where org_id <> public.my_org()) into n;
  reset role; perform pg_temp.ok('X22', 'Security', 'Cross-org: Org B admin → Org A (savol, modul, dars, manba, urinish, profil, kurs, path)', '0', n::text, n = 0);
end $$;

-- ===== Evidence: outdated / conflicting chiqariladi; tarix o'zgarmaydi =====
do $$ declare q1 text; w text; el boolean; m int; sc0 numeric; sc1 numeric; r0 text; r1 text; ver jsonb; rv jsonb; begin perform pg_temp.logout();
  q1 := (select qids[1] from public.exam_attempts where id = current_setting('medacademy.rb_attempt'));
  select score, results::text into sc0, r0 from public.exam_attempts where id = current_setting('medacademy.rb_attempt');
  update public.evidence_sources set status = 'retracted' where title like 'ROLLBACK TEST guideline%';
  select workflow_status, public._q_exam_eligible(q) into w, el from public.questions q where id = q1;
  perform pg_temp.login('e0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
  select count(*) into m from jsonb_array_elements(public.question_meta()) x where x ->> 'id' = q1; reset role;
  perform pg_temp.ok('X23', 'Evidence', 'Asosiy manba retracted/outdated → review_required, yangi imtihondan chiqarildi', 'review_required / false / meta 0', w || ' / ' || el || ' / meta ' || m,
    w = 'review_required' and not el and m = 0);
  select score, results::text into sc1, r1 from public.exam_attempts where id = current_setting('medacademy.rb_attempt');
  ver := public.verify_certificate(current_setting('medacademy.rb_cert'));
  perform pg_temp.login('e0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
  rv := public.get_attempt_review(current_setting('medacademy.rb_attempt')); reset role;
  perform pg_temp.ok('X24', 'Historical', 'Tarixiy urinish: ball/natijalar o''zgarmagan, sertifikat amalda, review ishlaydi', 'teng / Amalda / bor',
    case when sc0 = sc1 and r0 = r1 then 'teng' else 'O''ZGARGAN' end || ' / ' || coalesce(ver ->> 'status', 'null') || ' / ' || coalesce(jsonb_array_length(rv -> 'questions'), 0),
    sc0 = sc1 and r0 = r1 and ver ->> 'status' = 'Amalda' and jsonb_array_length(rv -> 'questions') > 0);
end $$;
do $$ declare s uuid; w text; el boolean; begin perform pg_temp.logout();
  insert into public.evidence_sources (org_id, source_type, title, url) values ('00000000-0000-0000-0000-000000000001', 'cohort_study', 'ROLLBACK TEST conflicting (sinov)', 'https://example.org/rollback-c') returning id into s;
  insert into public.question_evidence (org_id, question_id, evidence_source_id, relationship_type) values ('00000000-0000-0000-0000-000000000001', 'Q020', s, 'conflicting_evidence');
  select workflow_status, public._q_exam_eligible(q) into w, el from public.questions q where id = 'Q020';
  perform pg_temp.ok('X25', 'Evidence', 'Conflicting evidence → review_required, yangi imtihonga kirmaydi', 'review_required / false', w || ' / ' || el, w = 'review_required' and not el);
end $$;
do $$ declare rv jsonb; same boolean; begin perform pg_temp.logout();
  perform pg_temp.login('262a128c-6fb7-470e-9452-5468cd6797c0'); set local role authenticated;
  rv := public.get_attempt_review((select id from public.exam_attempts where kind = 'initial' and user_id = '262a128c-6fb7-470e-9452-5468cd6797c0' order by started_at limit 1));
  reset role;
  select (to_jsonb(a) - 'question_versions') = (to_jsonb(b) - 'question_versions') into same from public.exam_attempts a join backup.exam_attempts_pre005_20261123 b on b.id = a.id
   where a.kind = 'initial' and a.user_id = '262a128c-6fb7-470e-9452-5468cd6797c0' order by a.started_at limit 1;
  perform pg_temp.ok('X26', 'Historical', 'Abdulaziz''ning mavjud initial urinishi: backup bilan aynan, review ishlaydi (v1)', 'aynan / savollar > 0',
    case when same then 'aynan' else 'FARQ' end || ' / ' || coalesce(jsonb_array_length(rv -> 'questions'), 0), same and jsonb_array_length(rv -> 'questions') > 0);
end $$;

select line from (
  select 0 ord, 'SUMMARY total ' || count(*) || ' / FAIL ' || count(*) filter (where not pass) || coalesce(' :: ' || string_agg(id, ',') filter (where not pass), '') as line from r005
  union all select 1, id || ' ' || case when pass then 'PASS' else 'FAIL' end || ' ' || test || ' :: ' || actual from r005) x order by ord, line;
rollback;
