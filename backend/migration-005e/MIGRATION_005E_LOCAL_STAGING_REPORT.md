# MedAcademy — Migration 005e: Medical Review avtorizatsiyasi va nashrni mustahkamlash

**Lokal + staging hisoboti** · 2026-11-24 · Production'ga hech narsa yozilmagan

| | |
|---|---|
| Migratsiya | `005e_medical_review_authorization.sql` — sha256 `787a108454102713ac7bb2eab3fed69e893b34771deb2d91805e8d3cf7fe7c59`, 32 803 bayt |
| Rollback | `005e_rollback.sql` — sha256 `802aa04ec22384bd1716e447746ab54a7d783769e99bd01c9ebea356b2b33a0f` |
| Lokal | 005e: 124/124 · rollback/recovery: 21/21 · 005d: 101/101 · 005: 114/114 · 004: 50/50 · Phase 1: 32/32 |
| Staging | backup 43/43 · apply ×2 (idempotent) · 005e: 124/124 · 005d: 54/54 · role matrix: 62/62 · 005 (staging): 26/26 · 005 suite: 114/114 · 004: 50/50 · rollback: 0 farq · recovery: 0 farq · recovery regression: hammasi PASS |
| Production | Faqat SELECT so'rovlari yuborildi. 005e qo'llanmagan |
| Xulosa | **005e PRODUCTION READY** (production deploy alohida tasdiq bilan) |

---

## 1. Maqsad

Medical Review'ni boshqa review turlaridan ajratish. Medical Review'ni faqat `medical_reviewer` va `super_admin` yozadi. Klinik savolning yangi imtihonlarga yaroqliligi joriy versiya bo'yicha **eng oxirgi** haqiqiy Medical Review qaroriga bog'lanadi. Medical Reviewer savolni nashr qilmaydi. Instruktor nashr qilingan savolni hech qanday yo'l bilan imtihondan chiqara olmaydi. Hammasi server tomonida (RLS / trigger / funksiya) majburiy qilinadi.

## 2. Tasdiqlangan qarorlar

| # | Qaror | 005e'da qanday bajarildi |
|---|---|---|
| 1 | 005e lokal va staging'da quriladi va sinaladi | Bajarildi. Staging yakuniy holati: 005e |
| 2 | Medical Reviewer nashr qilmaydi; nashr — SA va EM, barcha shartlar bilan | MR'dan `question.publish` olib tashlandi. Nashr guard'i rolni tekshiradi (SA/EM). MR nashrdan chiqara ham olmaydi |
| 3 | Rad etilgan evidence review savolni yangi imtihonlar uchun yaroqsiz qiladi | `evidence` + `rejected` → `review_required` holati, `evidence_status ≠ current`, `review_reason = evidence_rejected`. Nashr va yaroqlilik oxirgi evidence qarorini tekshiradi |
| 4 | EM evidence review va manba tekshiruvini saqlaydi, medical review olmaydi | EM: `evidence.review`, `evidence.verify`, `question.publish` saqlandi. `medical.review` berilmaydi va CHECK constraint bilan bloklangan |

## 3. Yaratilgan va o'zgartirilgan fayllar

**Yangi (005e):**

| Fayl | Vazifasi |
|---|---|
| `migrations/005e_medical_review_authorization.sql` | Migratsiya (bitta tranzaksiya) |
| `migrations/005e_rollback.sql` | Snapshot'dan rollback |
| `staging/005e_00_backup.sql` | 43 jadval + sxema snapshot'lari (`*_pre005e_20261123`) |
| `staging/005e_01_fingerprint.sql` | SELECT-only barmoq izi: sxema, RLS, funksiya, ruxsat, ma'lumot |
| `staging/005e_02_tests.sql` | 005e xavfsizlik to'plami (124 test, ROLLBACK) |
| `staging/005e_03_regress_004.sql`, `005e_04_regress_005_suite.sql` | 004 va 005 to'plamlari, natija bitta JSON qatorda (staging uchun) |
| `tests/m005e_local.mjs`, `m005e_rollback_local.mjs`, `lib005e.mjs`, `perf005e.mjs`, `run_sqlfile_005e.mjs`, `mr_probe_005e.mjs`, `run_all_005e.sh` | Lokal harness'lar |

**005e-ga moslashtirilgan test fayllari** (migratsiya emas; o'zgarish faqat 005e o'rnatilganda ishlaydi, 005e'siz natija avvalgidek):

| Fayl | O'zgarish | Sababi |
|---|---|---|
| `tests/004_tests.sql` | "Review'dan o'tgan" simulyatsiyasiga SA medical approval qo'shildi | 005e'da klinik savol medical tasdiqsiz yaroqsiz |
| `tests/005_tests.sql` | Shu simulyatsiya. MR04: nashrni EM qiladi. AI03: EM instructor-turi review yozadi. EL13: EM `evidence` turida mark_outdated. E13: conflicting bog'lashni EM qiladi. E16: guideline almashtirishni EM qiladi | Qaror 2, 4 va instruktor yo'llari yopilgani |
| `staging/005d_05_regression_005.sql` | Simulyatsiyaga SA medical approval | X07 initial assessment banki |
| `staging/005d_06_role_matrix.sql` | Klinik nashrni EM qiladi (W09, W11, W13, W14) | Qaror 2 |

Commit'da bu fayllar asl joyida o'zgartirilmadi. Ular `backend/migration-005e/` papkasiga alohida nusxa sifatida qo'yildi.

**O'zgartirilmagan:** 004, 005, 005d migratsiyalari; `production/*` fayllari; xodim ilovasi; Admin Panel kodi va branch'i; GitHub Pages.

## 4. Sxema o'zgarishlari (faqat additive)

| Obyekt | O'zgarish |
|---|---|
| `question_reviews.reviewer_role_at_creation text` | Yangi ustun: review yozilgan paytdagi rol. CHECK bilan faqat ruxsat etilgan rollar. Eski qatorlarda NULL |
| `question_reviews.review_seq bigint identity` | Yangi ustun: "oxirgi qaror"ning aniq tartibi (bitta tranzaksiyada `created_at` bir xil bo'lishi mumkin) |
| `question_reviews_latest_idx (question_id, review_type, review_seq desc)` | Yangi indeks |
| `role_permissions_005e_chk` | CHECK: `medical.review` faqat MR/SA rolida; MR'ga `question.publish` berilmaydi |
| `backup.security_pre005e` | Rollback snapshot: 7 funksiya ta'rifi, 2 policy, MR publish qatorlari, boshlang'ich sonlar |

Jadval o'chirilmagan, TRUNCATE yo'q, biznes ma'lumoti o'chirilmagan. `question_reviews` immutability trigger'i (005) yangi ustunlarni ham qamraydi.

## 5. Ruxsat o'zgarishlari

| Rol | medical.review | question.publish | evidence.review | evidence.verify | question.review |
|---|---|---|---|---|---|
| super_admin | ✅ (implicit) | ✅ | ✅ | ✅ | ✅ |
| medical_reviewer | ✅ **yangi** | ❌ **olib tashlandi** | ✅ | ✅ | ✅ |
| education_manager | ❌ | ✅ | ✅ | ✅ | ✅ |
| instructor | ❌ | ❌ | ❌ | ❌ | ✅ (faqat instructor/editorial/psychometric turi) |
| department_head / hr / employee | ❌ | ❌ | ❌ | ❌ | ❌ |

- `seed_org_defaults_005` yangilandi: yangi tashkilotlarda ham shu matritsa (test A12).
- Production'da o'zgaradigan qatorlar: `+1` (MR → medical.review), `−1` (MR → question.publish). Production'da 1 tashkilot bor.

## 6. RLS o'zgarishlari

| Policy | Oldin | 005e |
|---|---|---|
| `question_reviews_insert` | `(question.review ∨ evidence.review) ∧ can_see_question` | `org_id = my_org() ∧ (question.review ∨ evidence.review ∨ medical.review) ∧ can_see_question` |
| `question_reviews_select` | `org_id = my_org() ∧ (o'ziniki ∨ (question.review ∨ evidence.review) ∧ can_see)` | Xuddi shu + `medical.review` |

Boshqa 95 ta policy o'zgarmadi. `policy_count` 97 bo'lib qoldi. Hech bir RLS zaiflashtirilmadi.

## 7. RPC / funksiya o'zgarishlari

| Funksiya | O'zgarish |
|---|---|
| `guard_question_review()` | `reviewer_id := auth.uid()`, `reviewer_role_at_creation := my_role()` server o'zi qo'yadi. Faol profil va o'z tashkiloti tekshiriladi. Review faqat joriy yoki nashr qilingan versiya uchun. `medical` → `medical.review` + rol ∈ {MR, SA}. `evidence` → `evidence.review`. Boshqa turlar → `question.review`. `mark_outdated` / `mark_conflicting` faqat evidence yoki medical turida |
| `question_review_effects()` | Evidence `rejected` → yaroqsiz (§11). Medical `rejected` / `changes_requested` (nashr qilingan versiya, MR/SA) → `review_required`. Mark qarorlari faqat evidence yoki medical turida |
| `question_workflow()` | Nashr faqat SA/EM (+ `question.publish`) va o'z tashkiloti. Oxirgi evidence qarori `rejected` bo'lsa nashr yo'q. Klinik savol: joriy versiya bo'yicha oxirgi haqiqiy medical qaror = `approved`. Nashrdan chiqarish faqat SA/EM. `review_required`'ga qaytarish: `evidence.review` yoki `medical.review`. AI savol qoidasi tarixiy rol bilan |
| `_q_exam_eligible()` | Himoya qatlami: oxirgi evidence `rejected` → false. Klinik savol: nashr qilingan versiya bo'yicha oxirgi haqiqiy medical = `approved`. plpgsql'ga o'tkazildi (§18) |
| `guard_question_evidence()` | Nashr qilingan savolning dalil bog'lanishini o'zgartirish faqat `evidence.review` |
| `guard_evidence_source()` | Manbani superseded / retracted / withdrawn qilish yoki `supersedes_id` faqat `evidence.review` |
| `seed_org_defaults_005()` | MR: `question.publish` → `medical.review` |
| `_q_latest_review(text,int,text)` **yangi** | Ichki funksiya (EXECUTE: hech kimga). 005d kategoriya reyestriga `internal` deb yozildi |

- `authenticated` chaqira oladigan RPC'lardan hech biri `question_reviews`'ga yozmaydi (B14 = 0).
- anon EXECUTE: 1 (faqat `verify_certificate`) — o'zgarmadi.

## 8. Klinik oqim

```
draft → evidence bog'lash (instructor/EM, verified primary_support)
      → Evidence Review (EM/MR/SA: evidence.review) ─ approved → evidence_status = current
      → Medical Review (faqat MR/SA: medical.review), joriy versiya
            oxirgi qaror = approved ? ── yo'q → nashr rad etiladi
      → Publish (faqat EM/SA: question.publish + server shartlari)
      → yangi imtihonlarda (_q_exam_eligible = true)
nashrdan keyin: MR rejected/changes_requested · evidence rejected · mark_outdated/conflicting · manba retracted/superseded
      → review_required (yangi imtihonlardan chiqadi; tarixiy urinish/sertifikat o'zgarmaydi)
```

"Klinik" qoidasi o'zgarmadi: kurs `domain`'i ∈ `content_policies.clinical_domains` (standart: medical, public_health, safety). Mutaxassislik bo'yicha qattiq kodlash yo'q.

## 9. Klinik bo'lmagan oqim

- Ethics, Communication, Sales va institutsional siyosat savollariga Medical Review talab qilinmaydi.
- Talab: tasdiqlangan evidence (asos) yoki `evidence_exempt` + sabab (EM/SA, `evidence.review`).
- Testlar: F01 (ETHICS evidence → EM publish → yaroqli), F02 (ozod qilish → yaroqli), F03 (MR publish → rad), F04 (asossiz → rad), F06 (klinik savolni ozod qilish → rad).
- ⚠️ **Mavjud konfiguratsiya topilmasi (o'zgartirilmadi):** `RECEPTION_START` kursining `domain`'i `medical`. Shuning uchun u hozir **klinik** hisoblanadi. Agar Reception klinik bo'lmasligi kerak bo'lsa, bu kurs domain'ini o'zgartirish bilan hal qilinadi. Bu kontent qarori — siz hal qilasiz.

## 10. Oxirgi qaror mantiqi

Qoida: `review_type = 'medical'`, `version_no` = tekshirilayotgan versiya, `reviewer_role_at_creation ∈ {medical_reviewer, super_admin}` bo'lgan qatorlar orasidan `review_seq` bo'yicha eng oxirgisining `decision` qiymati `approved` bo'lishi kerak. "Kamida bitta approved bor" qoidasi ishlatilmaydi.

| Ketma-ketlik | Natija | Test |
|---|---|---|
| Approved → Rejected | ❌ nashr yo'q, yaroqsiz | D03 |
| Rejected → Approved | ✅ nashr, yaroqli | D04 |
| Approved → Approved | ✅ | D05 |
| Approved → Changes requested | ❌ | D06 |
| Nashrdan keyin Rejected | `review_required`, yaroqsiz, qayta nashr rad | D12, D13 |
| v1 approved, kontent → v2 | v2 nashr rad (v1 tasdig'i hisoblanmaydi), v1 yaroqli qoladi | D14 |
| v2 uchun MR approved | v2 nashr, `published_version = 2` | D15 |

**Tarixiy rol:**
- Rol yozilgan paytda saqlanadi va o'zgarmaydi (Y07).
- Instruktor davridagi "medical" yozuv hisoblanmaydi, keyin u MR bo'lsa ham (E01, E02 — P20 yopildi).
- MR keyinchalik rolini yo'qotsa, yozilgan paytda vakolatli bo'lgan qarori tarixiy yozuv sifatida haqiqiy qoladi (E04). U yangi qaror yoza olmaydi (E05).
- Faolsiz profil yoza olmaydi (E06).
- 005e'dan oldingi (rolsiz) yozuvlar medical review sifatida haqiqiy emas. Production'da bunday yozuv yo'q (`question_reviews = 0`).

## 11. Evidence rad etish xatti-harakati

`review_type = 'evidence'`, `decision = 'rejected'` yozilganda:

| Maydon | Qiymat |
|---|---|
| `evidence_status` | `current` bo'lsa → `review_due`, aks holda o'zgarmaydi (mavjud holat qayta ishlatildi, yangi holat yaratilmadi) |
| `workflow_status` | `published` / `approved` → `review_required` |
| `review_reason` | `evidence_rejected` (rad etish aniq ko'rinadi) |
| `evidence_events` | `review_due` hodisasi: `{"decision": "evidence_rejected", "workflow_before", "evidence_before"}` (G03) |

- Savol, dalil bog'lanishlari va review yozuvlari saqlanadi (G02). Urinish va sertifikatlar o'zgarmaydi (Y01–Y03).
- **`evidence rejected` → `yangi imtihon yaroqliligi = false` ikki qatlamda:**
  1. `workflow_status` `published` emas.
  2. `_q_exam_eligible` va nashr guard'i oxirgi evidence qarori `rejected` bo'lsa rad etadi. Bu klinik bo'lmagan, dalildan ozod qilingan savollarda ham ishlaydi (G06, G07).
- Keyingi `approved` evidence review holatni tiklaydi va qayta nashr imkonini beradi (G05).
- `changes_requested` evidence qarori Qaror 3'ga kirmaydi, holat o'zgarmaydi (G08). Kerak bo'lsa alohida qaror qiling.

## 12. Nashr avtorizatsiyasi

| Shart | Klinik | Klinik emas |
|---|---|---|
| Rol: SA yoki EM + `question.publish` | ✅ | ✅ |
| O'z tashkiloti | ✅ | ✅ |
| `evidence_status` ∉ {conflicting, outdated, superseded, review_due} | ✅ | ✅ |
| Oxirgi evidence qarori ≠ rejected | ✅ | ✅ |
| `evidence_status = current` | ✅ | yoki `evidence_exempt` |
| Verified, active primary_support | ✅ | — |
| Joriy versiya bo'yicha oxirgi haqiqiy medical = approved | ✅ (policy bo'yicha) | — |

Bypass yo'llari ham yopiq (D08, H12): `status = 'approved'`, `draft_status = 'publish'`, `published_version` maydonini to'g'ridan-to'g'ri o'zgartirish. Nashrdan chiqarish (published → boshqa holat) ham faqat SA/EM (D10, H05).

## 13. Instruktor bypass testlari

Nashr qilingan, yaroqli klinik savol (H00) ustida:

| # | Yo'l | Natija |
|---|---|---|
| H01 | medical `mark_outdated` | DENIED |
| H02 | instructor `mark_conflicting` | DENIED |
| H03 | editorial / psychometric `mark_*` | DENIED / DENIED |
| H04 | `workflow_status = review_required` | DENIED |
| H05 | draft / deprecated / archived; `status` archived / draft | 5× DENIED |
| H06 | evidence review rejected / approved | DENIED / DENIED |
| H07 | medical review rejected | DENIED |
| H08 | `evidence_status` / `review_reason` to'g'ridan-to'g'ri | DENIED / DENIED |
| H09 | `evidence_exempt` / `published_version` / `current_version` | 3× DENIED |
| H10 | conflicting_evidence bog'lash / turini o'zgartirish / o'chirish | DENIED / DENIED / 0 qator |
| H11 | manbani retracted / superseded; `supersedes_id` bilan yangi manba | 3× DENIED |
| H12 | boshqa savolni publish / draft_status=publish / status=approved | 3× DENIED |
| H13 | o'zini MR sifatida tayinlash | DENIED |
| H14 | kontent tahriri | ruxsat (yangi draft v2); v1 imtihonda qoladi |
| H15 | yakuniy holat | published / current, yaroqli — hech bir yo'l ta'sir qilmadi |
| H16 | normal oqim: draft savolga dalil bog'lash | ruxsat |

- Avvalgi auditdagi P01–P20 probe'lari 005e ustida qayta ishga tushirildi. P04, P05, P08–P16, P19, P20 endi rad etiladi.
- P17 (klinik emas oqim) ishlaydi. P18 (immutability) saqlangan.
- H10 va H11 auditda topilmagan **yangi** yo'llar edi: instruktor `evidence.manage` orqali nashr qilingan savolni review'ga tushira olardi. Ular ham yopildi.

## 14. Education Manager testlari

| # | Test | Natija |
|---|---|---|
| I01 | EM medical review (approved / rejected) | DENIED / DENIED |
| I02 | EM yolg'iz: evidence + instructor approved → publish (P08) | DENIED |
| C01, C02 | Evidence review va manba tekshiruvi | OK |
| I03 | MR'ga medical tayinlash | OK |
| I04 | Nashr qilingan savolni review_required'ga qaytarish | OK |
| I05 | Evidence `mark_outdated` | OK → review_required / outdated |
| I06 | Instructor-turi `mark_conflicting` | DENIED |
| I07 | Manbani retracted qilish → bog'langan savollar review_required | OK |
| D02, D11 | Barcha shartlar bajarilganda publish | OK |

## 15. Tashkilot izolyatsiyasi

Org B'dagi test foydalanuvchi tranzaksiya ichida navbat bilan MR / EM / Instructor rolida sinaldi (ROLLBACK).

| # | Test | Natija |
|---|---|---|
| X01 | Org A MR → Org B medical | DENIED |
| X02 | Org A EM → Org B evidence | DENIED |
| X03 | Org A EM → Org B publish | 0 qator, o'zgarmadi |
| X04 | Org A savoliga Org B manbasi | DENIED |
| X05 | Org A SA → Org B review / manba / savol | 0 / 0 / 0 |
| X06 | Global manba ikkala tomonga | 1 / 1 |
| X07, X08 | Org B MR → Org A medical / o'qish | DENIED / 0 |
| X09 | Org B MR o'z savoliga | OK |
| X10 | Org B MR publish | DENIED |
| X11 | Org B EM → Org A publish / o'qish | 0 / 0 |
| X12 | Org B EM o'z savolini publish | OK, yaroqli |
| X13 | Org B EM medical | DENIED |
| X14 | Org B instructor → Org A | DENIED / 0 |
| X15 | Org B SA → Org A medical | DENIED |

## 16. Tarixiy o'zgarmaslik

| # | Test | Natija |
|---|---|---|
| Y01, Y02 | Test urinishi va sertifikati baytma-bayt bir xil | ✅ |
| Y03 | Mavjud barcha urinish va sertifikatlar (md5) | ✅ |
| Y04 | Fixture'dan oldingi review'lar va savol versiyalari (md5) | ✅ |
| Y05, Y06 | `question_reviews` UPDATE / DELETE, hatto platforma SQL | DENIED |
| Y07 | `reviewer_role_at_creation` ni keyin o'zgartirish | DENIED |
| Y08 | `question_versions` tahriri | DENIED |
| Y09 | v1, v2 saqlangan | ✅ |
| Y10 | Evidence rad etilgandan keyin ham tarixiy urinish natijasi o'zgarmagan | ✅ |

Staging'da apply → test → rollback → recovery → test siklidan keyin ma'lumot barmoq izi (savol, review, evidence, versiya, manba, urinish, sertifikat, profil) boshlang'ich holat bilan **0 farq**.

## 17. Lokal test natijalari

Muhit: PGlite, production zanjiri (002/003 → 004 → 005 → test akkauntlari → 005d) + 005e.

| To'plam | Kutilgan | 005e bilan | 005e'siz |
|---|---|---|---|
| 005e xavfsizlik (15 guruh) | — | **124/124** | — |
| 005e rollback / recovery (A: review'siz, B: review bilan) | — | **21/21** | — |
| 005d | 101/101 | **101/101** | 101/101 |
| 005 | 114/114 | **114/114** | 114/114 |
| 004 (standalone va 005 setup bilan) | 50/50 | **50/50** | 50/50 |
| Phase 1 (004 + 005 + 005d zanjiri) | 32/32 | **32/32** | 32/32 |
| 005d staging fayllari: `005d_04` / role matrix / `production/44` | 54 / 62 / 54 | 54 / 62 / 54 | 54 / 62 / 54 |
| Admin Panel UI testlari (mock + 005e, vaqtinchalik variant) | 85 | 84/86 (§21) | 85/85 |

**Qonuniy o'zgarishlar (005e xatti-harakati sababli):**
1. 005 testlari MR04, AI03, EL13, E13, E16 va role matrix W09/W11/W13/W14 eski siyosatni (MR nashr qiladi, EM medical yozadi, instruktor guideline almashtiradi) kutardi. Ular endi ruxsatli rol bilan bajariladi va avvalgidek o'tadi.
2. Test simulyatsiyalari ("review'dan o'tgan" SQL) endi medical approval'ni ham simulyatsiya qiladi. 005e klinik savolni medical tasdiqsiz yaroqsiz deb biladi — bu STEP 7 talabi.
3. 005d S06 ("tasniflanmagan funksiya"): `_q_latest_review` 005d reyestriga `internal` deb yozildi.
4. 005d F04: data snapshot `audit_logs`, `permissions`, `role_permissions` farqini ko'rsatdi — bu 005e'ning ruxsat o'zgarishi va uning audit yozuvi. Test 005e'dan keyingi holatga nisbatan solishtiradi.

**Eslatmalar:**
- Phase 1: `matching` testi tasodifiy imtihonda match-savol tushsagina chiqadi (31 yoki 32 qator). Bu oldindan mavjud va FAIL emas.
- Lokal PGlite'da `X13` / `H1` (anon → barcha jadvallar) muhit sababli farq qiladi (default grant modeli). 005e'siz ham shunday. Staging'da ikkalasi ham PASS.

## 18. Staging test natijalari

Staging `zwzxyikocqxbeyejeyga` (medacademy-staging):

| Qadam | Natija |
|---|---|
| 1. Backup (`*_pre005e_20261123`) | 43 jadval, 43/43 bir xil, 1 510 qator; 97 policy, 72 funksiya, 77 trigger, 286 constraint |
| 2. Baseline barmoq izi (F0) | migrations 001…005d; fn 72; policy 97; MR publish qatorlari 2; eligible 0 |
| 3. 005e apply | OK: medical.review → medical_reviewer; MR publish → 0; savollar 132, urinishlar 1 o'zgarmadi |
| 3b. Qayta apply (idempotentlik) | Barmoq izi F1 = F1b, **0 farq** |
| 4. 005e xavfsizlik to'plami | **124/124** |
| 5. Regressiya | `005d_04` 54/54 · role matrix 62/62 · 005 (staging) 26/26 · 005 suite 114/114 · 004 50/50 |

Phase 1 oqimlari staging'da 004 va 005 to'plamlari ichidagi Phase 1 testlari orqali qamraldi (start_exam, submit, sertifikat, review, xodim cheklovlari).

**Performance** (lokal PGlite, 600 ta nashr qilingan klinik savol, 1 800 review):

| So'rov | 005d | 005e |
|---|---|---|
| `question_meta()` (xodim) | ~16 ms | ~38 ms |
| Savollar banki (EM) | ~23 ms | ~24 ms |
| Review navbati (EM, 1 800 qator) | ~210 ms | ~210 ms |
| Medical navbat | <2 ms | <2 ms |

- N+1 muammo yo'q: yaroqlilik bitta server so'rovi ichida savol boshiga 2 ta indeksli qidiruv bilan hisoblanadi, klientdan qo'shimcha so'rov yo'q.
- Birinchi SQL-funksiya varianti ~250 ms edi (har chaqiruvda qayta rejalashtirish). plpgsql'ga o'tkazilgach ~38 ms; natijalar bir xil (600/600).
- Nashr guard'i faqat nashr paytida ishlaydi (bitta qator).

## 19. Rollback natijasi

- Staging'da `005e_rollback.sql`: medical.review qatorlari 0, MR publish qatorlari 2 ga qaytdi, `_q_latest_review` olib tashlandi. 005e davrida review yozilmagani uchun ustunlar ham olib tashlandi.
- **Barmoq izi F2 = F0: 0 farq** — funksiyalar (md5), policy'lar, constraint'lar, ustunlar, indekslar, trigger'lar, jadval ACL, ruxsatlar va barcha ma'lumot md5'lari.
- `schema_migrations`ga `005e-rollback-<vaqt>` qatori qo'shildi (005d kabi), `005e` qatori olindi.
- Lokal B-rejim: 005e davrida review yozilgan bo'lsa, rollback funksiya / RLS / ruxsatlarni aynan tiklaydi. `reviewer_role_at_creation` va `review_seq` esa tarixiy metadata sifatida **saqlanadi** — ma'lumot o'chirilmaydi (B05, B05b). Review qatorlari o'chirilmaydi (B07).

## 20. Recovery natijasi

- Rollback'dan keyin 005e qayta qo'llandi: **F3 = F1, 0 farq** (funksiya md5 `2be00416…`, policy md5 `01080a07…`).
- Recovery regressiyasi: 005e 124/124 · `005d_04` 54/54 · 005 suite 114/114 · 004 50/50.
- Barcha testlardan keyingi yakuniy barmoq izi F3 bilan 0 farq — staging'da test izi qolmadi.
- **Staging yakuniy holati: 005e qo'llangan** (talab bo'yicha).

## 21. Admin Panel moslik topilmalari

Admin Panel kodi **o'zgartirilmadi** va deploy qilinmadi. Moslik vaqtinchalik test varianti bilan tekshirildi (mock + 005e, asl fayllar tiklangan):

- Avvalgi 85 testdan 84 tasi o'tadi.
- Yangi W10b: MR'da Publish tugmasi ko'rinmaydi. UI buni `question.publish` yo'qligidan to'g'ri bajaradi.
- 2 ta FAIL kutilgan:
  - **E08:** EM'ga UI hali "Medical review" variantini ko'rsatadi. Server uni rad etadi — bu quyidagi 1-o'zgarishni tasdiqlaydi.
  - **E09:** test fixture'i klinik savolni medical tasdiqsiz "published" qiladi; 005e uni yaroqsiz deydi.

**Kerakli o'zgarishlar** (alohida tasdiq bilan, faqat branch'da):

| # | Fayl | O'zgarish |
|---|---|---|
| 1 | `js/admin/pages_evidence.js:75` | `canMed = PERMS.can('medical.review')` (SA implicit). Rolga qarab tekshiruv olib tashlanadi. EM va instruktorga "Medical review" variantini ko'rsatmaslik |
| 2 | `js/admin/pages_evidence.js:90` | Instructor/editorial turida `mark_outdated` / `mark_conflicting` variantlarini ko'rsatmaslik (server baribir rad etadi) |
| 3 | `js/admin/pages_evidence.js:100` | "Medical review'ga yuborish" formasi faqat SA/EM uchun (RLS faqat ularga ruxsat beradi). Hozir `question.review` bilan instruktorga ham ko'rinadi |
| 4 | `js/admin/pages_questions.js:89` | Nashr shartlari paneli: "Medical review mavjud" o'rniga joriy versiya bo'yicha **oxirgi** medical qaror (`review_seq` bo'yicha) va `reviewer_role_at_creation ∈ {MR, SA}`. Faqat ma'lumot uchun |
| 5 | `js/admin/pages_questions.js:103` | Publish tugmasi: `question.publish`. 005e'dan keyin MR'da yo'q — o'zgarish shart emas, test qo'shish kerak |
| 6 | `js/admin/perms.js:26` | Medical navbat bo'limi `medical.review` bilan; evidence navbati `evidence.review` bilan ajratiladi |
| 7 | Review tarixi | `reviewer_role_at_creation` ustunini ko'rsatish; `review_seq` bo'yicha tartiblash |
| 8 | `tests/admin/admin_tests.py` | W11 publish'ni EM qiladi; MR uchun W10b; E08 MR bilan; E09 fixture'iga medical approval |

UI xavfsizlik vositasi emas: yuqoridagi barcha holatlarda server rad etadi (§13, §14).

## 22. Production deploy tavsiyasi

**005e PRODUCTION READY**

Production holati (2026-11-24, faqat SELECT):
- migrations 001…005d; 1 ta tashkilot; 1 ta profil (super_admin, faol).
- `question_reviews` 0; nashr qilingan savol 0; yaroqli savol 0; urinishlar 2; sertifikatlar 0.
- MR → question.publish: 1 qator; `medical.review` kaliti yo'q; funksiyalar 72.
- 005e o'zgartiradigan 7 funksiyaning production md5'i (`32737926…`) lokal tahlil bazasi bilan **aynan bir xil**, ya'ni snapshot va testlar production kodiga mos.
- **Ta'sir:** production'da hech bir savolning yangi imtihonga yaroqliligi o'zgarmaydi (0 → 0). Hech bir urinish yoki sertifikat o'zgarmaydi. Faqat 2 ta ruxsat qatori o'zgaradi (+1 / −1).

Production qadami alohida tasdiqdan keyin (005d tartibida):
1. To'liq backup: `staging/005e_00_backup.sql` bilan bir xil fayl, production nomi bilan.
2. Precheck: `005e_01_fingerprint.sql` bilan baseline (yuqoridagi qiymatlar bilan solishtirish).
3. Apply: staging'da PASS bo'lgan fayl **baytma-bayt** (sha256 `787a1084…7c59`).
4. Tekshiruv: barmoq izi, `005e_02_tests.sql` (ROLLBACK).
5. Regressiya — `production/45_regression_005_after_005d.sql` ning 005e-ga moslashgan nusxasi kerak. Staging nusxasi shu commit'da: `005e_05_regress_005_staging.sql`; production fayli bundan alohida tayyorlanadi.
6. Live smoke (logout qilmasdan).
7. `main`'ga commit.

Production deploy'dan oldin qaror kerak:
1. **RECEPTION_START domain'i:** hozir `medical`, ya'ni klinik. Reception klinik bo'lmasligi kerakmi?
2. **Evidence `changes_requested`:** savolni yangi imtihonlardan chiqarishi kerakmi? Hozir chiqarmaydi.

Eslatma: production'da EM / Instructor / MR akkauntlarini 005e production'ga chiqqandan keyin ochish tavsiya etiladi.

Kirish jurnali: staging yakuniy holati 005e. Production'ga yozish yo'q. Admin Panel va xodim ilovasi o'zgarmagan. 006a yaratilmagan.
