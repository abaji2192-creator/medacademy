-- 005 testlari (local + staging). Bitta tranzaksiya, oxirida ROLLBACK — iz qoldirmaydi.
-- Foydalanuvchilar: 262a… super_admin A · a…02 hr · a…03 education_manager · a…04 instructor (CARDIO_BASIC'ga biriktirilgan)
-- a…05 department_head (Kardiologiya) · a…06 employee (Kardiologiya) · a…07 employee (Terapiya) · a…08 medical_reviewer · a…09 instructor (biriktirilmagan)
-- b…01 super_admin B · b…02 employee B
begin;
create temp table t005 (id text, grp text, test text, expected text, actual text, pass boolean) on commit drop;
grant all on t005 to authenticated, anon;
create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid::text, true);
end $$;
create function pg_temp.logout() returns void language plpgsql as $$
begin perform set_config('request.jwt.claims', '', true); perform set_config('request.jwt.claim.sub', '', true); end $$;
create function pg_temp.ok(p_id text, p_grp text, p_test text, p_exp text, p_act text, p_pass boolean) returns void language sql as $$
  insert into t005 values (p_id, p_grp, p_test, p_exp, p_act, p_pass) $$;
grant execute on function pg_temp.ok(text,text,text,text,text,boolean) to authenticated, anon;
create function pg_temp.src(t text) returns uuid language sql security definer as $$ select id from public.evidence_sources where title = t $$;
grant execute on function pg_temp.src(text) to authenticated, anon;
-- TEST: savollarni "review'dan o'tgan" qilib simulyatsiya qiladi (faqat shu tranzaksiyada; ROLLBACK bilan yo'qoladi)
create function pg_temp.make_reviewed(p_courses text[]) returns int language plpgsql security definer as $$
declare n int; begin
  perform set_config('request.jwt.claims', '', true); perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('medacademy.system_write', 'on', true);
  update public.questions set evidence_status = 'current', last_evidence_reviewed_at = now(), workflow_status = 'published'
   where org_id = '00000000-0000-0000-0000-000000000001' and course_id = any (p_courses) and published_version is not null;
  get diagnostics n = row_count;
  -- 005e o'rnatilgan bo'lsa: simulyatsiya tibbiy tasdiqni ham o'z ichiga oladi (Super Admin, nashr qilingan versiya) — faqat shu tranzaksiya
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'question_reviews' and column_name = 'reviewer_role_at_creation') then
    execute $q$insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision, internal_notes)
              select q.org_id, q.id, q.published_version, 'medical', '262a128c-6fb7-470e-9452-5468cd6797c0', 'approved', 'TEST simulyatsiya (005e)'
                from public.questions q where q.org_id = '00000000-0000-0000-0000-000000000001' and q.course_id = any ($1) and q.published_version is not null
                 and public._q_is_clinical(q)$q$ using p_courses;
  end if;

  perform set_config('medacademy.system_write', 'off', true); return n;
end $$;
create function pg_temp.has5e() returns boolean language sql security definer as $$ select exists (select 1 from public.schema_migrations where version = '005e') $$;
create function pg_temp.emp(uid uuid) returns uuid language sql security definer as $$ select id from public.employees where profile_id = uid $$;
grant execute on function pg_temp.emp(uuid), pg_temp.has5e() to authenticated, anon;

-- ===================== EL. Evidence-based exam eligibility (005c) =====================
do $$ declare n int; r text; begin perform pg_temp.logout();
  select count(*) into n from public.questions where id like 'Q%' and workflow_status = 'review_required' and evidence_status = 'unknown'
    and published_version = 1 and review_reason = 'evidence_unknown_policy_2026_11';
  perform pg_temp.ok('EL01', 'Eligibility', '131 savol: unknown evidence → review_required (o''chirilmagan, v1 saqlangan)', '131', n::text, n = 131);
end $$;
do $$ declare m int; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  select jsonb_array_length(public.question_meta()) into m;
  begin perform public.start_exam('ETHICS', 'final', null, null, false); reset role;
    perform pg_temp.ok('EL02', 'Eligibility', 'Unknown evidence savollar bilan yangi imtihon (ETHICS)', 'DENIED', 'ALLOWED', false);
  exception when others then reset role; perform pg_temp.ok('EL02', 'Eligibility', 'Unknown evidence savollar bilan yangi imtihon (ETHICS)', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end;
  perform pg_temp.ok('EL03', 'Eligibility', 'question_meta: yaroqli savollar soni (review''gacha)', '0', m::text, m = 0);
end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000007'); set local role authenticated;
  perform public.start_exam('INITIAL', 'initial', null, '{"medical":"RESIDENT_START","ethics":"ETHICS","communication":"COMM","safety":"SAFETY","public_health":"PH","sales":"SALES"}'::jsonb, false);
  reset role; perform pg_temp.ok('EL04', 'Eligibility', 'Unknown evidence bilan initial assessment', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('EL04', 'Eligibility', 'Unknown evidence bilan initial assessment', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ declare rv jsonb; a int; begin perform pg_temp.logout();
  select count(*) into a from public.exam_attempts;
  perform pg_temp.login('262a128c-6fb7-470e-9452-5468cd6797c0'); set local role authenticated;
  rv := public.get_attempt_review((select id from public.exam_attempts where kind = 'initial' and user_id = '262a128c-6fb7-470e-9452-5468cd6797c0' order by started_at limit 1));
  reset role; perform pg_temp.ok('EL05', 'Historical integrity', 'Tarixiy initial urinish (review''gacha ham) to''liq ko''rinadi, natija o''zgarmagan', 'savollar > 0 / score saqlangan',
    coalesce(jsonb_array_length(rv -> 'questions'), 0) || ' savol / score ' || (rv -> 'attempt' ->> 'score'),
    coalesce(jsonb_array_length(rv -> 'questions'), 0) > 0 and (rv -> 'attempt' ->> 'score') is not null);
end $$;
-- Phase 1 oqimlari uchun: CARDIO_BASIC va IPC'dan boshqa kurslar "review'dan o'tgan" deb simulyatsiya (ROLLBACK)
select pg_temp.make_reviewed(array['ETHICS','COMM','SAFETY','PH','SALES','RESIDENT_START','DOC_EM','NURSE_BASIC','RECEPTION','SANITARY','DOC_ASSIST']);
do $$ declare m int; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  select count(*) into m from jsonb_array_elements(public.question_meta()) x where x ->> 'course' in ('CARDIO_BASIC','IPC'); reset role;
  perform pg_temp.ok('EL06', 'Eligibility', 'Review''dan o''tmagan kurs savollari (CARDIO_BASIC, IPC) yangi imtihonga kirmaydi', '0', m::text, m = 0);
end $$;

-- ===================== S. Kurs tuzilmasi va yaxlitlik =====================
do $$ declare m int; l int; p int; lp int; begin perform pg_temp.logout();
  select count(*) into m from public.course_modules where org_id = '00000000-0000-0000-0000-000000000001';
  select count(*) into l from public.lessons where org_id = '00000000-0000-0000-0000-000000000001';
  select count(*) into p from public.learning_paths where org_id = '00000000-0000-0000-0000-000000000001';
  select count(*) into lp from public.learning_path_courses where org_id = '00000000-0000-0000-0000-000000000001';
  perform pg_temp.ok('S01', 'Structure', 'Organization → Course → Module → Lesson seed (data.js dan)', '34 modul / 47 dars / 9 path / 63 bog''lanish', m||'/'||l||'/'||p||'/'||lp, m = 34 and l = 47 and p = 9 and lp = 63);
end $$;
do $$ declare n int; begin perform pg_temp.logout();
  select count(*) into n from public.questions q where q.org_id = '00000000-0000-0000-0000-000000000001' and q.module_id is not null
    and not exists (select 1 from public.course_modules m where m.id = q.module_id and m.course_id = q.course_id);
  perform pg_temp.ok('S02', 'Structure', '131 savol modul FK: modul topilmagan / boshqa kursga tegishli', '0', n::text, n = 0);
end $$;
do $$ begin perform pg_temp.logout();
  insert into public.questions (id, org_id, course_id, module_id, type, stem, answer) values ('TFK1', '00000000-0000-0000-0000-000000000001', 'ETHICS', 'NO_SUCH_MOD', 'tf', 'x', 'true');
  perform pg_temp.ok('S03', 'Structure', 'Mavjud bo''lmagan modulga savol (FK)', 'DENIED', 'ALLOWED', false);
exception when foreign_key_violation then perform pg_temp.ok('S03', 'Structure', 'Mavjud bo''lmagan modulga savol (FK)', 'DENIED', 'foreign_key_violation', true); end $$;
do $$ begin perform pg_temp.logout();
  insert into public.course_modules (org_id, course_id, title) values ('0000000b-0000-0000-0000-00000000000b', 'ETHICS', 'x');
  perform pg_temp.ok('S04', 'Structure', 'Org B moduli Org A kursiga (cross-org, DB trigger)', 'DENIED', 'ALLOWED', false);
exception when others then perform pg_temp.ok('S04', 'Structure', 'Org B moduli Org A kursiga (cross-org, DB trigger)', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ begin perform pg_temp.logout();
  delete from public.course_modules where id = 'ETH1';
  perform pg_temp.ok('S05', 'Structure', 'Savol/darsi bor modulni o''chirish (FK RESTRICT)', 'DENIED', 'ALLOWED', false);
exception when others then perform pg_temp.ok('S05', 'Structure', 'Savol/darsi bor modulni o''chirish (FK RESTRICT)', 'DENIED', 'FK: ' || sqlstate, true); end $$;
do $$ declare n int; d int; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  select count(*) into n from public.lessons; select count(*) into d from public.course_modules where status <> 'published';
  reset role; perform pg_temp.ok('S06', 'Structure', 'Xodim nashr qilingan darslarni ko''radi', '47 / draft 0', n || ' / draft ' || d, n = 47 and d = 0);
end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  insert into public.lessons (org_id, module_id, title) values (public.my_org(), 'ETH1', 'hack');
  reset role; perform pg_temp.ok('S07', 'Structure', 'Xodim dars yaratadi', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('S07', 'Structure', 'Xodim dars yaratadi', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;

-- ===================== AS. Course assignments =====================
do $$ declare a uuid; b uuid; v_by uuid; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000003'); set local role authenticated;
  insert into public.course_assignments (org_id, course_id, employee_id, due_date) values (public.my_org(), 'ETHICS', pg_temp.emp('a0000000-0000-0000-0000-000000000006'), current_date + 30) returning id, assigned_by into a, v_by;
  insert into public.course_assignments (org_id, course_id, employee_id) values (public.my_org(), 'ETHICS', pg_temp.emp('a0000000-0000-0000-0000-000000000007')) returning id into b;
  reset role;
  perform pg_temp.ok('AS01', 'Assignment', 'Education Manager kurs tayinlaydi (assigned_by server tomonidan)', 'ALLOWED, assigned_by = edu manager', coalesce(v_by::text, 'null'), v_by = 'a0000000-0000-0000-0000-000000000003');
end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  insert into public.course_assignments (org_id, course_id, employee_id) values (public.my_org(), 'COMM', public.my_employee_id());
  reset role; perform pg_temp.ok('AS02', 'Assignment', 'Xodim o''ziga kurs tayinlaydi', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('AS02', 'Assignment', 'Xodim o''ziga kurs tayinlaydi', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ declare own int; oth int; u int; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  select count(*) into own from public.course_assignments where employee_id = public.my_employee_id();
  select count(*) into oth from public.course_assignments where employee_id <> public.my_employee_id();
  update public.course_assignments set status = 'completed' where employee_id = public.my_employee_id(); get diagnostics u = row_count;
  reset role;
  perform pg_temp.ok('AS03', 'Assignment', 'Xodim o''z tayinlashini ko''radi', '1', own::text, own = 1);
  perform pg_temp.ok('AS04', 'Assignment', 'Xodim boshqa xodim tayinlashini ko''radi', '0', oth::text, oth = 0);
  perform pg_temp.ok('AS05', 'Assignment', 'Xodim o''z tayinlashini "completed" qiladi', '0 qator', u::text, u = 0);
end $$;
do $$ declare k int; t int; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000005'); set local role authenticated;
  select count(*) into k from public.course_assignments where employee_id = pg_temp.emp('a0000000-0000-0000-0000-000000000006');
  select count(*) into t from public.course_assignments where employee_id = pg_temp.emp('a0000000-0000-0000-0000-000000000007');
  reset role; perform pg_temp.ok('AS06', 'Assignment', 'Dept Head: o''z bo''limi / boshqa bo''lim tayinlashlari', '1 / 0', k || ' / ' || t, k = 1 and t = 0);
end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000004'); set local role authenticated;
  insert into public.course_assignments (org_id, course_id, employee_id) values (public.my_org(), 'SAFETY', pg_temp.emp('a0000000-0000-0000-0000-000000000007'));
  reset role; perform pg_temp.ok('AS07', 'Assignment', 'Instructor biriktirilmagan kursga tayinlaydi', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('AS07', 'Assignment', 'Instructor biriktirilmagan kursga tayinlaydi', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ declare n int; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000004'); set local role authenticated;
  insert into public.course_assignments (org_id, course_id, employee_id) values (public.my_org(), 'CARDIO_BASIC', pg_temp.emp('a0000000-0000-0000-0000-000000000007'));
  select count(*) into n from public.course_assignments; reset role;
  perform pg_temp.ok('AS08', 'Assignment', 'Instructor o''z kursiga tayinlaydi va faqat o''z kursi tayinlashlarini ko''radi', 'ALLOWED, ko''radi=1', 'ko''radi=' || n, n = 1);
end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000003'); set local role authenticated;
  insert into public.course_assignments (org_id, course_id, employee_id) values (public.my_org(), 'ETHICS', pg_temp.emp('a0000000-0000-0000-0000-000000000006'));
  reset role; perform pg_temp.ok('AS09', 'Assignment', 'Takroriy faol tayinlash', 'DENIED', 'ALLOWED', false);
exception when unique_violation then reset role; perform pg_temp.ok('AS09', 'Assignment', 'Takroriy faol tayinlash', 'DENIED', 'unique_violation', true); end $$;

-- ===================== P. Lesson progress =====================
do $$ declare l uuid; st text; begin perform pg_temp.logout();
  select id into l from public.lessons where module_id = 'ETH1' order by order_index limit 1;
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  insert into public.lesson_progress (org_id, lesson_id, employee_id, progress_percent) values (public.my_org(), l, public.my_employee_id(), 40);
  reset role;
  select status into st from public.course_assignments where employee_id = pg_temp.emp('a0000000-0000-0000-0000-000000000006') and course_id = 'ETHICS';
  perform pg_temp.ok('P01', 'Progress', 'Xodim o''z progressini yozadi → tayinlash in_progress', 'in_progress', st, st = 'in_progress');
end $$;
do $$ declare l uuid; begin perform pg_temp.logout();
  select id into l from public.lessons where module_id = 'ETH2' order by order_index limit 1;
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  insert into public.lesson_progress (org_id, lesson_id, employee_id) values (public.my_org(), l, pg_temp.emp('a0000000-0000-0000-0000-000000000007'));
  reset role; perform pg_temp.ok('P02', 'Progress', 'Xodim boshqa xodim nomidan progress yozadi', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('P02', 'Progress', 'Xodim boshqa xodim nomidan progress yozadi', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  update public.lesson_progress set employee_id = pg_temp.emp('a0000000-0000-0000-0000-000000000007') where employee_id = public.my_employee_id();
  reset role; perform pg_temp.ok('P03', 'Progress', 'Xodim progress egalik maydonini o''zgartiradi', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('P03', 'Progress', 'Xodim progress egalik maydonini o''zgartiradi', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ declare pct int; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  update public.lesson_progress set status = 'completed' where employee_id = public.my_employee_id() returning progress_percent into pct;
  reset role; perform pg_temp.ok('P04', 'Progress', 'Xodim o''z progressini yakunlaydi (100%)', '100', coalesce(pct::text, 'null'), pct = 100);
end $$;
do $$ declare n int; m int; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000007'); set local role authenticated;
  select count(*) into n from public.lesson_progress; reset role;
  perform pg_temp.login('a0000000-0000-0000-0000-000000000005'); set local role authenticated;
  select count(*) into m from public.lesson_progress; reset role;
  perform pg_temp.ok('P05', 'Progress', 'Boshqa xodim / Dept Head (shu bo''lim) progressni ko''rishi', '0 / 1', n || ' / ' || m, n = 0 and m = 1);
end $$;

-- ===================== L. Learning paths =====================
do $$ declare n int; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  select count(*) into n from public.learning_paths; reset role;
  perform pg_temp.ok('L01', 'Learning path', 'Xodim nashr qilingan path''larni ko''radi (faqat Org A)', '9', n::text, n = 9);
end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  insert into public.learning_paths (org_id, code, title) values (public.my_org(), 'HACK', 'x');
  reset role; perform pg_temp.ok('L02', 'Learning path', 'Xodim path yaratadi', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('L02', 'Learning path', 'Xodim path yaratadi', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ declare p uuid; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000003'); set local role authenticated;
  insert into public.learning_paths (org_id, code, title, status) values (public.my_org(), 'CARDIO_TRACK', 'Cardio track', 'published') returning id into p;
  insert into public.learning_path_courses (org_id, path_id, course_id, order_index) values (public.my_org(), p, 'CARDIO_BASIC', 1);
  reset role; perform pg_temp.ok('L03', 'Learning path', 'Education Manager path + kurs qo''shadi', 'ALLOWED', 'ALLOWED', true);
exception when others then reset role; perform pg_temp.ok('L03', 'Learning path', 'Education Manager path + kurs qo''shadi', 'ALLOWED', left(sqlerrm, 60), false); end $$;

-- ===================== IN. Instructor =====================
do $$ declare c int; e int; u int; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000004'); set local role authenticated;
  select count(*) into c from public.questions where course_id = 'CARDIO_BASIC';
  select count(*) into e from public.questions where course_id <> 'CARDIO_BASIC';
  update public.questions set topic = 'x' where course_id = 'ETHICS'; get diagnostics u = row_count;
  reset role;
  perform pg_temp.ok('IN01', 'Instructor', 'Instructor: biriktirilgan kurs savollari / boshqa kurslar', '11 / 0', c || ' / ' || e, c = 11 and e = 0);
  perform pg_temp.ok('IN02', 'Instructor', 'Instructor biriktirilmagan kurs savolini tahrirlaydi', '0 qator', u::text, u = 0);
end $$;
do $$ declare n int; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000009'); set local role authenticated;
  select count(*) into n from public.questions; reset role;
  perform pg_temp.ok('IN03', 'Instructor', 'Biriktirilmagan instructor savollar bankini ko''radi', '0', n::text, n = 0);
end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000004'); set local role authenticated;
  insert into public.course_instructors (org_id, course_id, employee_id) values (public.my_org(), 'ETHICS', public.my_employee_id());
  reset role; perform pg_temp.ok('IN04', 'Instructor', 'Instructor o''zini boshqa kursga biriktiradi', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('IN04', 'Instructor', 'Instructor o''zini boshqa kursga biriktiradi', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ declare att jsonb; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000007'); set local role authenticated;
  att := public.start_exam('SAFETY', 'final', null, null, false); perform public.submit_exam(att ->> 'id', '{}'::jsonb); reset role;
  perform pg_temp.login('a0000000-0000-0000-0000-000000000004'); set local role authenticated;
  perform public.get_attempt_review(att ->> 'id');
  reset role; perform pg_temp.ok('IN05', 'Instructor', 'Instructor biriktirilmagan kurs urinishini (javoblar bilan) ko''radi', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('IN05', 'Instructor', 'Instructor biriktirilmagan kurs urinishini (javoblar bilan) ko''radi', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;

-- ===================== E. Evidence =====================
do $$ declare n int; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  select (select count(*) from public.evidence_sources) + (select count(*) from public.question_evidence) + (select count(*) from public.question_reviews)
       + (select count(*) from public.question_versions) + (select count(*) from public.evidence_events) + (select count(*) from public.research_results) into n;
  reset role; perform pg_temp.ok('E01', 'Evidence', 'Xodim → manbalar, bog''lanishlar, review izohlari, versiyalar, hodisalar', '0', n::text, n = 0);
end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000004'); set local role authenticated;
  insert into public.evidence_sources (org_id, scope_type, source_type, title) values (null, 'global', 'textbook', 'TEST global hack');
  reset role; perform pg_temp.ok('E02', 'Evidence', 'API orqali global manba yaratish', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('E02', 'Evidence', 'API orqali global manba yaratish', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ begin perform pg_temp.logout();
  insert into public.evidence_sources (org_id, source_type, title, doi) values ('00000000-0000-0000-0000-000000000001', 'cohort_study', 'TEST invalid doi', 'not-a-doi');
  perform pg_temp.ok('E03', 'Evidence integrity', 'Noto''g''ri DOI formati', 'DENIED', 'ALLOWED', false);
exception when check_violation then perform pg_temp.ok('E03', 'Evidence integrity', 'Noto''g''ri DOI formati', 'DENIED', 'check_violation', true); end $$;
do $$ begin perform pg_temp.logout();
  insert into public.evidence_sources (org_id, source_type, title, pmid) values ('00000000-0000-0000-0000-000000000001', 'cohort_study', 'TEST invalid pmid', 'PM12AB');
  perform pg_temp.ok('E04', 'Evidence integrity', 'Noto''g''ri PMID formati', 'DENIED', 'ALLOWED', false);
exception when check_violation then perform pg_temp.ok('E04', 'Evidence integrity', 'Noto''g''ri PMID formati', 'DENIED', 'check_violation', true); end $$;
do $$ begin perform pg_temp.logout();
  insert into public.evidence_sources (org_id, source_type, title) values ('00000000-0000-0000-0000-000000000001', 'randomized_controlled_trial', 'TEST RCT without any identifier');
  perform pg_temp.ok('E05', 'Evidence integrity', 'RCT identifikatorsiz (DOI/PMID/URL yo''q)', 'DENIED', 'ALLOWED', false);
exception when check_violation then perform pg_temp.ok('E05', 'Evidence integrity', 'RCT identifikatorsiz (DOI/PMID/URL yo''q)', 'DENIED', 'check_violation', true); end $$;
do $$ begin perform pg_temp.logout();
  insert into public.evidence_sources (org_id, source_type, title, url) values ('00000000-0000-0000-0000-000000000001', 'guideline', 'TEST guideline no version', 'https://example.org/test');
  perform pg_temp.ok('E06', 'Evidence integrity', 'Guideline tashkilot/versiyasiz', 'DENIED', 'ALLOWED', false);
exception when check_violation then perform pg_temp.ok('E06', 'Evidence integrity', 'Guideline tashkilot/versiyasiz', 'DENIED', 'check_violation', true); end $$;
do $$ begin perform pg_temp.logout();
  insert into public.evidence_sources (org_id, source_type, title, url, verification_status) values ('00000000-0000-0000-0000-000000000001', 'cohort_study', 'TEST verified w/o source', 'https://example.org/x', 'verified');
  perform pg_temp.ok('E07', 'Evidence integrity', '"verified" — kim/qachon/qayerdan tekshirilgani yo''q', 'DENIED', 'ALLOWED', false);
exception when check_violation then perform pg_temp.ok('E07', 'Evidence integrity', '"verified" — kim/qachon/qayerdan tekshirilgani yo''q', 'DENIED', 'check_violation', true); end $$;

-- Instruktor tashkilot manbasini qo'shadi (TEST guideline v1) va yangi klinik savol yaratadi
do $$ declare s uuid; cb uuid; wf text; ev text; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000004'); set local role authenticated;
  insert into public.evidence_sources (org_id, source_type, title, organization, guideline_name, guideline_version, url)
    values (public.my_org(), 'guideline', 'TEST Guideline (sinov)', 'TEST SOCIETY', 'TEST HF guideline', '2024', 'https://example.org/test-hf-2024') returning id, created_by into s, cb;
  insert into public.questions (id, org_id, course_id, module_id, type, topic, stem, options, answer, explanation, workflow_status)
    values ('TQ_CARD1', public.my_org(), 'CARDIO_BASIC', 'CB3', 'single', 'HF', 'TEST: HFrEF asosiy terapiyasi?', '["A","B","C","D"]', '0', 'test izoh', 'published')
    returning workflow_status, evidence_status into wf, ev;
  insert into public.question_evidence (org_id, question_id, evidence_source_id, relationship_type, citation_text, supporting_claim)
    values (public.my_org(), 'TQ_CARD1', s, 'primary_support', 'TEST citation', 'ICHKI: tavsiya 4.2');
  reset role;
  perform pg_temp.ok('E08', 'Evidence', 'Instructor manba qo''shadi (created_by server tomonidan)', 'created_by = instructor', coalesce(cb::text, 'null'), cb = 'a0000000-0000-0000-0000-000000000004');
  perform pg_temp.ok('E09', 'Evidence', 'API orqali yaratilgan savol darhol nashr qilinmaydi', 'draft / unknown', wf || ' / ' || ev, wf = 'draft' and ev = 'unknown');
  perform pg_temp.ok('E10', 'Evidence', 'Manba bog''langani o''zi "current" qilmaydi (inson review kerak)', 'unknown',
    (select evidence_status from public.questions where id = 'TQ_CARD1'), (select evidence_status from public.questions where id = 'TQ_CARD1') = 'unknown');
end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000004'); set local role authenticated;
  update public.evidence_sources set verification_status = 'verified', verification_source = 'manual' where title = 'TEST Guideline (sinov)';
  reset role; perform pg_temp.ok('E11', 'Evidence', 'Instructor manbani "verified" qiladi (evidence.verify yo''q)', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('E11', 'Evidence', 'Instructor manbani "verified" qiladi (evidence.verify yo''q)', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000003'); set local role authenticated;
  update public.questions set workflow_status = 'published' where id = 'TQ_CARD1';
  reset role; perform pg_temp.ok('E12', 'Evidence', 'Klinik savolni evidence review''siz nashr qilish (Education Manager)', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('E12', 'Evidence', 'Klinik savolni evidence review''siz nashr qilish (Education Manager)', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ declare n int; o int; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000008'); set local role authenticated;
  select count(*) into n from public.questions; reset role;
  perform pg_temp.login('a0000000-0000-0000-0000-000000000003'); set local role authenticated;
  insert into public.question_review_assignments (org_id, question_id, reviewer_id, review_type) values (public.my_org(), 'TQ_CARD1', 'a0000000-0000-0000-0000-000000000008', 'evidence');
  reset role;
  perform pg_temp.login('a0000000-0000-0000-0000-000000000008'); set local role authenticated;
  select count(*) into o from public.questions; reset role;
  perform pg_temp.ok('MR01', 'Medical reviewer', 'Reviewer: tayinlashdan oldin / keyin ko''rinadigan savollar', '0 / 1', n || ' / ' || o, n = 0 and o = 1);
end $$;
do $$ declare vf text; vb uuid; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000008'); set local role authenticated;
  update public.evidence_sources set verification_status = 'verified', verification_source = 'manual' where title = 'TEST Guideline (sinov)'
    returning verification_status, verified_by into vf, vb;
  reset role; perform pg_temp.ok('MR02', 'Medical reviewer', 'Reviewer manbani tekshiradi (verified_by server tomonidan)', 'verified / reviewer', vf || ' / ' || coalesce(vb::text, 'null'), vf = 'verified' and vb = 'a0000000-0000-0000-0000-000000000008');
end $$;
do $$ declare ev text; due timestamptz; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000008'); set local role authenticated;
  insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision, internal_notes)
    values (public.my_org(), 'TQ_CARD1', 1, 'evidence', 'a0000000-0000-0000-0000-000000000006', 'approved', 'ICHKI: manba tekshirildi');
  reset role;
  select evidence_status, evidence_review_due_at into ev, due from public.questions where id = 'TQ_CARD1';
  perform pg_temp.ok('MR03', 'Medical reviewer', 'Evidence review tasdig''i → current + keyingi review sanasi; reviewer_id soxtalashtirilmaydi', 'current / ~24 oy / reviewer=a…08',
    ev || ' / ' || to_char(due, 'YYYY-MM') || ' / ' || (select reviewer_id::text from public.question_reviews where question_id = 'TQ_CARD1' limit 1),
    ev = 'current' and due > now() + interval '23 months' and (select reviewer_id from public.question_reviews where question_id = 'TQ_CARD1' limit 1) = 'a0000000-0000-0000-0000-000000000008');
end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000008'); set local role authenticated;
  update public.questions set workflow_status = 'published' where id = 'TQ_CARD1';
  reset role; perform pg_temp.ok('MR06', 'Medical reviewer', 'Klinik savol: Medical Review tasdig''isiz nashr (evidence current bo''lsa ham)', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('MR06', 'Medical reviewer', 'Klinik savol: Medical Review tasdig''isiz nashr (evidence current bo''lsa ham)', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000004'); set local role authenticated;
  insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision) values (public.my_org(), 'TQ_CARD1', 1, 'medical', auth.uid(), 'approved');
  reset role;
  perform pg_temp.login('a0000000-0000-0000-0000-000000000003'); set local role authenticated;
  update public.questions set workflow_status = 'published' where id = 'TQ_CARD1';
  reset role; perform pg_temp.ok('MR07', 'Medical reviewer', 'Klinik savol: faqat instructor medical review''i bilan nashr (medical reviewer emas)', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('MR07', 'Medical reviewer', 'Klinik savol: faqat instructor medical review''i bilan nashr (medical reviewer emas)', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ declare pv int; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000008'); set local role authenticated;
  insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision) values (public.my_org(), 'TQ_CARD1', 1, 'medical', auth.uid(), 'approved');
  -- 005e: Medical Reviewer nashr qilmaydi — nashrni Education Manager qiladi (barcha shartlar bilan)
  if pg_temp.has5e() then reset role; perform pg_temp.login('a0000000-0000-0000-0000-000000000003'); set local role authenticated; end if;
  update public.questions set workflow_status = 'published' where id = 'TQ_CARD1' returning published_version into pv;
  reset role; perform pg_temp.ok('MR04', 'Medical reviewer', 'Evidence review + verified manba + Medical Review → reviewer nashr qiladi', 'published_version = 1', coalesce(pv::text, 'null'), pv = 1);
exception when others then reset role; perform pg_temp.ok('MR04', 'Medical reviewer', 'Evidence review + verified manba + Medical Review → reviewer nashr qiladi', 'published_version = 1', left(sqlerrm, 60), false); end $$;
do $$ declare n int; begin perform pg_temp.logout();
  select count(*) into n from public.question_publications where question_id = 'TQ_CARD1' and evidence_status = 'current' and jsonb_array_length(evidence_snapshot) = 1;
  perform pg_temp.ok('V01', 'Versioning', 'Nashr tarixi: versiya + dalil snapshot''i saqlanadi', '1', n::text, n = 1);
end $$;

-- Ziddiyatli dalil → conflicting → nashr qilinmaydi
do $$ declare s2 uuid; ev text; begin perform pg_temp.logout();
  insert into public.evidence_sources (org_id, source_type, title, url) values ('00000000-0000-0000-0000-000000000001', 'cohort_study', 'TEST conflicting cohort (sinov)', 'https://example.org/test-cohort')
    returning id into s2;
  -- 005e: nashr qilingan savolga ziddiyatli dalil bog'lash faqat evidence.review (EM); kontent tahririni instruktor qiladi
  perform pg_temp.login(case when pg_temp.has5e() then 'a0000000-0000-0000-0000-000000000003' else 'a0000000-0000-0000-0000-000000000004' end::uuid); set local role authenticated;
  insert into public.question_evidence (org_id, question_id, evidence_source_id, relationship_type) values (public.my_org(), 'TQ_CARD1', s2, 'conflicting_evidence');
  reset role; perform pg_temp.login('a0000000-0000-0000-0000-000000000004'); set local role authenticated;
  update public.questions set stem = 'TEST: HFrEF asosiy terapiyasi (v2)?' where id = 'TQ_CARD1';
  reset role;
  select evidence_status into ev from public.questions where id = 'TQ_CARD1';
  perform pg_temp.ok('E13', 'Evidence', 'Conflicting evidence qo''shildi → evidence_status', 'conflicting', ev, ev = 'conflicting');
  perform pg_temp.ok('EL07', 'Eligibility', 'Conflicting savol → review_required, yangi imtihonga yaroqsiz', 'review_required / false',
    (select workflow_status || ' / ' || public._q_exam_eligible(q) from public.questions q where id = 'TQ_CARD1'),
    (select workflow_status = 'review_required' and not public._q_exam_eligible(q) from public.questions q where id = 'TQ_CARD1'));
  perform pg_temp.ok('E14', 'Evidence', 'Conflict hodisasi (evidence_events) yozildi', '>=1',
    (select count(*) from public.evidence_events where question_id = 'TQ_CARD1' and event_type = 'conflict_detected')::text,
    exists (select 1 from public.evidence_events where question_id = 'TQ_CARD1' and event_type = 'conflict_detected'));
end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000008'); set local role authenticated;
  update public.questions set workflow_status = 'published' where id = 'TQ_CARD1';
  reset role; perform pg_temp.ok('E15', 'Evidence', 'Conflicting savolni nashr qilish (reviewer ham)', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('E15', 'Evidence', 'Conflicting savolni nashr qilish (reviewer ham)', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ declare cv int; pv int; wf text; begin perform pg_temp.logout();
  select current_version, published_version, coalesce(draft_status, '-') || ' / ' || workflow_status into cv, pv, wf from public.questions where id = 'TQ_CARD1';
  perform pg_temp.ok('V02', 'Versioning', 'Conflicting savol tahrirlandi → v2 draft_status=draft, nashr qilingan v1 saqlanadi, workflow review_required', 'cur=2 / pub=1 / draft / review_required', 'cur=' || cv || ' / pub=' || pv || ' / ' || wf, cv = 2 and pv = 1 and wf = 'draft / review_required');
end $$;

-- Guideline yangi versiyasi eski versiyani almashtiradi
do $$ declare s3 uuid; olds text; ev text; ex boolean; begin perform pg_temp.logout();
  delete from public.question_evidence where question_id = 'TQ_CARD1' and relationship_type = 'conflicting_evidence';
  -- 005e: guideline almashtirish (supersedes) faqat evidence.review — instruktor emas, Education Manager
  perform pg_temp.login(case when exists (select 1 from public.schema_migrations where version = '005e') then 'a0000000-0000-0000-0000-000000000003' else 'a0000000-0000-0000-0000-000000000004' end::uuid); set local role authenticated;
  insert into public.evidence_sources (org_id, source_type, title, organization, guideline_name, guideline_version, url, supersedes_id)
    values (public.my_org(), 'guideline', 'TEST Guideline 2026 (sinov)', 'TEST SOCIETY', 'TEST HF guideline', '2026', 'https://example.org/test-hf-2026',
            (select id from public.evidence_sources where title = 'TEST Guideline (sinov)')) returning id into s3;
  reset role;
  select status into olds from public.evidence_sources where title = 'TEST Guideline (sinov)';
  select evidence_status into ev from public.questions where id = 'TQ_CARD1';
  select exists (select 1 from public.questions where id = 'TQ_CARD1') into ex;
  perform pg_temp.ok('E16', 'Guideline versioning', 'Yangi guideline (2026) → eski (2024) superseded, savol superseded, savol o''chmaydi', 'superseded / superseded / bor',
    olds || ' / ' || ev || ' / ' || case when ex then 'bor' else 'yo''q' end, olds = 'superseded' and ev = 'superseded' and ex);
  perform pg_temp.ok('E17', 'Guideline versioning', 'new_guideline_version hodisasi', '1',
    (select count(*) from public.evidence_events where event_type = 'new_guideline_version' and evidence_source_id = (select id from public.evidence_sources where title = 'TEST Guideline (sinov)'))::text,
    (select count(*) from public.evidence_events where event_type = 'new_guideline_version' and evidence_source_id = (select id from public.evidence_sources where title = 'TEST Guideline (sinov)')) = 1);
end $$;
do $$ declare sp uuid; sa uuid; e1 text; e2 text; w1 text; w2 text; el1 boolean; el2 boolean; m int; begin perform pg_temp.logout();
  -- TEST: ikki savol SQL orqali "review'dan o'tgan" holatga keltiriladi; biri primary, biri additional manbaga tayanadi
  insert into public.evidence_sources (org_id, source_type, title, url, verification_status, verification_source, verified_at)
    values ('00000000-0000-0000-0000-000000000001', 'randomized_controlled_trial', 'TEST RCT primary (sinov)', 'https://example.org/test-rct-p', 'verified', 'manual', now()) returning id into sp;
  insert into public.evidence_sources (org_id, source_type, title, url) values ('00000000-0000-0000-0000-000000000001', 'cohort_study', 'TEST cohort additional (sinov)', 'https://example.org/test-coh-a') returning id into sa;
  insert into public.question_evidence (org_id, question_id, evidence_source_id, relationship_type) values
    ('00000000-0000-0000-0000-000000000001', 'Q001', sp, 'primary_support'), ('00000000-0000-0000-0000-000000000001', 'Q002', sp, 'primary_support'),
    ('00000000-0000-0000-0000-000000000001', 'Q002', sa, 'additional_support');
  update public.evidence_sources set status = 'retracted' where id = sa;          -- faqat Q002 ning qo'shimcha manbasi
  select evidence_status, workflow_status, public._q_exam_eligible(q) into e2, w2, el2 from public.questions q where id = 'Q002';
  update public.evidence_sources set status = 'retracted' where id = sp;          -- Q001 ning asosiy manbasi
  select evidence_status, workflow_status, public._q_exam_eligible(q) into e1, w1, el1 from public.questions q where id = 'Q001';
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  select count(*) into m from jsonb_array_elements(public.question_meta()) x where x ->> 'id' in ('Q001','Q002'); reset role;
  perform pg_temp.ok('E18', 'Retraction', 'Asosiy manba retracted → outdated + review_required + yangi imtihondan chiqarildi', 'outdated / review_required / false',
    e1 || ' / ' || w1 || ' / ' || el1, e1 = 'outdated' and w1 = 'review_required' and not el1);
  perform pg_temp.ok('EL08', 'Retraction', 'Qo''shimcha manba retracted → review_due + review_required (yaroqsiz)', 'review_due / review_required / false',
    e2 || ' / ' || w2 || ' / ' || el2, e2 = 'review_due' and w2 = 'review_required' and not el2);
  perform pg_temp.ok('EL09', 'Retraction', 'Xodim uchun question_meta''da Q001/Q002 yo''q', '0', m::text, m = 0);
  perform pg_temp.ok('EL10', 'Retraction', 'Savol matni/javobi avtomatik o''zgarmadi (versiya 1 saqlangan)', 'cur=1',
    (select 'cur=' || current_version from public.questions where id = 'Q001'), (select current_version = 1 and stem = (select snapshot ->> 'stem' from public.question_versions where question_id = 'Q001' and version_no = 1) from public.questions where id = 'Q001'));
end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000004'); set local role authenticated;
  update public.questions set evidence_status = 'current' where id = 'TQ_CARD1';
  reset role; perform pg_temp.ok('E19', 'Evidence', 'API orqali evidence_status ni to''g''ridan-to''g''ri "current" qilish', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('E19', 'Evidence', 'API orqali evidence_status ni to''g''ridan-to''g''ri "current" qilish', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000003'); set local role authenticated;
  update public.questions set published_version = 2 where id = 'TQ_CARD1';
  reset role; perform pg_temp.ok('V03', 'Versioning', 'API orqali published_version ni o''zgartirish', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('V03', 'Versioning', 'API orqali published_version ni o''zgartirish', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ begin perform pg_temp.logout();
  update public.question_versions set snapshot = '{}' where question_id = 'Q001';
  perform pg_temp.ok('V04', 'Versioning', 'Eski versiyani tahrirlash (hatto SQL orqali)', 'DENIED', 'ALLOWED', false);
exception when others then perform pg_temp.ok('V04', 'Versioning', 'Eski versiyani tahrirlash (hatto SQL orqali)', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ begin perform pg_temp.logout();
  delete from public.question_versions where question_id = 'Q001';
  perform pg_temp.ok('V05', 'Versioning', 'Eski versiyani o''chirish', 'DENIED', 'ALLOWED', false);
exception when others then perform pg_temp.ok('V05', 'Versioning', 'Eski versiyani o''chirish', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000004'); set local role authenticated;
  update public.questions set evidence_exempt = true, evidence_exempt_reason = 'klinik emas deb hisoblayman' where id = 'TQ_CARD1';
  reset role; perform pg_temp.ok('E20', 'Evidence', 'Instructor savolni dalildan ozod qiladi (evidence.review yo''q)', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('E20', 'Evidence', 'Instructor savolni dalildan ozod qiladi (evidence.review yo''q)', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;

-- AI kontent: inson review'isiz nashr qilinmaydi (klinik bo'lmagan kurs — faqat AI qoidasi sinaladi)
do $$ declare wf text; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000003'); set local role authenticated;
  insert into public.questions (id, org_id, course_id, module_id, type, stem, options, answer, explanation, ai_generated, workflow_status)
    values ('TQ_AI1', public.my_org(), 'SALES', (select module_id from public.questions where course_id = 'SALES' limit 1), 'single', 'TEST AI savol?', '["A","B"]', '0', 'x', true, 'published')
    returning workflow_status into wf;
  reset role; perform pg_temp.ok('AI01', 'AI workflow', 'AI yaratgan savol "published" bilan kiritilsa ham → draft', 'draft', wf, wf = 'draft');
end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000003'); set local role authenticated;
  update public.questions set workflow_status = 'published' where id = 'TQ_AI1';
  reset role; perform pg_temp.ok('AI02', 'AI workflow', 'AI savolni inson review''isiz nashr qilish (Education Manager)', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('AI02', 'AI workflow', 'AI savolni inson review''isiz nashr qilish (Education Manager)', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ declare pv int; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000003'); set local role authenticated;
  -- 005e: EM medical review yoza olmaydi — klinik bo'lmagan AI savol uchun inson (instructor-turi) review
  insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision) values (public.my_org(), 'TQ_AI1', 1, case when pg_temp.has5e() then 'instructor' else 'medical' end, auth.uid(), 'approved');
  update public.questions set evidence_exempt = true, evidence_exempt_reason = 'Sales & Service: ichki xizmat standarti asosida' where id = 'TQ_AI1';
  update public.questions set workflow_status = 'published' where id = 'TQ_AI1' returning published_version into pv;
  reset role; perform pg_temp.ok('AI03', 'AI workflow', 'Inson review + (klinik bo''lmagan) asos/ozod qilishdan keyin AI savol nashr qilinadi', 'published_version = 1', coalesce(pv::text, 'null'), pv = 1);
exception when others then reset role; perform pg_temp.ok('AI03', 'AI workflow', 'Inson review + (klinik bo''lmagan) asos/ozod qilishdan keyin AI savol nashr qilinadi', 'published_version = 1', left(sqlerrm, 60), false); end $$;
do $$ declare o jsonb; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000004'); set local role authenticated;
  insert into public.ai_jobs (org_id, task_type, input, output, status) values (public.my_org(), 'evidence_search', '{"q":"AF anticoagulation"}', '{"fake":"result"}', 'completed') returning output into o;
  reset role; perform pg_temp.ok('AI04', 'AI workflow', 'Klient AI natijasini o''zi yozib qo''yadi (output/status)', 'output=null, queued', coalesce(o::text, 'null'), o is null);
end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  insert into public.ai_jobs (org_id, task_type) values (public.my_org(), 'question_generation');
  reset role; perform pg_temp.ok('AI05', 'AI workflow', 'Xodim AI vazifasini ishga tushiradi', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('AI05', 'AI workflow', 'Xodim AI vazifasini ishga tushiradi', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ declare qid uuid; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000004'); set local role authenticated;
  insert into public.research_queries (org_id, query_text, databases) values (public.my_org(), 'heart failure SGLT2', '{pubmed,cochrane}') returning id into qid;
  insert into public.research_results (org_id, query_id, external_db, pmid, title, raw_metadata, retrieved_at) values (public.my_org(), qid, 'pubmed', '12345678', 'FAKE result', '{}', now());
  reset role; perform pg_temp.ok('RS01', 'Research', 'Klient research natijasini (soxta) yozadi', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('RS01', 'Research', 'Klient research natijasini (soxta) yozadi', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000004'); set local role authenticated;
  insert into public.research_queries (org_id, query_text, databases) values (public.my_org(), 'x test', '{google}');
  reset role; perform pg_temp.ok('RS02', 'Research', 'Ruxsat etilmagan research bazasi', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('RS02', 'Research', 'Ruxsat etilmagan research bazasi', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000004'); set local role authenticated;
  insert into public.evidence_summaries (org_id, summary, source_ids) values (public.my_org(), 'x', array[gen_random_uuid()]);
  reset role; perform pg_temp.ok('RS03', 'Research', 'Mavjud bo''lmagan manbaga asoslangan xulosa', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('RS03', 'Research', 'Mavjud bo''lmagan manbaga asoslangan xulosa', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;

-- ===================== EL2. Versiya, qarorlar, tarix, ierarxiya, research integrity =====================
do $$ declare old_stem text; cv int; pv int; ds text; el boolean; srv text; begin perform pg_temp.logout();
  select stem into old_stem from public.questions where id = 'Q003';
  perform pg_temp.login('a0000000-0000-0000-0000-000000000003'); set local role authenticated;
  update public.questions set stem = stem || ' (v2 loyiha)' where id = 'Q003';
  reset role;
  select current_version, published_version, draft_status, public._q_exam_eligible(q), (public._q_at(q.id, q.published_version)).stem into cv, pv, ds, el, srv from public.questions q where id = 'Q003';
  perform pg_temp.ok('EL11', 'Versioning', 'v1 published + v2 draft: v1 imtihonda qoladi (yaroqli, v1 matni beriladi)', 'cur=2 pub=1 draft eligible v1-matn',
    'cur=' || cv || ' pub=' || pv || ' ' || coalesce(ds, '-') || ' ' || case when el then 'eligible' else 'NOT' end || ' ' || case when srv = old_stem then 'v1-matn' else 'BOSHQA' end,
    cv = 2 and pv = 1 and ds = 'draft' and el and srv = old_stem);
end $$;
do $$ declare pv int; v1 int; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000003'); set local role authenticated;
  update public.questions set draft_status = 'publish' where id = 'Q003' returning published_version into pv;
  reset role;
  select count(*) into v1 from public.question_versions where question_id = 'Q003' and version_no = 1;
  perform pg_temp.ok('EL12', 'Versioning', 'v2 tasdiqlangach nashr: published_version=2, v1 tarixiy versiya sifatida saqlanadi', 'pub=2 / v1 bor',
    'pub=' || coalesce(pv::text, 'null') || ' / v1=' || v1, pv = 2 and v1 = 1);
exception when others then reset role; perform pg_temp.ok('EL12', 'Versioning', 'v2 tasdiqlangach nashr: published_version=2, v1 tarixiy versiya sifatida saqlanadi', 'pub=2 / v1 bor', left(sqlerrm, 60), false); end $$;
do $$ declare w text; ev text; el boolean; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000003'); set local role authenticated;
  insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision, internal_notes)
    values (public.my_org(), 'Q004', 1, case when pg_temp.has5e() then 'evidence' else 'medical' end, auth.uid(), 'mark_outdated', 'ICHKI: yangi tavsiya bor');   -- 005e: EM → evidence review turi
  reset role;
  select workflow_status, evidence_status, public._q_exam_eligible(q) into w, ev, el from public.questions q where id = 'Q004';
  perform pg_temp.ok('EL13', 'Review decision', 'Reviewer qarori "Mark Outdated" → outdated + review_required + yaroqsiz', 'review_required / outdated / false',
    w || ' / ' || ev || ' / ' || el, w = 'review_required' and ev = 'outdated' and not el);
end $$;
do $$ declare att jsonb; ans jsonb; res jsonb; sc0 numeric; sc1 numeric; ver jsonb; q1 text; st0 text; st1 text; rv jsonb; nres0 int; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000007'); set local role authenticated;
  att := public.start_exam('ETHICS', 'final', null, null, false); reset role;
  select jsonb_object_agg(q.id, case when q.type = 'match' then (select jsonb_object_agg((i - 1)::text, e) from jsonb_array_elements(q.answer) with ordinality x(e, i))
                                     when q.type = 'short' then q.answer -> 0 else q.answer end)
    into ans from unnest((select qids from public.exam_attempts where id = att ->> 'id')) u(qid) cross join lateral public._q_at(u.qid, ((select question_versions from public.exam_attempts where id = att ->> 'id') ->> u.qid)::int) q;
  perform pg_temp.login('a0000000-0000-0000-0000-000000000007'); set local role authenticated;
  res := public.submit_exam(att ->> 'id', ans); reset role;
  q1 := att -> 'qids' ->> 0;
  select score, results::text into sc0, st0 from public.exam_attempts where id = att ->> 'id';
  -- Imtihondan keyin: savol matni yangilanadi, dalili "outdated" qilinadi
  perform pg_temp.logout();
  update public.questions set stem = stem || ' [keyingi tahrir]' where id = q1;
  perform pg_temp.login('a0000000-0000-0000-0000-000000000003'); set local role authenticated;
  insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision) values (public.my_org(), q1, 1, 'evidence', auth.uid(), 'mark_outdated');
  reset role;
  select score, results::text into sc1, st1 from public.exam_attempts where id = att ->> 'id';
  ver := public.verify_certificate(res -> 'certificate' ->> 'id');
  perform pg_temp.login('a0000000-0000-0000-0000-000000000007'); set local role authenticated;
  rv := public.get_attempt_review(att ->> 'id'); reset role;
  perform pg_temp.ok('EL14', 'Historical integrity', 'Dalil outdated + savol tahrirlangandan keyin: urinish bali/natijalari o''zgarmagan, sertifikat amalda, review eski versiya',
    'score teng / results teng / Amalda / v1 matn',
    sc0 || '=' || sc1 || ' / ' || case when st0 = st1 then 'teng' else 'O''ZGARGAN' end || ' / ' || coalesce(ver ->> 'status', 'null') || ' / ' ||
      case when (select x ->> 'q' from jsonb_array_elements(rv -> 'questions') x where x ->> 'id' = q1) not like '%[keyingi tahrir]%' then 'v1 matn' else 'YANGI MATN' end,
    sc0 = sc1 and st0 = st1 and ver ->> 'status' = 'Amalda' and (select x ->> 'q' from jsonb_array_elements(rv -> 'questions') x where x ->> 'id' = q1) not like '%[keyingi tahrir]%'
    and (select workflow_status from public.questions where id = q1) = 'review_required');
end $$;
do $$ declare t1 text; t2 text; t3 text; begin perform pg_temp.logout();
  select evidence_tier into t1 from public.evidence_sources where title = 'TEST Guideline (sinov)';
  select evidence_tier into t2 from public.evidence_sources where title = 'TEST conflicting cohort (sinov)';
  select evidence_tier into t3 from public.evidence_sources where title like 'TEST — global darslik%';
  perform pg_temp.ok('EL15', 'Source hierarchy', 'Ierarxiya metadata: guideline / cohort / textbook', 'primary_authoritative / secondary / educational',
    coalesce(t1,'null') || ' / ' || coalesce(t2,'null') || ' / ' || coalesce(t3,'null'), t1 = 'primary_authoritative' and t2 = 'secondary' and t3 = 'educational');
end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000004'); set local role authenticated;
  update public.evidence_sources set evidence_level = 'A', evidence_level_scheme = 'MEDACADEMY_ABCD' where title = 'TEST Guideline 2026 (sinov)';
  reset role; perform pg_temp.ok('EL16', 'Source hierarchy', 'Instructor dalil darajasini belgilaydi (evidence.review yo''q)', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('EL16', 'Source hierarchy', 'Instructor dalil darajasini belgilaydi (evidence.review yo''q)', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ declare sb uuid; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000003'); set local role authenticated;
  update public.evidence_sources set evidence_level = 'A', evidence_level_scheme = 'MEDACADEMY_ABCD', evidence_level_basis = 'reviewer_assessed' where title = 'TEST Guideline 2026 (sinov)'
    returning evidence_level_set_by into sb;
  reset role; perform pg_temp.ok('EL17', 'Source hierarchy', 'Reviewer (evidence.review) darajani belgilaydi; kim belgilagani yoziladi', 'set_by = a…03', coalesce(sb::text, 'null'), sb = 'a0000000-0000-0000-0000-000000000003');
end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000004'); set local role authenticated;
  insert into public.evidence_sources (org_id, source_type, title, doi, origin) values (public.my_org(), 'meta_analysis', 'TEST AI suggested', '10.1234/test.ai', 'ai_suggested');
  reset role; perform pg_temp.ok('EL18', 'Research integrity', 'Klient "AI taklif qilgan" manbani to''g''ridan-to''g''ri yaratadi', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('EL18', 'Research integrity', 'Klient "AI taklif qilgan" manbani to''g''ridan-to''g''ri yaratadi', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ declare rq uuid; rr uuid; sid uuid; o text; v text; d text; begin perform pg_temp.logout();
  insert into public.research_queries (org_id, query_text, databases) values ('00000000-0000-0000-0000-000000000001', 'TEST query', '{pubmed}') returning id into rq;
  insert into public.research_results (org_id, query_id, external_db, doi, title, raw_metadata, retrieved_at)
    values ('00000000-0000-0000-0000-000000000001', rq, 'pubmed', '10.5555/test.import', 'TEST imported result (sinov)', '{"source":"test-fixture"}', now()) returning id into rr;
  perform pg_temp.login('a0000000-0000-0000-0000-000000000004'); set local role authenticated;
  sid := public.import_research_result(rr, 'cohort_study'); reset role;
  select origin, verification_status, doi into o, v, d from public.evidence_sources where id = sid;
  perform pg_temp.ok('EL19', 'Research integrity', 'Research importi: identifikator natijadan, origin=research_import, unverified', 'research_import / unverified / 10.5555/test.import',
    o || ' / ' || v || ' / ' || coalesce(d, 'null'), o = 'research_import' and v = 'unverified' and d = '10.5555/test.import');
end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000003'); set local role authenticated;
  update public.questions set evidence_exempt = true, evidence_exempt_reason = 'klinik savolni ozod qilishga urinish' where id = 'TQ_CARD1';
  reset role; perform pg_temp.ok('EL20', 'Eligibility', 'Klinik savolni dalildan ozod qilish (Education Manager ham)', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('EL20', 'Eligibility', 'Klinik savolni dalildan ozod qilish (Education Manager ham)', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000003'); set local role authenticated;
  insert into public.questions (id, org_id, course_id, module_id, type, stem, options, answer, explanation) values ('TQ_SALES1', public.my_org(), 'SALES',
    (select module_id from public.questions where course_id = 'SALES' limit 1), 'single', 'TEST: xizmat standarti?', '["A","B"]', '0', 'x');
  update public.questions set workflow_status = 'published' where id = 'TQ_SALES1';
  reset role; perform pg_temp.ok('EL21', 'Eligibility', 'Klinik bo''lmagan savolni manba/asos va ozod qilishsiz nashr qilish', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('EL21', 'Eligibility', 'Klinik bo''lmagan savolni manba/asos va ozod qilishsiz nashr qilish', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ declare w text; begin perform pg_temp.logout();
  select workflow_status into w from public.questions where id = 'TQ_CARD1';
  perform pg_temp.ok('EL22', 'Guideline update', 'Guideline yangilanishi → bog''langan savol review_required (matn o''zgarmaydi)', 'review_required', w, w = 'review_required');
end $$;

-- ===================== M. Ko'p tashkilot =====================
do $$ declare n int; begin perform pg_temp.logout();
  perform pg_temp.login('262a128c-6fb7-470e-9452-5468cd6797c0'); set local role authenticated;
  select (select count(*) from public.course_modules where org_id <> public.my_org()) + (select count(*) from public.lessons where org_id <> public.my_org())
       + (select count(*) from public.learning_paths where org_id <> public.my_org()) + (select count(*) from public.course_assignments where org_id <> public.my_org())
       + (select count(*) from public.evidence_sources where org_id <> public.my_org()) + (select count(*) from public.questions where org_id <> public.my_org())
       + (select count(*) from public.question_versions where org_id <> public.my_org()) + (select count(*) from public.courses where org_id <> public.my_org()) into n;
  reset role; perform pg_temp.ok('M01', 'Multi-org', 'Org A Super Admin → Org B (modul, dars, path, tayinlash, manba, savol, versiya, kurs)', '0', n::text, n = 0);
end $$;
do $$ declare own int; oth int; glob int; begin perform pg_temp.logout();
  perform pg_temp.login('b0000000-0000-0000-0000-000000000001'); set local role authenticated;
  select count(*) into own from public.questions;
  select count(*) into oth from public.evidence_sources where scope_type = 'organization' and org_id <> public.my_org();
  select count(*) into glob from public.evidence_sources where scope_type = 'global';
  reset role; perform pg_temp.ok('M02', 'Multi-org', 'Org B Admin: o''z savoli / Org A manbalari / global kutubxona', '1 / 0 / >=1', own || ' / ' || oth || ' / ' || glob, own = 1 and oth = 0 and glob >= 1);
end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('b0000000-0000-0000-0000-000000000001'); set local role authenticated;
  insert into public.question_evidence (org_id, question_id, evidence_source_id, relationship_type)
    values (public.my_org(), 'TESTB_Q1', pg_temp.src('TEST Guideline 2026 (sinov)'), 'primary_support');
  reset role; perform pg_temp.ok('M03', 'Multi-org', 'Org B savoliga Org A manbasini bog''lash', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('M03', 'Multi-org', 'Org B savoliga Org A manbasini bog''lash', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('262a128c-6fb7-470e-9452-5468cd6797c0'); set local role authenticated;
  insert into public.course_assignments (org_id, course_id, employee_id) values (public.my_org(), 'TESTB_CARDIO', pg_temp.emp('a0000000-0000-0000-0000-000000000006'));
  reset role; perform pg_temp.ok('M04', 'Multi-org', 'Org A xodimiga Org B kursini tayinlash', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('M04', 'Multi-org', 'Org A xodimiga Org B kursini tayinlash', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ declare n int; begin perform pg_temp.logout();
  perform pg_temp.login('b0000000-0000-0000-0000-000000000002'); set local role authenticated;
  select (select count(*) from public.lessons where org_id <> public.my_org()) + (select count(*) from public.course_modules where org_id <> public.my_org())
       + (select count(*) from public.learning_paths where org_id <> public.my_org()) into n;
  reset role; perform pg_temp.ok('M05', 'Multi-org', 'Org B xodimi → Org A darslari/modullari/path''lari', '0', n::text, n = 0);
end $$;
do $$ declare n int; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000008'); set local role authenticated;
  select (select count(*) from public.evidence_sources where org_id = '0000000b-0000-0000-0000-00000000000b') + (select count(*) from public.questions where org_id = '0000000b-0000-0000-0000-00000000000b') into n;
  reset role; perform pg_temp.ok('MR05', 'Medical reviewer', 'Org A reviewer → Org B manba/savollari', '0', n::text, n = 0);
end $$;

-- ===================== N. Anonim =====================
do $$ declare t text; denied int := 0; total int := 0; begin perform pg_temp.logout();
  perform set_config('request.jwt.claims', '{"role":"anon"}', true); perform set_config('request.jwt.claim.sub', '', true);
  foreach t in array array['course_modules','lessons','course_assignments','lesson_progress','learning_paths','learning_path_courses','course_instructors','org_invitations',
    'content_policies','medical_topics','evidence_grading_schemes','evidence_sources','evidence_source_topics','question_evidence','question_versions','question_publications',
    'question_review_assignments','question_reviews','question_quality_scores','research_queries','research_results','ai_jobs','evidence_summaries','evidence_monitors','evidence_events'] loop
    total := total + 1;
    begin set local role anon; execute format('select 1 from public.%I limit 1', t); reset role;
    exception when others then denied := denied + 1; reset role; end;
  end loop;
  perform pg_temp.ok('N01', 'Anonymous', 'Anonim → 005 dagi 25 ta yangi jadval', '25/25 DENIED', denied || '/' || total, denied = total);
end $$;

-- ===================== INV. Yangi foydalanuvchi tashkiloti =====================
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000002'); set local role authenticated;
  insert into public.org_invitations (org_id, email, role, department_id) values (public.my_org(), 'new.nurse@test.local', 'employee',
    (select id from public.departments where org_id = public.my_org() and code = 'THERAPY'));
  reset role;
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values ('a0000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'new.nurse@test.local', '{"full_name":"Yangi Hamshira"}', now(), now()),
           ('a0000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'stranger@test.local', '{}', now(), now());
  perform pg_temp.ok('INV01', 'New-user org model', 'Taklifnoma bilan ro''yxatdan o''tish → org/rol/bo''lim, faol, employee yozuvi',
    'org A / employee / active / Terapiya / employee bor',
    (select case when org_id = '00000000-0000-0000-0000-000000000001' then 'org A' else org_id::text end || ' / ' || role || ' / ' || status || ' / ' || coalesce(department, '-') from public.profiles where id = 'a0000000-0000-0000-0000-0000000000f1')
      || ' / ' || case when exists (select 1 from public.employees where profile_id = 'a0000000-0000-0000-0000-0000000000f1') then 'employee bor' else 'employee yo''q' end,
    (select role = 'employee' and status = 'active' and department = 'Terapiya' from public.profiles where id = 'a0000000-0000-0000-0000-0000000000f1')
      and exists (select 1 from public.employees where profile_id = 'a0000000-0000-0000-0000-0000000000f1')
      and (select status from public.org_invitations where email = 'new.nurse@test.local') = 'accepted');
  perform pg_temp.ok('INV02', 'New-user org model', 'Taklifnomasiz ro''yxatdan o''tish → avvalgidek pending (faollashtirish HR''da)', 'pending',
    (select status from public.profiles where id = 'a0000000-0000-0000-0000-0000000000f2'), (select status from public.profiles where id = 'a0000000-0000-0000-0000-0000000000f2') = 'pending');
end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000002'); set local role authenticated;
  insert into public.org_invitations (org_id, email, role) values (public.my_org(), 'boss@test.local', 'super_admin');
  reset role; perform pg_temp.ok('INV03', 'New-user org model', 'Taklifnoma orqali super_admin berish', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('INV03', 'New-user org model', 'Taklifnoma orqali super_admin berish', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  insert into public.org_invitations (org_id, email, role) values (public.my_org(), 'friend@test.local', 'employee');
  reset role; perform pg_temp.ok('INV04', 'New-user org model', 'Xodim taklifnoma yuboradi', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('INV04', 'New-user org model', 'Xodim taklifnoma yuboradi', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;

-- ===================== R. Phase 1 regressiya + versiyalangan imtihon =====================
do $$ declare ok boolean; v text; begin perform pg_temp.logout();
  select (select count(*) from public.questions where org_id = '00000000-0000-0000-0000-000000000001' and id like 'Q%') = 131
     and (select count(*) from public.exam_configs where org_id = '00000000-0000-0000-0000-000000000001') = 13
     and (select role || '/' || status from public.profiles where id = '262a128c-6fb7-470e-9452-5468cd6797c0') = 'super_admin/active'
     and (select count(*) from public.question_versions where question_id like 'Q%') >= 131
     and (select count(*) from public.question_versions where question_id like 'Q%' and version_no = 1) = 131
    into ok;
  select (select count(*) from public.questions where id like 'Q%') || ' savol, o''chirilgan=0, v1=' ||
         (select count(*) from public.question_versions where question_id like 'Q%' and version_no = 1) into v;
  perform pg_temp.ok('Q131', '131-question impact', '131 savol saqlangan, v1 snapshot''lar butun (test oxirida)', '131 / v1=131', v, ok);
end $$;
do $$ declare att jsonb; res jsonb; ans jsonb; ver jsonb; asg text; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  att := public.start_exam('ETHICS', 'final', null, null, false);
  reset role;
  select jsonb_object_agg(q.id, case when q.type = 'match' then (select jsonb_object_agg((i - 1)::text, e) from jsonb_array_elements(q.answer) with ordinality x(e, i))
                                     when q.type = 'short' then q.answer -> 0 else q.answer end)
    into ans from public.questions q where q.id in (select jsonb_array_elements_text(att -> 'qids'));
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  res := public.submit_exam(att ->> 'id', ans);
  ver := public.verify_certificate(res -> 'certificate' ->> 'id');
  reset role;
  select status into asg from public.course_assignments where employee_id = pg_temp.emp('a0000000-0000-0000-0000-000000000006') and course_id = 'ETHICS';
  perform pg_temp.ok('R01', 'Phase 1', 'Imtihon payload: javob, manba, ichki izoh yo''q', 'true',
    (select bool_and(not (q ? 'a') and not (q ? 'refs') and not (q ? 'e') and not (q ? 'ev')) from jsonb_array_elements(att -> 'questions') q)::text,
    (select bool_and(not (q ? 'a') and not (q ? 'refs') and not (q ? 'e') and not (q ? 'ev')) from jsonb_array_elements(att -> 'questions') q));
  perform pg_temp.ok('R02', 'Phase 1', 'Urinish savol versiyalarini qayd qiladi', 'har savol uchun v1',
    jsonb_array_length(res -> 'attempt' -> 'qids') || ' savol / ' || left((select question_versions::text from public.exam_attempts where id = att ->> 'id'), 60),
    (select count(*) from jsonb_each_text((select question_versions from public.exam_attempts where id = att ->> 'id'))) = jsonb_array_length(att -> 'qids'));
  perform pg_temp.ok('R03', 'Phase 1', 'To''g''ri javob → 100% + sertifikat + QR', '100 / Amalda', (res -> 'attempt' ->> 'score') || ' / ' || coalesce(ver ->> 'status', 'null'),
    (res -> 'attempt' ->> 'score')::numeric = 100 and ver ->> 'status' = 'Amalda');
  perform pg_temp.ok('R04', 'Phase 1', 'Sertifikat → tayinlash avtomatik completed', 'completed', asg, asg = 'completed');
  perform pg_temp.ok('R05', 'Phase 1', 'Natijadan keyin: izoh + manba ro''yxati bor, ichki izoh/supporting_claim yo''q', 'true',
    (select bool_and((q ? 'e') and (q ? 'refs') and q::text not like '%supporting_claim%' and q::text not like '%internal_notes%') from jsonb_array_elements(res -> 'questions') q)::text,
    (select bool_and((q ? 'e') and (q ? 'refs') and q::text not like '%supporting_claim%' and q::text not like '%internal_notes%') from jsonb_array_elements(res -> 'questions') q));
end $$;
do $$ declare ini jsonb; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000007'); set local role authenticated;
  ini := public.start_exam('INITIAL', 'initial', null, '{"medical":"RESIDENT_START","ethics":"ETHICS","communication":"COMM","safety":"SAFETY","public_health":"PH","sales":"SALES"}'::jsonb, false);
  reset role; perform pg_temp.ok('R06', 'Phase 1', 'Initial assessment (12 savol)', '12', jsonb_array_length(ini -> 'qids')::text, jsonb_array_length(ini -> 'qids') = 12);
end $$;
do $$ declare att jsonb; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000007'); set local role authenticated;
  att := public.start_exam('PH', 'final', null, null, false); perform public.submit_exam(att ->> 'id', '{}'::jsonb);
  begin perform public.start_exam('PH', 'final', null, null, false); reset role; perform pg_temp.ok('R07', 'Phase 1', 'Fail → retake bloklanadi', 'DENIED', 'ALLOWED', false);
  exception when others then reset role; perform pg_temp.ok('R07', 'Phase 1', 'Fail → retake bloklanadi', 'DENIED', 'DENIED: ' || left(sqlerrm, 40), true); end;
end $$;
-- Tarixiy urinish: savol keyin o'zgartirilsa ham review eski versiyani ko'rsatadi
do $$ declare att jsonb; old_stem text; rv jsonb; q1 text; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  att := public.start_exam('COMM', 'final', null, null, false); perform public.submit_exam(att ->> 'id', '{}'::jsonb);
  reset role;
  q1 := att -> 'qids' ->> 0;
  perform pg_temp.logout();
  select stem into old_stem from public.questions where id = q1;
  update public.questions set stem = stem || ' [v2 tahrir]' where id = q1;      -- SQL (platforma) orqali v2
  update public.questions set draft_status = 'publish' where id = q1;           -- v2 nashr (platforma)
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  rv := public.get_attempt_review(att ->> 'id');
  reset role;
  perform pg_temp.ok('V06', 'Versioning', 'Savol v2 nashr qilingandan keyin eski urinish review''i v1 matnini ko''rsatadi', 'v1 matn',
    (select q ->> 'q' from jsonb_array_elements(rv -> 'questions') q where q ->> 'id' = q1),
    (select q ->> 'q' from jsonb_array_elements(rv -> 'questions') q where q ->> 'id' = q1) = old_stem
    and (select published_version from public.questions where id = q1) = 2);
end $$;
do $$ declare rv jsonb; begin perform pg_temp.logout();
  perform pg_temp.login('262a128c-6fb7-470e-9452-5468cd6797c0'); set local role authenticated;
  rv := public.get_attempt_review((select id from public.exam_attempts where kind = 'initial' and user_id = '262a128c-6fb7-470e-9452-5468cd6797c0' order by started_at limit 1));
  reset role; perform pg_temp.ok('V07', 'Versioning', 'Migratsiyadan oldingi (versiyasiz) urinish review''i ishlaydi', 'savollar > 0',
    coalesce(jsonb_array_length(rv -> 'questions'), 0)::text, coalesce(jsonb_array_length(rv -> 'questions'), 0) > 0);
end $$;
do $$ declare n int; m int; begin perform pg_temp.logout();
  update public.questions set workflow_status = 'deprecated' where course_id = 'IPC';
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  select count(*) into n from jsonb_array_elements(public.question_meta()) q where q ->> 'course' = 'IPC';
  begin perform public.start_exam('IPC', 'final', null, null, false); m := 1; exception when others then m := 0; end;
  reset role; perform pg_temp.ok('R08', 'Phase 1', 'Deprecated savollar imtihon va meta''dan chiqadi (o''chirilmaydi)', 'meta 0 / imtihon yo''q / savollar bor',
    'meta ' || n || ' / imtihon ' || m || ' / savol ' || (select count(*) from public.questions where course_id = 'IPC'),
    n = 0 and m = 0 and (select count(*) from public.questions where course_id = 'IPC') = 12);
end $$;
do $$ declare n int; begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  select count(*) into n from public.questions; reset role;
  perform pg_temp.ok('R09', 'Phase 1', 'Xodim questions jadvalini (javob kaliti) ko''ra olmaydi', '0', n::text, n = 0);
end $$;
do $$ begin perform pg_temp.logout();
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  update public.profiles set role = 'medical_reviewer' where id = auth.uid();
  reset role; perform pg_temp.ok('R10', 'Phase 1', 'Xodim o''ziga yangi rol (medical_reviewer)', 'DENIED', 'ALLOWED', false);
exception when others then reset role; perform pg_temp.ok('R10', 'Phase 1', 'Xodim o''ziga yangi rol (medical_reviewer)', 'DENIED', 'DENIED: ' || left(sqlerrm, 50), true); end $$;

select id, grp, test, expected, actual, case when pass then 'PASS' else 'FAIL' end as result from t005 order by grp, id;
rollback;
