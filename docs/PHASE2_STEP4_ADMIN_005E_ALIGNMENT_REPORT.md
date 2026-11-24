# MedAcademy — Phase 2 STEP 4: Admin Panel 005e moslashtirish — hisobot

**Sana:** 2026-11-24
**Muhit:** faqat lokal (PGlite mini-Supabase, haqiqiy RLS/trigger/RPC) va branch. Production'ga **hech narsa deploy qilinmagan**, production'ga yozish: **0**.
**Yakuniy holat:** **ADMIN PANEL 005e ALIGNMENT COMPLETE** (kod va testlar). Haqiqiy staging login testi: **LIVE LOGIN TEST BLOCKED — USER LOGIN REQUIRED**.
**DO NOT deploy to production.**

---

## A. Boshlang'ich holat

| Band | Qiymat |
|---|---|
| Admin branch | `phase2-step3-005d-admin-local` (`b677bf9`) |
| main | `0bd7c6c` (005e production deploy) |
| Ahead / behind | 7 oldinda / 2 orqada (`74692ee`, `0bd7c6c`) |
| Konflikt | yo'q (GitHub: "Able to merge"); main'dagi farq faqat `backend/migration-005d/`, `backend/migration-005e/` |
| Commit qilinmagan fayllar | yo'q (lokal nusxa branch blob SHA'lari bilan aynan mos — tekshirildi) |
| Xavfsizlik skani | frontend'da service_role / secret / JWT yo'q (faqat `api.js`dagi rad etuvchi guard); live build'da javob kaliti yo'q |

**Aniqlangan nomuvofiqliklar (005e'ga):**
- `pages_evidence.js` — Medical review varianti rol ro'yxati + `question.review` bilan ko'rsatilardi (EM ham ko'rardi).
- `mark_outdated` / `mark_conflicting` har qanday review turida ko'rinardi.
- "Medical review'ga yuborish" formasi `question.review` egalariga (instructor) ko'rinardi.
- `pages_questions.js` — nashr shartlari "approved bormi" mantig'i bilan; oxirgi qaror va evidence `changes_requested` hisobga olinmasdi.
- Manba Retract/Superseded tugmasi faqat `evidence.manage` bilan (instructor ham ko'rardi), 005e esa `evidence.review` talab qiladi.
- Medical Reviewer uchun Publish tugmasi `question.publish` bo'yicha (005d'da MR'da edi).
- `reviewer_role_at_creation`, `review_seq` ko'rsatilmasdi.

## B. Kod o'zgarishlari (faqat Admin Panel UI + testlar)

| Fayl | O'zgarish |
|---|---|
| `js/admin/perms.js` | `canMedicalReview()` (medical.review + SA/MR), `canPublish()` (question.publish + SA/EM), `canAssignReview()` (SA/EM); Review Queue bo'limi `medical.review` bilan ham ochiladi |
| `js/admin/ui.js` | `reason` yorliqlari: evidence_rejected, evidence_changes_requested, medical_rejected, medical_changes_requested, mark_* |
| `js/admin/pages_evidence.js` | `reviewStatus()` + `statusPanel()` (oxirgi qaror semantikasi `review_seq` bo'yicha, faqat joriy versiya, faqat SA/MR medical qarori; yaroqlilik serverdan — `question_meta` RPC = `_q_exam_eligible`); review formasi: medical faqat SA/MR va faqat klinik kursda; medical qarorlar = Approved / Rejected / Changes Requested, sabab majburiy, tasdiqlash matni "This medical review decision affects eligibility for future clinical exams"; mark_* faqat evidence turida; assign formasi faqat SA/EM; tarixda reviewer roli; Retract/Superseded uchun `evidence.review` ham kerak |
| `js/admin/pages_questions.js` | Publish tugmasi `canPublish()`; nashr shartlari oxirgi evidence/medical qarori bo'yicha, klinik emas kurs uchun "Medical Review talab qilinmaydi"; status panel; review jadvalida "Rol (yozilgan paytda)", `review_seq` tartibi |
| `tests/mock_supabase.mjs` | mock bazaga `005e_medical_review_authorization.sql` qo'shildi |
| `tests/admin_tests.py` | 005e testlari (A01–A23), W10/W11/E08/E09 005e qoidalariga moslashtirildi |

**O'zgartirilmagan:** exam engine, scoring, sertifikatlar, RLS, sxema, migratsiyalar, tarixiy ma'lumotlar, xodim ilovasi (live build hash `e8dc98a4` — o'zgarmagan). 005e checksum: `06db1d7de5e611a6e7dc738f0d82691d5c44441ae0fcbd13ca909c24a198ffb5` — o'zgarmagan.

## C. 005e moslik jadvali

| Qoida | UI | Server (005e) | Test |
|---|---|---|---|
| Medical review faqat SA/MR | variant faqat `canMedicalReview()` | guard_question_review | A01, A12, A13, A15, A18, P01–P07 |
| MR publish/unpublish qila olmaydi | Publish tugmasi yo'q | question_workflow | A06, A07, P11 |
| EM: evidence review + publish, medical yo'q | evidence bor, medical yo'q, publish bor | ✓ | A08, A12, A13, W11 |
| Instructor: medical/mark_*/retract/publish yo'q | forma va tugmalar yo'q | ✓ | A15–A18, P12–P16 |
| Medical qaror sababi majburiy + ogohlantirish | ✓ | — (UI) | A04, A05 |
| Oxirgi qaror semantikasi | status panel `review_seq` | `_q_latest_review` | A10, A11, P10 |
| changes_requested / rejected → INELIGIBLE + sabab | ✓ | `_q_exam_eligible` | A10, A14 |
| Klinik emas (RECEPTION_START) — medical talab qilinmaydi | "Not required", variant yo'q | domain=communication | A19, A20, P17 |
| Yaroqlilik serverdan | `question_meta` RPC | ✓ | A08, A09 |
| Xodimga javob kaliti / review'lar ketmaydi | — | RLS / RPC | A22, A23, B01, B02 |

## D. Test natijalari (lokal)

| Suite | Natija |
|---|---|
| Admin Panel (Playwright + PGlite, 005e bilan) | **108 / 108** (avval 85: +23 yangi 005e testi) |
| 005e security | 146 / 146 |
| 005e rollback/recovery | 21 / 21 |
| 005d suite (005e bilan / 005e'siz) | 101 / 101, 101 / 101 |
| 005d staging tests / 44_security_tests_005d | 54 / 54, 54 / 54 |
| Role matrix | 62 / 62 |
| 005 suite (005e bilan / 005e'siz) | 114 / 114, 114 / 114 |
| 004 (005 setup bilan / standalone) | 50 / 50, 50 / 50 |
| Phase 1 SQL | FAIL 0 ("Barcha SQL testlar o'tdi") |
| P01–P20 probe | barcha kutilgan natija |

**Performance:** savollar ro'yxati server-side pagination (`range`) va server qidiruvi bilan; review sahifasida so'rovlar parallel (N+1 yo'q). Eslatma: yaroqlilikni olish uchun `question_meta` RPC ishlatiladi — u faqat metadata (id, kurs, mavzu, tur, qiyinlik) qaytaradi, javob kaliti yo'q; lekin tashkilotning barcha yaroqli savollari ro'yxatini qaytaradi. Keyingi bosqichda bitta savol uchun `question_eligibility(id)` RPC tavsiya etiladi (006a'da, alohida tasdiq bilan).

## E. Haqiqiy login testi (rollar bo'yicha)

**LIVE LOGIN TEST BLOCKED — USER LOGIN REQUIRED.** Parol chatga berilmadi, men parol o'ylab topmadim va kiritmadim; repo yoki `.env`ga hech qanday credential yozilmadi. Rollar matritsasi lokal mock'da (haqiqiy 005e RLS/trigger) tekshirildi: SA, EM, MR, Instructor, Employee, boshqa tashkilot (cross-org testlari mavjud suite'da).

## F. Production (faqat SELECT)

Production'ga yozish: **0**. Bitta o'qish so'rovi natijasi:

| Tekshiruv | Natija | Kutilgan |
|---|---|---|
| 005e qo'llangan | 1 | 1 ✅ |
| courses / questions / exam_configs | 13 / 131 / 13 | 13 / 131 / 13 ✅ |
| attempts / certificates / profiles | 2 / 0 / 1 | 2 / 0 / 1 ✅ |
| RECEPTION_START domain | communication | communication ✅ |
| medical.review ruxsati | medical_reviewer (SA — implicit) | ✅ |
| MR question.publish | 0 | 0 ✅ |
| question_reviews ustunlari | review_seq, reviewer_role_at_creation | ✅ |
| question_meta → `_q_exam_eligible` | true | ✅ |
| FK ON DELETE CASCADE (public) | 0 | 0 ✅ |
| FK RESTRICT | 74 (barcha public FK'lar bo'yicha) | eski "6" — boshqa (tor) doirada hisoblangan; bu son bilan to'g'ridan-to'g'ri solishtirib bo'lmaydi |
| anon EXECUTE | faqat verify_certificate | ✅ |

**docs / exam_configs DELETE xavfi (faqat hisobot):** o'zgarish qilinmadi; 006a doirasida alohida ko'rib chiqiladi.

## G. Git

- Branch: `phase2-step3-005d-admin-local` (main'ga merge qilinmagan).
- Commit xabari: `feat: align admin panel with 005e medical review authorization`.
- Faqat tegishli fayllar: `admin-panel/js/admin/{perms,ui,pages_evidence,pages_questions}.js`, `admin-panel/tests/{admin_tests.py,mock_supabase.mjs,admin_results.json}`, ushbu hisobot.
- Branch main'dan 2 commit orqada — konfliktsiz; sync (main → branch merge) alohida tasdiq bilan.

## H. Qolgan bloklovchilar

1. Haqiqiy staging login testi — foydalanuvchi o'zi login qilishi kerak.
2. Admin Panel production deploy — alohida tasdiq.
3. 006a (docs/exam_configs DELETE hardening, `question_eligibility` RPC) — ChatGPT ko'rib chiqqandan keyin.
4. Branch ↔ main sync — merge'dan oldin tasdiq.
