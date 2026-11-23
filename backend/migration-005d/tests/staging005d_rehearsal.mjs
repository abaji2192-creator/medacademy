// Staging skriptlarining lokal mashqi: backup → verify(ORIGINAL) → apply → verify(HARDENED) → tests → rollback → verify(ORIGINAL) → apply → tests → verify
import { PGlite } from '/tmp/pgt/node_modules/@electric-sql/pglite/dist/index.js';
import fs from 'fs';
const B = '/home/claude/medacademy/site/backend/'; const db = new PGlite();
await db.exec(`create role anon nologin; create role authenticated nologin; create role authenticator nologin; create role service_role nologin bypassrls; grant anon, authenticated to authenticator;
create schema auth; create table auth.users (id uuid primary key, instance_id uuid, aud text, role text, email text, raw_user_meta_data jsonb, created_at timestamptz, updated_at timestamptz);
create function auth.uid() returns uuid language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claim.sub', true),''), (nullif(current_setting('request.jwt.claims', true),'')::jsonb ->> 'sub'))::uuid $$;
grant usage on schema auth to authenticated, anon; grant execute on function auth.uid() to authenticated, anon;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;`);

// Supabase'ning o'z event trigger funksiyasi (rls_auto_enable) — production/staging'da mavjud
await db.exec(`create or replace function public.rls_auto_enable() returns event_trigger language plpgsql security definer as $$ declare cmd record; begin
  for cmd in select * from pg_event_trigger_ddl_commands() where command_tag in ('CREATE TABLE','CREATE TABLE AS','SELECT INTO') and object_type in ('table','partitioned table') loop
    if cmd.schema_name = 'public' then execute format('alter table %s enable row level security', cmd.object_identity); end if; end loop; end $$;
  create event trigger ensure_rls on ddl_command_end execute function public.rls_auto_enable();`);
const last = r => r.filter(x => x.fields.length).pop();
const run = async (f, label) => { const r = await db.exec(fs.readFileSync(B + f, 'utf8')); const t = last(r); if (label) { console.log('==', label, f);
  if (t && t.rows.length && t.rows[0].result !== undefined) { const fails = t.rows.filter(x => x.result !== 'PASS'); console.log(`   ${t.rows.length} test, ${fails.length} FAIL`); fails.forEach(x => console.log('   FAIL', x.id, x.test, '|', x.expected, '|', x.actual)); }
  else t && t.rows.forEach(x => console.log('  ', JSON.stringify(x))); } return t; };
for (const f of ['supabase.sql','staging/01_prod_like_data.sql','production/01_apply_002_003.sql','production/12_apply_004.sql','production/22_apply_005.sql']) await run(f);
await run('staging/005d_01_backup.sql', 'BACKUP');
await run('staging/005d_03_verify.sql', 'VERIFY (pre)');
await run('migrations/005d_security_hardening.sql', 'APPLY');
await run('staging/005d_03_verify.sql', 'VERIFY (hardened)');
await run('staging/005d_04_tests.sql', 'TESTS #1');
await run('staging/005d_03_verify.sql', 'VERIFY (after tests — rollback qilingan bo\'lishi kerak)');
await run('migrations/005d_rollback.sql', 'ROLLBACK');
await run('staging/005d_03_verify.sql', 'VERIFY (after rollback)');
await run('migrations/005d_security_hardening.sql', 'RE-APPLY (recovery)');
await run('staging/005d_04_tests.sql', 'TESTS #2');
await run('staging/005d_03_verify.sql', 'VERIFY (final)');
