-- FAQAT REAL INCIDENT UCHUN: Migration 007a ni bekor qilish.
-- Tarixiy qatorlar o'chirilmaydi: course_assignments holatlari ('completed'), audit_logs (course.completed) va lesson_progress saqlanadi.
-- Olib tashlanadi: 007a trigger'i, funksiyalari, indekslari, lessons.is_required ustuni (007a'ning o'z qiymati), schema_migrations '007a'.
begin;
drop trigger if exists lesson_progress_completion_007a_trg on public.lesson_progress;
drop function if exists public.lesson_progress_completion_007a();
drop function if exists public.my_learning_progress();
drop function if exists public.course_progress_summary(text);
drop function if exists public._lp_course_stats_007a(uuid, text);
drop function if exists public._lp_status_007a(text, date, int, int, boolean);
drop index if exists public.lesson_progress_completed_007a_idx;
drop index if exists public.course_assignments_course_007a_idx;
alter table public.lessons drop column if exists is_required;
do $$ begin
  if to_regclass('backup.function_categories_005d') is not null then
    delete from backup.function_categories_005d where name in ('_lp_course_stats_007a', '_lp_status_007a', 'lesson_progress_completion_007a', 'my_learning_progress', 'course_progress_summary');
  end if;
end $$;
delete from public.schema_migrations where version = '007a';
commit;
select json_build_object('migration_007a', (select count(*) from public.schema_migrations where version = '007a'),
  'is_required_column', (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'lessons' and column_name = 'is_required'),
  'trigger', (select count(*) from pg_trigger where tgname = 'lesson_progress_completion_007a_trg'))::text as rollback_007a;
