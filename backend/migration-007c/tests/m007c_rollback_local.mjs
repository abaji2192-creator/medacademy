// 007c rollback/recovery lokal: (… 007a) fp0 → 007c apply → fp1 → rollback → fp2 (= fp0) → reapply (2x) → testlar → residue → rollback → reapply
import { mk, B } from './lib005e.mjs';
import fs from 'fs';
const R = []; const ok = (id, name, pass, info = '') => R.push({ id, name, pass, info });
const db = await mk(['staging/005e_00_backup.sql', 'migrations/005e_medical_review_authorization.sql', 'migrations/006a_audit_hardening.sql', 'migrations/006b_course_delete_hardening.sql', 'migrations/007a_learning_progress.sql', 'migrations/007b_learning_path_assignments.sql']);
const FP = fs.readFileSync(B + 'staging/007a_01_fingerprint.sql', 'utf8');
// 007c ruxsat bog'lanishlari (role_permissions) audit_row trigger'i orqali audit_logs'ga yoziladi (kutilgan, qo'shimcha).
// Shuning uchun audit_logs fingerprint'dan alohida chiqariladi va ALOHIDA tekshiriladi: faqat role_permissions yozuvlari qo'shiladi, mavjudlari o'zgarmaydi.
const fp = async () => { const o = JSON.parse((await db.query(FP)).rows[0].fingerprint_007a); delete o.at; delete o.project_marker; delete o.counts.audit_logs; delete o.data_md5.audit_logs; return o; };
const audit0 = async () => (await db.query(`select md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) m, count(*)::int n from public.audit_logs x where x.created_at < '2000-01-01' or x.id in (select id from public.audit_logs order by id limit 0)`)).rows[0];
const run = async f => db.exec(fs.readFileSync(B + f, 'utf8'));
const suite = async () => { const sets = (await db.exec(fs.readFileSync(B + 'staging/007c_02_tests.sql', 'utf8'))).filter(x => x.fields.length); return sets[sets.length - 2].rows[0].line; };
const A0 = (await db.query(`select coalesce(max(id), 0) mx, count(*)::int n, md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) m from public.audit_logs x`)).rows[0];
const fp0 = await fp();
await run('migrations/007c_skills_competency.sql'); const fp1 = await fp();
ok('D01', 'apply: biznes ma\'lumoti o\'zgarmagan', JSON.stringify(fp1.data_md5) === JSON.stringify(fp0.data_md5) && JSON.stringify(fp1.counts) === JSON.stringify(fp0.counts));
ok('D02', 'apply: mavjud policy\'lar + 1 (3 ta 007c policy)', fp1.policies === fp0.policies + 3, fp1.policies + ' vs ' + fp0.policies);
ok('D03', 'apply: anon EXECUTE faqat verify_certificate', fp1.anon_exec === 'verify_certificate', fp1.anon_exec);
ok('D04', 'apply: jadval +1, CASCADE 0', fp1.tables === fp0.tables + 3 && fp1.cascade_fk === 0);
await run('migrations/007c_rollback.sql'); const fp2 = await fp();
for (const k of Object.keys(fp0)) ok('D1' + k.slice(0, 8), 'rollback: ' + k + ' = 007c\'dan oldingi holat', JSON.stringify(fp2[k]) === JSON.stringify(fp0[k]));
await run('migrations/007c_skills_competency.sql'); await run('migrations/007c_skills_competency.sql'); const fp3 = await fp();
ok('D20', 'reapply (2x): holat = birinchi apply', JSON.stringify(fp3) === JSON.stringify(fp1));
const s = await suite(); ok('D21', 'reapply → 007c test to\'plami', / FAIL 0/.test(s), s);
const fp4 = await fp(); ok('D22', 'test residue 0', JSON.stringify(fp4) === JSON.stringify(fp3));
await run('migrations/007c_rollback.sql'); await run('migrations/007c_skills_competency.sql'); const fp5 = await fp();
ok('D23', 'ikkinchi rollback → reapply = birinchi apply', JSON.stringify(fp5) === JSON.stringify(fp1));
const A1 = (await db.query(`select count(*)::int n, md5(coalesce(string_agg(to_jsonb(x)::text, '' order by x.id), '')) m from public.audit_logs x where x.id <= ${A0.mx}`)).rows[0];
const extra = (await db.query(`select string_agg(distinct entity || ':' || action, ',') s from public.audit_logs where id > ${A0.mx}`)).rows[0].s;
ok('D30', 'audit: mavjud yozuvlar o\'zgarmagan; qo\'shimchalar faqat permission.granted/revoked (rol ruxsatlari)', A1.n === A0.n && A1.m === A0.m && /^(permission:permission\.(granted|revoked),?)+$/.test(extra || 'permission:permission.granted'), extra);
R.forEach(r => console.log((r.pass ? 'PASS ' : 'FAIL ') + r.id + ' ' + r.name + (r.info ? ' :: ' + r.info : '')));
console.log(`007c rollback/recovery: ${R.length} test, ${R.filter(r => !r.pass).length} FAIL`);
