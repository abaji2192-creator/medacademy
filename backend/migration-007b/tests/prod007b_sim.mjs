// Production 007b deploy simulyatsiyasi (production-like zanjir + 007a): 80 → 81 → 82 → 83 → 84 → 85 (ROLLBACK) → 84 (residue) → 89 → compare → 83 → 84
import { mk, B } from './lib005e.mjs';
import fs from 'fs';
const CH = ['supabase.sql','staging/01_prod_like_data.sql','production/01_apply_002_003.sql','production/12_apply_004.sql','production/22_apply_005.sql','staging/005d_01_backup.sql','migrations/005d_security_hardening.sql','staging/005e_00_backup.sql','migrations/005e_medical_review_authorization.sql','migrations/006a_audit_hardening.sql','migrations/006b_course_delete_hardening.sql','migrations/007a_learning_progress.sql'];
const db = await mk([], CH);
const run = async (f) => { try { const r = (await db.exec(fs.readFileSync(B + f, 'utf8'))).filter(x => x.fields.length); return String(Object.values(r[r.length - 1].rows[0] || {})[0] ?? 'no rows'); } catch (e) { await db.exec('rollback').catch(()=>{}); return 'ERROR ' + e.message; } };
const show = (k, v) => console.log(k.padEnd(14), v.length > 400 ? v.slice(0, 400) + '…' : v);
show('80 readonly', (await run('production/80_readonly_review_007b.sql')).slice(0, 120));
show('81 backup', await run('production/81_backup_pre007b.sql'));
show('82 precheck', await run('production/82_precheck_007b.sql'));
show('83 apply', await run('production/83_apply_007b.sql'));
const v1 = await run('production/84_verify_007b.sql'); show('84 verify', v1);
show('85 tests', (await run('production/85_security_tests_007b.sql')).replace(/"groups".*/, ''));
show('75 tests', (await run('production/75_security_tests_007a.sql')).replace(/"groups".*/, ''));
show('65 tests', (await run('production/65_security_tests_006a.sql')).replace(/"groups".*/, ''));
console.log('residue0:', v1 === await run('production/84_verify_007b.sql'));
show('89 rollback', await run('production/89_rollback_007b.sql'));
show('compare', await run('staging/007b_04_compare_pre.sql'));
await run('production/83_apply_007b.sql'); console.log('reapply verify == first:', v1 === await run('production/84_verify_007b.sql'));
