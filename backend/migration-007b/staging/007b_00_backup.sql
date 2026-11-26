-- STAGING: Migration 007b dan oldin to'liq backup (60_backup_pre006.sql mantig'i; nom: _pre007b). Faqat backup sxemasiga qo'shadi.
-- Qamrov: public'dagi BARCHA jadvallar (to'liq ma'lumot) + ustun / constraint / indeks / RLS policy / funksiya (ta'rif + EXECUTE huquqlari)
--         / trigger / jadval grant / default privileges snapshot'lari.
create schema if not exists backup;
revoke all on schema backup from anon, authenticated;
do $$ declare t text; begin
  if to_regclass('backup.tables_pre007b') is not null then raise exception 'pre007b backup allaqachon mavjud — qayta yozilmaydi'; end if;
  create table backup.tables_pre007b (tablename text primary key, live_rows bigint, backup_table text);
  for t in select tablename from pg_tables where schemaname = 'public' order by tablename loop
    execute format('create table backup.%I as select * from public.%I', left(t, 38) || '_pre007b', t);
    execute format('alter table backup.%I enable row level security', left(t, 38) || '_pre007b');
    execute format('insert into backup.tables_pre007b values (%L, (select count(*) from public.%I), %L)', t, t, left(t, 38) || '_pre007b');
  end loop;
end $$;
alter table backup.tables_pre007b enable row level security;

create table backup.columns_pre007b as
  select table_name, column_name, ordinal_position, data_type, is_nullable, column_default from information_schema.columns where table_schema = 'public';
create table backup.constraints_pre007b as
  select conrelid::regclass::text as tablename, conname, contype, pg_get_constraintdef(oid) as def from pg_constraint where connamespace = 'public'::regnamespace;
create table backup.indexes_pre007b as select tablename, indexname, indexdef from pg_indexes where schemaname = 'public';
create table backup.policies_pre007b as
  select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check from pg_policies where schemaname = 'public';
create table backup.functions_pre007b as
  select p.oid::regprocedure::text as signature, p.prosecdef as security_definer, pg_get_functiondef(p.oid) as def,
         has_function_privilege('anon', p.oid, 'execute') as anon_exec, has_function_privilege('authenticated', p.oid, 'execute') as auth_exec
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.prokind = 'f';
create table backup.triggers_pre007b as
  select c.relname as tablename, t.tgname, pg_get_triggerdef(t.oid) as def
    from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and not t.tgisinternal;
create table backup.grants_pre007b as
  select table_name, grantee, privilege_type from information_schema.role_table_grants where table_schema = 'public' and grantee in ('anon','authenticated');
create table backup.default_acl_pre007b as
  select d.defaclrole::regrole::text as owner_role, d.defaclobjtype as objtype, d.defaclacl::text as acl from pg_default_acl d where d.defaclnamespace = 'public'::regnamespace;
alter table backup.columns_pre007b enable row level security;
alter table backup.constraints_pre007b enable row level security;
alter table backup.indexes_pre007b enable row level security;
alter table backup.policies_pre007b enable row level security;
alter table backup.functions_pre007b enable row level security;
alter table backup.triggers_pre007b enable row level security;
alter table backup.grants_pre007b enable row level security;
alter table backup.default_acl_pre007b enable row level security;

create table backup.rls_state_pre007b as
  select c.relname as tablename, c.relrowsecurity as rls_enabled, c.relforcerowsecurity as rls_forced, c.relacl::text as acl
    from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r';
create table backup.fingerprint_pre007b as select (select json_build_object(
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
)::text) as fingerprint, now() as taken_at;
alter table backup.rls_state_pre007b enable row level security;
alter table backup.fingerprint_pre007b enable row level security;

-- Tekshiruv (bitta qator): har bir jadval uchun backup = live (soni va md5); snapshot'lar to'liq
create or replace function pg_temp.bsame(t text, b text) returns boolean language plpgsql as $$ declare x text; y text; begin
  execute format('select coalesce(md5(string_agg(md5(r::text), '''' order by md5(r::text))), ''-'') from public.%I r', t) into x;
  execute format('select coalesce(md5(string_agg(md5(r::text), '''' order by md5(r::text))), ''-'') from backup.%I r', b) into y;
  return x = y; end $$;
select json_build_object(
  'tables_backed_up', (select count(*) from backup.tables_pre007b),
  'tables_identical', (select count(*) from backup.tables_pre007b b where pg_temp.bsame(b.tablename, b.backup_table)),
  'mismatched', (select coalesce(string_agg(b.tablename, ','), '-') from backup.tables_pre007b b where not pg_temp.bsame(b.tablename, b.backup_table)),
  'total_rows', (select sum(live_rows) from backup.tables_pre007b),
  'policies', (select count(*) from backup.policies_pre007b), 'functions', (select count(*) from backup.functions_pre007b),
  'anon_exec_functions', (select count(*) from backup.functions_pre007b where anon_exec),
  'triggers', (select count(*) from backup.triggers_pre007b), 'constraints', (select count(*) from backup.constraints_pre007b),
  'default_acl_rows', (select count(*) from backup.default_acl_pre007b),
  'rls_tables', (select count(*) from backup.rls_state_pre007b), 'rls_enabled', (select count(*) from backup.rls_state_pre007b where rls_enabled),
  'fk', (select count(*) from backup.constraints_pre007b where contype = 'f'),
  'fingerprint_saved', (select count(*) from backup.fingerprint_pre007b))::text as backup_pre007b;
