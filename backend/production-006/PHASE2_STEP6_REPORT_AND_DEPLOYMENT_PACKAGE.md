# MedAcademy — Phase 2 STEP 6: Final Production Readiness & Controlled Deployment Preparation

**Sana:** 2026-11-24
**Yakuniy holat:** **MEDACADEMY PRODUCTION READINESS — UI ACCEPTANCE BLOCKED BY USER LOGIN**
**Server tomoni xavfsizlik tayyorligi:** **TAYYOR** — barcha texnik talablar bajarildi (006a + 006b lokal va staging'da, rollback/reapply aniq, regressiya to'liq o'tdi, production o'zgarmagan).

Production writes: **0** · Production migrations: **0** · Admin production deploy: **0** · main'ga merge: **0**.

---

## A. Course DELETE finding

| Band | Natija |
|---|---|
| Joriy policy | `courses_write` (FOR ALL) — SA / EM tashkilotdagi istalgan kursni DELETE qila olardi |
| FK | course_modules, course_assignments, learning_path_courses, course_instructors, exam_configs → RESTRICT; questions → NO ACTION. `exam_attempts` / `certificates` kursga FK bilan bog'lanmagan (course_id matn) — bog'liqliksiz kursni o'chirish urinish/sertifikat tarixini "yetim" qoldirar edi |
| Frontend / RPC | Admin Panel va xodim ilovasida kursni o'chirish chaqiruvi yo'q (faqat to'g'ridan-to'g'ri REST orqali mumkin edi) |
| Xavf | tarixiy kursni fizik o'chirish (bog'liqliksiz kurs — FK to'xtatmaydi) |
| Tuzatish | 006b: `courses` uchun BEFORE DELETE trigger — API orqali har qanday rol uchun DELETE rad; arxivlash `status = 'archived'` (mavjud CHECK: draft / under_review / approved / published / archived); `admin_set_course_status(p_course, p_status, p_reason)` — SA/EM, sabab majburiy, audit (006a: eski/yangi holat, actor, tashkilot, vaqt, sabab). `courses_write` policy O'ZGARMADI (INSERT / UPDATE saqlanadi) |
| Testlar | 006b 34/34: SA / EM / Instructor / HR / Employee / anon / cross-org / o'z org'i (Org B) DELETE → DENIED; bog'liqliksiz kurs ham o'chirilmaydi; arxivlash RPC + sabab + audit; to'g'ridan-to'g'ri status UPDATE saqlangan; arxivlangan kurs sertifikati, urinishlar, audit saqlangan; RLS o'zgarmagan; platforma SQL (non-API) texnik xizmat uchun DELETE mumkin va `course.deleted` audit qilinadi |

## B. 006b

| Band | Qiymat |
|---|---|
| Fayl | `backend/migration-006b/006b_course_delete_hardening.sql` |
| SHA-256 / hajm | `c84e1638fcd509ed351a09724ee04d95ddf296ccbd2c5fc3a07a7f4b9cbcd08d` / 4 273 B |
| Rollback | `006b_rollback.sql` — `bb638bf3d4220936020bc90d0f50f249669a90fa76f9c8deeda4f8d2884df070` / 861 B |
| Lokal | 006b 34/34; rollback/recovery 18/18 (apply → rollback = oldingi fingerprint aynan → reapply ×2 = birinchi apply → testlar → residue 0 → yana rollback/reapply) |
| Staging | apply → 006b 34/34, 006a 83/83, 005e 146/146, role matrix 62/62, 005d 54/54 → residue 0 → rollback (fingerprint = 006b'dan oldingi holat aynan) → reapply (= apply holati) → reapply (idempotent) → 006b 34/34 → residue 0. Staging hozir 006a + 006b bilan |
| Ta'sir | jadval / ustun / ma'lumot / RLS o'zgarmaydi; 1 trigger + 2 funksiya |

## C. Staging login

| Rol | Natija |
|---|---|
| Super Admin | BLOCKED (user login required) |
| Medical Reviewer | BLOCKED |
| Education Manager | BLOCKED |
| Instructor | BLOCKED |
| HR | BLOCKED |
| Department Head | BLOCKED |
| Employee | BLOCKED |

Parol o'ylab topilmadi va kiritilmadi. Server tomoni rollar matritsasi staging'da (haqiqiy RLS / trigger / RPC) to'liq o'tdi; UI — lokal mock'da (haqiqiy 005e/006a RLS) 109/109.

## D. Regressiya

| Suite | Lokal (006a + 006b) | Staging (006a + 006b) |
|---|---|---|
| 006b | 34/34 | 34/34 (×2) |
| 006b rollback/recovery | 18/18 | rollback/reapply aniq |
| 006a | 83/83 | 83/83 |
| 006a rollback/recovery | 21/21 | (STEP 5'da) aniq |
| 005e | 146/146 | 146/146 |
| 005e rollback | 21/21 | — |
| 005d | 101/101 | 54/54 (staging suite) |
| Security (44) | 54/54 | — |
| Role matrix | 62/62 | 62/62 |
| 005 | 114/114 | — |
| 004 (005 setup / standalone) | 50/50, 50/50 | — |
| Phase 1 | 32/32 (0 FAIL)* | — |
| Admin Panel | 109/109 (006a bilan va 006a'siz) | — |
| P01–P20 probe | kutilgandek | — |

\* Phase 1'dagi "matching" tekshiruvi tasodifiy imtihonda matching savoli tushgandagina ishlaydi — ba'zi ishga tushirishlarda 31 ta tekshiruv (FAIL emas). Avvaldan mavjud xususiyat.

## E. Git

| Band | Qiymat |
|---|---|
| Branch | `phase2-step3-005d-admin-local` |
| HEAD (bu hisobotdan oldin) | `3cb1ae0` |
| main | `0bd7c6c` (o'zgarmagan) |
| Ahead / behind | 14 / 0 (STEP 5'da main → branch sinxronlandi, PR #1, `580a1bb`) |
| Merge holati | **main'ga merge QILINMADI.** Sabab: GitHub Pages **main / root**'dan build qilinadi — merge = production'ga chiqish |

**Yakuniy merge rejasi (deploy tasdig'i bilan):**
1. Production DB: 006a → 006b (pastdagi tartib) — verify `ok = true`.
2. Admin Panel build'i: `dist/admin/admin.html` (SHA-256 `c37ccd47a9d1916b6f4a132ee4a193ca2ef701a1135aaf197b6cf80b3002d59e`, 363 840 B; javob kaliti / secret yo'q, production publishable key bilan) main root'ga `admin.html` sifatida.
3. PR: `phase2-step3-005d-admin-local` → `main` (kutilgan fayllar: `admin-panel/**`, `backend/migration-006a/**`, `backend/migration-006b/**`, `backend/production-006/**`, `docs/**`; xodim ilovasi `index.html` o'zgarmaydi — live build hash `e8dc98a4`).
4. Kutilgan production effekti: yangi `…/medacademy/admin.html` sahifasi (faqat admin rollari; server RLS bilan). `admin-panel/admin.html` manba sahifasi ham Pages'da ko'rinadi, lekin `js/config.js` / `vendor` yo'qligi uchun ishlamaydi (xavfsiz; ixtiyoriy ravishda `admin-panel/` ni Pages'dan chiqarish mumkin).

## F. Production (faqat SELECT, 2026-11-24 06:38 UTC)

| Tekshiruv | Natija |
|---|---|
| 005e / 006a / 006b | 1 / 0 / 0 |
| courses / questions / exam_configs | 13 / 131 / 13 |
| attempts / certificates / profiles | 2 / 0 / 1 |
| RECEPTION_START | communication |
| medical.review / MR publish | medical_reviewer / 0 |
| CASCADE | 0 |
| anon EXECUTE | faqat verify_certificate |
| fn_md5 / policy_md5 | `8bdab755…` / `01080a07…` (005e deploy'dan keyingi bilan bir xil) |
| attempt_reset_events | yo'q |
| attempt_resets / audit_logs / public jadvallar | 0 / 307 / 43 |

## G. Production deployment paketi (`backend/production-006/`)

| Fayl | SHA-256 | Hajm |
|---|---|---|
| 60_backup_pre006.sql | `37a2400afb74b44ac96984b0b9d32614625c6ae68f9ee419b0a27ad9766ba09e` | 10 837 |
| 61_precheck_006.sql | `f4b84feee3507d3cc858af9c6c1ded169e95a18e799d45677f1c1e282917880e` | 3 947 |
| 62_apply_006a.sql (= 006a migratsiya) | `60e978ad5fa955c45cc747389ea07b3d694dee72f086125625de31278b856bc0` | 25 806 |
| 63_apply_006b.sql (= 006b migratsiya) | `c84e1638fcd509ed351a09724ee04d95ddf296ccbd2c5fc3a07a7f4b9cbcd08d` | 4 273 |
| 64_verify_006.sql | `6a10bc96bb3cec5664b65cb6af2b3d317192edfecab4a89a30e58f2504616547` | 4 197 |
| 69_rollback_006.sql (tartib: 006b → 006a) | `ad37726fb9ca163cc94f98458a1446719bc4f883f5caf254903f5995f72d99f0` | 545 |
| 006a_rollback.sql | `3bb3c3e6e37e0e44409371ff5e057f4b5f070ba356ff6632246c4e686cf3bc2e` | 4 368 |
| 006b_rollback.sql | `bb638bf3d4220936020bc90d0f50f249669a90fa76f9c8deeda4f8d2884df070` | 861 |

**Simulyatsiya (lokal, production-like zanjir):** backup 43/43 jadval aynan; precheck invariantlari to'g'ri; 006a + 006b apply; verify (migratsiyalar 3, trigger 13, audit client write 0, policy +1, eligibility RPC authenticated ✓ / anon ✗, anon faqat verify_certificate); rollback → 006a = 0, 006b = 0.

**Deploy ketma-ketligi:**
1. Git: joriy production commit — main `0bd7c6c` (qayd).
2. `60_backup_pre006.sql` → `tables_identical = public jadvallar soni`, `mismatched = '-'`. Aks holda — **DO NOT DEPLOY**.
3. `61_precheck_006.sql` → `ok = true` (005e = 1, 006a = 0, 006b = 0, 13 / 131 / 13 / 2 / 0, RECEPTION_START = communication, MR publish 0, CASCADE 0, anon faqat verify_certificate, fn_md5 `8bdab755…`, policy_md5 `01080a07…`, backup to'liq). profiles soni alohida qayd etiladi (ok shartida emas).
4. SHA tekshiruvi (fayl = SQL editor) → `62_apply_006a.sql` → `63_apply_006b.sql`.
5. `64_verify_006.sql` → `ok = true` (urinishlar, sertifikatlar, savollar, kurslar md5 = backup).
6. Production xavfsizlik testlari: 54/55 uslubida (tranzaksiya ichidagi vaqtinchalik identifikatorlar + ROLLBACK) 006a/006b uchun production varianti — deploy prompt'ida tayyorlanadi; test residue 0.
7. Admin Panel: `dist/admin/admin.html` → main root; PR merge; Pages build; read-only smoke (foydalanuvchi login qiladi).

**Kutilgan o'zgarishlar:**
- Sxema: `attempt_reset_events` jadvali (+ RLS + 1 policy + indeks); `backup.security_pre006a`.
- Funksiyalar: yangi — `_audit006`, 10 ta trigger funksiyasi, `admin_set_profile_role`, `revoke_certificate(text,text)`, `admin_reset_attempts(uuid,text,text)`, `question_eligibility`, `admin_set_course_status`; o'zgargan — `admin_reset_attempts(uuid,text)` (tarix + audit yozadi, semantika bir xil).
- Huquqlar: audit_logs'dan anon / authenticated INSERT / UPDATE / DELETE / TRUNCATE olinadi (SELECT + RLS qoladi); yangi RPC'lar faqat authenticated'ga.
- Trigger'lar: 13 ta (audit, immutability, self-guard, delete guard'lar).
- UI: Admin Panel (yangi sahifa); xodim ilovasi o'zgarmaydi.
- Ma'lumot: tarixiy ma'lumot o'zgarmaydi. Yagona qo'shimcha: mavjud `attempt_resets` qatorlari `attempt_reset_events`'ga bir marta nusxalanadi — production'da hozir `attempt_resets = 0` (06:40 UTC, read-only), ya'ni 0 qator.

**Rollback rejasi:**
- DB: `006b_rollback.sql` → `006a_rollback.sql` (staging va lokal'da sinovdan o'tgan; fingerprint 006a/006b'dan oldingi holatga aynan qaytadi; audit_logs va attempt_reset_events tarixi saqlanadi; shu sababli rollback'dan keyin tekshiruv `006a_01_fingerprint.sql` bilan, 61_precheck bilan emas).
- To'liq tiklash: `backup.*_pre006` jadvallari.
- Admin Panel: main'dagi merge commit'ni revert (yoki `admin.html` ni o'chirish) → Pages qayta build; oldingi production commit `0bd7c6c`.

## H. Final status

**MEDACADEMY PRODUCTION READINESS — UI ACCEPTANCE BLOCKED BY USER LOGIN**

Server tomoni: course DELETE yopilgan, 006a va 006b barqaror, staging testlari o'tgan, xavfsizlik invariantlari o'tgan, git / backup / rollback rejasi tayyor, production o'zgarmagan, deploy qilinmagan. Foydalanuvchi staging'da login qilib UI acceptance o'tkazilgach → **MEDACADEMY TECHNICALLY READY FOR PRODUCTION DEPLOYMENT — AWAITING EXPLICIT DEPLOYMENT APPROVAL**.

PRODUCTION DEPLOYMENT BOSHLANMADI.
