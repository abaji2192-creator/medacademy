-- PRODUCTION BACKUP Migration 005 dan oldin (faqat qo'shadi: backup sxemasida nusxa yaratadi; hech narsani o'zgartirmaydi/o'chirmaydi)
-- Qamrov: public sxemasidagi BARCHA jadvallar (to'liq ma'lumot) + sxema snapshot (ustunlar, cheklovlar, indekslar)
--         + RLS policy, funksiya, trigger va grant snapshot'lari. Rollback (29_rollback_005.sql) shu snapshot'dan tiklaydi.
create schema if not exists backup;
revoke all on schema backup from anon, authenticated;
do $$ declare t text; begin
  if to_regclass('backup.tables_pre005_20261123') is not null then raise exception 'pre005 backup allaqachon mavjud — qayta yozilmaydi'; end if;
  create table backup.tables_pre005_20261123 (tablename text primary key, live_rows bigint, backup_table text);
  for t in select tablename from pg_tables where schemaname = 'public' order by tablename loop
    execute format('create table backup.%I as select * from public.%I', left(t, 40) || '_pre005_20261123', t);
    execute format('alter table backup.%I enable row level security', left(t, 40) || '_pre005_20261123');
    execute format('insert into backup.tables_pre005_20261123 values (%L, (select count(*) from public.%I), %L)', t, t, left(t, 40) || '_pre005_20261123');
  end loop;
end $$;
alter table backup.tables_pre005_20261123 enable row level security;

create table backup.columns_pre005_20261123 as
  select table_name, column_name, ordinal_position, data_type, is_nullable, column_default from information_schema.columns where table_schema = 'public';
create table backup.constraints_pre005_20261123 as
  select conrelid::regclass::text as tablename, conname, contype, pg_get_constraintdef(oid) as def from pg_constraint where connamespace = 'public'::regnamespace;
create table backup.indexes_pre005_20261123 as select tablename, indexname, indexdef from pg_indexes where schemaname = 'public';
create table backup.policies_pre005_20261123 as
  select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check from pg_policies where schemaname = 'public';
create table backup.functions_pre005_20261123 as
  select p.oid::regprocedure::text as signature, pg_get_functiondef(p.oid) as def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.prokind = 'f';
create table backup.triggers_pre005_20261123 as
  select c.relname as tablename, t.tgname, pg_get_triggerdef(t.oid) as def
    from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and not t.tgisinternal;
create table backup.grants_pre005_20261123 as
  select table_name, grantee, privilege_type from information_schema.role_table_grants where table_schema = 'public' and grantee in ('anon','authenticated');
alter table backup.columns_pre005_20261123 enable row level security;
alter table backup.constraints_pre005_20261123 enable row level security;
alter table backup.indexes_pre005_20261123 enable row level security;
alter table backup.policies_pre005_20261123 enable row level security;
alter table backup.functions_pre005_20261123 enable row level security;
alter table backup.triggers_pre005_20261123 enable row level security;
alter table backup.grants_pre005_20261123 enable row level security;

-- Tekshiruv: har bir jadval uchun backup = live; snapshot'lar bo'sh emas
create or replace function pg_temp.bcount(t text) returns bigint language plpgsql as $$ declare n bigint; begin execute format('select count(*) from backup.%I', t) into n; return n; end $$;
select x.chk, x.live, x.backup, x.live = x.backup as ok from (
  select 'table: ' || b.tablename as chk, b.live_rows as live, pg_temp.bcount(b.backup_table) as backup from backup.tables_pre005_20261123 b
  union all select 'snapshot: policies', (select count(*) from pg_policies where schemaname = 'public'), (select count(*) from backup.policies_pre005_20261123)
  union all select 'snapshot: functions', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.prokind = 'f'), (select count(*) from backup.functions_pre005_20261123)
  union all select 'snapshot: triggers', (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'public'::regnamespace and not t.tgisinternal), (select count(*) from backup.triggers_pre005_20261123)
  union all select 'snapshot: constraints', (select count(*) from pg_constraint where connamespace = 'public'::regnamespace), (select count(*) from backup.constraints_pre005_20261123)
  union all select 'snapshot: columns', (select count(*) from information_schema.columns where table_schema = 'public'), (select count(*) from backup.columns_pre005_20261123)
  union all select 'snapshot: indexes', (select count(*) from pg_indexes where schemaname = 'public'), (select count(*) from backup.indexes_pre005_20261123)
  union all select 'snapshot: grants', (select count(*) from information_schema.role_table_grants where table_schema = 'public' and grantee in ('anon','authenticated')), (select count(*) from backup.grants_pre005_20261123)
) x order by x.chk;
