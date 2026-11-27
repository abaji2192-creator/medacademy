-- PRODUCTION READ-ONLY (Phase 3 STEP 11): 007e dan oldingi production holati. Hech narsa yozilmaydi:
-- tranzaksiya READ ONLY rejimida ochiladi va ROLLBACK bilan yopiladi.
begin;
set transaction read only;
select json_build_object(
  'read_only', current_setting('transaction_read_only'),
  'migrations', (select string_agg(version, ',' order by version) from public.schema_migrations),
  'has_007c', (select count(*) from public.schema_migrations where version = '007c'),
  'has_007d', (select count(*) from public.schema_migrations where version = '007d'),
  'has_007e', (select count(*) from public.schema_migrations where version = '007e'),
  'name_collisions', (select coalesce(string_agg(n, ','), '-') from unnest(array['training_compliance','competency_matrix']) n where to_regclass('public.' || n) is not null),
  'fn_collisions', (select coalesce(string_agg(proname, ','), '-') from pg_proc where pronamespace = 'public'::regnamespace and proname in ('employee_training_compliance','employee_competency_matrix','department_compliance_matrix') or (pronamespace = 'public'::regnamespace and proname like '%\_007e')),
  'perm_collisions', (select count(*) from public.permissions where key ~ '(compliance|matrix)'),
  'perm_categories', (select string_agg(distinct category, ',') from public.permissions),
  'orgs', (select count(*) from public.organizations),
  'role_permissions', (select count(*) from public.role_permissions),
  'tables', (select count(*) from pg_tables where schemaname = 'public'),
  'functions', (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and prokind = 'f'),
  'triggers', (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'public'::regnamespace and not t.tgisinternal),
  'policies', (select count(*) from pg_policies where schemaname = 'public'),
  'indexes', (select count(*) from pg_indexes where schemaname = 'public'),
  'cascade_fk', (select count(*) from pg_constraint where connamespace = 'public'::regnamespace and contype = 'f' and confdeltype = 'c'),
  'anon_exec', (select string_agg(p.proname, ',' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')),
  'anon_table_grants', (select count(*) from information_schema.role_table_grants where table_schema = 'public' and grantee = 'anon'),
  'fn_md5', (select md5(string_agg(p.oid::regprocedure::text||':'||md5(pg_get_functiondef(p.oid))||':'||coalesce(p.proacl::text,'-'), '|' order by p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'),
  'trg_md5', (select md5(string_agg(tgrelid::regclass||'.'||tgname||':'||tgtype, '|' order by tgrelid::regclass::text, tgname)) from pg_trigger where not tgisinternal and tgrelid::regclass::text not like 'backup.%'),
  'cols_md5', (select md5(string_agg(table_name||'.'||column_name||':'||data_type||':'||is_nullable||':'||coalesce(column_default,'-'), '|' order by table_name, column_name)) from information_schema.columns where table_schema = 'public'),
  'idx_md5', (select md5(string_agg(indexdef, '|' order by indexname)) from pg_indexes where schemaname = 'public'),
  'policy_md5', (select md5(string_agg(tablename||'.'||policyname||':'||cmd||':'||roles::text||':'||coalesce(qual,'-')||':'||coalesce(with_check,'-'), '|' order by tablename, policyname)) from pg_policies where schemaname = 'public'),
  'grant_md5', (select md5(string_agg(table_name||':'||grantee||':'||privilege_type, '|' order by table_name, grantee, privilege_type)) from information_schema.role_table_grants where table_schema = 'public' and grantee in ('anon','authenticated')),
  'role_perm_md5', (select md5(string_agg(org_id || ':' || role || ':' || permission_key, '|' order by org_id, role, permission_key)) from public.role_permissions),
  'org_triggers', (select string_agg(tgname, ',' order by tgname) from pg_trigger where tgrelid = 'public.organizations'::regclass and not tgisinternal),
  'counts', json_build_object('courses', (select count(*) from public.courses), 'questions', (select count(*) from public.questions), 'exam_configs', (select count(*) from public.exam_configs),
    'attempts', (select count(*) from public.exam_attempts), 'certificates', (select count(*) from public.certificates), 'profiles', (select count(*) from public.profiles),
    'employees', (select count(*) from public.employees), 'departments', (select count(*) from public.departments), 'audit_logs', (select count(*) from public.audit_logs),
    'course_assignments', (select count(*) from public.course_assignments), 'lpa', (select count(*) from public.learning_path_assignments),
    'skills', (select count(*) from public.skills), 'skill_assessments', (select count(*) from public.skill_assessments), 'competency_requirements', (select count(*) from public.competency_requirements),
    'notifications', (select count(*) from public.notifications), 'lessons', (select count(*) from public.lessons), 'lesson_progress', (select count(*) from public.lesson_progress),
    'learning_paths', (select count(*) from public.learning_paths), 'organizations', (select count(*) from public.organizations)),
  'backup_schema_tables', (select count(*) from pg_tables where schemaname = 'backup' and tablename like '%pre007e'),
  'at', clock_timestamp()
)::text as prod_readonly_007e;
rollback;
