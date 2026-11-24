-- FAQAT REAL INCIDENT UCHUN: Migration 006b ni bekor qilish. Ma'lumot o'zgarmaydi.
begin;
drop trigger if exists courses_no_delete_006b_trg on public.courses;
drop function if exists public.guard_course_delete_006b();
drop function if exists public.admin_set_course_status(text, text, text);
do $$ begin
  if to_regclass('backup.function_categories_005d') is not null then
    delete from backup.function_categories_005d where name in ('guard_course_delete_006b', 'admin_set_course_status');
  end if;
end $$;
delete from public.schema_migrations where version = '006b';
commit;
select json_build_object('migration_006b', (select count(*) from public.schema_migrations where version = '006b'),
  'trigger', (select count(*) from pg_trigger where tgname = 'courses_no_delete_006b_trg'), 'courses', (select count(*) from public.courses))::text as rollback_006b;
