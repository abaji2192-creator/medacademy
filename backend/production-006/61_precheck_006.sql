-- PRODUCTION: 006a + 006b precheck — FAQAT SELECT. Natija: bitta JSON; 'ok' = true bo'lmasa — TO'XTASH, 006a/006b qo'llanmaydi.
-- Kutilgan bazaviy holat 2026-11-24 dagi read-only tekshiruvdan (005e deploy'dan keyin, 006a/006b'dan oldin).
with s as (select
  (select count(*) from public.schema_migrations where version = '005e') m005e,
  (select count(*) from public.schema_migrations where version = '006a') m006a,
  (select count(*) from public.schema_migrations where version = '006b') m006b,
  (select count(*) from public.courses) courses, (select count(*) from public.questions) questions, (select count(*) from public.exam_configs) exam_configs,
  (select count(*) from public.exam_attempts) attempts, (select count(*) from public.certificates) certificates, (select count(*) from public.profiles) profiles,
  (select domain from public.courses where id = 'RECEPTION_START') reception_domain,
  (select coalesce(string_agg(distinct role, ','), '-') from public.role_permissions where permission_key = 'medical.review') medical_review_roles,
  (select count(*) from public.role_permissions where role = 'medical_reviewer' and permission_key = 'question.publish') mr_publish,
  (select count(*) from pg_constraint where connamespace = 'public'::regnamespace and contype = 'f' and confdeltype = 'c') fk_cascade,
  (select coalesce(string_agg(p.proname, ',' order by p.proname), '-') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')) anon_exec,
  (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(p.prosrc) || ':' || coalesce(p.proacl::text, '-') || ':' || p.prosecdef, '|' order by p.oid::regprocedure::text))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f') fn_md5,
  (select md5(string_agg(tablename || '.' || policyname || ':' || cmd || ':' || roles::text || ':' || coalesce(qual, '-') || ':' || coalesce(with_check, '-'), '|' order by tablename, policyname))
     from pg_policies where schemaname = 'public') policy_md5,
  to_regclass('public.attempt_reset_events') is not null reset_events_exists,
  to_regclass('backup.security_pre006a') is not null snapshot_006a_exists,
  (select count(*) from backup.tables_pre006) backup_tables,
  (select count(*) from backup.tables_pre006 b where b.live_rows is not null) backup_rows_recorded,
  (select count(*) from pg_tables where schemaname = 'public') public_tables,
  (select count(*) from pg_trigger where tgname like '%006a%' or tgname like '%006b%') triggers_006
)
select json_build_object(
  'ok', m005e = 1 and m006a = 0 and m006b = 0 and courses = 13 and questions = 131 and exam_configs = 13 and attempts = 2 and certificates = 0
        and reception_domain = 'communication' and medical_review_roles = 'medical_reviewer' and mr_publish = 0 and fk_cascade = 0
        and anon_exec = 'verify_certificate' and fn_md5 = '8bdab755ce579f860c0206805794841c' and policy_md5 = '01080a074cdde90d754b266ceb4bc206'
        and not reset_events_exists and not snapshot_006a_exists and triggers_006 = 0 and backup_tables = public_tables and backup_tables > 0,
  'profiles_note', 'profiles=' || profiles || ' (kutilgan 1; yangi ro''yxatdan o''tish bo''lsa farq qilishi mumkin — ok shartiga kiritilmagan, hisobotda qayd etiladi)',
  'm005e', m005e, 'm006a', m006a, 'm006b', m006b, 'courses', courses, 'questions', questions, 'exam_configs', exam_configs, 'attempts', attempts,
  'certificates', certificates, 'profiles', profiles, 'reception_domain', reception_domain, 'medical_review_roles', medical_review_roles, 'mr_publish', mr_publish,
  'fk_cascade', fk_cascade, 'anon_exec', anon_exec, 'fn_md5', fn_md5, 'policy_md5', policy_md5, 'reset_events_exists', reset_events_exists,
  'snapshot_006a_exists', snapshot_006a_exists, 'backup_tables', backup_tables, 'public_tables', public_tables, 'triggers_006', triggers_006)::text as precheck_006
from s;
