# MedAcademy — PRODUCTION DEPLOYMENT RESULT (006a + 006b + Admin Panel)

**Sana:** 2026-11-24, 14:29–14:40 UTC (19:29–19:40 Toshkent)

## Authorization

- Explicit approval: **PASS**
- Approval text: **DEPLOY TO PRODUCTION** (foydalanuvchi o'zi, 2026-11-24 19:26 Toshkent vaqtidan keyin — tanlov oynasida)

## Database

| Item | Result |
|---|---|
| Freeze check (SELECT) | PASS — STEP 7 baseline bilan aynan |
| Fayl yaxlitligi (SHA-256, fayl = SQL editor) | PASS — 60/61/62/63/64/65/66/54/55/56/rollback'lar |
| Backup (`60_backup_pre006`) | PASS — 43/43 jadval aynan, `mismatched = '-'`, 1 128 qator, 97 policy, 73 funksiya, 77 trigger, 119 FK, 43 RLS |
| Precheck (`61_precheck_006`) | PASS — `ok = true` |
| 006a apply (`60e978ad…`) | PASS |
| 006a tekshiruvi (`65_security_tests_006a`, ROLLBACK) | PASS — 83/83 |
| 006b apply (`c84e1638…`) | PASS |
| 006 verify (`64_verify_006`) | PASS — `ok = true` (ikki marta, aynan bir xil) |
| Xavfsizlik regressiyasi (ROLLBACK) | PASS — 006b 34/34, 005e 146/146, role matrix 62/62, 005 regression 26/26, 006a 83/83 (takroriy) |
| Tarixiy ma'lumot yaxlitligi | PASS — urinishlar / sertifikatlar / savollar / kurslar md5 = backup; fingerprint data_md5 o'zgarmagan |
| Test residue | 0 — verify oldin/keyin aynan; audit_logs 307 → 307; test identifikatorlari 0 |
| Rollback tayyorligi | PASS — `006b_rollback.sql` → `006a_rollback.sql` (staging'da sinovdan o'tgan), `backup.*_pre006` |

## Production holati (deploy'dan keyin)

| Band | Qiymat |
|---|---|
| 005e / 006a / 006b | 1 / 1 / 1 |
| courses / questions / exam_configs | 13 / 131 / 13 |
| attempts / certificates / profiles | 2 / 0 / 1 |
| audit_logs / attempt_resets | 307 / 0 |
| public jadvallar | 44 (43 + `attempt_reset_events`) |
| CASCADE | 0 |
| anon EXECUTE | faqat `verify_certificate` |
| fn_md5 (oldin → keyin) | `8bdab755ce579f860c0206805794841c` → `704c79d7506258f8178fc6b142a5bb3c` |
| policy_md5 (oldin → keyin) | `01080a074cdde90d754b266ceb4bc206` → `f27165f643c693164399f85a4ee65f51` (faqat `attempt_reset_events_select` qo'shildi; qolgan policy'lar aynan) |
| 006 trigger'lari | 13 |
| RECEPTION_START | communication |
| medical.review / MR publish | medical_reviewer (+ SA) / 0 |

## Xavfsizlik

RLS — mavjud policy'lar o'zgarmagan (+1 yangi); audit o'zgarmas; role escalation bloklangan; medical review faqat SA/MR; publish faqat SA/EM; course DELETE API orqali bloklangan; cross-org izolyatsiya — PASS (test to'plamlari).

Live anonim tekshiruv (publishable key bilan, production): `question_eligibility`, `admin_set_course_status`, `admin_set_profile_role` → 401; `audit_logs`, `attempt_reset_events` SELECT → 401; `courses` DELETE → 401; `verify_certificate` → 200.

Javob kaliti / service_role: Admin build'da yo'q (`SUPABASE_SERVICE_ROLE_KEY` 0, `answer_key` 0, `correct_answer` 0, JWT 0).

## Admin

| Band | Qiymat |
|---|---|
| Build | `admin.html` — SHA-256 `c37ccd47a9d1916b6f4a132ee4a193ca2ef701a1135aaf197b6cf80b3002d59e`, 363 840 B (live'dan qayta yuklab tekshirildi — aynan) |
| main commit | `01c6b63` (oldingi production: `0bd7c6c`) + migratsiya artefaktlari commit'lari |
| Deploy usuli | faqat `admin.html` main root'ga; admin branch to'liq merge qilinmadi (test fayllari / mock parollari production'ga chiqmasligi uchun) |
| Live URL | https://abaji2192-creator.github.io/medacademy/admin.html — login sahifasi yuklanadi, konsol xatosi yo'q |
| Xodim ilovasi | `index.html` sha1 `e8dc98a4` — o'zgarmagan (live'da tekshirildi) |

## Live UI

**BLOCKED — USER LOGIN REQUIRED.** Parol kiritilmadi. Foydalanuvchi admin.html'ga login qilgach, rollar bo'yicha smoke o'tkaziladi.

## Final status

**PRODUCTION DEPLOYMENT PARTIALLY COMPLETE — LIVE UI ACCEPTANCE BLOCKED**

(Database va Admin Panel deploy to'liq va tekshirilgan; faqat login bilan UI qabul testi qolgan.)
