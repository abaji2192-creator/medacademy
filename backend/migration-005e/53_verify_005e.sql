-- PRODUCTION: 005e post-apply / yakuniy holat tekshiruvi — FAQAT SELECT (pg_temp yordamchi funksiya faqat sessiya ichida).
create or replace function pg_temp.bsame(t text, b text) returns boolean language plpgsql as $$ declare x text; y text; begin
  execute format('select coalesce(md5(string_agg(md5(r::text), '''' order by md5(r::text))), ''-'') from public.%I r', t) into x;
  execute format('select coalesce(md5(string_agg(md5(r::text), '''' order by md5(r::text))), ''-'') from backup.%I r', b) into y;
  return x = y; end $$;
with fp as (select (select json_build_object(
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
)) j),
fk as (select count(*) filter (where confdeltype = 'c') c, count(*) filter (where confdeltype = 'r') r from pg_constraint
       where contype = 'f' and conname in ('profiles_id_fkey','docs_owner_fkey','exam_attempts_user_id_fkey','certificates_user_id_fkey','attempt_resets_user_id_fkey','exam_configs_course_id_fkey')),
v as (select json_build_object(
  'migrations', (select string_agg(version, ',' order by version) from public.schema_migrations),
  'courses', (select count(*) from public.courses), 'questions', (select count(*) from public.questions), 'exam_configs', (select count(*) from public.exam_configs),
  'exam_attempts', (select count(*) from public.exam_attempts), 'certificates', (select count(*) from public.certificates),
  'profiles', (select count(*) from public.profiles), 'auth_users', (select count(*) from auth.users), 'orgs', (select count(*) from public.organizations),
  'roles', (select string_agg(role || '/' || status, ',' order by role) from public.profiles),
  'reception_domain', (select domain from public.courses where id = 'RECEPTION_START'),
  'cascade_fk6', (select c from fk), 'restrict_fk6', (select r from fk),
  'cascade_fk_all', (select count(*) from pg_constraint where contype = 'f' and confdeltype = 'c' and connamespace = 'public'::regnamespace),
  'anon_exec', (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')),
  'anon_exec_names', (select string_agg(proname, ',') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')),
  'test_accounts', (select count(*) from auth.users where email ilike '%test.local' or email ilike '%invalid.local' or id::text like 'a0000000-%' or id::text like 'b0000000-%' or id::text like 'd0000000-%' or id::text like 'e0000000-%'),
  'mr_em_ins_profiles', (select count(*) from public.profiles where role in ('medical_reviewer','education_manager','instructor','hr','department_head','content_author')),
  'question_reviews', (select count(*) from public.question_reviews), 'question_evidence', (select count(*) from public.question_evidence),
  'evidence_sources', (select count(*) from public.evidence_sources), 'review_assignments', (select count(*) from public.question_review_assignments),
  'test_rows', (select count(*) from public.questions where id like 'T5%' or id like 'TQ_%' or id like 'TESTB%' or stem like 'T5E%') + (select count(*) from public.courses where id like 'TEST%' or id like 'T5%') + (select count(*) from public.exam_attempts where id like 'T5%'),
  'o05e_perm', (select count(*) from public.permissions where key = 'medical.review'),
  'o05e_rp', (select count(*) from public.role_permissions where permission_key = 'medical.review'),
  'o05e_fn', (select count(*) from pg_proc where proname = '_q_latest_review'),
  'o05e_cols', (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'question_reviews' and column_name in ('reviewer_role_at_creation','review_seq')),
  'o05e_chk', (select count(*) from pg_constraint where conname in ('role_permissions_005e_chk','question_reviews_reviewer_role_chk')),
  'o05e_idx', (select count(*) from pg_indexes where indexname = 'question_reviews_latest_idx'),
  'o05e_snapshot', (to_regclass('backup.security_pre005e') is not null),
  'mr_publish_rows', (select count(*) from public.role_permissions where role = 'medical_reviewer' and permission_key = 'question.publish'),
  'medical_review_roles', (select coalesce(string_agg(distinct role, ','), '-') from public.role_permissions where permission_key = 'medical.review'),
  'medical_review_roles_all_orgs', (select count(distinct org_id) from public.role_permissions where permission_key = 'medical.review'),
  'backup_tables_005e', (select count(*) from pg_tables where schemaname = 'backup' and tablename like '%_pre005e_20261124'),
  'backup_identical', (select count(*) from backup.tables_pre005e_20261124 b where to_regclass('backup.' || b.backup_table) is not null) ,
  'fp', (select j from fp)) j)
,
cd as (select coalesce(string_agg(c.id || ':' || b.domain || '->' || c.domain, ',' order by c.id), '-') changed, count(*) n
       from public.courses c full join backup.courses_pre005e_20261124 b on b.id = c.id where to_jsonb(c) is distinct from to_jsonb(b)),
dd as (select coalesce(string_agg(b.tablename, ',' order by b.tablename) filter (where not pg_temp.bsame(b.tablename, b.backup_table)), '-') names
         from backup.tables_pre005e_20261124 b)
select json_build_object('ok',
  (j->>'migrations') = '001,002,003,004a,004b,005a,005b,005c,005d,005e'
  and (j->>'courses')::int = 13 and (j->>'questions')::int = 131 and (j->>'exam_configs')::int = 13 and (j->>'exam_attempts')::int = 2
  and (j->>'certificates')::int = 0 and (j->>'profiles')::int = 1 and (j->>'auth_users')::int = 1
  and (j->>'reception_domain') = 'communication' and (select n from cd) = 1 and (select changed from cd) = 'RECEPTION_START:medical->communication'
  and (j->>'cascade_fk6')::int = 0 and (j->>'restrict_fk6')::int = 6 and (j->>'cascade_fk_all')::int = 0 and (j->>'anon_exec')::int = 1 and (j->>'anon_exec_names') = 'verify_certificate'
  and (j->>'test_accounts')::int = 0 and (j->>'mr_em_ins_profiles')::int = 0 and (j->>'test_rows')::int = 0
  and (j->>'question_reviews')::int = 0 and (j->>'question_evidence')::int = 0 and (j->>'evidence_sources')::int = 0
  and (j->>'o05e_perm')::int = 1 and (j->>'medical_review_roles') = 'medical_reviewer' and (j->>'medical_review_roles_all_orgs')::int = (j->>'orgs')::int
  and (j->>'mr_publish_rows')::int = 0 and (j->>'o05e_fn')::int = 1 and (j->>'o05e_cols')::int = 2 and (j->>'o05e_chk')::int = 2 and (j->>'o05e_idx')::int = 1
  and (j->>'o05e_snapshot')::boolean
  and (j->'fp'->>'fn_md5') = '8bdab755ce579f860c0206805794841c' and (j->'fp'->>'policy_md5') = '01080a074cdde90d754b266ceb4bc206'
  and (j->'fp'->>'constraint_md5') = '31bba4a9678b798b2a8fef8e135e5675' and (j->'fp'->>'column_md5') = 'e87a26bffaa401f92b459d5f4aa3b046'
  and (j->'fp'->>'trigger_md5') = 'b1507cb9c9baead680593549491bb127' and (j->'fp'->>'table_acl_md5') = 'dfa96ba71e52e4280c068334b514404b'
  and (j->'fp'->>'policy_count')::int = 97 and (j->'fp'->>'fn_count')::int = 73
  and (j->'fp'->'data'->>'questions') = '131:8993adb8a0d2be6beaaf1c4c3da0b0d5' and (j->'fp'->'data'->>'exam_attempts') = '2:f35ef12c6b8c1df065eb68ac45c75d21'
  and (j->'fp'->'data'->>'certificates') = '0:d41d8cd98f00b204e9800998ecf8427e',
  'courses_changed', (select changed from cd),
  'tables_changed_vs_backup', (select names from dd),
  'snapshot', (select json_object_agg(kind, n) from (select kind, count(*) n from backup.security_pre005e group by kind) s),
  'v', j)::text as verify_005e from v;
