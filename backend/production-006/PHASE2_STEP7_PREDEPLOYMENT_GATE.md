# MedAcademy — Phase 2 STEP 7: Final Pre-Deployment Gate

**Sana:** 2026-11-24 (06:38–06:48 UTC tekshiruvlar)

## 1. Final readiness

- **SERVER-SIDE READINESS: PASS**
- **UI ACCEPTANCE: BLOCKED — USER LOGIN REQUIRED**
- **PRODUCTION DEPLOYMENT: NOT EXECUTED**

## 2. Git

| Band | Qiymat |
|---|---|
| Branch | `phase2-step3-005d-admin-local` |
| HEAD | admin tests commit (006a + 006b mock rejimi) — oldingi: `16ed75c` (production-006 paketi), `0672313` (006b), `3cb1ae0`, `f691691`, `11ade22` (006a), `580a1bb` (main sinxronlash) |
| main | `0bd7c6c` — o'zgarmagan |
| Ahead / behind | 16+ / 0 |
| Clean / dirty | clean (barcha fayllar commit qilingan; branch blob'lari lokal fayllar bilan SHA bo'yicha mos) |
| Main merge | QILINMAGAN (Pages main/root'dan build qilinadi) |

## 3. Migratsiyalar

| Migration | Local | Staging | Production |
|---|---|---|---|
| 005e | PASS (146/146) | PASS (146/146) | APPLIED (checksum `06db1d7d…` — lokal = branch = production apply) |
| 006a | PASS (83/83, rollback 21/21) | PASS (83/83, rollback/reapply aniq) | NOT DEPLOYED |
| 006b | PASS (34/34, rollback 18/18) | PASS (34/34 ×2, rollback/reapply aniq) | NOT DEPLOYED |

Staging holati: `005e, 006a, 006b`; 006 trigger'lari 13 ta; anon EXECUTE faqat `verify_certificate` — deploy'dan keyingi kutilgan production holati bilan bir xil.

## 4. Xavfsizlik

| Tekshiruv | Natija |
|---|---|
| Audit o'zgarmas | PASS — UPDATE / DELETE / TRUNCATE API'da va platforma SQL'da rad; client write grant 0 |
| Role escalation | PASS — o'z rolini / holatini o'zgartirish rad; HR → super_admin rad; cross-org rad |
| Course DELETE | PASS — API orqali barcha rollar (SA, EM, Instructor, HR, Head, Employee, anon, cross-org) uchun rad |
| Medical review ruxsatlari | PASS — faqat SA / MR |
| Publish ruxsatlari | PASS — faqat SA / EM (guard'lar o'tganda) |
| Anonim kirish | PASS — faqat `verify_certificate` |
| Javob kaliti | PASS — Admin build'da va xodim javoblarida yo'q (B01, A22) |
| service_role | PASS — build'da yo'q (yagona moslik — supabase-js prefiks tekshiruvi va `api.js` rad etuvchi guard'i) |
| Cross-org izolyatsiya | PASS (005d / 006a / 006b test to'plamlari) |

Skript tekshiruvi: production-006 va migratsiya fayllarida `DROP TABLE`, biznes jadvallaridan `DELETE`, ustun o'chirish, credential yo'q. `DROP` faqat `drop trigger/policy/function if exists` (idempotentlik va rollback); `DELETE` faqat `schema_migrations` va `backup.function_categories_005d` (rollback'da). "truncate" so'zi faqat TRUNCATE'ni taqiqlovchi trigger va `revoke` ichida.

Admin build: `dist/admin/admin.html` — SHA-256 `c37ccd47a9d1916b6f4a132ee4a193ca2ef701a1135aaf197b6cf80b3002d59e`, 363 840 B (qayta hisoblandi). `SUPABASE_SERVICE_ROLE_KEY` 0, `answer_key` 0, `correct_answer` 0, JWT 0, savol matni ("Q001") 0; `password` — faqat login formasi va supabase-js maydon nomlari. Xodim live build hash `e8dc98a4` — o'zgarmagan.

## 5. UI

| Rol | Natija |
|---|---|
| Super Admin / Medical Reviewer / Education Manager / Instructor / HR / Department Head / Employee | BLOCKED — USER LOGIN REQUIRED |

Lokal UI (haqiqiy 005e/006a/006b RLS bilan mock): Admin 109/109 — 006a'siz, 006a bilan, 006a + 006b bilan.

## 6. Production baseline (faqat SELECT)

005e = 1, 006a = 0, 006b = 0; courses 13, questions 131, exam_configs 13, attempts 2, certificates 0, profiles 1; RECEPTION_START = communication; medical.review = medical_reviewer (+ SA implicit); MR publish 0; anon faqat verify_certificate; CASCADE 0; attempt_resets 0; audit_logs 307; public jadvallar 43; fn_md5 `8bdab755…`, policy_md5 `01080a07…`.

Kutilgan: courses 13 → 13, questions 131 → 131, exam_configs 13 → 13, attempts 2 → 2, certificates 0 → 0, profiles 1 → 1. Tarixiy ma'lumot o'zgarishi: 0.

## 7. Deployment paketi

`backend/production-006/` — 60_backup_pre006 (`37a2400a…`), 61_precheck_006 (`f4b84fee…`), 62_apply_006a (`60e978ad…`), 63_apply_006b (`c84e1638…`), 64_verify_006 (`6a10bc96…`), 69_rollback_006 (`ad37726f…`); rollback fayllari 006a (`3bb3c3e6…`), 006b (`bb638bf3…`). To'liq SHA'lar va hajmlar: `PHASE2_STEP6_REPORT_AND_DEPLOYMENT_PACKAGE.md`.

Backup: 43/43 jadval (production'da 43 ta public jadval), ma'lumot + ustun / constraint / indeks / policy / funksiya / trigger / grant / default ACL / RLS holati / fingerprint; lokal simulyatsiyada 43/43 aynan. Backup skripti deploy paytida (tasdiqdan keyin) ishga tushadi — bu ham production write.

Deploy tartibi (tasdiqdan keyin): 1) backup → 2) precheck `ok = true` → 3) 006a → 4) tekshirish → 5) 006b → 6) `64_verify_006` `ok = true` → 7) production xavfsizlik testlari (tranzaksiya + ROLLBACK, residue 0) → 8) invariantlar → 9) Admin Panel (`dist/admin/admin.html` → main root + PR merge) → 10) live tekshiruv → 11) xavfsizlik smoke → 12) hisobot.

## 8. Rollback

DB: `006b_rollback.sql` → `006a_rollback.sql` (staging'da sinovdan o'tgan, fingerprint aynan qaytadi; audit_logs va attempt_reset_events tarixi saqlanadi); kerak bo'lsa `backup.*_pre006` dan tiklash. Admin: main'dagi merge commit revert / `admin.html` o'chirish → Pages qayta build; oldingi production commit `0bd7c6c`; xodim ilovasiga ta'sir yo'q.

## 9. Qolgan blocker'lar

1. Haqiqiy staging UI login (foydalanuvchi).
2. Foydalanuvchining aniq buyrug'i: **DEPLOY TO PRODUCTION**.

## 10. Final status

**SERVER-SIDE PRODUCTION READY**
**UI ACCEPTANCE BLOCKED — USER LOGIN REQUIRED**
**AWAITING EXPLICIT PRODUCTION DEPLOYMENT APPROVAL**
