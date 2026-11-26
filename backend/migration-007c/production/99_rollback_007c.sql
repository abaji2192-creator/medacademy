-- FAQAT REAL INCIDENT UCHUN: Migration 007c ni bekor qilish.
-- Xavfsizlik: agar 007c jadvallarida ma'lumot (ko'nikma / baholash / talab) bo'lsa, rollback TO'XTAYDI — avval eksport qiling
-- (baholashlar tarixi o'zgarmas va yo'qotilmasligi kerak).
-- Olib tashlanadi: 007c jadvallari, trigger'lari, funksiyalari, organizations trigger'i, 4 ruxsat va ularning rol bog'lanishlari, schema_migrations '007c'.
-- Tegilmaydi: 007a / 007b / Phase 2 obyektlari va ma'lumotlari.
begin;
do $$ begin
  if to_regclass('public.skill_assessments') is not null and (
       exists (select 1 from public.skill_assessments) or exists (select 1 from public.skills) or exists (select 1 from public.competency_requirements)) then
    raise exception '007c rollback to''xtatildi: 007c ma''lumotlari mavjud — avval eksport qiling';
  end if;
end $$;
drop function if exists public.upsert_skill(uuid, text, text, text, text, uuid, int);
drop function if exists public.archive_skill(uuid, text);
drop function if exists public.record_skill_assessment(uuid, uuid, int, text);
drop function if exists public.set_competency_requirement(uuid, text, text, int);
drop function if exists public.archive_competency_requirement(uuid, text);
drop function if exists public.employee_competency_summary(uuid);
drop function if exists public.department_competency_summary(uuid);
drop function if exists public._sk_emp_competency_007c(uuid, uuid[]);
drop table if exists public.competency_requirements;
drop table if exists public.skill_assessments;
drop table if exists public.skills;
drop function if exists public._sk_can_view_employee_007c(uuid);
drop function if exists public._sk_my_dept_employees_007c();
drop function if exists public.guard_competency_req_007c();
drop function if exists public.guard_skill_assessment_truncate_007c();
drop function if exists public.guard_skill_assessment_007c();
drop function if exists public.guard_skill_007c();
drop trigger if exists org_skill_perms_007c_trg on public.organizations;
drop function if exists public.seed_org_skill_perms_007c();
drop function if exists public._sk_seed_perms_007c(uuid);
delete from public.role_permissions where permission_key in ('skill.view', 'skill.manage', 'skill.assess', 'competency.manage');
delete from public.permissions where key in ('skill.view', 'skill.manage', 'skill.assess', 'competency.manage');
do $$ begin
  if to_regclass('backup.function_categories_005d') is not null then
    delete from backup.function_categories_005d where name in ('_sk_seed_perms_007c', 'seed_org_skill_perms_007c', 'guard_skill_007c', 'guard_skill_assessment_007c',
      'guard_skill_assessment_truncate_007c', 'guard_competency_req_007c', '_sk_can_view_employee_007c', '_sk_my_dept_employees_007c', '_sk_emp_competency_007c', 'upsert_skill', 'archive_skill',
      'record_skill_assessment', 'set_competency_requirement', 'archive_competency_requirement', 'employee_competency_summary', 'department_competency_summary');
  end if;
end $$;
delete from public.schema_migrations where version = '007c';
commit;
select json_build_object('migration_007c', (select count(*) from public.schema_migrations where version = '007c'),
  'tables', (select count(*) from pg_tables where schemaname = 'public' and tablename in ('skills', 'skill_assessments', 'competency_requirements')),
  'permissions', (select count(*) from public.permissions where key in ('skill.view', 'skill.manage', 'skill.assess', 'competency.manage')))::text as rollback_007c;
