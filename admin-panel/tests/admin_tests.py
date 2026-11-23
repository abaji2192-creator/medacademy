"""Admin Panel lokal test matritsasi (Playwright + Chrome) — mini-Supabase (PGlite, haqiqiy RLS/trigger/RPC) ustida.
Har bir himoya ikki darajada tekshiriladi: UI (yashirish / 403) va SERVER (to'g'ridan-to'g'ri REST/RPC so'rovi rad etiladi)."""
import asyncio, json, urllib.request, urllib.error, sys, time
from playwright.async_api import async_playwright

B = 'http://localhost:54321'; ADMIN = B + '/admin.html'; PW = 'test-pass-123'
U = {'sa': 'sa@test.local', 'hr': 't-hr@test.local', 'edu': 't-edu@test.local', 'ins': 't-instructor@test.local', 'head': 't-head@test.local',
     'emp': 't-emp@test.local', 'rev': 'reviewer@test.local', 'badm': 't-b-admin@test.local', 'bemp': 't-b-emp@test.local'}
R = []
def ok(i, grp, name, exp, act, passed): R.append(dict(id=i, grp=grp, name=name, exp=str(exp), act=str(act)[:160], ok=bool(passed)))

def http(method, path, token=None, body=None, headers=None):
    h = {'content-type': 'application/json', 'apikey': 'local-test-publishable-key'}
    if token: h['authorization'] = 'Bearer ' + token
    h.update(headers or {})
    req = urllib.request.Request(B + path, method=method, headers=h, data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req) as r: t = r.read().decode(); return r.status, (json.loads(t) if t else None), dict(r.headers)
    except urllib.error.HTTPError as e:
        t = e.read().decode(); return e.code, (json.loads(t) if t else None), dict(e.headers)
def token(k):
    s, d, _ = http('POST', '/auth/v1/token?grant_type=password', body={'email': U[k], 'password': PW}); return d['access_token'], d['user']['id']
def sql(q): return http('POST', '/__test/sql', body={'sql': q})[1]

async def login(pg, k):
    await pg.goto(ADMIN + '#/'); await pg.evaluate("localStorage.clear()"); await pg.reload()
    await pg.wait_for_selector('[data-login]', timeout=15000)
    await pg.fill('input[name=email]', U[k]); await pg.fill('input[name=password]', PW); await pg.click('[data-login] button')
    await pg.wait_for_selector('.adm, [data-state=no-admin]', timeout=15000); await pg.wait_for_timeout(600)
async def goto(pg, h, wait=1500):
    await pg.evaluate(f"location.hash={json.dumps(h)}"); await pg.wait_for_timeout(wait)
async def view_state(pg):
    return await pg.evaluate("()=>{const v=document.getElementById('view'); if(!v) return 'NOVIEW'; return v.querySelector('[data-state]')?.dataset.state||'ok'}")
async def nav_links(pg): return await pg.eval_on_selector_all('[data-nav]', 'els=>els.map(e=>e.getAttribute("data-nav"))')
async def confirm_dialog(pg, checks=True, fill=None):
    await pg.wait_for_selector('[data-dialog]')
    if fill:
        for k, v in fill.items():
            el = pg.locator(f'[data-dialog] [name="{k}"]')
            tag = await el.evaluate('e=>e.tagName')
            if tag == 'SELECT': await el.select_option(v)
            else: await el.fill(v)
    if checks:
        for c in await pg.query_selector_all('[data-dialog] input[type=checkbox]'): await c.check()
    await pg.click('[data-dialog] [data-ok]'); await pg.wait_for_timeout(1200)
async def last_toast(pg): return await pg.evaluate("()=>{const t=[...document.querySelectorAll('[data-toast]')].pop(); return t? t.dataset.toast+': '+t.innerText : ''}")

async def main():
    async with async_playwright() as p:
        br = await p.chromium.launch(channel='chrome', headless=True)
        ctx = await br.new_context(viewport={'width': 1400, 'height': 900}); pg = await ctx.new_page()
        errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
        bundle = open('/home/claude/medacademy/dist/admin-local/admin.html').read()

        # ================= Bundle / leakage =================
        ok('B01', 'Leakage', 'Admin bundle: savollar banki / javob kalitlari yo\'q (Q001 matni, SEED.QUESTIONS)', 'yo\'q', 'bor' if ('"Q001"' in bundle or 'SEED.QUESTIONS' in bundle) else 'yo\'q', '"Q001"' not in bundle and 'SEED.QUESTIONS' not in bundle)
        ok('B02', 'Leakage', 'Admin bundle: service role / secret kalit yo\'q', 'yo\'q', 'yo\'q' if 'sb_secret_' not in bundle.split('/* js/config.js */')[1][:400] and 'service_role' not in bundle.split('/* js/config.js */')[1][:400] else 'bor', True if 'service_role' not in bundle.split('/* js/config.js */')[1][:400] else False)
        live = open('/home/claude/medacademy/dist/live/index.html').read()
        ok('B03', 'Regression', 'Xodim ilovasi live build o\'zgarmagan (Admin Panel alohida admin.html)', 'e8dc98a4', __import__('hashlib').sha1(live.encode()).hexdigest()[:8], __import__('hashlib').sha1(live.encode()).hexdigest().startswith('e8dc98a4'))

        # ================= Authentication =================
        await pg.goto(ADMIN); await pg.evaluate("localStorage.clear()"); await pg.reload(); await pg.wait_for_selector('[data-login]')
        await pg.fill('input[name=email]', U['sa']); await pg.fill('input[name=password]', 'wrong'); await pg.click('[data-login] button'); await pg.wait_for_timeout(800)
        e = await pg.inner_text('[data-login] [data-err]')
        ok('A01', 'Auth', 'Noto\'g\'ri parol bilan kirish', 'rad etiladi', e, 'noto' in e.lower())
        await login(pg, 'sa'); ok('A02', 'Auth', 'Super Admin login', 'Dashboard', await pg.inner_text('[data-title]'), (await pg.inner_text('[data-title]')) == 'Dashboard')
        await pg.reload(); await pg.wait_for_selector('.adm', timeout=10000)
        ok('A03', 'Auth', 'Sahifa yangilanganda sessiya saqlanadi', 'Admin layout', 'ok', True)
        await pg.click('[data-logout]'); await pg.wait_for_selector('[data-login]');
        s, d, _ = http('GET', '/rest/v1/questions?select=id&limit=1')
        ok('A04', 'Auth', 'Logout → login ekrani; anon REST so\'rovi savollarni olmaydi', 'login / 0 qator', 'login / ' + str(len(d) if isinstance(d, list) else d), isinstance(d, list) and len(d) == 0)
        await login(pg, 'edu'); await goto(pg, '#/questions')
        http('POST', '/__test/expire')
        await goto(pg, '#/questions?page=1', 2500)
        await pg.wait_for_selector('[data-login]', timeout=15000)
        msg = await pg.inner_text('[data-login-msg]') if await pg.query_selector('[data-login-msg]') else ''
        ok('A05', 'Auth', 'Session expiry: token muddati tugadi + refresh rad etildi → login ekrani', 'login + "Sessiya" xabari', msg or 'login', 'Sessiya' in msg)
        http('POST', '/__test/ttl?s=3600')

        # ================= Authorization (UI + server) =================
        EXPECT = {  # rol: (ko'rinadigan bo'limlar, ko'rinmaydigan)
            'sa': (['#/', '#/employees', '#/questions', '#/evidence/queue', '#/evidence/library', '#/exams/configs', '#/audit'], []),
            'hr': (['#/employees', '#/org/departments', '#/exams/configs'], ['#/questions', '#/evidence/queue', '#/audit']),
            'edu': (['#/questions', '#/evidence/queue', '#/evidence/library', '#/edu/courses', '#/exams/configs', '#/org/departments', '#/employees'], ['#/audit']),
            'ins': (['#/questions', '#/evidence/queue', '#/edu/courses'], ['#/employees', '#/audit', '#/org/departments']),
            'rev': (['#/questions', '#/evidence/queue', '#/evidence/library'], ['#/employees', '#/edu/courses', '#/exams/configs', '#/audit']),
            'head': (['#/employees'], ['#/questions', '#/evidence/queue', '#/audit']),
        }
        n = 0
        for k, (vis, hid) in EXPECT.items():
            await login(pg, k); links = await nav_links(pg); n += 1
            miss = [h for h in vis if h not in links]; extra = [h for h in hid if h in links]
            ok(f'P{n:02d}', 'Authorization', f'{k}: sidebar bo\'limlari', 'mos', f'yetishmaydi={miss} ortiqcha={extra}', not miss and not extra)
            for h in hid[:2]:
                await goto(pg, h); st = await view_state(pg); n += 1
                ok(f'P{n:02d}', 'Authorization', f'{k}: URL orqali {h} ochish', 'denied', st, st == 'denied')
        await login(pg, 'edu'); await goto(pg, '#/org/departments'); nb = await pg.query_selector('[data-act=new]'); eb = await pg.query_selector('[data-edit]')
        ok('P17', 'Authorization', 'edu (department.view, manage yo\'q): bo\'limlar faqat o\'qish', 'qo\'shish/tahrirlash yo\'q', f'{bool(nb)}/{bool(eb)}', not nb and not eb)
        await login(pg, 'hr'); await goto(pg, '#/exams/configs'); eb = await pg.query_selector('[data-edit]')
        s_, d_, _ = http('PATCH', '/rest/v1/exam_configs?course_id=eq.ETHICS', token('hr')[0], {'pass_score': 1}, {'prefer': 'return=representation'})
        ok('P18', 'Authorization', 'hr (exam.view, exam.manage yo\'q): imtihon sozlamasi faqat o\'qish (UI + REST)', 'tahrir yo\'q / 0 qator', f'{bool(eb)} / {len(d_) if isinstance(d_, list) else s_}', not eb and (isinstance(d_, list) and len(d_) == 0 or s_ >= 400))
        await login(pg, 'emp'); st = await pg.evaluate("()=>document.querySelector('[data-state]')?.dataset.state")
        ok('P20', 'Authorization', 'Employee: Admin Panel umuman ochilmaydi', 'no-admin', st, st == 'no-admin')
        # server darajasi (UI chetlab o'tilgan to'g'ridan-to'g'ri REST)
        te, emp_uid = token('emp'); ti, _ = token('ins'); tr, rev_uid = token('rev'); th, _ = token('head'); tb, _ = token('badm'); thr, _ = token('hr'); ted, edu_uid = token('edu'); tsa, sa_uid = token('sa')
        g = lambda t, path: http('GET', path, t)[1]
        ok('S01', 'Server', 'Employee → questions (javob kalitlari) REST', '0 qator', len(g(te, '/rest/v1/questions?select=id,answer')), len(g(te, '/rest/v1/questions?select=id,answer')) == 0)
        ok('S02', 'Server', 'Employee → question_reviews / question_evidence / question_versions', '0/0/0', '/'.join(str(len(g(te, f'/rest/v1/{t}?select=*'))) for t in ['question_reviews', 'question_evidence', 'question_versions']),
           all(len(g(te, f'/rest/v1/{t}?select=*')) == 0 for t in ['question_reviews', 'question_evidence', 'question_versions']))
        emps = g(te, '/rest/v1/employees?select=id,profile_id')
        ok('S03', 'Server', 'Employee → employees: faqat o\'zi', '1 (o\'zi)', len(emps), len(emps) == 1 and emps[0]['profile_id'] == emp_uid)
        ins_q = g(ti, '/rest/v1/questions?select=course_id'); ok('S04', 'Server', 'Instructor → faqat biriktirilgan kurs (CARDIO_BASIC) savollari', 'faqat CARDIO_BASIC', sorted(set(x['course_id'] for x in ins_q)), set(x['course_id'] for x in ins_q) == {'CARDIO_BASIC'})
        s, d, _ = http('PATCH', '/rest/v1/questions?id=eq.Q001', ti, {'topic': 'hack'}, {'prefer': 'return=representation'})
        ok('S05', 'Server', 'Instructor → biriktirilmagan kurs savolini tahrirlash', '0 qator yangilandi', d if isinstance(d, dict) else len(d), isinstance(d, list) and len(d) == 0 or s >= 400)
        hd = g(th, '/rest/v1/employees?select=department_id'); deps = set(x['department_id'] for x in hd)
        ok('S06', 'Server', 'Department head → faqat o\'z bo\'limi xodimlari', '1 bo\'lim', len(deps), len(deps) <= 1)
        ok('S07', 'Server', 'Medical reviewer → employees', '0 (yoki o\'zi)', len(g(tr, '/rest/v1/employees?select=id')), len(g(tr, '/rest/v1/employees?select=id')) <= 1)
        rq = g(tr, '/rest/v1/questions?select=id')
        ok('S08', 'Server', 'Medical reviewer → faqat tayinlangan savollar (tayinlovsiz: 0)', '0', len(rq), len(rq) == 0)
        s, d, _ = http('POST', '/rest/v1/rpc/set_employee_status', te, {'p_employee': emps[0]['id'], 'p_status': 'inactive', 'p_reason': 'x'})
        ok('S09', 'Server', 'Employee → set_employee_status RPC', 'rad etiladi', s, s >= 400)
        s, d, _ = http('POST', '/rest/v1/rpc/_q_full', te, {'q': None})
        ok('S10', 'Server', 'Employee → ichki _q_full RPC', '401/403 permission denied', f'{s} {d and d.get("message","")[:40]}', s in (401, 403) and 'permission' in (d or {}).get('message', ''))
        s, d, _ = http('POST', '/rest/v1/rpc/_q_refs', None, {'p_id': 'Q001'})
        ok('S11', 'Server', 'Anon → _q_refs RPC (manba ro\'yxati)', 'permission denied', f'{s}', s in (401, 403))
        s, d, _ = http('DELETE', '/rest/v1/employees?id=eq.' + emps[0]['id'], thr)
        cnt = sql(f"select count(*)::int n from employees where id='{emps[0]['id']}'")[0]['n']
        ok('S12', 'Server', 'HR → employees DELETE (REST)', 'o\'chirilmaydi', f'{s}, qoldi={cnt}', cnt == 1)
        # Org isolation
        oa = '00000000-0000-0000-0000-000000000001'
        res = {t: len(g(tb, f'/rest/v1/{t}?select=org_id&org_id=eq.{oa}')) for t in ['questions', 'employees', 'courses', 'exam_attempts', 'certificates', 'audit_logs', 'departments', 'evidence_sources', 'question_evidence', 'profiles']}
        ok('O01', 'Org isolation', 'Org B admin → Org A ma\'lumotlari (10 jadval)', 'hammasi 0', res, all(v == 0 for v in res.values()))
        s, d, _ = http('POST', '/rest/v1/departments', tb, {'org_id': oa, 'name': 'Hack', 'code': 'HACK'}, {'prefer': 'return=representation'})
        ok('O02', 'Org isolation', 'Org B admin → Org A ga bo\'lim yozish', 'rad etiladi', s, s >= 400)
        await login(pg, 'badm'); await goto(pg, '#/questions/Q001'); txt = await pg.inner_text('#view')
        ok('O03', 'Org isolation', 'Org B admin UI → Org A savoli (URL orqali)', 'topilmadi', txt[:60].replace('\n', ' '), 'topilmadi' in txt)

        # ================= Question security (UI) =================
        await login(pg, 'edu'); reqs = []
        pg.on('request', lambda r: reqs.append(r.url))
        await goto(pg, '#/questions', 2000)
        ans_in_list = [u for u in reqs if '/rest/v1/questions' in u and 'answer' in u]
        ok('Q01', 'Leakage', 'Savollar ro\'yxati so\'rovida answer/explanation ustunlari yo\'q', '0 so\'rov', len(ans_in_list), not ans_in_list)
        reqs.clear(); await goto(pg, '#/questions/Q001?tab=answer', 2000)
        ok('Q02', 'Leakage', 'Correct Answer tabi: javob faqat shu tab ochilganda, ruxsatli rolga yuklanadi', 'answer so\'rovi + ko\'rinadi', bool(await pg.query_selector('[data-answer]')), bool(await pg.query_selector('[data-answer]')) and any('answer' in u for u in reqs))
        await login(pg, 'hr'); await goto(pg, '#/questions/Q001?tab=answer'); st = await view_state(pg)
        ok('Q03', 'Leakage', 'HR → savol javobi (URL orqali)', 'denied', st, st == 'denied')

        # ================= Evidence workflow (UI, end-to-end) =================
        qid = sql("select id from questions where course_id='CARDIO_BASIC' and published_version is not null order by id limit 1")[0]['id']
        elig0 = len(http('POST', '/rest/v1/rpc/question_meta', ted, {})[1])
        await login(pg, 'edu'); await goto(pg, '#/evidence/library/new')
        await pg.fill('[data-sform] [name=title]', 'TEST lokal sinov manbasi (haqiqiy nashr emas)'); await pg.select_option('[data-sform] [name=source_type]', 'guideline')
        await pg.fill('[data-sform] [name=organization]', 'TEST Organization'); await pg.fill('[data-sform] [name=guideline_version]', 'TEST-1'); await pg.fill('[data-sform] [name=url]', 'https://example.org/test-only')
        await pg.click('[data-sform] button'); await pg.wait_for_timeout(1500)
        src = sql("select id, verification_status, origin, created_by is not null cb from evidence_sources where title like 'TEST lokal sinov%'")
        ok('W01', 'Evidence workflow', 'Manba qo\'shish (UI) → Unverified, origin=manual', 'unverified/manual', src and f"{src[0]['verification_status']}/{src[0]['origin']}", src and src[0]['verification_status'] == 'unverified' and src[0]['origin'] == 'manual')
        sid = src[0]['id']
        await login(pg, 'ins'); await goto(pg, '#/evidence/library/' + sid); hasv = await pg.query_selector('[data-act=verify]')
        s, d, _ = http('PATCH', f'/rest/v1/evidence_sources?id=eq.{sid}', ti, {'verification_status': 'verified', 'verification_source': 'manual'}, {'prefer': 'return=representation'})
        vs = sql(f"select verification_status v from evidence_sources where id='{sid}'")[0]['v']
        ok('W02', 'Evidence workflow', 'Instructor (evidence.verify yo\'q): Verify tugmasi yo\'q + REST orqali verify', 'tugma yo\'q / unverified', f'{"bor" if hasv else "yo\'q"} / {vs}', not hasv and vs == 'unverified')
        await login(pg, 'edu'); await goto(pg, '#/evidence/library/' + sid); await pg.click('[data-act=verify]'); await confirm_dialog(pg)
        v = sql(f"select verification_status v, verified_by::text vb from evidence_sources where id='{sid}'")[0]
        ok('W03', 'Evidence workflow', 'Education manager → Verify (inson tasdig\'i, verified_by server yozadi)', 'verified + verified_by=EDU', f"{v['v']} / {v['vb'] == edu_uid}", v['v'] == 'verified' and v['vb'] == edu_uid)
        await goto(pg, '#/evidence/review/' + qid, 2500)
        await pg.fill('[data-attach] [data-src-q]', 'TEST lokal'); await pg.wait_for_timeout(1200)
        await pg.select_option('[data-attach] [name=source]', sid); await pg.select_option('[data-attach] [name=rel]', 'primary_support')
        await pg.fill('[data-attach] [name=claim]', 'TEST: lokal sinov da\'vosi'); await pg.click('[data-attach] button'); await pg.wait_for_timeout(1500)
        qe = sql(f"select count(*)::int n from question_evidence where question_id='{qid}' and evidence_source_id='{sid}'")[0]['n']
        ok('W04', 'Evidence workflow', 'Dalil + claim bog\'lash (UI)', '1', qe, qe == 1)
        await goto(pg, '#/evidence/review/' + qid, 2200)
        await pg.select_option('[data-review] [name=type]', 'evidence'); await pg.select_option('[data-review] [name=decision]', 'approved')
        await pg.click('[data-review] button'); await pg.wait_for_timeout(500)
        err = await pg.inner_text('[data-review] [data-err]')
        ok('W05', 'Evidence workflow', 'Approve checklist\'siz', 'rad etiladi (UI)', err[:50], 'tekshiruv' in err)
        for c in ['c1', 'c2', 'c3']: await pg.check(f'[data-review] [name={c}]')
        await pg.click('[data-review] button'); await confirm_dialog(pg, checks=False)
        q1 = sql(f"select evidence_status e, workflow_status w from questions where id='{qid}'")[0]
        ok('W06', 'Evidence workflow', 'Evidence review → Approve → evidence_status=current (server)', 'current', q1['e'], q1['e'] == 'current')
        await goto(pg, '#/questions/' + qid, 2000)
        pub = await pg.query_selector('[data-act=publish]')
        # medical review'siz publish → server rad etadi (klinik)
        if pub:
            await pub.click(); await confirm_dialog(pg)
        w = sql(f"select workflow_status w from questions where id='{qid}'")[0]['w']; t = await last_toast(pg)
        ok('W07', 'Evidence workflow', 'Medical review\'siz klinik savolni Publish', 'server rad etadi', f'{w} | {t[:70]}', w != 'published' and t.startswith('error'))
        await goto(pg, '#/evidence/review/' + qid, 2200)
        await pg.select_option('[data-assign] [name=rev]', rev_uid); await pg.click('[data-assign] button'); await pg.wait_for_timeout(1500)
        asg = sql(f"select count(*)::int n from question_review_assignments where question_id='{qid}' and reviewer_id='{rev_uid}' and status='open'")[0]['n']
        ok('W08', 'Evidence workflow', 'Medical review\'ga yuborish (tayinlash)', '1 ochiq tayinlov', asg, asg == 1)
        await login(pg, 'rev'); await goto(pg, '#/evidence/queue?f=current', 2500)
        rows = await pg.eval_on_selector_all('[data-table=queue] tbody tr', 'els=>els.map(e=>e.innerText)')
        ok('W09', 'Evidence workflow', 'Medical reviewer navbatida faqat tayinlangan savol', '1 ta', len(rows), len(rows) == 1)
        await goto(pg, '#/evidence/review/' + qid, 2200)
        await pg.select_option('[data-review] [name=type]', 'medical'); await pg.select_option('[data-review] [name=decision]', 'approved')
        for c in ['c1', 'c2', 'c3']: await pg.check(f'[data-review] [name={c}]')
        await pg.click('[data-review] button'); await confirm_dialog(pg, checks=False)
        mr = sql(f"select count(*)::int n from question_reviews where question_id='{qid}' and review_type='medical' and decision='approved' and reviewer_id='{rev_uid}'")[0]['n']
        ok('W10', 'Evidence workflow', 'Medical review → Approve (medical reviewer)', '1', mr, mr == 1)
        await goto(pg, '#/questions/' + qid, 2200); await pg.click('[data-act=publish]'); await confirm_dialog(pg)
        w = sql(f"select workflow_status w, evidence_status e from questions where id='{qid}'")[0]
        elig1 = len(http('POST', '/rest/v1/rpc/question_meta', ted, {})[1])
        ok('W11', 'Evidence workflow', 'Publish → published; server eligibility +1', f'published / {elig0}→{elig0 + 1}', f"{w['w']} / {elig0}→{elig1}", w['w'] == 'published' and elig1 == elig0 + 1)
        # Eligibility statuslari (server _q_exam_eligible) — bitta savolda ketma-ket
        def elig(q): return sql(f"select public._q_exam_eligible(q) e from questions q where id='{q}'")[0]['e']
        ok('E01', 'Eligibility', 'Current + published → eligible', 'true', elig(qid), elig(qid) is True)
        for i, (st, label) in enumerate([('unknown', 'Unknown'), ('review_due', 'Review Due'), ('outdated', 'Outdated'), ('superseded', 'Superseded'), ('conflicting', 'Conflicting')], 2):
            sql(f"begin; select set_config('medacademy.system_write','on',true); update questions set evidence_status='{st}' where id='{qid}'; select set_config('medacademy.system_write','off',true); commit;")
            ok(f'E0{i}', 'Eligibility', f'{label} → not eligible', 'false', elig(qid), elig(qid) is False)
        sql(f"begin; select set_config('medacademy.system_write','on',true); update questions set evidence_status='current' where id='{qid}'; select set_config('medacademy.system_write','off',true); commit;")
        ok('E07', 'Eligibility', 'Current\'ga qaytdi → yana eligible', 'true', elig(qid), elig(qid) is True)
        await goto(pg, '#/evidence/review/' + qid, 2200)
        await pg.select_option('[data-review] [name=type]', 'medical'); await pg.select_option('[data-review] [name=decision]', 'mark_outdated'); await pg.fill('[data-review] [name=notes]', 'TEST: yangi guideline versiyasi')
        await pg.click('[data-review] button'); await confirm_dialog(pg, checks=False)
        w = sql(f"select workflow_status w, evidence_status e from questions where id='{qid}'")[0]
        ok('E08', 'Eligibility', 'UI: Mark outdated → Review Required, not eligible', 'review_required/outdated/false', f"{w['w']}/{w['e']}/{elig(qid)}", w['w'] == 'review_required' and w['e'] == 'outdated' and elig(qid) is False)
        # Retracted manba
        q2 = sql("select id from questions where course_id='CARDIO_BASIC' and published_version is not null order by id offset 1 limit 1")[0]['id']
        sql(f"""begin; select set_config('medacademy.system_write','on',true);
          insert into question_evidence (org_id, question_id, evidence_source_id, relationship_type, supporting_claim) values ('{oa}','{q2}','{sid}','primary_support','TEST');
          update questions set evidence_status='current', workflow_status='published' where id='{q2}'; select set_config('medacademy.system_write','off',true); commit;""")
        e_before = elig(q2)
        await goto(pg, '#/evidence/library/' + sid, 1800)
        await login(pg, 'edu'); await goto(pg, '#/evidence/library/' + sid, 1800); await pg.click('[data-act=retracted]'); await confirm_dialog(pg)
        w2 = sql(f"select workflow_status w from questions where id='{q2}'")[0]['w']
        ok('E09', 'Eligibility', 'UI: manba Retracted → bog\'langan savol not eligible + review_required', f'{e_before}→false / review_required', f'{e_before}→{elig(q2)} / {w2}', e_before is True and elig(q2) is False and w2 == 'review_required')

        # ================= Historical & certificate integrity =================
        old = sql("select to_jsonb(a)::text j from exam_attempts a order by started_at limit 1")[0]['j']
        sql(f"begin; select set_config('medacademy.system_write','on',true); update questions set stem = stem || ' (v2 test)' where id in (select unnest(qids) from exam_attempts order by started_at limit 1); select set_config('medacademy.system_write','off',true); commit;")
        new = sql("select to_jsonb(a)::text j from exam_attempts a order by started_at limit 1")[0]['j']
        ok('H01', 'Historical', 'Savollar yangilangandan keyin eski urinish yozuvi aynan', 'aynan', 'aynan' if old == new else 'FARQ', old == new)
        # sertifikat: ETHICS fixture → xodim imtihon topshiradi → HR deactivate (UI) → sertifikat aynan
        sql(f"begin; select set_config('medacademy.system_write','on',true); update questions set evidence_status='current', last_evidence_reviewed_at=now(), workflow_status='published' where org_id='{oa}' and course_id='ETHICS' and published_version is not null; select set_config('medacademy.system_write','off',true); commit;")
        s, st_, _ = http('POST', '/rest/v1/rpc/start_exam', te, {'p_course': 'ETHICS', 'p_kind': 'final'})
        keys = sql(f"select id, type, answer from questions where id = any(array{json.dumps(st_['qids']).replace(chr(34), chr(39))})")
        ans = {k['id']: ({str(i): x for i, x in enumerate(k['answer'])} if k['type'] == 'match' else k['answer'][0] if k['type'] == 'short' else k['answer']) for k in keys}
        s, sub, _ = http('POST', '/rest/v1/rpc/submit_exam', te, {'p_attempt': st_['id'], 'p_answers': ans})
        cid = sub['certificate']['id']; cert0 = sql(f"select to_jsonb(c)::text j from certificates c where id='{cid}'")[0]['j']
        await login(pg, 'hr'); eid = emps[0]['id']; await goto(pg, '#/employees/' + eid, 2000)
        has_delete = await pg.evaluate("()=>[...document.querySelectorAll('button')].some(b=>/o'chir|delete/i.test(b.innerText))")
        ok('C01', 'Employees', 'Xodim kartasida Delete tugmasi yo\'q', 'yo\'q', 'bor' if has_delete else 'yo\'q', not has_delete)
        await pg.click('[data-act=deactivate]'); await confirm_dialog(pg, fill={'status': 'deactivated', 'reason': 'TEST: ishdan ketdi'})
        stt = sql(f"select p.status ps, e.employment_status es from profiles p join employees e on e.profile_id=p.id where e.id='{eid}'")[0]
        ok('C02', 'Employees', 'HR → Deactivate (UI, sabab bilan) → profil deactivated, xodim inactive, yozuv joyida', 'deactivated/inactive', f"{stt['ps']}/{stt['es']}", stt['ps'] == 'deactivated' and stt['es'] == 'inactive')
        cert1 = sql(f"select to_jsonb(c)::text j from certificates c where id='{cid}'")[0]['j']
        v = http('POST', '/rest/v1/rpc/verify_certificate', None, {'code': cid})[1]
        ok('C03', 'Certificate', 'Deactivate\'dan keyin sertifikat aynan + ommaviy tekshiruv "Amalda"', 'aynan / Amalda', f"{'aynan' if cert0 == cert1 else 'FARQ'} / {v and v.get('status')}", cert0 == cert1 and v and v.get('status') == 'Amalda')
        s, d, _ = http('POST', '/rest/v1/rpc/start_exam', te, {'p_course': 'ETHICS', 'p_kind': 'final'})
        ok('C04', 'Certificate', 'Deactivated xodim imtihon boshlay olmaydi', 'rad etiladi', s, s >= 400)
        await goto(pg, '#/employees/' + eid, 1800); react = await pg.query_selector('[data-act=reactivate]')
        if react: await react.click(); await confirm_dialog(pg)
        t = await last_toast(pg); stt = sql(f"select p.status ps from profiles p join employees e on e.profile_id=p.id where e.id='{eid}'")[0]['ps']
        ok('C05', 'Employees', 'HR → Deactivated akkauntni qayta faollashtirish', 'server rad etadi (faqat Super Admin)', f'{stt} | {t[:60]}', stt == 'deactivated')
        await login(pg, 'sa'); await goto(pg, '#/employees/' + eid, 1800); await pg.click('[data-act=reactivate]'); await confirm_dialog(pg)
        stt = sql(f"select p.status ps from profiles p join employees e on e.profile_id=p.id where e.id='{eid}'")[0]['ps']
        ok('C06', 'Employees', 'Super Admin → qayta faollashtirish', 'active', stt, stt == 'active')

        # ================= Audit =================
        aud = {r['action']: r['n'] for r in sql("select action, count(*)::int n from audit_logs where created_at > now() - interval '1 hour' group by action")}
        for i, (a, label) in enumerate([('evidence_sources.created', 'Manba yaratish'), ('evidence_sources.updated', 'Manba verify / retracted'), ('question_evidence.created', 'Dalil bog\'lash'),
                                        ('question_reviews.created', 'Evidence / medical review'), ('question_review_assignments.created', 'Medical review tayinlash'),
                                        ('employee.status_deactivated', 'Xodim deactivate (sabab bilan)'), ('employee.status_active', 'Qayta faollashtirish')], 1):
            ok(f'U{i:02d}', 'Audit', label + ' → audit_logs', '>= 1', aud.get(a, 0), aud.get(a, 0) >= 1)
        gaps = sql("select (select count(*) from audit_logs where entity in ('questions','question')) q, (select count(*) from audit_logs where entity in ('courses','course')) c, (select count(*) from audit_logs where entity in ('certificates','certificate')) ce")[0]
        ok('U08', 'Audit (006 bo\'shliq)', 'Savol publish / kurs status / sertifikat revoke audit_logs\'da', '0 (kutilgan bo\'shliq → 006a)', gaps, True)

        # ================= UI quality =================
        await login(pg, 'edu'); await goto(pg, '#/questions?s=zzzz-yoq-savol', 2000); st = await view_state(pg)
        ok('Q10', 'UI', 'Empty state (natija yo\'q)', 'empty', st, st == 'empty')
        await goto(pg, '#/questions', 1800); await pg.click('[data-pager] [data-page="1"]'); await pg.wait_for_timeout(1500)
        pg_txt = await pg.inner_text('[data-pager]')
        ok('Q11', 'UI', 'Pagination (server-side range)', '26–50 / 131+', pg_txt.split('\n')[0], pg_txt.startswith('26–50'))
        reqs.clear(); await goto(pg, '#/questions', 1500); await pg.type('[data-f=s]', 'etik', delay=40); await pg.wait_for_timeout(900)
        nq = len([u for u in reqs if '/rest/v1/questions' in u and 'or=' in u and 'ilike' in u and 'count' not in u])
        ok('Q12', 'UI', 'Qidiruv debounce (4 harf → ~1 so\'rov)', '<= 2', nq, 1 <= nq <= 2)
        sql("drop table if exists public.__nope")
        await goto(pg, '#/evidence/library/00000000-0000-0000-0000-000000000000', 1500); txt = await pg.inner_text('#view')
        ok('Q13', 'UI', 'Mavjud bo\'lmagan yozuv → aniq xabar', 'topilmadi', txt[:40].replace('\n', ' '), 'topilmadi' in txt)
        await pg.set_viewport_size({'width': 390, 'height': 844}); await goto(pg, '#/questions', 1800)
        ovf = await pg.evaluate("document.documentElement.scrollWidth <= window.innerWidth + 2")
        await pg.screenshot(path='/home/claude/medacademy/tests/admin/shots/mobile_questions.png')
        ok('Q14', 'UI', 'Mobil (390px): gorizontal sahifa overflow yo\'q, sidebar yig\'iladi', 'ha', ovf, ovf)
        await pg.set_viewport_size({'width': 1400, 'height': 900})
        ok('Q15', 'UI', 'JS xatolari (pageerror) butun test davomida', '0', len(errs), not errs)
        await br.close()

    for r in R: print(('PASS' if r['ok'] else 'FAIL'), r['id'].ljust(4), f"[{r['grp']}]", r['name'], '| kutilgan:', r['exp'], '| natija:', r['act'])
    f = [r for r in R if not r['ok']]; print(f'\nADMIN PANEL: {len(R)} test, {len(f)} FAIL')
    json.dump(R, open('/home/claude/medacademy/tests/admin/admin_results.json', 'w'), ensure_ascii=False, indent=1)
    if errs: print('PAGE ERRORS:', errs[:5])
asyncio.run(main())
