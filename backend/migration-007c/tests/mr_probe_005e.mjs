// Medical Review avtorizatsiyasi — hozirgi xatti-harakatni isbotlovchi probe'lar (lokal, prod zanjiri + 005d). Hech narsa o'zgartirmaydi (lokal xotira bazasi).
import { PGlite } from '/tmp/pgt/node_modules/@electric-sql/pglite/dist/index.js';
import fs from 'fs';
const B = '/home/claude/medacademy/site/backend/'; const db = new PGlite();
await db.exec(`create role anon nologin; create role authenticated nologin; create role authenticator nologin; create role service_role nologin bypassrls; grant anon, authenticated to authenticator;
create schema auth; create table auth.users (id uuid primary key, instance_id uuid, aud text, role text, email text, raw_user_meta_data jsonb, created_at timestamptz, updated_at timestamptz);
create function auth.uid() returns uuid language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claim.sub', true),''), (nullif(current_setting('request.jwt.claims', true),'')::jsonb ->> 'sub'))::uuid $$;
grant usage on schema auth to authenticated, anon; grant execute on function auth.uid() to authenticated, anon;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;`);
for (const f of ['supabase.sql','staging/01_prod_like_data.sql','production/01_apply_002_003.sql','production/12_apply_004.sql','production/22_apply_005.sql','migrations/005d_security_hardening.sql','tests/004_test_setup.sql','tests/005_test_setup.sql',...(process.env.T5E?['migrations/005e_medical_review_authorization.sql', ...(process.env.T6A?['migrations/006a_audit_hardening.sql', ...(process.env.T6B?['migrations/006b_course_delete_hardening.sql',...(process.env.T7A?['migrations/007a_learning_progress.sql',...(process.env.T7B?['migrations/007b_learning_path_assignments.sql',...(process.env.T7C?['migrations/007c_skills_competency.sql']:[])]:[])]:[])]:[])]:[])]:[])]) await db.exec(fs.readFileSync(B+f,'utf8'));
const OA='00000000-0000-0000-0000-000000000001', SA='262a128c-6fb7-470e-9452-5468cd6797c0', HR='a0000000-0000-0000-0000-000000000002', EDU='a0000000-0000-0000-0000-000000000003', INS='a0000000-0000-0000-0000-000000000004', HEAD='a0000000-0000-0000-0000-000000000005', EMP='a0000000-0000-0000-0000-000000000006', REV='a0000000-0000-0000-0000-000000000008';
const as = async (uid, sql, p) => { await db.exec(`set role authenticated; select set_config('request.jwt.claims', '{"sub":"${uid}","role":"authenticated"}', false), set_config('request.jwt.claim.sub','${uid}',false);`);
  try { const r = await db.query(sql, p); return 'OK:' + (r.affectedRows ?? r.rows.length); } catch (e) { return 'DENIED: ' + e.message.slice(0, 80); } finally { await db.exec(`reset role; select set_config('request.jwt.claims','',false), set_config('request.jwt.claim.sub','',false);`); } };
const sys = s => db.exec(`select set_config('medacademy.system_write','on',false); ${s}; select set_config('medacademy.system_write','off',false);`);
const st = async id => (await db.query(`select workflow_status w, evidence_status e, current_version v, public._q_exam_eligible(q) el from questions q where id=$1`, [id])).rows[0];
const qs = (await db.query(`select id from questions where course_id='CARDIO_BASIC' and published_version is not null order by id limit 6`)).rows.map(r => r.id);
const qn = (await db.query(`select id from questions where course_id='ETHICS' and published_version is not null order by id limit 1`)).rows[0].id;
const src = (await db.query(`insert into evidence_sources (org_id, scope_type, source_type, title, organization, guideline_version, url, verification_status, verification_source, verified_at) values ($1,'organization','guideline','PROBE guideline','PROBE','1','https://example.org/p','verified','manual',now()) returning id`, [OA])).rows[0].id;
const ready = async q => { await sys(`insert into question_evidence (org_id, question_id, evidence_source_id, relationship_type, supporting_claim) values ('${OA}','${q}','${src}','primary_support','PROBE')`);
  await as(EDU, `insert into question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision) select org_id, id, current_version, 'evidence', $1, 'approved' from questions where id=$2`, [EDU, q]); };
const medIns = (uid, q, dec = 'approved', type = 'medical') => as(uid, `insert into question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision, internal_notes) select org_id, id, current_version, $3, $1, $4, 'probe' from questions where id=$2`, [uid, q, type, dec]);
const publish = (uid, q) => as(uid, `update questions set workflow_status='published' where id=$1`, [q]);
const out = [];
const P = (id, name, r) => { out.push([id, name, r]); };
// P1-P5: kim medical review yoza oladi
for (const [id, who, uid] of [['P01','HR',HR],['P02','Department Head',HEAD],['P03','Employee',EMP],['P04','Instructor (biriktirilgan kurs)',INS],['P05','Education Manager',EDU],['P06','Medical Reviewer (tayinlovsiz)',REV],['P07','Super Admin',SA]])
  P(id, who + ' → medical review INSERT (approved)', await medIns(uid, qs[0]));
// P8: EM bir o'zi: evidence approve + medical approve + publish (klinik)
await ready(qs[1]); await medIns(EDU, qs[1]); P('P08', 'EM yolg\'iz: evidence+medical approve → publish (klinik)', (await publish(EDU, qs[1])) + ' | ' + JSON.stringify(await st(qs[1])));
// P9: faqat instructor medical approve → publish (EM)
await ready(qs[2]); await medIns(INS, qs[2]); P('P09', 'Faqat instructor medical approve → EM publish', (await publish(EDU, qs[2])) + ' | ' + JSON.stringify(await st(qs[2])));
// P10: MR approve, keyin MR reject → publish
await ready(qs[3]); await sys(`insert into question_review_assignments (org_id, question_id, reviewer_id, review_type) values ('${OA}','${qs[3]}','${REV}','medical')`);
const a1 = await medIns(REV, qs[3], 'approved'), a2 = await medIns(REV, qs[3], 'rejected');
P('P10', 'MR approve → keyin MR REJECT → EM publish (oxirgi qaror hisobga olinadimi?)', a1 + ' / ' + a2 + ' / ' + (await publish(EDU, qs[3])) + ' | ' + JSON.stringify(await st(qs[3])));
// P11: MR publish
await ready(qs[4]); await sys(`insert into question_review_assignments (org_id, question_id, reviewer_id, review_type) values ('${OA}','${qs[4]}','${REV}','medical')`); await medIns(REV, qs[4]);
P('P11', 'MR medical approve → MR publish', (await publish(REV, qs[4])) + ' | ' + JSON.stringify(await st(qs[4])));
// P12: instructor published savolni review_required'ga tushiradi (medical mark_outdated)
P('P12', 'Instructor medical "mark_outdated" (published, eligible savol)', (await medIns(INS, qs[4], 'mark_outdated')) + ' | ' + JSON.stringify(await st(qs[4])));
// P13: instructor review_type=instructor, mark_conflicting
await sys(`update questions set evidence_status='current', workflow_status='published' where id='${qs[1]}'`);
P('P13', 'Instructor review_type="instructor" decision "mark_conflicting"', (await medIns(INS, qs[1], 'mark_conflicting', 'instructor')) + ' | ' + JSON.stringify(await st(qs[1])));
// P14: instructor to'g'ridan-to'g'ri workflow_status='review_required'
await sys(`update questions set evidence_status='current', workflow_status='published' where id='${qs[5]}'`);
P('P14', 'Instructor UPDATE questions.workflow_status=review_required', (await as(INS, `update questions set workflow_status='review_required' where id=$1`, [qs[5]])) + ' | ' + JSON.stringify(await st(qs[5])));
// P15: instructor publish
P('P15', 'Instructor publish (question.publish yo\'q)', await publish(INS, qs[0]));
// P16: instructor legacy status=approved
P('P16', 'Instructor legacy status="approved"', await as(INS, `update questions set status='approved' where id=$1`, [qs[0]]));
// P17: non-clinical: evidence approve → publish without medical
await sys(`insert into question_evidence (org_id, question_id, evidence_source_id, relationship_type, supporting_claim) values ('${OA}','${qn}','${src}','primary_support','PROBE')`);
await as(EDU, `insert into question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision) select org_id, id, current_version, 'evidence', $1, 'approved' from questions where id=$2`, [EDU, qn]);
P('P17', 'Klinik emas (ETHICS): evidence approve → EM publish, medical review\'siz', (await publish(EDU, qn)) + ' | ' + JSON.stringify(await st(qn)));
// P18: review yozuvini o'zgartirish/o'chirish
P('P18', 'question_reviews UPDATE / DELETE (hatto SQL)', await db.query(`update question_reviews set decision='approved' where internal_notes='probe'`).then(() => 'ALLOWED', e => 'DENIED: ' + e.message.slice(0, 50)) + ' / ' + await db.query(`delete from question_reviews where internal_notes='probe'`).then(() => 'ALLOWED', e => 'DENIED: ' + e.message.slice(0, 50)));
// P19: reviewer_id soxtalashtirish (boshqa reviewer nomidan)
P('P19', 'Instructor reviewer_id = MR id bilan INSERT (soxtalashtirish)', (await as(INS, `insert into question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision) select org_id, id, current_version, 'medical', $1, 'approved' from questions where id=$2 returning reviewer_id`, [REV, qs[0]])) + ' | stored reviewer = ' + (await db.query(`select reviewer_id from question_reviews where question_id=$1 order by created_at desc limit 1`, [qs[0]])).rows[0].reviewer_id);
// P20: rolni keyin o'zgartirish: instructor approve → instructor medical_reviewer'ga ko'tariladi → eski yozuv hisobga olinadimi
await ready(qs[0]);
const oldRev = await medIns(INS, qs[0]); await sys(`update profiles set role='medical_reviewer' where id='${INS}'`);
P('P20', 'Instructor davridagi medical approve, keyin rol medical_reviewer\'ga o\'zgaradi → EM publish', oldRev + ' / ' + (await publish(EDU, qs[0])) + ' | ' + JSON.stringify(await st(qs[0])));
for (const [id, n, r] of out) console.log(id, '|', n, '|', r);
