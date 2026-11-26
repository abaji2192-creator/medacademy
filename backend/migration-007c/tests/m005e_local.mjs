// 005e lokal: prod zanjiri + test akkauntlari + 005d + 005e (2 marta, idempotentlik) → 005e test to'plami
import { mk, last, B } from './lib005e.mjs';
import fs from 'fs';
const db = await mk(['migrations/005e_medical_review_authorization.sql', 'migrations/005e_medical_review_authorization.sql', ...(process.env.T6A ? ['migrations/006a_audit_hardening.sql', ...(process.env.T6B ? ['migrations/006b_course_delete_hardening.sql', ...(process.env.T7A ? ['migrations/007a_learning_progress.sql', ...(process.env.T7B ? ['migrations/007b_learning_path_assignments.sql', ...(process.env.T7C ? ['migrations/007c_skills_competency.sql'] : [])] : [])] : [])] : [])] : [])]);
let res; try { res = await db.exec(fs.readFileSync(B + 'staging/005e_02_tests.sql', 'utf8')); } catch (e) { console.log('ERR', e.message, '|', e.where, '|', e.internalQuery); process.exit(1); }
const sets = res.filter(x => x.fields.length);
const lines = sets[sets.length - 2].rows.map(r => r.line);
if (process.env.ALL) lines.forEach(l => console.log(l)); else lines.filter(l => l.startsWith('SUMMARY') || l.includes(' FAIL ')).forEach(l => console.log(l));
console.log(sets[sets.length - 1].rows[0].summary_005e);
fs.writeFileSync('/home/claude/medacademy/tests/m005e_results.txt', lines.join('\n'));
