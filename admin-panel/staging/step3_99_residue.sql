-- STEP 3 staging QA'dan keyin qoldiq tekshiruvi (READ-ONLY).
begin;
set transaction read only;
select jsonb_build_object(
  'skills_step3', (select count(*) from public.skills where code like 'STEP3%'),
  'lpa_step3', (select count(*) from public.learning_path_assignments where cancel_reason like 'STEP3%'),
  'req_step3', (select count(*) from public.competency_requirements cr join public.skills s on s.id = cr.skill_id where s.code like 'STEP3%'),
  'notif_forge', (select count(*) from public.notifications where event_key like 'step3:%'),
  'counts', (select count(*) from public.notifications) || '/' || (select count(*) from public.audit_logs) || '/' || (select count(*) from public.course_assignments) || '/' ||
            (select count(*) from public.skill_assessments) || '/' || (select count(*) from public.competency_requirements) || '/' || (select count(*) from public.learning_path_assignments)) as residue;
rollback;
