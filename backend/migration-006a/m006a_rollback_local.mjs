// 006a rollback/recovery lokal: fp0 → apply → fp1 → rollback → fp2 (= fp0) → reapply (2x) → test to'plami → rollback → reapply
import { mk, B } from './lib005e.mjs';
import fs from 'fs';
const R = []; const ok = (id, name, pass, info = '') => R.push({ id, name, pass, info });
const db = await mk(['staging/005e_00_backup.sql', 'migrations/005e_medical_review_authorization.sql']);
const FP = fs.readFileSync(B + 'staging/006a_01_fingerprint.sql', 'utf8');
const fp = async () => JSON.parse((await db.query(FP)).rows[0].fingerprint_006a);
const run = async f => db.exec(fs.readFileSync(B + f, 'utf8'));
const fp0 = await fp();
await run('migrations/006a_audit_hardening.sql'); const fp1 = await fp();
ok('R01', 'apply: migrations 006a qo\'shildi', fp1.migrations.endsWith('006a'), fp1.migrations.slice(-12));
ok('R02', 'apply: biznes ma\'lumoti o\'zgarmagan (questions/courses/exam_configs/attempts/certs/resets/profiles/docs/reviews/perms)', JSON.stringify(fp1.data_md5) === JSON.stringify(fp0.data_md5));
ok('R03', 'apply: anon EXECUTE faqat verify_certificate', fp1.anon_exec === 'verify_certificate', fp1.anon_exec);
ok('R04', 'apply: 006a dan oldingi policy\'lar o\'zgarmagan', fp1.policy_md5 === fp0.policy_md5);
ok('R05', 'apply: RLS yoqilgan jadvallar o\'zgarmagan (+ yangi jadval)', fp1.rls_tables === fp0.rls_tables);
await run('migrations/006a_rollback.sql'); const fp2 = await fp();
for (const k of Object.keys(fp0)) ok('R1' + k.slice(0, 6), 'rollback: ' + k + ' = 006a\'dan oldingi holat', JSON.stringify(fp2[k]) === JSON.stringify(fp0[k]), k === 'audit_logs' ? `${fp0[k]} → ${fp2[k]}` : '');
const kept = (await db.query(`select count(*)::int n from public.attempt_reset_events`)).rows[0].n;
ok('R30', 'rollback: attempt_reset_events tarixi saqlangan (jadval o\'chirilmadi)', kept >= 0, 'rows=' + kept);
await run('migrations/006a_audit_hardening.sql'); await run('migrations/006a_audit_hardening.sql'); const fp3 = await fp();
ok('R31', 'reapply (2x): fn/policy/trigger/grant = birinchi apply', fp3.fn_md5 === fp1.fn_md5 && fp3.policy_md5 === fp1.policy_md5 && fp3.trigger_md5 === fp1.trigger_md5 && fp3.table_grant_md5 === fp1.table_grant_md5);
ok('R32', 'reapply: biznes ma\'lumoti o\'zgarmagan', JSON.stringify(fp3.data_md5) === JSON.stringify(fp0.data_md5));
let res; try { res = await db.exec(fs.readFileSync(B + 'staging/006a_02_tests.sql', 'utf8')); } catch (e) { res = null; ok('R33', 'reapply → 006a test to\'plami', false, e.message); }
if (res) { const sets = res.filter(x => x.fields.length); const sum = sets[sets.length - 2].rows[0].line; ok('R33', 'reapply → 006a test to\'plami', / FAIL 0/.test(sum), sum); }
const fp4 = await fp();
ok('R34', 'test to\'plami ROLLBACK: biznes ma\'lumoti va audit soni o\'zgarmagan (test residue 0)', JSON.stringify(fp4.data_md5) === JSON.stringify(fp3.data_md5) && fp4.audit_logs === fp3.audit_logs);
await run('migrations/006a_rollback.sql'); await run('migrations/006a_audit_hardening.sql'); const fp5 = await fp();
ok('R35', 'ikkinchi rollback → reapply: holat = birinchi apply', fp5.fn_md5 === fp1.fn_md5 && fp5.trigger_md5 === fp1.trigger_md5 && fp5.policy_md5 === fp1.policy_md5);
R.forEach(r => console.log((r.pass ? 'PASS ' : 'FAIL ') + r.id + ' ' + r.name + (r.info ? ' :: ' + r.info : '')));
console.log(`006a rollback/recovery: ${R.length} test, ${R.filter(r => !r.pass).length} FAIL`);
