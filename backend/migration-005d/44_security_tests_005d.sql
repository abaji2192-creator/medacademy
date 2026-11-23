-- STAGING: 005d xavfsizlik va funksional testlari. Hammasi BITTA tranzaksiyada, oxirida ROLLBACK
-- (vaqtinchalik foydalanuvchilar, Org B, "review simulyatsiyasi", urinish, sertifikat, deactivate — bazada QOLMAYDI).
begin;
do $$ begin
  if to_regclass('backup.tables_pre005d_20261123') is null then raise exception 'TO''XTATILDI: staging 005d backup topilmadi (bu skript faqat staging uchun)'; end if;
  if not exists (select 1 from public.schema_migrations where version = '005d') then raise exception '005d qo''llanmagan'; end if;
end $$;
create temp table r5d (id text, grp text, test text, expected text, actual text, pass boolean) on commit drop;
create temp table ctx (k text primary key, v text) on commit drop;
grant all on r5d, ctx to authenticated, anon;
create function pg_temp.login(uid uuid) returns void language plpgsql as $$ begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid::text, true); end $$;
create function pg_temp.logout() returns void language plpgsql as $$ begin
  perform set_config('request.jwt.claims', '', true); perform set_config('request.jwt.claim.sub', '', true); end $$;
create function pg_temp.ok(p_id text, p_grp text, p_test text, p_exp text, p_act text, p_pass boolean) returns void language sql as $$
  insert into r5d values (p_id, p_grp, p_test, p_exp, p_act, coalesce(p_pass, false)) $$;
create function pg_temp.c(p text) returns text language sql as $$ select v from ctx where k = p $$;
grant execute on function pg_temp.ok(text,text,text,text,text,boolean), pg_temp.c(text) to authenticated, anon;

-- ---- Vaqtinchalik foydalanuvchilar (faqat shu tranzaksiyada) ----
insert into ctx values ('SA', (select id::text from public.profiles where role = 'super_admin' and status = 'active' and org_id = '00000000-0000-0000-0000-000000000001' order by created_at limit 1));
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
  ('d0000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t5d-emp@invalid.local','{"full_name":"T5D Xodim"}',now(),now()),
  ('d0000000-0000-0000-0000-0000000000e2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t5d-emp2@invalid.local','{"full_name":"T5D Xodim2"}',now(),now()),
  ('d0000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t5d-hr@invalid.local','{"full_name":"T5D HR"}',now(),now()),
  ('d0000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t5d-edu@invalid.local','{"full_name":"T5D Edu"}',now(),now()),
  ('d0000000-0000-0000-0000-0000000000a3','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t5d-head@invalid.local','{"full_name":"T5D Head"}',now(),now()),
  ('d0000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t5d-orgb@invalid.local','{"full_name":"T5D OrgB"}',now(),now());
update public.profiles set status = 'active', role = 'employee', department = 'Terapiya' where id in ('d0000000-0000-0000-0000-0000000000e1','d0000000-0000-0000-0000-0000000000e2');
update public.profiles set status = 'active', role = 'hr' where id = 'd0000000-0000-0000-0000-0000000000a1';
update public.profiles set status = 'active', role = 'education_manager' where id = 'd0000000-0000-0000-0000-0000000000a2';
update public.profiles set status = 'active', role = 'department_head', department = 'Terapiya' where id = 'd0000000-0000-0000-0000-0000000000a3';
insert into public.employees (org_id, profile_id, employee_code, first_name, department_id)
select '00000000-0000-0000-0000-000000000001', v.pid, v.code, 'T5D', (select id from public.departments where org_id = '00000000-0000-0000-0000-000000000001' and code = 'THERAPY')
from (values ('d0000000-0000-0000-0000-0000000000e1'::uuid,'T5D-E1'),('d0000000-0000-0000-0000-0000000000e2'::uuid,'T5D-E2'),('d0000000-0000-0000-0000-0000000000a1'::uuid,'T5D-A1'),
             ('d0000000-0000-0000-0000-0000000000a2'::uuid,'T5D-A2'),('d0000000-0000-0000-0000-0000000000a3'::uuid,'T5D-A3')) v(pid, code)
on conflict do nothing;
insert into public.organizations (id, name, code) values ('0000000b-0000-0000-0000-0000000005d0', 'T5D Org B', 'T5DORGB');
update public.profiles set org_id = '0000000b-0000-0000-0000-0000000005d0', role = 'super_admin', status = 'active' where id = 'd0000000-0000-0000-0000-0000000000b1';
insert into ctx values ('E1EMP', (select id::text from public.employees where profile_id = 'd0000000-0000-0000-0000-0000000000e1')),
                       ('A1EMP', (select id::text from public.employees where profile_id = 'd0000000-0000-0000-0000-0000000000a1')),
                       ('SAEMP', (select id::text from public.employees where profile_id = (select v::uuid from ctx where k = 'SA')));

-- ===== S. Struktura =====
do $$ declare c int; r int; a int; n text; i text; m text; t int; begin
  select count(*) filter (where confdeltype = 'c'), count(*) filter (where confdeltype = 'r') into c, r from pg_constraint where contype = 'f'
    and conname in ('profiles_id_fkey','docs_owner_fkey','exam_attempts_user_id_fkey','certificates_user_id_fkey','attempt_resets_user_id_fkey','exam_configs_course_id_fkey');
  perform pg_temp.ok('S01', 'FK', 'Target 6 FK: CASCADE / RESTRICT', '0 / 6', c || ' / ' || r, c = 0 and r = 6);
  select count(*) into c from pg_constraint where contype = 'f' and confdeltype = 'c' and connamespace = 'public'::regnamespace;
  perform pg_temp.ok('S02', 'FK', 'public sxemasidagi barcha CASCADE FK', '0', c::text, c = 0);
  select count(*), coalesce(string_agg(proname, ','), '') into a, n from pg_proc where pronamespace = 'public'::regnamespace and prokind = 'f' and has_function_privilege('anon', oid, 'execute');
  perform pg_temp.ok('S03', 'Grants', 'anon EXECUTE funksiyalar', '1 (verify_certificate)', a || ' (' || n || ')', a = 1 and n = 'verify_certificate');
  select coalesce(string_agg(p.proname, ','), '') into i from pg_proc p join backup.function_categories_005d f on f.name = p.proname
   where p.pronamespace = 'public'::regnamespace and f.category = 'internal' and has_function_privilege('authenticated', p.oid, 'execute');
  perform pg_temp.ok('S04', 'Grants', 'authenticated → internal funksiyalar', 'hech biri', coalesce(nullif(i, ''), 'hech biri'), i = '');
  select coalesce(string_agg(p.proname, ','), '') into m from pg_proc p join backup.function_categories_005d f on f.name = p.proname
   where p.pronamespace = 'public'::regnamespace and f.category <> 'internal' and not has_function_privilege('authenticated', p.oid, 'execute');
  perform pg_temp.ok('S05', 'Grants', 'authenticated → ilova RPC + RLS helper''lar saqlangan', 'barchasi', coalesce(nullif(m, ''), 'barchasi'), m = '');
  select coalesce(string_agg(p.proname, ','), '') into m from pg_proc p left join backup.function_categories_005d f on f.name = p.proname
   where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and f.name is null and pg_get_function_result(p.oid) not in ('trigger','event_trigger');
  perform pg_temp.ok('S06', 'Grants', 'Tasniflanmagan (trigger bo''lmagan) funksiyalar', 'yo''q', coalesce(nullif(m, ''), 'yo''q'), m = '');
  select count(*) into t from pg_trigger where tgname in ('certificates_history_guard_trg','exam_attempts_history_guard_trg');
  perform pg_temp.ok('S07', 'History', 'Sertifikat + urinish guard trigger''lari', '2', t::text, t = 2);
end $$;

-- ===== F. RESTRICT =====
do $$ begin
  begin delete from auth.users where id = (select v::uuid from ctx where k = 'SA');
    perform pg_temp.ok('F01', 'RESTRICT', 'Super admin auth user''ini o''chirish (Dashboard/service role ekvivalenti)', 'DENIED', 'ALLOWED', false);
  exception when others then perform pg_temp.ok('F01', 'RESTRICT', 'Super admin auth user''ini o''chirish (Dashboard/service role ekvivalenti)', 'DENIED', 'DENIED: ' || left(sqlerrm, 45), true); end;
  begin delete from auth.users where id = 'd0000000-0000-0000-0000-0000000000e1';
    perform pg_temp.ok('F02', 'RESTRICT', 'Profili bor xodim auth user''ini o''chirish', 'DENIED', 'ALLOWED', false);
  exception when others then perform pg_temp.ok('F02', 'RESTRICT', 'Profili bor xodim auth user''ini o''chirish', 'DENIED', 'DENIED: ' || left(sqlerrm, 45), true); end;
  begin delete from public.courses where id = (select course_id from public.exam_configs order by course_id limit 1);
    perform pg_temp.ok('F03', 'RESTRICT', 'Exam config''i bor kursni o''chirish', 'DENIED', 'ALLOWED', false);
  exception when others then perform pg_temp.ok('F03', 'RESTRICT', 'Exam config''i bor kursni o''chirish', 'DENIED', 'DENIED: ' || left(sqlerrm, 45), true); end;
end $$;

-- ===== G. Funksiya chaqiruvlari: anon va xodim =====
do $$ declare fns text[] := array['public._q_full(null::public.questions)','public._q_refs(''Q001'')','public._grade(null::public.questions, ''{}''::jsonb, 0)',
    'public._q_at(''Q001'', 1)','public.recompute_question_evidence(''Q001'')','public.refresh_evidence_freshness()','public.seed_org_defaults(''00000000-0000-0000-0000-000000000001'')',
    'public._q_exam_eligible(null::public.questions)','public._cert_out(null::public.certificates)'];
  f text; a text; e text; k int := 0; begin
  foreach f in array fns loop k := k + 1;
    perform pg_temp.logout(); begin set local role anon; execute 'select ' || f; a := 'ALLOWED'; exception when others then a := 'DENIED'; end; reset role;
    perform pg_temp.login('d0000000-0000-0000-0000-0000000000e1'); begin set local role authenticated; execute 'select ' || f; e := 'ALLOWED'; exception when others then e := 'DENIED'; end; reset role;
    perform pg_temp.ok('G' || lpad(k::text, 2, '0'), 'Grants', 'anon / xodim → ' || split_part(replace(f, 'public.', ''), '(', 1), 'DENIED / DENIED', a || ' / ' || e, a = 'DENIED' and e = 'DENIED');
  end loop;
end $$;
do $$ declare fns text[] := array['public.start_exam(''ETHICS'',''final'')','public.question_meta()','public.admin_reset_attempts(gen_random_uuid(),''ETHICS'')',
    'public.revoke_certificate(''X'')','public.set_employee_status(gen_random_uuid(),''inactive'',''x'')','public.my_role()','public.has_perm(''question.view'')','public.get_attempt_review(''X'')'];
  f text; a text; k int := 10; begin
  foreach f in array fns loop k := k + 1;
    perform pg_temp.logout(); begin set local role anon; execute 'select ' || f; a := 'ALLOWED'; exception when insufficient_privilege then a := 'DENIED'; when others then a := 'OTHER: ' || left(sqlerrm, 30); end; reset role;
    perform pg_temp.ok('G' || lpad(k::text, 2, '0'), 'Grants', 'anon → ' || split_part(replace(f, 'public.', ''), '(', 1), 'DENIED (permission)', a, a = 'DENIED');
  end loop;
end $$;

-- ===== E. Xodim / admin oqimlari (nazoratli fixture: ETHICS "review'dan o'tgan" — faqat shu tranzaksiyada) =====
do $$ declare n int; begin perform pg_temp.logout();
  perform set_config('medacademy.system_write', 'on', true);
  update public.questions set evidence_status = 'current', last_evidence_reviewed_at = now(), workflow_status = 'published'
   where org_id = '00000000-0000-0000-0000-000000000001' and course_id = 'ETHICS' and published_version is not null;
  perform set_config('medacademy.system_write', 'off', true);
  select count(*) into n from public.questions q where q.course_id = 'ETHICS' and public._q_exam_eligible(q);
  perform pg_temp.ok('E01', 'Fixture', 'Nazoratli fixture: ETHICS yaroqli savollar (ROLLBACK qilinadi)', '> 0', n::text, n > 0);
end $$;
do $$ declare st jsonb; leak int; ans jsonb; sub jsonb; m int; begin perform pg_temp.logout();
  perform pg_temp.login('d0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
  select jsonb_array_length(public.question_meta()) into m;
  st := public.start_exam('ETHICS', 'final', null, null, false); reset role;
  perform pg_temp.ok('E02', 'Employee', 'Xodim question_meta() + start_exam(ETHICS)', 'OK', 'meta ' || m || ', ' || jsonb_array_length(st -> 'qids') || ' savol', jsonb_array_length(st -> 'qids') > 0);
  select count(*) into leak from jsonb_array_elements(st -> 'questions') x where x ? 'a' or x ? 'e' or x ? 'refs' or x ? 'ev';
  perform pg_temp.ok('E03', 'Leakage', 'start_exam payload: javob kaliti / izoh / manba / evidence', '0', leak::text, leak = 0);
  select jsonb_object_agg(q.id, case q.type when 'match' then (select jsonb_object_agg((t.i - 1)::text, t.x) from jsonb_array_elements(q.answer) with ordinality t(x, i))
                                       when 'short' then q.answer -> 0 else q.answer end) into ans
    from public.questions q where q.id in (select jsonb_array_elements_text(st -> 'qids'));
  perform pg_temp.login('d0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
  perform public.save_answers(st ->> 'id', ans);
  sub := public.submit_exam(st ->> 'id', ans); reset role;
  insert into ctx values ('ATT', st ->> 'id'), ('CERT', sub -> 'certificate' ->> 'id'), ('Q1', st -> 'qids' ->> 0);
  perform pg_temp.ok('E04', 'Employee', 'save_answers + submit_exam → PASSED + sertifikat', 'PASSED + sertifikat', (sub -> 'attempt' ->> 'score') || '% ' || coalesce(sub -> 'certificate' ->> 'id', 'sertifikatsiz'),
    (sub -> 'attempt' ->> 'passed')::boolean and sub -> 'certificate' is not null);
end $$;
do $$ declare rv jsonb; n1 int; n2 int; n3 int; n4 int; r text; begin perform pg_temp.logout();
  perform pg_temp.login('d0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
  rv := public.get_attempt_review(pg_temp.c('ATT'));
  select count(*) into n1 from public.questions; select count(*) into n2 from public.question_versions;
  select count(*) into n3 from public.question_reviews; select count(*) into n4 from public.question_evidence; reset role;
  perform pg_temp.ok('E05', 'Employee', 'O''z urinishi review (yakunlangandan keyin)', 'savollar > 0', jsonb_array_length(rv -> 'questions')::text, jsonb_array_length(rv -> 'questions') > 0);
  perform pg_temp.ok('E06', 'Leakage', 'Xodim → questions / versions / reviews / question_evidence', '0/0/0/0', n1 || '/' || n2 || '/' || n3 || '/' || n4, n1 + n2 + n3 + n4 = 0);
  perform pg_temp.login('d0000000-0000-0000-0000-0000000000e2'); set local role authenticated;
  begin perform public.get_attempt_review(pg_temp.c('ATT')); r := 'ALLOWED'; exception when others then r := 'DENIED'; end; reset role;
  perform pg_temp.ok('E07', 'Employee', 'Boshqa xodim urinish review''i', 'DENIED', r, r = 'DENIED');
end $$;
do $$ declare v jsonb; begin perform pg_temp.logout(); set local role anon;
  v := public.verify_certificate(pg_temp.c('CERT')); reset role;
  perform pg_temp.ok('E08', 'Public', 'anon → verify_certificate (QR)', 'Amalda, minimal maydonlar', (v ->> 'status') || ', ' || (select string_agg(k, ',' order by k) from jsonb_object_keys(v) k),
    v ->> 'status' = 'Amalda' and not (v ? 'empId') and not (v ? 'score') and not (v ? 'email'));
end $$;
do $$ declare n int; r boolean; rv jsonb; begin perform pg_temp.logout();
  perform pg_temp.login('d0000000-0000-0000-0000-0000000000a2'); set local role authenticated;
  select count(*) into n from public.questions; r := public.admin_reset_attempts('d0000000-0000-0000-0000-0000000000e1', 'ETHICS'); rv := public.get_attempt_review(pg_temp.c('ATT')); reset role;
  perform pg_temp.ok('E09', 'Admin', 'Education manager: savollar banki + reset + xodim review', '131+ / true / OK', n || ' / ' || r || ' / ' || case when rv is not null then 'OK' else '-' end, n >= 131 and r and rv is not null);
end $$;
do $$ declare qa int; aa int; ca int; ea int; r text; x boolean; begin perform pg_temp.logout();
  perform pg_temp.login('d0000000-0000-0000-0000-0000000000b1'); set local role authenticated;
  select count(*) into qa from public.questions where org_id = '00000000-0000-0000-0000-000000000001';
  select count(*) into aa from public.exam_attempts where org_id = '00000000-0000-0000-0000-000000000001';
  select count(*) into ca from public.certificates where org_id = '00000000-0000-0000-0000-000000000001';
  select count(*) into ea from public.employees where org_id = '00000000-0000-0000-0000-000000000001';
  begin perform public.get_attempt_review(pg_temp.c('ATT')); r := 'ALLOWED'; exception when others then r := 'DENIED'; end;
  x := public.revoke_certificate(pg_temp.c('CERT')); reset role;
  perform pg_temp.ok('E10', 'Cross-org', 'Org B super admin → Org A savol/urinish/sertifikat/xodim', '0/0/0/0', qa || '/' || aa || '/' || ca || '/' || ea, qa + aa + ca + ea = 0);
  perform pg_temp.ok('E11', 'Cross-org', 'Org B → Org A urinish review / sertifikat revoke', 'DENIED / false', r || ' / ' || x, r = 'DENIED' and not x);
end $$;

-- ===== H. Tarixiy yaxlitlik =====
do $$ declare b jsonb; a jsonb; rv jsonb; r1 text; r2 text; r3 text; r4 text; r5 text; begin perform pg_temp.logout();
  begin update public.certificates set name = 'Boshqa Ism' where id = pg_temp.c('CERT'); r1 := 'ALLOWED'; exception when others then r1 := 'DENIED'; end;
  begin update public.certificates set score = 1 where id = pg_temp.c('CERT'); r2 := 'ALLOWED'; exception when others then r2 := 'DENIED'; end;
  begin delete from public.certificates where id = pg_temp.c('CERT'); r3 := 'ALLOWED'; exception when others then r3 := 'DENIED'; end;
  begin update public.exam_attempts set score = 0 where id = pg_temp.c('ATT'); r4 := 'ALLOWED'; exception when others then r4 := 'DENIED'; end;
  begin delete from public.exam_attempts where id = pg_temp.c('ATT'); r5 := 'ALLOWED'; exception when others then r5 := 'DENIED'; end;
  perform pg_temp.ok('H01', 'Certificate', 'Sertifikat ism / ball o''zgartirish / o''chirish (hatto SQL Editor)', 'DENIED x3', r1 || ',' || r2 || ',' || r3, r1 = 'DENIED' and r2 = 'DENIED' and r3 = 'DENIED');
  perform pg_temp.ok('H02', 'Attempt', 'Yakunlangan urinish balini o''zgartirish / o''chirish', 'DENIED x2', r4 || ',' || r5, r4 = 'DENIED' and r5 = 'DENIED');
  select to_jsonb(x) into b from public.exam_attempts x where id = pg_temp.c('ATT');
  perform set_config('medacademy.system_write', 'on', true);
  update public.questions set stem = stem || ' (v2 test)' where id = pg_temp.c('Q1');
  perform set_config('medacademy.system_write', 'off', true);
  select to_jsonb(x) into a from public.exam_attempts x where id = pg_temp.c('ATT');
  perform pg_temp.login('d0000000-0000-0000-0000-0000000000e1'); set local role authenticated; rv := public.get_attempt_review(pg_temp.c('ATT')); reset role;
  perform pg_temp.ok('H03', 'Historical', 'Savol yangilangandan keyin: urinish yozuvi aynan, review v1 matni', 'aynan / v1',
    case when a = b then 'aynan' else 'FARQ' end || ' / ' || case when (select bool_or(x ->> 'q' like '%(v2 test)%') from jsonb_array_elements(rv -> 'questions') x) then 'v2' else 'v1' end,
    a = b and not coalesce((select bool_or(x ->> 'q' like '%(v2 test)%') from jsonb_array_elements(rv -> 'questions') x), false));
end $$;

-- ===== L. Lifecycle: Deactivate > Delete =====
do $$ declare r text; begin perform pg_temp.logout();
  perform pg_temp.login('d0000000-0000-0000-0000-0000000000e2'); set local role authenticated;
  begin perform public.set_employee_status(pg_temp.c('E1EMP')::uuid, 'inactive', 'x'); r := 'ALLOWED'; exception when others then r := 'DENIED'; end; reset role;
  perform pg_temp.ok('L01', 'Lifecycle', 'Xodim → boshqa xodimni faolsizlantirish', 'DENIED', r, r = 'DENIED');
  perform pg_temp.login('d0000000-0000-0000-0000-0000000000a3'); set local role authenticated;
  begin perform public.set_employee_status(pg_temp.c('E1EMP')::uuid, 'inactive', 'x'); r := 'ALLOWED'; exception when others then r := 'DENIED'; end; reset role;
  perform pg_temp.ok('L02', 'Lifecycle', 'Department head → faolsizlantirish', 'DENIED', r, r = 'DENIED');
  perform pg_temp.login('d0000000-0000-0000-0000-0000000000a1'); set local role authenticated;
  begin perform public.set_employee_status(pg_temp.c('E1EMP')::uuid, 'inactive', ''); r := 'ALLOWED'; exception when others then r := 'DENIED'; end; reset role;
  perform pg_temp.ok('L03', 'Lifecycle', 'Sababsiz faolsizlantirish', 'DENIED', r, r = 'DENIED');
  perform pg_temp.login('d0000000-0000-0000-0000-0000000000a1'); set local role authenticated;
  begin perform public.set_employee_status(pg_temp.c('A1EMP')::uuid, 'inactive', 'x'); r := 'ALLOWED'; exception when others then r := 'DENIED'; end; reset role;
  perform pg_temp.ok('L04', 'Lifecycle', 'O''z akkauntini faolsizlantirish', 'DENIED', r, r = 'DENIED');
  if pg_temp.c('SAEMP') is not null then
    perform pg_temp.login('d0000000-0000-0000-0000-0000000000a1'); set local role authenticated;
    begin perform public.set_employee_status(pg_temp.c('SAEMP')::uuid, 'inactive', 'x'); r := 'ALLOWED'; exception when others then r := 'DENIED'; end; reset role;
  else r := 'DENIED (SA employee yozuvi yo''q)'; end if;
  perform pg_temp.ok('L05', 'Lifecycle', 'HR → Super Admin''ni faolsizlantirish', 'DENIED', r, r like 'DENIED%');
  perform pg_temp.login('d0000000-0000-0000-0000-0000000000b1'); set local role authenticated;
  begin perform public.set_employee_status(pg_temp.c('E1EMP')::uuid, 'deactivated', 'x'); r := 'ALLOWED'; exception when others then r := 'DENIED'; end; reset role;
  perform pg_temp.ok('L06', 'Lifecycle', 'Org B → Org A xodimini faolsizlantirish', 'DENIED', r, r = 'DENIED');
end $$;
do $$ declare res jsonb; ps text; es text; au int; mr text; ex text; cb jsonb; ca jsonb; v jsonb; n int; begin perform pg_temp.logout();
  select to_jsonb(c) into cb from public.certificates c where id = pg_temp.c('CERT');
  perform pg_temp.login('d0000000-0000-0000-0000-0000000000a1'); set local role authenticated;
  res := public.set_employee_status(pg_temp.c('E1EMP')::uuid, 'deactivated', 'Ishdan ketdi (staging test)'); reset role;
  select p.status, e.employment_status into ps, es from public.profiles p join public.employees e on e.profile_id = p.id where p.id = 'd0000000-0000-0000-0000-0000000000e1';
  perform pg_temp.ok('L07', 'Lifecycle', 'HR → deactivate (sabab bilan): profil / employee', 'deactivated / inactive', ps || ' / ' || es, ps = 'deactivated' and es = 'inactive');
  select count(*) into au from public.audit_logs where entity_id = pg_temp.c('E1EMP') and action in ('employee.status_deactivated','employee.deactivated')
    and actor_id = 'd0000000-0000-0000-0000-0000000000a1';
  perform pg_temp.ok('L08', 'Audit', 'Server-side audit: status_deactivated (sabab) + employee.deactivated', '2', au::text, au = 2);
  perform pg_temp.login('d0000000-0000-0000-0000-0000000000e1'); set local role authenticated;
  mr := coalesce(public.my_role(), 'null');
  begin perform public.start_exam('ETHICS', 'final', null, null, false); ex := 'ALLOWED'; exception when others then ex := 'DENIED'; end;
  select count(*) into n from public.certificates; reset role;
  perform pg_temp.ok('L09', 'Lifecycle', 'Deactivated: my_role / start_exam / o''z sertifikati', 'null / DENIED / 1', mr || ' / ' || ex || ' / ' || n, mr = 'null' and ex = 'DENIED' and n = 1);
  select to_jsonb(c) into ca from public.certificates c where id = pg_temp.c('CERT');
  update public.profiles set full_name = 'Yangi Ism' where id = 'd0000000-0000-0000-0000-0000000000e1';
  perform pg_temp.logout(); set local role anon; v := public.verify_certificate(pg_temp.c('CERT')); reset role;
  perform pg_temp.ok('C01', 'Certificate', 'Deactivate + profil ismi o''zgargandan keyin: sertifikat aynan, QR: ism / holat', 'aynan / ' || (cb ->> 'name') || ' / Amalda',
    case when ca = cb then 'aynan' else 'FARQ' end || ' / ' || (v ->> 'name') || ' / ' || (v ->> 'status'), ca = cb and v ->> 'name' = cb ->> 'name' and v ->> 'status' = 'Amalda');
end $$;
do $$ declare r text; x1 boolean; x2 boolean; a1 jsonb; a2 jsonb; begin perform pg_temp.logout();
  perform pg_temp.login('d0000000-0000-0000-0000-0000000000a2'); set local role authenticated; x1 := public.revoke_certificate(pg_temp.c('CERT')); reset role;
  select jsonb_build_object('by', revoked_by, 'at', revoked_at) into a1 from public.certificates where id = pg_temp.c('CERT');
  perform pg_temp.login(pg_temp.c('SA')::uuid); set local role authenticated; x2 := public.revoke_certificate(pg_temp.c('CERT')); reset role;
  select jsonb_build_object('by', revoked_by, 'at', revoked_at) into a2 from public.certificates where id = pg_temp.c('CERT');
  begin update public.certificates set revoked = false where id = pg_temp.c('CERT'); r := 'ALLOWED'; exception when others then r := 'DENIED'; end;
  perform pg_temp.ok('C02', 'Certificate', 'Revoke ishlaydi; qayta revoke birinchi yozuvni saqlaydi; un-revoke', 'true / saqlandi / DENIED',
    x1 || ' / ' || case when a1 = a2 then 'saqlandi' else 'O''ZGARDI' end || ' / ' || r, x1 and a1 = a2 and r = 'DENIED');
  perform pg_temp.login('d0000000-0000-0000-0000-0000000000a1'); set local role authenticated;
  begin perform public.set_employee_status(pg_temp.c('E1EMP')::uuid, 'active', null); r := 'ALLOWED'; exception when others then r := 'DENIED'; end; reset role;
  perform pg_temp.ok('L10', 'Lifecycle', 'HR → deactivated akkauntni qayta faollashtirish (faqat Super Admin)', 'DENIED', r, r = 'DENIED');
  perform pg_temp.login(pg_temp.c('SA')::uuid); set local role authenticated;
  begin perform public.set_employee_status(pg_temp.c('E1EMP')::uuid, 'active', null); r := 'OK'; exception when others then r := 'XATO: ' || left(sqlerrm, 40); end; reset role;
  perform pg_temp.ok('L11', 'Lifecycle', 'Super Admin → qayta faollashtirish', 'OK', r, r = 'OK');
end $$;

select line from (
  select 0 ord, 'SUMMARY total ' || count(*) || ' / FAIL ' || count(*) filter (where not pass) as line from r5d
  union all select 1, id || ' ' || case when pass then 'PASS' else 'FAIL' end || ' [' || grp || '] ' || test || ' :: ' || actual from r5d) x order by ord, line;
rollback;
