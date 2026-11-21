-- PRODUCTION BACKUP oldin Migration 004 (faqat qo'shadi; hech narsani o'zgartirmaydi/o'chirmaydi)
create schema if not exists backup;
revoke all on schema backup from anon, authenticated;
do $$ declare t text; begin
  foreach t in array array['profiles','docs','organizations','courses','questions','exam_configs','exam_attempts','certificates','attempt_resets'] loop
    execute format('create table if not exists backup.%I as select * from public.%I', t || '_pre004_20261122', t);
    execute format('alter table backup.%I enable row level security', t || '_pre004_20261122');
  end loop;
end $$;
-- Rollback uchun: mavjud RLS siyosatlari, funksiyalar va triggerlar snapshot'i
create table if not exists backup.policies_pre004_20261122 as
  select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check from pg_policies where schemaname = 'public';
create table if not exists backup.functions_pre004_20261122 as
  select p.oid::regprocedure::text as signature, pg_get_functiondef(p.oid) as def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.prokind = 'f';
create table if not exists backup.triggers_pre004_20261122 as
  select c.relname as tablename, t.tgname, pg_get_triggerdef(t.oid) as def
    from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and not t.tgisinternal;
alter table backup.policies_pre004_20261122 enable row level security;
alter table backup.functions_pre004_20261122 enable row level security;
alter table backup.triggers_pre004_20261122 enable row level security;
-- Tekshiruv: backup = live
select t.tbl, t.live, t.backup, t.live = t.backup as ok from (
  select 'profiles' tbl, (select count(*) from public.profiles) live, (select count(*) from backup.profiles_pre004_20261122) backup union all
  select 'docs', (select count(*) from public.docs), (select count(*) from backup.docs_pre004_20261122) union all
  select 'organizations', (select count(*) from public.organizations), (select count(*) from backup.organizations_pre004_20261122) union all
  select 'courses', (select count(*) from public.courses), (select count(*) from backup.courses_pre004_20261122) union all
  select 'questions', (select count(*) from public.questions), (select count(*) from backup.questions_pre004_20261122) union all
  select 'exam_configs', (select count(*) from public.exam_configs), (select count(*) from backup.exam_configs_pre004_20261122) union all
  select 'exam_attempts', (select count(*) from public.exam_attempts), (select count(*) from backup.exam_attempts_pre004_20261122) union all
  select 'certificates', (select count(*) from public.certificates), (select count(*) from backup.certificates_pre004_20261122) union all
  select 'attempt_resets', (select count(*) from public.attempt_resets), (select count(*) from backup.attempt_resets_pre004_20261122) union all
  select 'policies', (select count(*) from pg_policies where schemaname='public'), (select count(*) from backup.policies_pre004_20261122) union all
  select 'functions', (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f'), (select count(*) from backup.functions_pre004_20261122) union all
  select '004_tables_exist', (select count(*) from pg_tables where schemaname='public' and tablename in ('branches','departments','positions','specialties','employees','permissions','role_permissions','audit_logs','schema_migrations')), 0
) t;
