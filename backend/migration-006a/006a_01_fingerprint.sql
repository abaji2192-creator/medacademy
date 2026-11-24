-- 006a: sxema / RLS / funksiya / huquq / trigger / ma'lumot barmoq izi (FAQAT SELECT). Bitta qatorli JSON.
-- Rollback'dan keyin 006a'dan oldingi holat bilan solishtirish uchun: 006a rollback'da ataylab SAQLANADIGAN obyektlar
-- (attempt_reset_events jadvali, policy'si, trigger'lari va audit_logs_immutable() funksiyasi) hisobga olinmaydi.
select json_build_object(
  'migrations', (select string_agg(version, ',' order by version) from public.schema_migrations),
  'fn_md5', (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(p.prosrc) || ':' || coalesce(p.proacl::text, '-') || ':' || p.prosecdef, '|' order by p.oid::regprocedure::text))
             from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and p.proname <> 'audit_logs_immutable'),
  'anon_exec', (select string_agg(p.proname, ',' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute')),
  'policy_md5', (select md5(string_agg(tablename || '.' || policyname || ':' || cmd || ':' || roles::text || ':' || coalesce(qual, '-') || ':' || coalesce(with_check, '-'), '|' order by tablename, policyname))
                 from pg_policies where schemaname = 'public' and tablename <> 'attempt_reset_events'),
  'rls_tables', (select string_agg(c.relname, ',' order by c.relname) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relrowsecurity and c.relname <> 'attempt_reset_events'),
  'trigger_md5', (select md5(string_agg(c.relname || '.' || t.tgname || ':' || t.tgtype || ':' || p.proname, '|' order by c.relname, t.tgname))
                  from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_proc p on p.oid = t.tgfoid
                  where not t.tgisinternal and c.relnamespace = 'public'::regnamespace and c.relname <> 'attempt_reset_events'),
  'table_grant_md5', (select md5(string_agg(table_name || ':' || grantee || ':' || privilege_type, '|' order by table_name, grantee, privilege_type))
                      from information_schema.role_table_grants where table_schema = 'public' and grantee in ('anon','authenticated') and table_name <> 'attempt_reset_events'),
  'audit_seq_priv', (select string_agg(r || ':' || pr, ',' order by r, pr) from unnest(array['anon','authenticated']) r, unnest(array['USAGE','SELECT','UPDATE']) pr
                     where exists (select 1 from pg_roles where rolname = r) and has_sequence_privilege(r, 'public.audit_logs_id_seq', pr)),
  'data_md5', json_build_object(
    'questions', (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.questions x),
    'courses', (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.courses x),
    'exam_configs', (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.course_id, x.org_id), '')) from public.exam_configs x),
    'exam_attempts', (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.exam_attempts x),
    'certificates', (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.certificates x),
    'attempt_resets', (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.user_id, x.course_id), '')) from public.attempt_resets x),
    'profiles', (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.profiles x),
    'docs', (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.collection, x.id), '')) from public.docs x),
    'question_reviews', (select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) from public.question_reviews x),
    'role_permissions', (select md5(coalesce(string_agg(x.org_id || x.role || x.permission_key, '' order by x.org_id, x.role, x.permission_key), '')) from public.role_permissions x)),
  'audit_logs', (select count(*) from public.audit_logs)
)::text as fingerprint_006a;
