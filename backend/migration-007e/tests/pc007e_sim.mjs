import { mk } from './lib005e.mjs'; import fs from 'fs';
delete process.env.T7D;
const db = await mk(['staging/005e_00_backup.sql', 'migrations/005e_medical_review_authorization.sql', 'migrations/006a_audit_hardening.sql', 'migrations/006b_course_delete_hardening.sql', 'migrations/007a_learning_progress.sql', 'migrations/007b_learning_path_assignments.sql', 'migrations/007c_skills_competency.sql', 'migrations/007d_in_app_notifications.sql', 'staging/007e_00_backup.sql']);
const r = await db.exec(fs.readFileSync('/home/claude/medacademy/site/backend/production/112_precheck_007e.sql', 'utf8'));
const j = JSON.parse(r.find(x => x.rows?.[0]?.precheck_007e).rows[0].precheck_007e); delete j.fn_md5; delete j.trg_md5; delete j.cols_md5; delete j.idx_md5; delete j.policy_md5; delete j.grant_md5; console.log(JSON.stringify(j));
