-- MedAcademy · Migration 007b — Learning Path Assignments (Phase 3 STEP 6)
-- 007a'dan keyin. 004…007a fayllari va obyektlari o'zgartirilmaydi. Additive: 1 yangi jadval, RLS, 4 RPC, 1 guard trigger, indekslar.
--
-- Haqiqiy sxema (lokal tekshiruv):
--   learning_paths(id uuid, org_id, code, title, status draft|published|archived), learning_path_courses(path_id, course_id, order_index, is_required),
--   course_assignments(course_id text, employee_id uuid, due_date date, status assigned|in_progress|completed|overdue|cancelled,
--                      UNIQUE (course_id, employee_id) WHERE status <> 'cancelled'),
--   employees(department_id, position_id, specialty_id, profile_id, employment_status active|on_leave|inactive|terminated),
--   profiles.role (8 ta rol), ruxsat 'learning_path.manage' (role_permissions: education_manager; super_admin — has_perm orqali hammasi).
--
-- Qarorlar (semantika):
--   * Qoida = learning_path_assignments qatori: aniq BITTA nishon (employee | department | position | specialty | role). CHECK bilan majburlanadi.
--   * Faqat status='published' yo'nalish tayinlanadi (draft / archived — rad). Arxivlangan yo'nalish yangi kurs tayinlashi yaratmaydi;
--     avval yaratilgan kurs tayinlashlari saqlanadi.
--   * Kurslar: faqat learning_path_courses.is_required = true va courses.status = 'published' kurslar avtomatik tayinlanadi
--     (ixtiyoriy kurslar xodim tanloviga qoladi).
--   * Mos xodimlar: qoida tashkilotidagi employment_status IN ('active','on_leave') xodimlar; 'role' nishoni uchun profiles.role = rol va
--     profiles.status = 'active'. Nofaol/ishdan ketgan xodimga to'g'ridan-to'g'ri (employee) tayinlash — rad.
--   * Takror yo'q: xodim × kurs uchun HAR QANDAY mavjud course_assignments qatori bo'lsa (assigned / in_progress / overdue / completed /
--     cancelled) — yangisi yaratilmaydi: tugallangan qayta ochilmaydi, jarayondagi progress tiklanmaydi, bekor qilingan jim
--     qayta faollashtirilmaydi (admin qo'lda qayta tayinlashi mumkin). DB himoyasi: course_assignments_active_uq + ON CONFLICT DO NOTHING.
--   * Muddat: qoidaning due_date (ixtiyoriy, mutlaq sana) — faqat SHU qoida yangi yaratgan kurs tayinlashlariga qo'yiladi;
--     mavjud tayinlashlarning muddati o'zgartirilmaydi.
--   * Qoida holati: active | cancelled. Bekor qilish yaratilgan kurs tayinlashlarini bekor qilmaydi (tarix saqlanadi). DELETE yo'q.
--   * Idempotentlik: bir xil (path, nishon) uchun faqat bitta active qoida (unique partial index); qayta chaqiruv yangi qator / audit
--     yaratmaydi (faqat holat haqiqatan o'zgarsa audit). reapply_* — yangi kelgan xodimlarni ham qamrash uchun qayta sinxronlash.
--   * Ruxsat: SA va learning_path.manage egalari (EM) — butun tashkilot. HR / Department Head / Instructor / MR / Employee / anon — rad
--     (mavjud ruxsat modelida ularda learning_path.manage yo'q; yangi ruxsat qo'shilmadi).
--   * 007a semantikasi o'zgarmaydi (progress / tugallash / overdue).
-- Rollback: 007b_rollback.sql.

begin;

do $$ begin
  if not exists (select 1 from public.schema_migrations where version = '007a') then raise exception '007b: avval 007a qo''llanishi kerak'; end if;
end $$;

-- ---------- 1. Jadval ----------
create table if not exists public.learning_path_assignments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete restrict,
  path_id uuid not null references public.learning_paths(id) on delete restrict,
  target_type text not null check (target_type in ('employee', 'department', 'position', 'specialty', 'role')),
  employee_id uuid references public.employees(id) on delete restrict,
  department_id uuid references public.departments(id) on delete restrict,
  position_id uuid references public.positions(id) on delete restrict,
  specialty_id uuid references public.specialties(id) on delete restrict,
  target_role text check (target_role is null or target_role in ('super_admin','hr','education_manager','department_head','instructor','employee','medical_reviewer','content_author')),
  due_date date,
  status text not null default 'active' check (status in ('active', 'cancelled')),
  created_by uuid references public.profiles(id) on delete restrict,
  cancelled_by uuid references public.profiles(id) on delete restrict,
  cancelled_at timestamptz,
  cancel_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  target_key text generated always as (coalesce(employee_id::text, department_id::text, position_id::text, specialty_id::text, target_role)) stored,
  constraint lpa_exactly_one_target check (
    num_nonnulls(employee_id, department_id, position_id, specialty_id, target_role) = 1
    and (target_type <> 'employee' or employee_id is not null)
    and (target_type <> 'department' or department_id is not null)
    and (target_type <> 'position' or position_id is not null)
    and (target_type <> 'specialty' or specialty_id is not null)
    and (target_type <> 'role' or target_role is not null)),
  constraint lpa_cancel_consistent check ((status = 'cancelled') = (cancelled_at is not null))
);
comment on table public.learning_path_assignments is '007b: o''quv yo''nalishini xodim / bo''lim / lavozim / mutaxassislik / rolga tayinlash qoidalari (DELETE yo''q; bekor qilish = status cancelled)';

create unique index if not exists lpa_active_target_uq on public.learning_path_assignments (path_id, target_type, target_key) where status = 'active';
create index if not exists lpa_org_status_idx on public.learning_path_assignments (org_id, status);
create index if not exists employees_org_dept_007b_idx on public.employees (org_id, department_id);

-- ---------- 2. Guard trigger (SQL darajasida ham tashkilot izolyatsiyasi va o'zgarmas maydonlar) ----------
create or replace function public.guard_lpa_007b() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_org uuid;
begin
  if tg_op = 'DELETE' then raise exception 'O''quv yo''nalishi tayinlashini o''chirib bo''lmaydi (bekor qilish: status cancelled)'; end if;
  if tg_op = 'UPDATE' then
    if new.org_id is distinct from old.org_id or new.path_id is distinct from old.path_id or new.target_type is distinct from old.target_type
       or new.employee_id is distinct from old.employee_id or new.department_id is distinct from old.department_id or new.position_id is distinct from old.position_id
       or new.specialty_id is distinct from old.specialty_id or new.target_role is distinct from old.target_role or new.created_by is distinct from old.created_by or new.created_at is distinct from old.created_at then
      raise exception 'Tayinlash qoidasining nishon / egalik maydonlarini o''zgartirib bo''lmaydi';
    end if;
    if old.status = 'cancelled' and new.status <> 'cancelled' then raise exception 'Bekor qilingan qoidani qayta faollashtirib bo''lmaydi (yangisini yarating)'; end if;
    new.updated_at := now();
  end if;
  select org_id into v_org from public.learning_paths where id = new.path_id;
  if v_org is distinct from new.org_id then raise exception 'Yo''nalish boshqa tashkilotga tegishli'; end if;
  if new.employee_id is not null and not exists (select 1 from public.employees where id = new.employee_id and org_id = new.org_id) then raise exception 'Xodim boshqa tashkilotga tegishli'; end if;
  if new.department_id is not null and not exists (select 1 from public.departments where id = new.department_id and org_id = new.org_id) then raise exception 'Bo''lim boshqa tashkilotga tegishli'; end if;
  if new.position_id is not null and not exists (select 1 from public.positions where id = new.position_id and org_id = new.org_id) then raise exception 'Lavozim boshqa tashkilotga tegishli'; end if;
  if new.specialty_id is not null and not exists (select 1 from public.specialties where id = new.specialty_id and org_id = new.org_id) then raise exception 'Mutaxassislik boshqa tashkilotga tegishli'; end if;
  return new;
end $$;
drop trigger if exists lpa_guard_007b_trg on public.learning_path_assignments;
create trigger lpa_guard_007b_trg before insert or update or delete on public.learning_path_assignments for each row execute function public.guard_lpa_007b();

-- ---------- 3. RLS (faqat o'qish; yozuv faqat RPC orqali) ----------
alter table public.learning_path_assignments enable row level security;
drop policy if exists lpa_select_007b on public.learning_path_assignments;
create policy lpa_select_007b on public.learning_path_assignments for select to authenticated
  using (org_id = public.my_org() and (public.has_perm('learning_path.manage') or public.has_perm('assignment.view')));
revoke all on public.learning_path_assignments from anon, authenticated;
grant select on public.learning_path_assignments to authenticated;

-- ---------- 4. Ichki yordamchi: qoidani qo'llash (xodimlar × majburiy kurslar), set-based ----------
create or replace function public._lpa_apply_rule_007b(p_rule uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.learning_path_assignments; v_emps int; v_created int;
begin
  select * into r from public.learning_path_assignments where id = p_rule;
  if r.id is null or r.status <> 'active' then return jsonb_build_object('employees_matched', 0, 'course_assignments_created', 0); end if;
  if not exists (select 1 from public.learning_paths where id = r.path_id and status = 'published') then
    return jsonb_build_object('employees_matched', 0, 'course_assignments_created', 0, 'skipped', 'path_not_published');
  end if;
  with emps as (
    select e.id from public.employees e
    where e.org_id = r.org_id and e.employment_status in ('active', 'on_leave')
      and case r.target_type
            when 'employee' then e.id = r.employee_id
            when 'department' then e.department_id = r.department_id
            when 'position' then e.position_id = r.position_id
            when 'specialty' then e.specialty_id = r.specialty_id
            when 'role' then exists (select 1 from public.profiles p where p.id = e.profile_id and p.org_id = r.org_id and p.role = r.target_role and p.status = 'active')
          end
  ), ins as (
    insert into public.course_assignments (org_id, course_id, employee_id, due_date, status)
      select r.org_id, lpc.course_id, x.id, r.due_date, 'assigned'
      from emps x
      cross join public.learning_path_courses lpc
      join public.courses c on c.id = lpc.course_id and c.org_id = r.org_id and c.status = 'published'
      where lpc.path_id = r.path_id and lpc.is_required
        and not exists (select 1 from public.course_assignments ca where ca.employee_id = x.id and ca.course_id = lpc.course_id)
    on conflict (course_id, employee_id) where (status <> 'cancelled') do nothing
    returning 1
  )
  select (select count(*) from emps), (select count(*) from ins) into v_emps, v_created;
  return jsonb_build_object('employees_matched', v_emps, 'course_assignments_created', v_created);
end $$;

create or replace function public._lpa_can_manage_007b() returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and public.my_role() is not null and public.my_org() is not null and public.has_perm('learning_path.manage')
$$;

-- ---------- 5. RPC: apply_learning_path ----------
create or replace function public.apply_learning_path(p_path uuid, p_target_type text, p_target_id text, p_due_date date default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_org uuid := public.my_org(); v_rule public.learning_path_assignments; v_state text := 'existing'; v_res jsonb;
        v_emp uuid; v_dept uuid; v_pos uuid; v_spec uuid; v_role text; v_old_due date;
begin
  if not public._lpa_can_manage_007b() then raise exception 'Ruxsat yo''q: o''quv yo''nalishini tayinlash (learning_path.manage)'; end if;
  if p_path is null or p_target_type is null or nullif(trim(p_target_id), '') is null then raise exception 'Yo''nalish, nishon turi va nishon majburiy'; end if;
  if not exists (select 1 from public.learning_paths where id = p_path and org_id = v_org) then raise exception 'O''quv yo''nalishi topilmadi yoki ruxsat yo''q'; end if;
  if not exists (select 1 from public.learning_paths where id = p_path and org_id = v_org and status = 'published') then raise exception 'Faqat nashr qilingan (published) yo''nalish tayinlanadi'; end if;
  if p_due_date is not null and p_due_date < current_date then raise exception 'Muddat o''tgan sana bo''lishi mumkin emas'; end if;
  begin
    case p_target_type
      when 'employee' then v_emp := p_target_id::uuid;
        if not exists (select 1 from public.employees where id = v_emp and org_id = v_org) then raise exception 'Xodim topilmadi yoki ruxsat yo''q'; end if;
        if not exists (select 1 from public.employees where id = v_emp and org_id = v_org and employment_status in ('active', 'on_leave')) then raise exception 'Nofaol xodimga tayinlab bo''lmaydi'; end if;
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

  select * into v_rule from public.learning_path_assignments
   where path_id = p_path and target_type = p_target_type and status = 'active'
     and target_key = coalesce(v_emp::text, v_dept::text, v_pos::text, v_spec::text, v_role)
   for update;
  if v_rule.id is null then
    insert into public.learning_path_assignments (org_id, path_id, target_type, employee_id, department_id, position_id, specialty_id, target_role, due_date, created_by)
      values (v_org, p_path, p_target_type, v_emp, v_dept, v_pos, v_spec, v_role, p_due_date, auth.uid())
      returning * into v_rule;
    v_state := 'created';
    perform public._audit006(v_org, 'learning_path_assignment', 'learning_path.assignment_created', v_rule.id::text, null,
      jsonb_build_object('path_id', p_path, 'target_type', p_target_type, 'target', v_rule.target_key, 'due_date', p_due_date));
  elsif p_due_date is not null and p_due_date is distinct from v_rule.due_date then
    v_old_due := v_rule.due_date;
    update public.learning_path_assignments set due_date = p_due_date where id = v_rule.id returning * into v_rule;
    v_state := 'updated';
    perform public._audit006(v_org, 'learning_path_assignment', 'learning_path.assignment_updated', v_rule.id::text,
      jsonb_build_object('due_date', v_old_due), jsonb_build_object('due_date', p_due_date));
  end if;

  v_res := public._lpa_apply_rule_007b(v_rule.id);
  if (v_res ->> 'course_assignments_created')::int > 0 then
    perform public._audit006(v_org, 'learning_path_assignment', 'learning_path.courses_applied', v_rule.id::text, null,
      jsonb_build_object('path_id', p_path) || v_res);
  end if;
  return jsonb_build_object('assignment_id', v_rule.id, 'rule', v_state) || v_res;
end $$;

-- ---------- 6. RPC: reapply (yangi kelgan xodimlarni qamrash; idempotent) ----------
create or replace function public.reapply_learning_path_assignment(p_assignment uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.learning_path_assignments; v_res jsonb;
begin
  if not public._lpa_can_manage_007b() then raise exception 'Ruxsat yo''q: o''quv yo''nalishini tayinlash (learning_path.manage)'; end if;
  select * into r from public.learning_path_assignments where id = p_assignment and org_id = public.my_org();
  if r.id is null then raise exception 'Tayinlash qoidasi topilmadi yoki ruxsat yo''q'; end if;
  if r.status <> 'active' then raise exception 'Bekor qilingan qoida qo''llanmaydi'; end if;
  if not exists (select 1 from public.learning_paths where id = r.path_id and status = 'published') then raise exception 'Yo''nalish nashr qilinmagan yoki arxivlangan — yangi tayinlash yaratilmaydi'; end if;
  v_res := public._lpa_apply_rule_007b(r.id);
  if (v_res ->> 'course_assignments_created')::int > 0 then
    perform public._audit006(r.org_id, 'learning_path_assignment', 'learning_path.courses_applied', r.id::text, null, jsonb_build_object('path_id', r.path_id) || v_res);
  end if;
  return jsonb_build_object('assignment_id', r.id, 'rule', 'existing') || v_res;
end $$;

-- ---------- 7. RPC: cancel (tarix saqlanadi; yaratilgan kurs tayinlashlari o'zgarmaydi) ----------
create or replace function public.cancel_learning_path_assignment(p_assignment uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.learning_path_assignments;
begin
  if not public._lpa_can_manage_007b() then raise exception 'Ruxsat yo''q: o''quv yo''nalishini tayinlash (learning_path.manage)'; end if;
  if length(coalesce(trim(p_reason), '')) < 3 then raise exception 'Bekor qilish sababi majburiy'; end if;
  select * into r from public.learning_path_assignments where id = p_assignment and org_id = public.my_org() for update;
  if r.id is null then raise exception 'Tayinlash qoidasi topilmadi yoki ruxsat yo''q'; end if;
  if r.status = 'cancelled' then return jsonb_build_object('assignment_id', r.id, 'status', 'cancelled', 'changed', false); end if;
  update public.learning_path_assignments set status = 'cancelled', cancelled_at = now(), cancelled_by = auth.uid(), cancel_reason = trim(p_reason) where id = r.id;
  perform public._audit006(r.org_id, 'learning_path_assignment', 'learning_path.assignment_cancelled', r.id::text,
    jsonb_build_object('status', 'active'), jsonb_build_object('status', 'cancelled', 'reason', trim(p_reason)));
  return jsonb_build_object('assignment_id', r.id, 'status', 'cancelled', 'changed', true);
end $$;

-- ---------- 8. Huquqlar va ro'yxatga olish ----------
revoke execute on function public.guard_lpa_007b() from public, anon, authenticated;
revoke execute on function public._lpa_apply_rule_007b(uuid) from public, anon, authenticated;
revoke execute on function public._lpa_can_manage_007b() from public, anon, authenticated;
revoke execute on function public.apply_learning_path(uuid, text, text, date) from public, anon;
revoke execute on function public.reapply_learning_path_assignment(uuid) from public, anon;
revoke execute on function public.cancel_learning_path_assignment(uuid, text) from public, anon;
grant execute on function public.apply_learning_path(uuid, text, text, date) to authenticated;
grant execute on function public.reapply_learning_path_assignment(uuid) to authenticated;
grant execute on function public.cancel_learning_path_assignment(uuid, text) to authenticated;
do $$ begin
  if to_regclass('backup.function_categories_005d') is not null then
    insert into backup.function_categories_005d (name, category) values
      ('guard_lpa_007b', 'internal'), ('_lpa_apply_rule_007b', 'internal'), ('_lpa_can_manage_007b', 'internal'),
      ('apply_learning_path', 'role_rpc'), ('reapply_learning_path_assignment', 'role_rpc'), ('cancel_learning_path_assignment', 'role_rpc')
    on conflict (name) do update set category = excluded.category;
  end if;
end $$;

insert into public.schema_migrations (version, description) values
  ('007b', 'Learning path assignments: learning_path_assignments (one target per rule, active|cancelled, no DELETE), apply / reapply / cancel RPC, required published courses only, no duplicate course assignments')
on conflict (version) do nothing;

commit;

select json_build_object(
  'migration', (select version from public.schema_migrations where version = '007b'),
  'table', to_regclass('public.learning_path_assignments') is not null,
  'rls', (select relrowsecurity from pg_class where oid = 'public.learning_path_assignments'::regclass),
  'rules', (select count(*) from public.learning_path_assignments),
  'anon_exec', (select string_agg(p.proname, ',') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')),
  'course_assignments', (select count(*) from public.course_assignments), 'attempts', (select count(*) from public.exam_attempts), 'certificates', (select count(*) from public.certificates)
)::text as result_007b;
