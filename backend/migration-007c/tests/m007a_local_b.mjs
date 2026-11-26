// 007a lokal: prod zanjiri + 005d + 005e + 006a (2 marta, idempotentlik) → 006a test to'plami
import { mk, B } from './lib005e.mjs';
import fs from 'fs';
const extra = (process.env.NO006A ? [] : ['migrations/006a_audit_hardening.sql', 'migrations/006b_course_delete_hardening.sql', 'migrations/007a_learning_progress.sql', 'migrations/007a_learning_progress.sql', 'migrations/007b_learning_path_assignments.sql', ...(process.env.T7C ? ['migrations/007c_skills_competency.sql'] : [])]);
const db = await mk(['staging/005e_00_backup.sql', 'migrations/005e_medical_review_authorization.sql', ...extra]);
let res; try { res = await db.exec(fs.readFileSync(B + 'staging/007a_02_tests.sql', 'utf8')); } catch (e) { console.log('ERR', e.message, '|', e.where, '|', e.internalQuery); process.exit(1); }
const sets = res.filter(x => x.fields.length);
const lines = sets[sets.length - 2].rows.map(r => r.line);
if (process.env.ALL) lines.forEach(l => console.log(l)); else lines.filter(l => l.startsWith('SUMMARY') || l.includes(' FAIL ')).forEach(l => console.log(l));
fs.writeFileSync('/home/claude/medacademy/tests/m007a_results.txt', lines.join('\n'));
