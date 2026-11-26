-- FAQAT REAL INCIDENT UCHUN: Migration 007b ni bekor qilish.
-- Olib tashlanadi: 007b'ning o'z obyektlari (learning_path_assignments jadvali — 007b qoidalari, uning trigger / policy / indekslari,
-- 007b funksiyalari, employees_org_dept_007b_idx, schema_migrations '007b').
-- SAQLANADI: 007b yaratgan course_assignments qatorlari, audit_logs (learning_path.*), lesson_progress, 007a va Phase 2 obyektlari.
begin;
drop function if exists public.apply_learning_path(uuid, text, text, date);
drop function if exists public.reapply_learning_path_assignment(uuid);
drop function if exists public.cancel_learning_path_assignment(uuid, text);
drop function if exists public._lpa_apply_rule_007b(uuid);
drop function if exists public._lpa_can_manage_007b();
drop table if exists public.learning_path_assignments;
drop function if exists public.guard_lpa_007b();
drop index if exists public.employees_org_dept_007b_idx;
do $$ begin
  if to_regclass('backup.function_categories_005d') is not null then
    delete from backup.function_categories_005d where name in ('guard_lpa_007b', '_lpa_apply_rule_007b', '_lpa_can_manage_007b', 'apply_learning_path', 'reapply_learning_path_assignment', 'cancel_learning_path_assignment');
  end if;
end $$;
delete from public.schema_migrations where version = '007b';
commit;
select json_build_object('migration_007b', (select count(*) from public.schema_migrations where version = '007b'),
  'table', to_regclass('public.learning_path_assignments') is not null,
  'functions', (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('apply_learning_path', 'reapply_learning_path_assignment', 'cancel_learning_path_assignment', '_lpa_apply_rule_007b', '_lpa_can_manage_007b', 'guard_lpa_007b')))::text as rollback_007b;
