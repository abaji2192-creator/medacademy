// Berilgan staging/production SQL test faylini (ROLLBACK) lokal zanjir + 005d + (ixtiyoriy) 005e ustida ishga tushiradi
import { mk, B } from './lib005e.mjs';
import fs from 'fs';
const [file, with5e] = [process.argv[2], process.argv[3] !== 'no5e'];
const db = await mk(with5e ? ['migrations/005e_medical_review_authorization.sql', ...(process.env.T6A ? ['migrations/006a_audit_hardening.sql', ...(process.env.T6B ? ['migrations/006b_course_delete_hardening.sql', ...(process.env.T7A ? ['migrations/007a_learning_progress.sql', ...(process.env.T7B ? ['migrations/007b_learning_path_assignments.sql', ...(process.env.T7C ? ['migrations/007c_skills_competency.sql'] : [])] : [])] : [])] : [])] : [])] : []);
try { const r = (await db.exec(fs.readFileSync(B + file, 'utf8'))).filter(x => x.fields.length);
  for (const set of r.slice(-2)) for (const row of set.rows) { const v = Object.values(row)[0]; const s = String(v); if (/SUMMARY|FAIL|"fail"|total|pass/i.test(s) || set.rows.length < 3) console.log(s.slice(0, 600)); }
} catch (e) { console.log('ERR', e.message, e.where || ''); }
