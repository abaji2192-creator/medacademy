import { mk, CHAIN } from './lib005e.mjs'; import fs from 'fs';
const chain = CHAIN.filter(f => !f.startsWith('tests/'));
const files = process.argv.slice(2);
for (const f of files) {
  const db = await mk(['staging/005e_00_backup.sql', 'migrations/005e_medical_review_authorization.sql', 'migrations/006a_audit_hardening.sql', 'migrations/006b_course_delete_hardening.sql', 'migrations/007a_learning_progress.sql', 'migrations/007b_learning_path_assignments.sql', 'migrations/007c_skills_competency.sql', 'migrations/007d_in_app_notifications.sql'], chain);
  try { const r = await db.exec(fs.readFileSync('/home/claude/medacademy/site/backend/production/' + f, 'utf8'));
    const last = r.filter(x => x.rows?.length).at(-1); const v = Object.values(last.rows[0])[0]; const s = String(v);
    const m = s.match(/"total"\s*:\s*(\d+).*?"pass"\s*:\s*(\d+).*?"fail"\s*:\s*(\d+)/s); console.log(f, m ? m.slice(1).join('/') : s.slice(0, 200));
  } catch (e) { console.log(f, 'ERROR', e.message.slice(0, 200)); }
}
