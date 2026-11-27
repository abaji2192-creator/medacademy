# MedAcademy — Phase 3 STEP 9: Migration 007c (Skills & Competency)

**Holat:** 007c PRODUCTION DEPLOYMENT COMPLETE — 007c = 1, ALL GATES PASS (2026-11-27)
**STEP 9 (2026-11-26):** LOCAL + STAGING + PRODUCTION READ-ONLY REVIEW PASSED. **STEP 9b (2026-11-27):** foydalanuvchi "DEPLOY TO PRODUCTION" tasdig'i bilan production deploy — 8-bo'limga qarang.

## 1. Qamrov

| Obyekt | Tavsif |
|---|---|
| `skills` | Tashkilot ko'nikmalar katalogi: `code` tashkilot ichida unikal, `max_level` 1–10 (standart 5), holat `active` / `archived`. DELETE yo'q, arxivdan qayta faollashtirish yo'q, `max_level` mavjud baholashlardan pastga tushirilmaydi |
| `skill_assessments` | Faqat INSERT (UPDATE / DELETE / TRUNCATE guard bilan bloklangan). `assessment_seq` — bir tranzaksiyadagi baholashlar tartibi uchun |
| `competency_requirements` | Talab: nishon `department` / `position` / `specialty` / `role`, aniq bitta nishon; bir (ko'nikma, nishon) uchun bitta faol talab |
| Ruxsatlar | `skill.view`, `skill.manage`, `skill.assess`, `competency.manage` (kategoriya `skills`). EM — 4 tasi; department_head — view + assess; HR — view; instructor — view. SA — `has_perm` orqali hammasi. Yangi tashkilotlar uchun `org_skill_perms_007c_trg` |
| RPC | `upsert_skill`, `archive_skill`, `record_skill_assessment`, `set_competency_requirement`, `archive_competency_requirement`, `employee_competency_summary`, `department_competency_summary` |
| Audit | `skill.created/updated/archived`, `skill.assessment_created`, `competency_requirement.created/updated/archived` |

**Baholash qoidalari:** `skill.assess` kerak; rol SA / EM / department_head; bo'lim boshlig'i faqat o'z bo'limi xodimlarini baholaydi; o'zini baholash va nofaol xodimni baholash rad etiladi.
**Xulosa holatlari:** `achieved` / `not_achieved` / `not_assessed` / `not_required` (oxirgi baholash = `assessed_at desc, assessment_seq desc`).
**RLS:** faqat SELECT siyosatlari; yozuv faqat RPC orqali. `skill_assessments` ko'rinishi: o'zi; SA/EM/HR (`skill.view`); bo'lim boshlig'i — o'z bo'limi.

### Unumdorlik tuzatishi (STEP 9 davomida)
Dastlabki RLS siyosati har qatorda `_sk_can_view_employee_007c()` chaqirardi: 10 000 baholashda bo'lim boshlig'i SELECT p95 = **1423 ms**. Siyosat set-based qilindi (`(select my_org())`, `(select my_role())`, `(select has_perm(...))` InitPlan sifatida bir marta, bo'lim xodimlari `_sk_my_dept_employees_007c()` orqali): p95 = **4.6 ms** (lokal), **6.3 ms** (staging). `_sk_can_view_employee_007c` endi `internal` (authenticated uchun yopiq), `_sk_my_dept_employees_007c` — `rls_helper` (faqat joriy foydalanuvchi bo'limi xodim ID'larini qaytaradi).

## 2. Fayllar va SHA-256

| Fayl | SHA-256 |
|---|---|
| `migrations/007c_skills_competency.sql` = `production/93_apply_007c.sql` | `56ce1ed951877cce5c63800561c197282693a96015a552449ea5c6d342a365e6` |
| `migrations/007c_rollback.sql` = `production/99_rollback_007c.sql` | `d4e20d252fd104cc2f370dbe443fcfe8ab4bd83b2bf49f90f84f009188473caf` |
| `production/90_readonly_review_007c.sql` | `9157d5b60085a079e898b97ba009a7ea7fb7c9e7170837491124d6eac5612dba` |
| `production/91_backup_pre007c.sql` = `staging/007c_00_backup.sql` | `992fe9e11c7f7b06de2641128d085b26a42f626a5fcf61f8237c30012f05a96a` |
| `production/92_precheck_007c.sql` | `beae81a66db11c3eb6e5e6fe6cbe8df4aa20b960d2e79158a67f32a55ae0da6b` |
| `production/94_verify_007c.sql` | `881af28e636c0270fad62cf6634e9bb3773981150f370bfe7b7b9a9e6d76831c` |
| `staging/007c_02_tests.sql` | `7b75a3d319e78ca1a55afafe17e9a8219b8b0743b86ff22c95ea51520a35d7c2` |
| `production/95_security_tests_007c.sql` (vaqtinchalik @test.local muhit + staging to'plami, ROLLBACK) | `924ec8e6fc4b2210056d68293d354c7522827d6e193f6b24e7fcd29e3e9bd7e5` |
| `staging/007c_03_perf.sql` | `ea7badd76e43b91ed4a252a591226d45191b069970cf4e35061443b4f867b7d9` |
| `staging/007c_04_compare_pre.sql` | `86a5cc9a293736880022b7ec36bdf8b4153a38ff826891f596f4ee5bcaaf7717` |

Rollback 007c ma'lumotlari mavjud bo'lsa ishlamaydi (xavfsizlik to'xtatgichi); aks holda 007c obyektlari, 4 ruxsat va ularning `role_permissions` qatorlari, org triggeri o'chiriladi.

## 3. LOCAL (PGlite)

| Tekshiruv | Natija |
|---|---|
| 007c test to'plami | **74 / 74 PASS** (K, A, I, C, S, D, R, X, N, V guruhlari) |
| 007c rollback / recovery | **26 / 26 PASS** (rollback → katalog 007b holatiga teng → reapply → 74/74) |
| To'liq regressiya (`run_all_007c.sh`, T7A/T7B/T7C) | 007b 78/78 · 007b rb 25/25 · 007a 55/55 · 007a rb 27/27 · 006b 34/34 · 006b rb 18/18 · 006a 83/83 · 006a rb 21/21 · 005e 146/146 · 005e rb 21/21 · 005d 101/101 · 005 114/114 · 004 50/50 (+ standalone 50/50) · Phase 1 31/31 · 005d SQL 54/54 · P01–P20 probe — **0 FAIL** |
| Perf (1011 xodim, 50 bo'lim, 100 lavozim, 50 mutaxassislik, 500 ko'nikma, 300 talab, 10 000 baholash) | p95: ro'yxat 4.6 ms · xodim xulosasi 2.6–3.4 ms · bo'lim xulosasi 5.0–6.2 ms · baholash insert 1.2–1.7 ms · RLS SELECT (head) 4.6 ms |

Maqsadlar: ro'yxat/insert < 200 ms, xulosa < 500 ms — **bajarildi**.

## 4. STAGING (`zwzxyikocqxbeyejeyga`)

| Qadam | Natija |
|---|---|
| Read-only review (007c'dan oldin) | fn / trg / cols / idx / policy / grant md5 — **production bilan 6/6 aynan mos**; 45 / 100 / 92 / 99 / 108; nom to'qnashuvlari yo'q |
| Backup `*_pre007c` | 45 jadval + katalog snapshot'lari |
| Precheck | katalog hashlari 6/6 mos; `ok=false` faqat staging ma'lumot soni production'dan farqli bo'lgani uchun (14/132/1 vs 13/131/2) — kutilgan |
| Apply (sha 56ce1ed9…) | `007c`, 3 jadval, 4 ruxsat, 16 role_permissions (2 tashkilot × 8), anon faqat `verify_certificate` |
| Verify | **ok = true**: 48 jadval / 116 funksiya / 97 trigger / 102 policy / 117 indeks; RLS 3/3; yozuv grantlari 0; anon grant 0; yozuv policy 0; internal→authenticated 0; kategoriyasiz 0; RPC 7/7; CASCADE 0; mavjud ma'lumot 9/9 o'zgarmagan; diff: trg 5, idx 9, col 40, pol 3, funksiyalar +16 (aniq ro'yxat), o'zgargan 0 |
| 007c testlari | **74 / 74 PASS** |
| Perf (ROLLBACK, residue 0) | p95: ro'yxat 0.9 · xodim xulosasi 1.9–3.3 · bo'lim xulosasi 4.6–7.1 · insert 1.4–3.0 · RLS SELECT 6.3 ms |
| Rollback (sha d4e20d25…) | `migration_007c=0`, jadval 0, ruxsat 0 |
| Compare pre-007c | funksiya/trigger/indeks/ustun/policy farqi — **hammasi 0** |
| Reapply → verify → testlar | ok = true · 74 / 74 PASS |
| Regressiya (007c bilan) | 006a 83/83 · 006b 34/34 · 007a 55/55 · 007b 78/78 · 005d 54/54 |
| Qoldiq | 007c qatorlari 0 (testlar va perf ROLLBACK bilan) |

## 5. PRODUCTION READ-ONLY REVIEW (`buuwjhpzptiiyggybvwr`)

`begin; set transaction read only; … rollback;` — `read_only = on`.

| Ko'rsatkich | Qiymat |
|---|---|
| Migratsiyalar | 001 … 007a, 007b; **007c = 0** |
| Nom / funksiya / ruxsat to'qnashuvlari | yo'q / yo'q / 0 |
| Katalog | 45 jadval / 100 funksiya / 92 trigger / 99 policy / 108 indeks; CASCADE 0 |
| anon execute | faqat `verify_certificate` |
| Ma'lumot | courses 13, questions 131, exam_configs 13, attempts 2, certificates 0, profiles 1, employees 1, departments 10, audit_logs 307 |
| Tashkilotlar / role_permissions | 1 / 111 (deploy'dan keyin kutilgan: 111 + 8) |
| anon REST | `skills`, `skill_assessments`, `competency_requirements` → 404 (mavjud emas); `rpc/employee_competency_summary` → 404; `courses`, `learning_path_assignments` → 401 (anon yopiq) |

Precheck (92) production hashlariga bog'langan: fn `974fbd4d…`, trg `3bbba44d…`, cols `e67adf34…`, idx `8ad5ee21…`, policy `3ac78566…`, grant `07db83be…`.

## 6. Production deploy rejasi (faqat "DEPLOY TO PRODUCTION" tasdig'idan keyin)

1. `91_backup_pre007c.sql` → 2. `92_precheck_007c.sql` (`ok = true` shart) → 3. `93_apply_007c.sql` (sha 56ce1ed9…) → 4. `94_verify_007c.sql` (`ok = true`; kutilgan 48 / 116 / 97 / 102 / 117, role_perms = 8) → 5. `95_security_tests_007c.sql` (ROLLBACK bilan, 74/74) → 6. 006a / 006b / 007a / 007b regressiya testlari → 7. anon REST tekshiruvi.
Muammo bo'lsa: `99_rollback_007c.sql` (alohida qaror bilan).

## 8. PRODUCTION DEPLOY (2026-11-27)

| Qadam | Natija |
|---|---|
| Pre-flight (90, READ ONLY) | 007c = 0, 45 / 100 / 92 / 99 / 108, backup jadvallari yo'q — oldingi review'dan beri o'zgarmagan |
| 91 backup | 45 / 45 jadval aynan, 1 140 qator, 99 policy, 100 funksiya, 92 trigger, 304 constraint |
| 92 precheck | **ok = true** (007b = 1, 007c = 0, to'qnashuv 0, 13 / 131 / 2, org 1, role_permissions 111, 6 katalog hashi mos) |
| 93 apply (sha 56ce1ed9…) | 13:49:15 → 13:49:25 UTC; `007c`, 3 jadval, 4 ruxsat, 8 role_permissions, anon faqat `verify_certificate` |
| 94 verify | **ok = true**: 48 / 116 / 97 / 102 / 117; RLS 3/3; yozuv grant / anon grant / yozuv policy 0; internal→auth 0; kategoriyasiz 0; RPC 7/7; CASCADE 0; ma'lumot 9/9 o'zgarmagan; diff trg 5 / idx 9 / col 40 / pol 3 |
| 95 testlar (vaqtinchalik @test.local, ROLLBACK) | **007c 74/74** |
| Regressiya | 007b 78/78 · 007a 55/55 · 006a 83/83 · 006b 34/34 · 005d 54/54 · role matrix 62/62 · 005 regression 26/26 — hammasi fail 0 |
| Yakuniy verify | ok = true, 007c qatorlari 0, test yozuvlari qolmagan |
| anon REST | `skills` / `skill_assessments` / `competency_requirements` SELECT 401, `skills` INSERT 401, `employee_competency_summary` / `record_skill_assessment` 401, `verify_certificate` 200 |

Rollback bajarilmadi. Production holati: migratsiyalar 001 … 007b, 007c; 48 jadval / 116 funksiya / 97 trigger / 102 policy / 117 indeks; CASCADE 0; ma'lumotlar 13 / 131 / 13 / 2 / 0 / 1 / 307 o'zgarmagan.

## 7. Cheklovlar (o'zgarmagan)
Main'ga merge yo'q, Pages deploy yo'q, employee build o'zgarmagan, questions.js / javob banki public build'da emas, "Confirm email" sozlamasiga tegilmagan, test yozuvlari qoldirilmagan.
