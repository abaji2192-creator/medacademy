-- FAQAT REAL INCIDENT UCHUN: Migration 005 (005a + seed + 005b + 005c) ni bekor qilish — 20_backup_pre005.sql snapshot'idan.
-- NON-DESTRUCTIVE: hech qanday jadval/ustun/qator o'chirilmaydi. 005 jadvallari va ustunlari qoladi (ishlatilmaydi, API'dan yopiladi).
-- Tiklanadi: funksiyalar, trigger'lar, RLS policy'lar, mavjud savollarning eski `status` qiymati (backup'dan).
-- Production'da SINOV sifatida ishga tushirilmaydi.
do $$ declare r record; v_sig text;
begin
  if to_regclass('backup.functions_pre005_20261123') is null or to_regclass('backup.policies_pre005_20261123') is null
     or to_regclass('backup.triggers_pre005_20261123') is null then
    raise exception 'pre005 snapshot topilmadi — rollback to''xtatildi';
  end if;

  -- 1) Funksiyalar: 005 dan oldingi ta'riflar (005 qo'shgan yangi funksiyalar qoladi, ammo hech narsa ularni chaqirmaydi)
  for r in select def from backup.functions_pre005_20261123 loop execute r.def; end loop;

  -- 2) Trigger'lar: snapshot'da yo'q trigger'lar olib tashlanadi; snapshot'dagi trigger'lar aynan tiklanadi
  for r in select c.relname as tablename, t.tgname, pg_get_triggerdef(t.oid) as def
             from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'public'::regnamespace and not t.tgisinternal loop
    if not exists (select 1 from backup.triggers_pre005_20261123 b where b.tablename = r.tablename and b.tgname = r.tgname and b.def = r.def) then
      execute format('drop trigger %I on public.%I', r.tgname, r.tablename);
    end if;
  end loop;
  for r in select * from backup.triggers_pre005_20261123 b where not exists (
             select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'public'::regnamespace and c.relname = b.tablename and t.tgname = b.tgname) loop
    execute r.def;
  end loop;

  -- 3) RLS policy'lar: 005 dan oldin mavjud jadvallarda policy'lar aynan snapshot'dagidek
  for r in select policyname, tablename from pg_policies where schemaname = 'public'
            and tablename in (select tablename from backup.tables_pre005_20261123) loop
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);
  end loop;
  for r in select * from backup.policies_pre005_20261123 loop
    execute format('create policy %I on public.%I as %s for %s to %s%s%s', r.policyname, r.tablename, r.permissive, r.cmd,
      array_to_string(r.roles, ', '),
      case when r.qual is not null then ' using (' || r.qual || ')' else '' end,
      case when r.with_check is not null then ' with check (' || r.with_check || ')' else '' end);
  end loop;

  -- 4) 005 da yaratilgan jadvallar: ma'lumot saqlanadi, API orqali kirish yopiladi
  for r in select tablename from pg_tables where schemaname = 'public'
            and tablename not in (select tablename from backup.tables_pre005_20261123) loop
    execute format('revoke all on public.%I from anon, authenticated', r.tablename);
  end loop;

  -- 5) Mavjud savollar: Phase 1 imtihon filtri (status = ''approved'') uchun eski status backup'dan qaytariladi
  --    (questions_workflow_trg 2-qadamda olib tashlangan, shuning uchun qayta ishlamaydi)
  update public.questions q set status = b.status
    from backup.questions_pre005_20261123 b where b.id = q.id and q.status is distinct from b.status;

  insert into public.schema_migrations (version, description) values ('005-rollback-' || to_char(now(), 'YYYYMMDDHH24MI'), 'Migration 005 rollback (snapshot pre005_20261123)')
  on conflict (version) do nothing;
end $$;

-- Tekshiruv: snapshot bilan aynan mosligi
select 'functions (snapshot = live)' as chk,
       (select count(*) from backup.functions_pre005_20261123 b where exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'public' and p.oid::regprocedure::text = b.signature and pg_get_functiondef(p.oid) = b.def))::text || '/' ||
       (select count(*) from backup.functions_pre005_20261123)::text as val
union all select 'triggers (live = snapshot)',
       (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'public'::regnamespace and not t.tgisinternal)::text || '/' ||
       (select count(*) from backup.triggers_pre005_20261123)::text
union all select 'policies (pre-005 jadvallar)',
       (select count(*) from pg_policies p where schemaname = 'public' and exists (select 1 from backup.policies_pre005_20261123 b
          where b.tablename = p.tablename and b.policyname = p.policyname and b.cmd = p.cmd and b.qual is not distinct from p.qual and b.with_check is not distinct from p.with_check))::text || '/' ||
       (select count(*) from backup.policies_pre005_20261123)::text
union all select 'questions status = backup',
       (select count(*) from public.questions q join backup.questions_pre005_20261123 b on b.id = q.id where q.status = b.status)::text || '/' ||
       (select count(*) from backup.questions_pre005_20261123)::text;
