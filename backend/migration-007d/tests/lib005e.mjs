import { PGlite } from '/tmp/pgt/node_modules/@electric-sql/pglite/dist/index.js';
import fs from 'fs';
export const B = '/home/claude/medacademy/site/backend/';
export const PRE = fs.readFileSync('/home/claude/medacademy/tests/role_matrix_local.mjs','utf8').match(/await db\.exec\(`([\s\S]*?)`\);/)[1];
export const CHAIN = ['supabase.sql','staging/01_prod_like_data.sql','production/01_apply_002_003.sql','production/12_apply_004.sql','production/22_apply_005.sql','tests/004_test_setup.sql','tests/005_test_setup.sql','staging/005d_01_backup.sql','migrations/005d_security_hardening.sql'];
export async function mk(extra = [], chain = CHAIN) { const db = new PGlite(); await db.exec(PRE); if (process.env.T7D && extra.includes('migrations/007c_skills_competency.sql') && !extra.includes('migrations/007d_in_app_notifications.sql')) extra = [...extra, 'migrations/007d_in_app_notifications.sql']; for (const f of [...chain, ...extra]) { try { await db.exec(fs.readFileSync(B+f,'utf8')); } catch (e) { throw new Error(f + ': ' + e.message + ' ' + (e.where||'')); } } return db; }
export const last = r => r.filter(x => x.fields.length).pop();
