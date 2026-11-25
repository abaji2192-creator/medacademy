-- PRODUCTION: 007a dan keyingi tekshiruv — FAQAT SELECT. 'ok' = true bo'lmasa — 79_rollback_007a.sql (alohida qaror bilan).
with c as (select (select json_build_object(
  'functions_extra', (select coalesce(string_agg(sig, ',' order by sig), '-') from (select p.oid::regprocedure::text sig from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' except select signature from backup.functions_pre007a) x),
  'functions_missing', (select coalesce(string_agg(signature, ',' order by signature), '-') from (select signature from backup.functions_pre007a except select p.oid::regprocedure::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f') x),
  'functions_def_changed', (select count(*) from backup.functions_pre007a b join pg_proc p on p.oid::regprocedure::text = b.signature where p.pronamespace = 'public'::regnamespace and (pg_get_functiondef(p.oid) <> b.def or has_function_privilege('anon', p.oid, 'execute') <> b.anon_exec or has_function_privilege('authenticated', p.oid, 'execute') <> b.auth_exec)),
  'triggers_diff', (select count(*) from ((select c.relname, t.tgname, pg_get_triggerdef(t.oid) from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'public'::regnamespace and not t.tgisinternal except select tablename, tgname, def from backup.triggers_pre007a)
                    union all (select tablename, tgname, def from backup.triggers_pre007a except select c.relname, t.tgname, pg_get_triggerdef(t.oid) from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'public'::regnamespace and not t.tgisinternal)) x),
  'indexes_diff', (select count(*) from ((select tablename, indexname, indexdef from pg_indexes where schemaname = 'public' except select tablename, indexname, indexdef from backup.indexes_pre007a)
                   union all (select tablename, indexname, indexdef from backup.indexes_pre007a except select tablename, indexname, indexdef from pg_indexes where schemaname = 'public')) x),
  'columns_diff', (select count(*) from ((select table_name::text, column_name::text, data_type::text, is_nullable::text, column_default::text from information_schema.columns where table_schema = 'public' except select table_name, column_name, data_type, is_nullable, column_default from backup.columns_pre007a)
                   union all (select table_name, column_name, data_type, is_nullable, column_default from backup.columns_pre007a except select table_name::text, column_name::text, data_type::text, is_nullable::text, column_default::text from information_schema.columns where table_schema = 'public')) x),
  'policies_diff', (select count(*) from ((select tablename, policyname, cmd, qual, with_check from pg_policies where schemaname = 'public' except select tablename, policyname, cmd, qual, with_check from backup.policies_pre007a)
                    union all (select tablename, policyname, cmd, qual, with_check from backup.policies_pre007a except select tablename, policyname, cmd, qual, with_check from pg_policies where schemaname = 'public')) x),
  'migration_007a', (select count(*) from public.schema_migrations where version = '007a'),
  'x', 0))::json j),
s as (select
  (select count(*) from public.schema_migrations where version = '007a') m007a,
  (select is_nullable || '/' || column_default from information_schema.columns where table_schema = 'public' and table_name = 'lessons' and column_name = 'is_required') is_required,
  (select count(*) from public.lessons where not is_required) optional_lessons,
  (select count(*) from pg_trigger where tgname = 'lesson_progress_completion_007a_trg' and tgrelid = 'public.lesson_progress'::regclass) trg,
  (select count(*) from pg_indexes where schemaname = 'public' and indexname in ('lesson_progress_completed_007a_idx', 'course_assignments_course_007a_idx')) idx,
  has_function_privilege('authenticated', 'public.my_learning_progress()'::regprocedure, 'execute') mlp_auth,
  has_function_privilege('anon', 'public.my_learning_progress()'::regprocedure, 'execute') mlp_anon,
  has_function_privilege('authenticated', 'public.course_progress_summary(text)'::regprocedure, 'execute') cps_auth,
  has_function_privilege('anon', 'public.course_progress_summary(text)'::regprocedure, 'execute') cps_anon,
  (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_lp_course_stats_007a', '_lp_status_007a', 'lesson_progress_completion_007a') and has_function_privilege('authenticated', p.oid, 'execute')) internal_auth,
  (select coalesce(string_agg(p.proname, ',' order by p.proname), '-') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')) anon_exec,
  (select count(*) from pg_constraint where connamespace = 'public'::regnamespace and contype = 'f' and confdeltype = 'c') fk_cascade,
  (select count(*) from pg_tables where schemaname = 'public') public_tables,
  (select count(*) from public.courses) courses, (select count(*) from public.questions) questions, (select count(*) from public.exam_configs) exam_configs,
  (select count(*) from public.exam_attempts) attempts, (select count(*) from public.certificates) certificates,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.questions x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.questions_pre007a x) questions_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.courses x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.courses_pre007a x) courses_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.course_id, x.org_id), '')) from public.exam_configs x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.course_id, x.org_id), '')) from backup.exam_configs_pre007a x) exam_configs_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.exam_attempts x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.exam_attempts_pre007a x) attempts_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.certificates x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.certificates_pre007a x) certificates_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.course_modules x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.course_modules_pre007a x) modules_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.course_assignments x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.course_assignments_pre007a x) assignments_same,
  (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.lesson_progress x) = (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from backup.lesson_progress_pre007a x) progress_same,
  (select md5(coalesce(string_agg(x.id||x.module_id||x.title||x.status||x.order_index, '' order by x.id), '')) from public.lessons x)
    = (select md5(coalesce(string_agg(x.id||x.module_id||x.title||x.status||x.order_index, '' order by x.id), '')) from backup.lessons_pre007a x) lessons_same,
  (select count(*) from public.audit_logs where action = 'course.completed') course_completed_audits
)
select json_build_object(
  'ok', m007a = 1 and is_required = 'NO/true' and optional_lessons = 0 and trg = 1 and idx = 2 and mlp_auth and not mlp_anon and cps_auth and not cps_anon
        and internal_auth = 0 and anon_exec = 'verify_certificate' and fk_cascade = 0 and public_tables = 44
        and courses = (select live_rows from backup.tables_pre007a where tablename = 'courses') and questions = (select live_rows from backup.tables_pre007a where tablename = 'questions')
        and exam_configs = (select live_rows from backup.tables_pre007a where tablename = 'exam_configs') and attempts = (select live_rows from backup.tables_pre007a where tablename = 'exam_attempts')
        and certificates = (select live_rows from backup.tables_pre007a where tablename = 'certificates')
        and questions_same and courses_same and exam_configs_same and attempts_same and certificates_same and modules_same and assignments_same and progress_same and lessons_same
        and (c.j ->> 'functions_missing') = '-' and (c.j ->> 'functions_def_changed')::int = 0 and (c.j ->> 'triggers_diff')::int = 1
        and (c.j ->> 'indexes_diff')::int = 2 and (c.j ->> 'columns_diff')::int = 1 and (c.j ->> 'policies_diff')::int = 0
        and (c.j ->> 'functions_extra') = (select string_agg(x, ',' order by x) from unnest(array['_lp_course_stats_007a(uuid,text)','_lp_status_007a(text,date,integer,integer,boolean)','course_progress_summary(text)','lesson_progress_completion_007a()','my_learning_progress()']) x),
  'm007a', m007a, 'is_required', is_required, 'optional_lessons', optional_lessons, 'trigger', trg, 'indexes', idx,
  'rpc_auth', mlp_auth and cps_auth, 'rpc_anon', mlp_anon or cps_anon, 'internal_auth', internal_auth, 'anon_exec', anon_exec, 'fk_cascade', fk_cascade,
  'public_tables', public_tables, 'counts', json_build_array(courses, questions, exam_configs, attempts, certificates),
  'data_same', json_build_object('questions', questions_same, 'courses', courses_same, 'exam_configs', exam_configs_same, 'attempts', attempts_same, 'certificates', certificates_same,
     'modules', modules_same, 'lessons', lessons_same, 'assignments', assignments_same, 'progress', progress_same),
  'course_completed_audits', course_completed_audits, 'catalog_vs_backup', c.j)::text as verify_007a
from s, c;
