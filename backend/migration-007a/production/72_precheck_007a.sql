-- PRODUCTION: 007a precheck — FAQAT SELECT. 'ok' = true bo'lmasa — TO'XTASH, 007a qo'llanmaydi.
-- Kutilgan qiymatlar 2026-11-25 dagi READ ONLY tekshiruvdan (70_readonly_review_007a.sql) va staging'ning 007a'dan oldingi holatidan (aynan mos).
with s as (select
  (select count(*) from public.schema_migrations where version = '006b') m006b,
  (select count(*) from public.schema_migrations where version = '007a') m007a,
  (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'lessons' and column_name = 'is_required') is_required_col,
  (select count(*) from public.courses) courses, (select count(*) from public.questions) questions, (select count(*) from public.exam_configs) exam_configs,
  (select count(*) from public.exam_attempts) attempts, (select count(*) from public.certificates) certificates, (select count(*) from public.profiles) profiles,
  (select count(*) from public.audit_logs) audit_logs,
  (select count(*) from pg_constraint where connamespace = 'public'::regnamespace and contype = 'f' and confdeltype = 'c') fk_cascade,
  (select coalesce(string_agg(p.proname, ',' order by p.proname), '-') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')) anon_exec,
  (select md5(string_agg(p.oid::regprocedure::text||':'||md5(pg_get_functiondef(p.oid))||':'||coalesce(p.proacl::text,'-'), '|' order by p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f') fn_md5, (select md5(string_agg(tgrelid::regclass||'.'||tgname||':'||tgtype, '|' order by tgrelid::regclass::text, tgname)) from pg_trigger where not tgisinternal and tgrelid::regclass::text not like 'backup.%') trg_md5, (select md5(string_agg(table_name||'.'||column_name||':'||data_type||':'||is_nullable||':'||coalesce(column_default,'-'), '|' order by table_name, column_name)) from information_schema.columns where table_schema = 'public') cols_md5, (select md5(string_agg(indexdef, '|' order by indexname)) from pg_indexes where schemaname = 'public') idx_md5, (select md5(string_agg(tablename||'.'||policyname||':'||cmd||':'||roles::text||':'||coalesce(qual,'-')||':'||coalesce(with_check,'-'), '|' order by tablename, policyname)) from pg_policies where schemaname = 'public') policy_md5, (select md5(string_agg(table_name||':'||grantee||':'||privilege_type, '|' order by table_name, grantee, privilege_type)) from information_schema.role_table_grants where table_schema = 'public' and grantee in ('anon','authenticated')) grant_md5,
  (select count(*) from pg_tables where schemaname = 'public') public_tables,
  (select count(*) from backup.tables_pre007a) backup_tables,
  (select count(*) from backup.fingerprint_pre007a) backup_fp
)
select json_build_object(
  'ok', m006b = 1 and m007a = 0 and is_required_col = 0 and courses = 13 and questions = 131 and exam_configs = 13 and attempts = 2 and certificates = 0
        and fk_cascade = 0 and anon_exec = 'verify_certificate' and public_tables = 44 and backup_tables = public_tables and backup_fp = 1
        and fn_md5 = '172209c6b19d383abed0bc390ef7012f' and trg_md5 = '65977d7e3a33503780f53a278d84ccda' and cols_md5 = '4e92bd08cc01dcf08b91461bfbe5b52d'
        and idx_md5 = '9e0c000957e51bd23df98163d4cba0d6' and policy_md5 = 'f27165f643c693164399f85a4ee65f51' and grant_md5 = '284356dbb45ebddb1719db28e8d94b7a',
  'notes', 'profiles=' || profiles || ', audit_logs=' || audit_logs || ' (kutilgan 1 / 307; login/ro''yxatdan o''tish faolligi bilan o''zgarishi mumkin — ok shartida emas, hisobotda qayd etiladi)',
  'm006b', m006b, 'm007a', m007a, 'is_required_col', is_required_col, 'courses', courses, 'questions', questions, 'exam_configs', exam_configs,
  'attempts', attempts, 'certificates', certificates, 'fk_cascade', fk_cascade, 'anon_exec', anon_exec, 'fn_md5', fn_md5, 'trg_md5', trg_md5,
  'cols_md5', cols_md5, 'idx_md5', idx_md5, 'policy_md5', policy_md5, 'grant_md5', grant_md5, 'public_tables', public_tables, 'backup_tables', backup_tables)::text as precheck_007a
from s;
