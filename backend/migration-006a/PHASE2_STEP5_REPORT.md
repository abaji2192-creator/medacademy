# MedAcademy — Phase 2 STEP 5: Final Security Hardening, Staging Acceptance & Production Readiness — hisobot

**Sana:** 2026-11-24
**Yakuniy holat:** **MEDACADEMY PRODUCTION READINESS BLOCKED**
Yagona blocker: haqiqiy staging login testi (**LIVE LOGIN TEST BLOCKED — USER LOGIN REQUIRED**). Kod, migratsiya, testlar, staging va production holati bo'yicha boshqa blocker yo'q. Foydalanuvchi staging'da login qilib rollar bo'yicha UI tekshiruvi o'tkazilgach → **PRODUCTION READY — AWAITING EXPLICIT DEPLOYMENT APPROVAL**.

Production'ga yozish: **0**. Production migratsiyalari: **0**. Admin Panel production'ga deploy: **0**.

---

## A. Git

| Band | Qiymat |
|---|---|
| Boshlang'ich holat | branch `phase2-step3-005d-admin-local` = `7fd0aa4`; main `0bd7c6c`; 10 oldinda / 2 orqada; konflikt yo'q; uncommitted yo'q |
| Sinxronlash | PR #1 (main → admin branch), merge commit `580a1bb` — main'dagi 005d/005e migratsiya tarixi (`74692ee`, `0bd7c6c`) saqlandi; faqat `backend/migration-005d/`, `backend/migration-005e/` (25 fayl); konflikt yo'q |
| Natija | admin branch main'dan **0 orqada**; main o'zgarmagan |
| Nega main'ga merge qilinmadi | GitHub Pages **main / root**'dan build qilinadi. Admin Panel'ni main'ga qo'shish = Admin Panel'ni production'ga chiqarish (production Supabase bilan) — bu bosqichda taqiqlangan. Main'ga merge Admin production deploy tasdig'i bilan birga qilinadi |
| Squash | qilinmadi (tarixni o'zgartirmaslik uchun) |
| 005e checksum | `06db1d7de5e611a6e7dc738f0d82691d5c44441ae0fcbd13ca909c24a198ffb5` — o'zgarmagan |

## B. Staging login

| Rol | Natija |
|---|---|
| Super Admin | BLOCKED (user login required) |
| Medical Reviewer | BLOCKED |
| Education Manager | BLOCKED |
| Instructor | BLOCKED |
| HR | BLOCKED |
| Department Head | BLOCKED |
| Employee | BLOCKED |

Parol o'ylab topilmadi, kiritilmadi, repo'ga yozilmadi. Rollar bo'yicha server tekshiruvi staging'da SQL test to'plamlari orqali (haqiqiy RLS/trigger/RPC, JWT claim'lari bilan, ROLLBACK) to'liq o'tdi — pastga qarang. UI rollar matritsasi lokal mock'da (haqiqiy 005e/006a RLS) 109/109.

## C. 006a migratsiya

| Band | Qiymat |
|---|---|
| Fayl | `backend/migration-006a/006a_audit_hardening.sql` |
| SHA-256 | `60e978ad5fa955c45cc747389ea07b3d694dee72f086125625de31278b856bc0` |
| Rollback | `006a_rollback.sql` — SHA-256 `3bb3c3e6e37e0e44409371ff5e057f4b5f070ba356ff6632246c4e686cf3bc2e` |
| Lokal testlar | 006a 83/83; rollback/recovery 21/21 (apply → rollback → fingerprint = oldingi holat → reapply ×2 → testlar → yana rollback/reapply) |
| Idempotentlik | 2 marta apply — fn/policy/trigger/grant bir xil |
| Staging | apply OK → 006a 83/83 → 005e 146/146, role matrix 62/62, 005d 54/54 → rollback (fingerprint = 006a'dan oldingi holat, aynan) → reapply (fingerprint = birinchi apply) → 006a 83/83 → test residue 0 (data md5 va audit soni o'zgarmagan). Staging hozir 006a bilan |

## D. Audit

| Hodisa | Natija |
|---|---|
| audit_logs o'zgarmas | UPDATE / DELETE / TRUNCATE — API'da ham, platforma SQL'da ham rad (A01–A06); soxta actor bilan INSERT rad (A03); client yozish huquqi 0 |
| Question publish / unpublish / status / eligibility | `question.published`, `question.unpublished`, `question.status_changed`, `question.eligibility_changed`, `question.edited`; matn/javob/izoh yozilmaydi (B05) |
| Course status | `course.created/updated/published/archived/status_changed/deleted` |
| Role change | `profile.role_changed` (actor, eski/yangi rol, sabab, tashkilot); `admin_set_profile_role(p_profile, p_role, p_reason)` — sabab majburiy; o'z rolini/holatini o'zgartirish taqiqlangan; HR → super_admin taqiqi saqlangan; cross-org rad |
| Profile status / bo'lim | `profile.status_changed`, `profile.department_changed`; email/parol/token yozilmaydi |
| Exam config | `exam_config.created/updated` |
| Attempt reset | `attempt_reset_events` — har bir reset alohida, o'zgarmas qator (sabab, oldingi reset vaqti/kim); `attempt_resets` (exam engine joriy holati) semantikasi o'zgarmagan; `admin_reset_attempts(p_user, p_course, p_reason)` + eski 2-argumentli chaqiruv ishlaydi; mavjud reset holati migratsiyada tarixga ko'chiriladi |
| Certificate | `certificate.issued`, `certificate.revoked` (sabab bilan: `revoke_certificate(p_code, p_reason)`); revoke qaytarilmas; DELETE rad |

## E. DELETE hardening

| Jadval | Oldingi holat | 006a |
|---|---|---|
| docs | `docs_delete` policy SA/EM'ga tashkilotdagi istalgan kolleksiyani o'chirishga ruxsat berardi; xodim ilovasida `DB.del()` chaqiruvi yo'q | tarixiy kolleksiyalar (attempts, certificates, audit, progress, initial, employees) API orqali o'chirilmaydi; qolganlari (notifications va h.k.) avvalgidek |
| exam_configs | `exam_configs_write` (ALL) SA/EM'ga DELETE ruxsat berardi; FK yo'q, lekin konfiguratsiya tarixiy urinishlar bilan mantiqan bog'liq | API orqali DELETE taqiqlangan; o'zgartirish (audit bilan) yoki kursni arxivlash. Yangi `is_active` ustuni qo'shilmadi (exam engine o'zgarmasligi uchun) |

## F. question_eligibility RPC

| Band | Natija |
|---|---|
| Yaratildi | `question_eligibility(p_question text) → jsonb` |
| Qaytaradi | id, course_id, clinical, medical_review_required, workflow_status, evidence_status, review_reason, current/published version, latest evidence decision, latest medical decision (joriy va nashr versiyasi), eligible (`_q_exam_eligible`) |
| Qaytarmaydi | savol matni, variantlar, javob, izoh, ichki izohlar, reviewer ma'lumoti |
| Avtorizatsiya | faol rol + `question.view` + `can_see_question` (tashkilot, kurs instruktori, MR — faqat tayinlangan savol); anon / Employee / HR / boshqa tashkilot — rad |
| Admin Panel | status panel avval `question_eligibility`'ni ishlatadi; 006a yo'q bo'lsa (hozirgi production) `question_meta`'ga qaytadi — Admin testlari ikkala holatda 109/109 |
| Performance (lokal) | 131 savol: ~0.7 ms / chaqiruv, ~390 bayt javob |

## G. Regressiya (lokal, 006a bilan)

| Suite | Natija |
|---|---|
| Admin Panel (006a bilan / 006a'siz) | 109/109, 109/109 |
| 006a | 83/83 |
| 006a rollback/recovery | 21/21 |
| 005e | 146/146 |
| 005e rollback | 21/21 |
| 005d | 101/101 |
| 005d staging | 54/54 |
| Security (44) | 54/54 |
| Role matrix | 62/62 |
| 005 | 114/114 |
| 004 (005 setup / standalone) | 50/50, 50/50 |
| Phase 1 | 32/32 |
| P01–P20 probe | kutilgandek |

Staging (006a bilan): 006a 83/83 (ikki marta), 005e 146/146, role matrix 62/62, 005d 54/54.

## H. Production (faqat SELECT)

Production writes: **0** · Production migrations deployed: **0** · Production Admin Panel deployed: **0**.

| Tekshiruv | Natija |
|---|---|
| 005e / 006a | 1 / 0 |
| courses / questions / exam_configs | 13 / 131 / 13 |
| attempts / certificates / profiles | 2 / 0 / 1 |
| RECEPTION_START | communication |
| medical.review | medical_reviewer (SA — implicit) |
| MR publish | 0 |
| CASCADE | 0 |
| anon EXECUTE | faqat verify_certificate |
| fn_md5 / policy_md5 | `8bdab755…` / `01080a07…` — 005e deploy'dan keyingi holat bilan bir xil |

## I. Qolgan blocker'lar

1. **Haqiqiy staging login** — foydalanuvchi o'zi login qilishi kerak (rollar bo'yicha UI acceptance).
2. Production deploy (006a + Admin Panel + admin branch → main) — alohida aniq tasdiq bilan.

Kuzatuvlar (blocker emas): `courses_write` (ALL) policy SA/EM'ga kurs DELETE ruxsatini beradi — FK'lar (RESTRICT) tarixiy ma'lumotni himoya qiladi, kurs o'chirilsa `course.deleted` audit qilinadi; keyingi bosqichda arxivlash-only qilish mumkin. Xodim ilovasi rol/holatni to'g'ridan-to'g'ri `profiles.update` bilan o'zgartiradi — audit yoziladi, lekin sabab bo'sh; sabab uchun `admin_set_profile_role` RPC tayyor.
