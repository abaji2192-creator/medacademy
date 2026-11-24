-- MedAcademy · Migration 006a — Audit hardening, DELETE hardening, question_eligibility RPC
-- 005e'dan keyin. 004 / 005 / 005d / 005e fayllari o'zgartirilmaydi.
--
--   1. audit_logs — o'zgarmas: UPDATE / DELETE / TRUNCATE trigger bilan har doim rad etiladi (hatto SECURITY DEFINER
--      funksiyalardan ham); anon / authenticated'dan INSERT / UPDATE / DELETE / TRUNCATE huquqi olinadi (faqat SELECT, RLS bilan).
--      Yozuvlar faqat server trigger'lari / RPC'lar orqali; actor = auth.uid(), rol = my_role(), vaqt = now() (frontend'ga ishonilmaydi).
--   2. Yangi server audit hodisalari (minimal metadata — javob kaliti, savol matni, parol, token YOZILMAYDI):
--      questions (created, edited, published, unpublished, status_changed, eligibility_changed), courses (created, updated,
--      status_changed, deleted), profiles (role_changed, status_changed, department_changed), exam_configs (created, updated),
--      certificates (issued, revoked), attempt reset (attempt.reset).
--   3. O'z rolini / holatini o'zgartirish API orqali taqiqlanadi (alohida trigger; guard_profile o'zgarmaydi).
--   4. Attempt reset tarixi: attempt_reset_events — o'zgarmas, har bir reset alohida qator (attempt_resets jadvali va exam engine
--      semantikasi o'zgarmaydi). admin_reset_attempts(p_user, p_course, p_reason) — yangi overload; eski 2-argumentli chaqiruv ishlaydi.
--   5. Sertifikat revoke: revoke_certificate(p_code, p_reason) — sabab audit'ga yoziladi; revoke qaytarilmas (005d guard saqlanadi).
--   6. Rol o'zgartirish sababi: admin_set_profile_role(p_profile, p_role, p_reason) — sabab majburiy; ruxsat guard_profile orqali.
--   7. docs: tarixiy kolleksiyalar (attempts, certificates, audit, progress, initial, employees) API orqali o'chirilmaydi.
--   8. exam_configs: API orqali DELETE taqiqlanadi (konfiguratsiya tarixiy urinishlar bilan bog'liq; o'chirish o'rniga o'zgartirish).
--   9. question_eligibility(p_question) — bitta savol uchun yaroqlilik holati (savol matni / javob / izoh / ichki izohlarsiz),
--      faqat question.view ruxsati va savolni ko'rish huquqi bilan; anon — yo'q.
--
-- Qoidalar: DROP TABLE / TRUNCATE / biznes ma'lumotini DELETE YO'Q. RLS policy'lari o'zgarmaydi (yangi jadval uchun yangi policy'dan
-- tashqari). Urinishlar, sertifikatlar, review / evidence yozuvlari, savol versiyalari o'zgarmaydi. Idempotent. Bitta tranzaksiya.
-- Rollback: 006a_rollback.sql.

begin;

do $$ begin
  if not exists (select 1 from public.schema_migrations where version = '005e') then raise exception '006a: avval 005e qo''llanishi kerak'; end if;
end $$;

-- ---------- 0. Rollback uchun snapshot (faqat birinchi marta yoziladi) ----------
create schema if not exists backup;
revoke all on schema backup from public;
do $$ begin
  if to_regclass('backup.security_pre006a') is null then
    create table backup.security_pre006a (kind text not null, name text not null, detail text, extra text, created_at timestamptz not null default now());
    alter table backup.security_pre006a enable row level security;
    insert into backup.security_pre006a (kind, name, detail)
      select 'fn_def', p.oid::regprocedure::text, pg_get_functiondef(p.oid)
      from pg_proc p where p.pronamespace = 'public'::regnamespace
        and p.oid::regprocedure::text in ('admin_reset_attempts(uuid,text)');
    insert into backup.security_pre006a (kind, name, detail)
      select 'grant', t.table_name, string_agg(t.grantee || ':' || t.privilege_type, ',' order by t.grantee, t.privilege_type)
      from information_schema.role_table_grants t
      where t.table_schema = 'public' and t.table_name = 'audit_logs' and t.grantee in ('anon','authenticated') group by t.table_name;
    insert into backup.security_pre006a (kind, name, detail)
      select 'seqgrant', 'audit_logs_id_seq', string_agg(r || ':' || pr, ',')
      from unnest(array['anon','authenticated']) r, unnest(array['USAGE','SELECT','UPDATE']) pr
      where exists (select 1 from pg_roles where rolname = r) and has_sequence_privilege(r, 'public.audit_logs_id_seq', pr);
    insert into backup.security_pre006a (kind, name, detail)
      select 'counts', 'baseline', json_build_object(
        'audit_logs', (select count(*) from public.audit_logs),
        'attempt_resets', (select count(*) from public.attempt_resets),
        'exam_attempts', (select count(*) from public.exam_attempts),
        'certificates', (select count(*) from public.certificates),
        'docs', (select count(*) from public.docs),
        'exam_configs', (select count(*) from public.exam_configs),
        'policies', (select count(*) from pg_policies where schemaname = 'public'))::text;
  end if;
end $$;

-- ---------- 1. Umumiy audit yordamchisi ----------
create or replace function public._audit006(p_org uuid, p_entity text, p_action text, p_id text, p_old jsonb, p_new jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_ip text; v_reason text;
begin
  if p_org is null then return; end if;
  begin v_ip := nullif(split_part(coalesce(current_setting('request.headers', true)::json ->> 'x-forwarded-for', ''), ',', 1), '');
  exception when others then v_ip := null; end;
  v_reason := nullif(left(coalesce(current_setting('medacademy.audit_reason', true), ''), 500), '');
  insert into public.audit_logs (org_id, actor_id, actor_role, action, entity, entity_id, old_value, new_value, ip)
  values (p_org, auth.uid(), public.my_role(), p_action, p_entity, p_id, p_old,
          case when v_reason is null then p_new else coalesce(p_new, '{}'::jsonb) || jsonb_build_object('reason', v_reason) end, v_ip);
end $$;

-- ---------- 2. audit_logs — o'zgarmas ----------
create or replace function public.audit_logs_immutable() returns trigger language plpgsql as $$
begin
  raise exception 'Audit yozuvlari o''zgarmas (UPDATE / DELETE / TRUNCATE taqiqlangan). Tuzatish uchun yangi audit hodisasi yoziladi.';
end $$;
drop trigger if exists audit_logs_immutable_trg on public.audit_logs;
create trigger audit_logs_immutable_trg before update or delete on public.audit_logs for each row execute function public.audit_logs_immutable();
drop trigger if exists audit_logs_no_truncate_trg on public.audit_logs;
create trigger audit_logs_no_truncate_trg before truncate on public.audit_logs for each statement execute function public.audit_logs_immutable();
revoke insert, update, delete, truncate on public.audit_logs from anon, authenticated;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'anon') then execute 'revoke all on public.audit_logs from anon'; end if;
end $$;
grant select on public.audit_logs to authenticated;
revoke usage, select, update on sequence public.audit_logs_id_seq from anon, authenticated;

-- ---------- 3. Savol audit'i (minimal: matn / javob / izoh yo'q) ----------
create or replace function public.audit_question_006a() returns trigger language plpgsql security definer set search_path = public as $$
declare
  k text[] := array['workflow_status','status','evidence_status','current_version','published_version','draft_status','review_reason','evidence_exempt','course_id'];
  v_old jsonb; v_new jsonb; v_action text;
begin
  v_new := (select jsonb_object_agg(x, to_jsonb(new) -> x) from unnest(k) x);
  if tg_op = 'INSERT' then
    perform public._audit006(new.org_id, 'question', 'question.created', new.id, null, v_new);
    return new;
  end if;
  v_old := (select jsonb_object_agg(x, to_jsonb(old) -> x) from unnest(k) x);
  if v_old = v_new then return new; end if;
  v_action := case
    when new.workflow_status = 'published' and (old.workflow_status is distinct from 'published' or new.published_version is distinct from old.published_version) then 'question.published'
    when old.workflow_status = 'published' and new.workflow_status is distinct from 'published' then 'question.unpublished'
    when new.workflow_status is distinct from old.workflow_status or new.status is distinct from old.status then 'question.status_changed'
    when new.evidence_status is distinct from old.evidence_status or new.review_reason is distinct from old.review_reason
         or new.evidence_exempt is distinct from old.evidence_exempt then 'question.eligibility_changed'
    when new.current_version is distinct from old.current_version or new.draft_status is distinct from old.draft_status then 'question.edited'
    else 'question.updated' end;
  perform public._audit006(new.org_id, 'question', v_action, new.id, v_old, v_new);
  return new;
end $$;
drop trigger if exists questions_audit_006a_trg on public.questions;
create trigger questions_audit_006a_trg after insert or update on public.questions for each row when (new.org_id is not null)
  execute function public.audit_question_006a();

-- ---------- 4. Kurs audit'i ----------
create or replace function public.audit_course_006a() returns trigger language plpgsql security definer set search_path = public as $$
declare v_old jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) - 'updated_at' - 'description' end;
        v_new jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) - 'updated_at' - 'description' end;
        v_action text;
begin
  if tg_op = 'UPDATE' and v_old = v_new and new.description is not distinct from old.description then return new; end if;
  v_action := case tg_op when 'INSERT' then 'course.created' when 'DELETE' then 'course.deleted'
    else case when new.status is distinct from old.status then
      case new.status when 'published' then 'course.published' when 'archived' then 'course.archived' else 'course.status_changed' end
      else 'course.updated' end end;
  perform public._audit006(coalesce(new.org_id, old.org_id), 'course', v_action, coalesce(new.id, old.id), v_old, v_new);
  return coalesce(new, old);
end $$;
drop trigger if exists courses_audit_006a_trg on public.courses;
create trigger courses_audit_006a_trg after insert or update or delete on public.courses for each row execute function public.audit_course_006a();

-- ---------- 5. Profil audit'i (rol / holat / bo'lim) + o'z rolini o'zgartirish taqiqi ----------
create or replace function public.audit_profile_006a() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.role is distinct from old.role then
    perform public._audit006(new.org_id, 'profile', 'profile.role_changed', new.id::text, jsonb_build_object('role', old.role), jsonb_build_object('role', new.role));
  end if;
  if new.status is distinct from old.status then
    perform public._audit006(new.org_id, 'profile', 'profile.status_changed', new.id::text, jsonb_build_object('status', old.status), jsonb_build_object('status', new.status));
  end if;
  if new.department is distinct from old.department then
    perform public._audit006(new.org_id, 'profile', 'profile.department_changed', new.id::text, jsonb_build_object('department', old.department), jsonb_build_object('department', new.department));
  end if;
  return new;
end $$;
drop trigger if exists profiles_audit_006a_trg on public.profiles;
create trigger profiles_audit_006a_trg after update on public.profiles for each row
  when (new.org_id is not null and (new.role is distinct from old.role or new.status is distinct from old.status or new.department is distinct from old.department))
  execute function public.audit_profile_006a();

create or replace function public.guard_profile_self_006a() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_api_request() and new.id = auth.uid() and (new.role is distinct from old.role or new.status is distinct from old.status) then
    raise exception 'O''z rolingizni yoki holatingizni o''zgartirib bo''lmaydi';
  end if;
  return new;
end $$;
drop trigger if exists profiles_self_guard_006a_trg on public.profiles;
create trigger profiles_self_guard_006a_trg before update on public.profiles for each row execute function public.guard_profile_self_006a();

create or replace function public.admin_set_profile_role(p_profile uuid, p_role text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_old text;
begin
  if coalesce(public.my_role(), '') not in ('super_admin','hr') then raise exception 'Ruxsat yo''q'; end if;
  if p_reason is null or length(trim(p_reason)) < 3 then raise exception 'Rol o''zgartirish sababi majburiy'; end if;
  select role into v_old from public.profiles where id = p_profile and org_id = public.my_org();
  if not found then raise exception 'Ruxsat yo''q'; end if;
  perform set_config('medacademy.audit_reason', trim(p_reason), true);
  update public.profiles set role = p_role where id = p_profile and org_id = public.my_org();   -- guard_profile / self-guard ishlaydi
  perform set_config('medacademy.audit_reason', '', true);
  return jsonb_build_object('id', p_profile, 'old_role', v_old, 'new_role', p_role);
end $$;

-- ---------- 6. exam_configs: audit + DELETE taqiqi ----------
create or replace function public.audit_exam_config_006a() returns trigger language plpgsql security definer set search_path = public as $$
declare v_old jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) - 'updated_at' end;
        v_new jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) - 'updated_at' end;
begin
  if tg_op = 'UPDATE' and v_old = v_new then return new; end if;
  perform public._audit006(coalesce(new.org_id, old.org_id), 'exam_config',
    case tg_op when 'INSERT' then 'exam_config.created' when 'DELETE' then 'exam_config.deleted' else 'exam_config.updated' end,
    coalesce(new.course_id, old.course_id), v_old, v_new);
  return coalesce(new, old);
end $$;
drop trigger if exists exam_configs_audit_006a_trg on public.exam_configs;
create trigger exam_configs_audit_006a_trg after insert or update or delete on public.exam_configs for each row execute function public.audit_exam_config_006a();

create or replace function public.guard_exam_config_delete_006a() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_api_request() then
    raise exception 'Imtihon konfiguratsiyasini o''chirib bo''lmaydi (tarixiy urinishlar bilan bog''liq) — sozlamalarni o''zgartiring yoki kursni arxivlang';
  end if;
  return old;
end $$;
drop trigger if exists exam_configs_no_delete_006a_trg on public.exam_configs;
create trigger exam_configs_no_delete_006a_trg before delete on public.exam_configs for each row execute function public.guard_exam_config_delete_006a();

-- ---------- 7. docs: tarixiy kolleksiyalarni o'chirish taqiqi ----------
create or replace function public.guard_docs_delete_006a() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_api_request() and old.collection in ('attempts','certificates','audit','progress','initial','employees') then
    raise exception 'Tarixiy yozuv (%) o''chirilmaydi', old.collection;
  end if;
  return old;
end $$;
drop trigger if exists docs_no_delete_006a_trg on public.docs;
create trigger docs_no_delete_006a_trg before delete on public.docs for each row execute function public.guard_docs_delete_006a();

-- ---------- 8. Sertifikat: berilishi va bekor qilinishi audit'i ----------
create or replace function public.audit_certificate_006a() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform public._audit006(new.org_id, 'certificate', 'certificate.issued', new.id, null,
      jsonb_build_object('user_id', new.user_id, 'course_id', new.course_id, 'score', new.score, 'attempt_id', new.attempt_id, 'issued_at', new.issued_at));
  elsif new.revoked and not coalesce(old.revoked, false) then
    perform public._audit006(new.org_id, 'certificate', 'certificate.revoked', new.id, jsonb_build_object('revoked', false),
      jsonb_build_object('revoked', true, 'revoked_by', new.revoked_by, 'revoked_at', new.revoked_at));
  end if;
  return new;
end $$;
drop trigger if exists certificates_audit_006a_trg on public.certificates;
create trigger certificates_audit_006a_trg after insert or update on public.certificates for each row execute function public.audit_certificate_006a();

create or replace function public.revoke_certificate(p_code text, p_reason text) returns boolean
language plpgsql security definer set search_path = public as $$
declare v_ok boolean;
begin
  if coalesce(public.my_role(), '') not in ('super_admin','education_manager') then raise exception 'Ruxsat yo''q'; end if;
  if p_reason is null or length(trim(p_reason)) < 3 then raise exception 'Bekor qilish sababi majburiy'; end if;
  perform set_config('medacademy.audit_reason', trim(p_reason), true);
  v_ok := public.revoke_certificate(p_code);
  perform set_config('medacademy.audit_reason', '', true);
  return v_ok;
end $$;

-- ---------- 9. Attempt reset tarixi (o'zgarmas) ----------
create table if not exists public.attempt_reset_events (
  id bigserial primary key,
  org_id uuid not null references public.organizations(id) on delete restrict,
  user_id uuid not null,
  course_id text not null,
  reset_at timestamptz not null default now(),
  reset_by uuid,
  reset_by_role text,
  reason text,
  previous_reset_at timestamptz,
  previous_reset_by uuid
);
create index if not exists attempt_reset_events_user_idx on public.attempt_reset_events (org_id, user_id, course_id, reset_at desc);
alter table public.attempt_reset_events enable row level security;
drop policy if exists attempt_reset_events_select on public.attempt_reset_events;
create policy attempt_reset_events_select on public.attempt_reset_events for select to authenticated
  using (user_id = auth.uid() or (org_id = public.my_org() and public.my_role() in ('super_admin','hr','education_manager','instructor','department_head')));
revoke all on public.attempt_reset_events from anon;
revoke insert, update, delete, truncate on public.attempt_reset_events from authenticated;
grant select on public.attempt_reset_events to authenticated;
do $$ begin execute 'revoke all on sequence public.attempt_reset_events_id_seq from anon, authenticated'; end $$;
drop trigger if exists attempt_reset_events_immutable_trg on public.attempt_reset_events;
create trigger attempt_reset_events_immutable_trg before update or delete on public.attempt_reset_events for each row execute function public.audit_logs_immutable();
drop trigger if exists attempt_reset_events_no_truncate_trg on public.attempt_reset_events;
create trigger attempt_reset_events_no_truncate_trg before truncate on public.attempt_reset_events for each statement execute function public.audit_logs_immutable();

-- Mavjud joriy reset holatini tarixga bir marta ko'chirish (yo'qolmasin)
insert into public.attempt_reset_events (org_id, user_id, course_id, reset_at, reset_by, reason)
  select r.org_id, r.user_id, r.course_id, r.reset_at, r.reset_by, '006a: mavjud reset holati (migratsiyadan oldin)'
  from public.attempt_resets r
  where not exists (select 1 from public.attempt_reset_events e where e.user_id = r.user_id and e.course_id = r.course_id and e.reset_at = r.reset_at);

create or replace function public.admin_reset_attempts(p_user uuid, p_course text, p_reason text) returns boolean
language plpgsql security definer set search_path = public as $$
declare v_prev public.attempt_resets;
begin
  if not (coalesce(public.my_role(), '') in ('super_admin','education_manager') or (public.my_role() = 'instructor' and public.is_course_instructor(p_course))) then
    raise exception 'Ruxsat yo''q';
  end if;
  if not exists (select 1 from public.profiles where id = p_user and org_id = public.my_org()) then raise exception 'Ruxsat yo''q'; end if;
  select * into v_prev from public.attempt_resets where user_id = p_user and course_id = p_course;
  insert into public.attempt_resets (org_id, user_id, course_id, reset_at, reset_by) values (public.my_org(), p_user, p_course, now(), auth.uid())
    on conflict (user_id, course_id) do update set reset_at = now(), reset_by = auth.uid();
  insert into public.attempt_reset_events (org_id, user_id, course_id, reset_at, reset_by, reset_by_role, reason, previous_reset_at, previous_reset_by)
    values (public.my_org(), p_user, p_course, now(), auth.uid(), public.my_role(), nullif(left(trim(coalesce(p_reason, '')), 500), ''), v_prev.reset_at, v_prev.reset_by);
  perform public._audit006(public.my_org(), 'attempt', 'attempt.reset', p_user::text || ':' || p_course,
    case when v_prev.reset_at is null then null else jsonb_build_object('reset_at', v_prev.reset_at, 'reset_by', v_prev.reset_by) end,
    jsonb_build_object('user_id', p_user, 'course_id', p_course, 'reason', nullif(trim(coalesce(p_reason, '')), '')));
  return true;
end $$;

-- Eski 2-argumentli chaqiruv: sababsiz, lekin tarix va audit bilan
create or replace function public.admin_reset_attempts(p_user uuid, p_course text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  return public.admin_reset_attempts(p_user, p_course, null::text);
end $$;

-- ---------- 10. question_eligibility (bitta savol, xavfsiz metadata) ----------
create or replace function public.question_eligibility(p_question text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare q public.questions; v_clin boolean; v_req boolean; v_pol public.content_policies;
begin
  if public.my_role() is null or not public.has_perm('question.view') then raise exception 'Ruxsat yo''q'; end if;
  if not public.can_see_question(p_question) then raise exception 'Savol topilmadi yoki ruxsat yo''q'; end if;
  select * into q from public.questions where id = p_question;
  if not found then raise exception 'Savol topilmadi yoki ruxsat yo''q'; end if;
  select * into v_pol from public.content_policies where org_id = coalesce(q.org_id, public.my_org()) limit 1;
  v_clin := public._q_is_clinical(q);
  v_req := v_clin and coalesce(v_pol.clinical_requires_medical_review, true);
  return jsonb_build_object(
    'id', q.id, 'course_id', q.course_id, 'clinical', v_clin, 'medical_review_required', v_req,
    'workflow_status', q.workflow_status, 'evidence_status', q.evidence_status, 'review_reason', q.review_reason,
    'current_version', q.current_version, 'published_version', q.published_version,
    'latest_evidence_decision', public._q_latest_review(q.id, null, 'evidence'),
    'latest_medical_decision', public._q_latest_review(q.id, q.current_version, 'medical'),
    'latest_medical_decision_published', case when q.published_version is null then null else public._q_latest_review(q.id, q.published_version, 'medical') end,
    'eligible', public._q_exam_eligible(q));
end $$;

-- ---------- 11. Funksiya huquqlari ----------
do $$ declare f text; begin
  foreach f in array array['public._audit006(uuid,text,text,text,jsonb,jsonb)', 'public.audit_logs_immutable()', 'public.audit_question_006a()',
    'public.audit_course_006a()', 'public.audit_profile_006a()', 'public.guard_profile_self_006a()', 'public.audit_exam_config_006a()',
    'public.guard_exam_config_delete_006a()', 'public.guard_docs_delete_006a()', 'public.audit_certificate_006a()'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.admin_set_profile_role(uuid,text,text)', 'public.revoke_certificate(text,text)',
    'public.admin_reset_attempts(uuid,text,text)', 'public.question_eligibility(text)'] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
do $$ begin
  if to_regclass('backup.function_categories_005d') is not null then
    insert into backup.function_categories_005d (name, category) values
      -- trigger funksiyalari 'internal' sifatida (hech kimga EXECUTE berilmaydi; 005d S05 qoidasi bilan mos)
      ('_audit006','internal'), ('audit_logs_immutable','internal'), ('audit_question_006a','internal'), ('audit_course_006a','internal'),
      ('audit_profile_006a','internal'), ('guard_profile_self_006a','internal'), ('audit_exam_config_006a','internal'),
      ('guard_exam_config_delete_006a','internal'), ('guard_docs_delete_006a','internal'), ('audit_certificate_006a','internal'),
      ('admin_set_profile_role','role_rpc'), ('question_eligibility','role_rpc')
    on conflict (name) do update set category = excluded.category;
  end if;
end $$;

insert into public.schema_migrations (version, description) values
  ('006a', 'Audit hardening: immutable audit_logs, question/course/profile/exam_config/certificate/attempt-reset audit, self role-change deny, attempt_reset_events history, docs/exam_configs DELETE hardening, question_eligibility RPC')
on conflict (version) do nothing;

commit;

-- Natija
select json_build_object(
  'migration', (select version from public.schema_migrations where version = '006a'),
  'audit_triggers', (select json_agg(tgname order by tgname) from pg_trigger where not tgisinternal and (tgname like '%006a%' or tgname like 'audit_logs_%_trg' or tgname like 'attempt_reset_events_%_trg')),
  'audit_logs_client_write', (select count(*) from information_schema.role_table_grants where table_schema = 'public' and table_name = 'audit_logs'
                                and grantee in ('anon','authenticated') and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE')),
  'reset_events', (select count(*) from public.attempt_reset_events),
  'attempts', (select count(*) from public.exam_attempts), 'certificates', (select count(*) from public.certificates),
  'questions', (select count(*) from public.questions), 'eligible', (select count(*) from public.questions q where public._q_exam_eligible(q))
)::text as result_006a;
