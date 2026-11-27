-- Phase 3 Frontend STEP 2 — Admin Panel uchun production backend READ-ONLY smoke (hech qanday yozish yo'q).
-- UI chaqiradigan RPC'lar mavjudligi, grant'lar va UI o'qiydigan jadvallarda RLS yoqilganligi.
begin;
set transaction read only;
with f(name) as (values ('apply_learning_path'), ('reapply_learning_path_assignment'), ('cancel_learning_path_assignment'), ('course_progress_summary'),
  ('upsert_skill'), ('archive_skill'), ('record_skill_assessment'), ('set_competency_requirement'), ('archive_competency_requirement'),
  ('employee_training_compliance'), ('employee_competency_matrix'), ('department_compliance_matrix'),
  ('my_notifications'), ('unread_notification_count'), ('mark_notification_read'), ('mark_all_notifications_read')),
p as (select f.name, pr.oid, pr.prosecdef from f left join pg_proc pr on pr.proname = f.name and pr.pronamespace = 'public'::regnamespace),
t(name) as (values ('learning_paths'), ('learning_path_courses'), ('learning_path_assignments'), ('course_assignments'), ('skills'),
  ('competency_requirements'), ('skill_assessments'), ('notifications'), ('employees'), ('departments'))
select jsonb_build_object(
  'rpc_total', (select count(*) from f),
  'rpc_missing', (select coalesce(jsonb_agg(name), '[]') from p where oid is null),
  'rpc_not_definer', (select coalesce(jsonb_agg(name), '[]') from p where oid is not null and not prosecdef),
  'rpc_auth_exec_missing', (select coalesce(jsonb_agg(name), '[]') from p where oid is not null and not has_function_privilege('authenticated', oid, 'execute')),
  'rpc_anon_exec', (select coalesce(jsonb_agg(name), '[]') from p where oid is not null and has_function_privilege('anon', oid, 'execute')),
  'tables_rls_off', (select coalesce(jsonb_agg(t.name), '[]') from t join pg_class c on c.relname = t.name and c.relnamespace = 'public'::regnamespace where not c.relrowsecurity),
  'anon_can_select', (select coalesce(jsonb_agg(t.name), '[]') from t where has_table_privilege('anon', 'public.' || t.name, 'select')
                        and exists (select 1 from pg_policies pp where pp.schemaname = 'public' and pp.tablename = t.name and 'anon' = any(pp.roles))),
  'migrations_last', (select max(version) from public.schema_migrations),
  'counts', jsonb_build_object('tables', (select count(*) from pg_tables where schemaname = 'public'),
     'functions', (select count(*) from pg_proc where pronamespace = 'public'::regnamespace),
     'policies', (select count(*) from pg_policies where schemaname = 'public'))) as smoke;
rollback;
