import { mk } from './lib005e.mjs'; import fs from 'fs';
delete process.env.T7D; delete process.env.T7E;
const db = await mk(['staging/005e_00_backup.sql', 'migrations/005e_medical_review_authorization.sql', 'migrations/006a_audit_hardening.sql', 'migrations/006b_course_delete_hardening.sql', 'migrations/007a_learning_progress.sql', 'migrations/007b_learning_path_assignments.sql', 'migrations/007c_skills_competency.sql', 'migrations/007d_in_app_notifications.sql', 'migrations/007e_compliance_matrix.sql']);
const t = Date.now();
const r = await db.exec(fs.readFileSync('/home/claude/medacademy/site/backend/staging/007e_03_perf.sql', 'utf8'));
const j = JSON.parse(r.find(x => x.rows?.[0]?.perf_007e).rows[0].perf_007e);
for (const [k, v] of Object.entries(j)) console.log(k, JSON.stringify(v));
console.log('total_s', (Date.now() - t) / 1000, (await db.query(`select (select count(*) from public.course_assignments) ca, (select count(*) from public.employees where employee_code like 'P7E_%') e`)).rows[0]);
