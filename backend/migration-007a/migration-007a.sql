-- MedAcademy · Migration 007a — Learning Progress RPC Foundation (Phase 3 STEP 2)
-- 006b'dan keyin. 004 / 005 / 005d / 005e / 006a / 006b fayllari o'zgartirilmaydi. YANGI JADVAL YO'Q.
--
--   1. lessons.is_required boolean NOT NULL DEFAULT true — additive ustun (tasdiqlangan qaror: majburiy/ixtiyoriy belgisi).
--      Mavjud darslar majburiy bo'lib qoladi; ma'lumot qayta yozilmaydi (default qiymat).
--   2. Progress formulasi (server tomonida): kursdagi majburiy darslar = lessons.is_required AND lessons.status='published'
--      AND course_modules.status='published'. progress_percent = tugallangan majburiy / jami majburiy × 100 (0–100).
--      Ixtiyoriy darslar maxrajga kirmaydi va tugallashni bloklamaydi. Jami majburiy = 0 → progress 0, avtomatik tugallash YO'Q.
--   3. computed_status (o'qishda hisoblanadi, bazaga yozilmaydi): cancelled > completed > overdue > in_progress > not_started.
--      overdue = tugallanmagan, due_date mavjud va due_date < current_date (bugungi muddat — overdue emas).
--   4. my_learning_progress() — faqat joriy xodim (my_employee_id()), faqat o'z tashkiloti; minimal maydonlar.
--   5. course_progress_summary(p_course) — SA / EM / HR (progress.view, butun tashkilot), Department Head (faqat o'z bo'limi),
--      Instructor (faqat o'z kursi); boshqalar va anon — rad. Boshqa tashkilot kursi — "topilmadi".
--   6. Kurs tugallanishi: lesson_progress 'completed' ga o'tganda, barcha majburiy darslar tugallangan bo'lsa, faol tayinlash
--      (assigned / in_progress / overdue) 'completed' ga o'tkaziladi va bir marta `course.completed` audit yoziladi (006a _audit006).
--      Faqat holat o'tishida yoziladi → takroriy audit yo'q; o'qish RPC'lari audit yozmaydi. Sertifikat bermaydi (faqat submit_exam).
--   7. Indekslar: mavjudlari tekshirildi; faqat ikkita qisman indeks qo'shiladi.
--
-- Qoidalar: DROP TABLE / DELETE / CASCADE yo'q; RLS va mavjud policy / funksiyalar o'zgarmaydi. Idempotent. Bitta tranzaksiya.
-- Rollback: 007a_rollback.sql.

begin;

do $$ begin
  if not exists (select 1 from public.schema_migrations where version = '006b') then raise exception '007a: avval 006b qo''llanishi kerak'; end if;
end $$;

-- ---------- 1. Majburiy dars belgisi ----------
alter table public.lessons add column if not exists is_required boolean not null default true;
comment on column public.lessons.is_required is '007a: dars kurs progressi va tugallanishi uchun majburiymi (default true)';

-- ---------- 2. Indekslar ----------
create index if not exists lesson_progress_completed_007a_idx on public.lesson_progress (employee_id, lesson_id) where status = 'completed';
create index if not exists course_assignments_course_007a_idx on public.course_assignments (org_id, course_id, status);

-- ---------- 3. Ichki yordamchi: bitta xodim × bitta kurs ----------
create or replace function public._lp_course_stats_007a(p_employee uuid, p_course text)
returns table (total_required int, completed_required int, last_activity_at timestamptz)
language sql stable security definer set search_path = public as $$
  with req as (
    select l.id from public.lessons l join public.course_modules m on m.id = l.module_id
    where m.course_id = p_course and l.is_required and l.status = 'published' and m.status = 'published' and l.org_id = m.org_id
  )
  select (select count(*) from req)::int,
         (select count(*) from public.lesson_progress lp where lp.employee_id = p_employee and lp.status = 'completed' and lp.lesson_id in (select id from req))::int,
         (select max(lp.last_accessed_at) from public.lesson_progress lp join public.lessons l on l.id = lp.lesson_id join public.course_modules m on m.id = l.module_id
           where lp.employee_id = p_employee and m.course_id = p_course)
$$;

create or replace function public._lp_status_007a(p_assignment_status text, p_due date, p_total int, p_done int, p_started boolean)
returns text language sql stable as $$
  select case
    when p_assignment_status = 'cancelled' then 'cancelled'
    when p_assignment_status = 'completed' or (p_total > 0 and p_done >= p_total) then 'completed'
    when p_due is not null and p_due < current_date then 'overdue'
    when p_done > 0 or p_started then 'in_progress'
    else 'not_started' end
$$;

-- ---------- 4. my_learning_progress ----------
create or replace function public.my_learning_progress()
returns table (course_id text, course_title text, assignment_id uuid, assignment_status text, assigned_at timestamptz, due_date date,
               completed_at timestamptz, total_required_lessons int, completed_required_lessons int, progress_percent int,
               computed_status text, last_activity_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare v_emp uuid := public.my_employee_id(); v_org uuid := public.my_org();
begin
  if auth.uid() is null then raise exception 'Ruxsat yo''q'; end if;
  if v_emp is null or v_org is null then return; end if;   -- faol xodim yozuvi yo'q → bo'sh ro'yxat
  return query
  with a as (
    select ca.* from public.course_assignments ca where ca.employee_id = v_emp and ca.org_id = v_org
  ), req as (
    select m.course_id, l.id lesson_id from public.lessons l join public.course_modules m on m.id = l.module_id
    where m.course_id in (select a.course_id from a) and m.org_id = v_org and l.is_required and l.status = 'published' and m.status = 'published'
  ), done as (
    select r.course_id, count(*)::int n from req r join public.lesson_progress lp on lp.lesson_id = r.lesson_id and lp.employee_id = v_emp and lp.status = 'completed'
    group by r.course_id
  ), tot as (select r.course_id, count(*)::int n from req r group by r.course_id),
  act as (
    select m.course_id, max(lp.last_accessed_at) t from public.lesson_progress lp join public.lessons l on l.id = lp.lesson_id
      join public.course_modules m on m.id = l.module_id where lp.employee_id = v_emp group by m.course_id
  )
  select a.course_id, c.title, a.id, a.status, a.assigned_at, a.due_date, a.completed_at,
         coalesce(tot.n, 0), coalesce(done.n, 0),
         case when coalesce(tot.n, 0) = 0 then 0 else least(100, (100 * coalesce(done.n, 0)) / tot.n) end,
         public._lp_status_007a(a.status, a.due_date, coalesce(tot.n, 0), coalesce(done.n, 0), a.started_at is not null or act.t is not null),
         act.t
  from a join public.courses c on c.id = a.course_id
  left join tot on tot.course_id = a.course_id left join done on done.course_id = a.course_id left join act on act.course_id = a.course_id
  order by (a.status = 'cancelled'), a.due_date nulls last, c.title;
end $$;

-- ---------- 5. course_progress_summary ----------
create or replace function public.course_progress_summary(p_course text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_role text := public.my_role(); v_org uuid := public.my_org(); v_dept uuid; v_scope text; r jsonb;
begin
  if auth.uid() is null or v_role is null or v_org is null then raise exception 'Ruxsat yo''q'; end if;
  if not exists (select 1 from public.courses c where c.id = p_course and c.org_id = v_org) then raise exception 'Kurs topilmadi yoki ruxsat yo''q'; end if;
  if v_role in ('super_admin', 'education_manager', 'hr') and public.has_perm('progress.view') then v_scope := 'organization';
  elsif v_role = 'super_admin' then v_scope := 'organization';
  elsif v_role = 'department_head' and public.has_perm('progress.view') then
    v_dept := public.my_department_id(); if v_dept is null then raise exception 'Ruxsat yo''q'; end if; v_scope := 'department';
  elsif v_role = 'instructor' and public.has_perm('progress.view') and public.is_course_instructor(p_course) then v_scope := 'course_instructor';
  else raise exception 'Ruxsat yo''q';
  end if;
  with req as (
    select l.id lesson_id from public.lessons l join public.course_modules m on m.id = l.module_id
    where m.course_id = p_course and m.org_id = v_org and l.is_required and l.status = 'published' and m.status = 'published'
  ), tot as (select count(*)::int n from req),
  a as (
    select ca.id, ca.employee_id, ca.status, ca.due_date, ca.started_at from public.course_assignments ca join public.employees e on e.id = ca.employee_id
    where ca.course_id = p_course and ca.org_id = v_org and e.org_id = v_org and (v_scope <> 'department' or e.department_id = v_dept)
  ), done as (
    select lp.employee_id, count(*)::int n from public.lesson_progress lp join req on req.lesson_id = lp.lesson_id
    where lp.status = 'completed' and lp.employee_id in (select employee_id from a) group by lp.employee_id
  ), act as (
    select distinct lp.employee_id from public.lesson_progress lp join public.lessons l on l.id = lp.lesson_id join public.course_modules m on m.id = l.module_id
    where m.course_id = p_course and lp.employee_id in (select employee_id from a)
  ), s as (
    select a.*, public._lp_status_007a(a.status, a.due_date, (select n from tot), coalesce(done.n, 0), a.started_at is not null or act.employee_id is not null) cs,
           case when (select n from tot) = 0 then 0 else least(100, (100 * coalesce(done.n, 0)) / (select n from tot)) end pct
    from a left join done on done.employee_id = a.employee_id left join act on act.employee_id = a.employee_id
  )
  select jsonb_build_object('course_id', p_course, 'scope', v_scope, 'total_required_lessons', (select n from tot),
    'assigned_count', count(*) filter (where cs <> 'cancelled'),
    'not_started_count', count(*) filter (where cs = 'not_started'), 'in_progress_count', count(*) filter (where cs = 'in_progress'),
    'completed_count', count(*) filter (where cs = 'completed'), 'overdue_count', count(*) filter (where cs = 'overdue'),
    'cancelled_count', count(*) filter (where cs = 'cancelled'),
    'average_progress', coalesce(round(avg(pct) filter (where cs <> 'cancelled'), 1), 0))
  into r from s;
  return r;
end $$;

-- ---------- 6. Kurs tugallanishi (holat o'tishida, bir marta audit) ----------
create or replace function public.lesson_progress_completion_007a() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_course text; v_total int; v_done int; x record;
begin
  if new.status <> 'completed' or (tg_op = 'UPDATE' and old.status = 'completed') then return new; end if;
  select m.course_id into v_course from public.lessons l join public.course_modules m on m.id = l.module_id where l.id = new.lesson_id;
  if v_course is null then return new; end if;
  select s.total_required, s.completed_required into v_total, v_done from public._lp_course_stats_007a(new.employee_id, v_course) s;
  if v_total = 0 or v_done < v_total then return new; end if;
  for x in
    select a.id, a.org_id, a.employee_id, a.course_id, a.status from public.course_assignments a
     where a.employee_id = new.employee_id and a.course_id = v_course and a.org_id = new.org_id and a.status in ('assigned', 'in_progress', 'overdue')
     for update
  loop
    update public.course_assignments set status = 'completed', completed_at = coalesce(completed_at, now()) where id = x.id;
    perform public._audit006(x.org_id, 'course_assignment', 'course.completed', x.id::text,
      jsonb_build_object('status', x.status),
      jsonb_build_object('status', 'completed', 'employee_id', x.employee_id, 'course_id', x.course_id, 'required_lessons', v_total));
  end loop;
  return new;
end $$;
drop trigger if exists lesson_progress_completion_007a_trg on public.lesson_progress;
create trigger lesson_progress_completion_007a_trg after insert or update of status on public.lesson_progress
  for each row execute function public.lesson_progress_completion_007a();

-- ---------- 7. Huquqlar ----------
revoke execute on function public._lp_course_stats_007a(uuid, text) from public, anon, authenticated;
revoke execute on function public._lp_status_007a(text, date, int, int, boolean) from public, anon, authenticated;
revoke execute on function public.lesson_progress_completion_007a() from public, anon, authenticated;
revoke execute on function public.my_learning_progress() from public, anon;
revoke execute on function public.course_progress_summary(text) from public, anon;
grant execute on function public.my_learning_progress() to authenticated;
grant execute on function public.course_progress_summary(text) to authenticated;
do $$ begin
  if to_regclass('backup.function_categories_005d') is not null then
    insert into backup.function_categories_005d (name, category) values
      ('_lp_course_stats_007a', 'internal'), ('_lp_status_007a', 'internal'), ('lesson_progress_completion_007a', 'internal'),
      ('my_learning_progress', 'role_rpc'), ('course_progress_summary', 'role_rpc')
    on conflict (name) do update set category = excluded.category;
  end if;
end $$;

insert into public.schema_migrations (version, description) values
  ('007a', 'Learning progress foundation: lessons.is_required, my_learning_progress / course_progress_summary RPC, read-time overdue, course.completed audit on completion transition, 2 partial indexes')
on conflict (version) do nothing;

commit;

select json_build_object(
  'migration', (select version from public.schema_migrations where version = '007a'),
  'is_required_column', (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'lessons' and column_name = 'is_required'),
  'lessons_required', (select count(*) from public.lessons where is_required),
  'trigger', (select count(*) from pg_trigger where tgname = 'lesson_progress_completion_007a_trg'),
  'anon_exec', (select string_agg(p.proname, ',') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')),
  'attempts', (select count(*) from public.exam_attempts), 'certificates', (select count(*) from public.certificates)
)::text as result_007a;
