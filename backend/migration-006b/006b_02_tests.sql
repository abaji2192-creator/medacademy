-- MedAcademy · 006b kurs DELETE hardening test to'plami (lokal PGlite va staging uchun bir xil fayl).
-- Mavjud test akkauntlari (staging) bilan; yangi auth akkaunt yaratilmaydi. Hammasi BITTA tranzaksiyada, oxirida ROLLBACK.
-- Har bir foydalanuvchi so'rovi haqiqiy RLS / trigger / RPC orqali JWT claim'lari bilan bajariladi.
begin;
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
