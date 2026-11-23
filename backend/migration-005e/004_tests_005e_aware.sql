-- 004 testlari (local + staging). Hammasi bitta tranzaksiyada, oxirida ROLLBACK — iz qoldirmaydi.
begin;
create temp table t004 (id text, test text, expected text, actual text, pass boolean) on commit drop;
grant all on t004 to authenticated, anon;

create function pg_temp.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid::text, true);
end $$;
create function pg_temp.ok(p_id text, p_test text, p_exp text, p_act text, p_pass boolean) returns void language sql as $$
  insert into t004 values (p_id, p_test, p_exp, p_act, p_pass) $$;
grant execute on function pg_temp.ok(text,text,text,text,boolean) to authenticated, anon;

-- TEST (005c dan keyin): Phase 1 oqimlarini sinash uchun Org A savollarini "review'dan o'tgan" deb simulyatsiya qilish.
-- Faqat shu tranzaksiyada, oxirida ROLLBACK. 005c o'rnatilmagan bazada hech narsa qilmaydi.
do $$ begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'questions' and column_name = 'review_reason') then
    perform set_config('request.jwt.claims', '', true); perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('medacademy.system_write', 'on', true);
    execute $q$update public.questions set evidence_status = 'current', last_evidence_reviewed_at = now(), workflow_status = 'published'
              where org_id = '00000000-0000-0000-0000-000000000001' and published_version is not null$q$;
    -- 005e o'rnatilgan bo'lsa: simulyatsiya tibbiy tasdiqni ham o'z ichiga oladi (Super Admin, nashr qilingan versiya) — faqat shu tranzaksiya
    if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'question_reviews' and column_name = 'reviewer_role_at_creation') then
      execute $q$insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision, internal_notes)
                select q.org_id, q.id, q.published_version, 'medical', '262a128c-6fb7-470e-9452-5468cd6797c0', 'approved', 'TEST simulyatsiya (005e)'
                  from public.questions q where q.org_id = '00000000-0000-0000-0000-000000000001' and q.published_version is not null and public._q_is_clinical(q)$q$;
    end if;
    perform set_config('medacademy.system_write', 'off', true);
  end if;
end $$;

-- ===================== A. Cross-organization =====================
do $$ declare n int; m int; begin
  perform pg_temp.login('262a128c-6fb7-470e-9452-5468cd6797c0'); set local role authenticated;
  select (select count(*) from public.branches where org_id <> public.my_org()) + (select count(*) from public.departments where org_id <> public.my_org())
       + (select count(*) from public.positions where org_id <> public.my_org()) + (select count(*) from public.specialties where org_id <> public.my_org())
       + (select count(*) from public.employees where org_id <> public.my_org()) + (select count(*) from public.organizations where id <> public.my_org())
       + (select count(*) from public.profiles where org_id <> public.my_org()) + (select count(*) from public.role_permissions where org_id <> public.my_org())
       + (select count(*) from public.audit_logs where org_id <> public.my_org()) into n;
  select count(*) into m from public.departments;
  reset role;
  perform pg_temp.ok('A1', 'Org A Super Admin → Org B (9 jadval) SELECT', '0 qator', n::text, n = 0 and m > 0);
end $$;
do $$ begin
  perform pg_temp.login('262a128c-6fb7-470e-9452-5468cd6797c0'); set local role authenticated;
  insert into public.departments (org_id, name, code) values ('0000000b-0000-0000-0000-00000000000b', 'Hack', 'HACK');
  reset role; perform pg_temp.ok('A2', 'Org A Super Admin → Org B department INSERT', 'DENIED', 'ALLOWED', false);
exception when others then perform pg_temp.ok('A2', 'Org A Super Admin → Org B department INSERT', 'DENIED', 'DENIED: ' || left(sqlerrm, 60), true); end $$;
do $$ declare n int; begin
  perform pg_temp.login('262a128c-6fb7-470e-9452-5468cd6797c0'); set local role authenticated;
  update public.departments set name = 'Hacked' where org_id = '0000000b-0000-0000-0000-00000000000b';
  get diagnostics n = row_count; reset role;
  perform pg_temp.ok('A3', 'Org A Super Admin → Org B department UPDATE', '0 qator', n::text, n = 0);
end $$;
do $$ declare n int; begin
  perform pg_temp.login('262a128c-6fb7-470e-9452-5468cd6797c0'); set local role authenticated;
  delete from public.role_permissions where org_id = '0000000b-0000-0000-0000-00000000000b';
  get diagnostics n = row_count; reset role;
  perform pg_temp.ok('A4', 'Org A Super Admin → Org B role_permissions DELETE', '0 qator', n::text, n = 0);
exception when others then perform pg_temp.ok('A4', 'Org A Super Admin → Org B role_permissions DELETE', '0 qator', 'DENIED', true); end $$;
do $$ declare n int; begin
  perform pg_temp.login('b0000000-0000-0000-0000-000000000001'); set local role authenticated;
  select (select count(*) from public.employees) - (select count(*) from public.employees where org_id = public.my_org())
       + (select count(*) from public.profiles where org_id <> public.my_org()) + (select count(*) from public.docs where org_id <> public.my_org())
       + (select count(*) from public.exam_attempts where org_id <> public.my_org()) + (select count(*) from public.certificates where org_id <> public.my_org())
       + (select count(*) from public.questions where org_id <> public.my_org()) + (select count(*) from public.courses where org_id <> public.my_org())
       + (select count(*) from public.exam_configs where org_id <> public.my_org()) into n;
  reset role;
  perform pg_temp.ok('A5', 'Org B Admin → Org A (employees, profiles, docs, attempts, certs, questions, courses, configs)', '0 qator', n::text, n = 0);
end $$;
do $$ declare dep_org uuid; begin
  perform pg_temp.login('262a128c-6fb7-470e-9452-5468cd6797c0'); set local role authenticated;
  update public.employees set department_id = (select id from public.departments d where d.code = 'CARDIO' and d.org_id = '0000000b-0000-0000-0000-00000000000b')
   where profile_id = 'a0000000-0000-0000-0000-000000000002';
  reset role;
  select d.org_id into dep_org from public.employees e left join public.departments d on d.id = e.department_id where e.profile_id = 'a0000000-0000-0000-0000-000000000002';
  perform pg_temp.ok('A6', 'Xodimni boshqa tashkilot bo''limiga bog''lash (API)', 'DENIED', coalesce(dep_org::text, 'Org B bo''limi ko''rinmadi'), dep_org is distinct from '0000000b-0000-0000-0000-00000000000b');
exception when others then perform pg_temp.ok('A6', 'Xodimni boshqa tashkilot bo''limiga bog''lash (API)', 'DENIED', 'DENIED: ' || left(sqlerrm, 60), true); end $$;
do $$ begin
  -- to'g'ridan-to'g'ri ID bilan urinish (RLS'dan o'tib ketgan holat uchun trigger himoyasi)
  update public.employees set department_id = (select id from public.departments d where d.code = 'CARDIO' and d.org_id = '0000000b-0000-0000-0000-00000000000b')
   where profile_id = 'a0000000-0000-0000-0000-000000000002';
  perform pg_temp.ok('A6b', 'Cross-org bog''lanish (DB trigger, RLS''siz)', 'DENIED', 'ALLOWED', false);
exception when others then perform pg_temp.ok('A6b', 'Cross-org bog''lanish (DB trigger, RLS''siz)', 'DENIED', 'DENIED: ' || left(sqlerrm, 60), true); end $$;
do $$ begin
  perform pg_temp.login('b0000000-0000-0000-0000-000000000001'); set local role authenticated;
  perform public.start_exam('ETHICS', 'final', null, null, false);
  reset role; perform pg_temp.ok('A7', 'Org B Admin → Org A kursi bo''yicha imtihon (RPC)', 'DENIED', 'ALLOWED', false);
exception when others then perform pg_temp.ok('A7', 'Org B Admin → Org A kursi bo''yicha imtihon (RPC)', 'DENIED', 'DENIED: ' || left(sqlerrm, 60), true); end $$;
do $$ declare n int; begin
  perform pg_temp.login('b0000000-0000-0000-0000-000000000001'); set local role authenticated;
  select count(*) into n from jsonb_array_elements(public.question_meta()) m where m ->> 'course' in (select id from public.courses where org_id = '00000000-0000-0000-0000-000000000001'); reset role;
  perform pg_temp.ok('A8', 'Org B Admin → Org A savollar meta (RPC, Org A kurslari)', '0', n::text, n = 0);
end $$;
do $$ begin
  perform pg_temp.login('262a128c-6fb7-470e-9452-5468cd6797c0'); set local role authenticated;
  perform public.admin_reset_attempts('b0000000-0000-0000-0000-000000000002', 'ETHICS');
  reset role; perform pg_temp.ok('A9', 'Org A Admin → Org B xodimi urinishlarini tiklash (RPC)', 'DENIED', 'ALLOWED', false);
exception when others then perform pg_temp.ok('A9', 'Org A Admin → Org B xodimi urinishlarini tiklash (RPC)', 'DENIED', 'DENIED: ' || left(sqlerrm, 60), true); end $$;

-- ===================== B. Employee → boshqa xodim =====================
do $$ declare n int; u int; begin
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  select (select count(*) from public.employees where profile_id is distinct from auth.uid()) + (select count(*) from public.profiles where id <> auth.uid())
       + (select count(*) from public.docs where owner is distinct from auth.uid() and collection not in ('settings','questions_custom','exam_overrides'))
       + (select count(*) from public.exam_attempts where user_id <> auth.uid()) + (select count(*) from public.certificates where user_id <> auth.uid()) into n;
  update public.employees set first_name = 'X' where profile_id <> auth.uid(); get diagnostics u = row_count;
  reset role;
  perform pg_temp.ok('B1', 'Employee → boshqa xodimlar (employees, profiles, docs, attempts, certs) SELECT', '0 qator', n::text, n = 0);
  perform pg_temp.ok('B2', 'Employee → boshqa xodim UPDATE', '0 qator', u::text, u = 0);
end $$;

-- ===================== C. Department Head =====================
do $$ declare own int; other int; depts int; ownd uuid; prof int; begin
  perform pg_temp.login('a0000000-0000-0000-0000-000000000005'); set local role authenticated;
  ownd := public.my_department_id();
  select count(*) into own from public.employees where department_id = ownd;
  select count(*) into other from public.employees where department_id is distinct from ownd;
  select count(*) into depts from public.departments where id <> ownd;
  select count(*) into prof from public.profiles where department is distinct from 'Kardiologiya';
  reset role;
  perform pg_temp.ok('C1', 'Dept Head → o''z bo''limi xodimlari', '>= 2', own::text, own >= 2);
  perform pg_temp.ok('C2', 'Dept Head → boshqa bo''lim xodimlari', '0', other::text, other = 0);
  perform pg_temp.ok('C3', 'Dept Head → boshqa bo''limlar', '0', depts::text, depts = 0);
  perform pg_temp.ok('C4', 'Dept Head → boshqa bo''lim profillari', '0', prof::text, prof = 0);
end $$;
do $$ declare n int; begin
  perform pg_temp.login('a0000000-0000-0000-0000-000000000005'); set local role authenticated;
  update public.employees set first_name = 'X' where profile_id = 'a0000000-0000-0000-0000-000000000006'; get diagnostics n = row_count;
  reset role; perform pg_temp.ok('C5', 'Dept Head → o''z bo''limi xodimini tahrirlash (employee.edit yo''q)', '0 qator', n::text, n = 0);
end $$;

-- ===================== D. Instructor =====================
do $$ declare n int; e int; begin
  perform pg_temp.login('a0000000-0000-0000-0000-000000000004'); set local role authenticated;
  select (select count(*) from public.employees where org_id <> public.my_org()) + (select count(*) from public.departments where org_id <> public.my_org())
       + (select count(*) from public.questions where org_id <> public.my_org()) into n;
  select count(*) into e from public.employees where profile_id <> auth.uid();
  reset role;
  perform pg_temp.ok('D1', 'Instructor → boshqa tashkilot (employees, departments, questions)', '0', n::text, n = 0);
  perform pg_temp.ok('D2', 'Instructor → xodimlar ro''yxati (employee.view yo''q)', '0', e::text, e = 0);
end $$;
do $$ begin
  perform pg_temp.login('a0000000-0000-0000-0000-000000000004'); set local role authenticated;
  insert into public.departments (org_id, name, code) values (public.my_org(), 'Inst dept', 'INSTX');
  reset role; perform pg_temp.ok('D3', 'Instructor → bo''lim yaratish', 'DENIED', 'ALLOWED', false);
exception when others then perform pg_temp.ok('D3', 'Instructor → bo''lim yaratish', 'DENIED', 'DENIED: ' || left(sqlerrm, 60), true); end $$;

-- ===================== E. Super Admin (o'z tashkiloti) =====================
do $$ declare n int; tot int; d uuid; a int; begin
  select count(*) into tot from public.employees where org_id = '00000000-0000-0000-0000-000000000001';
  perform pg_temp.login('262a128c-6fb7-470e-9452-5468cd6797c0'); set local role authenticated;
  select count(*) into n from public.employees;
  insert into public.departments (org_id, branch_id, name, code) values (public.my_org(), (select id from public.branches where code='MAIN' and org_id = public.my_org()), 'Test LOR', 'ENT_TEST') returning id into d;
  update public.departments set description = 'Test' where id = d;
  select count(*) into a from public.audit_logs where entity = 'department' and entity_id = d::text;
  reset role;
  perform pg_temp.ok('E1', 'Super Admin → o''z tashkiloti barcha xodimlari', tot::text, n::text, n = tot and n > 0);
  perform pg_temp.ok('E2', 'Super Admin → bo''lim yaratish/tahrirlash + audit (2 yozuv)', 'ALLOWED, audit=2', 'audit=' || a, a = 2);
end $$;

-- ===================== F. Employee → o'z ma'lumoti =====================
do $$ declare e int; p int; d int; begin
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  select count(*) into e from public.employees where profile_id = auth.uid();
  select count(*) into p from public.profiles where id = auth.uid();
  select count(*) into d from public.departments;
  reset role;
  perform pg_temp.ok('F1', 'Employee → o''z employee yozuvi va profili', '1 + 1', e || ' + ' || p, e = 1 and p = 1);
  perform pg_temp.ok('F2', 'Employee → faqat o''z bo''limi', '1', d::text, d = 1);
end $$;

-- ===================== G. Rolni oshirish =====================
do $$ begin
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  update public.profiles set role = 'super_admin' where id = auth.uid();
  reset role; perform pg_temp.ok('G1', 'Employee → o''ziga super_admin roli', 'DENIED', 'ALLOWED', false);
exception when others then perform pg_temp.ok('G1', 'Employee → o''ziga super_admin roli', 'DENIED', 'DENIED: ' || left(sqlerrm, 60), true); end $$;
do $$ begin
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  insert into public.role_permissions (org_id, role, permission_key) values (public.my_org(), 'employee', 'settings.manage');
  reset role; perform pg_temp.ok('G2', 'Employee → o''z roliga ruxsat qo''shish', 'DENIED', 'ALLOWED', false);
exception when others then perform pg_temp.ok('G2', 'Employee → o''z roliga ruxsat qo''shish', 'DENIED', 'DENIED: ' || left(sqlerrm, 60), true); end $$;
do $$ begin
  perform pg_temp.login('a0000000-0000-0000-0000-000000000002'); set local role authenticated;
  update public.profiles set role = 'super_admin' where id = 'a0000000-0000-0000-0000-000000000006';
  reset role; perform pg_temp.ok('G3', 'HR → kimgadir super_admin roli', 'DENIED', 'ALLOWED', false);
exception when others then perform pg_temp.ok('G3', 'HR → kimgadir super_admin roli', 'DENIED', 'DENIED: ' || left(sqlerrm, 60), true); end $$;
do $$ begin
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  update public.profiles set org_id = '0000000b-0000-0000-0000-00000000000b' where id = auth.uid();
  reset role; perform pg_temp.ok('G4', 'Employee → o''zini boshqa tashkilotga o''tkazish', 'DENIED', 'ALLOWED', false);
exception when others then perform pg_temp.ok('G4', 'Employee → o''zini boshqa tashkilotga o''tkazish', 'DENIED', 'DENIED: ' || left(sqlerrm, 60), true); end $$;

-- ===================== H. Anonim foydalanuvchi =====================
do $$ declare t text; denied int := 0; total int := 0; begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true); perform set_config('request.jwt.claim.sub', '', true);
  foreach t in array array['organizations','branches','departments','positions','specialties','employees','permissions','role_permissions','audit_logs','profiles','docs','questions','exam_attempts','certificates','schema_migrations'] loop
    total := total + 1;
    begin
      set local role anon;
      execute format('select count(*) from public.%I', t);
      reset role;
    exception when others then denied := denied + 1; reset role;
    end;
  end loop;
  perform pg_temp.ok('H1', 'Anonim → 15 ta jadval', '15/15 DENIED', denied || '/' || total || ' DENIED', denied = total);
end $$;

-- ===================== I. Klient orqali chetlab o'tish =====================
do $$ begin
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  insert into public.audit_logs (org_id, action, entity) values (public.my_org(), 'fake', 'fake');
  reset role; perform pg_temp.ok('I1', 'Employee → soxta audit yozuvi', 'DENIED', 'ALLOWED', false);
exception when others then perform pg_temp.ok('I1', 'Employee → soxta audit yozuvi', 'DENIED', 'DENIED: ' || left(sqlerrm, 60), true); end $$;
do $$ begin
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  insert into public.employees (org_id, employee_code) values (public.my_org(), 'FAKE-1');
  reset role; perform pg_temp.ok('I2', 'Employee → xodim yaratish', 'DENIED', 'ALLOWED', false);
exception when others then perform pg_temp.ok('I2', 'Employee → xodim yaratish', 'DENIED', 'DENIED: ' || left(sqlerrm, 60), true); end $$;
do $$ begin
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  perform public.seed_org_defaults(public.my_org());
  reset role; perform pg_temp.ok('I3', 'Employee → ichki funksiyani chaqirish (seed_org_defaults)', 'DENIED', 'ALLOWED', false);
exception when others then perform pg_temp.ok('I3', 'Employee → ichki funksiyani chaqirish (seed_org_defaults)', 'DENIED', 'DENIED: ' || left(sqlerrm, 60), true); end $$;
do $$ begin
  -- HR'dan employee.deactivate olib qo'yiladi → faolsizlantirish bloklanadi, oddiy tahrir esa ishlaydi
  delete from public.role_permissions where org_id = '00000000-0000-0000-0000-000000000001' and role = 'hr' and permission_key = 'employee.deactivate';
  perform pg_temp.login('a0000000-0000-0000-0000-000000000002'); set local role authenticated;
  update public.employees set employment_status = 'inactive' where profile_id = 'a0000000-0000-0000-0000-000000000007';
  reset role; perform pg_temp.ok('I4', 'employee.deactivate ruxsatisiz faolsizlantirish', 'DENIED', 'ALLOWED', false);
exception when others then perform pg_temp.ok('I4', 'employee.deactivate ruxsatisiz faolsizlantirish', 'DENIED', 'DENIED: ' || left(sqlerrm, 60), true); end $$;
do $$ declare n int; a int; begin
  perform pg_temp.login('a0000000-0000-0000-0000-000000000002'); set local role authenticated;
  update public.employees set employment_status = 'inactive' where profile_id = 'a0000000-0000-0000-0000-000000000007'; get diagnostics n = row_count;
  reset role;
  select count(*) into a from public.audit_logs where action = 'employee.deactivated' and old_value ->> 'employment_status' = 'active' and new_value ->> 'employment_status' = 'inactive';
  perform pg_temp.ok('I5', 'HR (ruxsat bilan) faolsizlantirish + audit old/new', '1 qator, audit=1', n || ' qator, audit=' || a, n = 1 and a = 1);
end $$;
do $$ declare a int; begin
  perform pg_temp.login('262a128c-6fb7-470e-9452-5468cd6797c0'); set local role authenticated;
  insert into public.role_permissions (org_id, role, permission_key) values (public.my_org(), 'instructor', 'report.view');
  delete from public.role_permissions where org_id = public.my_org() and role = 'instructor' and permission_key = 'report.view';
  reset role;
  select count(*) into a from public.audit_logs where action in ('permission.granted','permission.revoked') and entity_id = 'instructor:report.view';
  perform pg_temp.ok('I6', 'Ruxsat berish/olish audit qilinadi', 'audit=2', 'audit=' || a, a = 2);
end $$;

-- ===================== FK / UNIQUE =====================
do $$ begin
  insert into public.departments (org_id, name, code) values ('00000000-0000-0000-0000-000000000001', 'Dup', 'CARDIO');
  perform pg_temp.ok('U1', 'Bir tashkilotda bir xil department.code', 'DENIED', 'ALLOWED', false);
exception when unique_violation then perform pg_temp.ok('U1', 'Bir tashkilotda bir xil department.code', 'DENIED', 'unique_violation', true); end $$;
do $$ declare n int; begin
  select count(*) into n from public.departments where code = 'CARDIO';
  perform pg_temp.ok('U2', 'Turli tashkilotda bir xil code (CARDIO)', '2', n::text, n = 2);
end $$;
do $$ begin
  insert into public.employees (org_id, employee_code) values ('00000000-0000-0000-0000-000000000001', 'T-06');
  perform pg_temp.ok('U3', 'Bir tashkilotda bir xil employee_code', 'DENIED', 'ALLOWED', false);
exception when unique_violation then perform pg_temp.ok('U3', 'Bir tashkilotda bir xil employee_code', 'DENIED', 'unique_violation', true); end $$;
do $$ begin
  insert into public.positions (org_id, name, code) values ('00000000-0000-0000-0000-000000000001', 'Dup', 'DOCTOR');
  perform pg_temp.ok('U4', 'Bir tashkilotda bir xil position.code', 'DENIED', 'ALLOWED', false);
exception when unique_violation then perform pg_temp.ok('U4', 'Bir tashkilotda bir xil position.code', 'DENIED', 'unique_violation', true); end $$;
do $$ begin
  delete from public.branches where org_id = '00000000-0000-0000-0000-000000000001' and code = 'MAIN';
  perform pg_temp.ok('K1', 'Xodim/bo''limi bor filialni o''chirish (FK RESTRICT)', 'DENIED', 'ALLOWED', false);
exception when foreign_key_violation or restrict_violation then perform pg_temp.ok('K1', 'Xodim/bo''limi bor filialni o''chirish (FK RESTRICT)', 'DENIED', 'FK: ' || sqlstate, true); end $$;
do $$ begin
  delete from public.departments where org_id = '00000000-0000-0000-0000-000000000001' and code = 'CARDIO';
  perform pg_temp.ok('K2', 'Xodimi bor bo''limni o''chirish (FK RESTRICT)', 'DENIED', 'ALLOWED', false);
exception when foreign_key_violation or restrict_violation then perform pg_temp.ok('K2', 'Xodimi bor bo''limni o''chirish (FK RESTRICT)', 'DENIED', 'FK: ' || sqlstate, true); end $$;
do $$ begin
  insert into public.employees (org_id, employee_code, department_id) values ('00000000-0000-0000-0000-000000000001', 'BAD-FK', gen_random_uuid());
  perform pg_temp.ok('K3', 'Mavjud bo''lmagan bo''limga bog''lash', 'DENIED', 'ALLOWED', false);
exception when others then perform pg_temp.ok('K3', 'Mavjud bo''lmagan bo''limga bog''lash', 'DENIED', 'DENIED ' || sqlstate || ': ' || left(sqlerrm, 50), true); end $$;
do $$ declare n int; begin
  perform pg_temp.login('262a128c-6fb7-470e-9452-5468cd6797c0'); set local role authenticated;
  delete from public.employees where profile_id = 'a0000000-0000-0000-0000-000000000007'; get diagnostics n = row_count;
  reset role; perform pg_temp.ok('K4', 'API orqali xodimni hard delete', '0 qator (delete policy yo''q)', n::text, n = 0);
exception when others then perform pg_temp.ok('K4', 'API orqali xodimni hard delete', '0 qator', 'DENIED', true); end $$;

-- ===================== Mavjud ma'lumot va Phase 1 regressiya =====================
do $$ declare ok boolean; v text; begin
  select (select count(*) from public.courses where org_id = '00000000-0000-0000-0000-000000000001') = 13
     and (select count(*) from public.questions where org_id = '00000000-0000-0000-0000-000000000001' and id like 'Q%') = 131
     and (select count(*) from public.exam_configs where org_id = '00000000-0000-0000-0000-000000000001') = 13
     and (select role || '/' || status from public.profiles where id = '262a128c-6fb7-470e-9452-5468cd6797c0') = 'super_admin/active'
     and exists (select 1 from public.employees where profile_id = '262a128c-6fb7-470e-9452-5468cd6797c0' and department_id is not null)
     and (select department from public.profiles where id = '262a128c-6fb7-470e-9452-5468cd6797c0') = 'Kardiologiya'
     and (select count(*) from public.exam_attempts where kind = 'initial') >= 1
    into ok;
  select (select count(*) from public.courses where org_id = '00000000-0000-0000-0000-000000000001') || ' kurs, ' || (select count(*) from public.questions where org_id = '00000000-0000-0000-0000-000000000001' and id like 'Q%') || ' savol, admin=' ||
         (select role from public.profiles where id = '262a128c-6fb7-470e-9452-5468cd6797c0') || ', profiles.department=' ||
         coalesce((select department from public.profiles where id = '262a128c-6fb7-470e-9452-5468cd6797c0'), 'NULL') into v;
  perform pg_temp.ok('R1', 'Mavjud ma''lumot saqlangan (kurslar, savollar, admin, bo''lim matni, initial)', '13/131/super_admin', v, ok);
end $$;
do $$ declare att jsonb; res jsonb; ans jsonb; ver jsonb; ini jsonb; begin
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  att := public.start_exam('ETHICS', 'final', null, null, false);
  reset role;
  select jsonb_object_agg(q.id, case when q.type = 'match' then (select jsonb_object_agg((i - 1)::text, e) from jsonb_array_elements(q.answer) with ordinality x(e, i))
                                     when q.type = 'short' then q.answer -> 0 else q.answer end)
    into ans from public.questions q where q.id in (select jsonb_array_elements_text(att -> 'qids'));
  perform pg_temp.login('a0000000-0000-0000-0000-000000000006'); set local role authenticated;
  res := public.submit_exam(att ->> 'id', ans);
  ver := public.verify_certificate(res -> 'certificate' ->> 'id');
  ini := public.start_exam('INITIAL', 'initial', null, '{"medical":"RESIDENT_START","ethics":"ETHICS","communication":"COMM","safety":"SAFETY","public_health":"PH","sales":"SALES"}'::jsonb, false);
  reset role;
  perform pg_temp.ok('R2', 'Phase 1: imtihon payload''ida javob yo''q', 'true',
    (select bool_and(not (q ? 'a'))::text from jsonb_array_elements(att -> 'questions') q), (select bool_and(not (q ? 'a')) from jsonb_array_elements(att -> 'questions') q));
  perform pg_temp.ok('R3', 'Phase 1: to''g''ri javob → 100% PASSED + sertifikat (org A)', '100 / true / org A',
    (res -> 'attempt' ->> 'score') || ' / ' || (res -> 'attempt' ->> 'passed') || ' / ' || coalesce((select org_id::text from public.certificates where id = res -> 'certificate' ->> 'id'), 'yo''q'),
    (res -> 'attempt' ->> 'score')::numeric = 100 and (select org_id from public.certificates where id = res -> 'certificate' ->> 'id') = '00000000-0000-0000-0000-000000000001');
  perform pg_temp.ok('R4', 'Phase 1: QR tekshiruv', 'Amalda', coalesce(ver ->> 'status', 'null'), ver ->> 'status' = 'Amalda');
  perform pg_temp.ok('R5', 'Phase 1: initial assessment (12 savol, org A)', '12', jsonb_array_length(ini -> 'qids')::text,
    jsonb_array_length(ini -> 'qids') = 12 and (select org_id from public.exam_attempts where id = ini ->> 'id') = '00000000-0000-0000-0000-000000000001');
end $$;
do $$ declare att jsonb; res jsonb; begin
  perform pg_temp.login('a0000000-0000-0000-0000-000000000007'); set local role authenticated;
  att := public.start_exam('PH', 'final', null, null, false);
  res := public.submit_exam(att ->> 'id', '{}'::jsonb);
  begin
    perform public.start_exam('PH', 'final', null, null, false);
    reset role; perform pg_temp.ok('R6', 'Phase 1: fail → retake bloklanadi', 'DENIED', 'ALLOWED', false);
  exception when others then reset role; perform pg_temp.ok('R6', 'Phase 1: fail → retake bloklanadi', 'DENIED', 'DENIED: ' || left(sqlerrm, 40), (res -> 'attempt' ->> 'passed')::boolean = false);
  end;
end $$;
do $$ declare n int; begin
  -- frontend docs.employees'ga yozganda employees avtomatik sinxronlanadi (o'tish davri)
  perform pg_temp.login('a0000000-0000-0000-0000-000000000007'); set local role authenticated;
  insert into public.docs (collection, id, owner, data) values ('employees', 'a0000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000007',
     '{"id":"a0000000-0000-0000-0000-000000000007","firstName":"Yangi","lastName":"Ism","positionId":"senior_nurse","department":"Kardiologiya"}')
  on conflict (collection, id) do update set data = excluded.data;
  reset role;
  select count(*) into n from public.employees e join public.departments d on d.id = e.department_id
   where e.profile_id = 'a0000000-0000-0000-0000-000000000007' and e.first_name = 'Test' and d.code = 'THERAPY';
  perform pg_temp.ok('S1', 'docs → employees sinxron: xodim to''ldirilgan HR maydonlarini (bo''lim, ism) o''zgartira olmaydi', 'ism=Test, bo''lim=THERAPY', n || ' mos', n = 1);
end $$;

select id, test, expected, actual, case when pass then 'PASS' else 'FAIL' end as result from t004 order by id;
rollback;
