-- MedAcademy · Migration 005b — Evidence-Based Question System
-- Question → Topic → Evidence → Source → Review → Approval → Version zanjiri.
-- Mavjud 131 savol, exam_configs va urinishlar saqlanadi. Hech qanday soxta manba yoki research ma'lumoti yaratilmaydi.
-- Faqat qo'shadi. DROP TABLE / TRUNCATE / ma'lumot o'chirish yo'q. Idempotent.

-- ---------- 0. Tashkilot kontent siyosati ----------
create table if not exists public.content_policies (
  org_id uuid primary key references public.organizations(id) on delete restrict,
  require_primary_evidence boolean not null default true,          -- klinik savolni nashr qilish uchun primary_support + evidence review
  clinical_domains text[] not null default '{medical,public_health,safety}',
  evidence_review_months int not null default 24 check (evidence_review_months between 1 and 120),
  unknown_evidence_review_days int not null default 90 check (unknown_evidence_review_days between 1 and 3650),
  updated_at timestamptz not null default now()
);
insert into public.content_policies (org_id) select id from public.organizations on conflict do nothing;
create or replace function public.on_org_created() returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.seed_org_defaults(new.id); perform public.seed_org_defaults_005(new.id);
  insert into public.content_policies (org_id) values (new.id) on conflict do nothing;
  return new;
end $$;

-- ---------- 1. Tibbiy mavzular (global + tashkilot) ----------
create table if not exists public.medical_topics (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references public.organizations(id) on delete restrict,
  scope_type text not null default 'organization' check (scope_type in ('global','organization')),
  parent_id uuid references public.medical_topics(id) on delete restrict,
  code text not null check (code ~ '^[A-Z0-9_.-]{2,48}$'),
  name text not null,
  specialty_code text,
  guideline_topic text,
  description text,
  status text not null default 'active' check (status in ('active','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint medical_topics_scope_chk check ((scope_type = 'global' and org_id is null) or (scope_type = 'organization' and org_id is not null))
);
create unique index if not exists medical_topics_code_uq on public.medical_topics (coalesce(org_id, '00000000-0000-0000-0000-000000000000'::uuid), code);

-- ---------- 2. Dalil darajasi sxemalari (moslashuvchan, universal haqiqat sifatida kodlanmaydi) ----------
create table if not exists public.evidence_grading_schemes (
  code text primary key check (code ~ '^[A-Z0-9_]{2,32}$'),
  name text not null,
  levels jsonb not null,             -- [{"level":"A","label":"..."}] — sxema o'z ichida izohlanadi
  description text,
  created_at timestamptz not null default now()
);
insert into public.evidence_grading_schemes (code, name, levels, description) values
  ('MEDACADEMY_ABCD', 'MedAcademy educational A–D (ichki yo''l-yo''riq)',
   '[{"level":"A","label":"Systematic review / meta-analysis, high-quality RCT, authoritative guideline"},
     {"level":"B","label":"Cohort, case-control, observational evidence"},
     {"level":"C","label":"Expert consensus, narrative review"},
     {"level":"D","label":"Expert opinion, educational source"}]',
   'Faqat ta''limiy yo''naltiruvchi; klinik savol turiga qarab boshqa sxema tanlanishi mumkin.'),
  ('GRADE', 'GRADE certainty of evidence',
   '[{"level":"high"},{"level":"moderate"},{"level":"low"},{"level":"very_low"}]', 'Manba o''zi bergan GRADE bahosi kiritiladi.'),
  ('ESC_LOE', 'ESC Level of Evidence', '[{"level":"A"},{"level":"B"},{"level":"C"}]', 'Guideline tavsiyasining LOE qiymati manbadan ko''chiriladi.'),
  ('OXFORD_CEBM', 'Oxford CEBM Levels of Evidence', '[{"level":"1"},{"level":"2"},{"level":"3"},{"level":"4"},{"level":"5"}]', 'Savol turiga bog''liq.'),
  ('SOURCE_DEFINED', 'Manbaning o''z tizimi', '[]', 'Manba boshqa tizim ishlatsa, darajasi matn sifatida saqlanadi.')
on conflict (code) do nothing;

-- ---------- 3. Evidence sources (global kutubxona + tashkilot manbalari) ----------
create table if not exists public.evidence_sources (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references public.organizations(id) on delete restrict,
  scope_type text not null default 'organization' check (scope_type in ('global','organization')),
  source_type text not null check (source_type in ('guideline','systematic_review','meta_analysis','randomized_controlled_trial','cohort_study',
    'case_control_study','observational_study','narrative_review','textbook','official_public_health_guidance','consensus_statement',
    'expert_opinion','national_protocol','local_protocol','hospital_sop','other')),
  title text not null check (length(trim(title)) > 3),
  organization text,                            -- chiqaruvchi: ESC, AHA/ACC, WHO, NICE, CDC, O'zR SSV ...
  guideline_name text,
  guideline_version text,                       -- masalan: 2024
  authors text[] not null default '{}',
  publication_year int check (publication_year between 1800 and 2100),
  journal text,
  doi text check (doi is null or doi ~* '^10\.[0-9]{4,9}/\S+$'),
  pmid text check (pmid is null or pmid ~ '^[0-9]{1,9}$'),
  pmcid text check (pmcid is null or pmcid ~ '^PMC[0-9]+$'),
  isbn text,
  url text check (url is null or url ~* '^https?://'),
  publication_date date,
  accessed_at date,
  evidence_level text,
  evidence_level_scheme text references public.evidence_grading_schemes(code) on update cascade on delete restrict,
  abstract_summary text,
  jurisdiction text not null default 'international' check (jurisdiction in ('international','regional','national','local','institutional')),
  country_code text check (country_code is null or country_code ~ '^[A-Z]{2}$'),
  language text,
  supersedes_id uuid references public.evidence_sources(id) on delete restrict,
  status text not null default 'active' check (status in ('draft','active','superseded','retracted','withdrawn','archived')),
  retraction_notice_url text,
  verification_status text not null default 'unverified' check (verification_status in ('unverified','verified','failed','not_applicable')),
  verification_source text check (verification_source is null or verification_source in ('crossref','pubmed','publisher','manual')),
  verified_at timestamptz,
  verified_by uuid references public.profiles(id) on delete set null,
  external_metadata jsonb not null default '{}',   -- Crossref/PubMed javobi (faqat haqiqiy so'rov natijasi)
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint evidence_sources_scope_chk check ((scope_type = 'global' and org_id is null) or (scope_type = 'organization' and org_id is not null)),
  constraint evidence_sources_identifier_chk check (doi is not null or pmid is not null or pmcid is not null or isbn is not null or url is not null
                                                    or source_type in ('hospital_sop','local_protocol','textbook','expert_opinion') ),
  constraint evidence_sources_verified_chk check (verification_status <> 'verified' or (verified_at is not null and verification_source is not null
                                                    and (doi is not null or pmid is not null or pmcid is not null or isbn is not null or url is not null))),
  constraint evidence_sources_guideline_chk check (source_type <> 'guideline' or (organization is not null and guideline_version is not null)),
  constraint evidence_sources_not_self_chk check (supersedes_id is distinct from id)
);
create unique index if not exists evidence_sources_doi_uq on public.evidence_sources (coalesce(org_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(doi)) where doi is not null;
create unique index if not exists evidence_sources_pmid_uq on public.evidence_sources (coalesce(org_id, '00000000-0000-0000-0000-000000000000'::uuid), pmid) where pmid is not null;
create unique index if not exists evidence_sources_guideline_uq on public.evidence_sources
  (coalesce(org_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(organization), lower(coalesce(guideline_name, title)), guideline_version) where source_type = 'guideline';
create index if not exists evidence_sources_supersedes_idx on public.evidence_sources (supersedes_id);
create index if not exists evidence_sources_org_status_idx on public.evidence_sources (org_id, status);

create table if not exists public.evidence_source_topics (
  evidence_source_id uuid not null references public.evidence_sources(id) on delete restrict,
  topic_id uuid not null references public.medical_topics(id) on delete restrict,
  primary key (evidence_source_id, topic_id)
);

-- ---------- 4. Savol metadata va holatlari (mavjud jadval kengaytiriladi) ----------
alter table public.questions add column if not exists code text;
alter table public.questions add column if not exists scope_type text not null default 'organization';
alter table public.questions add column if not exists topic_id uuid references public.medical_topics(id) on delete set null;
alter table public.questions add column if not exists subtopic text;
alter table public.questions add column if not exists clinical_setting text;
alter table public.questions add column if not exists target_roles text[] not null default '{}';
alter table public.questions add column if not exists target_level text;
alter table public.questions add column if not exists learning_objective text;
alter table public.questions add column if not exists guideline_topic text;
alter table public.questions add column if not exists workflow_status text;
alter table public.questions add column if not exists evidence_status text not null default 'unknown';
alter table public.questions add column if not exists last_evidence_reviewed_at timestamptz;
alter table public.questions add column if not exists evidence_review_due_at timestamptz;
alter table public.questions add column if not exists evidence_exempt boolean not null default false;
alter table public.questions add column if not exists evidence_exempt_reason text;
alter table public.questions add column if not exists current_version int not null default 1;
alter table public.questions add column if not exists published_version int;
alter table public.questions add column if not exists ai_job_id uuid;
do $$ begin alter table public.questions add constraint questions_scope_chk check (scope_type in ('organization','global'));
exception when duplicate_object then null; end $$;
do $$ begin alter table public.questions add constraint questions_evidence_status_chk check (evidence_status in ('current','review_due','outdated','superseded','conflicting','unknown'));
exception when duplicate_object then null; end $$;
do $$ begin alter table public.questions add constraint questions_exempt_reason_chk check (not evidence_exempt or length(trim(coalesce(evidence_exempt_reason, ''))) > 5);
exception when duplicate_object then null; end $$;
do $$ begin alter table public.questions add constraint questions_published_version_chk check (published_version is null or (published_version between 1 and current_version));
exception when duplicate_object then null; end $$;

-- Backfill (faqat bir marta: workflow_status bo'sh bo'lganlar). Evidence-based deb BELGILANMAYDI.
update public.questions set
  workflow_status = case status when 'approved' then 'published' when 'under_review' then 'instructor_review' when 'archived' then 'archived' else 'draft' end,
  published_version = case when status = 'approved' then 1 end,
  evidence_status = 'unknown',
  evidence_review_due_at = case when status = 'approved' then now() + interval '90 days' end,
  code = coalesce(code, id)
where workflow_status is null;
alter table public.questions alter column workflow_status set default 'draft';
alter table public.questions alter column workflow_status set not null;
do $$ begin alter table public.questions add constraint questions_workflow_chk check (workflow_status in
  ('draft','evidence_review','instructor_review','approved','published','deprecated','archived'));
exception when duplicate_object then null; end $$;
create unique index if not exists questions_org_code_uq on public.questions (org_id, code) where code is not null;
create index if not exists questions_eligible_idx on public.questions (org_id, course_id, module_id) where published_version is not null;
create index if not exists questions_topic_idx on public.questions (topic_id);
create index if not exists questions_evidence_status_idx on public.questions (org_id, evidence_status);

-- Modul FK (mavjud module_id qiymatlari 005 seed'da course_modules'ga kiritilgan bo'lishi shart)
do $$ begin
  alter table public.questions add constraint questions_module_fk foreign key (module_id) references public.course_modules(id) on delete restrict not valid;
exception when duplicate_object then null; end $$;
alter table public.questions validate constraint questions_module_fk;

-- ---------- 5. Question ↔ Evidence ----------
create table if not exists public.question_evidence (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete restrict,
  question_id text not null references public.questions(id) on delete restrict,
  evidence_source_id uuid not null references public.evidence_sources(id) on delete restrict,
  relationship_type text not null check (relationship_type in ('primary_support','additional_support','background','conflicting_evidence')),
  citation_text text,
  supporting_claim text,                -- ichki (xodimga ko'rsatilmaydi)
  section_reference text,
  recommendation_class text,            -- masalan ESC Class I/IIa — manbadan
  level_of_evidence text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint question_evidence_uq unique (question_id, evidence_source_id, relationship_type)
);
create index if not exists question_evidence_source_idx on public.question_evidence (evidence_source_id);

-- ---------- 6. Savol versiyalari (o'zgarmas) va nashr tarixi ----------
create table if not exists public.question_versions (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete restrict,
  question_id text not null references public.questions(id) on delete restrict,
  version_no int not null check (version_no >= 1),
  snapshot jsonb not null,
  change_reason text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint question_versions_uq unique (question_id, version_no)
);
create table if not exists public.question_publications (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete restrict,
  question_id text not null references public.questions(id) on delete restrict,
  version_no int not null,
  evidence_status text not null,
  evidence_snapshot jsonb not null default '[]',
  published_by uuid references public.profiles(id) on delete set null,
  published_at timestamptz not null default now(),
  constraint question_publications_version_fk foreign key (question_id, version_no) references public.question_versions (question_id, version_no) on delete restrict
);
create index if not exists question_publications_q_idx on public.question_publications (question_id, version_no);
-- Mavjud savollar uchun v1 (o'zgartirishsiz snapshot)
insert into public.question_versions (org_id, question_id, version_no, snapshot, change_reason)
select q.org_id, q.id, 1, to_jsonb(q), 'Migration 005: boshlang''ich versiya (mavjud kontent)' from public.questions q
on conflict (question_id, version_no) do nothing;
insert into public.question_publications (org_id, question_id, version_no, evidence_status, evidence_snapshot)
select q.org_id, q.id, 1, 'unknown', '[]' from public.questions q
where q.published_version = 1 and not exists (select 1 from public.question_publications p where p.question_id = q.id);

alter table public.exam_attempts add column if not exists question_versions jsonb not null default '{}';

-- ---------- 7. Review, tayinlash, sifat ----------
create table if not exists public.question_review_assignments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete restrict,
  question_id text not null references public.questions(id) on delete restrict,
  reviewer_id uuid not null references public.profiles(id) on delete restrict,
  review_type text not null default 'medical' check (review_type in ('evidence','medical','instructor','editorial')),
  assigned_by uuid references public.profiles(id) on delete set null,
  status text not null default 'open' check (status in ('open','completed','cancelled')),
  due_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index if not exists question_review_assignments_open_uq on public.question_review_assignments (question_id, reviewer_id, review_type) where status = 'open';
create index if not exists question_review_assignments_reviewer_idx on public.question_review_assignments (reviewer_id, status);

create table if not exists public.question_reviews (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete restrict,
  question_id text not null references public.questions(id) on delete restrict,
  version_no int not null,
  review_type text not null check (review_type in ('evidence','medical','instructor','editorial','psychometric')),
  reviewer_id uuid not null references public.profiles(id) on delete restrict,
  decision text not null check (decision in ('approved','changes_requested','rejected','deprecate_recommended')),
  internal_notes text,                    -- ichki; xodimga hech qachon ko'rsatilmaydi
  checklist jsonb not null default '{}',
  created_at timestamptz not null default now(),
  constraint question_reviews_version_fk foreign key (question_id, version_no) references public.question_versions (question_id, version_no) on delete restrict
);
create index if not exists question_reviews_q_idx on public.question_reviews (question_id, version_no);

create table if not exists public.question_quality_scores (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete restrict,
  question_id text not null references public.questions(id) on delete restrict,
  version_no int not null,
  dimension text not null check (dimension in ('evidence_quality','clinical_relevance','clarity','difficulty_calibration','distractor_quality',
                                               'guideline_currency','review_status','psychometric','other')),
  score numeric not null check (score between 0 and 100),
  method text not null default 'human' check (method in ('human','ai','psychometric')),
  notes text,
  scored_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint question_quality_scores_version_fk foreign key (question_id, version_no) references public.question_versions (question_id, version_no) on delete restrict
);
create index if not exists question_quality_scores_q_idx on public.question_quality_scores (question_id, version_no);

-- ---------- 8. Research va AI (sxema tayyor; integratsiya keyin, soxta API/natija yo'q) ----------
create table if not exists public.research_queries (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete restrict,
  topic_id uuid references public.medical_topics(id) on delete set null,
  question_id text references public.questions(id) on delete restrict,
  query_text text not null check (length(trim(query_text)) > 2),
  databases text[] not null check (databases <@ array['pubmed','pmc','cochrane','crossref','who','cdc','nice','esc','aha_acc','ada','idsa','uz_moh','other_society']::text[] and cardinality(databases) > 0),
  filters jsonb not null default '{}',
  status text not null default 'queued' check (status in ('queued','running','completed','failed','cancelled')),
  requested_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);
create table if not exists public.research_results (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete restrict,
  query_id uuid not null references public.research_queries(id) on delete restrict,
  external_db text not null,
  external_id text,
  doi text check (doi is null or doi ~* '^10\.[0-9]{4,9}/\S+$'),
  pmid text check (pmid is null or pmid ~ '^[0-9]{1,9}$'),
  url text check (url is null or url ~* '^https?://'),
  title text not null,
  authors text[] not null default '{}',
  journal text,
  publication_year int,
  raw_metadata jsonb not null,             -- tashqi API'ning asl javobi
  retrieved_at timestamptz not null,
  screening_status text not null default 'pending' check (screening_status in ('pending','included','excluded')),
  imported_source_id uuid references public.evidence_sources(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint research_results_identifier_chk check (doi is not null or pmid is not null or url is not null or external_id is not null)
);
create index if not exists research_results_query_idx on public.research_results (query_id);

create table if not exists public.ai_jobs (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete restrict,
  task_type text not null check (task_type in ('question_review','evidence_search','evidence_summary','question_generation','update_detection','guideline_comparison')),
  input jsonb not null default '{}',
  output jsonb,
  model text,
  status text not null default 'queued' check (status in ('queued','running','completed','failed','cancelled')),
  requested_by uuid references public.profiles(id) on delete set null,
  created_question_ids text[] not null default '{}',
  error text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);
do $$ begin alter table public.questions add constraint questions_ai_job_fk foreign key (ai_job_id) references public.ai_jobs(id) on delete set null;
exception when duplicate_object then null; end $$;

create table if not exists public.evidence_summaries (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete restrict,
  topic_id uuid references public.medical_topics(id) on delete set null,
  question_id text references public.questions(id) on delete restrict,
  summary text not null,
  source_ids uuid[] not null check (cardinality(source_ids) > 0),
  generated_by text not null default 'human' check (generated_by in ('human','ai')),
  ai_job_id uuid references public.ai_jobs(id) on delete set null,
  status text not null default 'draft' check (status in ('draft','reviewed','approved','rejected')),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint evidence_summaries_ai_review_chk check (generated_by <> 'ai' or status in ('draft','rejected') or reviewed_by is not null)
);

-- ---------- 9. Monitoring (hozir o'chirilgan holatda; sxema tayyor) ----------
create table if not exists public.evidence_monitors (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete restrict,
  name text not null,
  topic_id uuid references public.medical_topics(id) on delete set null,
  specialty_code text,
  query_text text,
  databases text[] not null default '{}',
  frequency text not null default 'monthly' check (frequency in ('daily','weekly','monthly','quarterly')),
  enabled boolean not null default false,
  last_run_at timestamptz,
  next_run_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.evidence_events (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references public.organizations(id) on delete restrict,
  event_type text not null check (event_type in ('guideline_update','new_guideline_version','retraction','major_new_evidence','review_due','superseded','conflict_detected')),
  evidence_source_id uuid references public.evidence_sources(id) on delete restrict,
  question_id text references public.questions(id) on delete restrict,
  detected_by text not null default 'trigger' check (detected_by in ('manual','trigger','scheduled_job','ai')),
  details jsonb not null default '{}',
  status text not null default 'open' check (status in ('open','acknowledged','resolved','dismissed')),
  resolved_by uuid references public.profiles(id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists evidence_events_open_idx on public.evidence_events (org_id, status, event_type);
create index if not exists evidence_events_question_idx on public.evidence_events (question_id);

-- ---------- 10. Yordamchi funksiyalar ----------
create or replace function public.can_see_question_row(p_id text, p_org uuid, p_scope text, p_course text, p_created_by uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select (p_org = public.my_org() or p_scope = 'global') and (
      public.my_role() in ('super_admin','education_manager')
      or (public.my_role() in ('instructor','content_author') and (public.is_course_instructor(p_course) or p_created_by = auth.uid()))
      or (public.my_role() = 'medical_reviewer' and (public.is_course_instructor(p_course)
            or exists (select 1 from public.question_review_assignments a where a.question_id = p_id and a.reviewer_id = auth.uid() and a.status in ('open','completed')))))
$$;
create or replace function public.can_see_question(p_q text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select public.can_see_question_row(q.id, q.org_id, q.scope_type, q.course_id, q.created_by) from public.questions q where q.id = p_q), false)
$$;
create or replace function public.can_see_source(p_org uuid, p_scope text) returns boolean language sql stable security definer set search_path = public as $$
  select public.has_perm('evidence.view') and (p_scope = 'global' or p_org = public.my_org())
$$;

-- Savolning dalil holatini qayta hisoblash (faqat muammo bo'lsa pasaytiradi; "current" faqat inson evidence review'i bilan)
create or replace function public.recompute_question_evidence(p_q text) returns text language plpgsql security definer set search_path = public as $$
declare v_old text; v_new text; q public.questions;
begin
  select * into q from public.questions where id = p_q for update;
  if not found then return null; end if;
  v_old := q.evidence_status;
  if exists (select 1 from public.question_evidence qe join public.evidence_sources s on s.id = qe.evidence_source_id
             where qe.question_id = p_q and qe.relationship_type in ('primary_support','additional_support') and s.status in ('retracted','withdrawn')) then
    v_new := 'outdated';
  elsif exists (select 1 from public.question_evidence qe where qe.question_id = p_q and qe.relationship_type = 'conflicting_evidence') then
    v_new := 'conflicting';
  elsif exists (select 1 from public.question_evidence qe join public.evidence_sources s on s.id = qe.evidence_source_id
                where qe.question_id = p_q and qe.relationship_type = 'primary_support'
                  and (s.status = 'superseded' or exists (select 1 from public.evidence_sources s2 where s2.supersedes_id = s.id and s2.status = 'active'
                                                          and (s2.scope_type = 'global' or s2.org_id = q.org_id)))) then
    v_new := 'superseded';
  elsif v_old in ('outdated','conflicting','superseded') then
    v_new := 'review_due';          -- muammo bartaraf etildi → qayta inson review'i kerak
  else
    v_new := v_old;
  end if;
  if v_new is distinct from v_old then
    perform set_config('medacademy.system_write', 'on', true);
    update public.questions set evidence_status = v_new,
      evidence_review_due_at = case when v_new in ('outdated','conflicting','superseded','review_due') then now() else evidence_review_due_at end
      where id = p_q;
    perform set_config('medacademy.system_write', 'off', true);
    insert into public.evidence_events (org_id, event_type, question_id, detected_by, details)
    values (q.org_id, case v_new when 'conflicting' then 'conflict_detected' when 'superseded' then 'superseded' when 'outdated' then 'retraction' else 'review_due' end,
            p_q, 'trigger', jsonb_build_object('from', v_old, 'to', v_new));
  end if;
  return v_new;
end $$;
revoke execute on function public.recompute_question_evidence(text) from public, anon, authenticated;

-- Versiya bo'yicha savol (tarixiy urinishlar eski versiya bilan qoladi)
create or replace function public._q_at(p_id text, p_ver int) returns public.questions language plpgsql stable security definer set search_path = public as $$
declare r public.questions;
begin
  select (jsonb_populate_record(null::public.questions, v.snapshot)).* into r
    from public.question_versions v where v.question_id = p_id and v.version_no = coalesce(p_ver, 1);
  if r.id is null then select * into r from public.questions where id = p_id; end if;
  return r;
end $$;
revoke execute on function public._q_at(text, int) from public, anon, authenticated;

-- Natijadan keyin ko'rsatiladigan tasdiqlangan manbalar (ichki izohlarsiz)
create or replace function public._q_refs(p_id text) returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('title', s.title, 'organization', s.organization, 'version', s.guideline_version,
           'year', s.publication_year, 'journal', s.journal, 'doi', s.doi, 'pmid', s.pmid, 'url', s.url, 'type', s.source_type)
           order by qe.relationship_type, s.publication_year desc nulls last), '[]'::jsonb)
  from public.question_evidence qe join public.evidence_sources s on s.id = qe.evidence_source_id
  where qe.question_id = p_id and qe.relationship_type in ('primary_support','additional_support') and s.status in ('active','superseded')
$$;
revoke execute on function public._q_refs(text) from public, anon, authenticated;

-- ---------- 11. Trigger'lar ----------
-- Evidence source: API orqali faqat tashkilot manbasi; tekshiruv (verified) faqat evidence.verify bilan; supersede/retraction → savollarga ta'sir
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
  end if;
  if new.doi is not null then new.doi := lower(trim(new.doi)); end if;
  return new;
end $$;
create or replace function public.evidence_source_effects() returns trigger language plpgsql security definer set search_path = public as $$
declare r record;
begin
  -- Yangi versiya eski guideline'ni almashtiradi
  if new.supersedes_id is not null and (tg_op = 'INSERT' or new.supersedes_id is distinct from old.supersedes_id) then
    -- faqat bir xil doiradagi (shu tashkilot yoki global↔global) manba avtomatik "superseded" bo'ladi; aks holda faqat hodisa yoziladi
    update public.evidence_sources set status = 'superseded' where id = new.supersedes_id and status = 'active' and org_id is not distinct from new.org_id;
    insert into public.evidence_events (org_id, event_type, evidence_source_id, detected_by, details)
    values (new.org_id, 'new_guideline_version', new.supersedes_id, 'trigger', jsonb_build_object('new_source', new.id, 'version', new.guideline_version));
    -- tashkilot savollari global manbaga bog'langan bo'lsa ham review'ga tushadi
    for r in select distinct qe.question_id from public.question_evidence qe where qe.evidence_source_id = new.supersedes_id
               and (new.org_id is null or qe.org_id = new.org_id) loop
      perform public.recompute_question_evidence(r.question_id);
    end loop;
  end if;
  if tg_op = 'UPDATE' and new.status is distinct from old.status and new.status in ('superseded','retracted','withdrawn') then
    if new.status <> 'superseded' then
      insert into public.evidence_events (org_id, event_type, evidence_source_id, detected_by, details)
      values (new.org_id, 'retraction', new.id, 'trigger', jsonb_build_object('status', new.status));
    end if;
    for r in select distinct question_id from public.question_evidence where evidence_source_id = new.id loop
      perform public.recompute_question_evidence(r.question_id);
    end loop;
  end if;
  return null;
end $$;

-- Question evidence link: org savoldan olinadi; har o'zgarishda savol holati qayta hisoblanadi
create or replace function public.guard_question_evidence() returns trigger language plpgsql security definer set search_path = public as $$
declare v_src_org uuid; v_src_scope text;
begin
  new.org_id := (select org_id from public.questions where id = new.question_id);
  select org_id, scope_type into v_src_org, v_src_scope from public.evidence_sources where id = new.evidence_source_id;
  if v_src_scope = 'organization' and v_src_org is distinct from new.org_id then raise exception 'Boshqa tashkilot manbasini bog''lab bo''lmaydi'; end if;
  if public.is_api_request() and tg_op = 'INSERT' then new.created_by := auth.uid(); end if;
  return new;
end $$;
create or replace function public.question_evidence_effects() returns trigger language plpgsql security definer set search_path = public as $$
begin perform public.recompute_question_evidence(coalesce(new.question_id, old.question_id)); return null; end $$;

-- Savol workflow: versiyalash, nashr qoidalari, AI kontent, legacy status sinxroni
create or replace function public.question_workflow() returns trigger language plpgsql security definer set search_path = public as $$
declare v_pol public.content_policies; v_domain text; v_content_changed boolean := false; v_sys boolean := coalesce(current_setting('medacademy.system_write', true), 'off') = 'on';
begin
  select * into v_pol from public.content_policies where org_id = new.org_id;
  select domain into v_domain from public.courses where id = new.course_id;

  if tg_op = 'INSERT' then
    new.current_version := 1; new.published_version := null;
    if new.code is null then new.code := new.id; end if;
    if public.is_api_request() then
      new.created_by := auth.uid(); new.evidence_status := 'unknown'; new.last_evidence_reviewed_at := null;
      if new.workflow_status in ('approved','published') or new.status = 'approved' then
        -- yangi savol darhol nashr qilinmaydi: avval draft, keyin review → publish
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
       and (new.evidence_status, new.last_evidence_reviewed_at) is distinct from (old.evidence_status, old.last_evidence_reviewed_at) then
      raise exception 'Dalil holati faqat evidence review orqali o''zgaradi';
    end if;
    if v_content_changed then
      new.current_version := old.current_version + 1;
      if old.workflow_status in ('approved','published') and new.workflow_status = old.workflow_status then
        new.workflow_status := 'draft';     -- yangi versiya review'dan o'tadi; nashr qilingan eski versiya imtihonda qoladi
      end if;
    end if;
    -- Legacy UI: status='approved' → nashr so'rovi; status='archived' → arxiv
    if new.status is distinct from old.status and new.workflow_status = old.workflow_status then
      new.workflow_status := case new.status when 'approved' then 'published' when 'archived' then 'archived'
                                             when 'under_review' then 'instructor_review' else 'draft' end;
    end if;
    if new.evidence_exempt is distinct from old.evidence_exempt and public.is_api_request() and not public.has_perm('evidence.review') then
      raise exception 'Dalildan ozod qilishni faqat evidence.review ruxsati beradi';
    end if;
  end if;

  -- Nashr qoidalari
  if new.workflow_status = 'published' and (tg_op = 'INSERT' or old.workflow_status <> 'published' or new.current_version <> coalesce(old.published_version, 0)) then
    if public.is_api_request() then
      if not public.has_perm('question.publish') then raise exception 'Savolni nashr qilish uchun question.publish ruxsati kerak'; end if;
      if new.evidence_status in ('conflicting','outdated','superseded') then
        raise exception 'Dalil holati "%" — savol nashr qilinmaydi, instructor/medical review kerak', new.evidence_status;
      end if;
      if v_pol.require_primary_evidence and v_domain = any (v_pol.clinical_domains) and not new.evidence_exempt then
        if new.evidence_status <> 'current' or not exists (select 1 from public.question_evidence qe where qe.question_id = new.id and qe.relationship_type = 'primary_support') then
          raise exception 'Klinik savolni nashr qilish uchun primary_support manba va tasdiqlangan evidence review kerak';
        end if;
      end if;
      if new.ai_generated and not exists (select 1 from public.question_reviews r join public.profiles p on p.id = r.reviewer_id
                     where r.question_id = new.id and r.version_no = new.current_version and r.decision = 'approved'
                       and r.review_type in ('medical','instructor') and p.role in ('super_admin','education_manager','instructor','medical_reviewer')) then
        raise exception 'AI yaratgan savol inson (instructor/medical reviewer) tasdig''isiz nashr qilinmaydi';
      end if;
    end if;
    new.published_version := new.current_version;
    new.approved_by := coalesce(auth.uid(), new.approved_by);
  end if;
  if new.workflow_status = 'deprecated' and (tg_op = 'INSERT' or old.workflow_status <> 'deprecated')
     and public.is_api_request() and not public.has_perm('question.deprecate') then
    raise exception 'Savolni eskirgan deb belgilash uchun question.deprecate ruxsati kerak';
  end if;
  new.status := case new.workflow_status when 'published' then 'approved' when 'approved' then 'approved'
                  when 'evidence_review' then 'under_review' when 'instructor_review' then 'under_review'
                  when 'deprecated' then 'archived' when 'archived' then 'archived' else 'draft' end;
  return new;
end $$;
create or replace function public.question_versioning() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' or new.current_version <> old.current_version then
    insert into public.question_versions (org_id, question_id, version_no, snapshot, created_by)
    values (new.org_id, new.id, new.current_version, to_jsonb(new), auth.uid()) on conflict (question_id, version_no) do nothing;
  end if;
  if new.published_version is not null and (tg_op = 'INSERT' or new.published_version is distinct from old.published_version
                                            or (old.workflow_status <> 'published' and new.workflow_status = 'published')) then
    insert into public.question_publications (org_id, question_id, version_no, evidence_status, evidence_snapshot, published_by)
    values (new.org_id, new.id, new.published_version, new.evidence_status,
            (select coalesce(jsonb_agg(jsonb_build_object('source', qe.evidence_source_id, 'type', qe.relationship_type, 'citation', qe.citation_text)), '[]')
               from public.question_evidence qe where qe.question_id = new.id), auth.uid());
  end if;
  return null;
end $$;
create or replace function public.question_versions_immutable() returns trigger language plpgsql as $$
begin raise exception 'Savol versiyalari o''zgarmas (o''chirish/tahrirlash taqiqlangan)'; end $$;

-- Review: reviewer = joriy foydalanuvchi; evidence review tasdig'i → evidence_status = current
create or replace function public.guard_question_review() returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.org_id := (select org_id from public.questions where id = new.question_id);
  if public.is_api_request() then
    new.reviewer_id := auth.uid();
    if new.review_type = 'evidence' and not public.has_perm('evidence.review') then raise exception 'Evidence review uchun evidence.review ruxsati kerak'; end if;
    if new.review_type in ('medical','instructor','editorial') and not public.has_perm('question.review') then raise exception 'Review uchun question.review ruxsati kerak'; end if;
  end if;
  return new;
end $$;
create or replace function public.question_review_effects() returns trigger language plpgsql security definer set search_path = public as $$
declare v_months int;
begin
  if new.review_type = 'evidence' and new.decision = 'approved' then
    if not exists (select 1 from public.question_evidence where question_id = new.question_id and relationship_type = 'primary_support') then
      raise exception 'Evidence review tasdig''i uchun kamida bitta primary_support manba kerak';
    end if;
    if exists (select 1 from public.question_evidence qe join public.evidence_sources s on s.id = qe.evidence_source_id
               where qe.question_id = new.question_id and (qe.relationship_type = 'conflicting_evidence'
                  or (qe.relationship_type = 'primary_support' and s.status <> 'active'))) then
      raise exception 'Ziddiyatli yoki eskirgan manba bor — avval uni hal qiling';
    end if;
    select evidence_review_months into v_months from public.content_policies where org_id = new.org_id;
    perform set_config('medacademy.system_write', 'on', true);
    update public.questions set evidence_status = 'current', last_evidence_reviewed_at = now(),
           evidence_review_due_at = now() + make_interval(months => coalesce(v_months, 24))
     where id = new.question_id;
    perform set_config('medacademy.system_write', 'off', true);
  end if;
  update public.question_review_assignments set status = 'completed'
   where question_id = new.question_id and reviewer_id = new.reviewer_id and review_type = new.review_type and status = 'open';
  return null;
end $$;

-- Research natijalari va AI natijalari faqat server (service role) tomonidan yoziladi
create or replace function public.guard_requested_by() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_api_request() then
    new.requested_by := auth.uid(); new.org_id := public.my_org(); new.status := 'queued';
    if tg_table_name = 'ai_jobs' then new.output := null; new.created_question_ids := '{}'; new.completed_at := null; end if;
    if tg_table_name = 'research_queries' then new.completed_at := null; end if;
  end if;
  return new;
end $$;
create or replace function public.guard_evidence_summary() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from unnest(new.source_ids) sid where not exists (
       select 1 from public.evidence_sources s where s.id = sid and (s.scope_type = 'global' or s.org_id = new.org_id))) then
    raise exception 'Xulosa faqat mavjud va ruxsat etilgan manbalarga asoslanadi';
  end if;
  if public.is_api_request() then
    if tg_op = 'INSERT' then new.created_by := auth.uid(); new.status := 'draft'; new.reviewed_by := null; new.reviewed_at := null; end if;
    if tg_op = 'UPDATE' and new.status is distinct from old.status and new.status in ('reviewed','approved') then
      if not public.has_perm('evidence.review') then raise exception 'Xulosani tasdiqlash uchun evidence.review kerak'; end if;
      new.reviewed_by := auth.uid(); new.reviewed_at := now();
    end if;
  end if;
  return new;
end $$;
create or replace function public.guard_org_from_question() returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.org_id := (select org_id from public.questions where id = new.question_id);
  if public.is_api_request() then
    if tg_table_name = 'question_review_assignments' then new.assigned_by := auth.uid();
      if (select org_id from public.profiles where id = new.reviewer_id) is distinct from new.org_id then raise exception 'Reviewer boshqa tashkilotdan'; end if;
    elsif tg_table_name = 'question_quality_scores' then new.scored_by := auth.uid();
    end if;
  end if;
  return new;
end $$;

-- Kelajakdagi scheduled job: muddati o'tgan review'larni belgilash
create or replace function public.refresh_evidence_freshness() returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  perform set_config('medacademy.system_write', 'on', true);
  with u as (update public.questions set evidence_status = 'review_due'
             where evidence_status = 'current' and evidence_review_due_at < now() returning id, org_id)
  insert into public.evidence_events (org_id, event_type, question_id, detected_by) select org_id, 'review_due', id, 'scheduled_job' from u;
  get diagnostics n = row_count;
  perform set_config('medacademy.system_write', 'off', true);
  return n;
end $$;
revoke execute on function public.refresh_evidence_freshness() from public, anon, authenticated;

drop trigger if exists evidence_sources_guard_trg on public.evidence_sources;
create trigger evidence_sources_guard_trg before insert or update on public.evidence_sources for each row execute function public.guard_evidence_source();
drop trigger if exists evidence_sources_effects_trg on public.evidence_sources;
create trigger evidence_sources_effects_trg after insert or update on public.evidence_sources for each row execute function public.evidence_source_effects();
drop trigger if exists question_evidence_guard_trg on public.question_evidence;
create trigger question_evidence_guard_trg before insert or update on public.question_evidence for each row execute function public.guard_question_evidence();
drop trigger if exists question_evidence_effects_trg on public.question_evidence;
create trigger question_evidence_effects_trg after insert or update or delete on public.question_evidence for each row execute function public.question_evidence_effects();
drop trigger if exists questions_workflow_trg on public.questions;
create trigger questions_workflow_trg before insert or update on public.questions for each row execute function public.question_workflow();
drop trigger if exists questions_versioning_trg on public.questions;
create trigger questions_versioning_trg after insert or update on public.questions for each row execute function public.question_versioning();
drop trigger if exists question_versions_immutable_trg on public.question_versions;
create trigger question_versions_immutable_trg before update or delete on public.question_versions for each row execute function public.question_versions_immutable();
drop trigger if exists question_publications_immutable_trg on public.question_publications;
create trigger question_publications_immutable_trg before update or delete on public.question_publications for each row execute function public.question_versions_immutable();
drop trigger if exists question_reviews_immutable_trg on public.question_reviews;
create trigger question_reviews_immutable_trg before update or delete on public.question_reviews for each row execute function public.question_versions_immutable();
drop trigger if exists question_reviews_guard_trg on public.question_reviews;
create trigger question_reviews_guard_trg before insert on public.question_reviews for each row execute function public.guard_question_review();
drop trigger if exists question_reviews_effects_trg on public.question_reviews;
create trigger question_reviews_effects_trg after insert on public.question_reviews for each row execute function public.question_review_effects();
drop trigger if exists ai_jobs_guard_trg on public.ai_jobs;
create trigger ai_jobs_guard_trg before insert on public.ai_jobs for each row execute function public.guard_requested_by();
drop trigger if exists research_queries_guard_trg on public.research_queries;
create trigger research_queries_guard_trg before insert on public.research_queries for each row execute function public.guard_requested_by();
drop trigger if exists evidence_summaries_guard_trg on public.evidence_summaries;
create trigger evidence_summaries_guard_trg before insert or update on public.evidence_summaries for each row execute function public.guard_evidence_summary();
drop trigger if exists question_review_assignments_guard_trg on public.question_review_assignments;
create trigger question_review_assignments_guard_trg before insert on public.question_review_assignments for each row execute function public.guard_org_from_question();
drop trigger if exists question_quality_scores_guard_trg on public.question_quality_scores;
create trigger question_quality_scores_guard_trg before insert on public.question_quality_scores for each row execute function public.guard_org_from_question();
do $$ declare t text; begin
  foreach t in array array['question_evidence','question_reviews','question_review_assignments','content_policies'] loop
    execute format('drop trigger if exists %1$s_audit_trg on public.%1$s', t);
    execute format('create trigger %1$s_audit_trg after insert or update or delete on public.%1$s for each row execute function public.audit_row()', t);
  end loop;
  -- org_id bo'sh bo'lishi mumkin (global) — audit faqat tashkilot yozuvlari uchun
  foreach t in array array['evidence_sources','medical_topics','evidence_events'] loop
    execute format('drop trigger if exists %1$s_audit_trg on public.%1$s', t);
    execute format('create trigger %1$s_audit_trg after insert or update on public.%1$s for each row when (new.org_id is not null) execute function public.audit_row()', t);
    execute format('drop trigger if exists %1$s_audit_del_trg on public.%1$s', t);
    execute format('create trigger %1$s_audit_del_trg after delete on public.%1$s for each row when (old.org_id is not null) execute function public.audit_row()', t);
  end loop;
  foreach t in array array['evidence_sources','medical_topics','evidence_summaries','content_policies'] loop
    execute format('drop trigger if exists %1$s_touch_trg on public.%1$s', t);
    execute format('create trigger %1$s_touch_trg before update on public.%1$s for each row execute function public.touch_updated_at()', t);
  end loop;
end $$;
-- ---------- 12. RLS ----------
do $$ declare t text; begin
  foreach t in array array['content_policies','medical_topics','evidence_grading_schemes','evidence_sources','evidence_source_topics','question_evidence',
                           'question_versions','question_publications','question_review_assignments','question_reviews','question_quality_scores',
                           'research_queries','research_results','ai_jobs','evidence_summaries','evidence_monitors','evidence_events'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon', t);
  end loop;
end $$;

drop policy if exists content_policies_select on public.content_policies;
create policy content_policies_select on public.content_policies for select to authenticated using (org_id = public.my_org() and public.has_perm('question.view'));
drop policy if exists content_policies_update on public.content_policies;
create policy content_policies_update on public.content_policies for update to authenticated
  using (org_id = public.my_org() and public.has_perm('settings.manage')) with check (org_id = public.my_org());

drop policy if exists medical_topics_select on public.medical_topics;
create policy medical_topics_select on public.medical_topics for select to authenticated using ((scope_type = 'global' or org_id = public.my_org()) and public.my_role() is not null);
drop policy if exists medical_topics_write on public.medical_topics;
create policy medical_topics_write on public.medical_topics for insert to authenticated with check (scope_type = 'organization' and org_id = public.my_org() and public.has_perm('evidence.manage'));
drop policy if exists medical_topics_update on public.medical_topics;
create policy medical_topics_update on public.medical_topics for update to authenticated
  using (scope_type = 'organization' and org_id = public.my_org() and public.has_perm('evidence.manage')) with check (scope_type = 'organization' and org_id = public.my_org());

drop policy if exists evidence_grading_schemes_select on public.evidence_grading_schemes;
create policy evidence_grading_schemes_select on public.evidence_grading_schemes for select to authenticated using (public.has_perm('evidence.view'));

drop policy if exists evidence_sources_select on public.evidence_sources;
create policy evidence_sources_select on public.evidence_sources for select to authenticated using (public.can_see_source(org_id, scope_type));
drop policy if exists evidence_sources_insert on public.evidence_sources;
create policy evidence_sources_insert on public.evidence_sources for insert to authenticated
  with check (scope_type = 'organization' and org_id = public.my_org() and public.has_perm('evidence.manage'));
drop policy if exists evidence_sources_update on public.evidence_sources;
create policy evidence_sources_update on public.evidence_sources for update to authenticated
  using (scope_type = 'organization' and org_id = public.my_org() and public.has_perm('evidence.manage'))
  with check (scope_type = 'organization' and org_id = public.my_org());
drop policy if exists evidence_source_topics_select on public.evidence_source_topics;
create policy evidence_source_topics_select on public.evidence_source_topics for select to authenticated
  using (exists (select 1 from public.evidence_sources s where s.id = evidence_source_id and public.can_see_source(s.org_id, s.scope_type)));
drop policy if exists evidence_source_topics_write on public.evidence_source_topics;
create policy evidence_source_topics_write on public.evidence_source_topics for insert to authenticated
  with check (public.has_perm('evidence.manage') and exists (select 1 from public.evidence_sources s where s.id = evidence_source_id and s.org_id = public.my_org()));

drop policy if exists question_evidence_select on public.question_evidence;
create policy question_evidence_select on public.question_evidence for select to authenticated
  using (org_id = public.my_org() and public.has_perm('evidence.view') and public.can_see_question(question_id));
drop policy if exists question_evidence_insert on public.question_evidence;
create policy question_evidence_insert on public.question_evidence for insert to authenticated
  with check (public.has_perm('evidence.manage') and public.can_see_question(question_id));
drop policy if exists question_evidence_update on public.question_evidence;
create policy question_evidence_update on public.question_evidence for update to authenticated
  using (org_id = public.my_org() and public.has_perm('evidence.manage') and public.can_see_question(question_id)) with check (org_id = public.my_org());
drop policy if exists question_evidence_delete on public.question_evidence;
create policy question_evidence_delete on public.question_evidence for delete to authenticated
  using (org_id = public.my_org() and public.has_perm('evidence.review') and public.can_see_question(question_id));

drop policy if exists question_versions_select on public.question_versions;
create policy question_versions_select on public.question_versions for select to authenticated using (org_id = public.my_org() and public.can_see_question(question_id));
drop policy if exists question_publications_select on public.question_publications;
create policy question_publications_select on public.question_publications for select to authenticated using (org_id = public.my_org() and public.can_see_question(question_id));

drop policy if exists question_review_assignments_select on public.question_review_assignments;
create policy question_review_assignments_select on public.question_review_assignments for select to authenticated
  using (org_id = public.my_org() and (reviewer_id = auth.uid() or public.my_role() in ('super_admin','education_manager')));
drop policy if exists question_review_assignments_insert on public.question_review_assignments;
create policy question_review_assignments_insert on public.question_review_assignments for insert to authenticated
  with check (public.my_role() in ('super_admin','education_manager') and public.can_see_question(question_id));
drop policy if exists question_review_assignments_update on public.question_review_assignments;
create policy question_review_assignments_update on public.question_review_assignments for update to authenticated
  using (org_id = public.my_org() and public.my_role() in ('super_admin','education_manager')) with check (org_id = public.my_org());

drop policy if exists question_reviews_select on public.question_reviews;
create policy question_reviews_select on public.question_reviews for select to authenticated
  using (org_id = public.my_org() and (reviewer_id = auth.uid() or ((public.has_perm('question.review') or public.has_perm('evidence.review')) and public.can_see_question(question_id))));
drop policy if exists question_reviews_insert on public.question_reviews;
create policy question_reviews_insert on public.question_reviews for insert to authenticated
  with check ((public.has_perm('question.review') or public.has_perm('evidence.review')) and public.can_see_question(question_id));

drop policy if exists question_quality_scores_select on public.question_quality_scores;
create policy question_quality_scores_select on public.question_quality_scores for select to authenticated
  using (org_id = public.my_org() and public.has_perm('quality.score') and public.can_see_question(question_id));
drop policy if exists question_quality_scores_insert on public.question_quality_scores;
create policy question_quality_scores_insert on public.question_quality_scores for insert to authenticated
  with check (public.has_perm('quality.score') and public.can_see_question(question_id));

drop policy if exists research_queries_select on public.research_queries;
create policy research_queries_select on public.research_queries for select to authenticated using (org_id = public.my_org() and public.has_perm('research.run'));
drop policy if exists research_queries_insert on public.research_queries;
create policy research_queries_insert on public.research_queries for insert to authenticated with check (public.has_perm('research.run'));
drop policy if exists research_results_select on public.research_results;
create policy research_results_select on public.research_results for select to authenticated using (org_id = public.my_org() and public.has_perm('research.run'));
-- research_results: INSERT siyosati yo'q → faqat server integratsiyasi (service role) yozadi

drop policy if exists ai_jobs_select on public.ai_jobs;
create policy ai_jobs_select on public.ai_jobs for select to authenticated
  using (org_id = public.my_org() and (requested_by = auth.uid() or public.my_role() in ('super_admin','education_manager')));
drop policy if exists ai_jobs_insert on public.ai_jobs;
create policy ai_jobs_insert on public.ai_jobs for insert to authenticated with check (public.has_perm('ai.use'));

drop policy if exists evidence_summaries_select on public.evidence_summaries;
create policy evidence_summaries_select on public.evidence_summaries for select to authenticated using (org_id = public.my_org() and public.has_perm('evidence.view'));
drop policy if exists evidence_summaries_insert on public.evidence_summaries;
create policy evidence_summaries_insert on public.evidence_summaries for insert to authenticated with check (org_id = public.my_org() and public.has_perm('evidence.manage'));
drop policy if exists evidence_summaries_update on public.evidence_summaries;
create policy evidence_summaries_update on public.evidence_summaries for update to authenticated
  using (org_id = public.my_org() and (public.has_perm('evidence.manage') or public.has_perm('evidence.review'))) with check (org_id = public.my_org());

drop policy if exists evidence_monitors_select on public.evidence_monitors;
create policy evidence_monitors_select on public.evidence_monitors for select to authenticated using (org_id = public.my_org() and public.has_perm('evidence.view'));
drop policy if exists evidence_monitors_write on public.evidence_monitors;
create policy evidence_monitors_write on public.evidence_monitors for insert to authenticated with check (org_id = public.my_org() and public.has_perm('evidence.manage'));
drop policy if exists evidence_monitors_update on public.evidence_monitors;
create policy evidence_monitors_update on public.evidence_monitors for update to authenticated
  using (org_id = public.my_org() and public.has_perm('evidence.manage')) with check (org_id = public.my_org());

drop policy if exists evidence_events_select on public.evidence_events;
create policy evidence_events_select on public.evidence_events for select to authenticated using (org_id = public.my_org() and public.has_perm('evidence.view'));
drop policy if exists evidence_events_update on public.evidence_events;
create policy evidence_events_update on public.evidence_events for update to authenticated
  using (org_id = public.my_org() and public.has_perm('evidence.review')) with check (org_id = public.my_org());

grant select on public.content_policies, public.medical_topics, public.evidence_grading_schemes, public.evidence_sources, public.evidence_source_topics,
  public.question_evidence, public.question_versions, public.question_publications, public.question_review_assignments, public.question_reviews,
  public.question_quality_scores, public.research_queries, public.research_results, public.ai_jobs, public.evidence_summaries,
  public.evidence_monitors, public.evidence_events to authenticated;
grant insert on public.medical_topics, public.evidence_sources, public.evidence_source_topics, public.question_evidence, public.question_review_assignments,
  public.question_reviews, public.question_quality_scores, public.research_queries, public.ai_jobs, public.evidence_summaries, public.evidence_monitors to authenticated;
grant update on public.content_policies, public.medical_topics, public.evidence_sources, public.question_evidence, public.question_review_assignments,
  public.evidence_summaries, public.evidence_monitors, public.evidence_events to authenticated;
grant delete on public.question_evidence to authenticated;

-- Savollar (Phase 1 siyosatlari yangilanadi): instruktor/author faqat biriktirilgan kurs yoki o'zi yaratgan; reviewer — tayinlangan
drop policy if exists questions_select on public.questions;
create policy questions_select on public.questions for select to authenticated using (public.can_see_question_row(id, org_id, scope_type, course_id, created_by));
drop policy if exists questions_insert on public.questions;
create policy questions_insert on public.questions for insert to authenticated with check (
  org_id = public.my_org() and scope_type = 'organization' and (public.my_role() in ('super_admin','education_manager')
    or (public.my_role() in ('instructor','content_author') and public.has_perm('question.create') and public.is_course_instructor(course_id))));
drop policy if exists questions_update on public.questions;
create policy questions_update on public.questions for update to authenticated
  using (org_id = public.my_org() and public.can_see_question_row(id, org_id, scope_type, course_id, created_by) and public.my_role() in ('super_admin','education_manager','instructor','content_author','medical_reviewer'))
  with check (org_id = public.my_org());
drop policy if exists questions_delete on public.questions;   -- savollar o'chirilmaydi (versiyalar saqlanadi); archive/deprecate ishlatiladi

-- ---------- 13. Imtihon RPC'lari: nashr qilingan versiya + tarixiy versiya ----------
create or replace function public._attempt_payload(a public.exam_attempts) returns jsonb language sql stable as $$
  select public._attempt_out(a) || jsonb_build_object('questions',
    (select jsonb_agg(public._q_public(q, a.option_order -> q.id) order by array_position(a.qids, q.id))
       from unnest(a.qids) as u(qid) cross join lateral public._q_at(u.qid, (a.question_versions ->> u.qid)::int) q))
$$;
create or replace function public._q_full(q public.questions) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', q.id, 'course', q.course_id, 'module', q.module_id, 'type', q.type, 'topic', q.topic,
    'difficulty', q.difficulty, 'q', q.stem, 'o', q.options, 'a', q.answer, 'e', q.explanation, 'ev', q.evidence, 'r', q.reading,
    'image', q.image_url, 'status', q.status, 'refs', public._q_refs(q.id))
$$;

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
                          and published_version is not null and workflow_status not in ('deprecated','archived')
                          and type in ('single','tf','case') order by random() limit 2) qq) s;
    if ids is null then raise exception 'Savollar bankida savol yo''q'; end if;
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
        where course_id = p_course and org_id = v_org and published_version is not null and workflow_status not in ('deprecated','archived')
          and (p_kind <> 'module' or module_id = p_module)) s
      order by s.rn, s.rnd limit n) t;
    if ids is null then raise exception 'Savollar bankida savol yo''q'; end if;
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

create or replace function public.submit_exam(p_attempt text, p_answers jsonb default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); att public.exam_attempts; q public.questions; g jsonb; res jsonb := '{}'; total numeric := 0;
  cnt int; sc numeric; ok_pass boolean; doms jsonb; crs public.courses; prof public.profiles; emp jsonb;
  cert public.certificates; v_code text; v_name text;
begin
  select * into att from public.exam_attempts where id = p_attempt and user_id = uid for update;
  if not found then raise exception 'Urinish topilmadi'; end if;
  if att.finished_at is not null then raise exception 'Bu urinish allaqachon yakunlangan'; end if;
  if p_answers is null or (att.deadline is not null and now() > att.deadline + interval '2 minutes') then
    p_answers := coalesce(att.answers, '{}');
  end if;
  cnt := coalesce(array_length(att.qids, 1), 0);
  if cnt = 0 then raise exception 'Urinishda savol yo''q'; end if;
  for q in select x.* from unnest(att.qids) u(qid) cross join lateral public._q_at(u.qid, (att.question_versions ->> u.qid)::int) x loop
    g := public._grade(q, p_answers -> q.id, case when att.kind = 'final' then coalesce((att.config ->> 'neg')::numeric, 0) else 0 end)
         || jsonb_build_object('topic', q.topic, 'course', q.course_id, 'module', q.module_id);
    res := res || jsonb_build_object(q.id, g);
    total := total + (g ->> 'pts')::numeric;
  end loop;

  if att.kind = 'initial' then
    select jsonb_object_agg(s.d, round(100.0 * s.okc / s.n)) into doms from (
      select dm.value as d, count(*) as n, count(*) filter (where (res -> dm.key ->> 'ok')::boolean) as okc
      from jsonb_each_text(att.domain_map) dm group by dm.value) s;
    sc := round(100.0 * (select count(*) from jsonb_each(res) where (value ->> 'ok')::boolean) / cnt);
    ok_pass := true;
  else
    sc := greatest(0, round(total / cnt * 1000) / 10);
    ok_pass := sc >= coalesce((att.config ->> 'pass')::numeric, 80);
  end if;

  update public.exam_attempts set answers = p_answers, results = res, score = sc, passed = ok_pass, finished_at = now(),
    retake_after = case when att.kind = 'final' and not ok_pass then now() + make_interval(days => coalesce((att.config ->> 'retakeDays')::int, 2)) end
    where id = att.id returning * into att;

  if att.kind = 'final' and ok_pass and not att.is_preview then
    select * into crs from public.courses where id = att.course_id;
    select * into prof from public.profiles where id = uid;
    select d.data into emp from public.docs d where d.collection = 'employees' and d.id = uid::text;
    v_name := nullif(trim(coalesce(emp ->> 'firstName', '') || ' ' || coalesce(emp ->> 'lastName', '')), '');
    loop
      v_code := 'IMP-' || to_char(now(), 'YYYY') || '-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
      exit when not exists (select 1 from public.certificates where id = v_code);
    end loop;
    insert into public.certificates (id, org_id, user_id, course_id, course_title, name, position, department, score, attempt_id, expires_at)
      values (v_code, prof.org_id, uid, att.course_id, crs.title, coalesce(v_name, prof.full_name), emp ->> 'positionName', prof.department, sc, att.id,
              now() + make_interval(months => coalesce(crs.valid_months, 24)))
      returning * into cert;
  end if;

  return jsonb_build_object(
    'attempt', public._attempt_out(att),
    'certificate', case when cert.id is null then null else public._cert_out(cert) end,
    'domains', doms,
    'questions', (select jsonb_agg(public._q_full(x)) from unnest(att.qids) u(qid) cross join lateral public._q_at(u.qid, (att.question_versions ->> u.qid)::int) x));
end $$;

create or replace function public.get_attempt_review(p_attempt text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare att public.exam_attempts; r text := public.my_role();
begin
  select * into att from public.exam_attempts where id = p_attempt;
  if not found or att.finished_at is null then raise exception 'Urinish topilmadi yoki yakunlanmagan'; end if;
  if att.user_id <> auth.uid() and (att.org_id is distinct from public.my_org()
       or not (coalesce(r, '') in ('super_admin','education_manager') or (r = 'instructor' and public.is_course_instructor(att.course_id)))) then
    raise exception 'Ruxsat yo''q';
  end if;
  return jsonb_build_object('attempt', public._attempt_out(att),
    'questions', (select jsonb_agg(public._q_full(x)) from unnest(att.qids) u(qid) cross join lateral public._q_at(u.qid, (att.question_versions ->> u.qid)::int) x));
end $$;

create or replace function public.question_meta() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'course', course_id, 'module', module_id, 'topic', topic,
    'type', type, 'difficulty', difficulty, 'status', status)), '[]'::jsonb)
  from public.questions where published_version is not null and workflow_status not in ('deprecated','archived')
    and org_id = public.my_org() and public.my_role() is not null
$$;

create or replace function public.admin_reset_attempts(p_user uuid, p_course text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not (coalesce(public.my_role(), '') in ('super_admin','education_manager') or (public.my_role() = 'instructor' and public.is_course_instructor(p_course))) then
    raise exception 'Ruxsat yo''q';
  end if;
  if not exists (select 1 from public.profiles where id = p_user and org_id = public.my_org()) then raise exception 'Ruxsat yo''q'; end if;
  insert into public.attempt_resets (org_id, user_id, course_id, reset_at, reset_by) values (public.my_org(), p_user, p_course, now(), auth.uid())
    on conflict (user_id, course_id) do update set reset_at = now(), reset_by = auth.uid();
  return true;
end $$;

-- Research natijasini manbaga aylantirish (tekshirilmagan holatda; identifikatorlar natijadan ko'chiriladi, uydirilmaydi)
create or replace function public.import_research_result(p_result uuid, p_source_type text) returns uuid
language plpgsql security definer set search_path = public as $$
declare rr public.research_results; v_id uuid;
begin
  if not public.has_perm('evidence.manage') then raise exception 'Ruxsat yo''q'; end if;
  select * into rr from public.research_results where id = p_result and org_id = public.my_org();
  if not found then raise exception 'Natija topilmadi'; end if;
  insert into public.evidence_sources (org_id, scope_type, source_type, title, authors, publication_year, journal, doi, pmid, url, external_metadata, created_by, verification_status)
  values (rr.org_id, 'organization', p_source_type, rr.title, rr.authors, rr.publication_year, rr.journal, rr.doi, rr.pmid, rr.url, rr.raw_metadata, auth.uid(), 'unverified')
  returning id into v_id;
  update public.research_results set imported_source_id = v_id, screening_status = 'included' where id = rr.id;
  return v_id;
end $$;
revoke execute on function public.import_research_result(uuid, text) from public, anon;
grant execute on function public.import_research_result(uuid, text) to authenticated;

insert into public.schema_migrations (version, description) values
  ('005a', 'Course modules, lessons, assignments, progress, learning paths, instructors, roles, invitations'),
  ('005b', 'Evidence-based question system: sources, links, versions, reviews, research/AI schema, versioned exams')
on conflict (version) do nothing;
