-- MedAcademy · Migration 004a — Tashkiliy tuzilma, xodimlar, ruxsatlar, server audit
-- Faqat qo'shadi (ADD). DROP TABLE / TRUNCATE / DELETE yo'q. Qayta ishga tushirish xavfsiz (idempotent).
-- Mavjud jadvallarga ta'sir: organizations'ga 3 ustun qo'shiladi; profiles.department (matn) SAQLANADI.

-- ---------- 0. Migratsiyalar jurnali ----------
create table if not exists public.schema_migrations (
  version text primary key,
  description text not null,
  applied_at timestamptz not null default now()
);
alter table public.schema_migrations enable row level security;
insert into public.schema_migrations (version, description) values
  ('001', 'Base: profiles, docs, auth trigger, RLS'),
  ('002', 'Phase 1: server-side exams, certificates, questions security'),
  ('003', 'Phase 1: content seed (13 courses, 131 questions)')
on conflict (version) do nothing;

-- ---------- 1. Organizations (mavjud jadval — faqat ustun qo'shiladi) ----------
alter table public.organizations add column if not exists code text;
alter table public.organizations add column if not exists status text not null default 'active';
alter table public.organizations add column if not exists updated_at timestamptz not null default now();
do $$ begin
  alter table public.organizations add constraint organizations_status_chk check (status in ('active','inactive'));
exception when duplicate_object then null; end $$;
update public.organizations set code = 'IMPULS' where id = '00000000-0000-0000-0000-000000000001' and code is null;
create unique index if not exists organizations_code_uq on public.organizations (code) where code is not null;

-- ---------- 2. Yordamchi funksiyalar ----------
-- API so'rovi (PostgREST JWT bilan) yoki to'g'ridan-to'g'ri SQL (SQL Editor / migratsiya) ekanini aniqlaydi
create or replace function public.is_api_request() returns boolean language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), nullif(current_setting('request.jwt.claim.sub', true), '')) is not null
$$;
create or replace function public.my_org() returns uuid language sql stable security definer set search_path = public as $$
  select org_id from public.profiles where id = auth.uid() and status = 'active'
$$;
create or replace function public.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;

-- ---------- 3. Branches ----------
create table if not exists public.branches (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete restrict,
  name text not null check (length(trim(name)) > 0),
  code text not null check (code ~ '^[A-Z0-9_-]{2,32}$'),
  address text,
  phone text,
  status text not null default 'active' check (status in ('active','inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint branches_org_code_uq unique (org_id, code)
);

-- ---------- 4. Departments ----------
create table if not exists public.departments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete restrict,
  branch_id uuid references public.branches(id) on delete restrict,
  name text not null check (length(trim(name)) > 0),
  code text not null check (code ~ '^[A-Z0-9_-]{2,32}$'),
  description text,
  parent_department_id uuid references public.departments(id) on delete set null,
  head_employee_id uuid,
  status text not null default 'active' check (status in ('active','inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint departments_org_code_uq unique (org_id, code),
  constraint departments_not_own_parent check (parent_department_id is null or parent_department_id <> id)
);
create index if not exists departments_branch_idx on public.departments (branch_id);

-- ---------- 5. Positions ----------
create table if not exists public.positions (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete restrict,
  name text not null check (length(trim(name)) > 0),
  code text not null check (code ~ '^[A-Z0-9_-]{2,32}$'),
  description text,
  academy text,   -- curriculum engine uchun (RES_START, NURSE, RECEPTION ...)
  family text,    -- doctor, resident, nurse, reception, sanitary, assistant, admin
  status text not null default 'active' check (status in ('active','inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint positions_org_code_uq unique (org_id, code)
);

-- ---------- 6. Specialties ----------
create table if not exists public.specialties (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete restrict,
  name text not null check (length(trim(name)) > 0),
  code text not null check (code ~ '^[A-Z0-9_-]{2,32}$'),
  description text,
  status text not null default 'active' check (status in ('active','inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint specialties_org_code_uq unique (org_id, code)
);

-- ---------- 7. Employees (HR yozuvi; profiles'ni almashtirmaydi) ----------
create table if not exists public.employees (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete restrict,
  profile_id uuid references public.profiles(id) on delete set null,   -- akkauntsiz xodim ham bo'lishi mumkin
  employee_code text not null check (length(trim(employee_code)) > 0),
  first_name text,
  last_name text,
  branch_id uuid references public.branches(id) on delete restrict,
  department_id uuid references public.departments(id) on delete restrict,
  position_id uuid references public.positions(id) on delete restrict,
  specialty_id uuid references public.specialties(id) on delete set null,
  employment_status text not null default 'active' check (employment_status in ('active','on_leave','inactive','terminated')),
  hire_date date,
  termination_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint employees_org_code_uq unique (org_id, employee_code),
  constraint employees_profile_uq unique (profile_id),
  constraint employees_dates_chk check (termination_date is null or hire_date is null or termination_date >= hire_date)
);
create index if not exists employees_department_idx on public.employees (department_id);
create index if not exists employees_position_idx on public.employees (position_id);
create index if not exists employees_branch_idx on public.employees (branch_id);
create index if not exists employees_specialty_idx on public.employees (specialty_id);
create index if not exists employees_org_status_idx on public.employees (org_id, employment_status);

do $$ begin
  alter table public.departments add constraint departments_head_fk foreign key (head_employee_id) references public.employees(id) on delete set null;
exception when duplicate_object then null; end $$;

-- ---------- 8. Bog'langan yozuvlar bir tashkilotda bo'lishi (cross-org bog'lanishni taqiqlash) ----------
create or replace function public.enforce_same_org() returns trigger language plpgsql security definer set search_path = public as $$
declare bad text;
begin
  if tg_op = 'UPDATE' and new.org_id is distinct from old.org_id then
    raise exception 'org_id o''zgartirilmaydi';
  end if;
  if tg_table_name = 'departments' then
    if new.branch_id is not null and (select org_id from public.branches where id = new.branch_id) is distinct from new.org_id then bad := 'branch'; end if;
    if new.parent_department_id is not null and (select org_id from public.departments where id = new.parent_department_id) is distinct from new.org_id then bad := 'parent_department'; end if;
    if new.head_employee_id is not null and (select org_id from public.employees where id = new.head_employee_id) is distinct from new.org_id then bad := 'head_employee'; end if;
  elsif tg_table_name = 'employees' then
    if new.profile_id is not null and (select org_id from public.profiles where id = new.profile_id) is distinct from new.org_id then bad := 'profile'; end if;
    if new.branch_id is not null and (select org_id from public.branches where id = new.branch_id) is distinct from new.org_id then bad := 'branch'; end if;
    if new.department_id is not null and (select org_id from public.departments where id = new.department_id) is distinct from new.org_id then bad := 'department'; end if;
    if new.position_id is not null and (select org_id from public.positions where id = new.position_id) is distinct from new.org_id then bad := 'position'; end if;
    if new.specialty_id is not null and (select org_id from public.specialties where id = new.specialty_id) is distinct from new.org_id then bad := 'specialty'; end if;
  end if;
  if bad is not null then raise exception 'Boshqa tashkilotga tegishli % bog''lanmaydi', bad; end if;
  return new;
end $$;

-- ---------- 9. Ruxsatlar ----------
create table if not exists public.permissions (
  key text primary key check (key ~ '^[a-z_]+\.[a-z_]+$'),
  category text not null,
  description text not null,
  created_at timestamptz not null default now()
);
insert into public.permissions (key, category, description) values
  ('employee.view','employee','Xodimlarni ko''rish'),
  ('employee.create','employee','Xodim qo''shish'),
  ('employee.edit','employee','Xodim ma''lumotlarini tahrirlash'),
  ('employee.deactivate','employee','Xodimni faolsizlantirish'),
  ('branch.view','organization','Filiallarni ko''rish'),
  ('branch.manage','organization','Filiallarni boshqarish'),
  ('department.view','organization','Barcha bo''limlarni ko''rish'),
  ('department.manage','organization','Bo''limlarni boshqarish'),
  ('position.view','organization','Lavozimlarni ko''rish'),
  ('position.manage','organization','Lavozimlarni boshqarish'),
  ('specialty.view','organization','Mutaxassisliklarni ko''rish'),
  ('specialty.manage','organization','Mutaxassisliklarni boshqarish'),
  ('course.view','education','Kurslarni ko''rish'),
  ('course.create','education','Kurs yaratish'),
  ('course.edit','education','Kursni tahrirlash'),
  ('course.publish','education','Kursni nashr qilish'),
  ('question.view','assessment','Savollar bankini ko''rish'),
  ('question.create','assessment','Savol yaratish'),
  ('question.edit','assessment','Savolni tahrirlash'),
  ('question.approve','assessment','Savolni tasdiqlash'),
  ('exam.view','assessment','Imtihonlarni ko''rish'),
  ('exam.create','assessment','Imtihon yaratish'),
  ('exam.manage','assessment','Imtihon qoidalari va urinishlarni boshqarish'),
  ('assessment.view','assessment','Baholash natijalarini ko''rish'),
  ('certificate.view','certification','Sertifikatlarni ko''rish'),
  ('certificate.revoke','certification','Sertifikatni bekor qilish'),
  ('report.view','analytics','Hisobotlarni ko''rish'),
  ('audit.view','analytics','Audit log''ni ko''rish'),
  ('settings.manage','system','Tizim sozlamalari va ruxsatlarni boshqarish')
on conflict (key) do nothing;

create table if not exists public.role_permissions (
  org_id uuid not null references public.organizations(id) on delete restrict,
  role text not null check (role in ('super_admin','hr','education_manager','department_head','instructor','employee')),
  permission_key text not null references public.permissions(key) on update cascade on delete restrict,
  granted_by uuid references auth.users,
  granted_at timestamptz not null default now(),
  primary key (org_id, role, permission_key)
);

create or replace function public.has_perm(p text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.my_role() = 'super_admin', false)
      or exists (select 1 from public.role_permissions rp
                 where rp.org_id = public.my_org() and rp.role = public.my_role() and rp.permission_key = p)
$$;
create or replace function public.my_employee_id() returns uuid language sql stable security definer set search_path = public as $$
  select e.id from public.employees e where e.profile_id = auth.uid() and e.org_id = public.my_org() and e.employment_status in ('active','on_leave')
$$;
create or replace function public.my_department_id() returns uuid language sql stable security definer set search_path = public as $$
  select e.department_id from public.employees e where e.profile_id = auth.uid() and e.org_id = public.my_org() and e.employment_status in ('active','on_leave')
$$;

-- Standart rol → ruxsat matritsasi (har yangi tashkilotga avtomatik)
create or replace function public.seed_org_defaults(p_org uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.role_permissions (org_id, role, permission_key)
  select p_org, m.role, m.perm from (values
    -- HR
    ('hr','employee.view'),('hr','employee.create'),('hr','employee.edit'),('hr','employee.deactivate'),
    ('hr','branch.view'),('hr','branch.manage'),('hr','department.view'),('hr','department.manage'),
    ('hr','position.view'),('hr','position.manage'),('hr','specialty.view'),('hr','specialty.manage'),
    ('hr','course.view'),('hr','exam.view'),('hr','assessment.view'),('hr','certificate.view'),('hr','report.view'),
    -- Education Manager
    ('education_manager','employee.view'),('education_manager','branch.view'),('education_manager','department.view'),
    ('education_manager','position.view'),('education_manager','specialty.view'),
    ('education_manager','course.view'),('education_manager','course.create'),('education_manager','course.edit'),('education_manager','course.publish'),
    ('education_manager','question.view'),('education_manager','question.create'),('education_manager','question.edit'),('education_manager','question.approve'),
    ('education_manager','exam.view'),('education_manager','exam.create'),('education_manager','exam.manage'),
    ('education_manager','assessment.view'),('education_manager','certificate.view'),('education_manager','certificate.revoke'),('education_manager','report.view'),
    -- Instructor (kurslarga biriktirish 005-migratsiyada)
    ('instructor','branch.view'),('instructor','position.view'),('instructor','specialty.view'),
    ('instructor','course.view'),('instructor','question.view'),('instructor','question.create'),('instructor','question.edit'),
    ('instructor','exam.view'),('instructor','assessment.view'),
    -- Department Head (o'z bo'limi qoida orqali; employee.view/department.view BERILMAYDI)
    ('department_head','branch.view'),('department_head','position.view'),('department_head','specialty.view'),
    ('department_head','course.view'),('department_head','assessment.view'),('department_head','report.view'),
    -- Employee
    ('employee','branch.view'),('employee','position.view'),('employee','specialty.view'),('employee','course.view')
  ) as m(role, perm)
  on conflict do nothing;
end $$;
create or replace function public.on_org_created() returns trigger language plpgsql security definer set search_path = public as $$
begin perform public.seed_org_defaults(new.id); return new; end $$;
drop trigger if exists on_org_created_trg on public.organizations;
create trigger on_org_created_trg after insert on public.organizations for each row execute function public.on_org_created();

-- ---------- 10. Server tomonidagi audit ----------
create table if not exists public.audit_logs (
  id bigserial primary key,
  org_id uuid not null references public.organizations(id) on delete restrict,
  actor_id uuid,
  actor_role text,
  action text not null,
  entity text not null,
  entity_id text,
  old_value jsonb,
  new_value jsonb,
  ip text,
  created_at timestamptz not null default now()
);
create index if not exists audit_logs_org_time_idx on public.audit_logs (org_id, created_at desc);
create index if not exists audit_logs_entity_idx on public.audit_logs (entity, entity_id);

create or replace function public.audit_row() returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_old jsonb := case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end;
  v_new jsonb := case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end;
  v_entity text := case tg_table_name when 'branches' then 'branch' when 'departments' then 'department' when 'positions' then 'position'
                    when 'specialties' then 'specialty' when 'employees' then 'employee' when 'role_permissions' then 'permission' else tg_table_name end;
  v_action text; v_id text; v_ip text;
begin
  if tg_op = 'UPDATE' and (v_old - 'updated_at') = (v_new - 'updated_at') then return new; end if;
  v_action := v_entity || case tg_op when 'INSERT' then '.created' when 'DELETE' then '.deleted' else '.updated' end;
  if tg_table_name = 'role_permissions' then
    v_action := case tg_op when 'INSERT' then 'permission.granted' when 'DELETE' then 'permission.revoked' else 'permission.changed' end;
    v_id := (coalesce(v_new, v_old) ->> 'role') || ':' || (coalesce(v_new, v_old) ->> 'permission_key');
  else
    v_id := coalesce(v_new, v_old) ->> 'id';
  end if;
  if tg_op = 'UPDATE' then
    if coalesce(v_old ->> 'employment_status', v_old ->> 'status') = 'active'
       and coalesce(v_new ->> 'employment_status', v_new ->> 'status') in ('inactive','terminated') then
      v_action := v_entity || '.deactivated';
    end if;
  end if;
  begin v_ip := nullif(split_part(coalesce(current_setting('request.headers', true)::json ->> 'x-forwarded-for', ''), ',', 1), '');
  exception when others then v_ip := null; end;
  insert into public.audit_logs (org_id, actor_id, actor_role, action, entity, entity_id, old_value, new_value, ip)
  values ((coalesce(v_new, v_old) ->> 'org_id')::uuid, auth.uid(), public.my_role(), v_action, v_entity, v_id, v_old, v_new, v_ip);
  return coalesce(new, old);
end $$;

-- Faolsizlantirish uchun alohida ruxsat (employee.edit yetarli emas)
create or replace function public.guard_employee() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_api_request() and new.employment_status is distinct from old.employment_status
     and new.employment_status in ('inactive','terminated') and not public.has_perm('employee.deactivate') then
    raise exception 'Xodimni faolsizlantirish uchun employee.deactivate ruxsati kerak';
  end if;
  return new;
end $$;

-- ---------- 11. Trigger'lar ----------
do $$
declare t text;
begin
  foreach t in array array['branches','departments','positions','specialties','employees'] loop
    execute format('drop trigger if exists %1$s_touch_trg on public.%1$s', t);
    execute format('create trigger %1$s_touch_trg before update on public.%1$s for each row execute function public.touch_updated_at()', t);
    execute format('drop trigger if exists %1$s_audit_trg on public.%1$s', t);
    execute format('create trigger %1$s_audit_trg after insert or update or delete on public.%1$s for each row execute function public.audit_row()', t);
  end loop;
end $$;
drop trigger if exists departments_same_org_trg on public.departments;
create trigger departments_same_org_trg before insert or update on public.departments for each row execute function public.enforce_same_org();
drop trigger if exists employees_same_org_trg on public.employees;
create trigger employees_same_org_trg before insert or update on public.employees for each row execute function public.enforce_same_org();
drop trigger if exists employees_guard_trg on public.employees;
create trigger employees_guard_trg before update on public.employees for each row execute function public.guard_employee();
drop trigger if exists role_permissions_audit_trg on public.role_permissions;
create trigger role_permissions_audit_trg after insert or update or delete on public.role_permissions for each row execute function public.audit_row();

-- ---------- 12. RLS ----------
alter table public.branches enable row level security;
alter table public.departments enable row level security;
alter table public.positions enable row level security;
alter table public.specialties enable row level security;
alter table public.employees enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.audit_logs enable row level security;

drop policy if exists branches_select on public.branches;
create policy branches_select on public.branches for select to authenticated using (org_id = public.my_org() and public.has_perm('branch.view'));
drop policy if exists branches_insert on public.branches;
create policy branches_insert on public.branches for insert to authenticated with check (org_id = public.my_org() and public.has_perm('branch.manage'));
drop policy if exists branches_update on public.branches;
create policy branches_update on public.branches for update to authenticated
  using (org_id = public.my_org() and public.has_perm('branch.manage')) with check (org_id = public.my_org() and public.has_perm('branch.manage'));

drop policy if exists departments_select on public.departments;
create policy departments_select on public.departments for select to authenticated
  using (org_id = public.my_org() and (public.has_perm('department.view') or id = public.my_department_id()));
drop policy if exists departments_insert on public.departments;
create policy departments_insert on public.departments for insert to authenticated with check (org_id = public.my_org() and public.has_perm('department.manage'));
drop policy if exists departments_update on public.departments;
create policy departments_update on public.departments for update to authenticated
  using (org_id = public.my_org() and public.has_perm('department.manage')) with check (org_id = public.my_org() and public.has_perm('department.manage'));

drop policy if exists positions_select on public.positions;
create policy positions_select on public.positions for select to authenticated using (org_id = public.my_org() and public.has_perm('position.view'));
drop policy if exists positions_insert on public.positions;
create policy positions_insert on public.positions for insert to authenticated with check (org_id = public.my_org() and public.has_perm('position.manage'));
drop policy if exists positions_update on public.positions;
create policy positions_update on public.positions for update to authenticated
  using (org_id = public.my_org() and public.has_perm('position.manage')) with check (org_id = public.my_org() and public.has_perm('position.manage'));

drop policy if exists specialties_select on public.specialties;
create policy specialties_select on public.specialties for select to authenticated using (org_id = public.my_org() and public.has_perm('specialty.view'));
drop policy if exists specialties_insert on public.specialties;
create policy specialties_insert on public.specialties for insert to authenticated with check (org_id = public.my_org() and public.has_perm('specialty.manage'));
drop policy if exists specialties_update on public.specialties;
create policy specialties_update on public.specialties for update to authenticated
  using (org_id = public.my_org() and public.has_perm('specialty.manage')) with check (org_id = public.my_org() and public.has_perm('specialty.manage'));

drop policy if exists employees_select on public.employees;
create policy employees_select on public.employees for select to authenticated using (
  org_id = public.my_org() and (
    public.has_perm('employee.view')
    or profile_id = auth.uid()
    or (public.my_role() = 'department_head' and department_id is not null and department_id = public.my_department_id())
  ));
drop policy if exists employees_insert on public.employees;
create policy employees_insert on public.employees for insert to authenticated with check (org_id = public.my_org() and public.has_perm('employee.create'));
drop policy if exists employees_update on public.employees;
create policy employees_update on public.employees for update to authenticated
  using (org_id = public.my_org() and public.has_perm('employee.edit')) with check (org_id = public.my_org() and public.has_perm('employee.edit'));
-- Hard delete uchun policy yo'q: o'chirish o'rniga employment_status / status ishlatiladi

drop policy if exists permissions_select on public.permissions;
create policy permissions_select on public.permissions for select to authenticated using (public.my_role() is not null);

drop policy if exists role_permissions_select on public.role_permissions;
create policy role_permissions_select on public.role_permissions for select to authenticated
  using (org_id = public.my_org() and (public.has_perm('settings.manage') or role = public.my_role()));
drop policy if exists role_permissions_insert on public.role_permissions;
create policy role_permissions_insert on public.role_permissions for insert to authenticated
  with check (org_id = public.my_org() and public.has_perm('settings.manage'));
drop policy if exists role_permissions_delete on public.role_permissions;
create policy role_permissions_delete on public.role_permissions for delete to authenticated
  using (org_id = public.my_org() and public.has_perm('settings.manage'));

drop policy if exists audit_logs_select on public.audit_logs;
create policy audit_logs_select on public.audit_logs for select to authenticated using (org_id = public.my_org() and public.has_perm('audit.view'));
-- audit_logs: klient yoza olmaydi (insert/update/delete policy yo'q); faqat trigger yozadi

revoke all on public.branches, public.departments, public.positions, public.specialties, public.employees,
  public.permissions, public.role_permissions, public.audit_logs, public.schema_migrations from anon;
grant select, insert, update on public.branches, public.departments, public.positions, public.specialties, public.employees to authenticated;
grant select on public.permissions, public.audit_logs to authenticated;
grant select, insert, delete on public.role_permissions to authenticated;
grant execute on function public.my_org(), public.has_perm(text), public.my_employee_id(), public.my_department_id(), public.is_api_request() to authenticated;
revoke execute on function public.seed_org_defaults(uuid) from public, anon, authenticated;

-- ---------- 13. Mavjud ma'lumotni yangi tuzilmaga moslashtirish (MIGRATE) ----------
select public.seed_org_defaults(id) from public.organizations;

insert into public.branches (org_id, name, code)
select id, 'Asosiy filial', 'MAIN' from public.organizations
on conflict (org_id, code) do nothing;

insert into public.departments (org_id, branch_id, name, code)
select o.id, b.id, d.name, d.code
from public.organizations o
join public.branches b on b.org_id = o.id and b.code = 'MAIN'
cross join (values ('Kardiologiya','CARDIO'),('Nevrologiya','NEURO'),('Pediatriya','PEDIATRICS'),('Jarrohlik','SURGERY'),
                   ('Ginekologiya','GYNECOLOGY'),('Terapiya','THERAPY'),('Reanimatsiya','ICU'),('Radiologiya','RADIOLOGY'),
                   ('Registratura','RECEPTION'),('Ma''muriyat','ADMIN')) as d(name, code)
where o.id = '00000000-0000-0000-0000-000000000001'
on conflict (org_id, code) do nothing;

insert into public.positions (org_id, name, code, academy, family)
select '00000000-0000-0000-0000-000000000001', p.name, p.code, p.academy, p.family from (values
  ('Intern / yangi shifokor','INTERN','JR_DOC','doctor'), ('Junior Doctor','JUNIOR_DOCTOR','JR_DOC','doctor'),
  ('Doctor (shifokor)','DOCTOR','DOC_PRO','doctor'), ('Experienced Doctor','EXPERIENCED_DOCTOR','DOC_PRO','doctor'),
  ('Senior Doctor','SENIOR_DOCTOR','DOC_PRO','doctor'), ('Specialist','SPECIALIST','DOC_PRO','doctor'), ('Expert','EXPERT','DOC_PRO','doctor'),
  ('Yangi rezident','NEW_RESIDENT','RES_START','resident'), ('Rezident (rezidentura davomida)','RESIDENT','RES_DEV','resident'),
  ('Yangi hamshira','NEW_NURSE','NURSE','nurse'), ('Junior nurse','JUNIOR_NURSE','NURSE','nurse'), ('Hamshira','NURSE','NURSE','nurse'),
  ('Senior nurse','SENIOR_NURSE','NURSE','nurse'), ('Bosh hamshira (Head nurse)','HEAD_NURSE','NURSE','nurse'),
  ('Sanitarka / kichik tibbiy xodim','SANITARY','SANITARY','sanitary'), ('Shifokor yordamchisi','DOC_ASSISTANT','DOC_ASSIST','assistant'),
  ('Registrator','RECEPTIONIST','RECEPTION','reception'), ('Administrator','ADMINISTRATOR','ADMIN','admin')
) as p(name, code, academy, family)
where exists (select 1 from public.organizations where id = '00000000-0000-0000-0000-000000000001')
on conflict (org_id, code) do nothing;

insert into public.specialties (org_id, name, code)
select '00000000-0000-0000-0000-000000000001', s.name, s.code from (values
  ('Kardiologiya','CARDIOLOGY'),('Nevrologiya','NEUROLOGY'),('Pediatriya','PEDIATRICS'),('Jarrohlik','SURGERY'),
  ('Ginekologiya','GYNECOLOGY'),('LOR (ENT)','ENT'),('Urologiya','UROLOGY'),('Terapiya','THERAPY'),
  ('Dermatologiya','DERMATOLOGY'),('Radiologiya','RADIOLOGY'),('Anesteziologiya','ANESTHESIOLOGY')
) as s(name, code)
where exists (select 1 from public.organizations where id = '00000000-0000-0000-0000-000000000001')
on conflict (org_id, code) do nothing;

-- Mavjud profillar → employees (profiles o'zgarmaydi; profiles.department matni saqlanadi)
create or replace function public._safe_date(t text) returns date language plpgsql immutable as $$
begin return nullif(t, '')::timestamptz::date; exception when others then return null; end $$;

insert into public.employees (org_id, profile_id, employee_code, first_name, last_name, branch_id, department_id, position_id, specialty_id, hire_date)
select p.org_id, p.id, 'EMP-' || upper(substr(replace(p.id::text, '-', ''), 1, 8)),
       nullif(e.data ->> 'firstName', ''), nullif(e.data ->> 'lastName', ''),
       b.id, d.id, pos.id, sp.id, public._safe_date(e.data ->> 'hireDate')
from public.profiles p
left join public.docs e on e.collection = 'employees' and e.id = p.id::text
left join public.branches b on b.org_id = p.org_id and b.code = 'MAIN'
left join public.departments d on d.org_id = p.org_id and d.name = p.department
left join public.positions pos on pos.org_id = p.org_id and pos.code = upper(e.data ->> 'positionId')
left join public.specialties sp on sp.org_id = p.org_id and sp.name = e.data ->> 'specialty'
where not exists (select 1 from public.employees x where x.profile_id = p.id)
on conflict do nothing;

-- O'tish davri: frontend hali docs.employees'ga yozadi → employees jadvali avtomatik yangilanadi.
-- Oddiy xodim o'z yozuvida faqat BO'SH maydonlarni to'ldira oladi (bo'lim/lavozimni qayta-qayta o'zgartira olmaydi).
create or replace function public.sync_employee_from_docs() returns trigger language plpgsql security definer set search_path = public as $$
declare p public.profiles; v_dept uuid; v_pos uuid; v_spec uuid; v_branch uuid; v_full boolean;
begin
  if new.collection <> 'employees' then return new; end if;
  begin
    select * into p from public.profiles where id::text = new.id;
    if not found then return new; end if;
    v_full := (not public.is_api_request()) or public.has_perm('employee.edit');
    select id into v_branch from public.branches where org_id = p.org_id and code = 'MAIN';
    select id into v_dept from public.departments where org_id = p.org_id and name = coalesce(nullif(new.data ->> 'department', ''), p.department);
    select id into v_pos from public.positions where org_id = p.org_id and code = upper(new.data ->> 'positionId');
    select id into v_spec from public.specialties where org_id = p.org_id and name = new.data ->> 'specialty';
    if exists (select 1 from public.employees where profile_id = p.id) then
      update public.employees set
        first_name    = case when v_full or first_name is null then coalesce(nullif(new.data ->> 'firstName', ''), first_name) else first_name end,
        last_name     = case when v_full or last_name is null then coalesce(nullif(new.data ->> 'lastName', ''), last_name) else last_name end,
        department_id = case when v_full or department_id is null then coalesce(v_dept, department_id) else department_id end,
        position_id   = case when v_full or position_id is null then coalesce(v_pos, position_id) else position_id end,
        specialty_id  = case when v_full or specialty_id is null then coalesce(v_spec, specialty_id) else specialty_id end,
        hire_date     = case when v_full or hire_date is null then coalesce(public._safe_date(new.data ->> 'hireDate'), hire_date) else hire_date end
      where profile_id = p.id and org_id = p.org_id;
    elsif p.status = 'active' then
      insert into public.employees (org_id, profile_id, employee_code, first_name, last_name, branch_id, department_id, position_id, specialty_id, hire_date)
      values (p.org_id, p.id, 'EMP-' || upper(substr(replace(p.id::text, '-', ''), 1, 8)), nullif(new.data ->> 'firstName', ''), nullif(new.data ->> 'lastName', ''),
              v_branch, v_dept, v_pos, v_spec, public._safe_date(new.data ->> 'hireDate'))
      on conflict do nothing;
    end if;
  exception when others then
    raise warning 'sync_employee_from_docs: %', sqlerrm;  -- docs yozuvini hech qachon bloklamaydi
  end;
  return new;
end $$;
drop trigger if exists docs_sync_employee_trg on public.docs;
create trigger docs_sync_employee_trg after insert or update on public.docs for each row execute function public.sync_employee_from_docs();

insert into public.schema_migrations (version, description) values ('004a', 'Org structure: branches, departments, positions, specialties, employees, permissions, audit_logs')
on conflict (version) do nothing;
