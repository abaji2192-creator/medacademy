-- MedAcademy · 007d rollback — faqat 007d obyektlari. 007a / 007b / 007c obyektlari va ma'lumotlari, urinishlar, sertifikatlar o'zgarmaydi.
-- Bildirishnomalar o'chirilishidan oldin backup.notifications_rb007d ga to'liq nusxalanadi (tarix yo'qolmaydi). CASCADE ishlatilmaydi.
begin;

do $$ begin
  if not exists (select 1 from public.schema_migrations where version = '007d') then raise exception '007d rollback: 007d qo''llanmagan'; end if;
end $$;

create schema if not exists backup;
do $$ begin
  if to_regclass('public.notifications') is not null then
    if to_regclass('backup.notifications_rb007d') is null then
      create table backup.notifications_rb007d as select n.*, now() as rolled_back_at from public.notifications n;
    else
      insert into backup.notifications_rb007d select n.*, now() from public.notifications n
       where not exists (select 1 from backup.notifications_rb007d b where b.id = n.id);
    end if;
  end if;
end $$;

drop trigger if exists course_assignments_ntf_ins_007d on public.course_assignments;
drop trigger if exists course_assignments_ntf_upd_007d on public.course_assignments;
drop trigger if exists lpa_ntf_ins_007d on public.learning_path_assignments;
drop trigger if exists skill_assessments_ntf_ins_007d on public.skill_assessments;
drop trigger if exists certificates_ntf_ins_007d on public.certificates;
drop trigger if exists notifications_guard_007d on public.notifications;
drop trigger if exists notifications_truncate_guard_007d on public.notifications;

drop function if exists public.my_notifications(int, timestamptz, uuid, boolean);
drop function if exists public.unread_notification_count();
drop function if exists public.mark_notification_read(uuid, boolean);
drop function if exists public.mark_all_notifications_read();
drop function if exists public.ntf_course_assigned_007d();
drop function if exists public.ntf_course_completed_007d();
drop function if exists public.ntf_learning_path_assigned_007d();
drop function if exists public.ntf_skill_assessment_007d();
drop function if exists public.ntf_certificate_issued_007d();

drop policy if exists notifications_select_own_007d on public.notifications;
drop table if exists public.notifications;
drop function if exists public.guard_notification_007d();
drop function if exists public.guard_notification_truncate_007d();

do $$ begin
  if to_regclass('backup.function_categories_005d') is not null then
    delete from backup.function_categories_005d where name in ('guard_notification_007d', 'guard_notification_truncate_007d',
      'ntf_course_assigned_007d', 'ntf_course_completed_007d', 'ntf_learning_path_assigned_007d', 'ntf_skill_assessment_007d',
      'ntf_certificate_issued_007d', 'my_notifications', 'unread_notification_count', 'mark_notification_read', 'mark_all_notifications_read');
  end if;
end $$;
delete from public.schema_migrations where version = '007d';

commit;

select json_build_object(
  'migration_007d', (select count(*) from public.schema_migrations where version = '007d'),
  'table', to_regclass('public.notifications') is not null,
  'backed_up', (select count(*) from backup.notifications_rb007d),
  'functions_left', (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('my_notifications', 'unread_notification_count',
     'mark_notification_read', 'mark_all_notifications_read') or (pronamespace = 'public'::regnamespace and proname like '%\_007d'))
)::text as rollback_007d;
