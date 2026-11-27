import { mk } from './lib005e.mjs'; import fs from 'fs';
delete process.env.T7D;
const P = '/home/claude/medacademy/site/backend/';
const db = await mk(['staging/005e_00_backup.sql', 'migrations/005e_medical_review_authorization.sql', 'migrations/006a_audit_hardening.sql', 'migrations/006b_course_delete_hardening.sql', 'migrations/007a_learning_progress.sql', 'migrations/007b_learning_path_assignments.sql', 'migrations/007c_skills_competency.sql', 'staging/007d_00_backup.sql', 'production/103_apply_007d.sql']);
const last = (r, k) => r.find(x => x.rows?.[0]?.[k]).rows[0][k];
console.log(last(await db.exec(fs.readFileSync(P + 'production/104_verify_007d.sql', 'utf8')), 'verify_007d'));
await db.exec(fs.readFileSync(P + 'production/109_rollback_007d.sql', 'utf8'));
console.log(last(await db.exec(fs.readFileSync(P + 'staging/007d_04_compare_pre.sql', 'utf8')), 'compare_pre007d'));
