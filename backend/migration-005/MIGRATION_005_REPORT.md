# MedAcademy — Migration 005 hisoboti (LOCAL + STAGING)

Sana: 2026-11-22 · Holat: **LOCAL PASS · STAGING PASS · PRODUCTION'GA QO'LLANMAGAN**
Fayllar: `backend/migrations/005a_learning_structure.sql`, `005_seed_structure.sql`, `005b_evidence_question_system.sql`; testlar: `backend/tests/005_test_setup.sql`, `005_tests.sql`.

**Natija qisqacha:** 005 testlari lokal 90/90 va staging 90/90 PASS. 004 regressiyasi (005 ustida) lokal 50/50 va staging 50/50 PASS. Phase 1 SQL testlari lokal 32/32 PASS. Migratsiya idempotent: lokal va staging'da 2 martadan qo'llandi, xatosiz. Hech qanday FAIL yashirilmagan (staging'dagi 3 ta oraliq FAIL va ularning sababi 25-bo'limda).

## 1. Existing schema (audit)
- `courses` (13): text PK, `org_id`, `domain`, `status`. Modul va darslar faqat frontend `data.js` faylida bor edi (DB'da yo'q).
- `questions` (131):
  - text PK; `course_id` va `module_id` to'liq to'ldirilgan (131/131).
  - `explanation` 131/131, `difficulty` 131/131, `topic` 131/131.
  - `specialty` 0/131.
  - `status`: hammasi `approved`.
  - Dalil maydoni faqat erkin matn (`evidence`) va 5 ta savolda bor: "ESC 2021/2023 HF", "ESC 2023 ACS", "ESC 2024 Hypertension", "Resuscitation Council UK 2021".
- `exam_configs` (13), `exam_attempts`, `certificates`: o'zgartirilmadi (faqat `exam_attempts` ga 1 ustun qo'shildi).
- Rollar `profiles.role` orqali boshqariladi; ruxsatlar 004 dagi `permissions` / `role_permissions` jadvallarida.

## 2. New tables (25)
| Guruh | Jadvallar |
|---|---|
| Ta'lim tuzilmasi | `course_modules`, `lessons`, `course_assignments`, `lesson_progress`, `learning_paths`, `learning_path_courses`, `course_instructors`, `org_invitations` |
| Evidence | `content_policies`, `medical_topics`, `evidence_grading_schemes`, `evidence_sources`, `evidence_source_topics`, `question_evidence` |
| Versiya / review | `question_versions`, `question_publications`, `question_review_assignments`, `question_reviews`, `question_quality_scores` |
| Research / AI / monitoring | `research_queries`, `research_results`, `ai_jobs`, `evidence_summaries`, `evidence_monitors`, `evidence_events` |

## 3. Modified tables (faqat ADD; hech narsa o'chirilmadi)
- `courses`: qo'shilgan ustunlar `code`, `description`, `scope_type`, `created_at`. Kod tashkilot ichida unique.
- `questions`: qo'shilgan ustunlar:
  - `code`, `scope_type`, `topic_id`, `subtopic`, `clinical_setting`, `target_roles[]`, `target_level`, `learning_objective`, `guideline_topic`;
  - `workflow_status`, `evidence_status`, `last_evidence_reviewed_at`, `evidence_review_due_at`;
  - `evidence_exempt` (+ sabab), `current_version`, `published_version`, `ai_job_id`;
  - `module_id` uchun FK (`course_modules`), validate qilingan.
  - Eski `status` va `evidence` ustunlari saqlangan; `status` avtomatik sinxronlanadi.
- `exam_attempts`: `question_versions jsonb` ustuni (savol → versiya xaritasi).
- `profiles.role` va `role_permissions.role` CHECK cheklovlariga `medical_reviewer` va `content_author` rollari qo'shildi.
- Funksiyalar yangilandi:
  - Imtihon: `start_exam`, `submit_exam`, `get_attempt_review`, `question_meta`, `admin_reset_attempts`, `_attempt_payload`, `_q_full`.
  - Tizim: `handle_new_user`, `on_org_created`.
- RLS yangilandi: `questions` (select/insert/update; delete siyosati olib tashlandi) va `exam_attempts` (select).

## 4. Course architecture
- Ierarxiya: **Organization → Course → Module → Lesson**.
- Mavjud `courses` jadvali almashtirilmadi; text PK saqlandi. Yangi kurslar generatsiya qilingan ID va tashkilotga xos `code` oladi, shuning uchun global PK to'qnashuvi yo'q.
- `scope_type` ustuni (`organization` / `global`) qo'shildi. Imtihon dvigateli hozircha faqat tashkilot kurslari bilan ishlaydi (28-bo'lim).

## 5. Module architecture
- `course_modules`: `id` (text; mavjud `CB1`, `ETH1` va hokazo ID'lar saqlangan), `org_id`, `course_id` (RESTRICT), `title`, `description`, `order_index`, `status` (draft / published / archived), vaqt belgilari.
- `data.js` dan 34 ta modul seed qilindi, yangi kontent yaratilmadi.
- 131 savolning barchasi o'z kursining moduliga FK bilan bog'langan.

## 6. Lesson architecture
- `lessons`: `content_type` qiymatlari text / video / document / presentation / clinical_case / quiz. Qo'shimcha maydonlar: `content`, `content_meta jsonb` (video URL va shunga o'xshashlar uchun), `estimated_minutes`, `status`.
- `data.js` dan 47 ta dars ko'chirildi: 46 tasi text, 1 tasi clinical_case.
- Frontend hali `data.js` dan o'qiydi. DB nusxasi Admin Panel uchun tayyor.

## 7. Assignment architecture
- `course_assignments`: statuslar assigned / in_progress / completed / overdue / cancelled.
- Bir xodim–kurs juftligi uchun faqat bitta faol tayinlash bo'ladi (partial unique).
- Avtomatik o'zgarishlar:
  - `assigned_by` server tomonidan qo'yiladi.
  - Xodim o'ziga kurs tayinlay olmaydi va statusni o'zi o'zgartira olmaydi.
  - Birinchi progress yozilganda status → `in_progress`.
  - Server sertifikati berilganda status → `completed`.
  - `mark_overdue_assignments()` — kelajakdagi scheduled job uchun.
- `lesson_progress`: xodim faqat o'z yozuvini yarata va yangilay oladi. Egalik maydonlari (`lesson_id`, `employee_id`, `org_id`, `started_at`) o'zgarmaydi. `completed` holatida progress avtomatik 100%.

## 8. Learning Path architecture
- `learning_paths` (tashkilot ichida unique `code`) va `learning_path_courses` (tartib, majburiylik).
- `data.js` dagi 9 ta akademiya seed qilindi: Resident Starter, Residency Development, Junior Doctor, Doctor Professional Development, Nursing, Sanitary, Doctor Assistant, Reception, Hospital Administration.
- 63 ta bog'lanish: core kurslar har bir path'da + akademiyaga xos kurslar.

## 9. Instructor architecture
- `course_instructors`: kurs–xodim, status active / inactive. Biriktirishni `instructor.assign` ruxsati bor foydalanuvchi qiladi.
- `is_course_instructor()` yordamchisi orqali instruktor faqat biriktirilgan kurslar bilan ishlaydi:
  - savollar (ko'rish / tahrirlash / yaratish);
  - modul va darslar;
  - tayinlashlar, progress, urinishlar va review;
  - urinishlarni tiklash.
- Biriktirilmagan instruktor savollar bankini umuman ko'rmaydi.

## 10. Evidence architecture
- `evidence_sources` maydonlari:
  - **Doira:** global kutubxona (`org_id` = NULL) yoki tashkilot manbasi (`scope_type` bilan qat'iy CHECK).
  - **Manba turi** (16 ta): guideline, systematic review, meta-analysis, RCT, cohort, case-control, observational, narrative review, textbook, official public health guidance, consensus, expert opinion, national protocol, local protocol, hospital SOP, other.
  - **Bibliografiya:** chiqaruvchi tashkilot, guideline nomi va versiyasi, mualliflar, yil, jurnal, DOI, PMID, PMCID, ISBN, URL, nashr / kirish sanasi, abstract summary.
  - **Darajasi:** `evidence_level` + `evidence_level_scheme`.
  - **Mahalliylik:** `jurisdiction` (international … institutional), `country_code`.
  - **Holat va bog'liqlik:** status (active / superseded / retracted / withdrawn …), `supersedes_id`.
  - **Tekshiruv:** `verification_*`, `external_metadata`.
- **Citation integrity:**
  - DOI, PMID, PMCID va URL format CHECK orqali tekshiriladi.
  - RCT, cohort va shunga o'xshash manbalar kamida bitta identifikatorsiz kiritilmaydi.
  - Guideline uchun tashkilot va versiya majburiy.
  - `verified` holati kim, qachon va qaysi manbadan tekshirilgani yozilmasdan qo'yilmaydi va faqat `evidence.verify` ruxsati bilan beriladi.
  - DOI / PMID tashkilot doirasida takrorlanmaydi.
- Global kutubxonaga API orqali yozib bo'lmaydi; u faqat platforma (service role / SQL) orqali yangilanadi.
- **Soxta manba yaratilmagan.** Testdagi manbalar "TEST … (sinov)" deb belgilangan va faqat staging'da.

## 11. Question → Evidence relationship
- `question_evidence`: ko'pdan-ko'pga bog'lanish. Bitta savol bir nechta manbaga bog'lanishi mumkin.
- Maydonlar: `relationship_type` (primary_support / additional_support / background / conflicting_evidence), `citation_text`, `supporting_claim` (ichki), `section_reference`, `recommendation_class`, `level_of_evidence`.
- Boshqa tashkilot manbasini bog'lab bo'lmaydi; global manbaga bog'lash mumkin.
- Har o'zgarishda `recompute_question_evidence()` ishlaydi, lekin faqat holatni pasaytiradi:
  - retracted / withdrawn manba → `outdated`;
  - conflicting manba → `conflicting`;
  - primary manba superseded → `superseded`;
  - muammo hal qilinsa → `review_due`.
- **`current` holati faqat inson evidence review'i bilan qo'yiladi**, manbani bog'lashning o'zi yetarli emas.

## 12. Question versioning
- `question_versions`: o'zgarmas snapshot'lar (UPDATE / DELETE hatto SQL orqali ham bloklangan). Mavjud 131 savol uchun v1 yaratildi.
- Kontent (stem / options / answer / explanation / type / image) o'zgarsa:
  - `current_version` +1 bo'ladi, yangi versiya draft holatida review'ga tushadi;
  - **imtihonda nashr qilingan eski versiya (`published_version`) xizmat qilishda davom etadi.**
- `question_publications`: har bir nashr qayd etiladi (versiya, dalil holati, dalil snapshot'i, kim nashr qilgan).
- Imtihon:
  - `start_exam` har urinishda savol versiyalarini `exam_attempts.question_versions` ga yozadi;
  - `submit_exam` va `get_attempt_review` aynan o'sha versiyadan baholaydi va ko'rsatadi;
  - migratsiyadan oldingi urinishlar v1 bilan ishlaydi.
- **Tarixiy natijalar buzilmaydi** (test V06: v2 nashr qilingandan keyin ham eski urinish v1 matnini ko'rsatadi).

## 13. Guideline versioning
- Guideline uchta ma'lumot bilan ajratiladi: `organization` + `guideline_name` + `guideline_version` (unique).
- Yangi manba `supersedes_id` bilan kiritilsa:
  - shu doiradagi eski manba avtomatik `superseded` bo'ladi;
  - `new_guideline_version` hodisasi yoziladi;
  - unga bog'langan savollar `superseded` bo'ladi va review'ga tushadi.
- Tashkilot manbasi global guideline'ni almashtirsa, global yozuv o'zgarmaydi, lekin tashkilot savollari baribir flag qilinadi.
- **Savol avtomatik o'chirilmaydi.**

## 14. Research source architecture
- `research_queries`: so'rov matni, bazalar va filtrlar. Ruxsat etilgan bazalar: pubmed, pmc, cochrane, crossref, who, cdc, nice, esc, aha_acc, ada, idsa, uz_moh, other_society.
- `research_results`:
  - tashqi baza, identifikator, DOI / PMID / URL, asl `raw_metadata` va `retrieved_at` majburiy;
  - **klientga INSERT ruxsati yo'q** — natijani faqat kelajakdagi server integratsiyasi (service role / edge function) yozadi; soxta natija kiritib bo'lmaydi.
- `import_research_result()` natijani manbaga aylantiradi: identifikatorlar natijadan ko'chiriladi, manba `unverified` holatda qoladi.
- **Fake API yoki fake research ma'lumot yaratilmagan.** Hozir hech qanday tashqi API ulanmagan.

## 15. AI research workflow
- `ai_jobs`: vazifa turlari question_review, evidence_search, evidence_summary, question_generation, update_detection, guideline_comparison.
  - Klient faqat vazifa yarata oladi; `output` va `status` ni faqat server yozadi.
  - Xodim AI vazifasini ishga tushira olmaydi.
- `evidence_summaries`:
  - faqat mavjud va ruxsat etilgan manbalarga asoslanadi;
  - AI xulosasi inson review'isiz `approved` bo'lmaydi.
- AI yaratgan savol:
  - har doim `draft` holatida kiritiladi;
  - **inson (instructor / medical reviewer) `approved` review'isiz nashr qilinmaydi** — bu qoida Education Manager uchun ham amal qiladi.
- Jarayon: **Draft → Evidence Check → Human Review → Approved → Published.**

## 16. Medical review workflow
- Savol `workflow_status` bosqichlari: draft → evidence_review → instructor_review → approved → published → deprecated / archived.
- `question_review_assignments`: reviewer'ga aniq savollar tayinlanadi. Reviewer faqat tayinlangan (yoki review qilgan) savollarni ko'radi.
- `question_reviews`:
  - turlari evidence / medical / instructor / editorial / psychometric;
  - qarorlar approved / changes_requested / rejected / deprecate_recommended;
  - `internal_notes` faqat ichki foydalanish uchun;
  - yozuvlar o'zgarmas; `reviewer_id` ni soxtalashtirib bo'lmaydi.
- Klinik domen (`content_policies.clinical_domains`; standart: medical, public_health, safety) savolini nashr qilish uchun shartlar:
  - `question.publish` ruxsati;
  - primary_support manba;
  - evidence_status = `current` (ya'ni evidence review tasdiqlangan);
  - conflicting / outdated / superseded holatdagi savol hech kim tomonidan nashr qilinmaydi.
- Dalildan ozod qilish (`evidence_exempt`) faqat `evidence.review` ruxsati bilan va sabab ko'rsatilgan holda beriladi.
- `question_quality_scores`: o'lchovlar evidence quality, clinical relevance, clarity, difficulty calibration, distractor quality, guideline currency, review status, psychometric (0–100; inson / AI / psixometrik). Murakkab AI scoring yo'q, faqat sxema.
- Monitoring:
  - `evidence_events`: guideline_update, new_guideline_version, retraction, major_new_evidence, review_due, superseded, conflict_detected.
  - `evidence_monitors`: haftalik / oylik va hokazo; hozir **o'chirilgan**.
  - `refresh_evidence_freshness()` — kelajakdagi cron uchun.

## 17. Multi-organization content model
- Bitta arxitektura, takrorlanuvchi jadvallarsiz: `scope_type` = global / organization.
- Evidence va topic'lar: `org_id` NULL bo'lsa global (masalan, ESC, WHO). Mahalliy SOP / protokol tashkilot doirasida qoladi.
- Mahalliy moslashuv (O'zbekiston uchun):
  - `jurisdiction` (national / local / institutional) va `country_code` (`UZ`);
  - manba turlari national_protocol / local_protocol / hospital_sop.
- Global guideline va mahalliy protokol alohida ko'rinadi. Ular bir-biriga zid bo'lsa, `conflicting_evidence` → review jarayoni ishga tushadi.
- Kurs va savollarda `scope_type` bor, lekin global kursdan imtihon olish hali yo'q (28-bo'lim).

## 18. New-user organization model
- `org_invitations`: email, rol, bo'lim, lavozim, muddat (14 kun).
  - Faqat `invitation.manage` ruxsati (HR) bilan yuboriladi.
  - super_admin roli taklif qilinmaydi.
- `handle_new_user` uchun taklifnoma bo'lsa:
  - foydalanuvchi o'sha tashkilot, rol va bo'limga avtomatik `active` holatda tushadi;
  - `employees` yozuvi yaratiladi;
  - taklifnoma `accepted` bo'ladi.
- Taklifnoma bo'lmasa — **avvalgi xatti-harakat o'zgarmaydi** (Impuls, `pending`). Bu production ro'yxatdan o'tishini buzmaslik uchun ataylab saqlangan.

## 19. RLS
- 25 ta yangi jadvalning barchasida RLS yoqilgan va `anon` uchun yopiq.
  - API orqali hard delete yo'q, faqat `question_evidence` bog'lanishini `evidence.review` ruxsati bilan olib tashlash mumkin.
  - Versiya va review jadvallari o'zgarmas.
- Kim nimani ko'radi:
  - **Employee:** faqat o'z tayinlashi va progressi; manbalar, bog'lanishlar, review izohlari, versiyalar va javob kalitlari ko'rinmaydi.
  - **Instructor:** biriktirilgan kurslar.
  - **Dept Head:** o'z bo'limining tayinlashlari va progressi.
  - **Medical Reviewer:** tayinlangan savollar va dalil kutubxonasi.
  - **Super Admin / Education Manager:** o'z tashkiloti doirasida to'liq.
- Imtihon payload'ida javob, manba, izoh va ichki notes yo'q.
- Natijadan keyin xodimga ko'rsatiladi: izoh + **tasdiqlangan manbalar ro'yxati** (sarlavha, tashkilot, versiya, yil, DOI / PMID / URL). `supporting_claim` va `internal_notes` ko'rsatilmaydi.

## 20. Permissions
16 ta yangi kalit: `assignment.view/manage`, `progress.view`, `learning_path.manage`, `instructor.assign`, `question.review/publish/deprecate`, `evidence.view/manage/review/verify`, `research.run`, `ai.use`, `quality.score`, `invitation.manage`.

| Rol | Yangi ruxsatlar |
|---|---|
| Education Manager | barcha ta'lim va evidence ruxsatlari |
| Instructor | assignment (o'z kursida), progress, question.review, evidence.view/manage, research, ai, quality |
| Medical Reviewer (yangi) | question.view/review/publish/deprecate, evidence.view/manage/review/verify, research, ai, quality |
| Content Author (yangi) | question.create/edit (biriktirilgan kurs), evidence.view/manage, research, ai |
| HR | assignment.view, progress.view, invitation.manage |
| Dept Head | assignment.view, progress.view (o'z bo'limi) |

Yangi tashkilot yaratilganda ruxsatlar avtomatik seed qilinadi.

## 21. Indexes
- Tez-tez ishlatiladigan yo'llar uchun indekslar: modul va dars tartibi, xodim tayinlashlari va statusi, progress, path kurslari, instruktor biriktirishlari.
- Evidence: DOI / PMID / guideline unique, `supersedes_id`, org + status.
- Savollar: imtihonga yaroqli savollar uchun partial indeks (`published_version` NOT NULL), topic, org + evidence_status.
- Versiya, nashr, review va sifat jadvallari: (question, version) bo'yicha.
- Hodisalar: ochiq hodisalar va savol bo'yicha.
- Keraksiz indeks qo'shilmagan.

## 22. Foreign keys
- Barcha yangi FK'lar **RESTRICT** yoki **SET NULL** (CASCADE yo'q).
- `questions.module_id → course_modules` (validate qilingan).
- `question_publications`, `question_reviews` va `question_quality_scores` → `question_versions (question_id, version_no)` composite FK.
- Cross-org bog'lanish DB trigger'i orqali bloklanadi (`enforce_same_org_005`, `guard_question_evidence`).

## 23. Existing data impact
- **Staging'da 005 dan oldin va keyin bir xil:** 131 savol (Org A), 13 config, 5 docs, 1 urinish, 0 sertifikat.
- Test natijalari iz qoldirmadi: urinish, sertifikat, tayinlash, progress va review — barchasi testdan keyin 0 yoki o'zgarmagan.
- `docs` o'chirilmagan; `data.js` frontend manbasi bo'lib qoladi.
- DROP TABLE / TRUNCATE / DELETE yo'q.
- **Frontend'ga ta'siri (005 production'ga chiqsa):**
  - API orqali yangi savol darhol nashr qilinmaydi: avval draft, so'ng review.
  - Klinik savollarni eski "approved" tugmasi orqali tasdiqlash evidence review talab qiladi.
  - Savolni o'chirish API'da yopiq; o'rniga archive / deprecate ishlatiladi.
  - Production'da instruktor yo'q, shuning uchun instruktor cheklovi hozir hech kimga ta'sir qilmaydi.
  - Bularni Admin Panel'da hisobga olish kerak.

## 24. 131-question impact
- 131 savolning barchasi saqlangan.
  - Har biri uchun `workflow_status = published`, `published_version = 1` va v1 snapshot.
  - Ularning 95 tasi klinik domenda (medical 59, safety 24, public_health 12); qolgan 36 tasi ethics, communication va sales.
- **`evidence_status = unknown`** — hech biri avtomatik "evidence-based" deb belgilanmagan.
  - `evidence_review_due_at` = migratsiya sanasi + 90 kun.
- Eski erkin matnli `evidence` 5 ta savolda bor ("ESC 2023 ACS Guidelines" va boshqalar). Ular **avtomatik manbaga aylantirilmadi** (uydirma metadata yaratmaslik uchun). Medical reviewer ularni DOI / versiyasi bilan qo'lda bog'lashi kerak.
- `specialty` 0/131 — reviewer to'ldiradi.
- Imtihonlarda bu savollar avvalgidek ishlaydi (R01–R08).

## 25. Security tests
- Barcha 90 ta 005 testi (lokal va staging'da bir xil natija) quyidagi jadvalda. Lokal: 90/90 PASS. Staging: 90/90 PASS.
- 004 regressiyasi (005 ustida): lokal 50/50, staging 50/50.
- **Staging'dagi oraliq FAIL (yashirilmaydi):** 004 testlarini 005 setup'idan keyin birinchi marta ishga tushirganda A5, A8 va R1 FAIL bo'ldi.
  - **Sabab:** testlar Org B'da kontent yo'q deb hisoblagan, 005 setup esa Org B'ga o'z kursi, savoli va configini qo'shgan. Org B admini **o'z** kontentini ko'rgan, R1 esa barcha tashkilotlarni sanagan. Izolyatsiya buzilishi emas.
  - **Tuzatish:** testlar Org A bo'yicha aniq filtrlandi va qayta ishga tushirildi: 50/50 PASS.
- Lokalda ishlab chiqish jarayonida topilgan va tuzatilgan xatolar:
  1. RLS INSERT … RETURNING'da savol ko'rinmasdi → qator bo'yicha `can_see_question_row` yordamchisi kiritildi.
  2. Review tugagach reviewer savolni nashr qila olmasdi → tayinlash statusi `completed` bo'lganda ham ruxsat beriladigan qilindi.

| ID | Guruh | Test | Kutilgan | Natija |
|---|---|---|---|---|
| S01 | Kurs tuzilmasi | Organization → Course → Module → Lesson seed (data.js dan) | 34 modul / 47 dars / 9 path / 63 bog'lanish | **PASS** |
| S02 | Kurs tuzilmasi | 131 savol modul FK: modul topilmagan / boshqa kursga tegishli | 0 | **PASS** |
| S03 | Kurs tuzilmasi | Mavjud bo'lmagan modulga savol (FK) | DENIED | **PASS** |
| S04 | Kurs tuzilmasi | Org B moduli Org A kursiga (cross-org, DB trigger) | DENIED | **PASS** |
| S05 | Kurs tuzilmasi | Savol/darsi bor modulni o'chirish (FK RESTRICT) | DENIED | **PASS** |
| S06 | Kurs tuzilmasi | Xodim nashr qilingan darslarni ko'radi | 47 / draft 0 | **PASS** |
| S07 | Kurs tuzilmasi | Xodim dars yaratadi | DENIED | **PASS** |
| AS01 | Tayinlash | Education Manager kurs tayinlaydi (assigned_by server tomonidan) | ALLOWED, assigned_by = edu manager | **PASS** |
| AS02 | Tayinlash | Xodim o'ziga kurs tayinlaydi | DENIED | **PASS** |
| AS03 | Tayinlash | Xodim o'z tayinlashini ko'radi | 1 | **PASS** |
| AS04 | Tayinlash | Xodim boshqa xodim tayinlashini ko'radi | 0 | **PASS** |
| AS05 | Tayinlash | Xodim o'z tayinlashini "completed" qiladi | 0 qator | **PASS** |
| AS06 | Tayinlash | Dept Head: o'z bo'limi / boshqa bo'lim tayinlashlari | 1 / 0 | **PASS** |
| AS07 | Tayinlash | Instructor biriktirilmagan kursga tayinlaydi | DENIED | **PASS** |
| AS08 | Tayinlash | Instructor o'z kursiga tayinlaydi va faqat o'z kursi tayinlashlarini ko'radi | ALLOWED, ko'radi=1 | **PASS** |
| AS09 | Tayinlash | Takroriy faol tayinlash | DENIED | **PASS** |
| P01 | Progress | Xodim o'z progressini yozadi → tayinlash in_progress | in_progress | **PASS** |
| P02 | Progress | Xodim boshqa xodim nomidan progress yozadi | DENIED | **PASS** |
| P03 | Progress | Xodim progress egalik maydonini o'zgartiradi | DENIED | **PASS** |
| P04 | Progress | Xodim o'z progressini yakunlaydi (100%) | 100 | **PASS** |
| P05 | Progress | Boshqa xodim / Dept Head (shu bo'lim) progressni ko'rishi | 0 / 1 | **PASS** |
| L01 | Learning path | Xodim nashr qilingan path'larni ko'radi (faqat Org A) | 9 | **PASS** |
| L02 | Learning path | Xodim path yaratadi | DENIED | **PASS** |
| L03 | Learning path | Education Manager path + kurs qo'shadi | ALLOWED | **PASS** |
| IN01 | Instructor | Instructor: biriktirilgan kurs savollari / boshqa kurslar | 11 / 0 | **PASS** |
| IN02 | Instructor | Instructor biriktirilmagan kurs savolini tahrirlaydi | 0 qator | **PASS** |
| IN03 | Instructor | Biriktirilmagan instructor savollar bankini ko'radi | 0 | **PASS** |
| IN04 | Instructor | Instructor o'zini boshqa kursga biriktiradi | DENIED | **PASS** |
| IN05 | Instructor | Instructor biriktirilmagan kurs urinishini (javoblar bilan) ko'radi | DENIED | **PASS** |
| MR01 | Medical reviewer | Reviewer: tayinlashdan oldin / keyin ko'rinadigan savollar | 0 / 1 | **PASS** |
| MR02 | Medical reviewer | Reviewer manbani tekshiradi (verified_by server tomonidan) | verified / reviewer | **PASS** |
| MR03 | Medical reviewer | Evidence review tasdig'i → current + keyingi review sanasi; reviewer_id soxtalashtirilmaydi | current / ~24 oy / reviewer=a…08 | **PASS** |
| MR04 | Medical reviewer | Reviewer evidence current savolni nashr qiladi | published_version = 1 | **PASS** |
| MR05 | Medical reviewer | Org A reviewer → Org B manba/savollari | 0 | **PASS** |
| E01 | Evidence | Xodim → manbalar, bog'lanishlar, review izohlari, versiyalar, hodisalar | 0 | **PASS** |
| E02 | Evidence | API orqali global manba yaratish | DENIED | **PASS** |
| E03 | Evidence | Noto'g'ri DOI formati | DENIED | **PASS** |
| E04 | Evidence | Noto'g'ri PMID formati | DENIED | **PASS** |
| E05 | Evidence | RCT identifikatorsiz (DOI/PMID/URL yo'q) | DENIED | **PASS** |
| E06 | Evidence | Guideline tashkilot/versiyasiz | DENIED | **PASS** |
| E07 | Evidence | "verified" — kim/qachon/qayerdan tekshirilgani yo'q | DENIED | **PASS** |
| E08 | Evidence | Instructor manba qo'shadi (created_by server tomonidan) | created_by = instructor | **PASS** |
| E09 | Evidence | API orqali yaratilgan savol darhol nashr qilinmaydi | draft / unknown | **PASS** |
| E10 | Evidence | Manba bog'langani o'zi "current" qilmaydi (inson review kerak) | unknown | **PASS** |
| E11 | Evidence | Instructor manbani "verified" qiladi (evidence.verify yo'q) | DENIED | **PASS** |
| E12 | Evidence | Klinik savolni evidence review'siz nashr qilish (Education Manager) | DENIED | **PASS** |
| E13 | Evidence | Conflicting evidence qo'shildi → evidence_status | conflicting | **PASS** |
| E14 | Evidence | Conflict hodisasi (evidence_events) yozildi | >=1 | **PASS** |
| E15 | Evidence | Conflicting savolni nashr qilish (reviewer ham) | DENIED | **PASS** |
| E16 | Evidence | Yangi guideline (2026) → eski (2024) superseded, savol superseded, savol o'chmaydi | superseded / superseded / bor | **PASS** |
| E17 | Evidence | new_guideline_version hodisasi | 1 | **PASS** |
| E18 | Evidence | Retracted manba qo'llab-quvvatlovchi sifatida → outdated | outdated | **PASS** |
| E19 | Evidence | API orqali evidence_status ni to'g'ridan-to'g'ri "current" qilish | DENIED | **PASS** |
| E20 | Evidence | Instructor savolni dalildan ozod qiladi (evidence.review yo'q) | DENIED | **PASS** |
| V01 | Versiyalash | Nashr tarixi: versiya + dalil snapshot'i saqlanadi | 1 | **PASS** |
| V02 | Versiyalash | Nashr qilingan savol tahrirlandi → v2 draft, imtihonda v1 qoladi | cur=2 / pub=1 / draft | **PASS** |
| V03 | Versiyalash | API orqali published_version ni o'zgartirish | DENIED | **PASS** |
| V04 | Versiyalash | Eski versiyani tahrirlash (hatto SQL orqali) | DENIED | **PASS** |
| V05 | Versiyalash | Eski versiyani o'chirish | DENIED | **PASS** |
| V06 | Versiyalash | Savol v2 nashr qilingandan keyin eski urinish review'i v1 matnini ko'rsatadi | v1 matn | **PASS** |
| V07 | Versiyalash | Migratsiyadan oldingi (versiyasiz) urinish review'i ishlaydi | savollar > 0 | **PASS** |
| AI01 | AI workflow | AI yaratgan savol "published" bilan kiritilsa ham → draft | draft | **PASS** |
| AI02 | AI workflow | AI savolni inson review'isiz nashr qilish (Education Manager) | DENIED | **PASS** |
| AI03 | AI workflow | Inson (medical) review'dan keyin AI savol nashr qilinadi | published_version = 1 | **PASS** |
| AI04 | AI workflow | Klient AI natijasini o'zi yozib qo'yadi (output/status) | output=null, queued | **PASS** |
| AI05 | AI workflow | Xodim AI vazifasini ishga tushiradi | DENIED | **PASS** |
| RS01 | Research | Klient research natijasini (soxta) yozadi | DENIED | **PASS** |
| RS02 | Research | Ruxsat etilmagan research bazasi | DENIED | **PASS** |
| RS03 | Research | Mavjud bo'lmagan manbaga asoslangan xulosa | DENIED | **PASS** |
| M01 | Multi-org | Org A Super Admin → Org B (modul, dars, path, tayinlash, manba, savol, versiya, kurs) | 0 | **PASS** |
| M02 | Multi-org | Org B Admin: o'z savoli / Org A manbalari / global kutubxona | 1 / 0 / >=1 | **PASS** |
| M03 | Multi-org | Org B savoliga Org A manbasini bog'lash | DENIED | **PASS** |
| M04 | Multi-org | Org A xodimiga Org B kursini tayinlash | DENIED | **PASS** |
| M05 | Multi-org | Org B xodimi → Org A darslari/modullari/path'lari | 0 | **PASS** |
| N01 | Anonim | Anonim → 005 dagi 25 ta yangi jadval | 25/25 DENIED | **PASS** |
| INV01 | Yangi foydalanuvchi | Taklifnoma bilan ro'yxatdan o'tish → org/rol/bo'lim, faol, employee yozuvi | org A / employee / active / Terapiya / employee bor | **PASS** |
| INV02 | Yangi foydalanuvchi | Taklifnomasiz ro'yxatdan o'tish → avvalgidek pending (faollashtirish HR'da) | pending | **PASS** |
| INV03 | Yangi foydalanuvchi | Taklifnoma orqali super_admin berish | DENIED | **PASS** |
| INV04 | Yangi foydalanuvchi | Xodim taklifnoma yuboradi | DENIED | **PASS** |
| Q131 | 131 savol | 131 savol saqlangan; "evidence-based" deb belgilanmagan (unknown); v1 snapshot | 131 / 131 / 131 | **PASS** |
| R01 | Phase 1 regressiya | Imtihon payload: javob, manba, ichki izoh yo'q | true | **PASS** |
| R02 | Phase 1 regressiya | Urinish savol versiyalarini qayd qiladi | har savol uchun v1 | **PASS** |
| R03 | Phase 1 regressiya | To'g'ri javob → 100% + sertifikat + QR | 100 / Amalda | **PASS** |
| R04 | Phase 1 regressiya | Sertifikat → tayinlash avtomatik completed | completed | **PASS** |
| R05 | Phase 1 regressiya | Natijadan keyin: izoh + manba ro'yxati bor, ichki izoh/supporting_claim yo'q | true | **PASS** |
| R06 | Phase 1 regressiya | Initial assessment (12 savol) | 12 | **PASS** |
| R07 | Phase 1 regressiya | Fail → retake bloklanadi | DENIED | **PASS** |
| R08 | Phase 1 regressiya | Deprecated savollar imtihon va meta'dan chiqadi (o'chirilmaydi) | meta 0 / imtihon yo'q / savollar bor | **PASS** |
| R09 | Phase 1 regressiya | Xodim questions jadvalini (javob kaliti) ko'ra olmaydi | 0 | **PASS** |
| R10 | Phase 1 regressiya | Xodim o'ziga yangi rol (medical_reviewer) | DENIED | **PASS** |

## 26. Evidence integrity tests
- E03–E07: noto'g'ri DOI / PMID, identifikatorsiz RCT, versiyasiz guideline, asoslanmagan "verified" — barchasi bloklandi.
- E10, E19, MR03: manba bog'lash "current" qilmaydi; "current" faqat inson evidence review'i bilan qo'yiladi.
- E13–E18: conflicting, superseded va retracted holatlari to'g'ri aniqlandi va hodisa yozildi.
- E12, E15: dalilsiz yoki conflicting savol nashr qilinmadi.
- AI01–AI05, RS01–RS03: AI va research natijalarini soxtalashtirib bo'lmaydi.

**Barchasi PASS.**

## 27. Phase 1 regression
- R01–R10 (staging + lokal) barchasi PASS. Tekshirilgan narsalar:
  - imtihon payload'ida javob yo'q; to'g'ri javoblar → 100% + sertifikat + QR;
  - initial assessment 12 savol; fail → retake bloki;
  - xodim javob kalitlarini va yangi rollarni ololmaydi;
  - deprecated savollar imtihondan chiqadi.
- `sql_test.mjs` (Phase 1, 004+005 bilan): 32/32 PASS.
- 004 testlari: 50/50 PASS.

## 28. Risks
1. **Ochiq qaror kerak:** evidence holati `outdated`, `superseded` yoki `conflicting` bo'lgan, lekin nashr qilingan savol hozir imtihonda qolmoqda. U review'ga flag qilinadi; faqat `deprecated` holati uni imtihondan chiqaradi. Bunday savollarni avtomatik chiqarish kerakmi — sizning qaroringiz.
2. Eski frontend: savol yaratish/tasdiqlash oqimi yangi qoidalarga to'liq mos emas (23-bo'lim). 005 production'dan oldin yoki u bilan birga Admin Panel kerak.
3. Modul va darslar DB va `data.js` da ikki nusxada. Frontend DB'ga o'tguncha sinxron saqlash kerak.
4. Global kurs/savollardan imtihon olish hali yo'q (faqat `scope_type`).
5. DOI / PMID faqat format bo'yicha tekshiriladi. Haqiqiy Crossref / PubMed tekshiruvi kelajakdagi server integratsiyasida bo'ladi.
6. `evidence_monitors` va scheduled job'lar hali ishga tushirilmagan (ataylab).
7. Free tier: avtomatik backup yo'q. 005 dan oldin 004 dagidek qo'lda backup va snapshot olish shart.
8. Staging'da `medical_reviewer` / `content_author` rollari bilan frontend'ning UI xatti-harakati tekshirilmagan (UI hali bu rollarni bilmaydi).

## 29. Rollback strategy
- 004 dagi usul qo'llanadi: production'da migratsiyadan oldin `backup.*_pre005_<sana>` jadvallari va RLS policy, funksiya, trigger snapshot'lari olinadi.
- Rollback skripti (004 dagi `19_rollback_004.sql` andozasida):
  - funksiyalar va policy'larni snapshot'dan tiklaydi;
  - 005 trigger'larini (`questions_workflow_trg`, `questions_versioning_trg`, `certificates_assignment_trg` va boshqalar) olib tashlaydi;
  - yangi jadvallarni API'dan yopadi.
- Ma'lumot o'chirilmaydi: yangi ustunlar va jadvallar qoladi, ammo ishlatilmaydi.
- `questions.status` doim sinxron saqlangani uchun Phase 1 RPC'lari tiklangach eski `status = 'approved'` filtri bilan darhol ishlaydi.
- 005 rollback skripti hali yozilmagan va sinalmagan. Production rejasini tasdiqlasangiz, uni lokalda 004 dagidek (policy va funksiyalarning aynan tiklanishi) sinab beraman.

## 30. Production recommendation
- **005 hozircha production'ga qo'llanmadi** va sizning alohida tasdig'ingizsiz qo'llanmaydi.
- Texnik jihatdan (local + staging PASS) tayyor. Lekin tavsiyam: 005 ni **Admin Panel (Phase 2 STEP 3) bilan birga** chiqarish, chunki yangi nashr qoidalari eski savol-yaratish UI'sini cheklaydi (28-bo'lim, 2-band).
- Chiqarishdan oldin:
  1. 28-bo'lim, 1-banddagi qaror (outdated savollarni imtihondan avtomatik chiqarish).
  2. Rollback skriptini lokalda sinash.
  3. Production backup va snapshot.
  4. 004 dagidek: pre-check → apply → verify → regressiya.

To'xtadim. Keyingi qadam faqat sizning tasdig'ingiz bilan.
