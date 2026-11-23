-- MedAcademy · Migration 005e — Medical Review avtorizatsiyasi va nashr qilishni mustahkamlash
-- 005d'dan keyin. 004 / 005 / 005d fayllari o'zgartirilmaydi. 006a EMAS (audit hardening alohida).
--
--   1. Yangi ruxsat: medical.review — faqat medical_reviewer (super_admin — implicit). EM / instructor / HR / head / employee'da YO'Q.
--      role_permissions CHECK: medical.review faqat medical_reviewer/super_admin; medical_reviewer'ga question.publish berilmaydi.
--   2. Medical Reviewer nashr qilmaydi: medical_reviewer → question.publish qatorlari olib tashlanadi (faqat shu ruxsat biriktiruvi).
--   3. question_reviews: reviewer_role_at_creation (tarixiy metadata) + review_seq (aniq "oxirgi qaror" tartibi).
--      Tarixiy rol HOZIRGI ruxsat bermaydi; eski (005e'dan oldingi) yozuvlar rolsiz → medical review sifatida haqiqiy emas.
--   4. guard_question_review: review turi aniq; medical → medical.review + rol (MR/SA); joriy yoki nashr qilingan versiya; tashkilot;
--      mark_outdated / mark_conflicting faqat evidence yoki medical review turida.
--   5. question_review_effects: evidence "rejected" → yangi imtihonlar uchun yaroqsiz (review_required, evidence_status ≠ current);
--      joriy nashr versiyasi bo'yicha medical "rejected"/"changes_requested" → review_required.
--   6. question_workflow (nashr): faqat super_admin / education_manager; klinik savol — joriy versiya bo'yicha OXIRGI haqiqiy
--      medical qaror = approved; oxirgi evidence qarori rejected bo'lsa nashr yo'q; nashrdan chiqarish faqat SA/EM.
--   7. _q_exam_eligible: yuqoridagi qoidalar yangi imtihonlar uchun ham (himoya qatlami).
--   7b. Dalil orqali bilvosita yo'llar: nashr qilingan savolning dalil bog'lanishini o'zgartirish va manbani
--       superseded/retracted/withdrawn qilish (yoki supersedes_id) — faqat evidence.review (instruktor emas).
--   8. RLS question_reviews: medical.review hisobga olinadi; INSERT faqat o'z tashkiloti.
--
-- Qoidalar: DROP TABLE / TRUNCATE / biznes ma'lumotini DELETE YO'Q. Urinishlar, sertifikatlar, review / evidence yozuvlari,
-- savol versiyalari o'zgarmaydi. Idempotent. Bitta tranzaksiya. Rollback: 005e_rollback.sql (backup.security_pre005e snapshot'idan).

begin;

do $$ begin
  if not exists (select 1 from public.schema_migrations where version = '005d') then raise exception '005e: avval 005d qo''llanishi kerak'; end if;
end $$;

-- ---------- 0. Rollback uchun snapshot (faqat birinchi marta yoziladi) ----------
create schema if not exists backup;
revoke all on schema backup from public;
do $$ begin
  if to_regclass('backup.security_pre005e') is null then
    create table backup.security_pre005e (kind text not null, name text not null, detail text, extra text, created_at timestamptz not null default now());
    alter table backup.security_pre005e enable row level security;
    insert into backup.security_pre005e (kind, name, detail)
      select 'fn_def', p.oid::regprocedure::text, pg_get_functiondef(p.oid)
      from pg_proc p where p.pronamespace = 'public'::regnamespace
        and p.oid::regprocedure::text in ('guard_question_review()', 'question_review_effects()', 'question_workflow()',
                                          '_q_exam_eligible(questions)', 'seed_org_defaults_005(uuid)',
                                          'guard_question_evidence()', 'guard_evidence_source()');
    insert into backup.security_pre005e (kind, name, detail, extra)
      select 'policy', policyname, cmd, json_build_object('roles', roles, 'qual', qual, 'with_check', with_check, 'permissive', permissive)::text
      from pg_policies where schemaname = 'public' and tablename = 'question_reviews';
    insert into backup.security_pre005e (kind, name, detail, extra)
      select 'role_perm', rp.role, rp.permission_key, rp.org_id::text
      from public.role_permissions rp where rp.role = 'medical_reviewer' and rp.permission_key = 'question.publish';
    insert into backup.security_pre005e (kind, name, detail)
      select 'counts', 'baseline', json_build_object(
        'question_reviews', (select count(*) from public.question_reviews),
        'question_evidence', (select count(*) from public.question_evidence),
        'question_versions', (select count(*) from public.question_versions),
        'exam_attempts', (select count(*) from public.exam_attempts),
        'certificates', (select count(*) from public.certificates),
        'eligible', (select count(*) from public.questions q where public._q_exam_eligible(q)))::text;
  end if;
end $$;

-- ---------- 1. Ruxsat: medical.review ----------
insert into public.permissions (key, category, description) values
  ('medical.review', 'assessment', 'Medical Review (klinik savolni tibbiy tasdiqlash / rad etish) — faqat Medical Reviewer va Super Admin')
on conflict (key) do nothing;

-- Medical Reviewer: medical.review beriladi, question.publish olib tashlanadi (faqat shu ruxsat biriktiruvi; snapshot'da saqlangan)
insert into public.role_permissions (org_id, role, permission_key)
  select o.id, 'medical_reviewer', 'medical.review' from public.organizations o
on conflict do nothing;
delete from public.role_permissions where role = 'medical_reviewer' and permission_key = 'question.publish';

do $$ begin
  alter table public.role_permissions add constraint role_permissions_005e_chk check (
    (permission_key <> 'medical.review' or role in ('medical_reviewer','super_admin'))
    and not (role = 'medical_reviewer' and permission_key = 'question.publish'));
exception when duplicate_object then null; end $$;

-- Yangi tashkilotlar uchun standart matritsa (005 matritsasi; MR: question.publish → medical.review)
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
    ('medical_reviewer','course.view'),('medical_reviewer','question.view'),('medical_reviewer','question.review'),('medical_reviewer','medical.review'),
    ('medical_reviewer','question.deprecate'),('medical_reviewer','evidence.view'),('medical_reviewer','evidence.manage'),('medical_reviewer','evidence.review'),
    ('medical_reviewer','evidence.verify'),('medical_reviewer','research.run'),('medical_reviewer','ai.use'),('medical_reviewer','quality.score'),
    ('medical_reviewer','branch.view'),('medical_reviewer','position.view'),('medical_reviewer','specialty.view'),
    ('content_author','course.view'),('content_author','question.view'),('content_author','question.create'),('content_author','question.edit'),
    ('content_author','evidence.view'),('content_author','evidence.manage'),('content_author','research.run'),('content_author','ai.use'),
    ('content_author','branch.view'),('content_author','position.view'),('content_author','specialty.view')
  ) as m(role, perm)
  on conflict do nothing;
end $$;

-- ---------- 2. Review muallifligi: tarixiy rol + aniq tartib ----------
alter table public.question_reviews add column if not exists reviewer_role_at_creation text;
alter table public.question_reviews add column if not exists review_seq bigint generated by default as identity;
do $$ begin
  alter table public.question_reviews add constraint question_reviews_reviewer_role_chk check (reviewer_role_at_creation is null or reviewer_role_at_creation in
    ('super_admin','hr','education_manager','department_head','instructor','employee','medical_reviewer','content_author'));
exception when duplicate_object then null; end $$;
create index if not exists question_reviews_latest_idx on public.question_reviews (question_id, review_type, review_seq desc);
comment on column public.question_reviews.reviewer_role_at_creation is
  '005e: review yozilgan paytdagi rol (tarixiy metadata, o''zgarmas). HOZIRGI ruxsat bermaydi. NULL = 005e''dan oldingi yozuv (medical review sifatida haqiqiy emas).';

-- Oxirgi haqiqiy qaror (medical: faqat MR/SA rolida yozilgan; p_ver NULL = barcha versiyalar)
create or replace function public._q_latest_review(p_q text, p_ver int, p_type text) returns text
language sql stable security definer set search_path = public as $$
  select r.decision from public.question_reviews r
   where r.question_id = p_q and r.review_type = p_type and (p_ver is null or r.version_no = p_ver)
     and (p_type <> 'medical' or r.reviewer_role_at_creation in ('medical_reviewer','super_admin'))
   order by r.review_seq desc limit 1
$$;
revoke execute on function public._q_latest_review(text, int, text) from public, anon, authenticated;
-- 005d funksiya kategoriyalari reyestri (mavjud bo'lsa): yangi funksiya — internal
do $$ begin
  if to_regclass('backup.function_categories_005d') is not null then
    insert into backup.function_categories_005d (name, category) values ('_q_latest_review', 'internal')
    on conflict (name) do update set category = excluded.category;
  end if;
end $$;

-- ---------- 3. Review guard: tur, rol, ruxsat, tashkilot, versiya ----------
create or replace function public.guard_question_review() returns trigger language plpgsql security definer set search_path = public as $$
declare v_q public.questions;
begin
  select * into v_q from public.questions where id = new.question_id;
  new.org_id := v_q.org_id;
  if public.is_api_request() then
    new.reviewer_id := auth.uid();
    new.reviewer_role_at_creation := public.my_role();
    if public.my_role() is null then raise exception 'Faol profil kerak'; end if;
    if new.org_id is distinct from public.my_org() then raise exception 'Boshqa tashkilot savoliga review yozib bo''lmaydi'; end if;
    if new.version_no is distinct from v_q.current_version and new.version_no is distinct from v_q.published_version then
      raise exception 'Review faqat savolning joriy (v%) yoki nashr qilingan (v%) versiyasi uchun yoziladi', v_q.current_version, coalesce(v_q.published_version::text, '-');
    end if;
    if new.review_type = 'medical' then
      if not (public.has_perm('medical.review') and public.my_role() in ('medical_reviewer','super_admin')) then
        raise exception 'Medical Review faqat Medical Reviewer yoki Super Admin tomonidan (medical.review ruxsati)';
      end if;
    elsif new.review_type = 'evidence' then
      if not public.has_perm('evidence.review') then raise exception 'Evidence review uchun evidence.review ruxsati kerak'; end if;
    else  -- instructor / editorial / psychometric
      if not public.has_perm('question.review') then raise exception 'Review uchun question.review ruxsati kerak'; end if;
    end if;
    if new.decision in ('mark_outdated','mark_conflicting') and new.review_type not in ('evidence','medical') then
      raise exception '"%" qarori faqat evidence yoki medical review''da', new.decision;
    end if;
  else
    -- platforma SQL'i (migratsiya/test): yozilish paytidagi rol
    new.reviewer_role_at_creation := coalesce(new.reviewer_role_at_creation, (select role from public.profiles where id = new.reviewer_id));
  end if;
  return new;
end $$;

-- ---------- 4. Review effektlari ----------
create or replace function public.question_review_effects() returns trigger language plpgsql security definer set search_path = public as $$
declare v_months int; v_q public.questions;
begin
  select * into v_q from public.questions where id = new.question_id;
  if new.review_type = 'evidence' and new.decision = 'approved' then
    if not exists (select 1 from public.question_evidence where question_id = new.question_id and relationship_type = 'primary_support') then
      raise exception 'Evidence review tasdig''i uchun kamida bitta primary_support manba (yoki asos) kerak';
    end if;
    if exists (select 1 from public.question_evidence qe join public.evidence_sources s on s.id = qe.evidence_source_id
               where qe.question_id = new.question_id and (qe.relationship_type = 'conflicting_evidence'
                  or (qe.relationship_type in ('primary_support','additional_support') and s.status <> 'active'))) then
      raise exception 'Ziddiyatli yoki eskirgan manba bor — avval uni hal qiling';
    end if;
    select evidence_review_months into v_months from public.content_policies where org_id = new.org_id;
    perform set_config('medacademy.system_write', 'on', true);
    update public.questions set evidence_status = 'current', last_evidence_reviewed_at = now(),
           evidence_review_due_at = now() + make_interval(months => coalesce(v_months, 24))
     where id = new.question_id;
    perform set_config('medacademy.system_write', 'off', true);
  elsif new.review_type = 'evidence' and new.decision = 'rejected' then
    -- Qaror 3: evidence rad etildi → yangi imtihonlar uchun yaroqsiz. Savol, dalil, urinish, sertifikat o'chirilmaydi / o'zgarmaydi.
    perform set_config('medacademy.system_write', 'on', true);
    update public.questions set
           evidence_status = case when evidence_status = 'current' then 'review_due' else evidence_status end,
           evidence_review_due_at = now(),
           workflow_status = case when workflow_status in ('published','approved') then 'review_required' else workflow_status end,
           review_reason = 'evidence_rejected', review_required_at = now()
     where id = new.question_id;
    perform set_config('medacademy.system_write', 'off', true);
    insert into public.evidence_events (org_id, event_type, question_id, detected_by, details)
    values (new.org_id, 'review_due', new.question_id, 'manual',
            jsonb_build_object('decision', 'evidence_rejected', 'review', new.id, 'workflow_before', v_q.workflow_status, 'evidence_before', v_q.evidence_status));
  elsif new.review_type in ('evidence','medical') and new.decision in ('mark_outdated','mark_conflicting') then
    perform set_config('medacademy.system_write', 'on', true);
    update public.questions set evidence_status = case new.decision when 'mark_outdated' then 'outdated' else 'conflicting' end,
           workflow_status = case when workflow_status in ('published','approved') then 'review_required' else workflow_status end,
           review_reason = new.decision, review_required_at = now(), evidence_review_due_at = now()
     where id = new.question_id;
    perform set_config('medacademy.system_write', 'off', true);
    insert into public.evidence_events (org_id, event_type, question_id, detected_by, details)
    values (new.org_id, case new.decision when 'mark_outdated' then 'review_due' else 'conflict_detected' end, new.question_id, 'manual',
            jsonb_build_object('decision', new.decision, 'review', new.id));
  elsif new.review_type = 'medical' and new.decision in ('rejected','changes_requested')
        and new.reviewer_role_at_creation in ('medical_reviewer','super_admin')
        and v_q.workflow_status = 'published' and new.version_no = v_q.published_version then
    -- Nashr qilingan versiya bo'yicha keyingi medical rad/o'zgartirish → yangi imtihonlardan chiqadi (qayta nashr: SA/EM + yangi tasdiq)
    perform set_config('medacademy.system_write', 'on', true);
    update public.questions set workflow_status = 'review_required', review_reason = 'medical_' || new.decision, review_required_at = now()
     where id = new.question_id;
    perform set_config('medacademy.system_write', 'off', true);
  end if;
  update public.question_review_assignments set status = 'completed'
   where question_id = new.question_id and reviewer_id = new.reviewer_id and review_type = new.review_type and status = 'open';
  return null;
end $$;

-- ---------- 5. Savol workflow / nashr guard ----------
create or replace function public.question_workflow() returns trigger language plpgsql security definer set search_path = public as $$
declare v_pol public.content_policies; v_clin boolean; v_content_changed boolean := false; v_sys boolean := coalesce(current_setting('medacademy.system_write', true), 'off') = 'on';
begin
  select * into v_pol from public.content_policies where org_id = new.org_id;
  v_clin := public._q_is_clinical(new);

  if tg_op = 'INSERT' then
    new.current_version := 1; new.published_version := null;
    if new.code is null then new.code := new.id; end if;
    if public.is_api_request() then
      new.created_by := auth.uid(); new.evidence_status := 'unknown'; new.last_evidence_reviewed_at := null;
      if new.workflow_status in ('approved','published','review_required') or new.status = 'approved' then
        new.workflow_status := 'draft'; new.status := 'draft';
      end if;
    end if;
    if new.ai_generated then new.workflow_status := 'draft'; new.status := 'draft'; end if;
  else
    v_content_changed := (new.stem, new.options, new.answer, new.explanation, new.type, new.image_url)
                         is distinct from (old.stem, old.options, old.answer, old.explanation, old.type, old.image_url);
    if new.current_version is distinct from old.current_version or new.published_version is distinct from old.published_version
       or new.created_by is distinct from old.created_by or new.ai_generated is distinct from old.ai_generated then
      if public.is_api_request() and not v_sys then raise exception 'Versiya va kelib chiqish maydonlarini to''g''ridan-to''g''ri o''zgartirib bo''lmaydi'; end if;
    end if;
    if public.is_api_request() and not v_sys
       and (new.evidence_status, new.last_evidence_reviewed_at, new.review_reason, new.review_required_at)
           is distinct from (old.evidence_status, old.last_evidence_reviewed_at, old.review_reason, old.review_required_at) then
      raise exception 'Dalil holati faqat evidence review orqali o''zgaradi';
    end if;
    if v_content_changed then
      new.current_version := old.current_version + 1;
      if old.published_version is not null and old.workflow_status in ('published','review_required') then
        new.draft_status := 'draft';        -- nashr qilingan versiya imtihonda qoladi; yangi versiya draft sifatida review'dan o'tadi
      elsif old.workflow_status = 'approved' and new.workflow_status = old.workflow_status then
        new.workflow_status := 'draft';
      end if;
    end if;
    if new.draft_status = 'publish' then new.workflow_status := 'published'; end if;
    if new.status is distinct from old.status and new.workflow_status = old.workflow_status then
      new.workflow_status := case new.status when 'approved' then 'published' when 'archived' then 'archived'
                                             when 'under_review' then 'instructor_review' else 'draft' end;
    end if;
    if new.evidence_exempt is distinct from old.evidence_exempt and public.is_api_request() and not v_sys and not public.has_perm('evidence.review') then
      raise exception 'Dalildan ozod qilishni faqat evidence.review ruxsati beradi';
    end if;
    -- 005e: nashrdan chiqarish (published → boshqa holat) faqat nashr qiluvchi rollar
    if old.workflow_status = 'published' and new.workflow_status <> 'published' and public.is_api_request() and not v_sys
       and not (public.has_perm('question.publish') and public.my_role() in ('super_admin','education_manager')) then
      raise exception 'Nashr qilingan savolni nashrdan chiqarish faqat Super Admin / Education Manager (question.publish)';
    end if;
    -- 005e: review'ga qaytarish — faqat evidence.review yoki medical.review (instruktor emas)
    if new.workflow_status = 'review_required' and old.workflow_status <> 'review_required' and public.is_api_request() and not v_sys
       and not (public.has_perm('evidence.review') or public.has_perm('medical.review')) then
      raise exception 'Savolni review''ga qaytarish uchun evidence.review yoki medical.review ruxsati kerak';
    end if;
  end if;
  if new.evidence_exempt and v_clin then
    raise exception 'Klinik savol dalildan ozod qilinmaydi (faqat Ethics/Communication/Reception/Sales kabi klinik bo''lmagan savollar)';
  end if;

  -- Nashr qoidalari (API orqali; platforma SQL'i faqat migratsiya/test uchun)
  if new.workflow_status = 'published' and (tg_op = 'INSERT' or old.workflow_status <> 'published' or new.draft_status = 'publish') then
    if public.is_api_request() and not v_sys then
      -- 005e: nashr faqat Super Admin / Education Manager (Medical Reviewer nashr qilmaydi)
      if not (public.has_perm('question.publish') and public.my_role() in ('super_admin','education_manager')) then
        raise exception 'Savolni nashr qilish faqat Super Admin / Education Manager (question.publish)';
      end if;
      if new.org_id is distinct from public.my_org() then raise exception 'Boshqa tashkilot savolini nashr qilib bo''lmaydi'; end if;
      if new.evidence_status in ('conflicting','outdated','superseded','review_due') then
        raise exception 'Dalil holati "%" — savol nashr qilinmaydi, review kerak', new.evidence_status;
      end if;
      if public._q_latest_review(new.id, null, 'evidence') = 'rejected' then
        raise exception 'Oxirgi evidence review qarori "rejected" — savol nashr qilinmaydi';
      end if;
      if v_clin then
        if new.evidence_status <> 'current' then raise exception 'Klinik savol: tasdiqlangan evidence review (evidence_status = current) kerak'; end if;
        if not exists (select 1 from public.question_evidence qe join public.evidence_sources s on s.id = qe.evidence_source_id
                       where qe.question_id = new.id and qe.relationship_type = 'primary_support' and s.status = 'active'
                         and (not coalesce(v_pol.clinical_requires_verified_source, true) or s.verification_status = 'verified')) then
          raise exception 'Klinik savol: tekshirilgan (verified) va amaldagi primary_support manba kerak';
        end if;
        -- 005e: joriy versiya bo'yicha OXIRGI haqiqiy (MR/SA rolida yozilgan) medical qaror = approved
        if coalesce(v_pol.clinical_requires_medical_review, true)
           and coalesce(public._q_latest_review(new.id, new.current_version, 'medical'), '-') <> 'approved' then
          raise exception 'Klinik savol: shu versiya (v%) bo''yicha oxirgi Medical Review qarori "approved" bo''lishi kerak', new.current_version;
        end if;
      else
        if not (new.evidence_status = 'current' or new.evidence_exempt) and coalesce(v_pol.nonclinical_requires_reference, true) then
          raise exception 'Klinik bo''lmagan savol: tasdiqlangan manba/asos (policy, standart, kodeks) yoki ozod qilish kerak';
        end if;
      end if;
      if new.ai_generated and not exists (select 1 from public.question_reviews r
                     where r.question_id = new.id and r.version_no = new.current_version and r.decision = 'approved'
                       and ((r.review_type = 'medical' and r.reviewer_role_at_creation in ('super_admin','medical_reviewer'))
                         or (r.review_type = 'instructor' and r.reviewer_role_at_creation in ('super_admin','education_manager','instructor','medical_reviewer')))) then
        raise exception 'AI yaratgan savol inson (instructor/medical reviewer) tasdig''isiz nashr qilinmaydi';
      end if;
    end if;
    new.published_version := new.current_version;     -- avvalgi versiya tarixiy (question_versions'da o'zgarmas) bo'lib qoladi
    new.approved_by := coalesce(auth.uid(), new.approved_by);
    new.review_reason := null; new.review_required_at := null; new.draft_status := null;
  end if;
  if new.workflow_status = 'deprecated' and (tg_op = 'INSERT' or old.workflow_status <> 'deprecated')
     and public.is_api_request() and not public.has_perm('question.deprecate') then
    raise exception 'Savolni eskirgan deb belgilash uchun question.deprecate ruxsati kerak';
  end if;
  new.status := case new.workflow_status when 'published' then 'approved' when 'approved' then 'approved'
                  when 'evidence_review' then 'under_review' when 'instructor_review' then 'under_review' when 'review_required' then 'under_review'
                  when 'deprecated' then 'archived' when 'archived' then 'archived' else 'draft' end;
  return new;
end $$;

-- ---------- 6. Yangi imtihonlar uchun yaroqlilik (server-side yagona qoida; himoya qatlami) ----------
-- plpgsql: rejalar sessiya davomida keshlanadi (har savol uchun qayta rejalashtirilmaydi) — SQL varianti bilan bir xil natija, ~8x tez
create or replace function public._q_exam_eligible(q public.questions) returns boolean language plpgsql stable security definer set search_path = public as $$
declare v_clin boolean;
begin
  if not (q.workflow_status = 'published' and q.published_version is not null) then return false; end if;
  v_clin := public._q_is_clinical(q);
  if not (q.evidence_status = 'current' or (q.evidence_exempt and not v_clin)) then return false; end if;
  -- himoya qatlami: asosiy/qo'shimcha manba holati kechikib yangilangan bo'lsa ham yaroqsiz
  if exists (select 1 from public.question_evidence qe join public.evidence_sources s on s.id = qe.evidence_source_id
             where qe.question_id = q.id and (qe.relationship_type = 'conflicting_evidence'
                or (qe.relationship_type in ('primary_support','additional_support') and s.status in ('superseded','retracted','withdrawn')))) then
    return false;
  end if;
  -- 005e: oxirgi evidence qarori "rejected" → yaroqsiz
  if coalesce((select r.decision from public.question_reviews r where r.question_id = q.id and r.review_type = 'evidence'
               order by r.review_seq desc limit 1), '-') = 'rejected' then
    return false;
  end if;
  -- 005e: klinik savol — nashr qilingan versiya bo'yicha oxirgi haqiqiy (MR/SA rolida yozilgan) medical qaror = approved
  if v_clin and coalesce((select p.clinical_requires_medical_review from public.content_policies p where p.org_id = q.org_id), true) then
    return coalesce((select r.decision from public.question_reviews r
                      where r.question_id = q.id and r.review_type = 'medical' and r.version_no = q.published_version
                        and r.reviewer_role_at_creation in ('medical_reviewer','super_admin')
                      order by r.review_seq desc limit 1), '-') = 'approved';
  end if;
  return true;
end $$;
revoke execute on function public._q_exam_eligible(public.questions) from public, anon;

-- ---------- 6b. Dalil orqali bilvosita yo'llar (instruktor nashr qilingan savolni imtihondan chiqara olmasin) ----------
create or replace function public.guard_question_evidence() returns trigger language plpgsql security definer set search_path = public as $$
declare v_src_org uuid; v_src_scope text;
begin
  new.org_id := (select org_id from public.questions where id = new.question_id);
  select org_id, scope_type into v_src_org, v_src_scope from public.evidence_sources where id = new.evidence_source_id;
  if v_src_scope = 'organization' and v_src_org is distinct from new.org_id then raise exception 'Boshqa tashkilot manbasini bog''lab bo''lmaydi'; end if;
  if public.is_api_request() and tg_op = 'INSERT' then new.created_by := auth.uid(); end if;
  -- 005e: nashr qilingan savolning dalil bog'lanishini o'zgartirish — faqat evidence.review
  if public.is_api_request() and coalesce(current_setting('medacademy.system_write', true), 'off') <> 'on' and not public.has_perm('evidence.review')
     and exists (select 1 from public.questions q where q.id in (new.question_id, case when tg_op = 'UPDATE' then old.question_id end) and q.workflow_status = 'published') then
    raise exception 'Nashr qilingan savol dalil bog''lanishini o''zgartirish uchun evidence.review ruxsati kerak';
  end if;
  return new;
end $$;

create or replace function public.guard_evidence_source() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_api_request() then
    if new.scope_type = 'global' or new.org_id is distinct from public.my_org() then
      raise exception 'Global dalil kutubxonasi faqat platforma administratori orqali yangilanadi';
    end if;
    if tg_op = 'INSERT' then new.created_by := auth.uid(); end if;
    if (tg_op = 'INSERT' and new.verification_status = 'verified')
       or (tg_op = 'UPDATE' and (new.verification_status, new.verified_at, new.verification_source) is distinct from (old.verification_status, old.verified_at, old.verification_source)) then
      if not public.has_perm('evidence.verify') then raise exception 'Manba tekshiruvini faqat evidence.verify ruxsati bilan tasdiqlash mumkin'; end if;
      if new.verification_status = 'verified' then new.verified_by := auth.uid(); new.verified_at := coalesce(new.verified_at, now()); end if;
    end if;
    if tg_op = 'UPDATE' and old.status in ('retracted','withdrawn') and new.status = 'active' then
      raise exception 'Bekor qilingan manbani qayta faollashtirib bo''lmaydi';
    end if;
    -- 005e: manbani eskirgan/bekor deb belgilash yoki almashtirish (savollarni review'ga tushiradi) — faqat evidence.review
    if ((tg_op = 'UPDATE' and ((new.status is distinct from old.status and new.status in ('superseded','retracted','withdrawn'))
                               or new.supersedes_id is distinct from old.supersedes_id))
        or (tg_op = 'INSERT' and (new.supersedes_id is not null or new.status in ('superseded','retracted','withdrawn'))))
       and not public.has_perm('evidence.review') then
      raise exception 'Manbani superseded/retracted/withdrawn qilish yoki almashtirish uchun evidence.review ruxsati kerak';
    end if;
  end if;
  if new.doi is not null then new.doi := lower(trim(new.doi)); end if;
  return new;
end $$;

-- ---------- 7. RLS: question_reviews ----------
drop policy if exists question_reviews_select on public.question_reviews;
create policy question_reviews_select on public.question_reviews for select to authenticated
  using (org_id = public.my_org() and (reviewer_id = auth.uid()
         or ((public.has_perm('question.review') or public.has_perm('evidence.review') or public.has_perm('medical.review')) and public.can_see_question(question_id))));
drop policy if exists question_reviews_insert on public.question_reviews;
create policy question_reviews_insert on public.question_reviews for insert to authenticated
  with check (org_id = public.my_org()
              and (public.has_perm('question.review') or public.has_perm('evidence.review') or public.has_perm('medical.review'))
              and public.can_see_question(question_id));

insert into public.schema_migrations (version, description) values
  ('005e', 'Medical review authorization: medical.review permission (MR/SA only), reviewer_role_at_creation + review_seq, latest-decision publish/eligibility gate, MR cannot publish, evidence rejection -> ineligible, instructor bypass closed')
on conflict (version) do nothing;

commit;

-- Natija
select json_build_object(
  'migration', (select version from public.schema_migrations where version = '005e'),
  'medical_review_roles', (select json_agg(distinct role) from public.role_permissions where permission_key = 'medical.review'),
  'mr_publish_rows', (select count(*) from public.role_permissions where role = 'medical_reviewer' and permission_key = 'question.publish'),
  'review_cols', (select json_agg(column_name order by column_name) from information_schema.columns where table_schema = 'public' and table_name = 'question_reviews' and column_name in ('reviewer_role_at_creation','review_seq')),
  'questions', (select count(*) from public.questions), 'eligible', (select count(*) from public.questions q where public._q_exam_eligible(q)),
  'reviews', (select count(*) from public.question_reviews), 'attempts', (select count(*) from public.exam_attempts), 'certificates', (select count(*) from public.certificates)
)::text as result_005e;
