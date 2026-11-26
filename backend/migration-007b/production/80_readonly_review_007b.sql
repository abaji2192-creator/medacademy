-- PRODUCTION READ-ONLY (Phase 3 STEP 7): 007b dan oldingi/keyingi production holati. Hech narsa yozilmaydi:
-- tranzaksiya READ ONLY rejimida ochiladi (har qanday yozuv urinishi PostgreSQL darajasida rad etiladi) va ROLLBACK bilan yopiladi.
begin;
set transaction read only;
select json_build_object(
  'read_only', current_setting('transaction_read_only'),
  'has_007a', (select count(*) from public.schema_migrations where version = '007a'),
  'has_007b', (select count(*) from public.schema_migrations where version = '007b'),
  'lpa_table', to_regclass('public.learning_path_assignments') is not null,
  'is_required_col', (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'lessons' and column_name = 'is_required'),
  'm005e', (select count(*) from public.schema_migrations where version = '005e'),
  'm006a', (select count(*) from public.schema_migrations where version = '006a'),
  'm006b', (select count(*) from public.schema_migrations where version = '006b'),
  'fp006a', (select json_build_object(
  'migrations', (select string_agg(version, ',' order by version) from public.schema_migrations),
  'fn_md5', (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(p.prosrc) || ':' || coalesce(p.proacl::text, '-') || ':' || p.prosecdef, '|' order by p.oid::regprocedure::text))
             from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and p.proname <> 'audit_logs_immutable'),
  'anon_exec', (select string_agg(p.proname, ',' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')),
  'policy_md5', (select md5(string_agg(tablename || '.' || policyname || ':' || cmd || ':' || roles::text || ':' || coalesce(qual, '-') || ':' || coalesce(with_check, '-'), '|' order by tablename, policyname))
                 from pg_policies where schemaname = 'public' and tablename <> 'attempt_reset_events'),
  'rls_tables', (select string_agg(c.relname, ',' order by c.relname) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relrowsecurity and c.relname <> 'attempt_reset_events'),
  'trigger_md5', (select md5(string_agg(c.relname || '.' || t.tgname || ':' || t.tgtype || ':' || p.proname, '|' order by c.relname, t.tgname))
                  from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_proc p on p.oid = t.tgfoid
                  where not t.tgisinternal and c.relnamespace = 'public'::regnamespace and c.relname <> 'attempt_reset_events'),
  'table_grant_md5', (select md5(string_agg(table_name || ':' || grantee || ':' || privilege_type, '|' order by table_name, grantee, privilege_type))
                      from information_schema.role_table_grants where table_schema = 'public' and grantee in ('anon','authenticated') and table_name <> 'attempt_reset_events'),
  'audit_seq_priv', (select string_agg(r || ':' || pr, ',' order by r, pr) from unnest(array['anon','authenticated']) r, unnest(array['USAGE','SELECT','UPDATE']) pr
                     where exists (select 1 from pg_roles where rolname = r) and has_sequence_privilege(r, 'public.audit_logs_id_seq', pr)),
  'data_md5', json_build_object(
    'questions', (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.questions x),
    'courses', (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.courses x),
    'exam_configs', (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.course_id, x.org_id), '')) from public.exam_configs x),
    'exam_attempts', (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.exam_attempts x),
    'certificates', (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.certificates x),
    'attempt_resets', (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.user_id, x.course_id), '')) from public.attempt_resets x),
    'profiles', (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.profiles x),
    'docs', (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.collection, x.id), '')) from public.docs x),
    'question_reviews', (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.question_reviews x),
    'role_permissions', (select md5(coalesce(string_agg(x.org_id || x.role || x.permission_key, '' order by x.org_id, x.role, x.permission_key), '')) from public.role_permissions x)),
  'audit_logs', (select count(*) from public.audit_logs)
)::text)::json,
  'fp007a', (select json_build_object(
  'project_marker', current_database() || '@' || coalesce(inet_server_addr()::text, '-'),
  'migrations', (select string_agg(version, ',' order by version) from public.schema_migrations),
  'tables', (select count(*) from pg_tables where schemaname = 'public'),
  'functions', (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and prokind = 'f'),
  'triggers', (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'public'::regnamespace and not t.tgisinternal),
  'policies', (select count(*) from pg_policies where schemaname = 'public'),
  'indexes', (select count(*) from pg_indexes where schemaname = 'public'),
  'cascade_fk', (select count(*) from pg_constraint where connamespace = 'public'::regnamespace and contype = 'f' and confdeltype = 'c'),
  'anon_exec', (select string_agg(p.proname, ',' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')),
  'cols_md5', (select md5(string_agg(table_name||'.'||column_name||':'||data_type||':'||is_nullable||':'||coalesce(column_default,'-'), '|' order by table_name, column_name)) from information_schema.columns where table_schema = 'public'),
  'fn_md5', (select md5(string_agg(p.oid::regprocedure::text||':'||md5(pg_get_functiondef(p.oid))||':'||coalesce(p.proacl::text,'-'), '|' order by p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'),
  'idx_md5', (select md5(string_agg(indexdef, '|' order by indexname)) from pg_indexes where schemaname = 'public'),
  'trg_md5', (select md5(string_agg(tgrelid::regclass||'.'||tgname||':'||tgtype, '|' order by tgrelid::regclass::text, tgname)) from pg_trigger where not tgisinternal and tgrelid::regclass::text not like 'backup.%'),
  'policy_md5', (select md5(string_agg(tablename||'.'||policyname||':'||cmd||':'||roles::text||':'||coalesce(qual,'-')||':'||coalesce(with_check,'-'), '|' order by tablename, policyname)) from pg_policies where schemaname = 'public'),
  'table_grant_md5', (select md5(string_agg(table_name||':'||grantee||':'||privilege_type, '|' order by table_name, grantee, privilege_type)) from information_schema.role_table_grants where table_schema = 'public' and grantee in ('anon','authenticated')),
  'fcat_md5', (select md5(coalesce(string_agg(name||':'||category, '|' order by name), '')) from backup.function_categories_005d),
  'counts', json_build_object(
    'courses', (select count(*) from public.courses), 'questions', (select count(*) from public.questions), 'exam_configs', (select count(*) from public.exam_configs),
    'exam_attempts', (select count(*) from public.exam_attempts), 'certificates', (select count(*) from public.certificates), 'profiles', (select count(*) from public.profiles),
    'employees', (select count(*) from public.employees), 'audit_logs', (select count(*) from public.audit_logs),
    'course_modules', (select count(*) from public.course_modules), 'lessons', (select count(*) from public.lessons),
    'lesson_progress', (select count(*) from public.lesson_progress), 'course_assignments', (select count(*) from public.course_assignments),
    'learning_paths', (select count(*) from public.learning_paths)),
  'data_md5', json_build_object(
    'questions', (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.questions x),
    'courses', (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.courses x),
    'exam_configs', (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.course_id, x.org_id), '')) from public.exam_configs x),
    'exam_attempts', (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.exam_attempts x),
    'certificates', (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.certificates x),
    'profiles', (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.profiles x),
    'course_modules', (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.course_modules x),
    'lessons_core', (select md5(coalesce(string_agg(x.id||x.module_id||x.title||x.status||x.order_index, '' order by x.id), '')) from public.lessons x),
    'lesson_progress', (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.lesson_progress x),
    'course_assignments', (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.course_assignments x),
    'audit_logs', (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.audit_logs x)),
  'at', clock_timestamp()
)::text)::json
)::text as prod_readonly_007a;
rollback;
