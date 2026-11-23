-- STAGING: Migration 005e dan oldin to'liq backup + snapshot (faqat qo'shadi: backup sxemasida nusxa; hech narsani o'zgartirmaydi/o'chirmaydi)
-- Qamrov: public'dagi BARCHA jadvallar (to'liq ma'lumot) + ustun / constraint / indeks / RLS policy / funksiya (ta'rif + EXECUTE huquqlari)
--         / trigger / jadval grant / default privileges snapshot'lari.
create schema if not exists backup;
revoke all on schema backup from anon, authenticated;
do $$ declare t text; begin
  if to_regclass('backup.tables_pre005e_20261123') is not null then raise exception 'pre005e backup allaqachon mavjud — qayta yozilmaydi'; end if;
  create table backup.tables_pre005e_20261123 (tablename text primary key, live_rows bigint, backup_table text);
  for t in select tablename from pg_tables where schemaname = 'public' order by tablename loop
    execute format('create table backup.%I as select * from public.%I', left(t, 38) || '_pre005e_20261123', t);
    execute format('alter table backup.%I enable row level security', left(t, 38) || '_pre005e_20261123');
    execute format('insert into backup.tables_pre005e_20261123 values (%L, (select count(*) from public.%I), %L)', t, t, left(t, 38) || '_pre005e_20261123');
  end loop;
end $$;
alter table backup.tables_pre005e_20261123 enable row level security;

create table backup.columns_pre005e_20261123 as
  select table_name, column_name, ordinal_position, data_type, is_nullable, column_default from information_schema.columns where table_schema = 'public';
create table backup.constraints_pre005e_20261123 as
  select conrelid::regclass::text as tablename, conname, contype, pg_get_constraintdef(oid) as def from pg_constraint where connamespace = 'public'::regnamespace;
create table backup.indexes_pre005e_20261123 as select tablename, indexname, indexdef from pg_indexes where schemaname = 'public';
create table backup.policies_pre005e_20261123 as
  select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check from pg_policies where schemaname = 'public';
create table backup.functions_pre005e_20261123 as
  select p.oid::regprocedure::text as signature, p.prosecdef as security_definer, pg_get_functiondef(p.oid) as def,
         has_function_privilege('anon', p.oid, 'execute') as anon_exec, has_function_privilege('authenticated', p.oid, 'execute') as auth_exec
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.prokind = 'f';
create table backup.triggers_pre005e_20261123 as
  select c.relname as tablename, t.tgname, pg_get_triggerdef(t.oid) as def
    from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and not t.tgisinternal;
create table backup.grants_pre005e_20261123 as
  select table_name, grantee, privilege_type from information_schema.role_table_grants where table_schema = 'public' and grantee in ('anon','authenticated');
create table backup.default_acl_pre005e_20261123 as
  select d.defaclrole::regrole::text as owner_role, d.defaclobjtype as objtype, d.defaclacl::text as acl from pg_default_acl d where d.defaclnamespace = 'public'::regnamespace;
alter table backup.columns_pre005e_20261123 enable row level security;
alter table backup.constraints_pre005e_20261123 enable row level security;
alter table backup.indexes_pre005e_20261123 enable row level security;
alter table backup.policies_pre005e_20261123 enable row level security;
alter table backup.functions_pre005e_20261123 enable row level security;
alter table backup.triggers_pre005e_20261123 enable row level security;
alter table backup.grants_pre005e_20261123 enable row level security;
alter table backup.default_acl_pre005e_20261123 enable row level security;

-- Tekshiruv (bitta qator): har bir jadval uchun backup = live (soni va md5); snapshot'lar to'liq
create or replace function pg_temp.bsame(t text, b text) returns boolean language plpgsql as $$ declare x text; y text; begin
  execute format('select coalesce(md5(string_agg(md5(r::text), '''' order by md5(r::text))), ''-'') from public.%I r', t) into x;
  execute format('select coalesce(md5(string_agg(md5(r::text), '''' order by md5(r::text))), ''-'') from backup.%I r', b) into y;
  return x = y; end $$;
select json_build_object(
  'tables_backed_up', (select count(*) from backup.tables_pre005e_20261123),
  'tables_identical', (select count(*) from backup.tables_pre005e_20261123 b where pg_temp.bsame(b.tablename, b.backup_table)),
  'mismatched', (select coalesce(string_agg(b.tablename, ','), '-') from backup.tables_pre005e_20261123 b where not pg_temp.bsame(b.tablename, b.backup_table)),
  'total_rows', (select sum(live_rows) from backup.tables_pre005e_20261123),
  'policies', (select count(*) from backup.policies_pre005e_20261123), 'functions', (select count(*) from backup.functions_pre005e_20261123),
  'anon_exec_functions', (select count(*) from backup.functions_pre005e_20261123 where anon_exec),
  'triggers', (select count(*) from backup.triggers_pre005e_20261123), 'constraints', (select count(*) from backup.constraints_pre005e_20261123),
  'default_acl_rows', (select count(*) from backup.default_acl_pre005e_20261123))::text as backup_005e;
