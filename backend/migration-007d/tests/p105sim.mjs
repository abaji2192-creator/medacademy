// production simulyatsiya: staging test identifikatorlarisiz (005/004 test setup yo'q) zanjir + 007c, keyin 95
delete process.env.T7D;
import { mk, CHAIN } from './lib005e.mjs'; import fs from 'fs';
const chain = CHAIN.filter(f => !f.startsWith('tests/'));
const db = await mk(['staging/005e_00_backup.sql', 'migrations/005e_medical_review_authorization.sql', 'migrations/006a_audit_hardening.sql', 'migrations/006b_course_delete_hardening.sql', 'migrations/007a_learning_progress.sql', 'migrations/007b_learning_path_assignments.sql', 'migrations/007c_skills_competency.sql', 'migrations/007d_in_app_notifications.sql'], chain);
const r = await db.exec(fs.readFileSync('/home/claude/medacademy/site/backend/production/105_security_tests_007d.sql', 'utf8'));
console.log(r.find(x => x.rows?.[0]?.summary_007d)?.rows[0].summary_007d);
console.log((await db.query(`select (select count(*) from auth.users where email like '%@test.local') u, (select count(*) from public.skills) s, (select count(*) from public.organizations) o`)).rows[0]);
