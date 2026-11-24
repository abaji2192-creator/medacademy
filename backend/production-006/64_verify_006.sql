-- PRODUCTION: 006a + 006b dan keyingi tekshiruv — FAQAT SELECT. 'ok' = true bo'lmasa — 69_rollback_006.sql (alohida qaror bilan).
with s as (select
  (select count(*) from public.schema_migrations where version in ('005e','006a','006b')) migs,
  (select count(*) from public.courses) courses, (select count(*) from public.questions) questions, (select count(*) from public.exam_configs) exam_configs,
  (select count(*) from public.exam_attempts) attempts, (select count(*) from public.certificates) certificates,
  (select md5(coalesce(string_agg(to_jsonb(a)::text, '|' order by a.id), '')) from public.exam_attempts a) attempts_md5,
  (select md5(coalesce(string_agg(to_jsonb(c)::text, '|' order by c.id), '')) from public.certificates c) certs_md5,
  (select md5(coalesce(string_agg(to_jsonb(q)::text, '|' order by q.id), '')) from public.questions q) questions_md5,
  (select md5(coalesce(string_agg(to_jsonb(c)::text, '|' order by c.id), '')) from public.courses c) courses_md5,
  (select domain from public.courses where id = 'RECEPTION_START') reception_domain,
  (select count(*) from public.role_permissions where role = 'medical_reviewer' and permission_key = 'question.publish') mr_publish,
  (select coalesce(string_agg(p.proname, ',' order by p.proname), '-') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')) anon_exec,
  (select count(*) from pg_trigger where not tgisinternal and (tgname like '%006a%' or tgname like '%006b%' or tgname like 'audit_logs_%_trg' or tgname like 'attempt_reset_events_%_trg')) triggers,
  (select count(*) from information_schema.role_table_grants where table_schema = 'public' and table_name = 'audit_logs' and grantee in ('anon','authenticated') and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE')) audit_client_write,
  (select count(*) from pg_policies where schemaname = 'public') policies,
  (select (detail::json ->> 'policies')::int from backup.security_pre006a where kind = 'counts') policies_before,
  (select relrowsecurity from pg_class where oid = 'public.attempt_reset_events'::regclass) reset_events_rls,
  (select count(*) from public.attempt_reset_events) reset_events,
  (select count(*) from public.attempt_resets) attempt_resets,
  has_function_privilege('authenticated', 'public.question_eligibility(text)'::regprocedure, 'execute') elig_auth,
  has_function_privilege('anon', 'public.question_eligibility(text)'::regprocedure, 'execute') elig_anon,
  (select count(*) from pg_constraint where connamespace = 'public'::regnamespace and contype = 'f' and confdeltype = 'c') fk_cascade
)
select json_build_object(
  'ok', migs = 3 and courses = 13 and questions = 131 and exam_configs = 13 and attempts = 2 and certificates = 0 and reception_domain = 'communication'
        and mr_publish = 0 and anon_exec = 'verify_certificate' and triggers = 13 and audit_client_write = 0 and policies = policies_before + 1
        and reset_events_rls and reset_events = attempt_resets and elig_auth and not elig_anon and fk_cascade = 0
        and attempts_md5 = (select md5(coalesce(string_agg(to_jsonb(a)::text, '|' order by a.id), '')) from backup.exam_attempts_pre006 a)
        and certs_md5 = (select md5(coalesce(string_agg(to_jsonb(c)::text, '|' order by c.id), '')) from backup.certificates_pre006 c)
        and questions_md5 = (select md5(coalesce(string_agg(to_jsonb(q)::text, '|' order by q.id), '')) from backup.questions_pre006 q)
        and courses_md5 = (select md5(coalesce(string_agg(to_jsonb(c)::text, '|' order by c.id), '')) from backup.courses_pre006 c),
  'migrations', migs, 'courses', courses, 'questions', questions, 'exam_configs', exam_configs, 'attempts', attempts, 'certificates', certificates,
  'reception_domain', reception_domain, 'mr_publish', mr_publish, 'anon_exec', anon_exec, 'triggers_006', triggers, 'audit_client_write', audit_client_write,
  'policies', policies, 'policies_before', policies_before, 'reset_events', reset_events, 'attempt_resets', attempt_resets,
  'eligibility_rpc_authenticated', elig_auth, 'eligibility_rpc_anon', elig_anon, 'fk_cascade', fk_cascade)::text as verify_006
from s;
