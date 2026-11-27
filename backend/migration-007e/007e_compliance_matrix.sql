-- MedAcademy · Migration 007e — Training Compliance + Competency Matrix (Phase 3 STEP 11)
-- 007d'dan keyin. FAQAT O'QISH / HISOBOT QATLAMI: yangi jadval, view, trigger, permission, rol YO'Q. 004…007d obyektlari o'zgarmaydi.
--
-- Haqiqiy sxema (lokal tekshiruv): compliance / matrix obyekti yo'q. Legacy docs JSON (progress / skills / notifications) import QILINMAYDI.
-- Manba (source of truth) — mavjud jadvallar:
--   trening:     course_assignments (status, due_date, started_at, completed_at) + lessons.is_required / status + course_modules.status
--                + lesson_progress (007a). Learning path orqali kelgan kurslar — 007b yaratgan course_assignments (qayta apply qilinmaydi).
--   kompetensiya: competency_requirements + skills + skill_assessments — 007c ichki funksiyasi _sk_emp_competency_007c ORQALI (aynan bir xil semantika).
--   xodim:       employees + profiles + departments / positions / specialties.
--
-- Semantika:
--   * Kurs holati — 007a _lp_status_007a bilan AYNAN bir xil (my_learning_progress / course_progress_summary bilan bir xil formulalar):
--       cancelled | completed (assignment completed YOKI barcha majburiy published darslar tugallangan) | overdue (due_date < bugun) |
--       in_progress (progress bor yoki started_at) | not_started. Optional darslar maxrajga kirmaydi; yakuniy imtihon kurs tugallanishiga kirmaydi.
--   * Compliance: total_required = bekor qilinmagan tayinlashlar; cancelled alohida sanaladi va maxrajga kirmaydi;
--       compliance_percent = round(100 * completed / total_required, 1); total_required = 0 → 0. 100% faqat hammasi completed bo'lsa.
--       Kurs tugallanishi ≠ sertifikatlash (sertifikat — alohida imtihon / sertifikat dvigateli).
--   * Kompetensiya matritsasi — 007c: har skill bo'yicha bitta qator (canonical identity = skill); mos keladigan barcha faol talablar
--       (department / position / specialty / role) ichidan eng yuqori required_level; joriy daraja = eng so'nggi baholash
--       (assessed_at desc, assessment_seq desc). Status: achieved | not_achieved (= gap) | not_assessed. Talab manbalari ro'yxat sifatida.
--       Umumiy "competency score" / og'irlikli KPI yo'q.
--   * O'qish operatsiyalari audit / bildirishnoma / tayinlash / baholash YARATMAYDI (faqat STABLE funksiyalar).
--
-- Ruxsat va qamrov (mavjud ruxsatlar; yangi permission yo'q):
--   trening:      o'zi — har doim; super_admin — tashkilot; education_manager / hr (progress.view) — tashkilot;
--                 department_head (progress.view) — faqat o'z bo'limi; instructor / medical_reviewer / employee — faqat o'zi.
--   kompetensiya: 007c _sk_can_view_employee_007c bilan bir xil (o'zi; SA / EM / HR skill.view; department_head — o'z bo'limi).
--   bo'lim / tashkilot matritsasi: SA / EM / HR (progress.view + skill.view) — tashkilot ichidagi istalgan bo'lim yoki butun tashkilot;
--                 department_head — faqat o'z bo'limi. Boshqa rollar — rad. Cross-org — topilmadi / rad. Anonim — EXECUTE yo'q.
-- Rollback: 007e_rollback.sql (faqat 007e funksiyalari; ma'lumotga tegilmaydi).

begin;

do $$ begin
  if not exists (select 1 from public.schema_migrations where version = '007d') then raise exception '007e: avval 007d qo''llanishi kerak'; end if;
end $$;

-- ---------- 1. Ichki: trening holati (set-based, ko'p xodim) — 007a formulasi ----------
create or replace function public._cmp_training_007e(p_org uuid, p_emp uuid[])
returns table (employee_id uuid, assignment_id uuid, course_id text, course_title text, assignment_status text, assigned_at timestamptz,
               due_date date, completed_at timestamptz, total_required_lessons int, completed_required_lessons int, progress_percent int, computed_status text)
language sql stable security definer set search_path = public as $$
  with a as (
    select ca.* from public.course_assignments ca where ca.org_id = p_org and ca.employee_id = any(p_emp)
  ), req as (
    select m.course_id, l.id lesson_id from public.lessons l join public.course_modules m on m.id = l.module_id
    where m.course_id in (select distinct a.course_id from a) and m.org_id = p_org and l.is_required and l.status = 'published' and m.status = 'published'
  ), tot as (select r.course_id, count(*)::int n from req r group by r.course_id),
  pr as (   -- bitta skan: har (xodim, kurs) uchun tugallangan majburiy darslar soni + istalgan faollik (007a: istalgan dars progressi = boshlangan)
    select lp.employee_id, m.course_id,
           count(*) filter (where lp.status = 'completed' and l.is_required and l.status = 'published' and m.status = 'published')::int n
    from public.lesson_progress lp join public.lessons l on l.id = lp.lesson_id join public.course_modules m on m.id = l.module_id
    where lp.employee_id = any(p_emp) and m.org_id = p_org and m.course_id in (select distinct a.course_id from a)
    group by 1, 2
  )
  select a.employee_id, a.id, a.course_id, c.title, a.status, a.assigned_at, a.due_date, a.completed_at,
         coalesce(tot.n, 0), coalesce(pr.n, 0),
         case when coalesce(tot.n, 0) = 0 then 0 else least(100, (100 * coalesce(pr.n, 0)) / tot.n) end,
         public._lp_status_007a(a.status, a.due_date, coalesce(tot.n, 0), coalesce(pr.n, 0), a.started_at is not null or pr.course_id is not null)
  from a join public.courses c on c.id = a.course_id
  left join tot on tot.course_id = a.course_id
  left join pr on pr.employee_id = a.employee_id and pr.course_id = a.course_id
$$;

-- ---------- 2. Ichki: qamrov tekshiruvlari ----------
create or replace function public._cmp_can_view_training_007e(p_employee uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.employees e
    where e.id = p_employee and e.org_id = public.my_org()
      and (e.id = public.my_employee_id()
        or public.my_role() = 'super_admin'
        or (public.my_role() in ('education_manager', 'hr') and public.has_perm('progress.view'))
        or (public.my_role() = 'department_head' and public.has_perm('progress.view') and public.my_department_id() is not null
            and e.department_id = public.my_department_id())))
$$;

create or replace function public._cmp_emp_json_007e(p_employee uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('employee_id', e.id, 'employee_code', e.employee_code,
           'employee_name', trim(coalesce(e.first_name, '') || ' ' || coalesce(e.last_name, '')),
           'employment_status', e.employment_status,
           'department_id', e.department_id, 'department', d.name, 'position_id', e.position_id, 'position', po.name,
           'specialty_id', e.specialty_id, 'specialty', sp.name, 'role', p.role)
  from public.employees e
  left join public.departments d on d.id = e.department_id left join public.positions po on po.id = e.position_id
  left join public.specialties sp on sp.id = e.specialty_id left join public.profiles p on p.id = e.profile_id
  where e.id = p_employee
$$;

-- ---------- 3. employee_training_compliance ----------
create or replace function public.employee_training_compliance(p_employee uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_emp uuid := coalesce(p_employee, public.my_employee_id()); v_org uuid := public.my_org(); r jsonb;
begin
  if auth.uid() is null or v_org is null then raise exception 'Ruxsat yo''q' using errcode = '42501'; end if;
  if v_emp is null then raise exception 'Xodim yozuvi topilmadi' using errcode = 'P0002'; end if;
  if not public._cmp_can_view_training_007e(v_emp) then raise exception 'Ruxsat yo''q: bu xodim trening holatini ko''rish' using errcode = '42501'; end if;
  with t as (select * from public._cmp_training_007e(v_org, array[v_emp]))
  select jsonb_build_object(
    'employee', public._cmp_emp_json_007e(v_emp),
    'summary', jsonb_build_object(
      'total_required', count(*) filter (where computed_status <> 'cancelled'),
      'completed', count(*) filter (where computed_status = 'completed'),
      'in_progress', count(*) filter (where computed_status = 'in_progress'),
      'not_started', count(*) filter (where computed_status = 'not_started'),
      'overdue', count(*) filter (where computed_status = 'overdue'),
      'cancelled', count(*) filter (where computed_status = 'cancelled'),
      'compliance_percent', case when count(*) filter (where computed_status <> 'cancelled') = 0 then 0.0
        else round(100.0 * count(*) filter (where computed_status = 'completed') / count(*) filter (where computed_status <> 'cancelled'), 1) end),
    'courses', coalesce(jsonb_agg(jsonb_build_object('assignment_id', assignment_id, 'course_id', course_id, 'course_title', course_title,
        'assignment_status', assignment_status, 'status', computed_status, 'assigned_at', assigned_at, 'due_date', due_date, 'completed_at', completed_at,
        'total_required_lessons', total_required_lessons, 'completed_required_lessons', completed_required_lessons, 'progress_percent', progress_percent)
      order by (computed_status = 'cancelled'), due_date nulls last, course_title) filter (where assignment_id is not null), '[]'::jsonb))
  into r from t;
  return r;
end $$;

-- ---------- 4. employee_competency_matrix ----------
create or replace function public.employee_competency_matrix(p_employee uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_emp uuid := coalesce(p_employee, public.my_employee_id()); v_org uuid := public.my_org(); r jsonb;
begin
  if auth.uid() is null or v_org is null then raise exception 'Ruxsat yo''q' using errcode = '42501'; end if;
  if v_emp is null then raise exception 'Xodim yozuvi topilmadi' using errcode = 'P0002'; end if;
  if not public._sk_can_view_employee_007c(v_emp) then raise exception 'Ruxsat yo''q: bu xodim kompetensiyasini ko''rish' using errcode = '42501'; end if;
  with c as (select * from public._sk_emp_competency_007c(v_org, array[v_emp]) where required_level is not null),
  e as (select e.id, e.department_id, e.position_id, e.specialty_id, p.role, p.status pstatus from public.employees e
        left join public.profiles p on p.id = e.profile_id where e.id = v_emp),
  src as (   -- talab manbalari (007c moslik qoidasi bilan bir xil)
    select cr.skill_id, jsonb_agg(jsonb_build_object('requirement_id', cr.id, 'target_type', cr.target_type,
             'target_id', coalesce(cr.department_id::text, cr.position_id::text, cr.specialty_id::text, cr.target_role), 'required_level', cr.required_level)
           order by cr.required_level desc, cr.target_type) reqs
    from e join public.competency_requirements cr on cr.org_id = v_org and cr.status = 'active'
      and ((cr.target_type = 'department' and cr.department_id = e.department_id)
        or (cr.target_type = 'position' and cr.position_id = e.position_id)
        or (cr.target_type = 'specialty' and cr.specialty_id = e.specialty_id)
        or (cr.target_type = 'role' and cr.target_role = e.role and e.pstatus = 'active'))
    join public.skills s on s.id = cr.skill_id and s.status = 'active'
    group by cr.skill_id
  )
  select jsonb_build_object(
    'employee', public._cmp_emp_json_007e(v_emp),
    'summary', jsonb_build_object('required', count(c.skill_id), 'achieved', count(*) filter (where c.status = 'achieved'),
       'not_achieved', count(*) filter (where c.status = 'not_achieved'), 'not_assessed', count(*) filter (where c.status = 'not_assessed')),
    'competencies', coalesce(jsonb_agg(jsonb_build_object('skill_id', c.skill_id, 'skill_code', s.code, 'skill_name', s.name, 'max_level', s.max_level,
        'required_level', c.required_level, 'current_level', c.achieved_level, 'latest_assessment_at', c.assessed_at, 'status', c.status,
        'requirements', coalesce(src.reqs, '[]'::jsonb))
      order by case c.status when 'not_assessed' then 1 when 'not_achieved' then 0 else 2 end, s.name) filter (where c.skill_id is not null), '[]'::jsonb))
  into r
  from c join public.skills s on s.id = c.skill_id left join src on src.skill_id = c.skill_id;
  if r is null then
    r := jsonb_build_object('employee', public._cmp_emp_json_007e(v_emp),
      'summary', jsonb_build_object('required', 0, 'achieved', 0, 'not_achieved', 0, 'not_assessed', 0), 'competencies', '[]'::jsonb);
  end if;
  return r;
end $$;

-- ---------- 5. department_compliance_matrix (bo'lim yoki butun tashkilot) ----------
create or replace function public.department_compliance_matrix(p_department uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_org uuid := public.my_org(); v_role text := public.my_role(); v_emps uuid[]; r jsonb; v_scope text;
begin
  if auth.uid() is null or v_org is null then raise exception 'Ruxsat yo''q' using errcode = '42501'; end if;
  if v_role = 'department_head' then
    if not (public.has_perm('progress.view') and public.has_perm('skill.view')) or p_department is null
       or public.my_department_id() is distinct from p_department then
      raise exception 'Department Head faqat o''z bo''limini ko''radi' using errcode = '42501';
    end if;
  elsif not (v_role = 'super_admin' or (v_role in ('education_manager', 'hr') and public.has_perm('progress.view') and public.has_perm('skill.view'))) then
    raise exception 'Ruxsat yo''q' using errcode = '42501';
  end if;
  if p_department is not null and not exists (select 1 from public.departments where id = p_department and org_id = v_org) then
    raise exception 'Bo''lim topilmadi yoki ruxsat yo''q' using errcode = '42501';
  end if;
  v_scope := case when p_department is null then 'organization' else 'department' end;
  select array_agg(id) into v_emps from public.employees
   where org_id = v_org and employment_status in ('active', 'on_leave') and (p_department is null or department_id = p_department);
  v_emps := coalesce(v_emps, '{}');
  with t as (select employee_id, computed_status from public._cmp_training_007e(v_org, v_emps)),
  ts as (
    select employee_id, count(*) filter (where computed_status <> 'cancelled') req, count(*) filter (where computed_status = 'completed') done,
           count(*) filter (where computed_status = 'in_progress') inprog, count(*) filter (where computed_status = 'not_started') notst,
           count(*) filter (where computed_status = 'overdue') ovd, count(*) filter (where computed_status = 'cancelled') canc
    from t group by employee_id
  ), cs as (
    select employee_id, count(*) req, count(*) filter (where status = 'achieved') ach, count(*) filter (where status = 'not_achieved') gap,
           count(*) filter (where status = 'not_assessed') nas
    from public._sk_emp_competency_007c(v_org, v_emps) where required_level is not null group by employee_id
  ), rows as (
    select e.id, e.employee_code, trim(coalesce(e.first_name, '') || ' ' || coalesce(e.last_name, '')) nm, e.department_id, d.name dname,
           coalesce(ts.req, 0) req, coalesce(ts.done, 0) done, coalesce(ts.inprog, 0) inprog, coalesce(ts.notst, 0) notst, coalesce(ts.ovd, 0) ovd,
           coalesce(ts.canc, 0) canc, coalesce(cs.req, 0) creq, coalesce(cs.ach, 0) ach, coalesce(cs.gap, 0) gap, coalesce(cs.nas, 0) nas
    from public.employees e left join public.departments d on d.id = e.department_id
    left join ts on ts.employee_id = e.id left join cs on cs.employee_id = e.id
    where e.id = any(v_emps)
  )
  select jsonb_build_object('scope', v_scope, 'department_id', p_department, 'employees', count(*),
    'training', jsonb_build_object('total_required', coalesce(sum(req), 0), 'completed', coalesce(sum(done), 0), 'in_progress', coalesce(sum(inprog), 0),
       'not_started', coalesce(sum(notst), 0), 'overdue', coalesce(sum(ovd), 0), 'cancelled', coalesce(sum(canc), 0),
       'compliance_percent', case when coalesce(sum(req), 0) = 0 then 0.0 else round(100.0 * sum(done) / sum(req), 1) end,
       'fully_compliant_employees', count(*) filter (where req > 0 and done = req)),
    'competency', jsonb_build_object('required', coalesce(sum(creq), 0), 'achieved', coalesce(sum(ach), 0), 'not_achieved', coalesce(sum(gap), 0),
       'not_assessed', coalesce(sum(nas), 0)),
    'departments', case when p_department is null then (
        select coalesce(jsonb_agg(x order by x ->> 'department'), '[]'::jsonb) from (
          select jsonb_build_object('department_id', department_id, 'department', max(dname), 'employees', count(*),
                   'total_required', sum(req), 'completed', sum(done), 'overdue', sum(ovd),
                   'compliance_percent', case when sum(req) = 0 then 0.0 else round(100.0 * sum(done) / sum(req), 1) end,
                   'competency_required', sum(creq), 'competency_achieved', sum(ach), 'competency_not_achieved', sum(gap), 'competency_not_assessed', sum(nas)) x
          from rows group by department_id) z) else null end,
    'rows', case when p_department is not null then coalesce(jsonb_agg(jsonb_build_object('employee_id', id, 'employee_code', employee_code, 'employee_name', nm,
        'training', jsonb_build_object('total_required', req, 'completed', done, 'in_progress', inprog, 'not_started', notst, 'overdue', ovd, 'cancelled', canc,
           'compliance_percent', case when req = 0 then 0.0 else round(100.0 * done / req, 1) end),
        'competency', jsonb_build_object('required', creq, 'achieved', ach, 'not_achieved', gap, 'not_assessed', nas)) order by nm), '[]'::jsonb) else null end)
  into r from rows;
  return r;
end $$;

-- ---------- 6. Grant'lar va funksiya kategoriyalari ----------
revoke execute on function public._cmp_training_007e(uuid, uuid[]) from public, anon, authenticated;
revoke execute on function public._cmp_can_view_training_007e(uuid) from public, anon, authenticated;
revoke execute on function public._cmp_emp_json_007e(uuid) from public, anon, authenticated;
revoke execute on function public.employee_training_compliance(uuid) from public, anon;
revoke execute on function public.employee_competency_matrix(uuid) from public, anon;
revoke execute on function public.department_compliance_matrix(uuid) from public, anon;
grant execute on function public.employee_training_compliance(uuid) to authenticated;
grant execute on function public.employee_competency_matrix(uuid) to authenticated;
grant execute on function public.department_compliance_matrix(uuid) to authenticated;
do $$ begin
  if to_regclass('backup.function_categories_005d') is not null then
    insert into backup.function_categories_005d (name, category) values
      ('_cmp_training_007e', 'internal'), ('_cmp_can_view_training_007e', 'internal'), ('_cmp_emp_json_007e', 'internal'),
      ('employee_training_compliance', 'role_rpc'), ('employee_competency_matrix', 'role_rpc'), ('department_compliance_matrix', 'role_rpc')
    on conflict (name) do update set category = excluded.category;
  end if;
end $$;

insert into public.schema_migrations (version, description) values
  ('007e', 'Training compliance + competency matrix: read-only computed RPCs over 007a/007b/007c sources (no tables, no triggers, no permissions)')
on conflict (version) do nothing;

commit;

select json_build_object(
  'migration', (select version from public.schema_migrations where version = '007e'),
  'functions', (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('_cmp_training_007e', '_cmp_can_view_training_007e',
     '_cmp_emp_json_007e', 'employee_training_compliance', 'employee_competency_matrix', 'department_compliance_matrix')),
  'anon_exec', (select string_agg(p.proname, ',') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')),
  'attempts', (select count(*) from public.exam_attempts), 'certificates', (select count(*) from public.certificates)
)::text as result_007e;
