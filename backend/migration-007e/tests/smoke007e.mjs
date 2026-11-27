import { mk } from './lib005e.mjs';
delete process.env.T7D;
const db = await mk(['staging/005e_00_backup.sql', 'migrations/005e_medical_review_authorization.sql', 'migrations/006a_audit_hardening.sql', 'migrations/006b_course_delete_hardening.sql', 'migrations/007a_learning_progress.sql', 'migrations/007b_learning_path_assignments.sql', 'migrations/007c_skills_competency.sql', 'migrations/007d_in_app_notifications.sql', 'migrations/007e_compliance_matrix.sql', 'migrations/007e_compliance_matrix.sql']);
const as = async (uid, q) => { await db.exec(`set role authenticated; select set_config('request.jwt.claims','{"sub":"${uid}","role":"authenticated"}',false), set_config('request.jwt.claim.sub','${uid}',false);`); try { return (await db.query(q)).rows[0]; } catch (e) { return 'ERR ' + e.message; } finally { await db.exec('reset role'); } };
console.log(JSON.stringify(await as('a0000000-0000-0000-0000-000000000006', 'select public.employee_training_compliance() t, public.employee_competency_matrix() c')).slice(0, 900));
console.log(JSON.stringify(await as('a0000000-0000-0000-0000-000000000003', 'select public.department_compliance_matrix() o')).slice(0, 900));
