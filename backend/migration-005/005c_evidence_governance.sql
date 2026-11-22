-- MedAcademy · Migration 005c — Evidence governance: imtihonga yaroqlilik (exam eligibility), "review_required",
-- manba ierarxiyasi (metadata), research integrity, klinik savol uchun majburiy Evidence Review → Medical Review.
-- Doimiy medical-content policy (2026-11-23):
--   * Yangi imtihonlarga faqat: workflow = published  VA  dalil holati = current (yoki klinik bo'lmagan savol uchun tasdiqlangan ozod qilish).
--   * outdated / superseded / retracted / conflicting / unknown / review_required / draft / deprecated / archived → yaroqsiz.
--   * Tarixiy urinishlar, natijalar, sertifikatlar va eski versiyalar O'ZGARMAYDI (bu migratsiya ularga tegmaydi).
-- Faqat qo'shadi/kengaytiradi. DROP TABLE / TRUNCATE / ma'lumot o'chirish yo'q. Idempotent.

-- ---------- 1. Holatlar va siyosat ----------
do $$ declare c record; begin
  for c in select conname from pg_constraint where conrelid = 'public.questions'::regclass and contype = 'c' and conname = 'questions_workflow_chk' loop
    execute 'alter table public.questions drop constraint questions_workflow_chk';
  end loop;
end $$;
alter table public.questions add constraint questions_workflow_chk check (workflow_status in
  ('draft','evidence_review','instructor_review','approved','published','review_required','deprecated','archived'));
alter table public.questions add column if not exists review_reason text;
alter table public.questions add column if not exists review_required_at timestamptz;
-- Nashr qilingan savolning yangi (ishchi) versiyasi holati: v1 imtihonda xizmat qiladi, v2 shu yerda review'dan o'tadi.
-- 'publish' — API so'rovi (saqlanmaydi): ishchi versiyani nashr qilish.
alter table public.questions add column if not exists draft_status text;
do $$ begin alter table public.questions add constraint questions_draft_status_chk check (draft_status is null or draft_status in ('draft','evidence_review','instructor_review','approved','publish'));
exception when duplicate_object then null; end $$;

alter table public.content_policies add column if not exists clinical_requires_verified_source boolean not null default true;
alter table public.content_policies add column if not exists clinical_requires_medical_review boolean not null default true;
alter table public.content_policies add column if not exists nonclinical_requires_reference boolean not null default true;

-- Review qarorlari: Admin Panel uchun "Mark Outdated" / "Mark Conflicting"
do $$ declare c record; begin
  for c in select conname from pg_constraint where conrelid = 'public.question_reviews'::regclass and contype = 'c'
            and pg_get_constraintdef(oid) like '%decision%' and conname <> 'question_reviews_decision_chk' loop
    execute format('alter table public.question_reviews drop constraint %I', c.conname);
  end loop;
end $$;
do $$ begin
  alter table public.question_reviews add constraint question_reviews_decision_chk check (decision in
    ('approved','changes_requested','rejected','mark_outdated','mark_conflicting','deprecate_recommended'));
exception when duplicate_object then null; end $$;

-- ---------- 2. Manba ierarxiyasi (faqat metadata) va research integrity ----------
do $$ declare c record; begin
  for c in select conname from pg_constraint where conrelid = 'public.evidence_sources'::regclass and contype = 'c'
            and (pg_get_constraintdef(oid) like '%source_type = ANY%' or pg_get_constraintdef(oid) like '%source_type)::text = ANY%')
            and conname not in ('evidence_sources_source_type_chk') loop
    execute format('alter table public.evidence_sources drop constraint %I', c.conname);
  end loop;
end $$;
do $$ begin
  alter table public.evidence_sources add constraint evidence_sources_source_type_chk check (source_type in ('guideline','systematic_review','meta_analysis',
    'randomized_controlled_trial','cohort_study','case_control_study','observational_study','narrative_review','textbook','educational_resource',
    'official_public_health_guidance','consensus_statement','expert_opinion','national_protocol','national_standard','local_protocol','hospital_sop',
    'institutional_policy','professional_code','other'));
exception when duplicate_object then null; end $$;
alter table public.evidence_sources drop constraint if exists evidence_sources_identifier_chk;
alter table public.evidence_sources add constraint evidence_sources_identifier_chk check (doi is not null or pmid is not null or pmcid is not null or isbn is not null or url is not null
  or source_type in ('hospital_sop','local_protocol','institutional_policy','professional_code','national_standard','textbook','educational_resource','expert_opinion'));
alter table public.evidence_sources add column if not exists evidence_tier text;
alter table public.evidence_sources add column if not exists evidence_level_basis text;
alter table public.evidence_sources add column if not exists evidence_level_set_by uuid references public.profiles(id) on delete set null;
alter table public.evidence_sources add column if not exists origin text not null default 'manual';
do $$ begin alter table public.evidence_sources add constraint evidence_sources_tier_chk check (evidence_tier is null or evidence_tier in ('primary_authoritative','secondary','educational','institutional'));
exception when duplicate_object then null; end $$;
do $$ begin alter table public.evidence_sources add constraint evidence_sources_level_basis_chk check (evidence_level_basis is null or evidence_level_basis in ('source_reported','reviewer_assessed'));
exception when duplicate_object then null; end $$;
do $$ begin alter table public.evidence_sources add constraint evidence_sources_origin_chk check (origin in ('manual','research_import','ai_suggested','platform_library'));
exception when duplicate_object then null; end $$;
-- AI taklif qilgan yoki research'dan import qilingan manba inson tekshiruvisiz "verified" bo'lmaydi
do $$ begin alter table public.evidence_sources add constraint evidence_sources_origin_verify_chk check (origin = 'manual' or verification_status <> 'verified' or verified_by is not null);
exception when duplicate_object then null; end $$;

create or replace function public._default_evidence_tier(p_type text) returns text language sql immutable as $$
  select case
    when p_type in ('guideline','systematic_review','meta_analysis','randomized_controlled_trial','official_public_health_guidance',
                    'consensus_statement','national_protocol','national_standard') then 'primary_authoritative'
    when p_type in ('cohort_study','case_control_study','observational_study','narrative_review','expert_opinion') then 'secondary'
    when p_type in ('textbook','educational_resource') then 'educational'
    when p_type in ('local_protocol','hospital_sop','institutional_policy','professional_code') then 'institutional'
    else null end
$$;
update public.evidence_sources set evidence_tier = public._default_evidence_tier(source_type) where evidence_tier is null;

-- Daraja/ierarxiya faqat inson (evidence.review) tomonidan o'zgaradi; kim belgilagani yoziladi. AI'ning yozish yo'li yo'q.

-- Research natijasi importi: identifikatorlar faqat natijadan; manba "research_import" + "unverified"
create or replace function public.import_research_result(p_result uuid, p_source_type text) returns uuid
language plpgsql security definer set search_path = public as $$
declare rr public.research_results; v_id uuid;
begin
  if not public.has_perm('evidence.manage') then raise exception 'Ruxsat yo''q'; end if;
  select * into rr from public.research_results where id = p_result and org_id = public.my_org();
  if not found then raise exception 'Natija topilmadi'; end if;
  perform set_config('medacademy.system_write', 'on', true);
  insert into public.evidence_sources (org_id, scope_type, source_type, title, authors, publication_year, journal, doi, pmid, url, external_metadata,
                                       created_by, verification_status, origin)
  values (rr.org_id, 'organization', p_source_type, rr.title, rr.authors, rr.publication_year, rr.journal, rr.doi, rr.pmid, rr.url, rr.raw_metadata,
          auth.uid(), 'unverified', 'research_import')
  returning id into v_id;
  perform set_config('medacademy.system_write', 'off', true);
  update public.research_results set imported_source_id = v_id, screening_status = 'included' where id = rr.id;
  return v_id;
end $$;
revoke execute on function public.import_research_result(uuid, text) from public, anon;
grant execute on function public.import_research_result(uuid, text) to authenticated;
-- guard_evidence_classification import yo'lini system_write orqali ajratadi
create or replace function public.guard_evidence_classification_origin_ok() returns boolean language sql stable as $$
  select coalesce(current_setting('medacademy.system_write', true), 'off') = 'on'
$$;
create or replace function public.guard_evidence_classification() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if new.evidence_tier is null then new.evidence_tier := public._default_evidence_tier(new.source_type); end if;
    if public.is_api_request() and not public.guard_evidence_classification_origin_ok() then
      if new.origin <> 'manual' then raise exception 'API orqali faqat qo''lda kiritilgan manba yaratiladi (research import alohida funksiya orqali)'; end if;
    end if;
    if public.is_api_request() and new.evidence_level is not null then
      new.evidence_level_set_by := auth.uid(); new.evidence_level_basis := coalesce(new.evidence_level_basis, 'source_reported');
    end if;
  elsif public.is_api_request() then
    if new.origin is distinct from old.origin then raise exception 'Manba kelib chiqishini (origin) o''zgartirib bo''lmaydi'; end if;
    if (new.evidence_level, new.evidence_level_scheme, new.evidence_tier, new.evidence_level_basis)
       is distinct from (old.evidence_level, old.evidence_level_scheme, old.evidence_tier, old.evidence_level_basis) then
      if not public.has_perm('evidence.review') then raise exception 'Dalil darajasi/ierarxiyasini faqat evidence.review ruxsati bilan o''zgartirish mumkin'; end if;
      new.evidence_level_set_by := auth.uid();
    end if;
  end if;
  return new;
end $$;

drop trigger if exists evidence_sources_classify_trg on public.evidence_sources;
create trigger evidence_sources_classify_trg before insert or update on public.evidence_sources for each row execute function public.guard_evidence_classification();

-- ---------- 3. Imtihonga yaroqlilik (server-side yagona qoida) ----------
create or replace function public._q_is_clinical(q public.questions) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select c.domain = any (coalesce(p.clinical_domains, '{medical,public_health,safety}'))
                   from public.courses c left join public.content_policies p on p.org_id = q.org_id where c.id = q.course_id), true)
$$;
create or replace function public._q_exam_eligible(q public.questions) returns boolean language sql stable security definer set search_path = public as $$
  select q.workflow_status = 'published'
     and q.published_version is not null
     and (q.evidence_status = 'current' or (q.evidence_exempt and not public._q_is_clinical(q)))
     -- himoya qatlami: asosiy/qo'shimcha manba holati kechikib yangilangan bo'lsa ham yaroqsiz
     and not exists (select 1 from public.question_evidence qe join public.evidence_sources s on s.id = qe.evidence_source_id
                     where qe.question_id = q.id and (qe.relationship_type = 'conflicting_evidence'
                        or (qe.relationship_type in ('primary_support','additional_support') and s.status in ('superseded','retracted','withdrawn'))))
$$;
revoke execute on function public._q_exam_eligible(public.questions) from public, anon;
revoke execute on function public._q_is_clinical(public.questions) from public, anon;

-- ---------- 4. Dalil holatini qayta hisoblash: muammo → evidence holati + "review_required" (savol matni/javobi o'zgarmaydi) ----------
create or replace function public.recompute_question_evidence(p_q text) returns text language plpgsql security definer set search_path = public as $$
declare v_old text; v_new text; q public.questions; v_reason text;
begin
  select * into q from public.questions where id = p_q for update;
  if not found then return null; end if;
  v_old := q.evidence_status;
  if exists (select 1 from public.question_evidence qe join public.evidence_sources s on s.id = qe.evidence_source_id
             where qe.question_id = p_q and qe.relationship_type = 'primary_support' and s.status in ('retracted','withdrawn')) then
    v_new := 'outdated'; v_reason := 'primary_source_retracted';
  elsif exists (select 1 from public.question_evidence qe where qe.question_id = p_q and qe.relationship_type = 'conflicting_evidence') then
    v_new := 'conflicting'; v_reason := 'conflicting_evidence';
  elsif exists (select 1 from public.question_evidence qe join public.evidence_sources s on s.id = qe.evidence_source_id
                where qe.question_id = p_q and qe.relationship_type = 'primary_support'
                  and (s.status = 'superseded' or exists (select 1 from public.evidence_sources s2 where s2.supersedes_id = s.id and s2.status = 'active'
                                                          and (s2.scope_type = 'global' or s2.org_id = q.org_id)))) then
    v_new := 'superseded'; v_reason := 'primary_source_superseded';
  elsif exists (select 1 from public.question_evidence qe join public.evidence_sources s on s.id = qe.evidence_source_id
                where qe.question_id = p_q and qe.relationship_type = 'additional_support'
                  and (s.status in ('superseded','retracted','withdrawn') or exists (select 1 from public.evidence_sources s2 where s2.supersedes_id = s.id and s2.status = 'active'
                                                          and (s2.scope_type = 'global' or s2.org_id = q.org_id)))) then
    v_new := 'review_due'; v_reason := 'supporting_source_changed';
  elsif v_old in ('outdated','conflicting','superseded') then
    v_new := 'review_due'; v_reason := 'issue_resolved_needs_review';
  else
    v_new := v_old;
  end if;
  if v_new is distinct from v_old or (v_reason is not null and q.workflow_status in ('published','approved')) then
    perform set_config('medacademy.system_write', 'on', true);
    update public.questions set evidence_status = v_new,
      evidence_review_due_at = case when v_new in ('outdated','conflicting','superseded','review_due') then now() else evidence_review_due_at end,
      workflow_status = case when v_reason is not null and workflow_status in ('published','approved') then 'review_required' else workflow_status end,
      review_reason = case when v_reason is not null and workflow_status in ('published','approved') then v_reason else review_reason end,
      review_required_at = case when v_reason is not null and workflow_status in ('published','approved') then now() else review_required_at end
      where id = p_q;
    perform set_config('medacademy.system_write', 'off', true);
    if v_new is distinct from v_old then
      insert into public.evidence_events (org_id, event_type, question_id, detected_by, details)
      values (q.org_id, case v_new when 'conflicting' then 'conflict_detected' when 'superseded' then 'superseded' when 'outdated' then 'retraction' else 'review_due' end,
              p_q, 'trigger', jsonb_build_object('from', v_old, 'to', v_new, 'reason', v_reason, 'workflow_before', q.workflow_status));
    end if;
  end if;
  return v_new;
end $$;
revoke execute on function public.recompute_question_evidence(text) from public, anon, authenticated;

-- ---------- 5. Savol workflow: majburiy Evidence Review → Medical Review → Approved → Published ----------
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
        new.draft_status := 'draft';        -- nashr qilingan versiya (v1) imtihonda qoladi; yangi versiya (v2) draft sifatida review'dan o'tadi
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
    if new.workflow_status = 'review_required' and old.workflow_status <> 'review_required' and public.is_api_request() and not v_sys
       and not (public.has_perm('question.review') or public.has_perm('evidence.review')) then
      raise exception 'Savolni review''ga qaytarish uchun question.review ruxsati kerak';
    end if;
  end if;
  if new.evidence_exempt and v_clin then
    raise exception 'Klinik savol dalildan ozod qilinmaydi (faqat Ethics/Communication/Reception/Sales kabi klinik bo''lmagan savollar)';
  end if;

  -- Nashr qoidalari (API orqali; platforma SQL'i faqat migratsiya/test uchun)
  if new.workflow_status = 'published' and (tg_op = 'INSERT' or old.workflow_status <> 'published' or new.draft_status = 'publish') then
    if public.is_api_request() and not v_sys then
      if not public.has_perm('question.publish') then raise exception 'Savolni nashr qilish uchun question.publish ruxsati kerak'; end if;
      if new.evidence_status in ('conflicting','outdated','superseded','review_due') then
        raise exception 'Dalil holati "%" — savol nashr qilinmaydi, medical review kerak', new.evidence_status;
      end if;
      if v_clin then
        if new.evidence_status <> 'current' then raise exception 'Klinik savol: tasdiqlangan evidence review (evidence_status = current) kerak'; end if;
        if not exists (select 1 from public.question_evidence qe join public.evidence_sources s on s.id = qe.evidence_source_id
                       where qe.question_id = new.id and qe.relationship_type = 'primary_support' and s.status = 'active'
                         and (not coalesce(v_pol.clinical_requires_verified_source, true) or s.verification_status = 'verified')) then
          raise exception 'Klinik savol: tekshirilgan (verified) va amaldagi primary_support manba kerak';
        end if;
        if coalesce(v_pol.clinical_requires_medical_review, true) and not exists (
             select 1 from public.question_reviews r join public.profiles p on p.id = r.reviewer_id
             where r.question_id = new.id and r.version_no = new.current_version and r.review_type = 'medical' and r.decision = 'approved'
               and p.role in ('medical_reviewer','education_manager','super_admin')) then
          raise exception 'Klinik savol: shu versiya uchun Medical Review tasdig''i kerak';
        end if;
      else
        if not (new.evidence_status = 'current' or new.evidence_exempt) and coalesce(v_pol.nonclinical_requires_reference, true) then
          raise exception 'Klinik bo''lmagan savol: tasdiqlangan manba/asos (policy, standart, kodeks) yoki ozod qilish kerak';
        end if;
      end if;
      if new.ai_generated and not exists (select 1 from public.question_reviews r join public.profiles p on p.id = r.reviewer_id
                     where r.question_id = new.id and r.version_no = new.current_version and r.decision = 'approved'
                       and r.review_type in ('medical','instructor') and p.role in ('super_admin','education_manager','instructor','medical_reviewer')) then
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

-- Review effektlari: evidence tasdig'i → current; "Mark Outdated/Conflicting" → review_required
create or replace function public.question_review_effects() returns trigger language plpgsql security definer set search_path = public as $$
declare v_months int;
begin
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
  elsif new.decision in ('mark_outdated','mark_conflicting') then
    perform set_config('medacademy.system_write', 'on', true);
    update public.questions set evidence_status = case new.decision when 'mark_outdated' then 'outdated' else 'conflicting' end,
           workflow_status = case when workflow_status in ('published','approved') then 'review_required' else workflow_status end,
           review_reason = new.decision, review_required_at = now(), evidence_review_due_at = now()
     where id = new.question_id;
    perform set_config('medacademy.system_write', 'off', true);
    insert into public.evidence_events (org_id, event_type, question_id, detected_by, details)
    values (new.org_id, case new.decision when 'mark_outdated' then 'review_due' else 'conflict_detected' end, new.question_id, 'manual',
            jsonb_build_object('decision', new.decision, 'review', new.id));
  end if;
  update public.question_review_assignments set status = 'completed'
   where question_id = new.question_id and reviewer_id = new.reviewer_id and review_type = new.review_type and status = 'open';
  return null;
end $$;

-- ---------- 6. Mavjud savollar: yaroqsiz bo'lsa "review_required" (o'chirilmaydi, versiya/urinishlarga tegilmaydi) ----------
do $$ begin
  perform set_config('medacademy.system_write', 'on', true);
  update public.questions q set workflow_status = 'review_required',
         review_reason = case when q.evidence_status = 'unknown' then 'evidence_unknown_policy_2026_11' else 'evidence_not_current' end,
         review_required_at = now()
   where q.workflow_status = 'published' and not public._q_exam_eligible(q);
  perform set_config('medacademy.system_write', 'off', true);
end $$;
create index if not exists questions_review_required_idx on public.questions (org_id, workflow_status) where workflow_status = 'review_required';

-- ---------- 7. Imtihon RPC'lari: faqat yaroqli savollar (server-side) ----------
create or replace function public.start_exam(p_course text, p_kind text, p_module text default null, p_domains jsonb default null, p_preview boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); r text := public.my_role(); v_org uuid := public.my_org();
  cfg public.exam_configs; att public.exam_attempts; v_last public.exam_attempts;
  n int; used int; v_reset timestamptz; ids text[]; ord jsonb; dmap jsonb; vers jsonb;
begin
  if uid is null or r is null or v_org is null then raise exception 'Faol akkaunt talab qilinadi'; end if;
  if p_kind not in ('module','final','initial') then raise exception 'Noto''g''ri imtihon turi'; end if;
  if p_preview and r not in ('super_admin','education_manager','instructor') then p_preview := false; end if;

  if p_kind = 'initial' then
    if p_domains is null then raise exception 'Initial assessment uchun sohalar ro''yxati kerak'; end if;
    select array_agg(s.id), jsonb_object_agg(s.id, s.d) into ids, dmap from (
      select qq.id, dd.key as d from jsonb_each_text(p_domains) dd
      cross join lateral (select id from public.questions where course_id = dd.value and org_id = v_org
                          and public._q_exam_eligible(questions)
                          and type in ('single','tf','case') order by random() limit 2) qq) s;
    if ids is null then raise exception 'Bu kurs uchun dalil (evidence) review''idan o''tgan nashr qilingan savol hali yo''q'; end if;
    select jsonb_object_agg(id, published_version) into vers from public.questions where id = any (ids);
    insert into public.exam_attempts (org_id, user_id, course_id, kind, qids, domain_map, config, is_preview, question_versions)
      values (v_org, uid, 'INITIAL', 'initial', ids, dmap, jsonb_build_object('pass', 0, 'neg', 0), p_preview, coalesce(vers, '{}')) returning * into att;
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
        where course_id = p_course and org_id = v_org and public._q_exam_eligible(questions)
          and (p_kind <> 'module' or module_id = p_module)) s
      order by s.rn, s.rnd limit n) t;
    if ids is null then raise exception 'Bu kurs uchun dalil (evidence) review''idan o''tgan nashr qilingan savol hali yo''q'; end if;
    select jsonb_object_agg(id, published_version) into vers from public.questions where id = any (ids);
    insert into public.exam_attempts (org_id, user_id, course_id, module_id, kind, qids, is_preview, deadline, config, question_versions)
      values (v_org, uid, p_course, case when p_kind = 'module' then p_module end, p_kind, ids, p_preview,
              case when p_kind = 'final' then now() + make_interval(mins => cfg.time_min) end,
              jsonb_build_object('count', cfg.question_count, 'time', cfg.time_min, 'pass', cfg.pass_score, 'attempts', cfg.max_attempts,
                                 'neg', cfg.negative_mark, 'retakeDays', cfg.retake_days), coalesce(vers, '{}'))
      returning * into att;
  end if;

  select jsonb_object_agg(q.id, (select jsonb_agg(i order by random()) from generate_series(0, jsonb_array_length(q.options) - 1) i))
    into ord from unnest(ids) u(qid) cross join lateral public._q_at(u.qid, (vers ->> u.qid)::int) q
    where q.type in ('single','multiple','case','match','image','ecg','lab') and jsonb_typeof(q.options) = 'array';
  update public.exam_attempts set option_order = coalesce(ord, '{}') where id = att.id returning * into att;
  return public._attempt_payload(att);
end $$;

create or replace function public.question_meta() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'course', course_id, 'module', module_id, 'topic', topic,
    'type', type, 'difficulty', difficulty, 'status', status)), '[]'::jsonb)
  from public.questions where public._q_exam_eligible(questions)
    and org_id = public.my_org() and public.my_role() is not null
$$;

insert into public.schema_migrations (version, description) values
  ('005c', 'Evidence governance: exam eligibility (published + current evidence), review_required, source hierarchy metadata, research integrity, mandatory evidence+medical review for clinical publish')
on conflict (version) do nothing;
