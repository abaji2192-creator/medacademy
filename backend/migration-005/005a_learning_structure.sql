-- MedAcademy · Migration 005a — Organization → Course → Module → Lesson; tayinlash, progress, learning path, instruktorlar,
-- yangi rollar (medical_reviewer, content_author), taklifnoma asosidagi ro'yxatdan o'tish.
-- Faqat qo'shadi. DROP TABLE / TRUNCATE / ma'lumot o'chirish yo'q. Idempotent.

-- ---------- 1. Yangi rollar ----------
do $$ declare c record; begin
  for c in select conname from pg_constraint where conrelid = 'public.profiles'::regclass and contype = 'c'
            and pg_get_constraintdef(oid) like '%role%' and pg_get_constraintdef(oid) like '%employee%' and conname <> 'profiles_role_chk' loop
    execute format('alter table public.profiles drop constraint %I', c.conname);
  end loop;
  for c in select conname from pg_constraint where conrelid = 'public.role_permissions'::regclass and contype = 'c'
            and pg_get_constraintdef(oid) like '%role%' and conname <> 'role_permissions_role_chk' loop
    execute format('alter table public.role_permissions drop constraint %I', c.conname);
  end loop;
end $$;
do $$ begin
  alter table public.profiles add constraint profiles_role_chk check (role in
    ('super_admin','hr','education_manager','department_head','instructor','employee','medical_reviewer','content_author'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.role_permissions add constraint role_permissions_role_chk check (role in
    ('super_admin','hr','education_manager','department_head','instructor','employee','medical_reviewer','content_author'));
exception when duplicate_object then null; end $$;

-- ---------- 2. Yangi ruxsatlar ----------
insert into public.permissions (key, category, description) values
  ('assignment.view','education','Kurs tayinlashlarini ko''rish'),
  ('assignment.manage','education','Kurs tayinlash / bekor qilish'),
  ('progress.view','education','O''qish progressini ko''rish'),
  ('learning_path.manage','education','Learning path''larni boshqarish'),
  ('instructor.assign','education','Kursga instruktor biriktirish'),
  ('question.review','assessment','Savolni tibbiy/instruktor review qilish'),
  ('question.publish','assessment','Savolni nashr qilish (imtihonga chiqarish)'),
  ('question.deprecate','assessment','Savolni eskirgan deb belgilash'),
  ('evidence.view','evidence','Dalil manbalarini ko''rish'),
  ('evidence.manage','evidence','Dalil manbalarini qo''shish/tahrirlash'),
  ('evidence.review','evidence','Dalil review (savol dalilini tasdiqlash)'),
  ('evidence.verify','evidence','DOI/PMID/manba tekshiruvini tasdiqlash'),
  ('research.run','evidence','Research qidiruv so''rovlarini yaratish'),
  ('ai.use','evidence','AI yordamchi vazifalarini ishga tushirish'),
  ('quality.score','assessment','Savol sifatini baholash'),
  ('invitation.manage','employee','Tashkilotga taklifnoma yuborish')
on conflict (key) do nothing;

-- Standart matritsa (004 dagi + 005 qo'shimchalari). Mavjud qatorlar saqlanadi.
create or replace function public.seed_org_defaults_005(p_org uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.role_permissions (org_id, role, permission_key)
  select p_org, m.role, m.perm from (values
    ('hr','assignment.view'),('hr','progress.view'),('hr','invitation.manage'),
    ('education_manager','assignment.view'),('education_manager','assignment.manage'),('education_manager','progress.view'),
    ('education_manager','learning_path.manage'),('education_manager','instructor.assign'),
    ('education_manager','question.review'),('education_manager','question.publish'),('education_manager','question.deprecate'),
    ('education_manager','evidence.view'),('education_manager','evidence.manage'),('education_manager','evidence.review'),('education_manager','evidence.verify'),
    ('education_manager','research.run'),('education_manager','ai.use'),('education_manager','quality.score'),
    ('instructor','assignment.view'),('instructor','assignment.manage'),('instructor','progress.view'),
    ('instructor','question.review'),('instructor','evidence.view'),('instructor','evidence.manage'),('instructor','research.run'),('instructor','ai.use'),('instructor','quality.score'),
    ('department_head','assignment.view'),('department_head','progress.view'),
    ('medical_reviewer','course.view'),('medical_reviewer','question.view'),('medical_reviewer','question.review'),('medical_reviewer','question.publish'),
    ('medical_reviewer','question.deprecate'),('medical_reviewer','evidence.view'),('medical_reviewer','evidence.manage'),('medical_reviewer','evidence.review'),
    ('medical_reviewer','evidence.verify'),('medical_reviewer','research.run'),('medical_reviewer','ai.use'),('medical_reviewer','quality.score'),
    ('medical_reviewer','branch.view'),('medical_reviewer','position.view'),('medical_reviewer','specialty.view'),
    ('content_author','course.view'),('content_author','question.view'),('content_author','question.create'),('content_author','question.edit'),
    ('content_author','evidence.view'),('content_author','evidence.manage'),('content_author','research.run'),('content_author','ai.use'),
    ('content_author','branch.view'),('content_author','position.view'),('content_author','specialty.view')
  ) as m(role, perm)
  on conflict do nothing;
end $$;
revoke execute on function public.seed_org_defaults_005(uuid) from public, anon, authenticated;
create or replace function public.on_org_created() returns trigger language plpgsql security definer set search_path = public as $$
begin perform public.seed_org_defaults(new.id); perform public.seed_org_defaults_005(new.id); return new; end $$;
do $$ declare o record; begin for o in select id from public.organizations loop perform public.seed_org_defaults_005(o.id); end loop; end $$;

-- ---------- 4. Courses: kengaytirish (almashtirilmaydi) ----------
alter table public.courses add column if not exists code text;
alter table public.courses add column if not exists description text;
alter table public.courses add column if not exists scope_type text not null default 'organization';
alter table public.courses add column if not exists created_at timestamptz not null default now();
do $$ begin
  alter table public.courses add constraint courses_scope_chk check (scope_type in ('organization','global'));
exception when duplicate_object then null; end $$;
update public.courses set code = id where code is null;
create unique index if not exists courses_org_code_uq on public.courses (org_id, code) where code is not null;

-- ---------- 5. Course modules ----------
create table if not exists public.course_modules (
  id text primary key default ('M' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 12)),
  org_id uuid not null references public.organizations(id) on delete restrict,
  course_id text not null references public.courses(id) on delete restrict,
  title text not null check (length(trim(title)) > 0),
  description text,
  order_index int not null default 1 check (order_index >= 0),
  status text not null default 'draft' check (status in ('draft','published','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists course_modules_course_idx on public.course_modules (course_id, order_index);

-- ---------- 6. Lessons ----------
create table if not exists public.lessons (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete restrict,
  module_id text not null references public.course_modules(id) on delete restrict,
  title text not null check (length(trim(title)) > 0),
  description text,
  content_type text not null default 'text' check (content_type in ('text','video','document','presentation','clinical_case','quiz')),
  content text,
  content_meta jsonb not null default '{}',
  order_index int not null default 1 check (order_index >= 0),
  estimated_minutes int not null default 0 check (estimated_minutes between 0 and 1440),
  status text not null default 'draft' check (status in ('draft','published','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists lessons_module_idx on public.lessons (module_id, order_index);

-- ---------- 7. Course assignments ----------
create table if not exists public.course_assignments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete restrict,
  course_id text not null references public.courses(id) on delete restrict,
  employee_id uuid not null references public.employees(id) on delete restrict,
  assigned_by uuid references public.profiles(id) on delete set null,
  assigned_at timestamptz not null default now(),
  due_date date,
  status text not null default 'assigned' check (status in ('assigned','in_progress','completed','overdue','cancelled')),
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint course_assignments_dates_chk check (completed_at is null or started_at is null or completed_at >= started_at)
);
create unique index if not exists course_assignments_active_uq on public.course_assignments (course_id, employee_id) where status <> 'cancelled';
create index if not exists course_assignments_employee_idx on public.course_assignments (employee_id, status);
create index if not exists course_assignments_org_status_idx on public.course_assignments (org_id, status);

-- ---------- 8. Lesson progress ----------
create table if not exists public.lesson_progress (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete restrict,
  lesson_id uuid not null references public.lessons(id) on delete restrict,
  employee_id uuid not null references public.employees(id) on delete restrict,
  status text not null default 'in_progress' check (status in ('not_started','in_progress','completed')),
  progress_percent int not null default 0 check (progress_percent between 0 and 100),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  last_accessed_at timestamptz not null default now(),
  constraint lesson_progress_uq unique (lesson_id, employee_id)
);
create index if not exists lesson_progress_employee_idx on public.lesson_progress (employee_id);

-- ---------- 9. Learning paths ----------
create table if not exists public.learning_paths (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete restrict,
  code text not null check (code ~ '^[A-Z0-9_-]{2,32}$'),
  title text not null,
  description text,
  target_position_family text,
  status text not null default 'draft' check (status in ('draft','published','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint learning_paths_org_code_uq unique (org_id, code)
);
create table if not exists public.learning_path_courses (
  org_id uuid not null references public.organizations(id) on delete restrict,
  path_id uuid not null references public.learning_paths(id) on delete restrict,
  course_id text not null references public.courses(id) on delete restrict,
  order_index int not null default 1,
  is_required boolean not null default true,
  primary key (path_id, course_id)
);
create index if not exists learning_path_courses_course_idx on public.learning_path_courses (course_id);

-- ---------- 10. Course instructors ----------
create table if not exists public.course_instructors (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete restrict,
  course_id text not null references public.courses(id) on delete restrict,
  employee_id uuid not null references public.employees(id) on delete restrict,
  assigned_by uuid references public.profiles(id) on delete set null,
  assigned_at timestamptz not null default now(),
  status text not null default 'active' check (status in ('active','inactive')),
  constraint course_instructors_uq unique (course_id, employee_id)
);
create index if not exists course_instructors_employee_idx on public.course_instructors (employee_id, status);

-- ---------- 10b. Yordamchi funksiya (jadvaldan keyin) ----------
create or replace function public.is_course_instructor(p_course text) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.course_instructors ci
                 where ci.course_id = p_course and ci.employee_id = public.my_employee_id() and ci.status = 'active' and ci.org_id = public.my_org())
$$;

-- ---------- 11. Taklifnomalar (yangi foydalanuvchi qaysi tashkilotga tushishi) ----------
create table if not exists public.org_invitations (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete restrict,
  email text not null check (email = lower(trim(email)) and email like '%@%'),
  role text not null default 'employee' check (role in ('hr','education_manager','department_head','instructor','employee','medical_reviewer','content_author')),
  department_id uuid references public.departments(id) on delete set null,
  position_id uuid references public.positions(id) on delete set null,
  invited_by uuid references public.profiles(id) on delete set null,
  status text not null default 'pending' check (status in ('pending','accepted','revoked','expired')),
  expires_at timestamptz not null default (now() + interval '14 days'),
  accepted_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index if not exists org_invitations_pending_uq on public.org_invitations (email) where status = 'pending';

-- Ro'yxatdan o'tish: amaldagi taklifnoma bo'lsa — o'sha tashkilot/rol/bo'lim; bo'lmasa — avvalgi xatti-harakat (Impuls, pending).
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
declare first_user boolean; inv public.org_invitations; v_dept text;
begin
  select not exists (select 1 from public.profiles) into first_user;
  select * into inv from public.org_invitations where email = lower(trim(new.email)) and status = 'pending' and expires_at > now() limit 1;
  if found then
    select name into v_dept from public.departments where id = inv.department_id;
    insert into public.profiles (id, org_id, email, full_name, role, status, department)
    values (new.id, inv.org_id, new.email, coalesce(new.raw_user_meta_data->>'full_name', ''), inv.role, 'active', v_dept);
    insert into public.employees (org_id, profile_id, employee_code, first_name, department_id, position_id)
    values (inv.org_id, new.id, 'EMP-' || upper(substr(replace(new.id::text, '-', ''), 1, 8)),
            nullif(split_part(coalesce(new.raw_user_meta_data->>'full_name', ''), ' ', 1), ''), inv.department_id, inv.position_id)
    on conflict do nothing;
    update public.org_invitations set status = 'accepted', accepted_at = now() where id = inv.id;
  else
    insert into public.profiles (id, email, full_name, role, status)
    values (new.id, new.email, coalesce(new.raw_user_meta_data->>'full_name', ''),
            case when first_user then 'super_admin' else 'employee' end,
            case when first_user then 'active' else 'pending' end);
  end if;
  return new;
end $$;

-- ---------- 12. Bir tashkilot qoidasi va himoya trigger'lari ----------
create or replace function public.enforce_same_org_005() returns trigger language plpgsql security definer set search_path = public as $$
declare bad text; j jsonb := to_jsonb(new);
begin
  if tg_op = 'UPDATE' and new.org_id is distinct from old.org_id then raise exception 'org_id o''zgartirilmaydi'; end if;
  if j ? 'course_id' and j ->> 'course_id' is not null and (select org_id from public.courses where id = j ->> 'course_id') is distinct from new.org_id then bad := 'course'; end if;
  if j ? 'module_id' and j ->> 'module_id' is not null and (select org_id from public.course_modules where id = j ->> 'module_id') is distinct from new.org_id then bad := 'module'; end if;
  if j ? 'lesson_id' and j ->> 'lesson_id' is not null and (select org_id from public.lessons where id = (j ->> 'lesson_id')::uuid) is distinct from new.org_id then bad := 'lesson'; end if;
  if j ? 'employee_id' and j ->> 'employee_id' is not null and (select org_id from public.employees where id = (j ->> 'employee_id')::uuid) is distinct from new.org_id then bad := 'employee'; end if;
  if j ? 'path_id' and j ->> 'path_id' is not null and (select org_id from public.learning_paths where id = (j ->> 'path_id')::uuid) is distinct from new.org_id then bad := 'learning_path'; end if;
  if j ? 'department_id' and j ->> 'department_id' is not null and (select org_id from public.departments where id = (j ->> 'department_id')::uuid) is distinct from new.org_id then bad := 'department'; end if;
  if j ? 'position_id' and j ->> 'position_id' is not null and (select org_id from public.positions where id = (j ->> 'position_id')::uuid) is distinct from new.org_id then bad := 'position'; end if;
  if bad is not null then raise exception 'Boshqa tashkilotga tegishli % bog''lanmaydi', bad; end if;
  return new;
end $$;

-- Xodim progressi: egalik maydonlari o'zgarmaydi; org_id server tomonidan qo'yiladi; tayinlash avtomatik "in_progress".
create or replace function public.guard_lesson_progress() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.org_id := coalesce((select org_id from public.lessons where id = new.lesson_id), new.org_id);
  else
    if new.lesson_id is distinct from old.lesson_id or new.employee_id is distinct from old.employee_id or new.org_id is distinct from old.org_id
       or new.started_at is distinct from old.started_at then
      raise exception 'Progress egalik maydonlarini o''zgartirib bo''lmaydi';
    end if;
  end if;
  new.last_accessed_at := now();
  if new.status = 'completed' then new.progress_percent := 100; new.completed_at := coalesce(new.completed_at, now()); end if;
  return new;
end $$;
create or replace function public.progress_marks_assignment() returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.course_assignments a set status = 'in_progress', started_at = coalesce(a.started_at, now())
   where a.employee_id = new.employee_id and a.status in ('assigned','overdue')
     and a.course_id = (select m.course_id from public.lessons l join public.course_modules m on m.id = l.module_id where l.id = new.lesson_id);
  return new;
end $$;
-- Sertifikat berilganda (server imtihoni) tayinlash avtomatik "completed"
create or replace function public.certificate_completes_assignment() returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.course_assignments a set status = 'completed', completed_at = now(), started_at = coalesce(a.started_at, now())
   where a.course_id = new.course_id and a.status in ('assigned','in_progress','overdue')
     and a.employee_id = (select e.id from public.employees e where e.profile_id = new.user_id);
  return new;
end $$;
-- Tayinlashda: xodim o'ziga tayinlay olmaydi; assigned_by server tomonidan
create or replace function public.guard_course_assignment() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_api_request() then
    if tg_op = 'INSERT' then
      new.assigned_by := auth.uid(); new.assigned_at := now();
      if new.employee_id = public.my_employee_id() and not public.has_perm('assignment.manage') then
        raise exception 'Xodim o''ziga kurs tayinlay olmaydi';
      end if;
    elsif new.employee_id is distinct from old.employee_id or new.course_id is distinct from old.course_id or new.assigned_by is distinct from old.assigned_by then
      raise exception 'Tayinlash egalik maydonlarini o''zgartirib bo''lmaydi';
    end if;
  end if;
  return new;
end $$;
-- Taklifnoma: Super Admin rolini taklif qilib bo'lmaydi (rol ro'yxatida yo'q); invited_by server tomonidan
create or replace function public.guard_invitation() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_api_request() and tg_op = 'INSERT' then new.invited_by := auth.uid(); new.status := 'pending'; new.accepted_at := null; end if;
  return new;
end $$;
-- Muddati o'tgan tayinlashlar (kelajakdagi scheduled job uchun; API'dan chaqirilmaydi)
create or replace function public.mark_overdue_assignments() returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.course_assignments set status = 'overdue' where status in ('assigned','in_progress') and due_date < current_date;
  get diagnostics n = row_count; return n;
end $$;
revoke execute on function public.mark_overdue_assignments() from public, anon, authenticated;

do $$ declare t text; begin
  foreach t in array array['course_modules','lessons','course_assignments','lesson_progress','learning_paths','learning_path_courses','course_instructors','org_invitations'] loop
    execute format('drop trigger if exists %1$s_same_org_trg on public.%1$s', t);
    execute format('create trigger %1$s_same_org_trg before insert or update on public.%1$s for each row execute function public.enforce_same_org_005()', t);
    execute format('drop trigger if exists %1$s_audit_trg on public.%1$s', t);
    execute format('create trigger %1$s_audit_trg after insert or update or delete on public.%1$s for each row execute function public.audit_row()', t);
  end loop;
  foreach t in array array['course_modules','lessons','course_assignments','learning_paths'] loop
    execute format('drop trigger if exists %1$s_touch_trg on public.%1$s', t);
    execute format('create trigger %1$s_touch_trg before update on public.%1$s for each row execute function public.touch_updated_at()', t);
  end loop;
end $$;
drop trigger if exists lesson_progress_guard_trg on public.lesson_progress;
create trigger lesson_progress_guard_trg before insert or update on public.lesson_progress for each row execute function public.guard_lesson_progress();
drop trigger if exists lesson_progress_assignment_trg on public.lesson_progress;
create trigger lesson_progress_assignment_trg after insert or update on public.lesson_progress for each row execute function public.progress_marks_assignment();
drop trigger if exists certificates_assignment_trg on public.certificates;
create trigger certificates_assignment_trg after insert on public.certificates for each row execute function public.certificate_completes_assignment();
drop trigger if exists course_assignments_guard_trg on public.course_assignments;
create trigger course_assignments_guard_trg before insert or update on public.course_assignments for each row execute function public.guard_course_assignment();
drop trigger if exists org_invitations_guard_trg on public.org_invitations;
create trigger org_invitations_guard_trg before insert on public.org_invitations for each row execute function public.guard_invitation();

-- ---------- 13. RLS ----------
alter table public.course_modules enable row level security;
alter table public.lessons enable row level security;
alter table public.course_assignments enable row level security;
alter table public.lesson_progress enable row level security;
alter table public.learning_paths enable row level security;
alter table public.learning_path_courses enable row level security;
alter table public.course_instructors enable row level security;
alter table public.org_invitations enable row level security;

drop policy if exists course_modules_select on public.course_modules;
create policy course_modules_select on public.course_modules for select to authenticated using (
  org_id = public.my_org() and (status = 'published' or public.has_perm('course.edit') or public.is_course_instructor(course_id)));
drop policy if exists course_modules_write on public.course_modules;
create policy course_modules_write on public.course_modules for insert to authenticated
  with check (org_id = public.my_org() and (public.has_perm('course.edit') or public.is_course_instructor(course_id)));
drop policy if exists course_modules_update on public.course_modules;
create policy course_modules_update on public.course_modules for update to authenticated
  using (org_id = public.my_org() and (public.has_perm('course.edit') or public.is_course_instructor(course_id)))
  with check (org_id = public.my_org() and (public.has_perm('course.edit') or public.is_course_instructor(course_id)));

drop policy if exists lessons_select on public.lessons;
create policy lessons_select on public.lessons for select to authenticated using (
  org_id = public.my_org() and exists (select 1 from public.course_modules m where m.id = lessons.module_id
    and ((lessons.status = 'published' and m.status = 'published') or public.has_perm('course.edit') or public.is_course_instructor(m.course_id))));
drop policy if exists lessons_insert on public.lessons;
create policy lessons_insert on public.lessons for insert to authenticated with check (
  org_id = public.my_org() and exists (select 1 from public.course_modules m where m.id = lessons.module_id
    and (public.has_perm('course.edit') or public.is_course_instructor(m.course_id))));
drop policy if exists lessons_update on public.lessons;
create policy lessons_update on public.lessons for update to authenticated
  using (org_id = public.my_org() and exists (select 1 from public.course_modules m where m.id = lessons.module_id
    and (public.has_perm('course.edit') or public.is_course_instructor(m.course_id))))
  with check (org_id = public.my_org());

drop policy if exists course_assignments_select on public.course_assignments;
create policy course_assignments_select on public.course_assignments for select to authenticated using (
  org_id = public.my_org() and (
    employee_id = public.my_employee_id()
    or (public.has_perm('assignment.view') and public.my_role() in ('super_admin','hr','education_manager'))
    or (public.my_role() = 'department_head' and exists (select 1 from public.employees e where e.id = course_assignments.employee_id and e.department_id = public.my_department_id()))
    or (public.my_role() = 'instructor' and public.is_course_instructor(course_id))));
drop policy if exists course_assignments_insert on public.course_assignments;
create policy course_assignments_insert on public.course_assignments for insert to authenticated with check (
  org_id = public.my_org() and public.has_perm('assignment.manage')
  and (public.my_role() <> 'instructor' or public.is_course_instructor(course_id)));
drop policy if exists course_assignments_update on public.course_assignments;
create policy course_assignments_update on public.course_assignments for update to authenticated
  using (org_id = public.my_org() and public.has_perm('assignment.manage') and (public.my_role() <> 'instructor' or public.is_course_instructor(course_id)))
  with check (org_id = public.my_org());

drop policy if exists lesson_progress_select on public.lesson_progress;
create policy lesson_progress_select on public.lesson_progress for select to authenticated using (
  org_id = public.my_org() and (
    employee_id = public.my_employee_id()
    or (public.has_perm('progress.view') and public.my_role() in ('super_admin','hr','education_manager'))
    or (public.my_role() = 'department_head' and exists (select 1 from public.employees e where e.id = lesson_progress.employee_id and e.department_id = public.my_department_id()))
    or (public.my_role() = 'instructor' and exists (select 1 from public.lessons l join public.course_modules m on m.id = l.module_id
                                                    where l.id = lesson_progress.lesson_id and public.is_course_instructor(m.course_id)))));
drop policy if exists lesson_progress_insert on public.lesson_progress;
create policy lesson_progress_insert on public.lesson_progress for insert to authenticated
  with check (employee_id = public.my_employee_id() and org_id = public.my_org());
drop policy if exists lesson_progress_update on public.lesson_progress;
create policy lesson_progress_update on public.lesson_progress for update to authenticated
  using (employee_id = public.my_employee_id()) with check (employee_id = public.my_employee_id());

drop policy if exists learning_paths_select on public.learning_paths;
create policy learning_paths_select on public.learning_paths for select to authenticated using (
  org_id = public.my_org() and (status = 'published' or public.has_perm('learning_path.manage')));
drop policy if exists learning_paths_write on public.learning_paths;
create policy learning_paths_write on public.learning_paths for insert to authenticated with check (org_id = public.my_org() and public.has_perm('learning_path.manage'));
drop policy if exists learning_paths_update on public.learning_paths;
create policy learning_paths_update on public.learning_paths for update to authenticated
  using (org_id = public.my_org() and public.has_perm('learning_path.manage')) with check (org_id = public.my_org());
drop policy if exists learning_path_courses_select on public.learning_path_courses;
create policy learning_path_courses_select on public.learning_path_courses for select to authenticated using (org_id = public.my_org() and public.my_role() is not null);
drop policy if exists learning_path_courses_write on public.learning_path_courses;
create policy learning_path_courses_write on public.learning_path_courses for all to authenticated
  using (org_id = public.my_org() and public.has_perm('learning_path.manage')) with check (org_id = public.my_org() and public.has_perm('learning_path.manage'));

drop policy if exists course_instructors_select on public.course_instructors;
create policy course_instructors_select on public.course_instructors for select to authenticated using (org_id = public.my_org() and public.my_role() is not null);
drop policy if exists course_instructors_insert on public.course_instructors;
create policy course_instructors_insert on public.course_instructors for insert to authenticated with check (org_id = public.my_org() and public.has_perm('instructor.assign'));
drop policy if exists course_instructors_update on public.course_instructors;
create policy course_instructors_update on public.course_instructors for update to authenticated
  using (org_id = public.my_org() and public.has_perm('instructor.assign')) with check (org_id = public.my_org());

drop policy if exists org_invitations_select on public.org_invitations;
create policy org_invitations_select on public.org_invitations for select to authenticated using (org_id = public.my_org() and public.has_perm('invitation.manage'));
drop policy if exists org_invitations_insert on public.org_invitations;
create policy org_invitations_insert on public.org_invitations for insert to authenticated with check (org_id = public.my_org() and public.has_perm('invitation.manage'));
drop policy if exists org_invitations_update on public.org_invitations;
create policy org_invitations_update on public.org_invitations for update to authenticated
  using (org_id = public.my_org() and public.has_perm('invitation.manage')) with check (org_id = public.my_org() and status in ('pending','revoked'));

-- Phase 1 siyosatlari: instruktor faqat o'ziga biriktirilgan kurslar bo'yicha urinishlarni ko'radi
drop policy if exists attempts_select on public.exam_attempts;
create policy attempts_select on public.exam_attempts for select to authenticated using (
  user_id = auth.uid()
  or (org_id = public.my_org() and (
        public.my_role() in ('super_admin','hr','education_manager')
        or (public.my_role() = 'instructor' and public.is_course_instructor(course_id))
        or (public.my_role() = 'department_head' and exists (select 1 from public.profiles p where p.id = exam_attempts.user_id and p.department = public.my_dept()))))
);

grant select, insert, update on public.course_modules, public.lessons, public.course_assignments, public.lesson_progress,
  public.learning_paths, public.learning_path_courses, public.course_instructors, public.org_invitations to authenticated;
grant delete on public.learning_path_courses to authenticated;
revoke all on public.course_modules, public.lessons, public.course_assignments, public.lesson_progress,
  public.learning_paths, public.learning_path_courses, public.course_instructors, public.org_invitations from anon;
