// Production 006 paketi simulyatsiyasi (lokal PGlite, production-like zanjir + 005e): backup → precheck → apply 006a/006b → verify → rollback → precheck
import { mk, B } from './lib005e.mjs';
import fs from 'fs';
const db = await mk(['staging/005e_00_backup.sql', 'migrations/005e_medical_review_authorization.sql']);
const run = async f => { const r = (await db.exec(fs.readFileSync(B + f, 'utf8'))).filter(x => x.fields.length); return r.length ? Object.values(r[r.length - 1].rows[0])[0] : null; };
const j = s => JSON.parse(s);
const out = {};
out.backup = j(await run('production/60_backup_pre006.sql'));
out.precheck = j(await run('production/61_precheck_006.sql'));
out.apply6a = j(await run('production/62_apply_006a.sql'));
out.apply6b = j(await run('production/63_apply_006b.sql'));
out.verify = j(await run('production/64_verify_006.sql'));
await run('migrations/006b_rollback.sql'); await run('migrations/006a_rollback.sql');
out.precheck_after_rollback = j(await run('production/61_precheck_006.sql'));
const pick = (o, ks) => Object.fromEntries(ks.map(k => [k, o[k]]));
console.log(JSON.stringify({
  backup: pick(out.backup, ['tables_backed_up', 'tables_identical', 'mismatched']),
  precheck: pick(out.precheck, ['m005e', 'm006a', 'm006b', 'anon_exec', 'reception_domain', 'mr_publish', 'fk_cascade', 'reset_events_exists', 'snapshot_006a_exists', 'triggers_006', 'backup_tables', 'public_tables', 'fn_md5', 'policy_md5']),
  apply6a: out.apply6a.migration, apply6b: out.apply6b.migration,
  verify: pick(out.verify, ['migrations', 'triggers_006', 'audit_client_write', 'policies', 'policies_before', 'reset_events', 'attempt_resets', 'eligibility_rpc_authenticated', 'eligibility_rpc_anon', 'anon_exec', 'fk_cascade']),
  verify_ok_except_counts: out.verify.migrations === 3 && out.verify.triggers_006 === 13 && out.verify.audit_client_write === 0 && out.verify.policies === out.verify.policies_before + 1,
  after_rollback: pick(out.precheck_after_rollback, ['m006a', 'm006b', 'fn_md5', 'policy_md5', 'triggers_006', 'snapshot_006a_exists', 'reset_events_exists']),
  rollback_restores_fn_policy: out.precheck_after_rollback.fn_md5 === out.precheck.fn_md5 && out.precheck_after_rollback.policy_md5 === out.precheck.policy_md5 }, null, 1));
