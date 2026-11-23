// 005e: apply → idempotent → rollback → aniq tiklanish → qayta apply → tiklanish regressiyasi (lokal)
import { mk, B } from './lib005e.mjs';
import fs from 'fs';
const R = f => fs.readFileSync(B + f, 'utf8');
const fp = async db => JSON.parse((await db.exec(R('staging/005e_01_fingerprint.sql'))).filter(x => x.fields.length).pop().rows[0].fingerprint_005e);
const cmp = (a, b, skip = []) => { const d = []; for (const k of Object.keys(a)) { if (skip.includes(k)) continue; if (k === 'data') { for (const t of Object.keys(a.data)) if (String(a.data[t]) !== String(b.data[t])) d.push('data.' + t); } else if (String(a[k]) !== String(b[k])) d.push(k); } return d; };
const out = []; const ok = (id, name, exp, act, pass) => out.push(`${pass ? 'PASS' : 'FAIL'}  ${id} ${name} | kutilgan: ${exp} | natija: ${act}`);
const suite = async db => { const r = (await db.exec(R('staging/005e_02_tests.sql'))).filter(x => x.fields.length); return JSON.parse(r.pop().rows[0].summary_005e); };
for (const mode of ['A', 'B']) {   // A: 005e davrida review yozilmagan; B: review yozilgan (tarixiy metadata saqlanishi kerak)
  const db = await mk();
  const F0 = await fp(db);
  await db.exec(R('migrations/005e_medical_review_authorization.sql')); const F1 = await fp(db);
  await db.exec(R('migrations/005e_medical_review_authorization.sql')); const F1b = await fp(db);
  ok(mode + '01', 'Idempotent: 2-apply barmoq izi = 1-apply', '0 farq', cmp(F1, F1b).join(',') || '0 farq', cmp(F1, F1b).length === 0);
  ok(mode + '02', 'Apply: ma\'lumot (savol/review/evidence/versiya/urinish/sertifikat/profil) o\'zgarmagan', '0 farq', cmp(F0.data, F1.data).join(',') || '0 farq',
     ['questions','question_reviews','question_evidence','question_versions','evidence_sources','exam_attempts','certificates','profiles','eligible'].every(k => String(F0.data[k]) === String(F1.data[k])));
  ok(mode + '03', 'Apply: o\'zgargan sxema qismlari (kutilgan)', 'fn,policy,constraint,column,index,permissions,role_perm', cmp(F0, F1, ['data']).join(','), true);
  if (mode === 'B') { // SA medical review yozadi (tarixiy rol bilan)
    await db.exec(`select set_config('request.jwt.claims', '{"sub":"262a128c-6fb7-470e-9452-5468cd6797c0","role":"authenticated"}', false); set role authenticated;
      insert into public.question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision, internal_notes) select org_id, id, current_version, 'medical', auth.uid(), 'changes_requested', 'RB-TEST' from public.questions where course_id = 'CARDIO_BASIC' order by id limit 1;
      reset role; select set_config('request.jwt.claims', '', false);`);
  }
  const t1 = await suite(db); ok(mode + '04', '005e test to\'plami (apply holatida)', `${t1.total}/${t1.total}`, `${t1.pass}/${t1.total}`, t1.fail === 0);
  const Fpre = await fp(db);
  const rb = (await db.exec(R('migrations/005e_rollback.sql'))).filter(x => x.fields.length).pop().rows[0].result_005e_rollback;
  const F2 = await fp(db);
  const d02 = cmp(F0, F2, mode === 'B' ? ['data', 'column_md5', 'constraint_md5', 'index_md5'] : ['data']);
  ok(mode + '05', mode === 'A' ? 'Rollback: sxema/RLS/funksiya/ruxsat 005e\'dan oldingi bilan AYNAN' : 'Rollback: funksiya/RLS/ruxsat aynan; ustunlar tarixiy metadata sifatida saqlandi',
     '0 farq', d02.join(',') || '0 farq', d02.length === 0);
  if (mode === 'B') ok('B05b', 'Rollback (B): reviewer_role_at_creation / review_seq saqlandi', '2', JSON.parse(rb).review_cols, JSON.parse(rb).review_cols === 2);
  const dataKeys = ['questions','question_evidence','question_versions','evidence_sources','exam_attempts','certificates','profiles'];
  ok(mode + '06', 'Rollback: ma\'lumot o\'zgarmagan (rollback oldidagi holat bilan)', '0 farq', dataKeys.filter(k => String(Fpre.data[k]) !== String(F2.data[k])).join(',') || '0 farq', dataKeys.every(k => String(Fpre.data[k]) === String(F2.data[k])));
  ok(mode + '07', 'Rollback: review yozuvlari o\'chirilmagan', Fpre.data.question_reviews, F2.data.question_reviews, String(Fpre.data.question_reviews) === String(F2.data.question_reviews));
  ok(mode + '08', 'Rollback: medical.review qatorlari / MR question.publish tiklandi', `- / ${F0.mr_publish_rows}`, `${F2.medical_review_roles} / ${F2.mr_publish_rows}`, F2.medical_review_roles === '-' && F2.mr_publish_rows === F0.mr_publish_rows);
  // Recovery
  await db.exec(R('migrations/005e_medical_review_authorization.sql')); const F3 = await fp(db);
  const d3 = cmp(F1, F3, mode === 'B' ? ['data', 'role_perm_md5'] : ['data']);
  ok(mode + '09', 'Qayta apply: barmoq izi birinchi apply bilan bir xil', '0 farq', d3.join(',') || '0 farq', d3.length === 0);
  const t2 = await suite(db); ok(mode + '10', '005e test to\'plami (recovery holatida)', `${t2.total}/${t2.total}`, `${t2.pass}/${t2.total}`, t2.fail === 0);
}
out.forEach(l => console.log(l)); console.log('005e rollback/recovery:', out.length, 'test,', out.filter(l => l.startsWith('FAIL')).length, 'FAIL');
