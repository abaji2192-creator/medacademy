import { mk } from './lib005e.mjs'; import fs from 'fs';
const db = await mk(['staging/005e_00_backup.sql', 'migrations/005e_medical_review_authorization.sql', 'migrations/006a_audit_hardening.sql', 'migrations/006b_course_delete_hardening.sql', 'migrations/007a_learning_progress.sql', 'migrations/007b_learning_path_assignments.sql', 'migrations/007c_skills_competency.sql']);
const r = await db.exec(fs.readFileSync('/home/claude/medacademy/site/backend/staging/007c_03_perf.sql', 'utf8'));
console.log(r.find(x => x.rows?.[0]?.perf_007c).rows[0].perf_007c);
console.log((await db.query(`select (select count(*) from public.skills) + (select count(*) from public.skill_assessments) + (select count(*) from public.employees where employee_code like 'P7C_%') residue`)).rows[0]);
