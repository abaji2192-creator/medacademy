-- MedAcademy · Migration 007d — In-App Notifications (Phase 3 STEP 10)
-- 007c'dan keyin. 004…007c obyektlari (jadval, funksiya, trigger, policy) O'ZGARTIRILMAYDI. Additive: 1 jadval, RLS, 4 RPC,
-- manba jadvallarda statement-level AFTER trigger'lar (transition tables — set-based, N+1 yo'q).
--
-- Haqiqiy sxema (lokal tekshiruv): notification jadvali / ruxsati YO'Q. Legacy docs.collection = 'notifications' JSON bor —
-- IMPORT QILINMAYDI va unga tegilmaydi.
--
-- Qarorlar:
--   * Faqat in-app. Email / Telegram / WhatsApp / SMS / push — yo'q.
--   * Qabul qiluvchi = profiles.id (= auth.uid()). Xodim → employees.profile_id; akkauntsiz xodimga bildirishnoma yozilmaydi.
--   * Yaratish faqat server tomonida: manba jadvallardagi SECURITY DEFINER trigger'lar. Frontend INSERT / UPDATE / DELETE grantiga ega emas;
--     authenticated uchun faqat SELECT (RLS: faqat o'z bildirishnomalari) + RPC'lar.
--   * Hodisalar (MVP):
--       course_assigned          — course_assignments INSERT (status <> 'cancelled')          key: course_assigned:<assignment_id>
--       course_completed         — course_assignments status → 'completed'                    key: course_completed:<assignment_id>
--       learning_path_assigned   — learning_path_assignments INSERT (active, nashr etilgan yo'nalish) — mos xodimlarga
--                                                                                             key: learning_path_assigned:<rule_id>
--       skill_assessment_created — skill_assessments INSERT (baholangan xodimga)              key: skill_assessment_created:<assessment_id>
--       competency_achieved      — yangi baholash xodimga mos faol talab darajasini birinchi marta qoplasa (oldingi so'nggi daraja < talab)
--                                                                                             key: competency_achieved:<employee>:<skill>:<assessment_id>
--       certificate_issued       — certificates INSERT (revoked = false)                      key: certificate_issued:<certificate_id>
--     course_due_soon / course_overdue — rejalashtiruvchi (cron) talab qiladi, MVP'ga kiritilmadi. exam_result — kiritilmadi
--     (imtihon dvigateliga tegilmaydi; ball/javob ma'lumoti bildirishnomaga chiqmaydi). competency_gap — har baholashda spam bo'lmasligi
--     uchun kiritilmadi (holat employee_competency_summary orqali ko'rinadi).
--   * Dublikat yo'q: unique (recipient_id, event_key) + INSERT … ON CONFLICT DO NOTHING — bir vaqtdagi (concurrent) urinishlarda ham
--     bitta qator. 007b reapply / takroriy hodisa yangi bildirishnoma yaratmaydi (manba qator yangi bo'lmasa).
--   * O'zgarmaslik: title / body / recipient / type / org / event_key / related_* / metadata / created_at o'zgarmaydi;
--     faqat read_at (o'qildi ↔ o'qilmadi, RPC orqali). DELETE va TRUNCATE rad etiladi. CASCADE yo'q.
--   * Kontent: faqat minimal ma'lumot (kurs / yo'nalish / ko'nikma nomi, daraja). Ball, javob kaliti, baholovchi izohi, PII — yo'q.
--   * Ruxsat: yangi permission QO'SHILMADI — o'z bildirishnomalarini ko'rish identifikatsiyaga bog'liq (recipient_id = auth.uid()).
--     Super Admin ham faqat o'zinikini ko'radi. Admin tomonidan ixtiyoriy bildirishnoma yaratish — MVP'da yo'q.
--   * Audit: bildirishnoma yaratish va o'qish audit qilinmaydi (manba hodisa allaqachon audit qilingan; audit flood yo'q).
-- Rollback: 007d_rollback.sql (bildirishnomalar avval backup.notifications_rb007d ga nusxalanadi).

begin;

do $$ begin
  if not exists (select 1 from public.schema_migrations where version = '007c') then raise exception '007d: avval 007c qo''llanishi kerak'; end if;
end $$;

-- ---------- 1. Jadval ----------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete restrict,
  recipient_id uuid not null references public.profiles(id) on delete restrict,
  notification_type text not null check (notification_type in ('course_assigned', 'course_completed', 'learning_path_assigned',
    'skill_assessment_created', 'competency_achieved', 'certificate_issued')),
  title text not null check (length(title) between 1 and 200),
  body text check (body is null or length(body) <= 1000),
  related_entity_type text check (related_entity_type is null or related_entity_type in ('course_assignment', 'course', 'learning_path_assignment',
    'learning_path', 'skill_assessment', 'skill', 'certificate')),
  related_entity_id text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  event_key text not null check (length(event_key) between 3 and 300),
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint notifications_recipient_event_uq unique (recipient_id, event_key)
);
create index if not exists notifications_recipient_created_idx on public.notifications (recipient_id, created_at desc, id desc);
create index if not exists notifications_recipient_unread_idx on public.notifications (recipient_id) where read_at is null;
create index if not exists notifications_org_idx on public.notifications (org_id);

-- ---------- 2. O'zgarmaslik ----------
create or replace function public.guard_notification_007d() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'notifications: o''chirish taqiqlangan' using errcode = '42501'; end if;
  if row(new.id, new.org_id, new.recipient_id, new.notification_type, new.title, new.body, new.related_entity_type, new.related_entity_id,
         new.metadata, new.event_key, new.created_at)
     is distinct from row(old.id, old.org_id, old.recipient_id, old.notification_type, old.title, old.body, old.related_entity_type,
         old.related_entity_id, old.metadata, old.event_key, old.created_at) then
    raise exception 'notifications: faqat read_at o''zgartirilishi mumkin' using errcode = '42501';
  end if;
  return new;
end $$;
create or replace function public.guard_notification_truncate_007d() returns trigger
language plpgsql security definer set search_path = public as $$
begin raise exception 'notifications: TRUNCATE taqiqlangan' using errcode = '42501'; end $$;
drop trigger if exists notifications_guard_007d on public.notifications;
create trigger notifications_guard_007d before update or delete on public.notifications for each row execute function public.guard_notification_007d();
drop trigger if exists notifications_truncate_guard_007d on public.notifications;
create trigger notifications_truncate_guard_007d before truncate on public.notifications for each statement execute function public.guard_notification_truncate_007d();

-- ---------- 3. RLS (faqat o'qish; yozuv faqat RPC / trigger orqali) ----------
alter table public.notifications enable row level security;
revoke all on public.notifications from public, anon, authenticated;
grant select on public.notifications to authenticated;
drop policy if exists notifications_select_own_007d on public.notifications;
create policy notifications_select_own_007d on public.notifications for select to authenticated
  using (recipient_id = (select auth.uid()) and org_id = (select public.my_org()));

-- ---------- 4. Hodisa trigger'lari (statement-level, set-based) ----------
-- 4a. course_assignments INSERT → course_assigned
create or replace function public.ntf_course_assigned_007d() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (org_id, recipient_id, notification_type, title, body, related_entity_type, related_entity_id, metadata, event_key)
  select n.org_id, e.profile_id, 'course_assigned', 'Yangi kurs tayinlandi', left(c.title, 300)
           || case when n.due_date is not null then ' — muddat: ' || to_char(n.due_date, 'DD.MM.YYYY') else '' end,
         'course_assignment', n.id::text, jsonb_build_object('course_id', n.course_id, 'due_date', n.due_date),
         'course_assigned:' || n.id
  from new_rows n
  join public.employees e on e.id = n.employee_id and e.org_id = n.org_id and e.profile_id is not null
  join public.profiles p on p.id = e.profile_id and p.org_id = n.org_id
  join public.courses c on c.id = n.course_id
  where n.status <> 'cancelled'
  on conflict (recipient_id, event_key) do nothing;
  return null;
end $$;
drop trigger if exists course_assignments_ntf_ins_007d on public.course_assignments;
create trigger course_assignments_ntf_ins_007d after insert on public.course_assignments
  referencing new table as new_rows for each statement execute function public.ntf_course_assigned_007d();

-- 4b. course_assignments status → completed → course_completed
create or replace function public.ntf_course_completed_007d() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (org_id, recipient_id, notification_type, title, body, related_entity_type, related_entity_id, metadata, event_key)
  select n.org_id, e.profile_id, 'course_completed', 'Kurs yakunlandi', left(c.title, 300),
         'course_assignment', n.id::text, jsonb_build_object('course_id', n.course_id), 'course_completed:' || n.id
  from new_rows n
  join old_rows o on o.id = n.id
  join public.employees e on e.id = n.employee_id and e.org_id = n.org_id and e.profile_id is not null
  join public.profiles p on p.id = e.profile_id and p.org_id = n.org_id
  join public.courses c on c.id = n.course_id
  where n.status = 'completed' and o.status is distinct from 'completed'
  on conflict (recipient_id, event_key) do nothing;
  return null;
end $$;
drop trigger if exists course_assignments_ntf_upd_007d on public.course_assignments;
create trigger course_assignments_ntf_upd_007d after update on public.course_assignments
  referencing old table as old_rows new table as new_rows for each statement execute function public.ntf_course_completed_007d();

-- 4c. learning_path_assignments INSERT → learning_path_assigned (mos xodimlar — 007b nishon qoidasi bilan bir xil, faqat o'qish)
create or replace function public.ntf_learning_path_assigned_007d() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (org_id, recipient_id, notification_type, title, body, related_entity_type, related_entity_id, metadata, event_key)
  select r.org_id, e.profile_id, 'learning_path_assigned', 'Yangi o''quv yo''nalishi tayinlandi', left(lp.title, 300)
           || case when r.due_date is not null then ' — muddat: ' || to_char(r.due_date, 'DD.MM.YYYY') else '' end,
         'learning_path_assignment', r.id::text, jsonb_build_object('path_id', r.path_id, 'due_date', r.due_date),
         'learning_path_assigned:' || r.id
  from new_rows r
  join public.learning_paths lp on lp.id = r.path_id and lp.org_id = r.org_id and lp.status = 'published'
  join public.employees e on e.org_id = r.org_id and e.employment_status in ('active', 'on_leave') and e.profile_id is not null
   and case r.target_type
         when 'employee' then e.id = r.employee_id
         when 'department' then e.department_id = r.department_id
         when 'position' then e.position_id = r.position_id
         when 'specialty' then e.specialty_id = r.specialty_id
         when 'role' then exists (select 1 from public.profiles pr where pr.id = e.profile_id and pr.org_id = r.org_id and pr.role = r.target_role and pr.status = 'active')
       end
  join public.profiles p on p.id = e.profile_id and p.org_id = r.org_id
  where r.status = 'active'
  on conflict (recipient_id, event_key) do nothing;
  return null;
end $$;
drop trigger if exists lpa_ntf_ins_007d on public.learning_path_assignments;
create trigger lpa_ntf_ins_007d after insert on public.learning_path_assignments
  referencing new table as new_rows for each statement execute function public.ntf_learning_path_assigned_007d();

-- 4d. skill_assessments INSERT → skill_assessment_created (+ competency_achieved talab birinchi marta qoplanganda)
create or replace function public.ntf_skill_assessment_007d() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (org_id, recipient_id, notification_type, title, body, related_entity_type, related_entity_id, metadata, event_key)
  select n.org_id, e.profile_id, 'skill_assessment_created', 'Ko''nikma baholandi',
         left(s.name, 300) || ': ' || n.level || ' / ' || s.max_level,
         'skill_assessment', n.id::text, jsonb_build_object('skill_id', n.skill_id, 'level', n.level, 'max_level', s.max_level),
         'skill_assessment_created:' || n.id
  from new_rows n
  join public.employees e on e.id = n.employee_id and e.org_id = n.org_id and e.profile_id is not null
  join public.profiles p on p.id = e.profile_id and p.org_id = n.org_id
  join public.skills s on s.id = n.skill_id
  on conflict (recipient_id, event_key) do nothing;

  with req as (   -- xodimga mos faol talablar ichida eng yuqori daraja (007c semantikasi bilan bir xil)
    select n.id assessment_id, n.org_id, n.employee_id, n.skill_id, n.level, n.assessed_at, n.assessment_seq, e.profile_id, max(cr.required_level) required_level
    from new_rows n
    join public.employees e on e.id = n.employee_id and e.org_id = n.org_id and e.profile_id is not null
    join public.profiles p on p.id = e.profile_id and p.org_id = n.org_id
    join public.competency_requirements cr on cr.org_id = n.org_id and cr.skill_id = n.skill_id and cr.status = 'active'
     and case cr.target_type
           when 'department' then cr.department_id = e.department_id
           when 'position' then cr.position_id = e.position_id
           when 'specialty' then cr.specialty_id = e.specialty_id
           when 'role' then cr.target_role = p.role
         end
    group by 1, 2, 3, 4, 5, 6, 7, 8
  ), prev as (
    select r.*, (select a.level from public.skill_assessments a
                 where a.employee_id = r.employee_id and a.skill_id = r.skill_id and a.id <> r.assessment_id
                   and (a.assessed_at, a.assessment_seq) < (r.assessed_at, r.assessment_seq)
                 order by a.assessed_at desc, a.assessment_seq desc limit 1) prev_level
    from req r
  )
  insert into public.notifications (org_id, recipient_id, notification_type, title, body, related_entity_type, related_entity_id, metadata, event_key)
  select x.org_id, x.profile_id, 'competency_achieved', 'Kompetensiya talabi bajarildi',
         left(s.name, 300) || ': ' || x.level || ' (talab: ' || x.required_level || ')',
         'skill', x.skill_id::text, jsonb_build_object('skill_id', x.skill_id, 'level', x.level, 'required_level', x.required_level),
         'competency_achieved:' || x.employee_id || ':' || x.skill_id || ':' || x.assessment_id
  from prev x join public.skills s on s.id = x.skill_id
  where x.level >= x.required_level and (x.prev_level is null or x.prev_level < x.required_level)
  on conflict (recipient_id, event_key) do nothing;
  return null;
end $$;
drop trigger if exists skill_assessments_ntf_ins_007d on public.skill_assessments;
create trigger skill_assessments_ntf_ins_007d after insert on public.skill_assessments
  referencing new table as new_rows for each statement execute function public.ntf_skill_assessment_007d();

-- 4e. certificates INSERT → certificate_issued (sertifikat dvigateli o'zgarmaydi; ball chiqarilmaydi)
create or replace function public.ntf_certificate_issued_007d() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (org_id, recipient_id, notification_type, title, body, related_entity_type, related_entity_id, metadata, event_key)
  select n.org_id, n.user_id, 'certificate_issued', 'Sertifikat berildi', left(coalesce(n.course_title, n.course_id), 300),
         'certificate', n.id, jsonb_build_object('course_id', n.course_id), 'certificate_issued:' || n.id
  from new_rows n
  join public.profiles p on p.id = n.user_id and p.org_id = n.org_id
  where not n.revoked
  on conflict (recipient_id, event_key) do nothing;
  return null;
end $$;
drop trigger if exists certificates_ntf_ins_007d on public.certificates;
create trigger certificates_ntf_ins_007d after insert on public.certificates
  referencing new table as new_rows for each statement execute function public.ntf_certificate_issued_007d();

-- ---------- 5. RPC'lar (faqat joriy foydalanuvchi) ----------
create or replace function public.my_notifications(p_limit int default 20, p_before_created timestamptz default null,
  p_before_id uuid default null, p_unread_only boolean default false)
returns table (id uuid, notification_type text, title text, body text, related_entity_type text, related_entity_id text,
               metadata jsonb, created_at timestamptz, read_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_org uuid := public.my_org(); v_lim int := least(greatest(coalesce(p_limit, 20), 1), 100);
begin
  if v_uid is null or v_org is null then raise exception 'Avtorizatsiya talab qilinadi' using errcode = '42501'; end if;
  if (p_before_created is null) <> (p_before_id is null) then raise exception 'Sahifalash: p_before_created va p_before_id birga beriladi' using errcode = '22023'; end if;
  return query
    select n.id, n.notification_type, n.title, n.body, n.related_entity_type, n.related_entity_id, n.metadata, n.created_at, n.read_at
    from public.notifications n
    where n.recipient_id = v_uid and n.org_id = v_org
      and (not coalesce(p_unread_only, false) or n.read_at is null)
      and (p_before_created is null or (n.created_at, n.id) < (p_before_created, p_before_id))
    order by n.created_at desc, n.id desc
    limit v_lim;
end $$;

create or replace function public.unread_notification_count() returns int
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_org uuid := public.my_org();
begin
  if v_uid is null or v_org is null then raise exception 'Avtorizatsiya talab qilinadi' using errcode = '42501'; end if;
  return (select count(*)::int from public.notifications where recipient_id = v_uid and org_id = v_org and read_at is null);
end $$;

create or replace function public.mark_notification_read(p_id uuid, p_read boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_org uuid := public.my_org(); v_read timestamptz; v_changed int;
begin
  if v_uid is null or v_org is null then raise exception 'Avtorizatsiya talab qilinadi' using errcode = '42501'; end if;
  select read_at into v_read from public.notifications where id = p_id and recipient_id = v_uid and org_id = v_org;
  if not found then raise exception 'Bildirishnoma topilmadi' using errcode = 'P0002'; end if;
  update public.notifications set read_at = case when coalesce(p_read, true) then coalesce(read_at, now()) else null end
   where id = p_id and recipient_id = v_uid and org_id = v_org
     and (case when coalesce(p_read, true) then read_at is null else read_at is not null end);
  get diagnostics v_changed = row_count;
  return jsonb_build_object('id', p_id, 'read', coalesce(p_read, true), 'changed', v_changed = 1);
end $$;

create or replace function public.mark_all_notifications_read() returns int
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_org uuid := public.my_org(); v_n int;
begin
  if v_uid is null or v_org is null then raise exception 'Avtorizatsiya talab qilinadi' using errcode = '42501'; end if;
  update public.notifications set read_at = now() where recipient_id = v_uid and org_id = v_org and read_at is null;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- ---------- 6. Grant'lar va funksiya kategoriyalari ----------
revoke execute on function public.guard_notification_007d() from public, anon, authenticated;
revoke execute on function public.guard_notification_truncate_007d() from public, anon, authenticated;
revoke execute on function public.ntf_course_assigned_007d() from public, anon, authenticated;
revoke execute on function public.ntf_course_completed_007d() from public, anon, authenticated;
revoke execute on function public.ntf_learning_path_assigned_007d() from public, anon, authenticated;
revoke execute on function public.ntf_skill_assessment_007d() from public, anon, authenticated;
revoke execute on function public.ntf_certificate_issued_007d() from public, anon, authenticated;
revoke execute on function public.my_notifications(int, timestamptz, uuid, boolean) from public, anon;
revoke execute on function public.unread_notification_count() from public, anon;
revoke execute on function public.mark_notification_read(uuid, boolean) from public, anon;
revoke execute on function public.mark_all_notifications_read() from public, anon;
grant execute on function public.my_notifications(int, timestamptz, uuid, boolean) to authenticated;
grant execute on function public.unread_notification_count() to authenticated;
grant execute on function public.mark_notification_read(uuid, boolean) to authenticated;
grant execute on function public.mark_all_notifications_read() to authenticated;
do $$ begin
  if to_regclass('backup.function_categories_005d') is not null then
    insert into backup.function_categories_005d (name, category) values
      ('guard_notification_007d', 'internal'), ('guard_notification_truncate_007d', 'internal'), ('ntf_course_assigned_007d', 'internal'),
      ('ntf_course_completed_007d', 'internal'), ('ntf_learning_path_assigned_007d', 'internal'), ('ntf_skill_assessment_007d', 'internal'),
      ('ntf_certificate_issued_007d', 'internal'),
      ('my_notifications', 'employee_rpc'), ('unread_notification_count', 'employee_rpc'), ('mark_notification_read', 'employee_rpc'),
      ('mark_all_notifications_read', 'employee_rpc')
    on conflict (name) do update set category = excluded.category;
  end if;
end $$;

insert into public.schema_migrations (version, description) values
  ('007d', 'In-app notifications: notifications (server-side creation via statement triggers, unique recipient+event_key, immutable except read_at, no DELETE), 4 own-only RPCs')
on conflict (version) do nothing;

commit;

select json_build_object(
  'migration', (select version from public.schema_migrations where version = '007d'),
  'table', to_regclass('public.notifications') is not null,
  'notifications', (select count(*) from public.notifications),
  'anon_exec', (select string_agg(p.proname, ',') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')),
  'attempts', (select count(*) from public.exam_attempts), 'certificates', (select count(*) from public.certificates)
)::text as result_007d;
