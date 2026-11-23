-- PRODUCTION: FAQAT SELECT. 005e oldidan holat tekshiruvi.
select json_build_object(
 'fingerprint', (select json_build_object(
  'migrations', (select string_agg(version, ',' order by version) from public.schema_migrations where version not like '%rollback%'),
  'fn_count', (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'),
  'fn_md5', (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(p.prosrc) || ':' || coalesce(p.proacl::text, '-') || ':' || p.prosecdef, '|' order by p.oid::regprocedure::text))
             from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'),
  'anon_exec', (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')),
  'policy_count', (select count(*) from pg_policies where schemaname = 'public'),
  'policy_md5', (select md5(string_agg(tablename || '.' || policyname || ':' || cmd || ':' || roles::text || ':' || coalesce(qual, '-') || ':' || coalesce(with_check, '-'), '|' order by tablename, policyname))
                 from pg_policies where schemaname = 'public'),
  'qr_policy_md5', (select md5(string_agg(policyname || ':' || coalesce(qual, '-') || ':' || coalesce(with_check, '-'), '|' order by policyname)) from pg_policies where schemaname = 'public' and tablename = 'question_reviews'),
  'constraint_md5', (select md5(string_agg(conrelid::regclass::text || '.' || conname || ':' || pg_get_constraintdef(oid), '|' order by conrelid::regclass::text, conname))
                     from pg_constraint where connamespace = 'public'::regnamespace),
  'column_md5', (select md5(string_agg(table_name || '.' || column_name || ':' || data_type || ':' || is_nullable || ':' || coalesce(column_default, '-') || ':' || coalesce(is_identity, '-'), '|' order by table_name, column_name))
                 from information_schema.columns where table_schema = 'public'),
  'index_md5', (select md5(string_agg(indexname || ':' || indexdef, '|' order by indexname)) from pg_indexes where schemaname = 'public'),
  'trigger_md5', (select md5(string_agg(tgrelid::regclass::text || '.' || tgname || ':' || tgfoid::regprocedure::text, '|' order by tgrelid::regclass::text, tgname)) from pg_trigger where not tgisinternal and tgrelid::regclass::text not like 'pg_%'),
  'table_acl_md5', (select md5(string_agg(c.relname || ':' || coalesce(c.relacl::text, '-') || ':' || c.relrowsecurity, '|' order by c.relname)) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'),
  'permissions_md5', (select md5(string_agg(key || ':' || category, '|' order by key)) from public.permissions),
  'role_perm_count', (select count(*) from public.role_permissions),
  'role_perm_md5', (select md5(string_agg(org_id || ':' || role || ':' || permission_key, '|' order by org_id, role, permission_key)) from public.role_permissions),
  'medical_review_roles', (select coalesce(string_agg(distinct role, ','), '-') from public.role_permissions where permission_key = 'medical.review'),
  'mr_publish_rows', (select count(*) from public.role_permissions where role = 'medical_reviewer' and permission_key = 'question.publish'),
  'data', json_build_object(
    'questions', (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(q)::text, '|' order by q.id), '')) from public.questions q),
    'question_reviews', (select count(*) || ':' || md5(coalesce(string_agg((to_jsonb(r) - 'reviewer_role_at_creation' - 'review_seq')::text, '|' order by r.id), '')) from public.question_reviews r),
    'question_evidence', (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(e)::text, '|' order by e.id), '')) from public.question_evidence e),
    'question_versions', (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(v)::text, '|' order by v.question_id, v.version_no), '')) from public.question_versions v),
    'evidence_sources', (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(s)::text, '|' order by s.id), '')) from public.evidence_sources s),
    'exam_attempts', (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(a)::text, '|' order by a.id), '')) from public.exam_attempts a),
    'certificates', (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(c)::text, '|' order by c.id), '')) from public.certificates c),
    'profiles', (select count(*) || ':' || md5(coalesce(string_agg(id || role || status || coalesce(org_id::text, ''), '|' order by id), '')) from public.profiles),
    'courses', (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(c)::text, '|' order by c.id), '')) from public.courses c),
    'reception_domain', (select coalesce(domain, '-') from public.courses where id = 'RECEPTION_START'),
    'question_publications', (select count(*) || ':' || md5(coalesce(string_agg(to_jsonb(p)::text, '|' order by p.id), '')) from public.question_publications p),
    'evidence_events', (select count(*) from public.evidence_events),
    'exam_configs', (select count(*) from public.exam_configs), 'docs', (select count(*) from public.docs),
    'eligible', (select count(*) from public.questions q where public._q_exam_eligible(q)))
)),
 'checks', json_build_object(
   'migrations_005e_rows', (select count(*) from public.schema_migrations where version like '005e%'),
   'reception_domain', (select domain from public.courses where id = 'RECEPTION_START'),
   'perm_medical_review', (select count(*) from public.permissions where key = 'medical.review'),
   'rp_medical_review', (select count(*) from public.role_permissions where permission_key = 'medical.review'),
   'fn_q_latest_review', (select count(*) from pg_proc where proname = '_q_latest_review'),
   'col_reviewer_role', (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'question_reviews' and column_name in ('reviewer_role_at_creation','review_seq')),
   'chk_005e', (select count(*) from pg_constraint where conname in ('role_permissions_005e_chk','question_reviews_reviewer_role_chk')),
   'idx_005e', (select count(*) from pg_indexes where indexname = 'question_reviews_latest_idx'),
   'backup_security_pre005e', to_regclass('backup.security_pre005e') is not null,
   'profiles', (select json_object_agg(role || '/' || status, n) from (select role, status, count(*) n from public.profiles group by 1, 2) x),
   'auth_users', (select count(*) from auth.users),
   'orgs', (select count(*) from public.organizations),
   'target_fn_md5', (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(p.prosrc), '|' order by 1)) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
       and p.proname in ('guard_question_review','question_review_effects','question_workflow','_q_exam_eligible','seed_org_defaults_005','guard_question_evidence','guard_evidence_source'))
 ))::text as prod_readonly;
