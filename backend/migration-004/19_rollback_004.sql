-- FAQAT FAVQULODDA: Migration 004 ni bekor qilish (10_backup_pre004.sql snapshot'idan).
-- Ma'lumot o'chirilmaydi: yangi 004 jadvallari qoladi, lekin Phase 1 siyosatlari, funksiyalari va triggerlari 004 dan oldingi holatga qaytadi.
do $$ declare r record; begin
  if to_regclass('backup.policies_pre004_20261122') is null then raise exception 'Snapshot topilmadi — rollback to''xtatildi'; end if;
  -- 1) 004 qo'shgan, mavjud jadvallardagi triggerlar
  drop trigger if exists on_org_created_trg on public.organizations;
  drop trigger if exists docs_sync_employee_trg on public.docs;
  -- 2) Funksiyalar: 004 dan oldingi ta'riflar
  for r in select def from backup.functions_pre004_20261122 loop execute r.def; end loop;
  -- 3) Phase 1 jadvallaridagi siyosatlar: hozirgisini olib tashlab, snapshot'dan tiklash
  for r in select policyname, tablename from pg_policies where schemaname = 'public'
           and tablename in (select distinct tablename from backup.policies_pre004_20261122) loop
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);
  end loop;
  for r in select * from backup.policies_pre004_20261122 loop
    execute format('create policy %I on public.%I as %s for %s to %s%s%s', r.policyname, r.tablename, r.permissive, r.cmd,
      array_to_string(r.roles, ', '),
      case when r.qual is not null then ' using (' || r.qual || ')' else '' end,
      case when r.with_check is not null then ' with check (' || r.with_check || ')' else '' end);
  end loop;
  -- 4) Yangi tuzilma jadvallarini API'dan yopish (ma'lumot saqlanadi)
  revoke all on public.branches, public.departments, public.positions, public.specialties, public.employees,
                public.permissions, public.role_permissions, public.audit_logs from authenticated;
  delete from public.schema_migrations where version in ('004a','004b');
end $$;
select (select count(*) from pg_policies where schemaname='public' and tablename in (select distinct tablename from backup.policies_pre004_20261122)) policies_now,
       (select count(*) from backup.policies_pre004_20261122) policies_snapshot;
