-- PRODUCTION: 007d precheck — FAQAT SELECT. 'ok' = true bo'lmasa — TO'XTASH, 007d qo'llanmaydi.
-- Kutilgan qiymatlar 2026-11-27 dagi READ ONLY tekshiruvdan (100_readonly_review_007d.sql, 2026-11-27).
with s as (select
  (select count(*) from public.schema_migrations where version = '007c') m007c_,
  (select count(*) from public.schema_migrations where version = '007d') m007d,
  (select count(*) from unnest(array['notifications']) n where to_regclass('public.' || n) is not null) collisions,
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and (proname in ('my_notifications','unread_notification_count','mark_notification_read','mark_all_notifications_read') or proname like '%\_007d')) perm_collisions,
  (select count(*) from public.courses) courses, (select count(*) from public.questions) questions, (select count(*) from public.exam_configs) exam_configs,
  (select count(*) from public.exam_attempts) attempts, (select count(*) from public.certificates) certificates, (select count(*) from public.profiles) profiles,
  (select count(*) from public.audit_logs) audit_logs, (select count(*) from public.organizations) orgs, (select count(*) from public.role_permissions) role_perms,
  (select count(*) from pg_constraint where connamespace = 'public'::regnamespace and contype = 'f' and confdeltype = 'c') fk_cascade,
  (select coalesce(string_agg(p.proname, ',' order by p.proname), '-') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')) anon_exec,
  (select md5(string_agg(p.oid::regprocedure::text||':'||md5(pg_get_functiondef(p.oid))||':'||coalesce(p.proacl::text,'-'), '|' order by p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f') fn_md5,
  (select md5(string_agg(tgrelid::regclass||'.'||tgname||':'||tgtype, '|' order by tgrelid::regclass::text, tgname)) from pg_trigger where not tgisinternal and tgrelid::regclass::text not like 'backup.%') trg_md5,
  (select md5(string_agg(table_name||'.'||column_name||':'||data_type||':'||is_nullable||':'||coalesce(column_default,'-'), '|' order by table_name, column_name)) from information_schema.columns where table_schema = 'public') cols_md5,
  (select md5(string_agg(indexdef, '|' order by indexname)) from pg_indexes where schemaname = 'public') idx_md5,
  (select md5(string_agg(tablename||'.'||policyname||':'||cmd||':'||roles::text||':'||coalesce(qual,'-')||':'||coalesce(with_check,'-'), '|' order by tablename, policyname)) from pg_policies where schemaname = 'public') policy_md5,
  (select md5(string_agg(table_name||':'||grantee||':'||privilege_type, '|' order by table_name, grantee, privilege_type)) from information_schema.role_table_grants where table_schema = 'public' and grantee in ('anon','authenticated')) grant_md5,
  (select count(*) from pg_tables where schemaname = 'public') public_tables,
  (select count(*) from backup.tables_pre007d) backup_tables,
  (select count(*) from backup.fingerprint_pre007d) backup_fp
)
select json_build_object(
  'ok', m007c_ = 1 and m007d = 0 and collisions = 0 and perm_collisions = 0 and courses = 13 and questions = 131 and exam_configs = 13 and attempts = 2 and certificates = 0
        and orgs = 1 and role_perms = 119 and fk_cascade = 0 and anon_exec = 'verify_certificate' and public_tables = 48 and backup_tables = public_tables and backup_fp = 1
        and fn_md5 = 'a35223b643862afaaa0ddf156e125703' and trg_md5 = 'f329c02c9478f76d3ea9ced711e952c4' and cols_md5 = 'f5f0eae51561e99d2291c591efd5effb'
        and idx_md5 = '3586745b01d6d81924bb041fc39a5332' and policy_md5 = '37c11f51af30023e4952647e8475076e' and grant_md5 = '0d9a87ceed5086011794d28779a3a4b6',
  'notes', 'profiles=' || profiles || ', audit_logs=' || audit_logs || ' (kutilgan 1 / 315; ok shartida emas)',
  'm007c', m007c_, 'm007d', m007d, 'collisions', collisions, 'perm_collisions', perm_collisions, 'courses', courses, 'questions', questions, 'attempts', attempts,
  'orgs', orgs, 'role_perms', role_perms, 'fk_cascade', fk_cascade, 'anon_exec', anon_exec, 'fn_md5', fn_md5, 'trg_md5', trg_md5, 'cols_md5', cols_md5,
  'idx_md5', idx_md5, 'policy_md5', policy_md5, 'grant_md5', grant_md5, 'public_tables', public_tables, 'backup_tables', backup_tables, 'at', clock_timestamp())::text as precheck_007d
from s;
