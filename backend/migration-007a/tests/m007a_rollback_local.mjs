// 007a rollback/recovery lokal: (005e+006a+006b) fp0 → 007a apply → fp1 → rollback → fp2 (= fp0) → reapply (2x) → testlar → rollback → reapply
import { mk, B } from './lib005e.mjs';
import fs from 'fs';
const R = []; const ok = (id, name, pass, info = '') => R.push({ id, name, pass, info });
const db = await mk(['staging/005e_00_backup.sql', 'migrations/005e_medical_review_authorization.sql', 'migrations/006a_audit_hardening.sql', 'migrations/006b_course_delete_hardening.sql']);
const FP = fs.readFileSync(B + 'staging/006a_01_fingerprint.sql', 'utf8');
const SCH = `select json_build_object(
  'cols', (select md5(string_agg(table_name||'.'||column_name||':'||data_type||':'||is_nullable||':'||coalesce(column_default,'-'), '|' order by table_name, column_name)) from information_schema.columns where table_schema='public'),
  'fns', (select md5(string_agg(p.oid::regprocedure::text||':'||md5(pg_get_functiondef(p.oid)), '|' order by 1)) from pg_proc p where p.pronamespace='public'::regnamespace and p.prokind='f'),
  'idx', (select md5(string_agg(indexdef, '|' order by indexname)) from pg_indexes where schemaname='public'),
  'trg', (select md5(string_agg(tgrelid::regclass||'.'||tgname, '|' order by 1)) from pg_trigger where not tgisinternal),
  'fcat', (select md5(coalesce(string_agg(name||':'||category, '|' order by name), '')) from backup.function_categories_005d),
  'lessons_data', (select md5(coalesce(string_agg(to_jsonb(l)::text, '' order by id), '')) from (select id, module_id, title, status, order_index from public.lessons) l),
  'assign_data', (select md5(coalesce(string_agg(to_jsonb(a)::text, '' order by id), '')) from public.course_assignments a))::text j`;
const fp = async () => ({ ...JSON.parse((await db.query(FP)).rows[0].fingerprint_006a), ...JSON.parse((await db.query(SCH)).rows[0].j) });
const run = async f => db.exec(fs.readFileSync(B + f, 'utf8'));
const suite = async () => { const sets = (await db.exec(fs.readFileSync(B + 'staging/007a_02_tests.sql', 'utf8'))).filter(x => x.fields.length); return sets[sets.length - 2].rows[0].line; };
const strip = o => { const { fns, cols, idx, trg, fcat, migrations, anon_exec, ...rest } = o; return rest; };
const fp0 = await fp();
await run('migrations/007a_learning_progress.sql'); const fp1 = await fp();
ok('C01', 'apply: biznes ma\'lumoti o\'zgarmagan', JSON.stringify(fp1.data_md5) === JSON.stringify(fp0.data_md5));
ok('C02', 'apply: RLS policy\'lari o\'zgarmagan', fp1.policy_md5 === fp0.policy_md5);
ok('C03', 'apply: table grant\'lar o\'zgarmagan', fp1.table_grant_md5 === fp0.table_grant_md5);
ok('C04', 'apply: anon EXECUTE faqat verify_certificate', fp1.anon_exec === 'verify_certificate', fp1.anon_exec);
ok('C05', 'apply: mavjud darslar/tayinlashlar qatorlari o\'zgarmagan', fp1.lessons_data === fp0.lessons_data && fp1.assign_data === fp0.assign_data);
ok('C06', 'apply: barcha mavjud darslar is_required = true', (await db.query(`select count(*) filter (where not is_required)::int n from public.lessons`)).rows[0].n === 0);
await run('migrations/007a_rollback.sql'); const fp2 = await fp();
for (const k of Object.keys(fp0)) ok('C1' + k.slice(0, 8), 'rollback: ' + k + ' = 007a\'dan oldingi holat', JSON.stringify(fp2[k]) === JSON.stringify(fp0[k]));
await run('migrations/007a_learning_progress.sql'); await run('migrations/007a_learning_progress.sql'); const fp3 = await fp();
ok('C20', 'reapply (2x): holat = birinchi apply', JSON.stringify(fp3) === JSON.stringify(fp1));
const s = await suite(); ok('C21', 'reapply → 007a test to\'plami', / FAIL 0/.test(s), s);
const fp4 = await fp(); ok('C22', 'test residue 0 (fingerprint o\'zgarmagan)', JSON.stringify(fp4) === JSON.stringify(fp3));
await run('migrations/007a_rollback.sql'); await run('migrations/007a_learning_progress.sql'); const fp5 = await fp();
ok('C23', 'ikkinchi rollback → reapply = birinchi apply', JSON.stringify(fp5) === JSON.stringify(fp1));
R.forEach(r => console.log((r.pass ? 'PASS ' : 'FAIL ') + r.id + ' ' + r.name + (r.info ? ' :: ' + r.info : '')));
console.log(`007a rollback/recovery: ${R.length} test, ${R.filter(r => !r.pass).length} FAIL`);
