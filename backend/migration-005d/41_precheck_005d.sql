-- PRODUCTION 005d PRECHECK — FAQAT SELECT. Kutilgan baseline bilan solishtiradi; birorta 'ok' false bo'lsa — STOP.
with c as (select
  (select count(*) from public.profiles) profiles, (select count(*) from public.docs) docs, (select count(*) from public.courses) courses,
  (select count(*) from public.questions) questions, (select count(*) from public.exam_configs) exam_configs, (select count(*) from public.exam_attempts) exam_attempts,
  (select count(*) from public.certificates) certificates, (select count(*) from public.attempt_resets) attempt_resets, (select count(*) from public.employees) employees,
  (select count(*) from public.audit_logs) audit_logs,
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and prokind = 'f' and has_function_privilege('anon', oid, 'execute')) anon_exec,
  (select count(*) from pg_constraint where contype = 'f' and confdeltype = 'c' and conname in ('profiles_id_fkey','docs_owner_fkey','exam_attempts_user_id_fkey','certificates_user_id_fkey','attempt_resets_user_id_fkey','exam_configs_course_id_fkey')) cascade6,
  (select count(*) from pg_policies where schemaname = 'public') policies,
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and prokind = 'f') functions,
  (select count(*) from public.profiles where status in ('inactive','deactivated')) lifecycle_rows,
  (select count(*) from public.schema_migrations where version = '005d') m005d,
  (select count(*) from backup.tables_pre005d_20261123) backup_tables,
  (select sum(live_rows) from backup.tables_pre005d_20261123 where tablename = 'docs') backup_docs)
select jsonb_build_object('counts', to_jsonb(c), 'ok', jsonb_build_object(
  'courses_13', courses = 13, 'questions_131', questions = 131, 'exam_configs_13', exam_configs = 13, 'exam_attempts_2', exam_attempts = 2, 'certificates_0', certificates = 0,
  'docs_eq_backup', docs = backup_docs, 'anon_58', anon_exec = 58, 'cascade6_6', cascade6 = 6, 'policies_97', policies = 97, 'functions_69', functions = 69,
  'no_lifecycle_rows', lifecycle_rows = 0, 'not_applied', m005d = 0, 'backup_43', backup_tables = 43))::text as precheck from c;
