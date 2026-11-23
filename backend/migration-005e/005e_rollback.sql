-- FAQAT REAL INCIDENT UCHUN: Migration 005e ni bekor qilish — backup.security_pre005e snapshot'idan.
-- NON-DESTRUCTIVE: savol, review, evidence, urinish, sertifikat qatorlari o'chirilmaydi / o'zgarmaydi.
-- Tiklanadi: guard_question_review, question_review_effects, question_workflow, _q_exam_eligible, seed_org_defaults_005,
--            guard_question_evidence, guard_evidence_source (aynan ta'rif),
--            question_reviews RLS policy'lari, medical_reviewer → question.publish biriktiruvlari.
-- Olib tashlanadi: medical.review ruxsat biriktiruvlari va kaliti, role_permissions_005e_chk, _q_latest_review(), indeks.
-- question_reviews.reviewer_role_at_creation / review_seq ustunlari: agar 005e davrida birorta review yozilmagan bo'lsa
--   (reviewer_role_at_creation hammasi NULL) — olib tashlanadi (aniq tiklanish); aks holda tarixiy metadata sifatida SAQLANADI.

begin;

do $$ begin
  if to_regclass('backup.security_pre005e') is null then raise exception '005e snapshot (backup.security_pre005e) topilmadi — rollback qilinmaydi'; end if;
  if (select count(*) from backup.security_pre005e where kind = 'fn_def') <> 7 then raise exception '005e snapshot to''liq emas (fn_def <> 7)'; end if;
end $$;

-- 1. Funksiyalar: snapshot'dagi aynan ta'rif (CREATE OR REPLACE — huquqlar saqlanadi)
do $$ declare r record; begin
  for r in select name, detail from backup.security_pre005e where kind = 'fn_def' order by name loop
    execute r.detail;
  end loop;
end $$;

-- 2. question_reviews RLS policy'lari: snapshot'dagi aynan ifoda
do $$ declare r record; j json; v_roles text; begin
  for r in select name, detail, extra from backup.security_pre005e where kind = 'policy' loop
    j := r.extra::json;
    select string_agg(quote_ident(x), ', ') into v_roles from json_array_elements_text(j -> 'roles') x;
    execute format('drop policy if exists %I on public.question_reviews', r.name);
    execute format('create policy %I on public.question_reviews as %s for %s to %s%s%s', r.name, j ->> 'permissive', r.detail, v_roles,
                   case when j ->> 'qual' is not null then ' using (' || (j ->> 'qual') || ')' else '' end,
                   case when j ->> 'with_check' is not null then ' with check (' || (j ->> 'with_check') || ')' else '' end);
  end loop;
end $$;

-- 3. Ruxsatlar
alter table public.role_permissions drop constraint if exists role_permissions_005e_chk;
delete from public.role_permissions where permission_key = 'medical.review';
insert into public.role_permissions (org_id, role, permission_key)
  select s.extra::uuid, s.name, s.detail from backup.security_pre005e s where s.kind = 'role_perm'
on conflict do nothing;
delete from public.permissions where key = 'medical.review' and not exists (select 1 from public.role_permissions where permission_key = 'medical.review');

-- 4. Yordamchi funksiya va indeks
drop function if exists public._q_latest_review(text, int, text);
do $$ begin if to_regclass('backup.function_categories_005d') is not null then delete from backup.function_categories_005d where name = '_q_latest_review'; end if; end $$;
drop index if exists public.question_reviews_latest_idx;

-- 5. Ustunlar: faqat 005e davrida review yozilmagan bo'lsa
do $$ begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'question_reviews' and column_name = 'reviewer_role_at_creation') then
    if exists (select 1 from public.question_reviews where reviewer_role_at_creation is not null) then
      raise notice '005e rollback: % ta review tarixiy rol bilan yozilgan — reviewer_role_at_creation / review_seq SAQLANDI (inert metadata)',
        (select count(*) from public.question_reviews where reviewer_role_at_creation is not null);
    else
      alter table public.question_reviews drop constraint if exists question_reviews_reviewer_role_chk;
      alter table public.question_reviews drop column if exists review_seq;
      alter table public.question_reviews drop column if exists reviewer_role_at_creation;
    end if;
  end if;
end $$;

insert into public.schema_migrations (version, description)
values ('005e-rollback-' || to_char(now(), 'YYYYMMDDHH24MISS'), 'Migration 005e rollback (snapshot backup.security_pre005e)')
on conflict (version) do nothing;
delete from public.schema_migrations where version = '005e';

commit;

select json_build_object(
  'medical_review_rows', (select count(*) from public.role_permissions where permission_key = 'medical.review'),
  'mr_publish_rows', (select count(*) from public.role_permissions where role = 'medical_reviewer' and permission_key = 'question.publish'),
  'latest_fn', to_regprocedure('public._q_latest_review(text,int,text)') is not null,
  'review_cols', (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'question_reviews' and column_name in ('reviewer_role_at_creation','review_seq')),
  'questions', (select count(*) from public.questions), 'reviews', (select count(*) from public.question_reviews),
  'attempts', (select count(*) from public.exam_attempts), 'certificates', (select count(*) from public.certificates)
)::text as result_005e_rollback;
