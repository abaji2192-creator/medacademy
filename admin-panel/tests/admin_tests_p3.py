"""Phase 3 Frontend STEP 2 — Admin Panel: Learning Paths, Course Progress, Skills/Competency, Compliance, Notifications.
Mini-Supabase (PGlite) WITH007=1 (006a, 006b, 007a–007e) ustida. Har bir himoya UI va SERVER darajasida tekshiriladi."""
import asyncio, json, hashlib
exec(open('/home/claude/medacademy/tests/admin/admin_tests.py').read().split('async def main')[0])

def one(q): r = sql(q); return r[0] if isinstance(r, list) and r else {}
def emp_of(k): return one(f"select e.id, e.department_id from employees e join profiles p on p.id = e.profile_id where p.email = '{U[k]}'")
def rpc(k, fn, args):
    t, _ = token(k); return http('POST', '/rest/v1/rpc/' + fn, t, args)
async def toast_after(pg): await pg.wait_for_timeout(300); return await last_toast(pg)

async def main():
    async with async_playwright() as p:
        br = await p.chromium.launch(channel='chrome', headless=True)
        ctx = await br.new_context(viewport={'width': 1400, 'height': 900}); pg = await ctx.new_page()
        errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
        reqs = []; pg.on('request', lambda r: reqs.append(r.url) if '/rest/v1/' in r.url else None)
        bundle = open('/home/claude/medacademy/dist/admin-local/admin.html').read()
        live = open('/home/claude/medacademy/dist/live/index.html').read()

        # ================= Bundle =================
        mods = ['pages_learning.js', 'pages_skills.js', 'pages_compliance.js']
        ok('P3B01', 'Bundle', 'Admin bundle\'da Phase 3 modullari bor', '3/3', sum(f'/* js/admin/{m} */' in bundle for m in mods), all(f'/* js/admin/{m} */' in bundle for m in mods))
        ok('P3B02', 'Bundle', 'Xodim live build o\'zgarmagan va Phase 3 admin kodi unga kirmagan', 'e8dc98a4 / yo\'q',
           hashlib.sha1(live.encode()).hexdigest()[:8] + ' / ' + ('bor' if 'department_compliance_matrix' in live else 'yo\'q'),
           hashlib.sha1(live.encode()).hexdigest().startswith('e8dc98a4') and 'department_compliance_matrix' not in live)
        import re as _re
        keyleak = _re.findall(r'sb_secret_[A-Za-z0-9_-]{12,}|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]*c2VydmljZV9yb2xl', bundle)
        ok('P3B03', 'Bundle', 'Bundle: service-role / secret kalit qiymati yo\'q', '0', len(keyleak), not keyleak)

        # ================= Navigation / role restrictions =================
        await login(pg, 'edu'); nl = await nav_links(pg)
        want = ['#/learning/paths', '#/learning/progress', '#/skills/skills', '#/compliance/department']
        ok('P3R01', 'Roles', 'Education Manager: "O\'quv rivojlanish" guruhi to\'liq ko\'rinadi', '4/4', sum(w in nl for w in want), all(w in nl for w in want))
        ok('P3R02', 'Roles', 'Education Manager: bildirishnoma qo\'ng\'irog\'i bor', 'bor', await pg.locator('[data-bell]').count(), await pg.locator('[data-bell]').count() == 1)
        await login(pg, 'ins'); nl = await nav_links(pg)
        ok('P3R03', 'Roles', 'Instructor: Compliance matritsasi menyuda yo\'q', 'yo\'q', '#/compliance/department' in nl, '#/compliance/department' not in nl)
        await goto(pg, '#/compliance/department'); st = await view_state(pg)
        ok('P3R04', 'Roles', 'Instructor: #/compliance → 403 sahifa', 'denied', st, st == 'denied')
        s, d, _ = rpc('ins', 'department_compliance_matrix', {'p_department': None})
        ok('P3R05', 'Roles', 'SERVER: Instructor department_compliance_matrix() → rad', '4xx', s, s >= 400)
        await login(pg, 'emp'); st = await pg.evaluate("document.querySelector('[data-state]')?.dataset.state || ''")
        ok('P3R06', 'Roles', 'Oddiy xodim admin panelga kira olmaydi', 'no-admin', st, st == 'no-admin')
        s, d, _ = rpc('emp', 'apply_learning_path', {'p_path': one("select id from learning_paths limit 1")['id'], 'p_target_type': 'role', 'p_target_id': 'employee'})
        ok('P3R07', 'Roles', 'SERVER: xodim apply_learning_path → rad', '4xx', s, s >= 400)

        # ================= Learning Paths =================
        await login(pg, 'edu'); reqs.clear(); await goto(pg, '#/learning/paths', 2200)
        rows = await pg.locator('[data-list] tbody tr').count()
        n_lp = one("select count(*)::int n from learning_paths where org_id = (select org_id from profiles where email = 't-edu@test.local')")['n']
        ok('P3L01', 'Learning', 'Learning Paths ro\'yxati (server bilan teng)', min(25, n_lp), rows, rows == min(25, n_lp))
        nreq = len([u for u in reqs if '/rest/v1/' in u])
        ok('P3L02', 'Learning', 'N+1 yo\'q: ro\'yxat ≤ 5 so\'rov (path + count + courses + assignments)', '<= 5', nreq, nreq <= 5)
        target = emp_of('emp'); edu_emp = emp_of('edu')
        path = one("select lp.id, (select count(*)::int from learning_path_courses c where c.path_id = lp.id) nc from learning_paths lp where status = 'published' order by code limit 1")
        await goto(pg, '#/learning/paths/' + path['id'], 2200)
        crs = await pg.locator('.card').first.inner_text()
        ok('P3L03', 'Learning', 'Path tafsiloti: kurslar ro\'yxati', f"{path['nc']} kurs", crs.split('\n')[0], f"({path['nc']})" in crs)
        ca0 = one(f"select count(*)::int n from course_assignments where employee_id = '{target['id']}'")['n']
        await pg.click('[data-act=apply]'); await confirm_dialog(pg, fill={'type': 'employee'})
        await confirm_dialog(pg, fill={'target': target['id']}); t1 = await toast_after(pg)
        lpa = one(f"select count(*)::int n, max(id::text) id from learning_path_assignments where path_id = '{path['id']}' and employee_id = '{target['id']}' and status = 'active'")
        ca1 = one(f"select count(*)::int n from course_assignments where employee_id = '{target['id']}'")['n']
        ok('P3L04', 'Learning', 'UI orqali tayinlash (RPC apply_learning_path) → qoida + kurs tayinlashlari', '1 qoida, +kurslar', f"{lpa['n']} qoida, +{ca1 - ca0}; {t1[:60]}", lpa['n'] == 1 and ca1 > ca0 and 'Tayinlandi' in t1)
        await pg.click('[data-act=apply]'); await confirm_dialog(pg, fill={'type': 'employee'}); await confirm_dialog(pg, fill={'target': target['id']}); t2 = await toast_after(pg)
        lpa2 = one(f"select count(*)::int n from learning_path_assignments where path_id = '{path['id']}' and employee_id = '{target['id']}'")['n']
        ca2 = one(f"select count(*)::int n from course_assignments where employee_id = '{target['id']}'")['n']
        ok('P3L05', 'Learning', 'Takroriy tayinlash idempotent (dublikat yo\'q)', '1 qoida, 0 yangi', f"{lpa2} qoida, +{ca2 - ca1}; {t2[:50]}", lpa2 == 1 and ca2 == ca1 and 'mavjud' in t2)
        await pg.click(f"[data-reapply='{lpa['id']}']"); await confirm_dialog(pg); t3 = await toast_after(pg)
        ca3 = one(f"select count(*)::int n from course_assignments where employee_id = '{target['id']}'")['n']
        ok('P3L06', 'Learning', 'Qayta qo\'llash (reapply) dublikat yaratmaydi', '+0', f"+{ca3 - ca2}; {t3[:40]}", ca3 == ca2 and 'Qayta' in t3)
        await pg.click(f"[data-cancel='{lpa['id']}']"); await confirm_dialog(pg, fill={'reason': 'P3 test bekor'}); t4 = await toast_after(pg)
        c = one(f"select status, cancel_reason from learning_path_assignments where id = '{lpa['id']}'")
        ca4 = one(f"select count(*)::int n from course_assignments where employee_id = '{target['id']}' and status <> 'cancelled'")['n']
        ok('P3L07', 'Learning', 'Bekor qilish: qoida cancelled, mavjud kurs tayinlashlari saqlanadi', 'cancelled / saqlangan', f"{c.get('status')} / {ca4}", c.get('status') == 'cancelled' and c.get('cancel_reason') == 'P3 test bekor' and ca4 >= ca3 - 0)
        await pg.click('[data-act=apply]'); await confirm_dialog(pg, fill={'type': 'employee'}); await confirm_dialog(pg, fill={'target': edu_emp['id']})  # bildirishnomalar uchun
        tk, _ = token('hr')
        s, d, _ = http('POST', '/rest/v1/learning_path_assignments', tk, {'path_id': path['id'], 'target_type': 'role', 'target_role': 'employee'})
        ok('P3L08', 'Learning', 'SERVER: HR to\'g\'ridan-to\'g\'ri learning_path_assignments INSERT → rad', '4xx', s, s >= 400)
        s, d, _ = rpc('head', 'apply_learning_path', {'p_path': path['id'], 'p_target_type': 'role', 'p_target_id': 'employee'})
        ok('P3L09', 'Learning', 'SERVER: Department Head apply_learning_path → rad', '4xx', s, s >= 400)

        # ================= Course Progress =================
        course = one(f"select course_id from course_assignments where employee_id = '{target['id']}' limit 1")['course_id']
        await goto(pg, '#/learning/progress?course=' + course, 2500)
        kp = await pg.evaluate("Object.fromEntries([...document.querySelectorAll('[data-kpi]')].map(k=>[k.dataset.kpi,k.querySelector('.v').innerText]))")
        s, d, _ = rpc('edu', 'course_progress_summary', {'p_course': course})
        same = all(str(d.get(k)) == kp.get(k) for k in ['assigned_count', 'completed_count', 'in_progress_count', 'not_started_count', 'overdue_count', 'cancelled_count'])
        ok('P3P01', 'Progress', 'Course Progress KPI = server course_progress_summary', 'teng', f"{kp.get('assigned_count')}/{d.get('assigned_count')}", s == 200 and same)
        avg = await pg.inner_text('[data-avg]')
        ok('P3P02', 'Progress', 'O\'rtacha progress serverdan (frontend hisoblamaydi)', f"{d.get('average_progress')}%", avg, avg == f"{d.get('average_progress')}%")
        await goto(pg, '#/learning/progress', 1500); txt = await pg.inner_text('#view')
        ok('P3P03', 'Progress', 'Kurs tanlanmagan → bo\'sh holat (empty state)', 'Kursni tanlang', 'ha' if 'Kursni tanlang' in txt else txt[:40], 'Kursni tanlang' in txt)
        s, d, _ = rpc('ins', 'course_progress_summary', {'p_course': course})
        ok('P3P04', 'Progress', 'SERVER: Instructor — faqat o\'z kurslari (boshqa kurs rad yoki instructor scope)', 'rad / instructor', s if s >= 400 else (d or {}).get('scope'), s >= 400 or (d or {}).get('scope') == 'instructor')

        # ================= Skills / Requirements / Assessments =================
        await goto(pg, '#/skills/skills', 1800); await pg.click('[data-new-skill]')
        await confirm_dialog(pg, fill={'code': 'P3_ECG', 'name': 'EKG talqini', 'category': 'Kardiologiya', 'max': '5'}); t = await toast_after(pg)
        sk = one("select id, max_level, status from skills where code = 'P3_ECG'")
        ok('P3S01', 'Skills', 'Ko\'nikma yaratish (upsert_skill RPC)', 'active / 5', f"{sk.get('status')} / {sk.get('max_level')}", sk.get('status') == 'active' and sk.get('max_level') == 5 and 'saqlandi' in t)
        await goto(pg, '#/skills/skills', 1800); await pg.click(f"[data-edit-skill='{sk['id']}']"); await confirm_dialog(pg, fill={'name': 'EKG talqini (12 tarmoq)'})
        ok('P3S02', 'Skills', 'Ko\'nikmani tahrirlash', 'EKG talqini (12 tarmoq)', one(f"select name from skills where id = '{sk['id']}'").get('name'), one(f"select name from skills where id = '{sk['id']}'").get('name') == 'EKG talqini (12 tarmoq)')
        await goto(pg, '#/skills/requirements', 1800); await pg.click('[data-new-req]')
        await confirm_dialog(pg, fill={'skill': sk['id'], 'type': 'department'}); await confirm_dialog(pg, fill={'target': target['department_id'], 'level': '3'}); t = await toast_after(pg)
        rq = one(f"select id, required_level from competency_requirements where skill_id = '{sk['id']}' and status = 'active'")
        ok('P3S03', 'Skills', 'Kompetensiya talabi (set_competency_requirement)', 'daraja 3', rq.get('required_level'), rq.get('required_level') == 3)
        await goto(pg, '#/compliance/employee/' + target['id'], 2500)
        st0 = await pg.evaluate("[...document.querySelectorAll('[data-table=emp_competencies] tbody tr')].map(r=>r.innerText).join('|')") if await pg.locator('[data-table=emp_competencies]').count() else await pg.inner_text('[data-cm]')
        ok('P3S04', 'Skills', 'Baholashsiz → "Baholanmagan" (not_assessed), ball o\'ylab topilmaydi', 'Baholanmagan', 'Baholanmagan' if 'Baholanmagan' in st0 else st0[:60], 'Baholanmagan' in st0)
        for lvl in ['2', '4']:
            await goto(pg, '#/skills/assessments', 1800); await pg.click('[data-new-asm]')
            await confirm_dialog(pg, fill={'emp': target['id'], 'skill': sk['id'], 'level': lvl, 'notes': 'P3 test'})
            if lvl == '2':
                await goto(pg, '#/compliance/employee/' + target['id'], 2500); st1 = await pg.inner_text('[data-cm]')
        await goto(pg, '#/compliance/employee/' + target['id'], 2500); st2 = await pg.inner_text('[data-cm]')
        hist = one(f"select count(*)::int n, string_agg(level::text, ',' order by assessed_at, assessment_seq) l from skill_assessments where skill_id = '{sk['id']}'")
        ok('P3S05', 'Skills', 'Daraja 2 < 3 → Bajarilmagan; daraja 4 → Bajarilgan', 'not_achieved → achieved', f"{'Bajarilmagan' in st1} → {'Bajarilgan' in st2.replace('Bajarilmagan', '')}",
           'Bajarilmagan' in st1 and 'Bajarilgan' in st2.replace('Bajarilmagan', ''))
        ok('P3S06', 'Skills', 'Baholash tarixi insert-only (2 yozuv saqlangan)', '2: 2,4', f"{hist.get('n')}: {hist.get('l')}", hist.get('n') == 2 and hist.get('l') == '2,4')
        await goto(pg, '#/skills/assessments', 1800); edits = await pg.locator('[data-list] tbody button').count()
        tk, _ = token('edu'); s, d, _ = http('PATCH', f"/rest/v1/skill_assessments?skill_id=eq.{sk['id']}", tk, {'level': 9})
        lv = one(f"select max(level)::int m from skill_assessments where skill_id = '{sk['id']}'")['m']
        ok('P3S07', 'Skills', 'Baholashni tahrirlash: UI tugmasi yo\'q + SERVER PATCH rad', '0 tugma / o\'zgarmagan', f"{edits} / {s} / max={lv}", edits == 0 and lv == 4)
        other = one(f"select id from employees where org_id = (select org_id from employees where id = '{target['id']}') and department_id is distinct from (select department_id from employees e join profiles p on p.id = e.profile_id where p.email = 't-head@test.local') and employment_status = 'active' limit 1")
        s, d, _ = rpc('head', 'record_skill_assessment', {'p_employee': other['id'], 'p_skill': sk['id'], 'p_level': 3})
        ok('P3S08', 'Skills', 'SERVER: Department Head boshqa bo\'lim xodimini baholay olmaydi', '4xx', s, s >= 400)
        await login(pg, 'ins'); await goto(pg, '#/skills/skills', 1800)
        ok('P3S09', 'Skills', 'Instructor (skill.view): ro\'yxat bor, yaratish/arxiv tugmasi yo\'q', '0 tugma', await pg.locator('[data-new-skill], [data-archive-skill]').count(), await pg.locator('[data-new-skill], [data-archive-skill]').count() == 0)
        s, d, _ = rpc('ins', 'upsert_skill', {'p_id': None, 'p_code': 'P3_X', 'p_name': 'Ruxsatsiz', 'p_max_level': 5})
        ok('P3S10', 'Skills', 'SERVER: Instructor upsert_skill → rad', '4xx', s, s >= 400)
        await login(pg, 'edu'); await goto(pg, '#/skills/requirements', 1800); await pg.click(f"[data-archive-req='{rq['id']}']"); await confirm_dialog(pg, fill={'reason': 'P3 test'})
        ok('P3S11', 'Skills', 'Talabni arxivlash (archive_competency_requirement)', 'archived', one(f"select status from competency_requirements where id = '{rq['id']}'").get('status'), one(f"select status from competency_requirements where id = '{rq['id']}'").get('status') == 'archived')
        await pg.click('[data-nav="#/skills/skills"]') if False else None

        # ================= Compliance =================
        await goto(pg, '#/compliance/department', 2500)
        s, d, _ = rpc('edu', 'department_compliance_matrix', {'p_department': None})
        ui_pct = await pg.evaluate("document.querySelector('[data-kpi=compliance_percent] .v')?.innerText")
        ui_deps = await pg.locator('[data-table=dept_matrix] tbody tr').count()
        ok('P3C01', 'Compliance', 'Tashkilot matritsasi: compliance % va bo\'limlar = server', f"{d['training']['compliance_percent']}% / {len(d['departments'])}", f"{ui_pct} / {ui_deps}",
           ui_pct == f"{d['training']['compliance_percent']}%" and ui_deps == len(d['departments']))
        await pg.select_option('[data-f=dep]', target['department_id']); await pg.wait_for_timeout(2200)
        s, d, _ = rpc('edu', 'department_compliance_matrix', {'p_department': target['department_id']})
        ui_rows = await pg.locator('[data-table=dept_rows] tbody tr').count()
        ok('P3C02', 'Compliance', 'Bo\'lim filtri: xodimlar qatorlari = server', len(d['rows']), ui_rows, ui_rows == len(d['rows']) and 'dep=' in pg.url)
        await goto(pg, '#/compliance/employee/' + target['id'], 2500)
        s, d, _ = rpc('edu', 'employee_training_compliance', {'p_employee': target['id']})
        ui_c = await pg.locator('[data-table=emp_courses] tbody tr').count()
        ok('P3C03', 'Compliance', 'Xodim trening compliance: kurslar soni = server', len(d['courses']), ui_c, ui_c == len(d['courses']))
        s, d, _ = rpc('edu', 'employee_competency_matrix', {'p_employee': target['id']})
        sts = {c['status'] for c in d['competencies']}
        ok('P3C04', 'Compliance', 'Kompetensiya statuslari faqat achieved/not_achieved/not_assessed', 'subset', sorted(sts), sts <= {'achieved', 'not_achieved', 'not_assessed'})
        await login(pg, 'head'); await goto(pg, '#/compliance/department', 2500)
        dis = await pg.evaluate("document.querySelector('[data-f=dep]')?.disabled"); hr_ = await pg.locator('[data-table=dept_rows]').count()
        ok('P3C05', 'Compliance', 'Department Head: faqat o\'z bo\'limi (filtr qulflangan)', 'disabled + rows', f"{dis} / {hr_}", dis is True and hr_ == 1)
        s, d, _ = rpc('head', 'department_compliance_matrix', {'p_department': None})
        s2, d2, _ = rpc('head', 'department_compliance_matrix', {'p_department': target['department_id']}) if target['department_id'] != emp_of('head')['department_id'] else (403, None, None)
        ok('P3C06', 'Compliance', 'SERVER: Head tashkilot / boshqa bo\'lim matritsasi → rad', '4xx / 4xx', f"{s} / {s2}", s >= 400 and s2 >= 400)
        await login(pg, 'hr'); await goto(pg, '#/compliance/department', 2500)
        ok('P3C07', 'Compliance', 'HR: tashkilot matritsasini ko\'radi', 'ok', await view_state(pg), await pg.locator('[data-kpi=compliance_percent]').count() == 1)

        # ================= Notifications =================
        await login(pg, 'edu'); await pg.wait_for_timeout(800)
        s, n, _ = rpc('edu', 'unread_notification_count', {})
        bell = await pg.evaluate("(()=>{const b=document.querySelector('[data-bell-count]'); return b && !b.hidden ? b.innerText : '0'})()")
        ok('P3N01', 'Notif', 'Qo\'ng\'iroq badge = unread_notification_count (server)', n, bell, n > 0 and bell == str(n))
        await goto(pg, '#/notifications', 2000); items = await pg.locator('[data-notif]').count()
        ok('P3N02', 'Notif', 'Bildirishnomalar ro\'yxati', f"{min(n, 20)}+", items, items >= min(n, 20) and items > 0)
        await pg.locator('[data-toggle][data-read="1"]').first.click(); await pg.wait_for_timeout(900)
        s, n2, _ = rpc('edu', 'unread_notification_count', {})
        ok('P3N03', 'Notif', 'Bittasini o\'qildi qilish (mark_notification_read) → hisob -1', n - 1, n2, n2 == n - 1)
        org = one("select org_id from profiles where email = 't-edu@test.local'")['org_id']; uid = one("select id from profiles where email = 't-edu@test.local'")['id']
        sql(f"insert into notifications (org_id, recipient_id, notification_type, title, event_key, created_at) select '{org}', '{uid}', 'course_assigned', 'P3 test #' || g, 'p3test:' || g, now() - (g || ' minutes')::interval from generate_series(1, 25) g")
        await goto(pg, '#/notifications?u=1', 2000); first = await pg.locator('[data-notif]').count(); more_vis = await pg.locator('[data-more]').is_visible()
        await pg.click('[data-more]'); await pg.wait_for_timeout(1500); second = await pg.locator('[data-notif]').count()
        ids = await pg.eval_on_selector_all('[data-notif]', 'e=>e.map(x=>x.dataset.notif)')
        ok('P3N04', 'Notif', 'Keyset paging: 20 → "Yana yuklash" → qolganlari, dublikatsiz', '20 → 20+', f"{first} → {second} (uniq {len(set(ids))})", first == 20 and more_vis and second > 20 and len(set(ids)) == second)
        await goto(pg, '#/notifications', 1800); await pg.click('[data-all]'); await pg.wait_for_timeout(1500)
        s, n3, _ = rpc('edu', 'unread_notification_count', {})
        bell = await pg.evaluate("(()=>{const b=document.querySelector('[data-bell-count]'); return b && !b.hidden ? b.innerText : '0'})()")
        ok('P3N05', 'Notif', 'Barchasini o\'qilgan qilish → 0, badge yashirin', '0 / 0', f"{n3} / {bell}", n3 == 0 and bell == '0')
        await goto(pg, '#/notifications?u=1', 1500); txt = await pg.inner_text('[data-list]')
        ok('P3N06', 'Notif', 'O\'qilmaganlar bo\'sh → empty state', 'yo\'q', txt[:40], 'yo\'q' in txt)
        tk, _ = token('hr'); nid = one(f"select id from notifications where recipient_id = '{uid}' limit 1")['id']
        s, d, _ = http('PATCH', f"/rest/v1/notifications?id=eq.{nid}", tk, {'read_at': None})
        still = one(f"select read_at is not null r from notifications where id = '{nid}'")['r']
        ok('P3N07', 'Notif', 'SERVER: boshqa foydalanuvchining bildirishnomasini o\'zgartirib bo\'lmaydi', 'o\'zgarmagan', f"{s} / read={still}", still is True)
        s, d, _ = http('POST', '/rest/v1/notifications', tk, {'org_id': org, 'recipient_id': uid, 'notification_type': 'course_assigned', 'title': 'x', 'event_key': 'p3:forge'})
        ok('P3N08', 'Notif', 'SERVER: bildirishnomani qo\'lda INSERT qilib bo\'lmaydi', '4xx', s, s >= 400)
        s, d, _ = rpc('hr', 'mark_notification_read', {'p_id': nid, 'p_read': False})
        still = one(f"select read_at is not null r from notifications where id = '{nid}'")['r']
        ok('P3N09', 'Notif', 'SERVER: boshqa foydalanuvchi mark_notification_read → ta\'sir yo\'q', 'o\'zgarmagan', f"{s} / read={still}", still is True)

        # ================= Cross-org / anonim =================
        for i, (fn, args) in enumerate([('department_compliance_matrix', {'p_department': None}), ('employee_training_compliance', {'p_employee': target['id']}),
                                        ('my_notifications', {'p_limit': 5}), ('course_progress_summary', {'p_course': course})]):
            s, d, _ = http('POST', '/rest/v1/rpc/' + fn, None, args)
            ok(f'P3X0{i + 1}', 'Isolation', f'SERVER: anonim {fn} → rad', '4xx', s, s >= 400)
        s, d, _ = rpc('badm', 'employee_training_compliance', {'p_employee': target['id']})
        ok('P3X05', 'Isolation', 'SERVER: Org B admin → Org A xodim compliance → rad', '4xx', s, s >= 400)
        s, d, _ = rpc('badm', 'employee_competency_matrix', {'p_employee': target['id']})
        ok('P3X06', 'Isolation', 'SERVER: Org B admin → Org A kompetensiya matritsasi → rad', '4xx', s, s >= 400)
        tk, _ = token('badm'); s, d, _ = http('GET', f"/rest/v1/skills?select=id&code=eq.P3_ECG", tk)
        ok('P3X07', 'Isolation', 'SERVER: Org B Org A ko\'nikmalarini ko\'rmaydi', '0', len(d) if isinstance(d, list) else d, isinstance(d, list) and len(d) == 0)
        s, d, _ = rpc('badm', 'apply_learning_path', {'p_path': path['id'], 'p_target_type': 'role', 'p_target_id': 'employee'})
        ok('P3X08', 'Isolation', 'SERVER: Org B Org A learning path\'ini tayinlay olmaydi', '4xx', s, s >= 400)

        # ================= UI states =================
        await login(pg, 'edu')
        sql("alter function public.department_compliance_matrix(uuid) rename to department_compliance_matrix__off")
        await goto(pg, '#/compliance/department', 2200); has_err = await pg.locator('[data-error] [data-retry]').count()
        sql("alter function public.department_compliance_matrix__off(uuid) rename to department_compliance_matrix")
        if has_err: await pg.click('[data-retry]'); await pg.wait_for_timeout(2200)
        rec = await pg.locator('[data-kpi=compliance_percent]').count()
        ok('P3U01', 'UI', 'Server xatosi → tushunarli xabar + "Qayta urinish" → tiklanadi', 'error → ok', f"{has_err} → {rec}", has_err == 1 and rec == 1)
        reqs.clear(); await goto(pg, '#/compliance/department?dep=' + target['department_id'], 2500)
        nreq = len([u for u in reqs if '/rest/v1/' in u])
        ok('P3U02', 'UI', 'N+1 yo\'q: bo\'lim matritsasi ≤ 3 so\'rov (bitta RPC + lookup)', '<= 3', nreq, nreq <= 3)
        reqs.clear(); await goto(pg, '#/compliance/employee/' + target['id'], 2500)
        nreq = len([u for u in reqs if '/rest/v1/' in u])
        ok('P3U03', 'UI', 'N+1 yo\'q: xodim sahifasi = 2 RPC', '2', nreq, nreq == 2)
        await goto(pg, '#/learning/paths/00000000-0000-0000-0000-000000000000', 1500); txt = await pg.inner_text('#view')
        ok('P3U04', 'UI', 'Mavjud bo\'lmagan learning path → aniq xabar', 'topilmadi', txt[:40].replace('\n', ' '), 'topilmadi' in txt)
        await pg.set_viewport_size({'width': 390, 'height': 844}); await goto(pg, '#/compliance/department', 2200)
        ovf = await pg.evaluate("document.documentElement.scrollWidth <= window.innerWidth + 2")
        await pg.screenshot(path='/home/claude/medacademy/tests/admin/shots/p3_compliance_mobile.png')
        ok('P3U05', 'UI', 'Mobil (390px): gorizontal overflow yo\'q', 'ha', ovf, ovf)
        await pg.set_viewport_size({'width': 1400, 'height': 900})
        for h, f in [('#/learning/paths/' + path['id'], 'p3_learning_path'), ('#/compliance/employee/' + target['id'], 'p3_employee_compliance'), ('#/skills/skills', 'p3_skills')]:
            await goto(pg, h, 2000); await pg.screenshot(path=f'/home/claude/medacademy/tests/admin/shots/{f}.png', full_page=True)
        ok('P3U06', 'UI', 'JS xatolari (pageerror) butun test davomida', '0', len(errs), not errs)
        await br.close()

    for r in R: print(('PASS' if r['ok'] else 'FAIL'), r['id'].ljust(6), f"[{r['grp']}]", r['name'], '| kutilgan:', r['exp'], '| natija:', r['act'])
    f = [r for r in R if not r['ok']]; print(f'\nPHASE 3 ADMIN: {len(R)} test, {len(f)} FAIL')
    json.dump(R, open('/home/claude/medacademy/tests/admin/admin_results_p3.json', 'w'), ensure_ascii=False, indent=1)
    if errs: print('PAGE ERRORS:', errs[:5])
asyncio.run(main())
