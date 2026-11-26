import { mk } from './lib005e.mjs';
const base = ['staging/005e_00_backup.sql', 'migrations/005e_medical_review_authorization.sql', 'migrations/006a_audit_hardening.sql', 'migrations/006b_course_delete_hardening.sql', 'migrations/007a_learning_progress.sql', 'migrations/007b_learning_path_assignments.sql'];
const db = await mk([...base, 'staging/007c_00_backup.sql', 'production/94_verify_007c.sql'.replace('94_verify_007c', '93_apply_007c')]);
import fs from 'fs';
const r = await db.query(fs.readFileSync('/home/claude/medacademy/site/backend/production/94_verify_007c.sql', 'utf8'));
console.log((Array.isArray(r) ? r.at(-1) : r).rows[0].verify_007c);
const r2 = await db.query(fs.readFileSync('/home/claude/medacademy/site/backend/staging/007c_04_compare_pre.sql', 'utf8'));
console.log((Array.isArray(r2) ? r2.at(-1) : r2).rows[0].compare_pre007c);
