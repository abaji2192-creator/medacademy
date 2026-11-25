// Production 007a deploy simulyatsiyasi (test akkauntlarisiz production-like zanjir + 005e + 006a + 006b):
// 70 read-only → 71 backup → 72 precheck → 73 apply → 74 verify → 75 tests (ROLLBACK) → 74 verify (residue) → 79 rollback → compare → 73 reapply → 74
import { mk, B } from './lib005e.mjs';
import fs from 'fs';
const CH = ['supabase.sql','staging/01_prod_like_data.sql','production/01_apply_002_003.sql','production/12_apply_004.sql','production/22_apply_005.sql','staging/005d_01_backup.sql','migrations/005d_security_hardening.sql','staging/005e_00_backup.sql','migrations/005e_medical_review_authorization.sql','migrations/006a_audit_hardening.sql','migrations/006b_course_delete_hardening.sql'];
const db = await mk([], CH);
const run = async (f) => { try { const r = (await db.exec(fs.readFileSync(B + f, 'utf8'))).filter(x => x.fields.length); return String(Object.values(r[r.length - 1].rows[0] || {})[0] ?? 'no rows'); } catch (e) { await db.exec('rollback').catch(()=>{}); return 'ERROR ' + e.message; } };
const show = (k, v) => console.log(k.padEnd(22), v.length > 700 ? v.slice(0, 700) + '…' : v);
show('70 readonly', (await run('production/70_readonly_review_007a.sql')).slice(0, 160));
show('71 backup', await run('production/71_backup_pre007a.sql'));
show('72 precheck', await run('production/72_precheck_007a.sql'));
show('73 apply', await run('production/73_apply_007a.sql'));
const v1 = await run('production/74_verify_007a.sql'); show('74 verify', v1);
show('75 tests', (await run('production/75_security_tests_007a.sql')).replace(/"groups".*/, ''));
const v2 = await run('production/74_verify_007a.sql'); console.log('residue0:', v1 === v2);
show('79 rollback', await run('production/79_rollback_007a.sql'));
show('compare_pre', await run('staging/007a_04_compare_pre.sql'));
show('73 reapply', await run('production/73_apply_007a.sql'));
const v3 = await run('production/74_verify_007a.sql'); console.log('reapply verify == first:', v1 === v3);
