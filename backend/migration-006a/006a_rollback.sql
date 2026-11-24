-- FAQAT REAL INCIDENT UCHUN: Migration 006a ni bekor qilish.
-- NON-DESTRUCTIVE: audit_logs va attempt_reset_events qatorlari O'CHIRILMAYDI (tarix saqlanadi; jadval qoladi, faqat yozish to'xtaydi).
-- Tiklanadi: admin_reset_attempts(uuid,text) aynan ta'rifi (snapshot'dan), audit_logs huquqlari (snapshot'dan).
-- Olib tashlanadi: 006a trigger'lari va trigger funksiyalari, yangi RPC'lar (admin_set_profile_role, revoke_certificate(text,text),
--   admin_reset_attempts(uuid,text,text), question_eligibility), _audit006, schema_migrations '006a'.

begin;

do $$ begin
  if to_regclass('backup.security_pre006a') is null then raise exception '006a snapshot (backup.security_pre006a) topilmadi — rollback qilinmaydi'; end if;
  if (select count(*) from backup.security_pre006a where kind = 'fn_def') <> 1 then raise exception '006a snapshot to''liq emas (fn_def <> 1)'; end if;
end $$;

drop trigger if exists questions_audit_006a_trg on public.questions;
drop trigger if exists courses_audit_006a_trg on public.courses;
drop trigger if exists profiles_audit_006a_trg on public.profiles;
drop trigger if exists profiles_self_guard_006a_trg on public.profiles;
drop trigger if exists exam_configs_audit_006a_trg on public.exam_configs;
drop trigger if exists exam_configs_no_delete_006a_trg on public.exam_configs;
drop trigger if exists docs_no_delete_006a_trg on public.docs;
drop trigger if exists certificates_audit_006a_trg on public.certificates;
drop trigger if exists audit_logs_immutable_trg on public.audit_logs;
drop trigger if exists audit_logs_no_truncate_trg on public.audit_logs;

-- admin_reset_attempts(uuid,text): 006a'dan oldingi aynan ta'rif
do $$ declare r record; begin
  for r in select detail from backup.security_pre006a where kind = 'fn_def' loop execute r.detail; end loop;
end $$;

drop function if exists public.admin_reset_attempts(uuid, text, text);
drop function if exists public.revoke_certificate(text, text);
drop function if exists public.admin_set_profile_role(uuid, text, text);
drop function if exists public.question_eligibility(text);
drop function if exists public.audit_question_006a();
drop function if exists public.audit_course_006a();
drop function if exists public.audit_profile_006a();
drop function if exists public.guard_profile_self_006a();
drop function if exists public.audit_exam_config_006a();
drop function if exists public.guard_exam_config_delete_006a();
drop function if exists public.guard_docs_delete_006a();
drop function if exists public.audit_certificate_006a();
drop function if exists public._audit006(uuid, text, text, text, jsonb, jsonb);
-- attempt_reset_events: tarix saqlanadi; immutability trigger'i qoladi, shuning uchun audit_logs_immutable() funksiyasi ham qoladi

-- audit_logs huquqlari: snapshot'dagi holat
do $$ declare g text; s text; begin
  select detail into s from backup.security_pre006a where kind = 'grant' and name = 'audit_logs';
  if s is not null then
    foreach g in array string_to_array(s, ',') loop
      execute format('grant %s on public.audit_logs to %I', split_part(g, ':', 2), split_part(g, ':', 1));
    end loop;
  end if;
end $$;

do $$ declare g text; s text; begin
  select detail into s from backup.security_pre006a where kind = 'seqgrant' and name = 'audit_logs_id_seq';
  if s is not null then
    foreach g in array string_to_array(s, ',') loop
      execute format('grant %s on sequence public.audit_logs_id_seq to %I', split_part(g, ':', 2), split_part(g, ':', 1));
    end loop;
  end if;
end $$;

do $$ begin
  if to_regclass('backup.function_categories_005d') is not null then
    delete from backup.function_categories_005d where name in ('_audit006','audit_question_006a','audit_course_006a','audit_profile_006a',
      'guard_profile_self_006a','audit_exam_config_006a','guard_exam_config_delete_006a','guard_docs_delete_006a','audit_certificate_006a',
      'admin_set_profile_role','question_eligibility');
  end if;
end $$;

delete from public.schema_migrations where version = '006a';
commit;

select json_build_object('migration_006a', (select count(*) from public.schema_migrations where version = '006a'),
  'triggers_006a', (select count(*) from pg_trigger where tgname like '%006a%'),
  'audit_logs', (select count(*) from public.audit_logs), 'reset_events_kept', (select count(*) from public.attempt_reset_events))::text as rollback_006a;
