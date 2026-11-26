-- MedAcademy · Migration 007c — Skills + Competency (Phase 3 STEP 9)
-- 007b'dan keyin. 004…007b obyektlari o'zgartirilmaydi. Additive: 3 jadval, 4 ruxsat (+ rol bog'lanishlari), RLS, RPC'lar, guard trigger'lar.
--
-- Haqiqiy sxema (lokal tekshiruv): skill / competency jadvali yoki ustuni YO'Q; legacy docs.skill_assess JSON import QILINMAYDI.
-- Ruxsat modeli: permissions(key, category, description) + role_permissions(org_id, role, permission_key) (har tashkilotga alohida);
-- has_perm(): super_admin hamma ruxsatga ega. Yangi tashkilotlar uchun seed_org_defaults* ga TEGILMAYDI — alohida AFTER INSERT trigger.
--
-- Qarorlar:
--   * Ruxsatlar: skill.view, skill.manage, skill.assess, competency.manage (category 'skills').
--       education_manager: 4 tasi; department_head: skill.view + skill.assess (faqat o'z bo'limi); hr: skill.view; instructor: skill.view;
--       medical_reviewer / employee: yo'q (xodim o'z kompetensiyasini RPC orqali ko'radi). Instructor uchun baholash huquqi BERILMADI.
--   * skills: tashkilot katalogi, code tashkilot ichida unique, max_level (1–10, default 5) — baholash shkalasi 0..max_level.
--       O'chirish yo'q: status active | archived. Arxivlangan skill yangi baholash / talab qabul qilmaydi; tarix saqlanadi.
--   * skill_assessments: INSERT-ONLY, IMMUTABLE (UPDATE / DELETE / TRUNCATE trigger bilan rad). Tuzatish = yangi baholash.
--       Bir xodim × skill uchun bir nechta baholash ruxsat etiladi (tarix); joriy daraja = eng so'nggi (assessed_at, assessment_seq).
--       assessor_id = auth.uid() (soxta actor mumkin emas); o'zini baholash rad; nofaol xodim rad.
--   * competency_requirements: skill × nishon (department | position | specialty | role), required_level; har qoidada aniq bitta nishon;
--       active | archived; bir xil (skill, nishon) uchun bitta active talab. Muddat (expiry) semantikasi kiritilmadi (biznes talabi yo'q).
--   * Kompetensiya holati (o'qishda hisoblanadi): xodimga mos active talablar ichidagi eng yuqori required_level;
--       achieved = so'nggi baholash darajasi >= required; not_achieved = baholangan, lekin past; not_assessed = baholash yo'q.
--   * 007a / 007b semantikasi, kurs tayinlashlari, urinishlar, sertifikatlar o'zgarmaydi.
-- Rollback: 007c_rollback.sql (007c ma'lumoti mavjud bo'lsa — avval eksport, rollback to'xtaydi).

begin;

do $$ begin
  if not exists (select 1 from public.schema_migrations where version = '007b') then raise exception '007c: avval 007b qo''llanishi kerak'; end if;
end $$;

-- ---------- 1. Ruxsatlar ----------
insert into public.permissions (key, category, description) values
  ('skill.view', 'skills', 'Ko''nikmalar katalogi va kompetensiyalarni ko''rish'),
  ('skill.manage', 'skills', 'Ko''nikmalar katalogini boshqarish'),
  ('skill.assess', 'skills', 'Xodim ko''nikmasini baholash'),
  ('competency.manage', 'skills', 'Kompetensiya talablarini boshqarish')
on conflict (key) do nothing;

create or replace function public._sk_seed_perms_007c(p_org uuid) returns void
language sql security definer set search_path = public as $$
  insert into public.role_permissions (org_id, role, permission_key)
  select p_org, x.role, x.perm from (values
    ('education_manager', 'skill.view'), ('education_manager', 'skill.manage'), ('education_manager', 'skill.assess'), ('education_manager', 'competency.manage'),
    ('department_head', 'skill.view'), ('department_head', 'skill.assess'),
    ('hr', 'skill.view'), ('instructor', 'skill.view')) x(role, perm)
  on conflict (org_id, role, permission_key) do nothing
$$;
select public._sk_seed_perms_007c(o.id) from public.organizations o;

create or replace function public.seed_org_skill_perms_007c() returns trigger
language plpgsql security definer set search_path = public as $$
begin perform public._sk_seed_perms_007c(new.id); return new; end $$;
drop trigger if exists org_skill_perms_007c_trg on public.organizations;
create trigger org_skill_perms_007c_trg after insert on public.organizations for each row execute function public.seed_org_skill_perms_007c();

-- ---------- 2. Jadvallar ----------
create table if not exists public.skills (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete restrict,
  code text not null check (code ~ '^[A-Za-z0-9_.-]{2,64}$'),
  name text not null check (length(trim(name)) between 2 and 200),
  description text,
  category text check (category is null or length(category) <= 100),
  specialty_id uuid references public.specialties(id) on delete restrict,
  max_level smallint not null default 5 check (max_level between 1 and 10),
  status text not null default 'active' check (status in ('active', 'archived')),
  created_by uuid references public.profiles(id) on delete restrict,
  updated_by uuid references public.profiles(id) on delete restrict,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint skills_org_code_uq unique (org_id, code),
  constraint skills_archive_consistent check ((status = 'archived') = (archived_at is not null))
);

create table if not exists public.skill_assessments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete restrict,
  skill_id uuid not null references public.skills(id) on delete restrict,
  employee_id uuid not null references public.employees(id) on delete restrict,
  assessor_id uuid not null references public.profiles(id) on delete restrict,
  level smallint not null check (level between 0 and 10),
  notes text check (notes is null or length(notes) <= 2000),
  assessed_at timestamptz not null default now(),
  assessment_seq bigint generated always as identity,
  created_at timestamptz not null default now()
);

create table if not exists public.competency_requirements (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete restrict,
  skill_id uuid not null references public.skills(id) on delete restrict,
  target_type text not null check (target_type in ('department', 'position', 'specialty', 'role')),
  department_id uuid references public.departments(id) on delete restrict,
  position_id uuid references public.positions(id) on delete restrict,
  specialty_id uuid references public.specialties(id) on delete restrict,
  target_role text check (target_role is null or target_role in ('super_admin','hr','education_manager','department_head','instructor','employee','medical_reviewer','content_author')),
  required_level smallint not null check (required_level between 1 and 10),
  status text not null default 'active' check (status in ('active', 'archived')),
  created_by uuid references public.profiles(id) on delete restrict,
  updated_by uuid references public.profiles(id) on delete restrict,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  target_key text generated always as (coalesce(department_id::text, position_id::text, specialty_id::text, target_role)) stored,
  constraint cr_exactly_one_target check (
    num_nonnulls(department_id, position_id, specialty_id, target_role) = 1
    and (target_type <> 'department' or department_id is not null)
    and (target_type <> 'position' or position_id is not null)
    and (target_type <> 'specialty' or specialty_id is not null)
    and (target_type <> 'role' or target_role is not null)),
  constraint cr_archive_consistent check ((status = 'archived') = (archived_at is not null))
);

create index if not exists skills_org_status_idx on public.skills (org_id, status);
create index if not exists skill_assessments_emp_skill_idx on public.skill_assessments (employee_id, skill_id, assessed_at desc, assessment_seq desc);
create index if not exists skill_assessments_org_skill_idx on public.skill_assessments (org_id, skill_id);
create unique index if not exists cr_active_target_uq on public.competency_requirements (skill_id, target_type, target_key) where status = 'active';
create index if not exists cr_org_status_idx on public.competency_requirements (org_id, status);

-- ---------- 3. Guard trigger'lar ----------
create or replace function public.guard_skill_007c() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'Ko''nikmani o''chirib bo''lmaydi (arxivlang)'; end if;
  if tg_op = 'UPDATE' then
    if new.org_id is distinct from old.org_id or new.code is distinct from old.code or new.created_by is distinct from old.created_by or new.created_at is distinct from old.created_at then
      raise exception 'Ko''nikmaning tashkiloti / kodi / yaratuvchisi o''zgarmaydi';
    end if;
    if old.status = 'archived' and new.status <> 'archived' then raise exception 'Arxivlangan ko''nikmani qayta faollashtirib bo''lmaydi'; end if;
    if new.max_level < old.max_level and exists (select 1 from public.skill_assessments a where a.skill_id = old.id and a.level > new.max_level) then
      raise exception 'Mavjud baholashlardan past max_level o''rnatib bo''lmaydi';
    end if;
    new.updated_at := now();
  end if;
  if new.specialty_id is not null and not exists (select 1 from public.specialties where id = new.specialty_id and org_id = new.org_id) then raise exception 'Mutaxassislik boshqa tashkilotga tegishli'; end if;
  return new;
end $$;
drop trigger if exists skills_guard_007c_trg on public.skills;
create trigger skills_guard_007c_trg before insert or update or delete on public.skills for each row execute function public.guard_skill_007c();

create or replace function public.guard_skill_assessment_007c() returns trigger
language plpgsql security definer set search_path = public as $$
declare s public.skills;
begin
  if tg_op in ('UPDATE', 'DELETE') then raise exception 'Ko''nikma baholashi o''zgarmas (tuzatish uchun yangi baholash yarating)'; end if;
  select * into s from public.skills where id = new.skill_id;
  if s.id is null or s.org_id <> new.org_id then raise exception 'Ko''nikma boshqa tashkilotga tegishli'; end if;
  if s.status <> 'active' then raise exception 'Arxivlangan ko''nikma baholanmaydi'; end if;
  if new.level > s.max_level then raise exception 'Daraja 0..% oralig''ida bo''lishi kerak', s.max_level; end if;
  if not exists (select 1 from public.employees where id = new.employee_id and org_id = new.org_id) then raise exception 'Xodim boshqa tashkilotga tegishli'; end if;
  if not exists (select 1 from public.profiles where id = new.assessor_id and org_id = new.org_id) then raise exception 'Baholovchi boshqa tashkilotga tegishli'; end if;
  return new;
end $$;
drop trigger if exists skill_assessments_guard_007c_trg on public.skill_assessments;
create trigger skill_assessments_guard_007c_trg before insert or update or delete on public.skill_assessments for each row execute function public.guard_skill_assessment_007c();
create or replace function public.guard_skill_assessment_truncate_007c() returns trigger
language plpgsql security definer set search_path = public as $$ begin raise exception 'Ko''nikma baholashlari tarixini tozalab bo''lmaydi'; end $$;
drop trigger if exists skill_assessments_truncate_007c_trg on public.skill_assessments;
create trigger skill_assessments_truncate_007c_trg before truncate on public.skill_assessments for each statement execute function public.guard_skill_assessment_truncate_007c();

create or replace function public.guard_competency_req_007c() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'Kompetensiya talabini o''chirib bo''lmaydi (arxivlang)'; end if;
  if tg_op = 'UPDATE' then
    if new.org_id is distinct from old.org_id or new.skill_id is distinct from old.skill_id or new.target_type is distinct from old.target_type
       or new.department_id is distinct from old.department_id or new.position_id is distinct from old.position_id or new.specialty_id is distinct from old.specialty_id
       or new.target_role is distinct from old.target_role or new.created_by is distinct from old.created_by or new.created_at is distinct from old.created_at then
      raise exception 'Talabning ko''nikma / nishon / egalik maydonlari o''zgarmaydi';
    end if;
    if old.status = 'archived' and new.status <> 'archived' then raise exception 'Arxivlangan talabni qayta faollashtirib bo''lmaydi'; end if;
    new.updated_at := now();
  end if;
  if not exists (select 1 from public.skills where id = new.skill_id and org_id = new.org_id) then raise exception 'Ko''nikma boshqa tashkilotga tegishli'; end if;
  if new.department_id is not null and not exists (select 1 from public.departments where id = new.department_id and org_id = new.org_id) then raise exception 'Bo''lim boshqa tashkilotga tegishli'; end if;
  if new.position_id is not null and not exists (select 1 from public.positions where id = new.position_id and org_id = new.org_id) then raise exception 'Lavozim boshqa tashkilotga tegishli'; end if;
  if new.specialty_id is not null and not exists (select 1 from public.specialties where id = new.specialty_id and org_id = new.org_id) then raise exception 'Mutaxassislik boshqa tashkilotga tegishli'; end if;
  return new;
end $$;
drop trigger if exists cr_guard_007c_trg on public.competency_requirements;
create trigger cr_guard_007c_trg before insert or update or delete on public.competency_requirements for each row execute function public.guard_competency_req_007c();

-- ---------- 4. Ko'rish doirasi yordamchisi ----------
-- Xodim ma'lumotini ko'ra olishi: o'zi; SA / EM / HR (skill.view, tashkilot); Department Head (skill.view, o'z bo'limi).
create or replace function public._sk_can_view_employee_007c(p_employee uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and exists (
    select 1 from public.employees e where e.id = p_employee and e.org_id = public.my_org()
      and (e.profile_id = auth.uid()
           or (public.my_role() in ('super_admin', 'education_manager', 'hr') and public.has_perm('skill.view'))
           or (public.my_role() = 'department_head' and public.has_perm('skill.view') and e.department_id = public.my_department_id() and public.my_department_id() is not null)))
$$;

create or replace function public._sk_my_dept_employees_007c() returns setof uuid
language sql stable security definer set search_path = public as $$
  select e.id from public.employees e where e.org_id = public.my_org() and public.my_department_id() is not null and e.department_id = public.my_department_id()
$$;

-- ---------- 5. RLS (faqat o'qish; yozuv faqat RPC orqali) ----------
alter table public.skills enable row level security;
alter table public.skill_assessments enable row level security;
alter table public.competency_requirements enable row level security;
drop policy if exists skills_select_007c on public.skills;
create policy skills_select_007c on public.skills for select to authenticated using (org_id = public.my_org());
drop policy if exists skill_assessments_select_007c on public.skill_assessments;
-- Set-based predikat: rol / ruxsat / bo'lim xodimlari bir marta hisoblanadi (InitPlan), qator boshiga funksiya chaqiruvi yo'q.
create policy skill_assessments_select_007c on public.skill_assessments for select to authenticated using (
  org_id = (select public.my_org()) and (
    employee_id = (select public.my_employee_id())
    or ((select public.my_role()) in ('super_admin', 'education_manager', 'hr') and (select public.has_perm('skill.view')))
    or ((select public.my_role()) = 'department_head' and (select public.has_perm('skill.view')) and employee_id in (select public._sk_my_dept_employees_007c()))));
drop policy if exists cr_select_007c on public.competency_requirements;
create policy cr_select_007c on public.competency_requirements for select to authenticated using (org_id = public.my_org());
revoke all on public.skills, public.skill_assessments, public.competency_requirements from anon, authenticated;
grant select on public.skills, public.skill_assessments, public.competency_requirements to authenticated;

-- ---------- 6. RPC: ko'nikma katalogi ----------
create or replace function public.upsert_skill(p_id uuid, p_code text, p_name text, p_description text default null, p_category text default null,
                                                p_specialty uuid default null, p_max_level int default 5) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_org uuid := public.my_org(); s public.skills; o public.skills;
begin
  if auth.uid() is null or v_org is null or not public.has_perm('skill.manage') then raise exception 'Ruxsat yo''q: ko''nikmalarni boshqarish (skill.manage)'; end if;
  if p_specialty is not null and not exists (select 1 from public.specialties where id = p_specialty and org_id = v_org) then raise exception 'Mutaxassislik topilmadi yoki ruxsat yo''q'; end if;
  if p_id is null then
    insert into public.skills (org_id, code, name, description, category, specialty_id, max_level, created_by, updated_by)
      values (v_org, trim(p_code), trim(p_name), nullif(trim(p_description), ''), nullif(trim(p_category), ''), p_specialty, coalesce(p_max_level, 5), auth.uid(), auth.uid())
      returning * into s;
    perform public._audit006(v_org, 'skill', 'skill.created', s.id::text, null, jsonb_build_object('code', s.code, 'name', s.name, 'max_level', s.max_level));
    return jsonb_build_object('skill_id', s.id, 'state', 'created');
  end if;
  select * into o from public.skills where id = p_id and org_id = v_org for update;
  if o.id is null then raise exception 'Ko''nikma topilmadi yoki ruxsat yo''q'; end if;
  if o.status <> 'active' then raise exception 'Arxivlangan ko''nikmani tahrirlab bo''lmaydi'; end if;
  if p_code is not null and trim(p_code) <> o.code then raise exception 'Ko''nikma kodi o''zgarmaydi'; end if;
  if (trim(p_name), nullif(trim(p_description), ''), nullif(trim(p_category), ''), p_specialty, coalesce(p_max_level, o.max_level)::smallint)
     is not distinct from (o.name, o.description, o.category, o.specialty_id, o.max_level) then
    return jsonb_build_object('skill_id', o.id, 'state', 'unchanged');
  end if;
  update public.skills set name = trim(p_name), description = nullif(trim(p_description), ''), category = nullif(trim(p_category), ''),
    specialty_id = p_specialty, max_level = coalesce(p_max_level, o.max_level), updated_by = auth.uid() where id = o.id returning * into s;
  perform public._audit006(v_org, 'skill', 'skill.updated', s.id::text,
    jsonb_build_object('name', o.name, 'category', o.category, 'max_level', o.max_level), jsonb_build_object('name', s.name, 'category', s.category, 'max_level', s.max_level));
  return jsonb_build_object('skill_id', s.id, 'state', 'updated');
end $$;

create or replace function public.archive_skill(p_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.skills;
begin
  if auth.uid() is null or not public.has_perm('skill.manage') then raise exception 'Ruxsat yo''q: ko''nikmalarni boshqarish (skill.manage)'; end if;
  if length(coalesce(trim(p_reason), '')) < 3 then raise exception 'Arxivlash sababi majburiy'; end if;
  select * into o from public.skills where id = p_id and org_id = public.my_org() for update;
  if o.id is null then raise exception 'Ko''nikma topilmadi yoki ruxsat yo''q'; end if;
  if o.status = 'archived' then return jsonb_build_object('skill_id', o.id, 'changed', false); end if;
  update public.skills set status = 'archived', archived_at = now(), updated_by = auth.uid() where id = o.id;
  perform public._audit006(o.org_id, 'skill', 'skill.archived', o.id::text, jsonb_build_object('status', 'active'), jsonb_build_object('status', 'archived', 'reason', trim(p_reason)));
  return jsonb_build_object('skill_id', o.id, 'changed', true);
end $$;

-- ---------- 7. RPC: baholash (insert-only) ----------
create or replace function public.record_skill_assessment(p_employee uuid, p_skill uuid, p_level int, p_notes text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_org uuid := public.my_org(); v_role text := public.my_role(); e public.employees; s public.skills; a public.skill_assessments;
begin
  if auth.uid() is null or v_org is null or not public.has_perm('skill.assess') then raise exception 'Ruxsat yo''q: ko''nikmani baholash (skill.assess)'; end if;
  select * into e from public.employees where id = p_employee and org_id = v_org;
  if e.id is null then raise exception 'Xodim topilmadi yoki ruxsat yo''q'; end if;
  if e.profile_id = auth.uid() then raise exception 'O''zingizni baholay olmaysiz'; end if;
  if e.employment_status not in ('active', 'on_leave') then raise exception 'Nofaol xodim baholanmaydi'; end if;
  if v_role = 'department_head' and (public.my_department_id() is null or e.department_id is distinct from public.my_department_id()) then
    raise exception 'Department Head faqat o''z bo''limi xodimlarini baholaydi';
  end if;
  if v_role not in ('super_admin', 'education_manager', 'department_head') then raise exception 'Ruxsat yo''q: baholash roli'; end if;
  select * into s from public.skills where id = p_skill and org_id = v_org;
  if s.id is null then raise exception 'Ko''nikma topilmadi yoki ruxsat yo''q'; end if;
  if s.status <> 'active' then raise exception 'Arxivlangan ko''nikma baholanmaydi'; end if;
  if p_level is null or p_level < 0 or p_level > s.max_level then raise exception 'Daraja 0..% oralig''ida bo''lishi kerak', s.max_level; end if;
  insert into public.skill_assessments (org_id, skill_id, employee_id, assessor_id, level, notes)
    values (v_org, s.id, e.id, auth.uid(), p_level, nullif(trim(p_notes), '')) returning * into a;
  perform public._audit006(v_org, 'skill_assessment', 'skill.assessment_created', a.id::text, null,
    jsonb_build_object('employee_id', e.id, 'skill_id', s.id, 'level', p_level, 'max_level', s.max_level));
  return jsonb_build_object('assessment_id', a.id, 'level', a.level, 'assessed_at', a.assessed_at);
end $$;

-- ---------- 8. RPC: kompetensiya talablari ----------
create or replace function public.set_competency_requirement(p_skill uuid, p_target_type text, p_target_id text, p_required_level int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_org uuid := public.my_org(); s public.skills; r public.competency_requirements; v_dept uuid; v_pos uuid; v_spec uuid; v_role text; v_old smallint;
begin
  if auth.uid() is null or v_org is null or not public.has_perm('competency.manage') then raise exception 'Ruxsat yo''q: kompetensiya talablari (competency.manage)'; end if;
  select * into s from public.skills where id = p_skill and org_id = v_org;
  if s.id is null then raise exception 'Ko''nikma topilmadi yoki ruxsat yo''q'; end if;
  if s.status <> 'active' then raise exception 'Arxivlangan ko''nikmaga talab qo''yilmaydi'; end if;
  if p_required_level is null or p_required_level < 1 or p_required_level > s.max_level then raise exception 'Talab darajasi 1..% oralig''ida bo''lishi kerak', s.max_level; end if;
  if nullif(trim(p_target_id), '') is null then raise exception 'Nishon majburiy'; end if;
  begin
    case p_target_type
      when 'department' then v_dept := p_target_id::uuid;
        if not exists (select 1 from public.departments where id = v_dept and org_id = v_org and status = 'active') then raise exception 'Bo''lim topilmadi, nofaol yoki ruxsat yo''q'; end if;
      when 'position' then v_pos := p_target_id::uuid;
        if not exists (select 1 from public.positions where id = v_pos and org_id = v_org and status = 'active') then raise exception 'Lavozim topilmadi, nofaol yoki ruxsat yo''q'; end if;
      when 'specialty' then v_spec := p_target_id::uuid;
        if not exists (select 1 from public.specialties where id = v_spec and org_id = v_org and status = 'active') then raise exception 'Mutaxassislik topilmadi, nofaol yoki ruxsat yo''q'; end if;
      when 'role' then v_role := p_target_id;
        if v_role not in ('super_admin','hr','education_manager','department_head','instructor','employee','medical_reviewer','content_author') then raise exception 'Noma''lum rol'; end if;
      else raise exception 'Noma''lum nishon turi: %', p_target_type;
    end case;
  exception when invalid_text_representation then raise exception 'Nishon identifikatori noto''g''ri';
  end;
  select * into r from public.competency_requirements where skill_id = s.id and target_type = p_target_type and status = 'active'
     and target_key = coalesce(v_dept::text, v_pos::text, v_spec::text, v_role) for update;
  if r.id is null then
    insert into public.competency_requirements (org_id, skill_id, target_type, department_id, position_id, specialty_id, target_role, required_level, created_by, updated_by)
      values (v_org, s.id, p_target_type, v_dept, v_pos, v_spec, v_role, p_required_level, auth.uid(), auth.uid()) returning * into r;
    perform public._audit006(v_org, 'competency_requirement', 'competency_requirement.created', r.id::text, null,
      jsonb_build_object('skill_id', s.id, 'target_type', p_target_type, 'target', r.target_key, 'required_level', p_required_level));
    return jsonb_build_object('requirement_id', r.id, 'state', 'created');
  end if;
  if r.required_level = p_required_level then return jsonb_build_object('requirement_id', r.id, 'state', 'unchanged'); end if;
  v_old := r.required_level;
  update public.competency_requirements set required_level = p_required_level, updated_by = auth.uid() where id = r.id;
  perform public._audit006(v_org, 'competency_requirement', 'competency_requirement.updated', r.id::text,
    jsonb_build_object('required_level', v_old), jsonb_build_object('required_level', p_required_level));
  return jsonb_build_object('requirement_id', r.id, 'state', 'updated');
end $$;

create or replace function public.archive_competency_requirement(p_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.competency_requirements;
begin
  if auth.uid() is null or not public.has_perm('competency.manage') then raise exception 'Ruxsat yo''q: kompetensiya talablari (competency.manage)'; end if;
  if length(coalesce(trim(p_reason), '')) < 3 then raise exception 'Arxivlash sababi majburiy'; end if;
  select * into r from public.competency_requirements where id = p_id and org_id = public.my_org() for update;
  if r.id is null then raise exception 'Talab topilmadi yoki ruxsat yo''q'; end if;
  if r.status = 'archived' then return jsonb_build_object('requirement_id', r.id, 'changed', false); end if;
  update public.competency_requirements set status = 'archived', archived_at = now(), updated_by = auth.uid() where id = r.id;
  perform public._audit006(r.org_id, 'competency_requirement', 'competency_requirement.archived', r.id::text,
    jsonb_build_object('status', 'active'), jsonb_build_object('status', 'archived', 'reason', trim(p_reason)));
  return jsonb_build_object('requirement_id', r.id, 'changed', true);
end $$;

-- ---------- 9. Kompetensiya hisoblari (o'qish, audit yozmaydi) ----------
create or replace function public._sk_emp_competency_007c(p_org uuid, p_emp uuid[])
returns table (employee_id uuid, skill_id uuid, required_level int, achieved_level int, assessed_at timestamptz, assessor_id uuid, status text)
language sql stable security definer set search_path = public as $$
  with emp as (
    select e.id, e.department_id, e.position_id, e.specialty_id, p.role, p.status pstatus
    from public.employees e left join public.profiles p on p.id = e.profile_id
    where e.org_id = p_org and e.id = any(p_emp)
  ), req as (
    select emp.id employee_id, cr.skill_id, max(cr.required_level)::int required_level
    from emp join public.competency_requirements cr on cr.org_id = p_org and cr.status = 'active'
      and ((cr.target_type = 'department' and cr.department_id = emp.department_id)
        or (cr.target_type = 'position' and cr.position_id = emp.position_id)
        or (cr.target_type = 'specialty' and cr.specialty_id = emp.specialty_id)
        or (cr.target_type = 'role' and cr.target_role = emp.role and emp.pstatus = 'active'))
    join public.skills s on s.id = cr.skill_id and s.status = 'active'
    group by 1, 2
  ), last as (
    select distinct on (a.employee_id, a.skill_id) a.employee_id, a.skill_id, a.level::int, a.assessed_at, a.assessor_id
    from public.skill_assessments a where a.org_id = p_org and a.employee_id = any(p_emp)
    order by a.employee_id, a.skill_id, a.assessed_at desc, a.assessment_seq desc
  )
  select coalesce(req.employee_id, last.employee_id), coalesce(req.skill_id, last.skill_id), req.required_level, last.level, last.assessed_at, last.assessor_id,
         case when req.required_level is null then 'not_required'
              when last.level is null then 'not_assessed'
              when last.level >= req.required_level then 'achieved' else 'not_achieved' end
  from req full join last on last.employee_id = req.employee_id and last.skill_id = req.skill_id
$$;

create or replace function public.employee_competency_summary(p_employee uuid default null)
returns table (skill_id uuid, skill_code text, skill_name text, max_level int, required_level int, achieved_level int, assessed_at timestamptz, status text)
language plpgsql stable security definer set search_path = public as $$
declare v_emp uuid := coalesce(p_employee, public.my_employee_id());
begin
  if auth.uid() is null then raise exception 'Ruxsat yo''q'; end if;
  if v_emp is null then return; end if;
  if not public._sk_can_view_employee_007c(v_emp) then raise exception 'Ruxsat yo''q: bu xodim kompetensiyasini ko''rish'; end if;
  return query
    select c.skill_id, s.code, s.name, s.max_level::int, c.required_level, c.achieved_level, c.assessed_at, c.status
    from public._sk_emp_competency_007c(public.my_org(), array[v_emp]) c join public.skills s on s.id = c.skill_id
    order by (c.status = 'not_required'), s.name;
end $$;

create or replace function public.department_competency_summary(p_department uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_org uuid := public.my_org(); v_role text := public.my_role(); v_emps uuid[]; r jsonb;
begin
  if auth.uid() is null or v_org is null or not public.has_perm('skill.view') then raise exception 'Ruxsat yo''q'; end if;
  if not exists (select 1 from public.departments where id = p_department and org_id = v_org) then raise exception 'Bo''lim topilmadi yoki ruxsat yo''q'; end if;
  if v_role = 'department_head' then
    if public.my_department_id() is distinct from p_department then raise exception 'Department Head faqat o''z bo''limini ko''radi'; end if;
  elsif v_role not in ('super_admin', 'education_manager', 'hr') then raise exception 'Ruxsat yo''q';
  end if;
  select array_agg(id) into v_emps from public.employees where org_id = v_org and department_id = p_department and employment_status in ('active', 'on_leave');
  select jsonb_build_object('department_id', p_department, 'employees', coalesce(array_length(v_emps, 1), 0),
           'skills', coalesce(jsonb_agg(x order by x ->> 'skill_code'), '[]'::jsonb))
    into r
  from (select jsonb_build_object('skill_id', s.id, 'skill_code', s.code, 'required', count(*) filter (where c.required_level is not null),
               'achieved', count(*) filter (where c.status = 'achieved'), 'not_achieved', count(*) filter (where c.status = 'not_achieved'),
               'not_assessed', count(*) filter (where c.status = 'not_assessed')) x
        from public._sk_emp_competency_007c(v_org, coalesce(v_emps, '{}')) c join public.skills s on s.id = c.skill_id
        where c.required_level is not null group by s.id, s.code) t;
  return r;
end $$;

-- ---------- 10. Huquqlar va ro'yxatga olish ----------
revoke execute on function public._sk_seed_perms_007c(uuid) from public, anon, authenticated;
revoke execute on function public.seed_org_skill_perms_007c() from public, anon, authenticated;
revoke execute on function public.guard_skill_007c() from public, anon, authenticated;
revoke execute on function public.guard_skill_assessment_007c() from public, anon, authenticated;
revoke execute on function public.guard_skill_assessment_truncate_007c() from public, anon, authenticated;
revoke execute on function public.guard_competency_req_007c() from public, anon, authenticated;
revoke execute on function public._sk_can_view_employee_007c(uuid) from public, anon, authenticated;
revoke execute on function public._sk_my_dept_employees_007c() from public, anon;
grant execute on function public._sk_my_dept_employees_007c() to authenticated;  -- RLS predikati (rls_helper): faqat joriy foydalanuvchi bo'limi xodim ID'lari
revoke execute on function public._sk_emp_competency_007c(uuid, uuid[]) from public, anon, authenticated;
revoke execute on function public.upsert_skill(uuid, text, text, text, text, uuid, int) from public, anon;
revoke execute on function public.archive_skill(uuid, text) from public, anon;
revoke execute on function public.record_skill_assessment(uuid, uuid, int, text) from public, anon;
revoke execute on function public.set_competency_requirement(uuid, text, text, int) from public, anon;
revoke execute on function public.archive_competency_requirement(uuid, text) from public, anon;
revoke execute on function public.employee_competency_summary(uuid) from public, anon;
revoke execute on function public.department_competency_summary(uuid) from public, anon;
grant execute on function public.upsert_skill(uuid, text, text, text, text, uuid, int) to authenticated;
grant execute on function public.archive_skill(uuid, text) to authenticated;
grant execute on function public.record_skill_assessment(uuid, uuid, int, text) to authenticated;
grant execute on function public.set_competency_requirement(uuid, text, text, int) to authenticated;
grant execute on function public.archive_competency_requirement(uuid, text) to authenticated;
grant execute on function public.employee_competency_summary(uuid) to authenticated;
grant execute on function public.department_competency_summary(uuid) to authenticated;
do $$ begin
  if to_regclass('backup.function_categories_005d') is not null then
    insert into backup.function_categories_005d (name, category) values
      ('_sk_seed_perms_007c', 'internal'), ('seed_org_skill_perms_007c', 'internal'), ('guard_skill_007c', 'internal'),
      ('guard_skill_assessment_007c', 'internal'), ('guard_skill_assessment_truncate_007c', 'internal'), ('guard_competency_req_007c', 'internal'),
      ('_sk_can_view_employee_007c', 'internal'), ('_sk_my_dept_employees_007c', 'rls_helper'), ('_sk_emp_competency_007c', 'internal'),
      ('upsert_skill', 'role_rpc'), ('archive_skill', 'role_rpc'), ('record_skill_assessment', 'role_rpc'), ('set_competency_requirement', 'role_rpc'),
      ('archive_competency_requirement', 'role_rpc'), ('employee_competency_summary', 'role_rpc'), ('department_competency_summary', 'role_rpc')
    on conflict (name) do update set category = excluded.category;
  end if;
end $$;

insert into public.schema_migrations (version, description) values
  ('007c', 'Skills + competency: skills (archive-only), skill_assessments (insert-only, immutable), competency_requirements (one target, archive-only), 4 permissions, RPCs, read-time competency status')
on conflict (version) do nothing;

commit;

select json_build_object(
  'migration', (select version from public.schema_migrations where version = '007c'),
  'tables', (select count(*) from pg_tables where schemaname = 'public' and tablename in ('skills', 'skill_assessments', 'competency_requirements')),
  'permissions', (select count(*) from public.permissions where key in ('skill.view', 'skill.manage', 'skill.assess', 'competency.manage')),
  'role_permissions', (select count(*) from public.role_permissions where permission_key in ('skill.view', 'skill.manage', 'skill.assess', 'competency.manage')),
  'anon_exec', (select string_agg(p.proname, ',') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')),
  'attempts', (select count(*) from public.exam_attempts), 'certificates', (select count(*) from public.certificates)
)::text as result_007c;
