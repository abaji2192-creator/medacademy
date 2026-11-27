import { mk } from './lib005e.mjs'; import fs from 'fs';
delete process.env.T7D; delete process.env.T7E;
const db = await mk(['staging/005e_00_backup.sql', 'migrations/005e_medical_review_authorization.sql', 'migrations/006a_audit_hardening.sql', 'migrations/006b_course_delete_hardening.sql', 'migrations/007a_learning_progress.sql', 'migrations/007b_learning_path_assignments.sql', 'migrations/007c_skills_competency.sql', 'migrations/007d_in_app_notifications.sql', 'migrations/007e_compliance_matrix.sql']);
let sql = fs.readFileSync('/home/claude/medacademy/site/backend/staging/007e_03_perf.sql', 'utf8');
sql = sql.replace(/select pg_temp\.bench\([\s\S]*?\nselect jsonb_object_agg/, 'select jsonb_object_agg').replace(/rollback;\s*$/, '');
await db.exec(sql);
const oa = (await db.query(`select (v->>'org') o from perf_r where k='ctx'`)).rows[0].o;
for (const [k, q] of [['training_1000', `select count(*) from public._cmp_training_007e('${oa}', (select array_agg(id) from public.employees where org_id = '${oa}'))`],
  ['competency_1000', `select count(*) from public._sk_emp_competency_007c('${oa}', (select array_agg(id) from public.employees where org_id = '${oa}'))`]]) {
  const ts = []; for (let i = 0; i < 5; i++) { const t = performance.now(); await db.query(q); ts.push(performance.now() - t); } console.log(k, ts.map(x => x.toFixed(0)).join(','));
}
const ex = await db.query(`explain analyze select count(*) from public._cmp_training_007e('${oa}', (select array_agg(id) from public.employees where org_id = '${oa}'))`);
console.log(ex.rows.map(r => r['QUERY PLAN']).join('\n').slice(0, 600));
