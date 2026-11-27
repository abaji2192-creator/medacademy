-- 007e dan keyingi tekshiruv — FAQAT SELECT (staging va production). 'ok' = true bo'lmasa — 119_rollback_007e.sql (alohida qaror bilan).
with c as (select (select json_build_object(
  'functions_extra', (select coalesce(string_agg(sig, ',' order by sig), '-') from (select p.oid::regprocedure::text sig from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' except select signature from backup.functions_pre007e) x),
  'functions_missing', (select coalesce(string_agg(signature, ',' order by signature), '-') from (select signature from backup.functions_pre007e except select p.oid::regprocedure::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f') x),
  'functions_def_changed', (select count(*) from backup.functions_pre007e b join pg_proc p on p.oid::regprocedure::text = b.signature where p.pronamespace = 'public'::regnamespace and (pg_get_functiondef(p.oid) <> b.def or has_function_privilege('anon', p.oid, 'execute') <> b.anon_exec or has_function_privilege('authenticated', p.oid, 'execute') <> b.auth_exec)),
  'triggers_diff', (select count(*) from ((select c.relname, t.tgname, pg_get_triggerdef(t.oid) from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'public'::regnamespace and not t.tgisinternal except select tablename, tgname, def from backup.triggers_pre007e)
                    union all (select tablename, tgname, def from backup.triggers_pre007e except select c.relname, t.tgname, pg_get_triggerdef(t.oid) from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'public'::regnamespace and not t.tgisinternal)) x),
  'indexes_diff', (select count(*) from ((select tablename, indexname, indexdef from pg_indexes where schemaname = 'public' except select tablename, indexname, indexdef from backup.indexes_pre007e)
                   union all (select tablename, indexname, indexdef from backup.indexes_pre007e except select tablename, indexname, indexdef from pg_indexes where schemaname = 'public')) x),
  'columns_diff', (select count(*) from ((select table_name::text, column_name::text, data_type::text, is_nullable::text, column_default::text from information_schema.columns where table_schema = 'public' except select table_name, column_name, data_type, is_nullable, column_default from backup.columns_pre007e)
                   union all (select table_name, column_name, data_type, is_nullable, column_default from backup.columns_pre007e except select table_name::text, column_name::text, data_type::text, is_nullable::text, column_default::text from information_schema.columns where table_schema = 'public')) x),
  'policies_diff', (select count(*) from ((select tablename, policyname, cmd, qual, with_check from pg_policies where schemaname = 'public' except select tablename, policyname, cmd, qual, with_check from backup.policies_pre007e)
                    union all (select tablename, policyname, cmd, qual, with_check from backup.policies_pre007e except select tablename, policyname, cmd, qual, with_check from pg_policies where schemaname = 'public')) x)))::json j),
s as (select
  (select count(*) from public.schema_migrations where version = '007e') m007e,
  (select count(*) from public.schema_migrations where version = '007d') m007d,
  (select count(*) from public.permissions) perms_total, (select count(*) from backup.permissions_pre007e) perms_before,
  (select count(*) from public.role_permissions) role_perms, (select count(*) from backup.role_permissions_pre007e) role_perms_before,
  (select count(*) from pg_proc p join backup.function_categories_005d f on f.name = p.proname where p.pronamespace = 'public'::regnamespace and f.category = 'internal' and has_function_privilege('authenticated', p.oid, 'EXECUTE')) internal_auth,
  (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and p.oid::regprocedure::text not in (select signature from backup.functions_pre007e) and not exists (select 1 from backup.function_categories_005d f where f.name = p.proname)) uncategorized,
  (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('employee_training_compliance','employee_competency_matrix','department_compliance_matrix') and has_function_privilege('authenticated', p.oid, 'EXECUTE') and not has_function_privilege('anon', p.oid, 'EXECUTE')) rpc_ok,
  (select coalesce(string_agg(p.proname, ',' order by p.proname), '-') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')) anon_exec,
  (select count(*) from pg_constraint where connamespace = 'public'::regnamespace and contype = 'f' and confdeltype = 'c') fk_cascade,
  (select count(*) from pg_tables where schemaname = 'public') public_tables,
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and prokind = 'f') functions,
  (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'public'::regnamespace and not t.tgisinternal) triggers,
  (select count(*) from pg_policies where schemaname = 'public') policies,
  (select count(*) from pg_indexes where schemaname = 'public') indexes,
  (select count(*) from backup.tables_pre007e t where not exists (select 1 from pg_tables p where p.schemaname = 'public' and p.tablename = t.tablename)) tables_missing,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.courses x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.courses_pre007e x) courses_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.questions x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.questions_pre007e x) questions_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.exam_attempts x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.exam_attempts_pre007e x) attempts_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.certificates x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.certificates_pre007e x) certificates_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.employees x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.employees_pre007e x) employees_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.profiles x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.profiles_pre007e x) profiles_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.course_assignments x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.course_assignments_pre007e x) assignments_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.learning_path_assignments x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.learning_path_assignments_pre007e x) lpa_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.lesson_progress x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.lesson_progress_pre007e x) progress_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.skills x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.skills_pre007e x) skills_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.skill_assessments x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.skill_assessments_pre007e x) assessments_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.competency_requirements x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.competency_requirements_pre007e x) reqs_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.notifications x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.notifications_pre007e x) notifications_same,
  (select count(*) from public.audit_logs) = (select count(*) from backup.audit_logs_pre007e) audit_same,
  (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname like '%\_007e' or p.proname in ('employee_training_compliance','employee_competency_matrix','department_compliance_matrix'))
     and p.provolatile = 's' and p.prosecdef and array_to_string(p.proconfig, ',') like '%search_path=public%') hardened,
  (select count(*) from pg_trigger where tgname like '%007e%') triggers_007e,
  (select count(*) from pg_class where relnamespace = 'public'::regnamespace and relname ~ '(compliance|matrix|007e)') relations_007e

)
select json_build_object(
  'ok', m007e = 1 and m007d = 1 and perms_total = perms_before and role_perms = role_perms_before and internal_auth = 0 and uncategorized = 0 and rpc_ok = 3
        and hardened = 6 and triggers_007e = 0 and relations_007e = 0
        and anon_exec = 'verify_certificate' and fk_cascade = 0 and public_tables = (select count(*) from backup.tables_pre007e) and tables_missing = 0
        and courses_same and questions_same and attempts_same and certificates_same and employees_same and profiles_same and assignments_same and lpa_same
        and progress_same and skills_same and assessments_same and reqs_same and notifications_same and audit_same
        and functions = (select count(*) from backup.functions_pre007e) + 6 and triggers = (select count(*) from backup.triggers_pre007e)
        and (c.j ->> 'functions_missing') = '-' and (c.j ->> 'functions_def_changed')::int = 0 and (c.j ->> 'triggers_diff')::int = 0
        and (c.j ->> 'indexes_diff')::int = 0 and (c.j ->> 'columns_diff')::int = 0 and (c.j ->> 'policies_diff')::int = 0
        and (c.j ->> 'functions_extra') = '_cmp_can_view_training_007e(uuid),_cmp_emp_json_007e(uuid),_cmp_training_007e(uuid,uuid[]),department_compliance_matrix(uuid),employee_competency_matrix(uuid),employee_training_compliance(uuid)',
  'm007e', m007e, 'perms_same', perms_total = perms_before, 'role_perms_same', role_perms = role_perms_before, 'internal_auth', internal_auth,
  'uncategorized', uncategorized, 'rpc_ok', rpc_ok, 'hardened', hardened, 'triggers_007e', triggers_007e, 'relations_007e', relations_007e,
  'anon_exec', anon_exec, 'fk_cascade', fk_cascade,
  'counts', json_build_object('tables', public_tables, 'functions', functions, 'triggers', triggers, 'policies', policies, 'indexes', indexes),
  'data_same', json_build_object('courses', courses_same, 'questions', questions_same, 'attempts', attempts_same, 'certificates', certificates_same,
     'employees', employees_same, 'profiles', profiles_same, 'assignments', assignments_same, 'lpa', lpa_same, 'progress', progress_same,
     'skills', skills_same, 'assessments', assessments_same, 'requirements', reqs_same, 'notifications', notifications_same, 'audit_logs', audit_same),
  'catalog_vs_backup', c.j, 'at', clock_timestamp())::text as verify_007e
from s, c;
