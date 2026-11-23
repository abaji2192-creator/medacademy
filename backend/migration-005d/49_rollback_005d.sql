-- FAQAT REAL INCIDENT UCHUN: Migration 005d ni bekor qilish — backup.security_pre005d snapshot'idan.
-- NON-DESTRUCTIVE: hech qanday jadval / ustun / qator o'chirilmaydi, ma'lumot o'zgarmaydi.
-- Tiklanadi: 6 ta FK (CASCADE), funksiya EXECUTE huquqlari, default privileges, profiles_status_check.
-- Olib tashlanadi: 005d trigger'lari (sertifikat/urinish guard) va set_employee_status() RPC (kod, ma'lumot emas).
-- Xavfsizlik: agar biror akkaunt 'inactive' / 'deactivated' holatida bo'lsa, rollback TO'XTAYDI (ma'lumotni o'zgartirmaslik uchun).

begin;

do $$ begin
  if to_regclass('backup.security_pre005d') is null then raise exception '005d snapshot (backup.security_pre005d) topilmadi — rollback qilinmaydi'; end if;
  if exists (select 1 from public.profiles where status in ('inactive','deactivated')) then
    raise exception 'Rollback to''xtatildi: % ta akkaunt inactive/deactivated holatida. Avval ularni qo''lda hal qiling.',
      (select count(*) from public.profiles where status in ('inactive','deactivated'));
  end if;
end $$;

-- 1. FK'lar: snapshot'dagi aynan ta'rif bilan (ON DELETE CASCADE)
do $$ declare r record; v_tbl text; v_con text; begin
  for r in select name, detail from backup.security_pre005d where kind = 'fk' loop
    v_tbl := split_part(r.name, '.', 1); v_con := split_part(r.name, '.', 2);
    if v_tbl not like '%.%' and position('.' in v_tbl) = 0 then v_tbl := 'public.' || v_tbl; end if;
    if exists (select 1 from pg_constraint where conrelid = v_tbl::regclass and conname = v_con and pg_get_constraintdef(oid) <> r.detail) then
      execute format('alter table %s drop constraint %I', v_tbl, v_con);
      execute format('alter table %s add constraint %I %s', v_tbl, v_con, r.detail);
    elsif not exists (select 1 from pg_constraint where conrelid = v_tbl::regclass and conname = v_con) then
      execute format('alter table %s add constraint %I %s', v_tbl, v_con, r.detail);
    end if;
  end loop;
end $$;

-- 2. Sertifikat / urinish guard trigger'lari va RPC
drop trigger if exists certificates_history_guard_trg on public.certificates;
drop trigger if exists exam_attempts_history_guard_trg on public.exam_attempts;
drop function if exists public.guard_certificate_history();
drop function if exists public.guard_attempt_history();
drop function if exists public.set_employee_status(uuid, text, text);

-- 3. profiles_status_check — asl ta'rif
do $$ declare v_def text; begin
  select detail into v_def from backup.security_pre005d where kind = 'constraint' and name = 'profiles.profiles_status_check';
  if v_def is not null then
    alter table public.profiles drop constraint if exists profiles_status_check;
    execute format('alter table public.profiles add constraint profiles_status_check %s', v_def);
  end if;
end $$;

-- 4. Funksiya huquqlari: snapshot'dagi grantee'lar aynan tiklanadi
do $$ declare r record; g record; begin
  for r in select distinct name from backup.security_pre005d where kind = 'fn_acl' loop
    if to_regprocedure(r.name) is null then continue; end if;
    execute format('revoke execute on function %s from public, anon, authenticated', r.name);
    for g in select grantee from backup.security_pre005d where kind = 'fn_acl' and name = r.name loop
      execute format('grant execute on function %s to %s', r.name, case when g.grantee = 'PUBLIC' then 'public' else quote_ident(g.grantee) end);
    end loop;
  end loop;
  -- snapshot'da hech bir grantee bo'lmagan (005d'dan oldin ham yopiq) funksiyalar yopiq qoladi
end $$;

-- 5. Default privileges (kelajakdagi funksiyalar)
do $$ declare r record; begin
  if not exists (select 1 from backup.security_pre005d where kind = 'default_acl') then
    execute 'alter default privileges in schema public grant execute on functions to public';   -- standart (o'rnatilgan) holat
  end if;
  for r in select name as owner_role, grantee from backup.security_pre005d where kind = 'default_acl' loop
    begin
      execute format('alter default privileges for role %I in schema public grant execute on functions to %s', r.owner_role,
                     case when r.grantee = 'PUBLIC' then 'public' else quote_ident(r.grantee) end);
    exception when insufficient_privilege then raise notice 'default privileges (%): huquq yo''q', r.owner_role;
    end;
  end loop;
end $$;

insert into public.schema_migrations (version, description)
values ('005d-rollback-' || to_char(now(), 'YYYYMMDDHH24MISS'), 'Migration 005d rollback (snapshot backup.security_pre005d)')
on conflict (version) do nothing;

commit;

-- Tekshiruv
select
  (select count(*) from pg_constraint where contype = 'f' and connamespace = 'public'::regnamespace and confdeltype = 'c') as cascade_fk_public,
  (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')) as anon_exec_functions,
  (select count(*) from pg_trigger where tgname in ('certificates_history_guard_trg','exam_attempts_history_guard_trg')) as guard_triggers,
  (select count(*) from public.questions) as questions, (select count(*) from public.exam_attempts) as attempts,
  (select count(*) from public.certificates) as certificates, (select count(*) from public.profiles) as profiles, (select count(*) from public.docs) as docs;
