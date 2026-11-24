# MedAcademy — Migration 005e: production deploy hisoboti

**Natija: 005e production'ga muvaffaqiyatli qo'llandi.** Tekshiruvlar, ROLLBACK bilan o'tkazilgan testlar va xavfsizlik nazorati PASS. Faqat 005e qo'llandi: 004, 005, 005d, 006a, Admin Panel va xodim ilovasi o'zgarmadi.

## 1. Deploy sanasi va vaqti

| | |
|---|---|
| Sana | 2026-11-24 |
| 005e apply | **04:25:10 UTC** (09:25 Toshkent) |
| Production | `buuwjhpzptiiyggybvwr` (medacademy) |
| Supabase holati | Ochiq incident yo'q. Bitta "monitoring" holatidagi eski incident bor (13–16-noyabr API kechikishlari, sababi bartaraf etilgan). Deploy'ga ta'sir qilmadi |

## 2. Production'ning boshlang'ich holati

| Ko'rsatkich | Qiymat |
|---|---|
| Migratsiyalar | `001…005d` |
| Kurslar / savollar / exam_configs | 13 / 131 / 13 |
| Urinishlar / sertifikatlar | 2 / 0 |
| Profillar / auth foydalanuvchilar / tashkilotlar | 1 (super_admin, faol) / 1 / 1 |
| `RECEPTION_START.domain` | `medical` |
| CASCADE FK (005d'ning 6 tasi) / RESTRICT | 0 / 6; public'da CASCADE jami 0 |
| anon EXECUTE | 1 (`verify_certificate`) |
| Funksiyalar / policy'lar | 72 / 97 |
| Barmoq izi md5 | fn `88c2bbfa…`, policy `7384de1f…`, constraint `52ce7426…`, ustun `01e21beb…`, permissions `41bcebd9…` — staging'ning 005e'dan oldingi holati bilan aynan bir xil |

## 3. Backup natijasi

`production/50_backup_pre005e.sql` (SHA `1f4b9c69…`). Backup `staging/005e_00_backup.sql` bilan bir xil mantiqda; jadval nomlari `_pre005e_20261124`.

| Qism | Natija |
|---|---|
| Jadvallar | **43 / 43 bir xil** (md5), jami 1 117 qator |
| Policy'lar | 97 |
| Funksiyalar (ta'rif + anon/authenticated EXECUTE) | 72 (anon EXECUTE: 1) |
| Trigger'lar / constraint'lar (FK 119 ta) | 77 / 286 |
| Jadval grant'lari, default privileges | saqlandi (default ACL: 6 qator) |
| RLS holati (yoqilgan/majburiy) va jadval ACL | 43 jadval, RLS 43 / 43 |
| Barmoq izi (`backup.fingerprint_pre005e_20261124`) | saqlandi |

Backup faqat `backup` sxemasiga yozdi; ilova ma'lumotlariga tegilmadi.

## 4. Precheck natijasi

`production/51_precheck_005e.sql` (faqat SELECT, SHA `115fa9f0…`) — **`ok: true`**. Barcha shartlar bajarildi:
- Migratsiyalar 005d'da; 005e obyektlari yo'q: ruxsat, `role_permissions` qatorlari, funksiya, ustunlar, CHECK'lar, indeks, snapshot.
- Sonlar: kurslar 13, savollar 131, exam_configs 13, urinishlar 2, sertifikatlar 0, profillar 1, auth foydalanuvchilar 1.
- `RECEPTION_START = medical`; CASCADE 0 / RESTRICT 6; anon EXECUTE faqat `verify_certificate`.
- Test akkaunti 0, MR / EM / Instructor / HR / Head profillari 0, test qatorlari 0.
- review / evidence / manba: 0 / 0 / 0. MR → `question.publish`: 1.
- Barmoq izi md5'lari: fn, policy, constraint, ustun, indeks, trigger, ACL, permissions, role_perm — kutilgan qiymatlarga teng. Savollar, kurslar va urinishlar ma'lumot md5'lari ham teng.

## 5. SHA-256 tekshiruvi

| Manba | SHA-256 | Bayt |
|---|---|---|
| Lokal repozitoriy fayli | `06db1d7de5e611a6e7dc738f0d82691d5c44441ae0fcbd13ca909c24a198ffb5` | 34 968 |
| Git `bf7c4e7` (commit'ga bog'langan raw fayl) | `06db1d7d…` ✅ | 34 968 |
| Staging'da sinalgan fayl | `06db1d7d…` ✅ | 34 968 |
| SQL Editor kiritmasi (Run'dan oldin brauzerda hisoblandi) | `06db1d7d…` ✅ | 34 968 |
| Rollback (Git va lokal) | `56ec44dd2fda79d3998993a271fcb27a6ff397dd51e6461aeb3100fb82a333be` ✅ | 6 006 |

To'rttala manba baytma-bayt bir xil. Har bir production skripti uchun ham SHA editor'da Run'dan oldin tekshirildi. Test fayllari oxirida `ROLLBACK` borligi ham tekshirildi.

## 6. Migratsiyani qo'llash natijasi

`production/52_apply_005e.sql` (= migratsiya fayli) bitta tranzaksiyada xatosiz bajarildi. Qo'shimcha yoki qo'lda yozilgan SQL yo'q.

Natija: `migration: 005e`, `medical_review_roles: [medical_reviewer]`, `mr_publish_rows: 0`, yangi ustunlar `review_seq` va `reviewer_role_at_creation`, savollar 131, yaroqli 0, `reception_domain: communication`, review'lar 0, urinishlar 2, sertifikatlar 0.

**Ulanish uzilishi haqida:** apply'dan oldin brauzer kengaytmasi bilan aloqa ~1 daqiqaga uzildi. Uzilgan chaqiruv ishga tushmagani tasdiqlandi (apply vaqt belgisi o'rnatilmagan edi, natija panelida hali precheck natijasi turardi). SHA qayta tekshirildi, so'ng migratsiya **bir marta** qo'llandi.

## 7. Medical Review ruxsati tekshiruvi

- `permissions`: `medical.review` qo'shildi.
- `role_permissions`: `medical.review` faqat `medical_reviewer` rolida, har bir tashkilotda. Super Admin uchun ruxsat implicit (avvalgidek).
- HR, Education Manager, Instructor, Department Head, Employee'da yo'q. `role_permissions_005e_chk` CHECK constraint ularga berishni bloklaydi.
- `medical_reviewer` → `question.publish`: **0** (avval 1).
- Server tomonidagi xatti-harakat 54-to'plamda ROLLBACK bilan sinaldi (§10):
  - medical review: SA ✅, MR ✅; EM / Instructor / Head / HR / Employee ❌;
  - MR nashr qilmaydi; EM va SA barcha shartlar bajarilganda nashr qiladi;
  - Instructor, HR, Head, Employee nashr qila olmaydi.

## 8. Reception tasnifi tekshiruvi

- `RECEPTION_START.domain`: `medical` → **`communication`**.
- `backup.courses_pre005e_20261124` bilan solishtirish: **faqat 1 ta kurs o'zgardi** — `RECEPTION_START:medical->communication`. Qolgan 12 kursda farq yo'q.
- Rollback uchun snapshot: `course_domain` (eski qiymat `medical`) va `course_domains_all` saqlandi.
- Kurs, uning kontenti va savollari o'zgarmadi (savollar md5 `8993adb8…` o'zgarmagan).

## 9. Evidence `changes_requested` tekshiruvi

- Production funksiyalari: `_q_exam_eligible` va nashr guard'i oxirgi evidence qarori `rejected` yoki `changes_requested` bo'lsa rad etadi; review effekti `review_reason = evidence_changes_requested` yozadi.
- Funksiya md5 (`8bdab755…`) staging'da sinalgan holat bilan aynan bir xil.
- 54-to'plam (ROLLBACK) tasdiqladi:
  - Approved → Changes requested → yaroqsiz (CL01, RC06, G08);
  - Changes requested → Approved → yana yaroqli (CL03, RC07, G10);
  - Approved → Rejected → yaroqsiz (G01, CL06);
  - Reception A–D holatlari va klinik bo'lmagan matritsa (Ethics, Communication, Sales, Reception).
- Tarixiy urinishlar va sertifikatlar o'zgarmadi (Y01–Y10; urinishlar md5 `f35ef12c…` deploy'dan oldin va keyin bir xil).

## 10. Regressiya testlari (har biri bitta tranzaksiyada, oxirida ROLLBACK)

| Fayl | SHA-256 | Natija |
|---|---|---|
| `54_security_tests_005e.sql` — 005e to'plami | `ef99e21c…` | **146 / 146** (18 guruh) |
| `55_role_matrix_005e.sql` — rol matritsasi | `6058d598…` | **62 / 62** |
| `44_security_tests_005d.sql` — 005d xavfsizlik (o'zgarishsiz) | `9870b58e…` | **54 / 54** |
| `56_regression_005_after_005e.sql` — 005 regressiyasi | `dafb4d89…` | **26 / 26** |

**Test identifikatorlari:**
- Production'da doimiy test akkaunti yaratilmadi.
- Rollarni server tomonida sinash uchun vaqtinchalik identifikatorlar (Org B va `@test.local` foydalanuvchilar, parolsiz, tizimga kira olmaydi) **faqat test tranzaksiyasi ichida** yaratildi va ROLLBACK bilan yo'qoldi. Bu 005d production testlaridagi 44/45 usuli bilan bir xil.
- Natija: auth foydalanuvchilar 1, profillar 1, test akkauntlari 0 (§11).

**005e-ga moslashtirilgan joylar:**
- 54 va 55 = staging fayllari (`005e_02_tests.sql`, `005d_06_role_matrix.sql`) aynan, oldida tranzaksiya ichidagi test muhiti bilan.
- 56 = 005d'dagi 45-fayl + 005e tibbiy tasdiq simulyatsiyasi (staging `005d_05` bilan bir xil o'zgarish).
- `005e_02_tests.sql` dagi RC01 testi aniqlashtirildi: kurslar endi faqat 005e snapshot'ida bor kurslar bo'yicha solishtiriladi (tranzaksiyada yaratilgan test kursi hisobga kirmaydi). Yangilangan fayl staging'da yana 146/146.

## 11. ROLLBACK tekshiruvi

Testlardan keyin `53_verify_005e.sql` qayta ishga tushirildi: natija **apply'dan keyingi tekshiruv bilan baytma-bayt bir xil** (`identical_to_post_apply: true`).

| | Natija |
|---|---|
| Savollar / kurslar / urinishlar / sertifikatlar | 131 / 13 / 2 / 0 (md5 o'zgarmagan) |
| Evidence / manbalar / review'lar | 0 / 0 / 0 |
| Ruxsat holati | o'zgarmagan (role_perm md5 `0dda0a2d…`) |
| auth foydalanuvchilar / profillar | 1 / 1 |
| Test akkauntlari / test qatorlari | 0 / 0 |

005e migratsiyasi qo'llangan holda qoldi. Faqat test tranzaksiyalari bekor qilindi.

## 12. Yakuniy production holati

`53_verify_005e.sql` — **`ok: true`**

| Ko'rsatkich | Kutilgan | Natija |
|---|---|---|
| Kurslar / savollar | 13 / 131 | 13 / 131 ✅ |
| Urinishlar / sertifikatlar | 2 / 0 | 2 / 0 ✅ |
| Foydalanuvchilar / profillar | 1 | 1 ✅ |
| `RECEPTION_START.domain` | communication | communication ✅ |
| 005e qo'llanganmi | ha | `001…005d,005e` ✅ |
| 005d xavfsizligi | saqlangan | CASCADE 0 / RESTRICT 6; anon EXECUTE 1 (`verify_certificate`) ✅ |
| Policy'lar | 97 | 97, md5 `01080a07…` (staging bilan teng) ✅ |
| Funksiyalar | 73 | 73, md5 `8bdab755…` (staging bilan teng) ✅ |
| Constraint / ustun / indeks / trigger / ACL | staging 005e bilan teng | `31bba4a9…` / `e87a26bf…` / `fe69c8ac…` / `b1507cb9…` / `dfa96ba7…` ✅ |
| Backup'ga nisbatan o'zgargan jadvallar | kutilganlar | `audit_logs` (role_permissions audit yozuvi), `courses`, `permissions`, `role_permissions`, `schema_migrations` ✅ |
| Snapshot (`backup.security_pre005e`) | bor | fn_def 7, policy 2, role_perm 1, course_domain 1, course_domains_all 1, counts 1 ✅ |

## 13. Live smoke test

| Tekshiruv | Natija |
|---|---|
| Bosh sahifa (`abaji2192-creator.github.io/medacademy/`) yuklanadi | ✅ |
| Console xatolari / JS exception (qayta yuklashda) | **0** |
| Javob kaliti public build'da | yo'q: `"answer":` 0, `correct:` 0, `questions.js` mavjud emas (503) |
| Maxfiy kalit | yo'q. Yagona `sb_secret_` mosligi — supabase-js kutubxonasidagi prefiks tekshiruvi; JWT/service kalit yo'q |
| Kirgan holatdagi smoke (dashboard, profil, kurslar, savollar banki, imtihonlar, initial natija, sertifikatlar) | ⏳ **bajarilmadi** |

**Nega bajarilmadi:** brauzerdagi oldingi sessiya muddati tugagan, ilova login sahifasini ko'rsatdi. Parolni kiritish yoki saqlangan parol bilan kirishni men bajarmayman. Siz bir marta tizimga kirsangiz, shu sahifalarni faqat o'qish rejimida tekshirib chiqaman (logout qilmayman, urinish yaratmayman).

## 14. Xavfsizlik tekshiruvi (anon, faqat publishable key)

| So'rov | Natija |
|---|---|
| REST GET: `questions`, `question_reviews`, `question_evidence`, `question_versions`, `evidence_sources`, `employees`, `exam_attempts`, `profiles`, `certificates`, `role_permissions`, `docs`, `audit_logs`, `courses` | hammasi **401** (42501) |
| REST POST `question_reviews` (medical review) | **401** |
| RPC: `question_meta`, `start_exam`, `submit_exam`, `get_attempt_review`, `set_employee_status`, `revoke_certificate`, `_q_latest_review` | hammasi **401** (42501) |
| RPC `verify_certificate` (mavjud bo'lmagan kod) | **200**, `null` — ishlaydi |

Bazadagi tekshiruv: anon EXECUTE faqat `verify_certificate`. `_q_latest_review` authenticated uchun ham yopiq (B15).

## 15. Performance

- Production'da `_q_exam_eligible`: 131 savol × 5 = 655 ta baholash — **18,3 ms** (`EXPLAIN ANALYZE`, faqat o'qish).
- Production'da hozir barcha savollar `review_required` holatida, shuning uchun funksiya tez qaytadi.
- To'liq yo'l staging va lokal o'lchovda: 600 ta nashr qilingan savol uchun xodim ro'yxati ~37 ms; 005d bilan farq kutilgan darajada.
- Kutilmagan sekinlashuv yo'q.

## 16. Production toza holati

| Tekshiruv | Natija |
|---|---|
| Test akkauntlari (`@test.local`, `@invalid.local`, `a0…/b0…/d0…/e0…` id'lar) | 0 |
| Test savollari / kurslari / urinishlari (`T5E%`, `TQ_%`, `TESTB%`) | 0 |
| Test dalillari / review'lari / sertifikatlari | 0 / 0 / 0 |
| Vaqtinchalik ruxsat, policy, funksiya, trigger | yo'q: pg_temp sessiya bilan yo'qoladi; doimiy obyektlar faqat 005e'dagilar |

- **Yagona biznes-ma'lumot o'zgarishi:** `RECEPTION_START.domain: medical → communication`.
- **Avtorizatsiya o'zgarishlari:** `medical.review` ruxsati va qatori (+1), MR → `question.publish` (−1), 7 ta funksiya ta'rifi, 1 ta yangi ichki funksiya, 2 ta policy, 2 ta ustun, 1 ta indeks, 2 ta CHECK.
- `audit_logs`: `role_permissions` o'zgarishining tizim audit yozuvi (kutilgan; o'chirilmaydi).
- `docs = 24`: deploy'dan oldin ham 24 edi, ilovaning oddiy faollik yozuvlari.
- Yangi qo'shilgan `backup.*_pre005e_20261124` jadvallari va `backup.security_pre005e` — rollback va diagnostika uchun ataylab saqlanadi.

## 17. Git / main

- `main` (`74692ee`) ga faqat 005e production fayllari qo'shildi. Commit: `feat: deploy migration 005e medical review authorization`.
- Papka: `backend/migration-005e/`:
  - migratsiya va rollback;
  - production skriptlari `50–56`, `59`;
  - staging fingerprint va test fayllari;
  - production natijalari (JSON) va shu hisobot.
- Admin Panel, 006a va boshqa o'zgarishlar kiritilmadi. Parol, kalit, javob kaliti va test credential yo'q.
- Commit hash yakuniy xabarda.

## 18. Rollback rejasi (kerak bo'lsa)

`production/59_rollback_005e.sql` (= `migrations/005e_rollback.sql`, SHA `56ec44dd…`):
- `backup.security_pre005e` snapshot'idan 7 ta funksiya va 2 ta policy'ni aynan tiklaydi;
- MR → `question.publish`ni qaytaradi, `medical.review`ni olib tashlaydi;
- `RECEPTION_START`ni `medical`ga qaytaradi.
- Agar 005e davrida review yozilmagan bo'lsa, yangi ustunlarni ham olib tashlaydi; aks holda ularni tarixiy metadata sifatida saqlaydi.
- Staging'da ikki marta 0 farq bilan sinalgan.

## 19. Qolgan ishlar

1. **Kirgan holatdagi live smoke** — sizning login'ingizdan keyin (§13).
2. **Admin Panel** 005e-ga moslashtirilishi kerak (alohida tasdiq bilan, faqat branch'da): Medical Review'ni faqat `medical.review` egasiga ko'rsatish, instructor turi uchun `mark_*` variantlarini yashirish, medical review'ga yuborish formasi faqat SA/EM uchun, oxirgi evidence va medical qarorini ko'rsatish, `evidence_changes_requested` yorlig'i, testlarni yangilash.
3. Keyingi xavfsizlik bosqichlari: 006a (audit), `docs` / `exam_configs` DELETE hardening, staging'da haqiqiy login bilan Admin UI testi.
4. Education Manager, Instructor va Medical Reviewer akkauntlarini endi ochish mumkin. 005e ularning ruxsatlarini server tomonida cheklaydi.
