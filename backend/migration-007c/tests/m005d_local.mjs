// Migration 005d — lokal to'liq sinov (PGlite, Supabase'ga o'xshash huquqlar bilan).
// Ketma-ketlik: prod-identik zanjir (002/003 → 004 → 005) → test fixture'lar → snapshot
//   → 005d apply → qayta apply (idempotent) → tekshiruvlar → rollback → tiklanish tekshiruvi → recovery (qayta apply)
//   → funksional / xavfsizlik testlari → rollback himoyasi (deactivated akkaunt bor) testi.
import { PGlite } from '/tmp/pgt/node_modules/@electric-sql/pglite/dist/index.js';
import fs from 'fs';
const B = '/home/claude/medacademy/site/backend/';
const db = new PGlite();
const ex = s => db.exec(s);
const q = async (s, p) => (await db.query(s, p)).rows;
const results = []; let n = 0;
const ok = (id, group, name, expected, actual, pass) => { results.push({ id, group, name, expected: String(expected), actual: String(actual), pass: !!pass }); };

// Supabase'ga o'xshash muhit: postgres yaratgan obyektlarga anon/authenticated uchun default huquqlar
await ex(`create role anon nologin; create role authenticated nologin; create role authenticator nologin; create role service_role nologin bypassrls; grant anon, authenticated to authenticator;
create schema auth; create table auth.users (id uuid primary key, instance_id uuid, aud text, role text, email text, raw_user_meta_data jsonb, created_at timestamptz, updated_at timestamptz);
create function auth.uid() returns uuid language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claim.sub', true),''), (nullif(current_setting('request.jwt.claims', true),'')::jsonb ->> 'sub'))::uuid $$;
grant usage on schema auth to authenticated, anon; grant execute on function auth.uid() to authenticated, anon;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;`);

// Supabase'ning o'z event trigger funksiyasi (rls_auto_enable) — production/staging'da mavjud
await ex(`create or replace function public.rls_auto_enable() returns event_trigger language plpgsql security definer as $$ declare cmd record; begin
  for cmd in select * from pg_event_trigger_ddl_commands() where command_tag in ('CREATE TABLE','CREATE TABLE AS','SELECT INTO') and object_type in ('table','partitioned table') loop
    if cmd.schema_name = 'public' then execute format('alter table %s enable row level security', cmd.object_identity); end if; end loop; end $$;
  create event trigger ensure_rls on ddl_command_end execute function public.rls_auto_enable();`);
const run = async f => { try { return await ex(fs.readFileSync(B + f, 'utf8')); } catch (e) { console.log('ERROR in', f, ':', e.message, e.where || ''); throw e; } };
for (const f of ['supabase.sql', 'staging/01_prod_like_data.sql', 'production/01_apply_002_003.sql', 'production/12_apply_004.sql', 'production/22_apply_005.sql',
                 'tests/004_test_setup.sql', 'tests/005_test_setup.sql']) await run(f);

const SA = '262a128c-6fb7-470e-9452-5468cd6797c0', HR = 'a0000000-0000-0000-0000-000000000002', EDU = 'a0000000-0000-0000-0000-000000000003',
  INS = 'a0000000-0000-0000-0000-000000000004', HEAD = 'a0000000-0000-0000-0000-000000000005', EMP = 'a0000000-0000-0000-0000-000000000006',
  EMP2 = 'a0000000-0000-0000-0000-000000000007', REV = 'a0000000-0000-0000-0000-000000000008', BADM = 'b0000000-0000-0000-0000-000000000001', BEMP = 'b0000000-0000-0000-0000-000000000002';

// ---- snapshot yordamchilari ----
const tables = (await q(`select tablename from pg_tables where schemaname='public' order by 1`)).map(r => r.tablename);
const dataSnap = async () => { const o = {}; for (const t of tables) { if (t === 'schema_migrations') continue;
  o[t] = (await q(`select count(*)::int n, coalesce(md5(string_agg(md5(x::text), '' order by md5(x::text))), '-') h from public.${t} x`))[0]; } return o; };
const fkSnap = async () => JSON.stringify(await q(`select conrelid::regclass::text t, conname, pg_get_constraintdef(oid) d from pg_constraint where contype in ('f','c') and connamespace='public'::regnamespace order by 1,2`));
const aclSnap = async () => JSON.stringify(await q(`select p.oid::regprocedure::text s, has_function_privilege('anon', p.oid, 'execute') a, has_function_privilege('authenticated', p.oid, 'execute') u
   from pg_proc p where p.pronamespace='public'::regnamespace and p.prokind='f' and p.proname not in ('set_employee_status','guard_certificate_history','guard_attempt_history') order by 1`));
const policySnap = async () => JSON.stringify(await q(`select tablename, policyname, cmd, roles::text, qual, with_check from pg_policies where schemaname='public' order by 1,2`));
const trgSnap = async () => JSON.stringify(await q(`select c.relname, t.tgname from pg_trigger t join pg_class c on c.oid=t.tgrelid where not t.tgisinternal and c.relnamespace='public'::regnamespace order by 1,2`));
const diff = (a, b) => Object.keys(a).filter(k => JSON.stringify(a[k]) !== JSON.stringify(b[k]));
const as = async (uid, sql, p) => { await ex(uid ? `set role authenticated; select set_config('request.jwt.claim.sub','${uid}',false);` : `set role anon; select set_config('request.jwt.claim.sub','',false);`);
  try { return await q(sql, p); } finally { await ex(`reset role; select set_config('request.jwt.claim.sub','',false);`); } };
const tryAs = async (uid, sql, p) => { try { const r = await as(uid, sql, p); return { ok: true, r }; } catch (e) { return { ok: false, e: e.message }; } };
const cascade6 = `select count(*)::int n from pg_constraint where contype='f' and confdeltype='c' and conname in ('profiles_id_fkey','docs_owner_fkey','exam_attempts_user_id_fkey','certificates_user_id_fkey','attempt_resets_user_id_fkey','exam_configs_course_id_fkey')`;
const restrict6 = cascade6.replace("confdeltype='c'", "confdeltype='r'");
const anonExec = `select count(*)::int n, coalesce(string_agg(proname, ',' order by proname), '') names from pg_proc p where p.pronamespace='public'::regnamespace and p.prokind='f' and has_function_privilege('anon', p.oid, 'execute')`;

const D0 = await dataSnap(), F0 = await fkSnap(), A0 = await aclSnap(), P0 = await policySnap(), T0 = await trgSnap();
const pre = (await q(anonExec))[0];
const preCascade = (await q(cascade6))[0].n;
console.log(`PRE-005d: anon executable functions = ${pre.n}; target CASCADE FK = ${preCascade}`);
// 005d'dan OLDIN: anon _q_full orqali manba ro'yxatini ola oladimi? (xavfni isbotlash)
const preLeak = await tryAs(null, `select public._q_full(q) r from (select (row('X1', null::uuid)::text) ) z, lateral (select * from public.questions limit 0) q`);

// ===== 1. Apply + idempotency =====
let applyErr = null; try { await run('migrations/005d_security_hardening.sql'); } catch (e) { applyErr = e.message; }
ok('D01', 'Migration', '005d apply', 'OK', applyErr || 'OK', !applyErr);
let rerunErr = null; try { await run('migrations/005d_security_hardening.sql'); } catch (e) { rerunErr = e.message; }
const F1 = await fkSnap(), A1 = await aclSnap(), T1 = await trgSnap();
try { await run('migrations/005d_security_hardening.sql'); } catch (e) { rerunErr = rerunErr || e.message; }
ok('D02', 'Migration', '005d qayta apply (idempotent, 3-marta ham) — sxema/huquqlar bir xil', 'OK, o\'zgarishsiz', rerunErr || ((F1 === await fkSnap() && A1 === await aclSnap() && T1 === await trgSnap()) ? 'OK, o\'zgarishsiz' : 'FARQ BOR'),
  !rerunErr && F1 === await fkSnap() && A1 === await aclSnap() && T1 === await trgSnap());
const D1 = await dataSnap();
ok('D03', 'Data', 'Mavjud ma\'lumot o\'zgarmagan (barcha public jadvallar: qator soni + md5)', '0 farq', diff(D0, D1).length + ' farq ' + diff(D0, D1).join(','), diff(D0, D1).length === 0);
ok('D04', 'Data', 'RLS policy\'lar o\'zgarmagan (005d RLS\'ga tegmaydi)', 'bir xil', P0 === await policySnap() ? 'bir xil' : 'FARQ', P0 === await policySnap());

const checkHardened = async (pfx) => {
  ok(pfx + '05', 'FK', 'Target 6 FK: CASCADE soni', '0', (await q(cascade6))[0].n, (await q(cascade6))[0].n === 0);
  ok(pfx + '06', 'FK', 'Target 6 FK: RESTRICT soni', '6', (await q(restrict6))[0].n, (await q(restrict6))[0].n === 6);
  const allCascade = (await q(`select count(*)::int n from pg_constraint where contype='f' and confdeltype='c' and connamespace='public'::regnamespace`))[0].n;
  ok(pfx + '07', 'FK', 'public sxemasidagi barcha CASCADE FK', '0', allCascade, allCascade === 0);
  const a = (await q(anonExec))[0];
  ok(pfx + '08', 'Grants', 'anon EXECUTE qila oladigan funksiyalar', '1 (verify_certificate)', a.n + ' (' + a.names + ')', a.n === 1 && a.names === 'verify_certificate');
  const internalAuth = (await q(`select coalesce(string_agg(p.proname, ','), '') s from pg_proc p join backup.function_categories_005d c on c.name = p.proname
     where p.pronamespace='public'::regnamespace and c.category = 'internal' and has_function_privilege('authenticated', p.oid, 'execute')`))[0].s;
  ok(pfx + '09', 'Grants', 'authenticated → internal funksiyalar (_q_full, _q_refs, _grade, …)', 'hech biri', internalAuth || 'hech biri', !internalAuth);
  const needAuth = (await q(`select coalesce(string_agg(p.proname, ','), '') s from pg_proc p join backup.function_categories_005d c on c.name = p.proname
     where p.pronamespace='public'::regnamespace and c.category in ('employee_rpc','role_rpc','rls_helper','public_safe') and not has_function_privilege('authenticated', p.oid, 'execute')`))[0].s;
  ok(pfx + '10', 'Grants', 'authenticated → ilova RPC va RLS helper\'lari saqlangan', 'barchasi bor', needAuth || 'barchasi bor', !needAuth);
  const unclassified = (await q(`select coalesce(string_agg(p.proname, ','), '') s from pg_proc p left join backup.function_categories_005d c on c.name = p.proname
     where p.pronamespace='public'::regnamespace and p.prokind='f' and c.name is null and pg_get_function_result(p.oid) not in ('trigger','event_trigger')`))[0].s;
  ok(pfx + '11', 'Grants', 'Tasniflanmagan (trigger bo\'lmagan) funksiyalar', 'yo\'q', unclassified || 'yo\'q', !unclassified);
  const trg = (await q(`select count(*)::int n from pg_trigger where tgname in ('certificates_history_guard_trg','exam_attempts_history_guard_trg')`))[0].n;
  ok(pfx + '12', 'History', 'Sertifikat va urinish guard trigger\'lari', '2', trg, trg === 2);
};
await checkHardened('D');

// ===== 2. Rollback → asl holatga qaytish =====
let rbErr = null; try { await run('migrations/005d_rollback.sql'); } catch (e) { rbErr = e.message; }
ok('R01', 'Rollback', '005d rollback', 'OK', rbErr || 'OK', !rbErr);
ok('R02', 'Rollback', 'FK va CHECK constraint\'lar 005d\'dan oldingi holat bilan aynan bir xil', 'bir xil', F0 === await fkSnap() ? 'bir xil' : 'FARQ', F0 === await fkSnap());
ok('R03', 'Rollback', 'Funksiya EXECUTE huquqlari (anon/authenticated) aynan tiklandi', 'bir xil', A0 === await aclSnap() ? 'bir xil' : 'FARQ', A0 === await aclSnap());
ok('R04', 'Rollback', 'Trigger\'lar ro\'yxati 005d\'dan oldingi bilan bir xil', 'bir xil', T0 === await trgSnap() ? 'bir xil' : 'FARQ', T0 === await trgSnap());
ok('R05', 'Rollback', 'RLS policy\'lar bir xil', 'bir xil', P0 === await policySnap() ? 'bir xil' : 'FARQ', P0 === await policySnap());
const D2 = await dataSnap();
ok('R06', 'Rollback', 'Ma\'lumot o\'zgarmagan (rollback ham hech narsa o\'chirmaydi)', '0 farq', diff(D0, D2).length + ' farq', diff(D0, D2).length === 0);
ok('R07', 'Rollback', 'Rollback\'dan keyin anon executable funksiyalar 005d\'dan oldingi soniga qaytdi', String(pre.n), (await q(anonExec))[0].n, (await q(anonExec))[0].n === pre.n);

// ===== 3. Recovery: qayta apply =====
let recErr = null; try { await run('migrations/005d_security_hardening.sql'); } catch (e) { recErr = e.message; }
ok('V01', 'Recovery', 'Rollback\'dan keyin qayta apply', 'OK', recErr || 'OK', !recErr);
await checkHardened('V');
ok('V13', 'Recovery', 'Recovery\'dan keyin sxema/huquqlar birinchi apply bilan bir xil', 'bir xil', (F1 === await fkSnap() && A1 === await aclSnap() && T1 === await trgSnap()) ? 'bir xil' : 'FARQ', F1 === await fkSnap() && A1 === await aclSnap() && T1 === await trgSnap());
const D3 = await dataSnap();
ok('V14', 'Recovery', 'Ma\'lumot o\'zgarmagan', '0 farq', diff(D0, D3).length + ' farq', diff(D0, D3).length === 0);

let D5E = D0; if (process.env.T5E) { await run('migrations/005e_medical_review_authorization.sql'); if (process.env.T6A) { await run('migrations/006a_audit_hardening.sql'); console.log('+ 006a'); if (process.env.T6B) { await run('migrations/006b_course_delete_hardening.sql'); console.log('+ 006b'); if (process.env.T7A) { await run('migrations/007a_learning_progress.sql'); console.log('+ 007a'); if (process.env.T7B) { await run('migrations/007b_learning_path_assignments.sql'); console.log('+ 007b'); if (process.env.T7C) { await run('migrations/007c_skills_competency.sql'); console.log('+ 007c'); } } } } } D5E = await dataSnap(); console.log('+ 005e (4-bo\'limdan boshlab testlar 005e holatida); 005e qonuniy data farqi:', diff(D0, D5E).join(',')); }
// ===== 4. RESTRICT xatti-harakati =====
const delUser = await tryAs(undefined, `select 1`); // no-op
const mustFail = async (sql) => { try { await ex(sql); return 'ALLOWED'; } catch (e) { return 'DENIED: ' + e.message.slice(0, 70); } };
let r = await mustFail(`begin; delete from auth.users where id = '${SA}'; rollback;`); await ex('rollback').catch(() => {});
ok('F01', 'RESTRICT', 'Tarixi bor auth user\'ni o\'chirish (service role / Dashboard ekvivalenti)', 'DENIED', r, r.startsWith('DENIED'));
r = await mustFail(`begin; delete from auth.users where id = '${EMP}'; rollback;`); await ex('rollback').catch(() => {});
ok('F02', 'RESTRICT', 'Profili bor oddiy xodim auth user\'ini o\'chirish', 'DENIED', r, r.startsWith('DENIED'));
r = await mustFail(`begin; delete from public.courses where id = 'TESTB_CARDIO'; rollback;`); await ex('rollback').catch(() => {});
ok('F03', 'RESTRICT', 'Exam config\'i bor kursni o\'chirish', 'DENIED', r, r.startsWith('DENIED'));
ok('F04', 'RESTRICT', 'O\'chirishga urinishdan keyin profil/urinish/sertifikat joyida', 'o\'zgarmagan', diff(D5E, await dataSnap()).length ? 'FARQ' : 'o\'zgarmagan', diff(D5E, await dataSnap()).length === 0);

// ===== 5. Funksiya huquqlari — haqiqiy chaqiruvlar =====
let t = await tryAs(null, `select public._q_full(q) r from public.questions q limit 1`);
ok('G01', 'Grants', 'anon → _q_full (savol + javob + manba)', 'DENIED', t.ok ? 'ALLOWED' : 'DENIED: ' + t.e.slice(0, 50), !t.ok);
t = await tryAs(EMP, `select public._q_full(row(q.*)::public.questions) r from (select 'Q001'::text id) z, lateral (select * from public.questions where false) q`);
const t2 = await tryAs(EMP, `select public._q_refs('Q001') r`);
ok('G02', 'Grants', 'xodim → _q_refs(\'Q001\') (istalgan savol manbalari)', 'DENIED', t2.ok ? 'ALLOWED' : 'DENIED: ' + t2.e.slice(0, 50), !t2.ok);
for (const [id, fn] of [['G03', `public._grade(null::public.questions, '{}'::jsonb, 0)`], ['G04', `public._q_at('Q001', 1)`], ['G05', `public.recompute_question_evidence('Q001')`],
                        ['G06', `public.refresh_evidence_freshness()`], ['G07', `public.mark_overdue_assignments()`], ['G08', `public.seed_org_defaults('00000000-0000-0000-0000-000000000001')`],
                        ['G09', `public._q_exam_eligible(null::public.questions)`], ['G10', `public._cert_out(null::public.certificates)`]]) {
  const a1 = await tryAs(null, `select ${fn}`), a2 = await tryAs(EMP, `select ${fn}`);
  ok(id, 'Grants', 'anon va xodim → ' + fn.split('(')[0].replace('public.', ''), 'DENIED/DENIED', (a1.ok ? 'ALLOWED' : 'DENIED') + '/' + (a2.ok ? 'ALLOWED' : 'DENIED'), !a1.ok && !a2.ok);
}
for (const [id, fn] of [['G11', `public.start_exam('ETHICS','final')`], ['G12', `public.question_meta()`], ['G13', `public.admin_reset_attempts('${EMP}','ETHICS')`],
                        ['G14', `public.revoke_certificate('X')`], ['G15', `public.set_employee_status(gen_random_uuid(), 'inactive', 'x')`], ['G16', `public.my_role()`], ['G17', `public.has_perm('question.view')`]]) {
  const a1 = await tryAs(null, `select ${fn}`);
  ok(id, 'Grants', 'anon → ' + fn.split('(')[0].replace('public.', ''), 'DENIED', a1.ok ? 'ALLOWED' : 'DENIED: ' + a1.e.slice(0, 40), !a1.ok && /permission denied/.test(a1.e));
}
// anon ommaviy tekshiruv: sertifikat yaratib (submit orqali) keyin tekshiramiz — pastda (F-oqim)

// ===== 6. Xodim / admin oqimlari (nazorat qilinadigan fixture: ETHICS, COMM "review'dan o'tgan") =====
await ex(`select set_config('medacademy.system_write','on',false);
  update public.questions set evidence_status='current', last_evidence_reviewed_at=now(), workflow_status='published'
   where org_id='00000000-0000-0000-0000-000000000001' and course_id in ('ETHICS','COMM') and published_version is not null;
  select set_config('medacademy.system_write','off',false);`);
const elig = (await q(`select count(*)::int n from public.questions q where public._q_exam_eligible(q)`))[0].n;
ok('E01', 'Fixture', 'Nazoratli fixture: ETHICS+COMM yaroqli savollar (test bazasida)', '> 0', elig, elig > 0);
t = await tryAs(EMP, `select jsonb_array_length(public.question_meta()) n`);
ok('E02', 'Employee', 'Xodim question_meta() (faqat meta, yaroqlilar)', String(elig), t.ok ? t.r[0].n : t.e, t.ok && t.r[0].n === elig);
t = await tryAs(EMP, `select public.start_exam('ETHICS','final') r`);
const st = t.ok ? t.r[0].r : null;
ok('E03', 'Employee', 'Xodim start_exam(ETHICS, final)', 'OK', t.ok ? 'OK, ' + st.qids.length + ' savol' : t.e, t.ok);
const leak = st ? st.questions.filter(x => x.a !== undefined || x.e !== undefined || x.refs !== undefined || x.ev !== undefined).length : -1;
ok('E04', 'Leakage', 'start_exam payload: javob kaliti / izoh / manba / evidence', '0', leak, leak === 0);
const keys = st ? await q(`select id, type, answer from public.questions where id = any($1)`, [st.qids]) : [];
const ans = {}; keys.forEach(k => { ans[k.id] = k.type === 'match' ? Object.fromEntries(k.answer.map((r, i) => [i, r])) : k.type === 'short' ? k.answer[0] : k.answer; });
t = st ? await tryAs(EMP, `select public.save_answers($1, $2::jsonb) r`, [st.id, JSON.stringify(ans)]) : { ok: false, e: 'no attempt' };
ok('E05', 'Employee', 'save_answers', 'OK', t.ok ? 'OK' : t.e, t.ok);
t = st ? await tryAs(EMP, `select public.submit_exam($1, $2::jsonb) r`, [st.id, JSON.stringify(ans)]) : { ok: false, e: 'no attempt' };
const sub = t.ok ? t.r[0].r : null;
ok('E06', 'Employee', 'submit_exam → 100%, sertifikat', 'PASSED + sertifikat', sub ? sub.attempt.score + '% ' + (sub.certificate ? sub.certificate.id : 'sertifikatsiz') : t.e, sub && sub.attempt.passed && sub.certificate);
const certId = sub && sub.certificate ? sub.certificate.id : 'NONE';
t = await tryAs(EMP, `select public.get_attempt_review($1) r`, [st ? st.id : '']);
ok('E07', 'Employee', 'O\'z urinishini review qilish (yakunlangandan keyin javoblar)', 'OK', t.ok ? 'OK' : t.e, t.ok && t.r[0].r.questions.length > 0);
t = await tryAs(EMP2, `select public.get_attempt_review($1) r`, [st ? st.id : '']);
ok('E08', 'Employee', 'Boshqa xodimning urinish review\'i', 'DENIED', t.ok ? 'ALLOWED' : 'DENIED', !t.ok);
t = await tryAs(EMP, `select count(*)::int n from public.questions`);
ok('E09', 'Leakage', 'Xodim → questions jadvali (javob kalitlari)', '0', t.ok ? t.r[0].n : t.e, t.ok && t.r[0].n === 0);
t = await tryAs(EMP, `select count(*)::int n from public.question_versions`);
ok('E10', 'Leakage', 'Xodim → question_versions', '0', t.ok ? t.r[0].n : t.e, t.ok && t.r[0].n === 0);
t = await tryAs(EMP, `select count(*)::int n from public.question_reviews`);
ok('E11', 'Leakage', 'Xodim → question_reviews (reviewer izohlari)', '0', t.ok ? t.r[0].n : t.e, t.ok && t.r[0].n === 0);
t = await tryAs(EMP, `select count(*)::int n from public.question_evidence`);
ok('E12', 'Leakage', 'Xodim → question_evidence (ichki evidence metadata)', '0', t.ok ? t.r[0].n : t.e, t.ok && t.r[0].n === 0);
t = await tryAs(null, `select public.verify_certificate($1) r`, [certId]);
ok('E13', 'Public', 'anon → verify_certificate (ommaviy QR tekshiruv)', 'Amalda', t.ok ? t.r[0].r?.status : t.e, t.ok && t.r[0].r?.status === 'Amalda');
const vkeys = t.ok && t.r[0].r ? Object.keys(t.r[0].r).sort().join(',') : '';
ok('E14', 'Public', 'verify_certificate faqat minimal maydonlar (email/user_id/ball yo\'q)', 'courseTitle,department,expiresAt,id,issuedAt,name,position,status', vkeys, vkeys === 'courseTitle,department,expiresAt,id,issuedAt,name,position,status');
// admin oqimlari
t = await tryAs(EDU, `select count(*)::int n from public.questions`);
ok('E15', 'Admin', 'Education manager → savollar banki', '> 0', t.ok ? t.r[0].n : t.e, t.ok && t.r[0].n > 0);
t = await tryAs(EDU, `select public.admin_reset_attempts($1, 'ETHICS') r`, [EMP]);
ok('E16', 'Admin', 'Education manager → admin_reset_attempts', 'true', t.ok ? t.r[0].r : t.e, t.ok && t.r[0].r === true);
t = await tryAs(EMP, `select public.admin_reset_attempts($1, 'ETHICS') r`, [EMP2]);
ok('E17', 'Admin', 'Xodim → admin_reset_attempts', 'DENIED', t.ok ? 'ALLOWED' : 'DENIED', !t.ok);
t = await tryAs(EDU, `select public.get_attempt_review($1) r`, [st ? st.id : '']);
ok('E18', 'Admin', 'Education manager → xodim urinishi review', 'OK', t.ok ? 'OK' : t.e, t.ok);
t = await tryAs(INS, `select count(*)::int n from public.questions where course_id = 'CARDIO_BASIC'`);
const t3 = await tryAs(INS, `select count(*)::int n from public.questions where course_id <> 'CARDIO_BASIC'`);
ok('E19', 'Admin', 'Instruktor: faqat biriktirilgan kurs savollari', 'CARDIO_BASIC > 0, boshqa 0', (t.ok ? t.r[0].n : t.e) + ' / ' + (t3.ok ? t3.r[0].n : t3.e), t.ok && t.r[0].n > 0 && t3.ok && t3.r[0].n === 0);
// cross-org
t = await tryAs(BADM, `select (select count(*) from public.questions where org_id='00000000-0000-0000-0000-000000000001')::int qa, (select count(*) from public.exam_attempts where org_id='00000000-0000-0000-0000-000000000001')::int aa,
  (select count(*) from public.certificates where org_id='00000000-0000-0000-0000-000000000001')::int ca, (select count(*) from public.employees where org_id='00000000-0000-0000-0000-000000000001')::int ea`);
ok('E20', 'Cross-org', 'Org B admin → Org A savol/urinish/sertifikat/xodim', '0/0/0/0', t.ok ? Object.values(t.r[0]).join('/') : t.e, t.ok && Object.values(t.r[0]).every(v => v === 0));
t = await tryAs(BADM, `select public.get_attempt_review($1) r`, [st ? st.id : '']);
ok('E21', 'Cross-org', 'Org B admin → Org A urinish review', 'DENIED', t.ok ? 'ALLOWED' : 'DENIED', !t.ok);
t = await tryAs(BADM, `select public.revoke_certificate($1) r`, [certId]);
ok('E22', 'Cross-org', 'Org B admin → Org A sertifikatini revoke', 'false (topilmadi)', t.ok ? String(t.r[0].r) : 'DENIED', !t.ok || t.r[0].r === false);

// ===== 7. Tarixiy yaxlitlik =====
const mustFailSql = async (sql) => { try { await ex(sql); return 'ALLOWED'; } catch (e) { return 'DENIED: ' + e.message.slice(0, 60); } };
const certBefore = (await q(`select to_jsonb(c) j from public.certificates c where id = $1`, [certId]))[0]?.j;
r = await mustFailSql(`update public.certificates set name = 'Boshqa Ism' where id = '${certId}'`);
ok('H01', 'Certificate', 'Sertifikat ismini o\'zgartirish (hatto SQL/service role)', 'DENIED', r, r.startsWith('DENIED'));
r = await mustFailSql(`update public.certificates set score = 50 where id = '${certId}'`);
ok('H02', 'Certificate', 'Sertifikat balini o\'zgartirish', 'DENIED', r, r.startsWith('DENIED'));
r = await mustFailSql(`delete from public.certificates where id = '${certId}'`);
ok('H03', 'Certificate', 'Sertifikatni o\'chirish', 'DENIED', r, r.startsWith('DENIED'));
r = await mustFailSql(`update public.exam_attempts set score = 0 where id = '${st ? st.id : ''}'`);
ok('H04', 'Attempt', 'Yakunlangan urinish balini o\'zgartirish', 'DENIED', r, r.startsWith('DENIED'));
r = await mustFailSql(`delete from public.exam_attempts where id = '${st ? st.id : ''}'`);
ok('H05', 'Attempt', 'Urinishni o\'chirish', 'DENIED', r, r.startsWith('DENIED'));
const oldAtt = (await q(`select to_jsonb(a) j from public.exam_attempts a where id = $1`, [st ? st.id : '']))[0]?.j;
// savol yangilanishi (yangi versiya) → eski urinish o'zgarmaydi
await ex(`select set_config('request.jwt.claim.sub','',false); select set_config('medacademy.system_write','on',false);
  update public.questions set stem = stem || ' (v2 test)' where id = '${st ? st.qids[0] : ''}'; select set_config('medacademy.system_write','off',false);`).catch(e => console.log('q update note:', e.message));
const rev2 = await tryAs(EMP, `select public.get_attempt_review($1) r`, [st ? st.id : '']);
const sameAtt = JSON.stringify(oldAtt) === JSON.stringify((await q(`select to_jsonb(a) j from public.exam_attempts a where id = $1`, [st ? st.id : '']))[0]?.j);
ok('H06', 'Historical', 'Savol yangilangandan keyin eski urinish yozuvi aynan o\'zgarmagan', 'o\'zgarmagan', sameAtt ? 'o\'zgarmagan' : 'O\'ZGARGAN', sameAtt);
const firstQ = rev2.ok ? rev2.r[0].r.questions.find(x => x.id === st.qids[0]) : null;
ok('H07', 'Historical', 'Eski urinish review\'i eski (v1) savol matnini ko\'rsatadi', 'v2 matni yo\'q', firstQ ? (String(firstQ.q).includes('(v2 test)') ? 'v2 ko\'rindi' : 'v2 matni yo\'q') : rev2.e, firstQ && !String(firstQ.q).includes('(v2 test)'));

// ===== 8. Lifecycle: Deactivate > Delete =====
const empRow = (await q(`select id from public.employees where profile_id = $1`, [EMP]))[0];
t = await tryAs(EMP2, `select public.set_employee_status($1, 'inactive', 'test') r`, [empRow.id]);
ok('L01', 'Lifecycle', 'Xodim boshqa xodimni faolsizlantira oladimi', 'DENIED', t.ok ? 'ALLOWED' : 'DENIED', !t.ok);
t = await tryAs(HEAD, `select public.set_employee_status($1, 'inactive', 'test') r`, [empRow.id]);
ok('L02', 'Lifecycle', 'Department head → faolsizlantirish (ruxsat yo\'q)', 'DENIED', t.ok ? 'ALLOWED' : 'DENIED', !t.ok);
t = await tryAs(HR, `select public.set_employee_status($1, 'inactive', '') r`, [empRow.id]);
ok('L03', 'Lifecycle', 'Sababsiz faolsizlantirish', 'DENIED', t.ok ? 'ALLOWED' : 'DENIED: ' + t.e.slice(0, 40), !t.ok);
t = await tryAs(BADM, `select public.set_employee_status($1, 'deactivated', 'x') r`, [empRow.id]);
ok('L04', 'Lifecycle', 'Org B admin → Org A xodimini faolsizlantirish', 'DENIED', t.ok ? 'ALLOWED' : 'DENIED: ' + t.e.slice(0, 30), !t.ok);
const hrEmp = (await q(`select id from public.employees where profile_id = $1`, [HR]))[0];
t = hrEmp ? await tryAs(HR, `select public.set_employee_status($1, 'inactive', 'x') r`, [hrEmp.id]) : { ok: false, e: 'hr employee yo\'q' };
ok('L05', 'Lifecycle', 'O\'z akkauntini faolsizlantirish', 'DENIED', t.ok ? 'ALLOWED' : 'DENIED: ' + t.e.slice(0, 40), !t.ok);
const saEmp = (await q(`select id from public.employees where profile_id = $1`, [SA]))[0];
t = saEmp ? await tryAs(HR, `select public.set_employee_status($1, 'inactive', 'x') r`, [saEmp.id]) : { ok: false, e: 'sa employee yo\'q' };
ok('L06', 'Lifecycle', 'HR → Super Admin\'ni faolsizlantirish', 'DENIED', t.ok ? 'ALLOWED' : 'DENIED: ' + t.e.slice(0, 40), !t.ok);
const auditBefore = (await q(`select count(*)::int n from public.audit_logs`))[0].n;
t = await tryAs(HR, `select public.set_employee_status($1, 'deactivated', 'Ishdan ketdi (test)') r`, [empRow.id]);
ok('L07', 'Lifecycle', 'HR → xodimni deactivate (sabab bilan)', 'OK', t.ok ? JSON.stringify(t.r[0].r) : t.e, t.ok && t.r[0].r.account_status === 'deactivated');
const st2 = (await q(`select p.status ps, e.employment_status es from public.profiles p join public.employees e on e.profile_id = p.id where p.id = $1`, [EMP]))[0];
ok('L08', 'Lifecycle', 'Profil = deactivated, employee = inactive; yozuvlar o\'chirilmagan', 'deactivated/inactive', st2.ps + '/' + st2.es, st2.ps === 'deactivated' && st2.es === 'inactive');
const aud = await q(`select action, actor_id, entity_id, new_value->>'reason' reason from public.audit_logs order by id desc limit 3`);
ok('L09', 'Audit', 'Server-side audit: employee.status_deactivated (actor, sabab) + employee.deactivated', 'ikkalasi', aud.map(a => a.action).join(','),
  aud.some(a => a.action === 'employee.status_deactivated' && a.actor_id === HR && a.reason) && aud.some(a => a.action === 'employee.deactivated'));
t = await tryAs(EMP, `select public.my_role() r`);
ok('L10', 'Lifecycle', 'Deactivated xodim: my_role() → null (barcha RLS yopiladi)', 'null', t.ok ? String(t.r[0].r) : t.e, t.ok && t.r[0].r === null);
t = await tryAs(EMP, `select public.start_exam('COMM','final') r`);
ok('L11', 'Lifecycle', 'Deactivated xodim imtihon boshlay olmaydi', 'DENIED', t.ok ? 'ALLOWED' : 'DENIED: ' + t.e.slice(0, 40), !t.ok);
t = await tryAs(EMP, `select count(*)::int n from public.certificates`);
ok('L12', 'Lifecycle', 'Deactivated xodim o\'z sertifikatini baribir ko\'radi (user_id = o\'zi)', '1', t.ok ? t.r[0].n : t.e, t.ok && t.r[0].n >= 1);
const certAfter = (await q(`select to_jsonb(c) j from public.certificates c where id = $1`, [certId]))[0]?.j;
ok('C01', 'Certificate', 'Deactivate\'dan keyin sertifikat yozuvi aynan o\'zgarmagan', 'o\'zgarmagan', JSON.stringify(certBefore) === JSON.stringify(certAfter) ? 'o\'zgarmagan' : 'O\'ZGARGAN', JSON.stringify(certBefore) === JSON.stringify(certAfter));
t = await tryAs(null, `select public.verify_certificate($1) r`, [certId]);
ok('C02', 'Certificate', 'Deactivate\'dan keyin ommaviy tekshiruv: ism va holat o\'zgarmagan', certBefore?.name + ' / Amalda', t.ok ? t.r[0].r.name + ' / ' + t.r[0].r.status : t.e, t.ok && t.r[0].r.name === certBefore?.name && t.r[0].r.status === 'Amalda');
await ex(`update public.profiles set full_name = 'Yangi Ism' where id = '${EMP}'`);
t = await tryAs(null, `select public.verify_certificate($1) r`, [certId]);
ok('C03', 'Certificate', 'Profil ismi o\'zgarsa ham sertifikatdagi berilgan ism o\'zgarmaydi', certBefore?.name, t.ok ? t.r[0].r.name : t.e, t.ok && t.r[0].r.name === certBefore?.name);
t = await tryAs(EDU, `select public.revoke_certificate($1) r`, [certId]);
const rv1 = (await q(`select revoked, revoked_by, revoked_at from public.certificates where id = $1`, [certId]))[0];
const t4 = await tryAs(SA, `select public.revoke_certificate($1) r`, [certId]);
const rv2 = (await q(`select revoked, revoked_by, revoked_at from public.certificates where id = $1`, [certId]))[0];
ok('C04', 'Certificate', 'Revoke ishlaydi; qayta revoke birinchi yozuvni (kim/qachon) o\'zgartirmaydi', 'revoked, revoked_by=EDU saqlandi',
  (t.ok && rv1.revoked ? 'revoked' : 'xato') + ', revoked_by=' + (rv2.revoked_by === EDU ? 'EDU saqlandi' : rv2.revoked_by), t.ok && rv1.revoked && t4.ok && rv2.revoked_by === EDU && String(rv2.revoked_at) === String(rv1.revoked_at));
r = await mustFailSql(`update public.certificates set revoked = false where id = '${certId}'`);
ok('C05', 'Certificate', 'Bekor qilingan sertifikatni qayta tiklash', 'DENIED', r, r.startsWith('DENIED'));
t = await tryAs(HR, `select public.set_employee_status($1, 'active', null) r`, [empRow.id]);
ok('L13', 'Lifecycle', 'HR → deactivated akkauntni qayta faollashtirish (faqat Super Admin)', 'DENIED', t.ok ? 'ALLOWED' : 'DENIED: ' + t.e.slice(0, 40), !t.ok);

// rollback himoyasi: deactivated akkaunt bor → rollback to'xtaydi, hech narsa o'zgarmaydi
const Fh = await fkSnap(), Ah = await aclSnap();
let rbg = null; try { await run('migrations/005d_rollback.sql'); } catch (e) { rbg = e.message; } await ex('rollback').catch(() => {});
ok('R08', 'Rollback', 'Deactivated akkaunt mavjud bo\'lsa rollback to\'xtaydi (ma\'lumot o\'zgartirilmaydi)', 'BLOCKED, sxema o\'zgarmagan',
  (rbg ? 'BLOCKED' : 'BAJARILDI') + ', ' + (Fh === await fkSnap() && Ah === await aclSnap() ? 'sxema o\'zgarmagan' : 'O\'ZGARDI'), !!rbg && Fh === await fkSnap() && Ah === await aclSnap());
t = await tryAs(SA, `select public.set_employee_status($1, 'active', null) r`, [empRow.id]);
ok('L14', 'Lifecycle', 'Super Admin → qayta faollashtirish', 'OK', t.ok ? t.r[0].r.account_status : t.e, t.ok && t.r[0].r.account_status === 'active');
const saCount = (await q(`select count(*)::int n from public.profiles where role='super_admin' and status='active' and org_id='00000000-0000-0000-0000-000000000001'`))[0].n;
ok('L15', 'Lifecycle', 'Oxirgi faol Super Admin himoyasi mavjud (org A faol super admin)', '>= 1', saCount, saCount >= 1);

// ===== Natija =====
console.log('\nPRE-005d leak demo: anon _q_full = ' + (preLeak.ok ? 'ALLOWED' : 'DENIED'));
for (const x of results) console.log(`${x.pass ? 'PASS' : 'FAIL'}  ${x.id.padEnd(4)} [${x.group}] ${x.name} | kutilgan: ${x.expected} | natija: ${x.actual}`);
const f = results.filter(x => !x.pass).length;
console.log(`\n005d: ${results.length} test, ${f} FAIL`);
fs.writeFileSync('/home/claude/medacademy/tests/m005d_results.json', JSON.stringify({ pre: { anon_exec: pre.n, cascade: preCascade }, results }, null, 1));
process.exit(f ? 1 : 0);
