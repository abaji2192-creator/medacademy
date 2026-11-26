// Lokal SQL test: Supabase'ga o'xshash muhit (auth sxemasi, rollar) + migratsiyalar + RPC oqimlari
import { PGlite } from '/tmp/pgt/node_modules/@electric-sql/pglite/dist/index.js';
import fs from 'fs';
const dir = '/home/claude/medacademy/site/backend/';
const db = new PGlite();
const ex = (s) => db.exec(s);
const q1 = async (s, p) => (await db.query(s, p)).rows;
let fails = 0; const ok = (c, m) => { console.log((c ? 'PASS ' : 'FAIL ') + m); if (!c) fails++; };
await ex(`create role anon nologin; create role authenticated nologin; create role authenticator nologin;
create schema auth; create table auth.users (id uuid primary key, email text, raw_user_meta_data jsonb);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true),'')::uuid $$;
grant usage on schema auth to authenticated, anon; grant execute on function auth.uid() to authenticated, anon;`);
await ex(fs.readFileSync(dir + 'supabase.sql', 'utf8'));
const A = '11111111-1111-1111-1111-111111111111', B = '22222222-2222-2222-2222-222222222222', C = '33333333-3333-3333-3333-333333333333';
await ex(`insert into auth.users values ('${A}','admin@x.uz','{"full_name":"Abdulaziz Isabaev"}');`);
await ex(`insert into public.docs (collection,id,owner,data) values ('attempts','Told1','${A}','{"id":"Told1","empId":"${A}","courseId":"INITIAL","kind":"initial","qids":["Q001","Q002"],"answers":{},"results":{},"score":50,"passed":true,"startedAt":"2026-11-21T06:30:00Z","finishedAt":"2026-11-21T06:35:00Z","dom":{"Q001":"medical"}}'),
 ('employees','${A}','${A}','{"id":"${A}","firstName":"Abdulaziz","lastName":"Isabaev","positionName":"Administrator"}');`);
await ex(fs.readFileSync(dir + 'migrations/002_phase1_server_exams.sql', 'utf8'));
await ex(fs.readFileSync(dir + 'migrations/003_seed_content.sql', 'utf8'));
// idempotent: ikkinchi marta ham xatosiz
await ex(fs.readFileSync(dir + 'migrations/002_phase1_server_exams.sql', 'utf8'));
if (process.env.WITH004) { await ex(fs.readFileSync(dir + 'migrations/004a_org_structure.sql', 'utf8')); await ex(fs.readFileSync(dir + 'migrations/004b_org_isolation_existing.sql', 'utf8')); console.log('+ 004a/004b'); }
if (process.env.WITH005) { for (const f of ['005a_learning_structure.sql','005_seed_structure.sql','005b_evidence_question_system.sql','005c_evidence_governance.sql']) await ex(fs.readFileSync(dir + 'migrations/' + f, 'utf8')); console.log('+ 005'); await ex(`select set_config('medacademy.system_write','on',false); update questions set evidence_status='current', workflow_status='published' where published_version is not null; select set_config('medacademy.system_write','off',false);`); console.log('+ TEST: savollar review qilingan deb simulyatsiya'); }
if (process.env.WITH005D) { await ex(fs.readFileSync(dir + 'migrations/005d_security_hardening.sql', 'utf8')); console.log('+ 005d'); }
if (process.env.WITH005E) { await ex(fs.readFileSync(dir + 'migrations/005e_medical_review_authorization.sql', 'utf8')); console.log('+ 005e'); if (process.env.WITH006A) { await ex(fs.readFileSync(dir + 'migrations/006a_audit_hardening.sql', 'utf8')); console.log('+ 006a'); if (process.env.WITH006B) { await ex(fs.readFileSync(dir + 'migrations/006b_course_delete_hardening.sql', 'utf8')); console.log('+ 006b'); if (process.env.WITH007A) { await ex(fs.readFileSync(dir + 'migrations/007a_learning_progress.sql', 'utf8')); console.log('+ 007a'); if (process.env.WITH007B) { await ex(fs.readFileSync(dir + 'migrations/007b_learning_path_assignments.sql', 'utf8')); console.log('+ 007b'); if (process.env.WITH007C) { await ex(fs.readFileSync(dir + 'migrations/007c_skills_competency.sql', 'utf8')); console.log('+ 007c'); } } } } }
  // TEST simulyatsiyasi (005e): yuqoridagi "review qilingan" simulyatsiyasiga Super Admin tibbiy tasdig'i qo'shiladi (klinik, nashr qilingan versiya)
  await ex(`insert into question_reviews (org_id, question_id, version_no, review_type, reviewer_id, decision, internal_notes)
            select q.org_id, q.id, q.published_version, 'medical', '${A}', 'approved', 'TEST simulyatsiya (005e)' from questions q where q.workflow_status = 'published' and q.published_version is not null and public._q_is_clinical(q)`);
  console.log('+ TEST: 005e tibbiy tasdiq simulyatsiyasi'); }
ok((await q1(`select count(*)::int n from questions`))[0].n === 131, '131 savol seed qilindi');
ok((await q1(`select count(*)::int n from exam_attempts where id='Told1'`))[0].n === 1, 'eski urinish docs → exam_attempts ko\'chirildi');
ok((await q1(`select role from profiles where id='${A}'`))[0].role === 'super_admin', 'birinchi foydalanuvchi super_admin');
await ex(`insert into auth.users values ('${B}','emp@x.uz','{"full_name":"Test Xodim"}'), ('${C}','emp2@x.uz','{}');`);
await ex(`update profiles set status='active', department='Registratura' where id='${B}';`);
const as = async (uid, sql, p) => { await ex(`set role authenticated; select set_config('request.jwt.claim.sub','${uid}',false);`); try { return await q1(sql, p); } finally { await ex(`reset role;`); } };
const err = async (uid, sql) => { try { await as(uid, sql); return null; } catch (e) { return e.message; } };
// xodim savollarni (javoblar bilan) o'qiy olmaydi
ok((await as(B, `select count(*)::int n from questions`))[0].n === 0, 'xodim questions jadvalini ko\'ra olmaydi (RLS)');
ok((await as(A, `select count(*)::int n from questions`))[0].n === 131, 'super_admin savollarni ko\'radi');
ok((await as(B, `select jsonb_array_length(question_meta()) n`))[0].n === 131, 'xodim faqat meta oladi');
// pending foydalanuvchi imtihon boshlay olmaydi
ok(/Faol akkaunt/.test(await err(C, `select start_exam('ETHICS','final')`)), 'pending foydalanuvchi bloklanadi');
// final exam
const st = (await as(B, `select start_exam('ETHICS','final') r`))[0].r;
ok(st.qids.length === 10 && st.deadline, 'final: 10 savol, deadline bor');
ok(st.questions.every(q => q.a === undefined && q.e === undefined), 'payload\'da to\'g\'ri javob yo\'q');
const m = st.questions.find(q => q.type === 'match'); if (m) ok(m.o.every(p => p[1] === null) && m.rights.length === m.o.length, 'matching: o\'ng ustun aralashtirilgan, juftlik yashirin');
const resume = (await as(B, `select start_exam('ETHICS','final') r`))[0].r; ok(resume.id === st.id, 'tugallanmagan imtihon davom ettiriladi (yangi urinish yaratilmaydi)');
// direct write blocked
ok(!!(await err(B, `insert into exam_attempts (user_id,course_id,kind,qids,score,passed) values ('${B}','ETHICS','final','{}',100,true)`)), 'xodim exam_attempts\'ga to\'g\'ridan-to\'g\'ri yoza olmaydi');
ok(!!(await err(B, `insert into certificates (id,user_id,course_id) values ('FAKE','${B}','ETHICS')`)), 'xodim sertifikat yozib qo\'ya olmaydi');
ok(!!(await err(B, `insert into docs (collection,id,owner,data) values ('certificates','X','${B}','{}')`)), 'docs orqali sertifikat yozish ham bloklangan');
// correct answers → pass + cert
const keys = await q1(`select id, type, answer, options from questions where id = any($1)`, [st.qids]);
const ans = {}; keys.forEach(k => { ans[k.id] = k.type === 'match' ? Object.fromEntries(k.answer.map((r, i) => [i, r])) : k.type === 'short' ? k.answer[0] : k.answer; });
const sub = (await as(B, `select submit_exam($1,$2::jsonb) r`, [st.id, JSON.stringify(ans)]))[0].r;
ok(sub.attempt.score === 100 && sub.attempt.passed && sub.certificate && /^IMP-\d{4}-[0-9A-F]{6}$/.test(sub.certificate.id), 'to\'g\'ri javoblar → 100%, PASSED, sertifikat: ' + (sub.certificate && sub.certificate.id));
ok(sub.questions.every(q => q.a !== undefined && q.e !== undefined), 'natijadan keyin javob va izohlar qaytadi');
ok(!!(await err(B, `select submit_exam('${st.id}', '{}'::jsonb)`)), 'qayta topshirib ballni o\'zgartirib bo\'lmaydi');
await ex('set role anon'); const ver = await q1(`select verify_certificate('${sub.certificate.id}') r`); await ex('reset role');
// fail path
const st2 = (await as(B, `select start_exam('PH','final') r`))[0].r;
const sub2 = (await as(B, `select submit_exam($1,'{}'::jsonb) r`, [st2.id]))[0].r;
ok(sub2.attempt.passed === false && sub2.attempt.score === 0 && sub2.attempt.retakeAfter, 'bo\'sh javob → FAILED, retake sanasi qo\'yildi');
ok(/Qayta topshirish sanasi/.test(await err(B, `select start_exam('PH','final')`)), 'retake sanasigacha qayta boshlash bloklanadi');
ok(!!(await err(B, `select admin_reset_attempts('${B}','PH')`)), 'xodim urinishlarni o\'zi tiklay olmaydi');
await as(A, `select admin_reset_attempts('${B}','PH')`);
ok(!!(await as(B, `select start_exam('PH','final') r`))[0].r.id, 'admin tiklagach qayta boshlash mumkin');
// negative marking (SAFETY neg 0.25)
const st3 = (await as(B, `select start_exam('SAFETY','final') r`))[0].r;
const wrong = {}; const k3 = await q1(`select id,type,answer,options from questions where id = any($1)`, [st3.qids]);
k3.forEach(k => { if (k.type === 'tf') wrong[k.id] = !k.answer; else if (['single','case'].includes(k.type)) wrong[k.id] = (k.answer + 1) % k.options.length; });
const sub3 = (await as(B, `select submit_exam($1,$2::jsonb) r`, [st3.id, JSON.stringify(wrong)]))[0].r;
ok(sub3.attempt.score === 0 && Object.values(sub3.attempt.results).some(r => r.pts === -0.25), 'negative marking ishlaydi, ball 0 dan pastga tushmaydi');
// module quiz
const mq = (await as(B, `select start_exam('COMM','module','COM1') r`))[0].r;
ok(mq.qids.length === 4 && !mq.deadline && mq.questions.every(q => q.module === 'COM1'), 'modul testi: 4 savol, faqat shu moduldan, taymersiz');
// initial
const ini = (await as(B, `select start_exam('INITIAL','initial',null,'{"medical":"RECEPTION_START","ethics":"ETHICS","communication":"COMM","safety":"SAFETY","public_health":"PH","sales":"SALES"}'::jsonb) r`))[0].r;
ok(ini.qids.length === 12, 'initial assessment: 6 soha × 2 savol');
const isub = (await as(B, `select submit_exam($1,'{}'::jsonb) r`, [ini.id]))[0].r;
ok(isub.domains && Object.keys(isub.domains).length === 6, 'initial: soha bo\'yicha natijalar qaytadi');
// review
ok(!!(await as(B, `select get_attempt_review('${st.id}') r`))[0].r.questions.length, 'o\'z urinishining tahlili ochiladi');
ok(!!(await err(C, `select get_attempt_review('${st.id}')`)), 'boshqa xodim urinishini ko\'ra olmaydi');
// visibility
ok((await as(B, `select count(*)::int n from exam_attempts where user_id <> '${B}'`))[0].n === 0, 'xodim faqat o\'z urinishlarini ko\'radi');
ok((await as(A, `select count(*)::int n from certificates`))[0].n === 1, 'admin barcha sertifikatlarni ko\'radi');
// revoke
ok(!!(await err(B, `select revoke_certificate('${sub.certificate.id}')`)), 'xodim sertifikatni bekor qila olmaydi');
await as(A, `select revoke_certificate('${sub.certificate.id}')`);
ok((await q1(`select verify_certificate('${sub.certificate.id}') r`))[0].r.status === 'Bekor qilingan', 'bekor qilingan sertifikat tekshiruvda ko\'rinadi');
ok(ver[ver.length-1].r && ver[ver.length-1].r.name === 'Test Xodim', 'anon QR tekshiruvi ishlaydi (faqat minimal ma\'lumot)');
console.log(fails ? `\n${fails} ta test YIQILDI` : '\nBarcha SQL testlar o\'tdi');
process.exit(fails ? 1 : 0);
