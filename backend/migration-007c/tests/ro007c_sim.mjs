import { mk } from './lib005e.mjs'; import fs from 'fs';
const db = await mk(['staging/005e_00_backup.sql', 'migrations/005e_medical_review_authorization.sql', 'migrations/006a_audit_hardening.sql', 'migrations/006b_course_delete_hardening.sql', 'migrations/007a_learning_progress.sql', 'migrations/007b_learning_path_assignments.sql']);
const r = await db.exec(fs.readFileSync('/home/claude/medacademy/site/backend/production/90_readonly_review_007c.sql', 'utf8'));
console.log(r.find(x => x.rows?.[0]?.prod_readonly_007c).rows[0].prod_readonly_007c);
