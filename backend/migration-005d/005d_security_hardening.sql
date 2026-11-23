-- MedAcademy · Migration 005d — Security hardening (tarixiy ma'lumot himoyasi + funksiya huquqlari)
-- Evidence migratsiyalari va Admin Panel migratsiyalaridan ALOHIDA. 005c production policy'siga tegmaydi.
--
--   A1. 6 ta CASCADE FK → RESTRICT (auth user / kurs o'chirilsa tarix jimgina yo'qolmasin)
--   A1b. Akkaunt lifecycle: active → inactive → deactivated ("Deactivate > Delete")
--        + set_employee_status() RPC (ruxsat, tashkilot, o'zini/oxirgi super adminni himoya, server-side audit)
--   A2/A3/A4. Funksiya EXECUTE huquqlari kategoriyalar bo'yicha (anon faqat verify_certificate)
--   C.  Sertifikat va yakunlangan urinish — o'zgarmas tarixiy yozuv (trigger bilan)
--
-- Qoidalar: DROP TABLE / TRUNCATE / DELETE / data migration YO'Q. Mavjud qatorlar o'zgarmaydi.
-- Idempotent (qayta ishga tushirish xavfsiz). Rollback: 005d_rollback.sql (shu fayl yaratgan snapshot'dan).
-- Bitta tranzaksiya: xato bo'lsa hech narsa qo'llanmaydi.

begin;

-- ---------- 0. Rollback uchun snapshot (faqat birinchi marta yoziladi) ----------
create schema if not exists backup;
revoke all on schema backup from public;
do $$ begin
  if to_regclass('backup.security_pre005d') is null then
    create table backup.security_pre005d (kind text not null, name text not null, detail text, grantee text, created_at timestamptz not null default now());
    alter table backup.security_pre005d enable row level security;
    -- FK ta'riflari
    insert into backup.security_pre005d (kind, name, detail)
      select 'fk', conrelid::regclass::text || '.' || conname, pg_get_constraintdef(oid)
      from pg_constraint where contype = 'f' and connamespace = 'public'::regnamespace and confdeltype = 'c';
    -- Funksiya huquqlari (proacl NULL = standart: PUBLIC execute)
    insert into backup.security_pre005d (kind, name, detail, grantee)
      select 'fn_acl', p.oid::regprocedure::text, 'EXECUTE',
             case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end
      from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and a.privilege_type = 'EXECUTE'
        and (a.grantee = 0 or a.grantee::regrole::text in ('anon','authenticated'));
    -- Kelajakdagi funksiyalar uchun default huquqlar (Supabase: postgres → anon, authenticated)
    insert into backup.security_pre005d (kind, name, detail, grantee)
      select 'default_acl', d.defaclrole::regrole::text, 'EXECUTE', case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end
      from pg_default_acl d cross join lateral aclexplode(d.defaclacl) a
      where d.defaclnamespace = 'public'::regnamespace and d.defaclobjtype = 'f' and a.privilege_type = 'EXECUTE'
        and (a.grantee = 0 or a.grantee::regrole::text in ('anon','authenticated'));
    insert into backup.security_pre005d (kind, name, detail)
      select 'constraint', 'profiles.' || conname, pg_get_constraintdef(oid) from pg_constraint
      where conrelid = 'public.profiles'::regclass and conname = 'profiles_status_check';
  end if;
end $$;

-- ---------- A1. CASCADE → RESTRICT (6 ta tarixiy FK) ----------
do $$ declare r record; v_def text; begin
  for r in select * from (values
      ('public.profiles',       'profiles_id_fkey',            'id',        'auth.users',     'id'),
      ('public.docs',           'docs_owner_fkey',             'owner',     'auth.users',     'id'),
      ('public.exam_attempts',  'exam_attempts_user_id_fkey',  'user_id',   'auth.users',     'id'),
      ('public.certificates',   'certificates_user_id_fkey',   'user_id',   'auth.users',     'id'),
      ('public.attempt_resets', 'attempt_resets_user_id_fkey', 'user_id',   'auth.users',     'id'),
      ('public.exam_configs',   'exam_configs_course_id_fkey', 'course_id', 'public.courses', 'id')
    ) as t(tbl, con, col, reftbl, refcol) loop
    select pg_get_constraintdef(oid) into v_def from pg_constraint where conrelid = r.tbl::regclass and conname = r.con;
    if v_def is null then
      execute format('alter table %s add constraint %I foreign key (%I) references %s(%I) on delete restrict', r.tbl, r.con, r.col, r.reftbl, r.refcol);
    elsif v_def not ilike '%on delete restrict%' then
      execute format('alter table %s drop constraint %I', r.tbl, r.con);
      execute format('alter table %s add constraint %I foreign key (%I) references %s(%I) on delete restrict', r.tbl, r.con, r.col, r.reftbl, r.refcol);
    end if;
  end loop;
end $$;

-- ---------- A1b. Akkaunt lifecycle: active → inactive → deactivated ----------
-- Faqat ruxsat etilgan qiymatlar to'plami kengayadi (mavjud qatorlar o'zgarmaydi). my_role() faqat 'active' uchun rol qaytaradi,
-- shuning uchun inactive/deactivated akkaunt avtomatik ravishda hech qanday RLS / RPC huquqiga ega bo'lmaydi.
do $$ declare v_def text; begin
  select pg_get_constraintdef(oid) into v_def from pg_constraint where conrelid = 'public.profiles'::regclass and conname = 'profiles_status_check';
  if v_def is null or v_def not like '%deactivated%' then
    if v_def is not null then alter table public.profiles drop constraint profiles_status_check; end if;
    alter table public.profiles add constraint profiles_status_check check (status in ('pending','active','inactive','deactivated','rejected'));
  end if;
end $$;

create or replace function public.set_employee_status(p_employee uuid, p_status text, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_role text := public.my_role(); v_org uuid := public.my_org();
  e public.employees; p public.profiles; v_emp_new text; v_prof_old text; v_prof_new text;
begin
  if auth.uid() is null or v_role is null then raise exception 'Ruxsat yo''q'; end if;
  if p_status is null or p_status not in ('active','inactive','deactivated') then raise exception 'Noto''g''ri holat: faqat active / inactive / deactivated'; end if;
  select * into e from public.employees where id = p_employee and org_id = v_org for update;
  if not found then raise exception 'Xodim topilmadi'; end if;           -- boshqa tashkilot xodimi ham shu xabar
  if p_status = 'active' then
    if not public.has_perm('employee.edit') then raise exception 'Ruxsat yo''q: employee.edit kerak'; end if;
  else
    if not public.has_perm('employee.deactivate') then raise exception 'Ruxsat yo''q: employee.deactivate kerak'; end if;
    if coalesce(trim(p_reason), '') = '' then raise exception 'Faolsizlantirish sababi kiritilishi shart'; end if;
  end if;

  if e.profile_id is not null then
    select * into p from public.profiles where id = e.profile_id for update;
    if e.profile_id = auth.uid() then raise exception 'O''z akkauntingiz holatini o''zgartira olmaysiz'; end if;
    if p.role = 'super_admin' and v_role <> 'super_admin' then raise exception 'Super Admin holatini faqat Super Admin o''zgartira oladi'; end if;
    if p.status = 'deactivated' and p_status <> 'deactivated' and v_role <> 'super_admin' then
      raise exception 'Deactivated akkauntni faqat Super Admin qayta faollashtira oladi';
    end if;
    if p.role = 'super_admin' and p.status = 'active' and p_status <> 'active'
       and (select count(*) from public.profiles where org_id = p.org_id and role = 'super_admin' and status = 'active') <= 1 then
      raise exception 'Oxirgi faol Super Admin''ni faolsizlantirib bo''lmaydi';
    end if;
    v_prof_old := p.status;
    -- pending / rejected akkauntlar HR tasdiqlash oqimida qoladi; bu RPC faqat lifecycle holatlarini boshqaradi
    if p.status in ('active','inactive','deactivated') and p.status <> p_status then
      update public.profiles set status = p_status where id = p.id;
      v_prof_new := p_status;
    else
      v_prof_new := p.status;
    end if;
  end if;

  v_emp_new := case when p_status = 'active' then 'active'
                    when e.employment_status = 'terminated' then 'terminated'   -- HR faktini o'zgartirmaymiz
                    else 'inactive' end;
  if v_emp_new <> e.employment_status then
    update public.employees set employment_status = v_emp_new where id = e.id;  -- employees_audit_trg ham yozadi
  end if;

  insert into public.audit_logs (org_id, actor_id, actor_role, action, entity, entity_id, old_value, new_value)
  values (v_org, auth.uid(), v_role, 'employee.status_' || p_status, 'employee', e.id::text,
          jsonb_build_object('employment_status', e.employment_status, 'account_status', v_prof_old),
          jsonb_build_object('employment_status', v_emp_new, 'account_status', v_prof_new, 'reason', nullif(trim(p_reason), ''), 'profile_id', e.profile_id));

  return jsonb_build_object('employee', e.id, 'employment_status', v_emp_new, 'account_status', v_prof_new);
end $$;

-- ---------- C. Tarixiy yozuvlar o'zgarmas ----------
-- Sertifikat: berilgan ism, lavozim, kurs, ball, sana — o'zgarmaydi. Faqat bekor qilish (revoke) mumkin va u qaytarilmaydi.
-- Xodim profili holati / ismi o'zgarishi sertifikat matniga ta'sir qilmaydi (sertifikat o'z nusxasini saqlaydi).
create or replace function public.guard_certificate_history() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Sertifikat tarixiy yozuv — o''chirib bo''lmaydi (bekor qilish uchun revoke ishlating)';
  end if;
  if (to_jsonb(new) - 'revoked' - 'revoked_by' - 'revoked_at') is distinct from (to_jsonb(old) - 'revoked' - 'revoked_by' - 'revoked_at') then
    raise exception 'Sertifikat ma''lumotlari o''zgarmas (ism, kurs, ball, sana, urinish)';
  end if;
  if old.revoked then
    if not new.revoked then raise exception 'Bekor qilingan sertifikatni qayta tiklab bo''lmaydi'; end if;
    new.revoked_by := old.revoked_by; new.revoked_at := old.revoked_at;   -- birinchi bekor qilish yozuvi saqlanadi
  end if;
  return new;
end $$;
drop trigger if exists certificates_history_guard_trg on public.certificates;
create trigger certificates_history_guard_trg before update or delete on public.certificates
  for each row execute function public.guard_certificate_history();

-- Yakunlangan urinish (finished_at bor) — javoblar, natija, ball, savol versiyalari o'zgarmaydi; urinish o'chirilmaydi.
create or replace function public.guard_attempt_history() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then raise exception 'Imtihon urinishi tarixiy yozuv — o''chirib bo''lmaydi'; end if;
  if old.finished_at is not null and to_jsonb(new) is distinct from to_jsonb(old) then
    raise exception 'Yakunlangan urinish o''zgarmas';
  end if;
  return new;
end $$;
drop trigger if exists exam_attempts_history_guard_trg on public.exam_attempts;
create trigger exam_attempts_history_guard_trg before update or delete on public.exam_attempts
  for each row execute function public.guard_attempt_history();

-- ---------- A2/A3/A4. Funksiya EXECUTE huquqlari ----------
-- Kategoriyalar:
--   public_safe   — anon + authenticated   (ochiq sertifikat tekshiruvi)
--   employee_rpc  — authenticated          (ichida auth.uid() va o'z doirasi tekshiriladi)
--   role_rpc      — authenticated          (ichida rol / ruxsat / tashkilot tekshiriladi)
--   rls_helper    — authenticated          (RLS policy'lar chaqiradi; olib tashlansa RLS buziladi)
--   internal      — hech kim (anon ham, authenticated ham emas): faqat security definer RPC/trigger ichidan
--   trigger       — trigger va event trigger funksiyalari (masalan Supabase'ning rls_auto_enable): to'g'ridan-to'g'ri chaqirib bo'lmaydi,
--                   EXECUTE huquqisiz ham ishga tushadi (lokal test bilan tasdiqlangan) — baribir yopiladi
create table if not exists backup.function_categories_005d (name text primary key, category text not null);
insert into backup.function_categories_005d (name, category) values
  ('verify_certificate','public_safe'),
  ('start_exam','employee_rpc'), ('save_answers','employee_rpc'), ('submit_exam','employee_rpc'),
  ('get_attempt_review','employee_rpc'), ('question_meta','employee_rpc'),
  ('admin_reset_attempts','role_rpc'), ('revoke_certificate','role_rpc'), ('import_research_result','role_rpc'), ('set_employee_status','role_rpc'),
  ('my_org','rls_helper'), ('my_role','rls_helper'), ('my_dept','rls_helper'), ('my_department_id','rls_helper'), ('my_employee_id','rls_helper'),
  ('has_perm','rls_helper'), ('is_course_instructor','rls_helper'), ('can_see_question','rls_helper'), ('can_see_question_row','rls_helper'),
  ('can_see_source','rls_helper'),
  ('_attempt_out','internal'), ('_attempt_payload','internal'), ('_cert_out','internal'), ('_default_evidence_tier','internal'),
  ('_grade','internal'), ('_norm','internal'), ('_q_at','internal'), ('_q_exam_eligible','internal'), ('_q_full','internal'),
  ('_q_is_clinical','internal'), ('_q_public','internal'), ('_q_refs','internal'), ('_safe_date','internal'),
  ('guard_evidence_classification_origin_ok','internal'), ('is_api_request','internal'), ('mark_overdue_assignments','internal'),
  ('recompute_question_evidence','internal'), ('refresh_evidence_freshness','internal'), ('seed_org_defaults','internal'),
  ('seed_org_defaults_005','internal')
on conflict (name) do update set category = excluded.category;
alter table backup.function_categories_005d enable row level security;
revoke all on backup.function_categories_005d from public;

do $$ declare r record; v_cat text; begin
  for r in select p.oid::regprocedure::text sig, p.proname, pg_get_function_result(p.oid) in ('trigger','event_trigger') is_trg
           from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' loop
    select category into v_cat from backup.function_categories_005d where name = r.proname;
    if v_cat is null and r.is_trg then v_cat := 'trigger'; end if;
    if v_cat is null then
      raise notice '005d: tasniflanmagan funksiya % — huquqlari o''zgartirilmadi', r.sig;
      continue;
    end if;
    execute format('revoke execute on function %s from public, anon, authenticated', r.sig);
    if v_cat = 'public_safe' then
      execute format('grant execute on function %s to anon, authenticated', r.sig);
    elsif v_cat in ('employee_rpc','role_rpc','rls_helper') then
      execute format('grant execute on function %s to authenticated', r.sig);
    end if;
    -- internal / trigger: hech kimga berilmaydi (owner va service_role saqlanadi)
  end loop;
end $$;

-- Kelajakdagi funksiyalar: standart bo'yicha anon/PUBLIC uchun EXECUTE berilmasin (ochiq funksiya faqat aniq GRANT bilan)
alter default privileges in schema public revoke execute on functions from public;
alter default privileges in schema public revoke execute on functions from anon;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'postgres') and current_user <> 'postgres' then
    execute 'alter default privileges for role postgres in schema public revoke execute on functions from public';
    execute 'alter default privileges for role postgres in schema public revoke execute on functions from anon';
  end if;
exception when insufficient_privilege then raise notice '005d: postgres default privileges o''zgartirilmadi (huquq yo''q)';
end $$;

insert into public.schema_migrations (version, description) values
  ('005d', 'Security hardening: 6 CASCADE FK -> RESTRICT, account lifecycle (inactive/deactivated) + set_employee_status RPC, certificate/attempt history immutability, function EXECUTE privileges by category')
on conflict (version) do nothing;

commit;

-- Natija
select
  (select count(*) from pg_constraint where contype = 'f' and connamespace = 'public'::regnamespace and confdeltype = 'c') as cascade_fk_public,
  (select count(*) from pg_constraint where contype = 'f' and connamespace = 'public'::regnamespace and confdeltype = 'r'
     and conname in ('profiles_id_fkey','docs_owner_fkey','exam_attempts_user_id_fkey','certificates_user_id_fkey','attempt_resets_user_id_fkey','exam_configs_course_id_fkey')) as restrict_fk_target6,
  (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')) as anon_exec_functions,
  (select string_agg(p.proname, ',') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')) as anon_exec_names,
  (select count(*) from public.questions) as questions, (select count(*) from public.exam_attempts) as attempts,
  (select count(*) from public.certificates) as certificates, (select count(*) from public.profiles) as profiles, (select count(*) from public.docs) as docs;
