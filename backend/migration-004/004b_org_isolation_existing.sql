-- MedAcademy · Migration 004b — Mavjud (Phase 1) jadvallar va RPC'larda tashkilot izolyatsiyasi
-- Ma'lumot o'zgarmaydi: faqat RLS policy'lar, trigger funksiyalari va RPC'lar org_id bo'yicha cheklanadi.
-- Bitta yangi ustun: attempt_resets.org_id (default bilan, NOT NULL).

-- ---------- Guard'lar: "SQL Editor bypass" endi session_user emas, JWT yo'qligiga qarab ----------
create or replace function public.guard_profile() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.is_api_request() then return new; end if;   -- migratsiya / SQL Editor
  if new.org_id is distinct from old.org_id then
    raise exception 'Tashkilotni API orqali o''zgartirib bo''lmaydi';
  end if;
  if coalesce(public.my_role(), '') not in ('super_admin','hr') then
    if new.role is distinct from old.role or new.status is distinct from old.status then
      raise exception 'Rol yoki holatni faqat HR / Super Admin o''zgartira oladi';
    end if;
    if old.department is not null and old.department <> '' and new.department is distinct from old.department then
      raise exception 'Bo''limni faqat HR / Super Admin o''zgartira oladi';
    end if;
  end if;
  if public.my_role() = 'hr' and new.role = 'super_admin' and old.role <> 'super_admin' then
    raise exception 'Super Admin rolini faqat Super Admin bera oladi';
  end if;
  if new.id <> auth.uid() and old.org_id is distinct from public.my_org() then
    raise exception 'Boshqa tashkilot foydalanuvchisi';
  end if;
  return new;
end $$;

create or replace function public.guard_question() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'approved' and (tg_op = 'INSERT' or old.status is distinct from 'approved') then
    if public.is_api_request() and coalesce(public.my_role(), '') not in ('super_admin','education_manager') then
      raise exception 'Savolni faqat Super Admin yoki Education Manager tasdiqlay oladi';
    end if;
    new.approved_by := coalesce(new.approved_by, auth.uid());
  end if;
  if tg_op = 'INSERT' then
    new.created_by := coalesce(new.created_by, auth.uid());
    if public.is_api_request() then new.org_id := public.my_org(); end if;
  elsif new.org_id is distinct from old.org_id then
    raise exception 'org_id o''zgartirilmaydi';
  end if;
  new.updated_at := now();
  return new;
end $$;

-- docs: department bilan birga org_id ham server tomonida egasidan olinadi
create or replace function public.docs_set_dept() returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.department := (select department from public.profiles where id = new.owner);
  new.org_id := coalesce((select org_id from public.profiles where id = new.owner), public.my_org(), new.org_id);
  new.updated_at := now();
  return new;
end $$;

-- attempt_resets: org_id
alter table public.attempt_resets add column if not exists org_id uuid not null default '00000000-0000-0000-0000-000000000001' references public.organizations(id);

-- ---------- RLS: org_id bo'yicha cheklash ----------
drop policy if exists org_select on public.organizations;
create policy org_select on public.organizations for select to authenticated using (id = public.my_org());

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated using (
  id = auth.uid()
  or (org_id = public.my_org() and (
        public.my_role() in ('super_admin','hr','education_manager','instructor')
        or (public.my_role() = 'department_head' and department = public.my_dept())))
);
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid() or (org_id = public.my_org() and public.my_role() in ('super_admin','hr')))
  with check (id = auth.uid() or (org_id = public.my_org() and public.my_role() in ('super_admin','hr')));

drop policy if exists docs_select on public.docs;
create policy docs_select on public.docs for select to authenticated using (
  owner = auth.uid()
  or (org_id = public.my_org() and (
        (collection in ('settings','questions_custom','exam_overrides') and public.my_role() is not null)
        or public.my_role() in ('super_admin','hr','education_manager','instructor')
        or (public.my_role() = 'department_head' and department = public.my_dept())))
);
drop policy if exists docs_insert on public.docs;
create policy docs_insert on public.docs for insert to authenticated with check (
  (owner = auth.uid() and collection in ('employees','plans','progress','initial','notifications','audit'))
  or (org_id = public.my_org() and (
        public.my_role() in ('super_admin','education_manager','hr')
        or (public.my_role() = 'instructor' and collection in ('skill_assess','notifications','audit','questions_custom'))
        or (public.my_role() = 'department_head' and department = public.my_dept() and collection in ('skill_assess','notifications','audit','plans'))))
);
drop policy if exists docs_update on public.docs;
create policy docs_update on public.docs for update to authenticated
  using (
    (owner = auth.uid() and collection in ('employees','plans','progress','initial','notifications'))
    or (org_id = public.my_org() and (
          public.my_role() in ('super_admin','education_manager','hr')
          or (public.my_role() = 'instructor' and collection in ('skill_assess','questions_custom'))
          or (public.my_role() = 'department_head' and department = public.my_dept() and collection in ('skill_assess','plans')))))
  with check (
    (owner = auth.uid() and collection in ('employees','plans','progress','initial','notifications'))
    or (org_id = public.my_org() and (
          public.my_role() in ('super_admin','education_manager','hr')
          or (public.my_role() = 'instructor' and collection in ('skill_assess','questions_custom'))
          or (public.my_role() = 'department_head' and department = public.my_dept() and collection in ('skill_assess','plans')))));
drop policy if exists docs_delete on public.docs;
create policy docs_delete on public.docs for delete to authenticated using (org_id = public.my_org() and public.my_role() in ('super_admin','education_manager'));

drop policy if exists courses_select on public.courses;
create policy courses_select on public.courses for select to authenticated using (org_id = public.my_org() and public.my_role() is not null);
drop policy if exists courses_write on public.courses;
create policy courses_write on public.courses for all to authenticated
  using (org_id = public.my_org() and public.my_role() in ('super_admin','education_manager'))
  with check (org_id = public.my_org() and public.my_role() in ('super_admin','education_manager'));

drop policy if exists exam_configs_select on public.exam_configs;
create policy exam_configs_select on public.exam_configs for select to authenticated using (org_id = public.my_org() and public.my_role() is not null);
drop policy if exists exam_configs_write on public.exam_configs;
create policy exam_configs_write on public.exam_configs for all to authenticated
  using (org_id = public.my_org() and public.my_role() in ('super_admin','education_manager'))
  with check (org_id = public.my_org() and public.my_role() in ('super_admin','education_manager'));

drop policy if exists questions_select on public.questions;
create policy questions_select on public.questions for select to authenticated
  using (org_id = public.my_org() and public.my_role() in ('super_admin','education_manager','instructor'));
drop policy if exists questions_insert on public.questions;
create policy questions_insert on public.questions for insert to authenticated
  with check (org_id = public.my_org() and public.my_role() in ('super_admin','education_manager','instructor'));
drop policy if exists questions_update on public.questions;
create policy questions_update on public.questions for update to authenticated
  using (org_id = public.my_org() and public.my_role() in ('super_admin','education_manager','instructor'))
  with check (org_id = public.my_org() and public.my_role() in ('super_admin','education_manager','instructor'));
drop policy if exists questions_delete on public.questions;
create policy questions_delete on public.questions for delete to authenticated
  using (org_id = public.my_org() and public.my_role() in ('super_admin','education_manager'));

drop policy if exists attempts_select on public.exam_attempts;
create policy attempts_select on public.exam_attempts for select to authenticated using (
  user_id = auth.uid()
  or (org_id = public.my_org() and (
        public.my_role() in ('super_admin','hr','education_manager','instructor')
        or (public.my_role() = 'department_head' and exists (select 1 from public.profiles p where p.id = exam_attempts.user_id and p.department = public.my_dept()))))
);
drop policy if exists certificates_select on public.certificates;
create policy certificates_select on public.certificates for select to authenticated using (
  user_id = auth.uid()
  or (org_id = public.my_org() and (
        public.my_role() in ('super_admin','hr','education_manager','instructor')
        or (public.my_role() = 'department_head' and exists (select 1 from public.profiles p where p.id = certificates.user_id and p.department = public.my_dept()))))
);
drop policy if exists resets_select on public.attempt_resets;
create policy resets_select on public.attempt_resets for select to authenticated using (
  user_id = auth.uid() or (org_id = public.my_org() and public.my_role() in ('super_admin','hr','education_manager','instructor','department_head'))
);

-- ---------- RPC'lar: o'z tashkiloti kontenti va foydalanuvchilari bilan cheklash ----------
create or replace function public.start_exam(p_course text, p_kind text, p_module text default null, p_domains jsonb default null, p_preview boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); r text := public.my_role(); v_org uuid := public.my_org();
  cfg public.exam_configs; att public.exam_attempts; v_last public.exam_attempts;
  n int; used int; v_reset timestamptz; ids text[]; ord jsonb; dmap jsonb;
begin
  if uid is null or r is null or v_org is null then raise exception 'Faol akkaunt talab qilinadi'; end if;
  if p_kind not in ('module','final','initial') then raise exception 'Noto''g''ri imtihon turi'; end if;
  if p_preview and r not in ('super_admin','education_manager','instructor') then p_preview := false; end if;

  if p_kind = 'initial' then
    if p_domains is null then raise exception 'Initial assessment uchun sohalar ro''yxati kerak'; end if;
    select array_agg(s.id), jsonb_object_agg(s.id, s.d) into ids, dmap from (
      select qq.id, dd.key as d from jsonb_each_text(p_domains) dd
      cross join lateral (select id from public.questions where course_id = dd.value and org_id = v_org and status = 'approved'
                          and type in ('single','tf','case') order by random() limit 2) qq) s;
    if ids is null then raise exception 'Savollar bankida savol yo''q'; end if;
    insert into public.exam_attempts (org_id, user_id, course_id, kind, qids, domain_map, config, is_preview)
      values (v_org, uid, 'INITIAL', 'initial', ids, dmap, jsonb_build_object('pass', 0, 'neg', 0), p_preview) returning * into att;
  else
    select * into cfg from public.exam_configs where course_id = p_course and org_id = v_org;
    if not found then raise exception 'Kurs topilmadi'; end if;
    if p_kind = 'final' and not p_preview then
      select * into att from public.exam_attempts where user_id = uid and course_id = p_course and kind = 'final'
        and finished_at is null and not is_preview and deadline > now() order by started_at desc limit 1;
      if found then return public._attempt_payload(att); end if;
      select ar.reset_at into v_reset from public.attempt_resets ar where ar.user_id = uid and ar.course_id = p_course;
      select count(*) into used from public.exam_attempts where user_id = uid and course_id = p_course and kind = 'final'
        and finished_at is not null and not is_preview and (v_reset is null or finished_at > v_reset);
      if used >= cfg.max_attempts then
        raise exception 'Urinishlar tugadi. Instructor yoki Education Manager urinishlarni tiklashi kerak.';
      end if;
      select * into v_last from public.exam_attempts where user_id = uid and course_id = p_course and kind = 'final'
        and finished_at is not null and not is_preview order by finished_at desc limit 1;
      if found and not v_last.passed and v_last.retake_after > now() and (v_reset is null or v_reset < v_last.finished_at) then
        raise exception 'Qayta topshirish sanasi: %', to_char(v_last.retake_after, 'YYYY-MM-DD');
      end if;
    end if;
    n := case when p_kind = 'module' then 4 else cfg.question_count end;
    select array_agg(t.id) into ids from (
      select s.id from (
        select id, row_number() over (partition by module_id order by random()) rn, random() rnd from public.questions
        where course_id = p_course and org_id = v_org and status = 'approved' and (p_kind <> 'module' or module_id = p_module)) s
      order by s.rn, s.rnd limit n) t;
    if ids is null then raise exception 'Savollar bankida savol yo''q'; end if;
    insert into public.exam_attempts (org_id, user_id, course_id, module_id, kind, qids, is_preview, deadline, config)
      values (v_org, uid, p_course, case when p_kind = 'module' then p_module end, p_kind, ids, p_preview,
              case when p_kind = 'final' then now() + make_interval(mins => cfg.time_min) end,
              jsonb_build_object('count', cfg.question_count, 'time', cfg.time_min, 'pass', cfg.pass_score, 'attempts', cfg.max_attempts,
                                 'neg', cfg.negative_mark, 'retakeDays', cfg.retake_days))
      returning * into att;
  end if;

  select jsonb_object_agg(q.id, (select jsonb_agg(i order by random()) from generate_series(0, jsonb_array_length(q.options) - 1) i))
    into ord from public.questions q
    where q.id = any (ids) and q.type in ('single','multiple','case','match','image','ecg','lab') and jsonb_typeof(q.options) = 'array';
  update public.exam_attempts set option_order = coalesce(ord, '{}') where id = att.id returning * into att;
  return public._attempt_payload(att);
end $$;

create or replace function public.get_attempt_review(p_attempt text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare att public.exam_attempts; r text := public.my_role();
begin
  select * into att from public.exam_attempts where id = p_attempt;
  if not found or att.finished_at is null then raise exception 'Urinish topilmadi yoki yakunlanmagan'; end if;
  if att.user_id <> auth.uid() and (coalesce(r, '') not in ('super_admin','education_manager','instructor') or att.org_id is distinct from public.my_org()) then
    raise exception 'Ruxsat yo''q';
  end if;
  return jsonb_build_object('attempt', public._attempt_out(att),
    'questions', (select jsonb_agg(public._q_full(x)) from public.questions x where x.id = any (att.qids)));
end $$;

create or replace function public.question_meta() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'course', course_id, 'module', module_id, 'topic', topic,
    'type', type, 'difficulty', difficulty, 'status', status)), '[]'::jsonb)
  from public.questions where status = 'approved' and org_id = public.my_org() and public.my_role() is not null
$$;

create or replace function public.admin_reset_attempts(p_user uuid, p_course text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(public.my_role(), '') not in ('super_admin','education_manager','instructor') then raise exception 'Ruxsat yo''q'; end if;
  if not exists (select 1 from public.profiles where id = p_user and org_id = public.my_org()) then raise exception 'Ruxsat yo''q'; end if;
  insert into public.attempt_resets (org_id, user_id, course_id, reset_at, reset_by) values (public.my_org(), p_user, p_course, now(), auth.uid())
    on conflict (user_id, course_id) do update set reset_at = now(), reset_by = auth.uid();
  return true;
end $$;

create or replace function public.revoke_certificate(p_code text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(public.my_role(), '') not in ('super_admin','education_manager') then raise exception 'Ruxsat yo''q'; end if;
  update public.certificates set revoked = true, revoked_by = auth.uid(), revoked_at = now() where id = upper(trim(p_code)) and org_id = public.my_org();
  return found;
end $$;

insert into public.schema_migrations (version, description) values ('004b', 'Org isolation for Phase 1 tables, policies and RPCs')
on conflict (version) do nothing;
