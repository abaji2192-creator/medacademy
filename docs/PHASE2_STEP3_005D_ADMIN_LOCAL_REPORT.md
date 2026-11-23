# MedAcademy — Phase 2 STEP 3: 005d Security Hardening + Admin Panel (lokal build)

**Hisobot sanasi:** 2026-11-23

**Holat: LOCAL + STAGING PASS.** Production'ga hech narsa yozilmagan, deploy qilinmagan.

**Production holati** (o'zgarishsiz):
- Migratsiyalar 001…005c.
- Commit `d711736`.
- Xodim ilovasi live build sha1: `e8dc98a4…` — aynan shu.

---

## 1. 005d SQL files

| Fayl | Vazifasi |
|---|---|
| `backend/migration-005d/005d_security_hardening.sql` | **Migratsiya.** Bitta tranzaksiya, idempotent, additive. DROP TABLE / TRUNCATE / DELETE / data migration yo'q. |
| `005d_01_backup.sql` | Staging: barcha public jadvallarning to'liq nusxasi. Qo'shimcha snapshot'lar: ustun, constraint, indeks, policy, funksiya (ta'rif + EXECUTE), trigger, grant, default privileges. |
| `005d_03_verify.sql` | Holat tekshiruvi (faqat SELECT), natija `HARDENED` yoki `ORIGINAL`. Backup bilan solishtiradi: ma'lumot md5, ACL, constraint, policy. |
| `005d_04_tests.sql` | Staging testlari: 54 test, oxirida `ROLLBACK`. |
| `005d_05_regression_005.sql` | 005 production regressiyasi: 26 test, `ROLLBACK`, 005d qo'llangan holatda. |

**Migratsiya mazmuni:**

- **A1. CASCADE → RESTRICT.** 6 ta FK: `profiles_id_fkey`, `docs_owner_fkey`, `exam_attempts_user_id_fkey`, `certificates_user_id_fkey`, `attempt_resets_user_id_fkey`, `exam_configs_course_id_fkey`.
- **A1b. Lifecycle "Deactivate > Delete".**
  - `profiles_status_check` ga `inactive` va `deactivated` qiymatlari qo'shildi. Superset, mavjud qatorlar o'zgarmaydi.
  - `my_role()` faqat `active` akkaunt uchun rol qaytaradi. Shu sababli inactive/deactivated akkauntning barcha RLS va RPC huquqlari avtomatik yopiladi.
  - Yangi RPC `set_employee_status(p_employee, p_status, p_reason)`:
    - ruxsat tekshiradi: `employee.deactivate` / `employee.edit`;
    - tashkilot izolyatsiyasi;
    - o'z akkauntini o'zgartirib bo'lmaydi;
    - HR Super Admin holatini o'zgartira olmaydi;
    - Deactivated akkauntni faqat Super Admin qayta faollashtiradi;
    - oxirgi faol Super Admin himoyalangan;
    - sabab majburiy;
    - server-side audit yozadi (`employee.status_*`, sabab bilan).
- **A2–A4. Funksiya EXECUTE huquqlari** kategoriyalar bo'yicha (6-bo'lim):
  - `anon` uchun faqat `verify_certificate`;
  - kelajakdagi funksiyalar uchun default privileges'dan `anon` va `PUBLIC` olib tashlandi.
- **C. Tarixiy yozuvlar o'zgarmas** (trigger):
  - Sertifikat: ism, lavozim, kurs, ball, sana, urinish o'zgarmaydi; DELETE yo'q. Revoke mumkin, lekin qaytarilmaydi, birinchi revoke yozuvi saqlanadi.
  - Yakunlangan urinish: hech bir maydon o'zgarmaydi; DELETE yo'q.

## 2. 005d rollback SQL

`backend/migration-005d/005d_rollback.sql`. Migratsiyaning o'zi yaratgan snapshot'dan (`backup.security_pre005d`) ishlaydi.

- **Non-destructive:** jadval, ustun va qatorlarga tegmaydi.
- **Tiklaydi:** 6 ta FK (aynan asl ta'rif bilan), har bir funksiyaning anon/authenticated huquqlari, default privileges, `profiles_status_check`.
- **Olib tashlaydi:** 005d guard trigger'lari va `set_employee_status` (bular kod, ma'lumot emas).
- **Xavfsizlik:** biror akkaunt `inactive` yoki `deactivated` holatida bo'lsa, rollback **to'xtaydi** va hech narsani o'zgartirmaydi. Bu sinovdan o'tgan (R08).

## 3. Local test results

**PGlite** — haqiqiy Postgres, Supabase'ga o'xshash default privileges va `rls_auto_enable` event trigger bilan. Production bilan bir xil zanjir: 002/003 → 004 → 005 → 005d.

**`m005d_local.mjs`: 101 test, 0 FAIL.**

| Talab (A5) | Test | Natija |
|---|---|---|
| 1. Migration applies | D01 | PASS |
| 2. Rerun / idempotency (3 marta) | D02 | PASS (sxema va huquqlar o'zgarmaydi) |
| 3. Rollback | R01–R05, R07 | PASS: FK, CHECK, ACL, trigger, policy aynan 005d'dan oldingi holatda |
| 4. Rollback recovery | V01–V14 | PASS: qayta apply birinchi apply bilan aynan bir xil |
| 5. Existing data preserved | D03, R06, V14, F04 | PASS: 43 jadval, qator soni + md5, 0 farq |
| 6. Target 6 FK CASCADE = 0 | D05–D07 | PASS (public'da jami CASCADE ham 0) |
| 7. RESTRICT ishlaydi | F01–F03 | PASS: tarixi bor auth user va exam config'li kursni o'chirib bo'lmaydi |
| 8. Ruxsatsiz EXECUTE rad etiladi | G01–G17 | PASS |
| 9. Ilova funksiyalari ishlaydi | E02–E07, E15–E19 | PASS |
| 10. Anonim ommaviy tekshiruv | E13–E14, C02–C03 | PASS (faqat minimal maydonlar) |
| 11. Employee flow | E02–E08 | PASS: start → save → submit → 100% → sertifikat → review |
| 12. Admin flow | E15–E19 | PASS |
| 13. Cross-org rad etiladi | E20–E22, L04 | PASS |
| 14. Answer key leakage | E04, E09–E12, G01–G02 | PASS (0) |
| Qo'shimcha: tarixiy yaxlitlik | H01–H07 | PASS |
| Qo'shimcha: lifecycle va sertifikat | L01–L15, C01–C05 | PASS |

**Eligibility fixture.** Production'da yaroqli savol 0 ta. Shuning uchun test ichida nazoratli fixture yaratildi: ETHICS+COMM savollari "review'dan o'tgan" deb belgilandi (faqat test bazasida, 23 savol). Production ma'lumotiga tegilmadi.

## 4. Staging test results

Loyiha: `medacademy-staging` (`zwzxyikocqxbeyejeyga`). Ketma-ketlik talabdagidek:

| # | Qadam | Natija |
|---|---|---|
| 1–3 | Full backup + schema/policy/function/trigger/grant/default-ACL snapshot | 43/43 jadval aynan (md5); 1508 qator; 97 policy, 69 funksiya, 58 anon-exec, 75 trigger |
| — | Verify (oldin) | `ORIGINAL`: CASCADE 6, anon-exec 58, diff 0 |
| 4 | 005d apply (+ qayta apply, idempotency) | OK. CASCADE 0, RESTRICT 6, anon-exec 1 (`verify_certificate`) |
| — | Verify | `HARDENED`, `data_tables_changed = 0`, `policy_diff = 0` |
| 5 | Tests #1 | **54/54 PASS** |
| 6 | Rollback | OK. CASCADE 6, anon-exec 58 |
| — | Verify | `ORIGINAL`, **acl_diff = 0, constraint_diff = 0, policy_diff = 0, data = 0** — aynan tiklandi |
| 7 | Recovery (qayta apply) | OK |
| 8 | Tests #2 | **54/54 PASS** |
| — | 005 regressiyasi (26 test) | **26/26 PASS** (pastdagi izohga qarang) |
| — | Verify (yakuniy) | `HARDENED`, ma'lumot o'zgarmagan |

Staging hozir 005d qo'llangan holatda qoldi.

**Izoh — X26 testi:**
- Birinchi ishga tushirishda X26 FAIL bo'ldi (25/26).
- Sabab: staging'dagi `pre005` backup 005 recovery siklidan keyin olingan va unda `question_versions` ustuni bor. X26 esa urinishni shu ustunsiz solishtiradi.
- Ma'lumot aynanligi alohida tasdiqlandi: urinish pre005d backup bilan `true`; pre005 bilan farq qiladigan kalitlar `null`.
- Staging varianti ikkala tomonni `question_versions`'siz solishtiradigan qilindi va natija 26/26 bo'ldi.
- Production fayli (`24_regression_005.sql`) o'zgarmadi.
- 005d bunga aloqador emas.

**Topilma:** production va staging'da Supabase'ning `rls_auto_enable` event trigger funksiyasi bor (69-funksiya). U "trigger" kategoriyasiga kiritildi va EXECUTE huquqi yopildi. Lokal test tasdiqladi: event trigger EXECUTE huquqisiz ham ishga tushadi.

## 5. Regression results

| Suite | Natija |
|---|---|
| 005 testlari (005d bilan) | **114/114 PASS** |
| 004 testlari (005 setup + 005d bilan) | **50/50 PASS** |
| Phase 1 SQL oqimlari (004+005+005d bilan) | **32/32 PASS** |
| 005 production regressiyasi (lokal, 005d bilan) | **26/26 PASS** |
| 005 production regressiyasi (staging, 005d bilan) | **26/26 PASS** |
| 005 verify (lokal, 005d'dan keyin) | **28/28 PASS** |
| Xodim ilovasi live build | o'zgarmagan (sha1 `e8dc98a4`) |

## 6. Function privilege matrix

To'liq JSON: `backend/migration-005d/tests/fn_matrix.json`.

**Belgilar:** "anon+auth" — ikkalasi EXECUTE qila oladi; "auth" — faqat authenticated; "—" — hech kim (owner va service_role saqlanadi).

**Public-safe**

| Funksiya | Turi | 005d'dan oldin | 005d'dan keyin | Kim chaqiradi | Qaytaradi | Xavf |
|---|---|---|---|---|---|---|
| `verify_certificate(code)` | definer | anon+auth | anon+auth | QR / ommaviy tekshiruv | id, name, kurs, lavozim, bo'lim, sana, holat | Past (minimal maydonlar) |

**Employee RPC** — ichida `auth.uid()` va o'z doirasi tekshiriladi.

| Funksiya | Turi | Oldin | Keyin | Kim chaqiradi | Qaytaradi | Xavf |
|---|---|---|---|---|---|---|
| `start_exam(...)` | definer | anon+auth | auth | Xodim (faol) | Savollar, javob kalitisiz | O'rta → past |
| `save_answers(attempt, answers)` | definer | anon+auth | auth | Urinish egasi | boolean | Past |
| `submit_exam(attempt, answers)` | definer | anon+auth | auth | Urinish egasi | Natija, sertifikat; javoblar faqat yakunlangandan keyin | O'rta → past |
| `get_attempt_review(attempt)` | definer | anon+auth | auth | Urinish egasi yoki o'z tashkilotidagi admin/instruktor | Yakunlangan urinish + savol, javob, izoh | O'rta (ichki tekshiruv bor) |
| `question_meta()` | definer | anon+auth | auth | Faol foydalanuvchi | Faqat yaroqli savollar meta'si (javobsiz) | Past |

**Role / permission RPC**

| Funksiya | Turi | Oldin | Keyin | Kim chaqiradi | Qaytaradi | Xavf |
|---|---|---|---|---|---|---|
| `admin_reset_attempts(user, course)` | definer | anon+auth | auth | SA, EM, instruktor (o'z kursi) | boolean | O'rta (ichki tekshiruv bor) |
| `revoke_certificate(code)` | definer | anon+auth | auth | SA, EM, o'z tashkiloti | boolean | O'rta (ichki tekshiruv bor) |
| `import_research_result(result, type)` | definer | auth | auth | `research.run` | uuid; manba `unverified` | Past |
| `set_employee_status(emp, status, reason)` **(yangi)** | definer | — | auth | HR / SA (`employee.deactivate` / `employee.edit`) | Holatlar | O'rta (ichki tekshiruv + audit) |

**RLS helper'lar** — RLS policy'lar ularni chaqiradi; olib tashlansa RLS buziladi.

| Funksiya | Turi | Oldin | Keyin | Qaytaradi | Xavf |
|---|---|---|---|---|---|
| `my_org()` | definer | anon+auth | auth | O'z tashkiloti id | Past |
| `my_role()` | definer | anon+auth | auth | O'z roli (faqat active) | Past |
| `my_dept()` | definer | anon+auth | auth | O'z bo'limi | Past |
| `my_department_id()` | definer | anon+auth | auth | O'z bo'limi id | Past |
| `my_employee_id()` | definer | anon+auth | auth | O'z xodim id'si | Past |
| `has_perm(p)` | definer | anon+auth | auth | O'z ruxsati (boolean) | Past |
| `is_course_instructor(c)` | definer | anon+auth | auth | boolean | Past |
| `can_see_question(q)` | definer | anon+auth | auth | boolean | Past |
| `can_see_question_row(...)` | definer | anon+auth | auth | boolean | Past |
| `can_see_source(org, scope)` | definer | anon+auth | auth | boolean | Past |

**Internal / server-only** — faqat definer RPC yoki trigger ichidan chaqiriladi. Hammasida 005d'dan keyin huquq "—".

| Funksiya | Turi | Oldin | Qaytaradi / izoh | Xavf (oldin → keyin) |
|---|---|---|---|---|
| `_q_full(q)` | definer | **anon+auth** | Savol + javob + izoh + `_q_refs` orqali **istalgan savol ID'si bo'yicha manbalar** | **Yuqori → yopiq** |
| `_q_public(q, ord)` | invoker | anon+auth | Javobsiz savol | Past → yopiq |
| `_attempt_out(a)` | invoker | anon+auth | Urinish formati | Past → yopiq |
| `_attempt_payload(a)` | invoker | anon+auth | Urinish formati | Past → yopiq |
| `_cert_out(c)` | invoker | anon+auth | Sertifikat formati | Past → yopiq |
| `_norm(t)` | invoker | anon+auth | Matn yordamchisi | Past → yopiq |
| `_safe_date(t)` | invoker | anon+auth | Sana yordamchisi | Past → yopiq |
| `_default_evidence_tier(t)` | invoker | anon+auth | Tier yordamchisi | Past → yopiq |
| `guard_evidence_classification_origin_ok()` | invoker | anon+auth | Ichki flag | Past → yopiq |
| `is_api_request()` | invoker | anon+auth | Ichki flag | Past → yopiq |
| `_q_exam_eligible(q)` | definer | auth | Yaroqlilik hisobi | Past → yopiq |
| `_q_is_clinical(q)` | definer | auth | Klinik/klinik emas | Past → yopiq |
| `_grade`, `_q_at`, `_q_refs`, `recompute_question_evidence`, `refresh_evidence_freshness`, `mark_overdue_assignments`, `seed_org_defaults`, `seed_org_defaults_005` | definer/invoker | — | 004/005 da yopilgan edi | Yopiq qoldi |

**Trigger / event trigger** — 32 ta funksiya, jumladan Supabase'ning `rls_auto_enable` funksiyasi va 005d'ning 2 ta yangi guard'i. 005d'dan keyin hammasida huquq "—". Bu funksiyalarni to'g'ridan-to'g'ri chaqirib bo'lmaydi, trigger esa EXECUTE huquqisiz ham ishga tushadi.

**Natija:** anon-executable funksiyalar **58 → 1**. Tasniflanmagan funksiya 0 ta.

## 7. CASCADE → RESTRICT result

| FK | Oldin | Keyin | Sinov |
|---|---|---|---|
| `profiles.id → auth.users` | CASCADE | RESTRICT | Profili bor userni o'chirish → rad (F02, staging F02) |
| `docs.owner → auth.users` | CASCADE | RESTRICT | ✔ |
| `exam_attempts.user_id → auth.users` | CASCADE | RESTRICT | Tarixi bor super admin → rad (F01) |
| `certificates.user_id → auth.users` | CASCADE | RESTRICT | ✔ |
| `attempt_resets.user_id → auth.users` | CASCADE | RESTRICT | ✔ |
| `exam_configs.course_id → courses` | CASCADE | RESTRICT | Exam config'li kurs → rad (F03) |

- Public sxemadagi jami CASCADE FK: **0**.
- Supabase Dashboard'dagi "Delete user" endi xodim tarixini jimgina o'chirmaydi: amal FK xatosi bilan to'xtaydi.
- Lifecycle: Active → Inactive → Deactivated (`set_employee_status`).
- Tarixi yo'q texnik akkauntni hard delete qilish alohida siyosat sifatida keyinroq ko'rib chiqiladi.

## 8. Certificate immutability result

- Sertifikat o'z nusxasini saqlaydi: ism, lavozim, bo'lim, kurs, ball, sana, urinish. Xodim profilining holati yoki ismi o'zgarsa, sertifikat matni o'zgarmaydi (C01–C03, staging C01; Admin Panel C03).
- Trigger sertifikat maydonlarini o'zgartirishni, DELETE'ni va bekor qilingan sertifikatni qayta tiklashni rad etadi — hatto SQL Editor yoki service role orqali ham (H01–H03, C05).
- `revoke` ishlaydi. Qayta revoke qilinsa, birinchi "kim/qachon" yozuvi saqlanadi (C04).
- Avtomatik "Anonimlashtirilgan" yo'q. Anonimlashtirish alohida huquqiy/maxfiylik siyosati sifatida keyinroq ko'riladi.

## 9. Admin Panel route map

**Alohida sahifa: `admin.html`.** Xodim ilovasiga (`index.html`) tegilmagan.

| Route | Bo'lim | Ko'rinish sharti (UI) |
|---|---|---|
| `#/` | Dashboard (10 KPI + evidence lifecycle) | Admin rollar |
| `#/employees`, `#/employees/:id?tab=` | Xodimlar + profil (8 tab), faqat Deactivate | `employee.view` yoki department_head |
| `#/org/departments`, `#/org/positions`, `#/org/specialties` | Tuzilma, faqat Inactive (DELETE yo'q) | `department.view` / `*.manage` |
| `#/edu/courses`, `#/edu/courses/:id` | Kurs → modul → dars, status workflow | `course.edit` / `assignment.view` / instruktor |
| `#/edu/assignments`, `#/edu/instructors` | Tayinlash va instruktorlar | xuddi shu |
| `#/questions`, `#/questions/new`, `#/questions/:id?tab=` | Savollar banki: 9 status tab, 7 filtr; savol kartasi 7 tab | `question.view` |
| `#/evidence/queue` | Review Queue: 9 filtr, KPI, tartiblash | `evidence.review` yoki `question.review` |
| `#/evidence/review/:id` | Review workspace: Question → Evidence → Claim → Review → Decision | xuddi shu |
| `#/evidence/library`, `/new`, `/:id` | Evidence Library + manba kartasi (verify, superseded, retracted) | `evidence.view` |
| `#/exams/configs`, `#/exams/attempts`, `#/exams/results` | Imtihon sozlamalari (yaroqlilik holati), urinishlar, natijalar | `exam.view` |
| `#/audit` | Audit Logs (faqat server jurnali) | `audit.view` |

## 10. Admin Panel component map

```
admin.html
  vendor/supabase.js, js/config.js (publishable key; maxfiy kalit build'da va runtime'da bloklanadi)
  js/admin/ui.js           — esc(), badge(), table(), pager(), skeleton/empty/error/denied holatlari, dialog (tasdiq, sabab maydoni), toast, debounce; route registri
  js/admin/api.js          — supabase-js: list (filtr, qidiruv, server-side range + count), count, get, insert, update, remove, rpc; xatolarni tushunarli xabarga aylantiradi; sessiya tugaganda login ekrani
  js/admin/perms.js        — role_permissions'dan o'z ruxsatlari; can(), section(); admin rollar
  js/admin/pages_core.js   — listPage (filtr + debounce + pagination), lookup cache, Dashboard, Audit Logs
  js/admin/pages_questions.js — Savollar banki, Yangi savol (Draft), savol kartasi (Question / Options / Correct Answer / Explanation / Evidence / Review / Version History), Publish/Deprecate
  js/admin/pages_evidence.js  — Review Queue, Review workspace, Evidence Library, manba kartasi
  js/admin/pages_org.js    — Xodimlar ro'yxati va profili (Deactivate RPC), Bo'limlar / Lavozimlar / Mutaxassisliklar
  js/admin/pages_edu.js    — Kurslar, tayinlashlar, instruktorlar, imtihon sozlamalari, urinishlar, natijalar
  js/admin/main.js         — login, logout, sessiya muddati, hash router, layout (sidebar, mobil menyu)
```

**Bundle xavfsizligi** (`build.py` tekshiradi):
- savollar banki, `SEED.QUESTIONS` va `Q001` matni yo'q;
- `sb_secret_` yoki `service_role` kaliti yo'q.

## 11. Permission matrix

Server ruxsatlari 004/005 `role_permissions` jadvalidan olinadi; 005d ularni o'zgartirmagan. Admin Panel shu ruxsatlarni ko'rsatadi:

| Bo'lim / amal | SA | HR | Edu Mgr | Instructor | Dept Head | Med Reviewer | Content Author | Employee |
|---|---|---|---|---|---|---|---|---|
| Admin Panel'ga kirish | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | — (no-admin ekrani) |
| Xodimlar | ✅ | ✅ | 👁 | — | 🔸 o'z bo'limi | — | — | — |
| Deactivate / reactivate | ✅ (+deactivated'ni tiklash) | ✅ (deactivated'ni tiklay olmaydi) | — | — | — | — | — | — |
| Tuzilma | ✅ | ✅ | 👁 | — | — | — | — | — |
| Kurslar va status | ✅ | — | ✅ | 🔸 | — | — | — | — |
| Savollar banki | ✅ | — | ✅ | 🔸 o'z kursi | — | 🔸 tayinlangan | 🔸 | — |
| Correct Answer | ✅ | — | ✅ | 🔸 | — | 🔸 | 🔸 | — |
| Evidence Library / manba qo'shish | ✅ | — | ✅ | ✅ | — | ✅ | ✅ | — |
| Verify | ✅ | — | ✅ | — | — | ✅ | — | — |
| Evidence review | ✅ | — | ✅ | — | — | ✅ | — | — |
| Medical review | ✅ | — | ✅ | — | — | ✅ | — | — |
| Publish / Deprecate | ✅ | — | ✅ | — | — | ✅ | — | — |
| Imtihon sozlamalari | ✅ | 👁 | ✅ | 👁 | — | — | — | — |
| Audit Logs | ✅ | — | — | — | — | — | — | — |

Har bir "—" va 🔸 cheklov server tomonida ham tekshirildi (S01–S12, O01–O02, P17–P18).

## 12. Evidence Review workflow

Admin Panel'da UI orqali to'liq sinovdan o'tgan oqim (W01–W11, E08–E09):

1. **Manba qo'shish** — har doim `Unverified`, origin `manual`.
2. **Verify** — faqat `evidence.verify` ruxsati bilan, inson tasdig'i (checkbox). `verified_by` ni server yozadi. Ruxsatsiz rol REST orqali ham tasdiqlay olmaydi.
3. **Savolga dalil va claim bog'lash** — supporting claim majburiy.
4. **Evidence review** — Approve uchun 3 ta checklist belgisi majburiy. Shundan keyin `evidence_status = current` bo'ladi; uni faqat server o'zgartiradi.
5. **Medical review'ga yuborish** — tayinlov yaratiladi; reviewer faqat tayinlangan savollarni ko'radi.
6. **Medical review → Approve** — medical reviewer tomonidan.
7. **Publish:**
   - medical review'siz klinik savol nashri server tomonidan rad etildi;
   - medical review'dan keyin nashr o'tdi va server eligibility +1 bo'ldi.
8. **Monitor:**
   - "Mark outdated" → Review Required, yaroqsiz;
   - manba Retracted → bog'langan savollar avtomatik Review Required, yaroqsiz.

**Review Queue filtrlari:** Unknown, Review Required, Current, Review Due, Outdated, Superseded, Conflicting, Retracted, Unverified. Har birida KPI soni bor.

**Soxta ma'lumot yo'q:** DOI, PMID, guideline yoki evidence status o'ylab topilmaydi. Evidence level ko'rsatilmagan bo'lsa "Unknown", tasdiqlanmagan manba "Not verified" deb chiqadi.

## 13. Question workflow

- **Holatlar** (005c, o'zgarishsiz): draft → evidence_review → instructor_review → approved → published → review_required / deprecated / archived. Qo'shimcha: `draft_status` — v1 nashrda qoladi, v2 review'dan o'tadi.
- **Yangi savol** har doim Draft + Unknown evidence holatida yaratiladi (server majburlaydi).
- **Savol kartasi:**
  - Correct Answer va Explanation alohida so'rov bilan, faqat tab ochilganda va ruxsatli rolga yuklanadi (Q01–Q03);
  - Version History'da versiyalar, nashr sanalari, nashrdagi evidence holati va almashtirilgan sana ko'rinadi.
- **Eligibility** faqat server tomonida hisoblanadi (`_q_exam_eligible` / `question_meta`):
  - Current → eligible;
  - Unknown, Review Due, Outdated, Superseded, Conflicting, Retracted manba, Review Required → not eligible (E01–E09).
- **Exam publish:** imtihon faqat yetarli yaroqli savol bo'lganda ishlaydi.
  - Admin Panel'da "Tayyor / Bloklangan (yaroqli X/Y)" holati ko'rsatiladi.
  - Server-side `start_exam` baribir tekshiradi.
- **Production'dagi savol statuslari o'zgartirilmadi** (Part D). Reopen strategiyasi uchun Dashboard'da ustuvorlik eslatmasi bor: Ethics → Communication → Reception → Sales.

## 14. Security test results

**Admin Panel: `admin_tests.py`, Playwright + Chrome, 85 test, 0 FAIL.** Mini-Supabase ishlatildi: PGlite + migratsiyalar 002…005d + haqiqiy RLS/trigger/RPC.

| Guruh | Testlar | Natija |
|---|---|---|
| Authentication: login, xato parol, refresh'da sessiya, logout, session expiry → login ekrani | A01–A05 | PASS |
| Authorization (7 rol + employee): sidebar, URL orqali kirish → denied, faqat o'qish rejimlari | P01–P20 | PASS |
| Server darajasi (UI chetlab, to'g'ridan-to'g'ri REST/RPC) | S01–S12 | PASS |
| Org izolyatsiya (10 jadval, yozish, UI) | O01–O03 | PASS |
| Javob kaliti sizib chiqishi (bundle, ro'yxat so'rovlari, tab, HR) | B01–B02, Q01–Q03 | PASS (0) |
| Evidence workflow (UI end-to-end) | W01–W11 | PASS |
| Eligibility (7 holat + UI qarorlari) | E01–E09 | PASS |
| Tarixiy yaxlitlik | H01 | PASS |
| Sertifikat yaxlitligi va Deactivate (Delete tugmasi yo'q) | C01–C06 | PASS |
| Audit (7 kritik amal) | U01–U07 | PASS |
| UI: empty, pagination, debounce, 404, mobil 390px, JS xatolari = 0 | Q10–Q15 | PASS |
| Regressiya: xodim ilovasi live build o'zgarmagan | B03 | PASS |

**005d xavfsizlik testlari:** lokal 101/101; staging 54/54 ×2.

## 15. Remaining migration requirements

| Talab | Hozir | Kerak |
|---|---|---|
| Savol o'zgarishi / publish / deprecate auditi | `question_versions` / `question_publications` bor, lekin `audit_logs` yozuvi yo'q (U08) | 006a |
| Kurs publish / archive auditi | Yo'q | 006a |
| Sertifikat revoke auditi | `revoked_by` / `revoked_at` bor, `audit_logs` yo'q | 006a |
| `profiles` o'zgarishlari (to'g'ridan-to'g'ri rol/holat o'zgarishi, eski HR tasdiq oqimi) | Yo'q (`set_employee_status` orqali o'tgan o'zgarish audit qilinadi) | 006a |
| Skills / amaliy assessment server jadvallari | docs'da | 006c |
| Notifications server jadvali | docs'da | 006c |
| Exam Builder (blueprint) | Yo'q | 006d |
| Dashboard aggregate RPC (katta tashkilotlar uchun) | count so'rovlari | 006b |
| Global evidence kutubxonasi uchun platform-admin | Faqat SQL | 006e |

## 16. Proposed 006 schema changes

Faqat taklif — 006 yaratilmagan. Har biri additive, idempotent va rollback skripti bilan.

- **006a Audit coverage.** `audit_row` trigger'lari quyidagi jadvallarga qo'shiladi:
  - `questions` — `answer` va `explanation` `new_value`'da maskalanadi, javob kaliti audit'ga tushmaydi;
  - `courses`, `exam_configs`;
  - `certificates` — faqat UPDATE/revoke;
  - `profiles` — rol, holat, org.
- **006b** `my_permissions()` RPC va `admin_dashboard_stats()` (bitta so'rovda KPI'lar, RLS doirasida).
- **006c** `skills`, `skill_assessments`, `practical_assessments`, `notifications` server jadvallari. docs'dan nazoratli ko'chirish alohida tasdiq bilan.
- **006d** `exam_blueprints`: modul, qiyinlik va mavzu bo'yicha taqsimot; `start_exam` integratsiyasi.
- **006e** Platform-admin roli va global evidence kutubxonasini boshqarish.
- **Ixtiyoriy:** texnik akkauntlar uchun nazoratli hard-delete siyosati (tarixi yo'q bo'lsa) va anonimlashtirish siyosati — huquqiy talab aniqlangandan keyin.

## 17. Git diff

`main...phase2-step3-005d-admin-local`:
- **6 commit oldinda, 0 orqada**;
- **28 fayl qo'shilgan, +5036 / −0**;
- hammasi `added` — mavjud fayl o'zgarmagan, `index.html` ga tegilmagan.

`main` = `d711736`, ya'ni GitHub Pages'dagi xodim ilovasi o'zgarmagan. Pull request ochilmagan.

```
backend/migration-005d/005d_security_hardening.sql, 005d_rollback.sql
backend/migration-005d/005d_01_backup.sql, 005d_03_verify.sql, 005d_04_tests.sql, 005d_05_regression_005.sql
backend/migration-005d/tests/m005d_local.mjs, staging005d_rehearsal.mjs, prod005d_regression.mjs, m005d_results.json, fn_matrix.json
admin-panel/admin.html, README.md, build.py, css/admin.css
admin-panel/js/admin/{ui,api,perms,pages_core,pages_questions,pages_evidence,pages_org,pages_edu,main}.js
admin-panel/tests/mock_supabase.mjs, admin_tests.py, smoke.py, admin_results.json
docs/PHASE2_STEP3_005D_ADMIN_LOCAL_REPORT.md   (shu hisobot — alohida commit)
```

Ko'rish: https://github.com/abaji2192-creator/medacademy/compare/main...phase2-step3-005d-admin-local

## 18. Git commit hash

Branch: `phase2-step3-005d-admin-local`.

| Commit | Mazmuni |
|---|---|
| `4116384` | feat: migration 005d security hardening (local+staging tested, NOT deployed) |
| `e2a0b95` | test: 005d local/staging test harnesses and results |
| `4bc3093` | feat: Admin Panel MVP (local build, NOT deployed) — admin.html, build |
| `909d275` | feat: Admin Panel MVP JS modules |
| `9065f4e` | feat: Admin Panel styles |
| **`a979d69`** | test: Admin Panel test matrix (85/85 PASS) — **kod uchun oxirgi commit** |
| (keyingi) | docs: shu hisobot |

## Explicit approval talab qilinadigan keyingi qadamlar

1. **005d production deploy.** Tartib: backup → precheck → apply → verify → regression → live smoke. Production'da `rls_auto_enable` bor; tasniflash uni qamrab oladi.
2. **Admin Panel deploy.** Ikkita savol:
   - `admin.html` GitHub Pages'ga qanday chiqariladi (public URL; ma'lumot faqat RLS orqali)?
   - Staging'da UI testi uchun parolli test akkauntlar yaratiladimi? Buni siz qilasiz yoki ruxsat berasiz.
3. **006a–006e** migratsiyalari (har biri alohida).
4. **Eski xodim ilovasidagi savol yaratish va tasdiqlash oqimini** Admin Panel'ga o'tkazish.

**TO'XTADIM.** Production'ga hech narsa yozilmadi.
