-- 007c dan keyingi tekshiruv — FAQAT SELECT (staging va production). 'ok' = true bo'lmasa — 99_rollback_007c.sql (alohida qaror bilan).
with c as (select (select json_build_object(
  'functions_extra', (select coalesce(string_agg(sig, ',' order by sig), '-') from (select p.oid::regprocedure::text sig from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' except select signature from backup.functions_pre007c) x),
  'functions_missing', (select coalesce(string_agg(signature, ',' order by signature), '-') from (select signature from backup.functions_pre007c except select p.oid::regprocedure::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f') x),
  'functions_def_changed', (select count(*) from backup.functions_pre007c b join pg_proc p on p.oid::regprocedure::text = b.signature where p.pronamespace = 'public'::regnamespace and (pg_get_functiondef(p.oid) <> b.def or has_function_privilege('anon', p.oid, 'execute') <> b.anon_exec or has_function_privilege('authenticated', p.oid, 'execute') <> b.auth_exec)),
  'triggers_diff', (select count(*) from ((select c.relname, t.tgname, pg_get_triggerdef(t.oid) from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'public'::regnamespace and not t.tgisinternal except select tablename, tgname, def from backup.triggers_pre007c)
                    union all (select tablename, tgname, def from backup.triggers_pre007c except select c.relname, t.tgname, pg_get_triggerdef(t.oid) from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'public'::regnamespace and not t.tgisinternal)) x),
  'indexes_diff', (select count(*) from ((select tablename, indexname, indexdef from pg_indexes where schemaname = 'public' except select tablename, indexname, indexdef from backup.indexes_pre007c)
                   union all (select tablename, indexname, indexdef from backup.indexes_pre007c except select tablename, indexname, indexdef from pg_indexes where schemaname = 'public')) x),
  'columns_diff', (select count(*) from ((select table_name::text, column_name::text, data_type::text, is_nullable::text, column_default::text from information_schema.columns where table_schema = 'public' except select table_name, column_name, data_type, is_nullable, column_default from backup.columns_pre007c)
                   union all (select table_name, column_name, data_type, is_nullable, column_default from backup.columns_pre007c except select table_name::text, column_name::text, data_type::text, is_nullable::text, column_default::text from information_schema.columns where table_schema = 'public')) x),
  'policies_diff', (select count(*) from ((select tablename, policyname, cmd, qual, with_check from pg_policies where schemaname = 'public' except select tablename, policyname, cmd, qual, with_check from backup.policies_pre007c)
                    union all (select tablename, policyname, cmd, qual, with_check from backup.policies_pre007c except select tablename, policyname, cmd, qual, with_check from pg_policies where schemaname = 'public')) x)))::json j),
s as (select
  (select count(*) from public.schema_migrations where version = '007c') m007c,
  (select count(*) from public.schema_migrations where version = '007b') m007b,
  (select count(*) from pg_class where oid in (to_regclass('public.skills'), to_regclass('public.skill_assessments'), to_regclass('public.competency_requirements')) and relrowsecurity) rls_tables,
  (select count(*) from public.skills) + (select count(*) from public.skill_assessments) + (select count(*) from public.competency_requirements) rows_007c,
  (select count(*) from information_schema.role_table_grants where table_schema = 'public' and table_name in ('skills','skill_assessments','competency_requirements') and grantee in ('anon','authenticated') and privilege_type <> 'SELECT') write_grants,
  (select count(*) from information_schema.role_table_grants where table_schema = 'public' and table_name in ('skills','skill_assessments','competency_requirements') and grantee = 'anon') anon_grants,
  (select count(*) from pg_policies where schemaname = 'public' and tablename in ('skills','skill_assessments','competency_requirements') and cmd <> 'SELECT') write_policies,
  (select count(*) from public.permissions where key in ('skill.view','skill.manage','skill.assess','competency.manage')) perms,
  (select count(*) from public.organizations) orgs,
  (select count(*) from public.role_permissions where permission_key in ('skill.view','skill.manage','skill.assess','competency.manage')) role_perms,
  (select count(*) from pg_proc p join backup.function_categories_005d f on f.name = p.proname where p.pronamespace = 'public'::regnamespace and f.category = 'internal' and has_function_privilege('authenticated', p.oid, 'EXECUTE')) internal_auth,
  (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and p.oid::regprocedure::text not in (select signature from backup.functions_pre007c) and not exists (select 1 from backup.function_categories_005d f where f.name = p.proname)) uncategorized,
  (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('upsert_skill','archive_skill','record_skill_assessment','set_competency_requirement','archive_competency_requirement','employee_competency_summary','department_competency_summary') and has_function_privilege('authenticated', p.oid, 'EXECUTE') and not has_function_privilege('anon', p.oid, 'EXECUTE')) rpc_ok,
  (select coalesce(string_agg(p.proname, ',' order by p.proname), '-') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')) anon_exec,
  (select count(*) from pg_constraint where connamespace = 'public'::regnamespace and contype = 'f' and confdeltype = 'c') fk_cascade,
  (select count(*) from pg_tables where schemaname = 'public') public_tables,
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and prokind = 'f') functions,
  (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'public'::regnamespace and not t.tgisinternal) triggers,
  (select count(*) from pg_policies where schemaname = 'public') policies,
  (select count(*) from pg_indexes where schemaname = 'public') indexes,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.courses x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.courses_pre007c x) courses_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.questions x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.questions_pre007c x) questions_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.exam_attempts x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.exam_attempts_pre007c x) attempts_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.certificates x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.certificates_pre007c x) certificates_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.employees x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.employees_pre007c x) employees_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.course_assignments x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.course_assignments_pre007c x) assignments_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.learning_path_assignments x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.learning_path_assignments_pre007c x) lpa_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.lesson_progress x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.lesson_progress_pre007c x) progress_same,
  (select count(*) from public.role_permissions x where permission_key not in ('skill.view','skill.manage','skill.assess','competency.manage')) = (select count(*) from backup.role_permissions_pre007c) old_role_perms_same
)
select json_build_object(
  'ok', m007c = 1 and m007b = 1 and rls_tables = 3 and rows_007c = 0 and write_grants = 0 and anon_grants = 0 and write_policies = 0 and perms = 4
        and role_perms = orgs * 8 and internal_auth = 0 and uncategorized = 0 and rpc_ok = 7 and anon_exec = 'verify_certificate' and fk_cascade = 0
        and public_tables = 48 and courses_same and questions_same and attempts_same and certificates_same and employees_same and assignments_same and lpa_same and progress_same and old_role_perms_same
        and functions = (select count(*) from backup.functions_pre007c) + 16 and triggers = (select count(*) from backup.triggers_pre007c) + 5
        and (c.j ->> 'functions_missing') = '-' and (c.j ->> 'functions_def_changed')::int = 0 and (c.j ->> 'triggers_diff')::int = 5
        and (c.j ->> 'indexes_diff')::int = 9 and (c.j ->> 'columns_diff')::int = 40 and (c.j ->> 'policies_diff')::int = 3
        and (c.j ->> 'functions_extra') = '_sk_can_view_employee_007c(uuid),_sk_emp_competency_007c(uuid,uuid[]),_sk_my_dept_employees_007c(),_sk_seed_perms_007c(uuid),archive_competency_requirement(uuid,text),archive_skill(uuid,text),department_competency_summary(uuid),employee_competency_summary(uuid),guard_competency_req_007c(),guard_skill_007c(),guard_skill_assessment_007c(),guard_skill_assessment_truncate_007c(),record_skill_assessment(uuid,uuid,integer,text),seed_org_skill_perms_007c(),set_competency_requirement(uuid,text,text,integer),upsert_skill(uuid,text,text,text,text,uuid,integer)',
  'm007c', m007c, 'rls_tables', rls_tables, 'rows_007c', rows_007c, 'write_grants', write_grants, 'anon_grants', anon_grants, 'write_policies', write_policies,
  'perms', perms, 'orgs', orgs, 'role_perms', role_perms, 'internal_auth', internal_auth, 'uncategorized', uncategorized, 'rpc_ok', rpc_ok, 'anon_exec', anon_exec, 'fk_cascade', fk_cascade,
  'counts', json_build_object('tables', public_tables, 'functions', functions, 'triggers', triggers, 'policies', policies, 'indexes', indexes),
  'data_same', json_build_object('courses', courses_same, 'questions', questions_same, 'attempts', attempts_same, 'certificates', certificates_same, 'employees', employees_same,
     'assignments', assignments_same, 'lpa', lpa_same, 'progress', progress_same, 'old_role_permissions', old_role_perms_same),
  'catalog_vs_backup', c.j, 'at', clock_timestamp())::text as verify_007c
from s, c;
