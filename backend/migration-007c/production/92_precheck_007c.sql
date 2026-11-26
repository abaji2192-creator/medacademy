-- PRODUCTION: 007c precheck — FAQAT SELECT. 'ok' = true bo'lmasa — TO'XTASH, 007c qo'llanmaydi.
-- Kutilgan qiymatlar 2026-11-26 dagi READ ONLY tekshiruvdan (90_readonly_review_007c.sql, 17:38 UTC).
with s as (select
  (select count(*) from public.schema_migrations where version = '007b') m007b,
  (select count(*) from public.schema_migrations where version = '007c') m007c,
  (select count(*) from unnest(array['skills','skill_assessments','competency_requirements']) n where to_regclass('public.' || n) is not null) collisions,
  (select count(*) from public.permissions where key in ('skill.view','skill.manage','skill.assess','competency.manage')) perm_collisions,
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
  (select count(*) from backup.tables_pre007c) backup_tables,
  (select count(*) from backup.fingerprint_pre007c) backup_fp
)
select json_build_object(
  'ok', m007b = 1 and m007c = 0 and collisions = 0 and perm_collisions = 0 and courses = 13 and questions = 131 and exam_configs = 13 and attempts = 2 and certificates = 0
        and orgs = 1 and role_perms = 111 and fk_cascade = 0 and anon_exec = 'verify_certificate' and public_tables = 45 and backup_tables = public_tables and backup_fp = 1
        and fn_md5 = '974fbd4d9dc09612276b97c7b22501d6' and trg_md5 = '3bbba44d286d604058c717ce064e7f55' and cols_md5 = 'e67adf34eff3c3de56fad231b371a232'
        and idx_md5 = '8ad5ee2160e277d85a651364a4bdd6d0' and policy_md5 = '3ac78566f2fc16866e2c6e3e3e8ff65d' and grant_md5 = '07db83beb825f635e10315bdde2f9ff1',
  'notes', 'profiles=' || profiles || ', audit_logs=' || audit_logs || ' (kutilgan 1 / 307; ok shartida emas)',
  'm007b', m007b, 'm007c', m007c, 'collisions', collisions, 'perm_collisions', perm_collisions, 'courses', courses, 'questions', questions, 'attempts', attempts,
  'orgs', orgs, 'role_perms', role_perms, 'fk_cascade', fk_cascade, 'anon_exec', anon_exec, 'fn_md5', fn_md5, 'trg_md5', trg_md5, 'cols_md5', cols_md5,
  'idx_md5', idx_md5, 'policy_md5', policy_md5, 'grant_md5', grant_md5, 'public_tables', public_tables, 'backup_tables', backup_tables, 'at', clock_timestamp())::text as precheck_007c
from s;
