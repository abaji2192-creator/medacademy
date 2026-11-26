-- 007b dan keyingi tekshiruv — FAQAT SELECT (staging va production). 'ok' = true bo'lmasa — 89_rollback_007b.sql (alohida qaror bilan).
with c as (select (select json_build_object(
  'functions_extra', (select coalesce(string_agg(sig, ',' order by sig), '-') from (select p.oid::regprocedure::text sig from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' except select signature from backup.functions_pre007b) x),
  'functions_missing', (select coalesce(string_agg(signature, ',' order by signature), '-') from (select signature from backup.functions_pre007b except select p.oid::regprocedure::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f') x),
  'functions_def_changed', (select count(*) from backup.functions_pre007b b join pg_proc p on p.oid::regprocedure::text = b.signature where p.pronamespace = 'public'::regnamespace and (pg_get_functiondef(p.oid) <> b.def or has_function_privilege('anon', p.oid, 'execute') <> b.anon_exec or has_function_privilege('authenticated', p.oid, 'execute') <> b.auth_exec)),
  'triggers_diff', (select count(*) from ((select c.relname, t.tgname, pg_get_triggerdef(t.oid) from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'public'::regnamespace and not t.tgisinternal except select tablename, tgname, def from backup.triggers_pre007b)
                    union all (select tablename, tgname, def from backup.triggers_pre007b except select c.relname, t.tgname, pg_get_triggerdef(t.oid) from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'public'::regnamespace and not t.tgisinternal)) x),
  'indexes_diff', (select count(*) from ((select tablename, indexname, indexdef from pg_indexes where schemaname = 'public' except select tablename, indexname, indexdef from backup.indexes_pre007b)
                   union all (select tablename, indexname, indexdef from backup.indexes_pre007b except select tablename, indexname, indexdef from pg_indexes where schemaname = 'public')) x),
  'columns_diff', (select count(*) from ((select table_name::text, column_name::text, data_type::text, is_nullable::text, column_default::text from information_schema.columns where table_schema = 'public' except select table_name, column_name, data_type, is_nullable, column_default from backup.columns_pre007b)
                   union all (select table_name, column_name, data_type, is_nullable, column_default from backup.columns_pre007b except select table_name::text, column_name::text, data_type::text, is_nullable::text, column_default::text from information_schema.columns where table_schema = 'public')) x),
  'policies_diff', (select count(*) from ((select tablename, policyname, cmd, qual, with_check from pg_policies where schemaname = 'public' except select tablename, policyname, cmd, qual, with_check from backup.policies_pre007b)
                    union all (select tablename, policyname, cmd, qual, with_check from backup.policies_pre007b except select tablename, policyname, cmd, qual, with_check from pg_policies where schemaname = 'public')) x),
  'migration_007b', (select count(*) from public.schema_migrations where version = '007b'),
  'x', 0))::json j),
s as (select
  (select count(*) from public.schema_migrations where version = '007b') m007b,
  (select count(*) from public.schema_migrations where version = '007a') m007a,
  to_regclass('public.learning_path_assignments') is not null lpa,
  (select relrowsecurity from pg_class where oid = to_regclass('public.learning_path_assignments')) lpa_rls,
  (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'learning_path_assignments') lpa_cols,
  (select count(*) from public.learning_path_assignments) rules,
  (select count(*) from information_schema.role_table_grants where table_schema = 'public' and table_name = 'learning_path_assignments' and grantee in ('anon','authenticated') and privilege_type <> 'SELECT') write_grants,
  (select count(*) from information_schema.role_table_grants where table_schema = 'public' and table_name = 'learning_path_assignments' and grantee = 'anon') anon_grants,
  has_function_privilege('authenticated', 'public.apply_learning_path(uuid,text,text,date)'::regprocedure, 'execute')
    and has_function_privilege('authenticated', 'public.reapply_learning_path_assignment(uuid)'::regprocedure, 'execute')
    and has_function_privilege('authenticated', 'public.cancel_learning_path_assignment(uuid,text)'::regprocedure, 'execute') rpc_auth,
  has_function_privilege('anon', 'public.apply_learning_path(uuid,text,text,date)'::regprocedure, 'execute')
    or has_function_privilege('anon', 'public.reapply_learning_path_assignment(uuid)'::regprocedure, 'execute')
    or has_function_privilege('anon', 'public.cancel_learning_path_assignment(uuid,text)'::regprocedure, 'execute') rpc_anon,
  (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('guard_lpa_007b', '_lpa_apply_rule_007b', '_lpa_can_manage_007b') and has_function_privilege('authenticated', p.oid, 'EXECUTE')) internal_auth,
  (select coalesce(string_agg(p.proname, ',' order by p.proname), '-') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')) anon_exec,
  (select count(*) from pg_constraint where connamespace = 'public'::regnamespace and contype = 'f' and confdeltype = 'c') fk_cascade,
  (select count(*) from pg_tables where schemaname = 'public') public_tables,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.courses x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.courses_pre007b x) courses_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.questions x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.questions_pre007b x) questions_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.course_id, x.org_id), '')) from public.exam_configs x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.course_id, x.org_id), '')) from backup.exam_configs_pre007b x) exam_configs_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.exam_attempts x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.exam_attempts_pre007b x) attempts_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.certificates x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.certificates_pre007b x) certificates_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.employees x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.employees_pre007b x) employees_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.learning_paths x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.learning_paths_pre007b x) paths_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.path_id, x.course_id), '')) from public.learning_path_courses x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.path_id, x.course_id), '')) from backup.learning_path_courses_pre007b x) path_courses_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.course_assignments x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.course_assignments_pre007b x) assignments_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.lesson_progress x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.lesson_progress_pre007b x) progress_same,
  (select count(*) from public.profiles) = (select live_rows from backup.tables_pre007b where tablename = 'profiles') profiles_same_count,
  (select count(*) from public.audit_logs where action like 'learning_path.%') lp_audits
)
select json_build_object(
  'ok', m007b = 1 and m007a = 1 and lpa and lpa_rls and lpa_cols = 18 and rules = 0 and write_grants = 0 and anon_grants = 0 and rpc_auth and not rpc_anon and internal_auth = 0
        and anon_exec = 'verify_certificate' and fk_cascade = 0 and public_tables = 45
        and courses_same and questions_same and exam_configs_same and attempts_same and certificates_same and employees_same and paths_same and path_courses_same and assignments_same and progress_same
        and (c.j ->> 'functions_missing') = '-' and (c.j ->> 'functions_def_changed')::int = 0 and (c.j ->> 'triggers_diff')::int = 1
        and (c.j ->> 'indexes_diff')::int = 4 and (c.j ->> 'columns_diff')::int = 18 and (c.j ->> 'policies_diff')::int = 1
        and (c.j ->> 'functions_extra') = (select string_agg(x, ',' order by x) from unnest(array['_lpa_apply_rule_007b(uuid)','_lpa_can_manage_007b()','apply_learning_path(uuid,text,text,date)','cancel_learning_path_assignment(uuid,text)','guard_lpa_007b()','reapply_learning_path_assignment(uuid)']) x),
  'm007b', m007b, 'lpa_table', lpa, 'rls', lpa_rls, 'columns', lpa_cols, 'rules', rules, 'write_grants', write_grants, 'rpc_auth', rpc_auth, 'rpc_anon', rpc_anon,
  'internal_auth', internal_auth, 'anon_exec', anon_exec, 'fk_cascade', fk_cascade, 'public_tables', public_tables,
  'data_same', json_build_object('courses', courses_same, 'questions', questions_same, 'exam_configs', exam_configs_same, 'attempts', attempts_same, 'certificates', certificates_same,
     'employees', employees_same, 'paths', paths_same, 'path_courses', path_courses_same, 'assignments', assignments_same, 'progress', progress_same, 'profiles_count', profiles_same_count),
  'lp_audits', lp_audits, 'catalog_vs_backup', c.j)::text as verify_007b
from s, c;
