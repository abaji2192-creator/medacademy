-- MedAcademy · 007e rollback — faqat 007e funksiyalari olib tashlanadi. 007e ma'lumot saqlamaydi (faqat hisoblaydi),
-- shuning uchun hech qanday ma'lumot (course_assignments, lesson_progress, skill_assessments, competency_requirements, notifications, audit) o'zgarmaydi.
begin;
do $$ begin
  if not exists (select 1 from public.schema_migrations where version = '007e') then raise exception '007e rollback: 007e qo''llanmagan'; end if;
end $$;
drop function if exists public.department_compliance_matrix(uuid);
drop function if exists public.employee_competency_matrix(uuid);
drop function if exists public.employee_training_compliance(uuid);
drop function if exists public._cmp_emp_json_007e(uuid);
drop function if exists public._cmp_can_view_training_007e(uuid);
drop function if exists public._cmp_training_007e(uuid, uuid[]);
do $$ begin
  if to_regclass('backup.function_categories_005d') is not null then
    delete from backup.function_categories_005d where name in ('_cmp_training_007e', '_cmp_can_view_training_007e', '_cmp_emp_json_007e',
      'employee_training_compliance', 'employee_competency_matrix', 'department_compliance_matrix');
  end if;
end $$;
delete from public.schema_migrations where version = '007e';
commit;
select json_build_object(
  'migration_007e', (select count(*) from public.schema_migrations where version = '007e'),
  'functions_left', (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and (proname like '%\_007e' or proname in
     ('employee_training_compliance', 'employee_competency_matrix', 'department_compliance_matrix')))
)::text as rollback_007e;
