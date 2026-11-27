-- Phase 3 Frontend STEP 3 — staging / production backend READ-ONLY baseline (yozish yo'q).
begin;
set transaction read only;
select jsonb_build_object(
  'migrations', (select jsonb_object_agg(v, (select count(*) from public.schema_migrations where version = v)) from unnest(array['007a','007b','007c','007d','007e']) v),
  'last', (select max(version) from public.schema_migrations),
  'tables', (select count(*) from pg_tables where schemaname = 'public'),
  'functions', (select count(*) from pg_proc where pronamespace = 'public'::regnamespace),
  'triggers', (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'public'::regnamespace and not t.tgisinternal),
  'policies', (select count(*) from pg_policies where schemaname = 'public'),
  'indexes', (select count(*) from pg_indexes where schemaname = 'public'),
  'cascade', (select count(*) from pg_constraint where contype = 'f' and confdeltype = 'c' and connamespace = 'public'::regnamespace),
  'anon_exec', (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and has_function_privilege('anon', oid, 'execute'))) as baseline;
rollback;
