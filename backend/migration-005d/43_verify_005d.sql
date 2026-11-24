-- STAGING: 005d holat tekshiruvi (faqat SELECT). Apply'dan keyin ham, rollback'dan keyin ham ishlaydi.
-- state = HARDENED (005d qo'llangan) yoki ORIGINAL (005d'dan oldingi / rollback'dan keyingi holat). Ma'lumot har doim backup bilan aynan bo'lishi kerak.
create or replace function pg_temp.bsame(t text, b text) returns boolean language plpgsql as $$ declare x text; y text; begin
  execute format('select coalesce(md5(string_agg(md5(r::text), '''' order by md5(r::text))), ''-'') from public.%I r', t) into x;
  execute format('select coalesce(md5(string_agg(md5(r::text), '''' order by md5(r::text))), ''-'') from backup.%I r', b) into y;
  return x = y; end $$;
with
fk as (select count(*) filter (where confdeltype = 'c') c, count(*) filter (where confdeltype = 'r') r from pg_constraint
       where contype = 'f' and conname in ('profiles_id_fkey','docs_owner_fkey','exam_attempts_user_id_fkey','certificates_user_id_fkey','attempt_resets_user_id_fkey','exam_configs_course_id_fkey')),
fn as (select p.oid, p.oid::regprocedure::text sig, p.proname from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'),
acl_diff as (select count(*) n from fn join backup.functions_pre005d_20261123 b on b.signature = fn.sig
             where b.anon_exec <> has_function_privilege('anon', fn.oid, 'execute') or b.auth_exec <> has_function_privilege('authenticated', fn.oid, 'execute')),
cons_diff as (select count(*) n from (select conname, pg_get_constraintdef(oid) d from pg_constraint where connamespace = 'public'::regnamespace
                                      except select conname, def from backup.constraints_pre005d_20261123) x),
pol_diff as (select count(*) n from (select tablename, policyname, cmd, qual, with_check from pg_policies where schemaname = 'public'
                                     except select tablename, policyname, cmd, qual, with_check from backup.policies_pre005d_20261123) x),
data as (select count(*) filter (where not pg_temp.bsame(b.tablename, b.backup_table) and b.tablename <> 'schema_migrations') n,
                coalesce(string_agg(b.tablename, ',') filter (where not pg_temp.bsame(b.tablename, b.backup_table) and b.tablename not in ('schema_migrations')), '-') names
         from backup.tables_pre005d_20261123 b)
select to_jsonb(v)::text as info from (select
  case when (select c from fk) = 0 and (select r from fk) = 6 then 'HARDENED' when (select c from fk) = 6 then 'ORIGINAL' else 'MIXED' end as state,
  (select c from fk) as cascade_target6, (select r from fk) as restrict_target6,
  (select count(*) from pg_constraint where contype = 'f' and confdeltype = 'c' and connamespace = 'public'::regnamespace) as cascade_public_all,
  (select count(*) from fn where has_function_privilege('anon', fn.oid, 'execute')) as anon_exec,
  (select coalesce(string_agg(proname, ',' order by proname), '-') from fn where has_function_privilege('anon', fn.oid, 'execute') and (select count(*) from fn f2 where has_function_privilege('anon', f2.oid, 'execute')) < 5) as anon_exec_names,
  (select count(*) from fn where proname in ('_q_full','_q_refs','_q_public','_grade','_q_at','_cert_out','_attempt_out','_attempt_payload','_norm','_safe_date','_default_evidence_tier','guard_evidence_classification_origin_ok','is_api_request') and has_function_privilege('authenticated', fn.oid, 'execute')) as auth_internal_exec,
  (select count(*) from fn where proname in ('start_exam','save_answers','submit_exam','get_attempt_review','question_meta','admin_reset_attempts','revoke_certificate','my_org','my_role','has_perm','can_see_question','verify_certificate') and not has_function_privilege('authenticated', fn.oid, 'execute')) as auth_app_missing,
  (select count(*) from pg_trigger where tgname in ('certificates_history_guard_trg','exam_attempts_history_guard_trg')) as guard_triggers,
  (select count(*) from fn where proname = 'set_employee_status') as lifecycle_rpc,
  (select n from acl_diff) as acl_diff_vs_backup, (select n from cons_diff) as constraint_diff_vs_backup, (select n from pol_diff) as policy_diff_vs_backup,
  (select n from data) as data_tables_changed, (select names from data) as data_changed_names,
  (select count(*) from fn) as functions,
  (select string_agg(version, ',' order by version) from public.schema_migrations) as migrations) v;
