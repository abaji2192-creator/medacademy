-- MedAcademy · Migration 006b — Kursni fizik o'chirishni taqiqlash (archive-only) + sababli holat o'zgartirish RPC
-- 006a'dan keyin. 004 / 005 / 005d / 005e / 006a fayllari o'zgartirilmaydi.
--
--   1. courses: API orqali DELETE har qanday rol uchun taqiqlanadi (BEFORE DELETE trigger, SECURITY DEFINER).
--      courses_write RLS policy O'ZGARMAYDI (INSERT / UPDATE semantikasi saqlanadi); kurs "archived" holatiga o'tkaziladi.
--      Platforma SQL (migratsiya / texnik xizmat) bundan mustasno — 006a audit'i (course.deleted) ishlaydi.
--   2. admin_set_course_status(p_course, p_status, p_reason) — SA / EM; sabab majburiy; audit (006a): eski/yangi holat,
--      actor, tashkilot, vaqt, sabab. Mavjud to'g'ridan-to'g'ri status UPDATE ham ishlaydi (sababsiz audit).
--
-- Qoidalar: jadval / ustun / ma'lumot o'zgarmaydi; RLS o'zgarmaydi. Idempotent. Bitta tranzaksiya. Rollback: 006b_rollback.sql.

begin;

do $$ begin
  if not exists (select 1 from public.schema_migrations where version = '006a') then raise exception '006b: avval 006a qo''llanishi kerak'; end if;
end $$;

create or replace function public.guard_course_delete_006b() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_api_request() then
    raise exception 'Kursni o''chirib bo''lmaydi (tarixiy urinishlar, sertifikatlar, audit bilan bog''liq) — kursni "archived" holatiga o''tkazing';
  end if;
  return old;
end $$;
drop trigger if exists courses_no_delete_006b_trg on public.courses;
create trigger courses_no_delete_006b_trg before delete on public.courses for each row execute function public.guard_course_delete_006b();

create or replace function public.admin_set_course_status(p_course text, p_status text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_old text;
begin
  if coalesce(public.my_role(), '') not in ('super_admin','education_manager') then raise exception 'Ruxsat yo''q'; end if;
  if p_reason is null or length(trim(p_reason)) < 3 then raise exception 'Holat o''zgartirish sababi majburiy'; end if;
  if p_status not in ('draft','under_review','approved','published','archived') then raise exception 'Noto''g''ri holat: %', p_status; end if;
  select status into v_old from public.courses where id = p_course and org_id = public.my_org();
  if not found then raise exception 'Kurs topilmadi yoki ruxsat yo''q'; end if;
  perform set_config('medacademy.audit_reason', trim(p_reason), true);
  update public.courses set status = p_status where id = p_course and org_id = public.my_org();
  perform set_config('medacademy.audit_reason', '', true);
  return jsonb_build_object('id', p_course, 'old_status', v_old, 'new_status', p_status);
end $$;

revoke execute on function public.guard_course_delete_006b() from public, anon, authenticated;
revoke execute on function public.admin_set_course_status(text, text, text) from public, anon;
grant execute on function public.admin_set_course_status(text, text, text) to authenticated;
do $$ begin
  if to_regclass('backup.function_categories_005d') is not null then
    insert into backup.function_categories_005d (name, category) values ('guard_course_delete_006b', 'internal'), ('admin_set_course_status', 'role_rpc')
    on conflict (name) do update set category = excluded.category;
  end if;
end $$;

insert into public.schema_migrations (version, description) values
  ('006b', 'Course delete hardening: API DELETE on courses denied for all roles (archive-only), admin_set_course_status RPC with mandatory reason (audited via 006a)')
on conflict (version) do nothing;

commit;

select json_build_object(
  'migration', (select version from public.schema_migrations where version = '006b'),
  'trigger', (select count(*) from pg_trigger where tgname = 'courses_no_delete_006b_trg'),
  'courses', (select count(*) from public.courses),
  'courses_write_policy_unchanged', (select qual from pg_policies where schemaname = 'public' and tablename = 'courses' and policyname = 'courses_write') is not null,
  'anon_exec', (select string_agg(p.proname, ',') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute'))
)::text as result_006b;
