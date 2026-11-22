# MedAcademy — Migration 005 Production Report

Sana: 2026-11-23 · Production: `buuwjhpzptiiyggybvwr` · Holat: **005 PRODUCTION'DA · PASS · TO'XTATILDI**

**Qo'llangan fayllar:** `005a_learning_structure.sql` + `005_seed_structure.sql` + `005b_evidence_question_system.sql` + **`005c_evidence_governance.sql`** (yangi evidence siyosati).

**Production'ga chiqishdan oldin:** 005c avval lokalda (114/114), keyin staging'da (114/114) sinaldi. Production'ga staging'dagi bilan **bayt-bayt bir xil** to'plam qo'llandi (`22_apply_005.sql` = `staging/005_apply_c.sql`, 176 465 belgi).

**Qo'llanmagan narsalar:** Admin Panel, Migration 006, frontend o'zgarishlari, research API.

## 1. Backup — PASS
`20_backup_pre005.sql`: `backup.*_pre005_20261123`.

| Qamrov | Natija |
|---|---|
| public sxemadagi 18 jadvalning hammasi, to'liq ma'lumot | 18/18 live = backup |
| Muhim jadvallar | profiles 1, docs 20, courses 13, questions 131, exam_configs 13, exam_attempts 2, certificates 0, employees 1 |
| Snapshot'lar: ustunlar, cheklovlar, indekslar, RLS policy, funksiya, trigger, grant | 7/7 |
| **Jami** | **25/25 PASS** |

## 2. Pre-check — PASS
- Abdulaziz Isabaev · abaji2192@gmail.com · super_admin / active / Kardiologiya · org Impuls.
- profiles 1, docs 20, organizations 1, employees 1, departments 10.
- courses 13, questions 131, exam_configs 13.
- exam_attempts 2 (initial 1, preview 1), certificates 0, auth users 1.
- Migratsiyalar 001–004b; 005 hali yo'q edi.

## 3. Migration — PASS
- Bitta tranzaksiyada qo'llandi, xatosiz.
- Supabase'ning odatiy "destructive operations" ogohlantirishi chiqdi. Sababi `drop policy/trigger/constraint if exists` buyruqlari (siyosatlarni qayta yaratish uchun); staging'da ham aynan shu fayl uchun chiqqan.
- DROP TABLE / TRUNCATE / ma'lumot DELETE yo'q. Mavjud urinish va sertifikatlarga tegilmagan.
- Natija: 001,002,003,004a,004b,005a,005b,005c; 131 savol; 2 urinish; 0 sertifikat; 34 modul; 47 dars.

## 4. Post-check — 28/28 PASS
Tekshirilganlar:
- Sxema: 25 ta yangi jadval.
- RLS: yoqilmagan public jadval yo'q.
- FK: `questions.module_id → course_modules` validated.
- Indekslar: +60 ta.
- Ruxsatlar: permissions 45 (29+16), role_permissions 111.
- `anon` grant'lari yo'q.
- `org_id` bo'sh qator yo'q.
- Evidence jadvallari bo'sh (0 manba / 0 bog'lanish / 0 review).
- Baholash sxemalari: 5.
- Savol versiyalari: v1 = 131, matni backup bilan aynan; publications 131.
- Yaroqli savol: 0.
- review_required: 131.
- Ma'lumot: 1 profil, 13 kurs, 131 savol (stem va answer o'zgarmagan), 13 config, 0 sertifikat, docs = backup.
- Urinishlar backup bilan aynan: 2/2.
- Abdulaziz: super_admin / active / Kardiologiya.
- Tuzilma seed: 34 / 47 / 9 / 63.
- Test ma'lumoti 0; auth users 1.

> **Yashirilmaydi — post-check'ning birinchi ishga tushirilishida 1 FAIL:** "FK: CASCADE" = 25. Faqat o'qiydigan diagnostik so'rov quyidagini ko'rsatdi:
> - 23 tasi `auth`, 2 tasi `storage` sxemasida — Supabase'ning tizim jadvallari;
> - `public`'dagi 6 tasi Phase 1 davridan qolgan;
> - **005 jadvallarida CASCADE yo'q.**
>
> Xato tekshiruv so'rovida edi (sxema filtri yo'q edi; lokal bazada `auth` FK'lari yo'qligi sababli ko'rinmagan). So'rov `public` bilan cheklandi, lokalda qayta sinaldi va production'da qayta ishga tushirildi: 28/28 PASS. Migratsiya fayllari o'zgarmadi.

## 5. Data integrity — PASS
- 131 savol: o'chirilmagan; stem va answer backup bilan bir xil; v1 snapshot'lari o'zgarmas.
- 2 ta mavjud urinish (initial 85.7% va preview): backup bilan aynan (`question_versions` ustunidan tashqari, u eski urinishlarda bo'sh).
- Sertifikatlar 0 (o'zgarmagan).
- docs: migratsiyadan keyin 20 (backup bilan teng).
  - Live UI smoke test paytida sahifani qayta yuklaganimda ilova odatdagi `audit` sessiya yozuvini yaratdi, shuning uchun hozir 21 ta. Bu 004 deploy'idagi xatti-harakat bilan bir xil; test ma'lumoti emas.

## 6. RLS — PASS
- Barcha public jadvallarda RLS yoqilgan.
- Anonim foydalanuvchi 43/43 jadvalda rad etildi (X13).
- Live REST: anonim `evidence_sources` so'roviga 401.

## 7. Security — PASS
Regressiya bitta tranzaksiyada bajarilib, oxirida ROLLBACK qilindi.

| ID | Test | Natija | |
|---|---|---|---|
| X13 | Anonim → 43 jadval | 43/43 DENIED | PASS |
| X14 | Employee → boshqa xodim (profil, urinish, tayinlash, progress, sertifikat) | 0 | PASS |
| X15 | Employee → to'g'ri javob (questions, versions, publications) | 0 | PASS |
| X17 | Employee → evidence manbalari / ichki izohlar / review | 0 | PASS |
| X18 | Employee → rolni oshirish (medical_reviewer) | DENIED | PASS |
| X19 | Employee → rolni oshirish (super_admin) | DENIED | PASS |
| X20 | Instructor → biriktirilmagan kurs (savollar / urinish review'i) | 0 / DENIED | PASS |
| X21 | Instructor → biriktirilgan kurs (CARDIO_BASIC) | 11 | PASS |
| X22 | Cross-org: Org B admin → Org A (8 jadval) | 0 | PASS |

## 8. Evidence system — PASS
| ID | Test | Natija | |
|---|---|---|---|
| X04 | Unknown evidence → initial assessment | DENIED | PASS |
| X05 | Unknown evidence → yangi imtihon tanlovi (`question_meta`) | 0 | PASS |
| X06 | Unknown evidence → kurs imtihoni (ETHICS) | DENIED | PASS |
| X16 | Question → evidence bog'lanishi (admin ko'radi) | 1 | PASS |
| X23 | Asosiy manba retracted → review_required, yangi imtihondan chiqarildi | review_required / false / meta 0 | PASS |
| X25 | Conflicting evidence → review_required, imtihonga kirmaydi | review_required / false | PASS |

Evidence siyosati (005c), staging va lokalda 114 test bilan sinalgan:
- outdated / superseded / retracted / conflicting / unknown / review_required / draft / deprecated / archived holatlari → imtihonga **yaroqsiz**.
- Yangi guideline eskisini almashtirsa → eski `superseded`, bog'langan savollar `review_required`. Matn va javob avtomatik o'zgarmaydi.
- Klinik savolni nashr qilish uchun barcha shartlar majburiy:
  - evidence review → `current`;
  - **tekshirilgan (verified)** amaldagi primary_support manba;
  - shu versiya uchun **Medical Review** (medical_reviewer / education_manager / super_admin roli).
  - Instructor'ning review'i yetarli emas.
  - Klinik savolni dalildan ozod qilib bo'lmaydi.
- Klinik bo'lmagan savollar (Ethics, Communication, Reception, Sales): tasdiqlangan asos (hospital policy, national standard, professional code, WHO guidance kabi) yoki sabab bilan ozod qilish kerak.
- Manba ierarxiyasi faqat metadata: primary_authoritative / secondary / educational / institutional. Uni faqat `evidence.review` ruxsati bor inson o'zgartiradi va kim o'zgartirgani yoziladi.
- Admin Panel uchun qarorlar: "Mark Outdated" / "Mark Conflicting" → review_required.

## 9. Question versioning — PASS
- 131 savol: v1 snapshot va v1 nashr yozuvi bor.
- Yangi model (lokal + staging, EL11/EL12/V06):
  - **v1 published + v2 draft → v1 imtihonda qoladi**;
  - v2 tasdiqlangach v2 published bo'ladi, v1 tarixiy versiyaga aylanadi;
  - eski urinish v1 bilan qoladi.
- Versiyalarni tahrirlash yoki o'chirish (hatto SQL orqali ham) bloklangan.

## 10. Exam eligibility — PASS
- Server-side yagona qoida: `_q_exam_eligible()` = `published` + `published_version` + (`evidence_status = current` yoki klinik bo'lmagan savol uchun tasdiqlangan ozod qilish).
- Qo'shimcha himoya: asosiy yoki qo'shimcha manba superseded / retracted bo'lsa yoki ziddiyat bo'lsa — savol yaroqsiz.
- `start_exam` (initial, module, final) va `question_meta` shu qoidani ishlatadi; frontend'ga ishonilmaydi.
- **Production holati: 131 savoldan 0 tasi yaroqli** (siyosat bo'yicha, chunki barchasining evidence holati `unknown`).

## 11. Research integrity — PASS (sxema darajasida)
- Research API ulanmagan (talabga ko'ra).
- Klient `research_results` jadvaliga yoza olmaydi.
- Import qilingan manba: identifikatorlar faqat natijadan olinadi, `origin = research_import`, holati `unverified`.
- Klient "ai_suggested" manba yarata olmaydi.
- AI'ning manba yoki daraja yozadigan yo'li yo'q.
- Production'da birorta manba yaratilmagan (0).

## 12. Historical attempt integrity — PASS
- **X24:** dalil retracted bo'lgandan keyin urinishning bali va natijalari o'zgarmadi, sertifikat amalda qoldi, review ishlaydi.
- **X26:** Abdulaziz'ning initial urinishi backup bilan aynan, review ishlaydi (v1).

## 13. Phase 1 regression — PASS
Rollback bilan tugaydigan tranzaksiya ichida; review'dan o'tgan bank faqat shu tranzaksiyada simulyatsiya qilindi.

| ID | Test | Natija | |
|---|---|---|---|
| X01 | Login (admin sessiyasi) | 1 / super_admin | PASS |
| X02 | Dashboard: kurslar / docs / configlar / modullar / darslar | 13 / 20 / 13 / 34 / 47 | PASS |
| X03 | Kurslar ro'yxati (xodim) | 13 kurs / 47 dars | PASS |
| X07 | Initial assessment (review qilingan bank) | 12 savol, javobsiz | PASS |
| X08 | Imtihonni boshlash (ETHICS): javob/manba/izoh yo'q, versiyalar qayd etildi | true | PASS |
| X09 | Javobni saqlash | true | PASS |
| X10 | Topshirish → 100% + sertifikat | IMP-2026-056C21 (ROLLBACK bilan yo'qoldi) | PASS |
| X11 | Natija: izoh + manbalar; ichki izoh yo'q | true | PASS |
| X12 | Sertifikat tekshiruvi (QR, anonim) | Amalda | PASS |

**Regressiyadan keyingi verify: 28/28 PASS.** Sertifikatlar 0, profil 1, auth users 1, urinishlar 2/2 aynan, test ma'lumoti 0.

## 14. Live UI smoke test (faqat o'qish) — PASS, 1 ta qism bajarilmagan
| Sahifa | Natija |
|---|---|
| Login (mavjud sessiya) | PASS |
| Dashboard (Impuls Medical, 1 xodim) | PASS |
| Xodim profili (Abdulaziz, Kardiologiya, 85.7%) | PASS |
| Kurslar (Mening kurslarim) | PASS |
| Kurs tuzilmasi (katalog: modul/dars) | PASS |
| Savollar banki (kurslar bo'yicha soni) | PASS |
| Initial assessment natijasi (85.7%) | PASS |
| Sertifikatlar (xodim + admin, 0 ta) | PASS |
| Konsol xatolari | 0 — PASS |
| Live REST: modullar 34, darslar 47, versiyalar 131, manbalar 0, `question_meta` 0, anonim → 401 | PASS |
| **Logout** | **BAJARILMADI.** Logout sizni haqiqiy sessiyangizdan chiqarib yuboradi, parolni esa men kirita olmayman. Logout tugmasi frontend'da o'zgarmagan (frontend kodiga tegilmagan). |

Production'da test xodim yoki sertifikat yaratilmadi.

## 15. Git commit
Commit: `feat: deploy migration 005 evidence based education schema`, `backend/migration-005/`. Commit hash quyidagi xabarda ko'rsatiladi.

## 16. Problems
1. Post-check'dagi CASCADE so'rovi xatosi (4-bo'lim) — tuzatildi, 28/28.
2. Live sahifani qayta yuklash docs'ga 1 ta odatdagi audit yozuvini qo'shdi (5-bo'lim).
3. Logout smoke testi bajarilmadi (14-bo'lim).

## 17. Risks
1. **Hozir production'da hech qanday yangi imtihon (initial assessment ham) boshlanmaydi.** Bu yangi evidence siyosatining natijasi: 131 savolning barchasi `review_required`. Foydalanuvchi "Bu kurs uchun dalil (evidence) review'idan o'tgan nashr qilingan savol hali yo'q" xabarini ko'radi.
   - Imtihonlar qayta ochilishi uchun reviewer manba bog'lashi, evidence va medical review qilishi va savolni nashr qilishi kerak.
   - Hozircha buning UI'si yo'q — Admin Panel kerak.
   - Production'da hozircha faqat 1 foydalanuvchi bor (SMTP sababli xodimlar ro'yxatdan o'ta olmaydi), shuning uchun amaliy ta'siri kichik.
2. Eski frontend savol tahrirlash ekrani yangi workflow'ni to'liq ko'rsatmaydi: holatlar "under_review" bo'lib ko'rinadi, savolni o'chirib bo'lmaydi.
3. **Phase 1 davridan qolgan `public` CASCADE FK'lar (6 ta):** attempt_resets, certificates, docs, exam_attempts, exam_configs, profiles. Masalan, auth foydalanuvchi o'chirilsa, uning urinishlari va sertifikatlari ham o'chib ketishi mumkin. Bu "tarix o'zgarmas" talabiga zid xavf. Keyingi migratsiyada RESTRICT'ga o'tkazishni tavsiya qilaman; sizning tasdig'ingiz kerak.
4. DOI / PMID faqat format bo'yicha tekshiriladi (haqiqiy tekshiruv Research Engine bosqichida).
5. Free tier: avtomatik backup yo'q. Qo'lda olingan backup'lar `backup` sxemasida saqlanadi.

## 18. Rollback status
- `29_rollback_005.sql` tayyor, non-destructive. Funksiyalar, trigger'lar, policy'lar va savollarning eski `status` qiymati snapshot'dan tiklanadi; 005 jadvallari saqlanadi va API'dan yopiladi.
- **Lokal sinov:** policy, funksiya va trigger'lar aynan tiklandi; 004 testlari 50/50; qayta deploy'dan keyin 005 testlari 114/114.
- **Staging recovery sinovi:** funksiyalar 64/64, trigger'lar 74/74, policy'lar 97/97, status 132/132 aynan; qayta deploy'dan keyin 114/114.
- **Production'da ishlatilmagan** (faqat real incident uchun).

## 19. Production status
- Migratsiyalar 001–005c; 25 ta yangi jadval; RLS hamma joyda yoqilgan.
- Ma'lumot: 1 profil, 13 kurs, 131 savol (review_required, evidence unknown), 13 config, 2 urinish (o'zgarmagan), 0 sertifikat.
- Yaroqli imtihon savollari: 0.
- Frontend: `9d8f699` (o'zgarmagan). Admin Panel yo'q.

## 20. Recommendation
- **005 production: PASS → TO'XTADIM.**
- Keyingi bosqich: **Phase 2 STEP 3 — Admin Panel**, evidence-based question governance bilan birga. Bu imtihonlarni qayta ochishning yagona xavfsiz yo'li (manba → verify → evidence review → medical review → publish).
- Alohida tasdiq kerak:
  1. Phase 1'dan qolgan CASCADE FK'larni RESTRICT'ga o'tkazish (17-bo'lim, 3-band).
  2. Admin Panel tayyor bo'lguncha imtihonlar yopiq turishi siyosat bo'yicha qabul qilinganmi — yoki klinik bo'lmagan kurslar (Ethics, Communication, Sales, Reception) uchun reviewer tomonidan vaqtinchalik tasdiqlangan asos kiritilsinmi.
