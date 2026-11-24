# MedAcademy — Migration 005e: yakuniy tayyorlik hisoboti

**2026-11-24** · Lokal va staging yakunlandi · Production'da faqat SELECT so'rovlari bajarildi

## YAKUNIY HOLAT

**005e READY FOR PRODUCTION DEPLOYMENT**

| | |
|---|---|
| Migratsiya fayli | `005e_medical_review_authorization.sql` |
| SHA-256 | `06db1d7de5e611a6e7dc738f0d82691d5c44441ae0fcbd13ca909c24a198ffb5` |
| Hajmi | 34 968 bayt |
| Rollback fayli | `005e_rollback.sql` — `56ec44dd2fda79d3998993a271fcb27a6ff397dd51e6461aeb3100fb82a333be`, 6 006 bayt |
| Git | branch `migration-005e`, commit **`bf7c4e7`** (avvalgisi `86fc8ef`) |
| Lokal | 005e 146/146 · rollback/recovery 21/21 · 005d 101/101 · 005 114/114 · 004 50/50 · Phase 1 32/32 |
| Staging | 005e 146/146 · 005d 54/54 · rol matritsasi 62/62 · 005 (staging) 26/26 · 005 to'plami 114/114 · 004 50/50 · rollback 0 farq · qayta qo'llash 0 farq |

---

## 1. Tasdiqlangan qarorlar

| # | Qaror | Bajarilishi |
|---|---|---|
| 1 | `RECEPTION_START` klinik emas, yo'nalishi `communication` | Faqat shu kurs o'zgaradi. Eski qiymat tekshiriladi; kutilmagan qiymat bo'lsa migratsiya to'xtaydi. Rollback `medical`ni tiklaydi |
| 2 | Evidence `changes_requested` savolni yangi imtihonlar uchun yaroqsiz qiladi | `rejected` bilan bir xil ta'sir; sababi alohida: `evidence_changes_requested`. Yangi holat yaratilmadi |
| — | 005e'ning avvalgi qarorlari: `medical.review` faqat MR/SA, MR nashr qilmaydi, `rejected` yaroqsiz qiladi, EM evidence review va manba tekshiruvini saqlaydi | O'zgarmadi |

Yangilangan narsalar faqat 005e fayllarida. 005f yo'q, 006a yo'q. 004, 005 va 005d migratsiyalariga, xodim ilovasiga (`data.js`), Admin Panel kodiga tegilmadi.

## 2. RECEPTION_START tuzatilishi

- **Qayerda hal qilinadi:** klinik yoki klinik emas savolning kursi yo'nalishi (`courses.domain`) bo'yicha `_q_is_clinical` funksiyasida hal qilinadi. Savol darajasidagi tasniflash yo'q va qo'shilmadi.
- **Migratsiya mantiqi (§0c):**

| `RECEPTION_START.domain` | Natija |
|---|---|
| `medical` | `communication`ga o'zgaradi (`... where id = 'RECEPTION_START' and domain = 'medical'`) |
| `communication` | o'zgarish yo'q (idempotent) |
| boshqa qiymat | `005e TO'XTATILDI` xatosi, ustidan yozilmaydi |
| kurs yo'q | o'zgarish yo'q, faqat xabar |

- **Snapshot (§0b):** `backup.security_pre005e`ga `course_domain` (RECEPTION_START = medical) va `course_domains_all` (barcha kurslar) yoziladi. Bu bir marta, oldingi 005e snapshot'i bo'lsa ham bajariladi.
- **Rollback:** kurs hozir `communication` bo'lsa, snapshot'dagi qiymat (`medical`) tiklanadi. Kurs o'chirilmaydi va qayta yaratilmaydi; kontent va savollarga tegilmaydi. `courses` jadvalida trigger yo'q, shuning uchun `updated_at` ham o'zgarmaydi — tiklanish baytma-bayt aniq.
- **Testlar:**
  - RC00: domain = `communication`, Reception savoli klinik emas.
  - RC01: boshqa 13 kursning domain'i snapshot bilan bir xil, farq faqat RECEPTION_START'da.
  - RC02: snapshot'da eski qiymat `medical`.
  - F05: klinik emas kurslar: COMM, ETHICS, RECEPTION_START, SALES.
- **Shoshilinch holat haqidagi savol** (ko'krak og'rig'i, nafas yetishmasligi): tasdiqlanganidek, kurs bo'yicha klinik bo'lmagan oqimda qoladi. Savol darajasidagi tasniflash — kelajakdagi alohida vazifa.

## 3. Evidence `changes_requested` siyosati

| Qatlam | `rejected` | `changes_requested` |
|---|---|---|
| Review effekti | `workflow` published/approved → `review_required`; `evidence_status` current → `review_due` | xuddi shunday |
| `review_reason` | `evidence_rejected` | `evidence_changes_requested` |
| `evidence_events` | `review_due`, `decision = evidence_rejected` | `review_due`, `decision = evidence_changes_requested` |
| Nashr guard'i | oxirgi evidence qarori → rad | oxirgi evidence qarori → rad |
| `_q_exam_eligible` | yaroqsiz | yaroqsiz |

- **Yangi imtihonga yo'llar:** `start_exam` (final, modul, initial) va `question_meta` savollarni faqat `_q_exam_eligible` orqali tanlaydi; nashr faqat `question_workflow` guard'i orqali. Ikkalasi ham yangilandi. Boshqa server yo'li yo'q.
- **O'chirilmaydi:** savol, dalil, review, urinish, sertifikat (G02, G09, Y01–Y10). Review qarori o'zgarmaydi — `question_reviews` o'zgarmas.
- **Qayta yaroqli bo'lish:** tuzatish → yangi evidence review `approved` → (klinikda oxirgi medical `approved`) → nashr. Yangi savol versiyasi talab qilinmaydi (G10: versiya 1 bo'lib qoldi).
- **Oxirgi qaror qoidasi:** `review_seq` bo'yicha eng oxirgi evidence qarori olinadi; "approved bormi" qoidasi ishlatilmaydi.

| Ketma-ketlik | Natija | Test |
|---|---|---|
| Approved → Changes requested | yaroqsiz | CL01, RC06, G08 |
| Approved → Rejected | yaroqsiz | G01, CL06 |
| Changes requested → Approved | yaroqli bo'lishi mumkin | CL03, RC07, G10 |
| Approved → CR → Approved → Rejected | yaroqsiz | CL06 |

## 4. Klinik savollar yaroqliligi

Yaroqli bo'lishi uchun barcha shartlar bir vaqtda bajarilishi kerak:
- `published` va `published_version` bor;
- `evidence_status = current`;
- verified va faol primary_support manba;
- ziddiyatli yoki eskirgan manba yo'q;
- oxirgi evidence qarori `rejected` yoki `changes_requested` emas;
- nashr qilingan versiya bo'yicha oxirgi haqiqiy (MR/SA rolida yozilgan) medical qaror `approved`.

| Holat | Yaroqli? | Test |
|---|---|---|
| Evidence + medical approved | ✅ | D02, CL01, CL03 |
| Evidence rejected | ❌ | G01, CL06 |
| Evidence changes_requested | ❌ | CL01, CL02 |
| Medical rejected | ❌ | D03, D12 |
| Medical changes_requested | ❌ | D06, CL05 |
| Medical yo'q | ❌ | D01, D16, CL04 |
| outdated / conflicting (mark) | ❌ | I05, 005 EL13 |
| superseded / retracted manba | ❌ | I07, 005 E16/E18, role matrix W13/W14 |
| review_required | ❌ | D12, G01 |

## 5. Klinik bo'lmagan savollar yaroqliligi

Medical Review talab qilinmaydi. NC matritsasi — har kurs uchun uchta savol:

| Kurs | Approved → publish → yaroqli | Changes requested | Rejected | Medical review |
|---|---|---|---|---|
| ETHICS | ✅ OK, true | ❌ rad, false | ❌ rad, false | talab qilinmaydi (0) |
| COMM | ✅ | ❌ | ❌ | 0 |
| SALES | ✅ | ❌ | ❌ | 0 |
| RECEPTION_START | ✅ | ❌ | ❌ | 0 |

**Reception holatlari (RC03–RC08):**
- A: approved → nashr → yaroqli, medical'siz.
- B: changes_requested → nashr rad, yaroqsiz.
- C: rejected → nashr rad, yaroqsiz.
- D: nashr qilingan → changes_requested → yaroqsiz → yangi approved → qayta nashr → yaroqli.
- MR nashr qila olmaydi; Super Admin nashr qila oladi.
- Ozod qilingan (`evidence_exempt`) klinik bo'lmagan savol ham oxirgi evidence `rejected` bo'lsa yaroqsiz (G06).

Barcha test ma'lumotlari tranzaksiya ichida yaratiladi va ROLLBACK bilan yo'qoladi. Staging'da yakuniy barmoq izi bilan farq 0.

## 6. Medical Review avtorizatsiyasi (o'zgarmagan)

| Rol | Medical review yarata oladimi |
|---|---|
| Super Admin | ✅ (B01) |
| Medical Reviewer | ✅ (B02) |
| Education Manager | ❌ (B03, I01) |
| Instructor | ❌ (B04, H01, H07) |
| Department Head | ❌ (B05) |
| HR | ❌ (B06) |
| Employee | ❌ (B07) |

- Rol yozilgan paytda saqlanadi va hozirgi ruxsat bermaydi (E01–E06).
- `role_permissions` CHECK constraint `medical.review`ni boshqa rolga berishni bloklaydi (A07–A10).

## 7. Nashr avtorizatsiyasi (o'zgarmagan, evidence qoidasi kengaydi)

- **Nashr qila oladi:** faqat Super Admin yoki Education Manager (`question.publish`), o'z tashkiloti doirasida.
- **Medical Reviewer:** nashr qilmaydi (D07, D08, F03, RC08, X10) va nashrdan chiqarmaydi (D10).
- **Instructor:** nashr qilmaydi (H12).
- **Yangi:** oxirgi evidence qarori `changes_requested` bo'lsa ham nashr rad etiladi (RC04, CL02, G08, NC).

## 8. Bypass testlari

| Yo'l | Instructor | Boshqalar |
|---|---|---|
| `workflow_status` / `status` to'g'ridan-to'g'ri | ❌ H04, H05 | MR ❌ D10 |
| `review_required` | ❌ H04 | EM ✅ (ruxsatli, I04) |
| `mark_outdated` / `mark_conflicting` | ❌ H01–H03 | EM faqat evidence turida (I05, I06) |
| Ziddiyatli dalil bog'lash | ❌ H10 | — |
| Manbani retracted / superseded qilish | ❌ H11 | EM ✅ ruxsatli (I07) |
| Evidence `changes_requested` / `rejected` / `approved` | ❌ H06, CL07 | HR ❌, Employee ❌ (CL07, C06) |
| Medical `rejected` / `changes_requested` | ❌ H07 | EM ❌ (I01) |
| `evidence_exempt`, `published_version`, `current_version` | ❌ H09 | — |
| RPC orqali (`question_reviews`ga yozuvchi funksiya) | yo'q (B14 = 0) | `_q_latest_review` authenticated uchun yopiq (B15) |
| anon | ❌ A13 | — |
| P01–P20 probe'lari (avvalgi audit) | barcha bypass'lar rad | — |

H15: barcha urinishlardan keyin savol `published` va yaroqli qoldi. Hech qaysi ruxsatsiz rol savolni yangi imtihonga yaroqli qila olmadi.

## 9. Lokal test natijalari

Muhit: PGlite, production zanjiri (002/003 → 004 → 005 → test akkauntlari → 005d) + 005e.

| To'plam | Natija | Oldingi |
|---|---|---|
| 005e xavfsizlik | **146/146** | 124/124 (+22 test) |
| 005e rollback / recovery (A: review'siz, B: review bilan) | **21/21** | 21/21 |
| 005d (005e bilan / 005e'siz) | **101/101** / 101/101 | 101/101 |
| 005 (005e bilan / 005e'siz) | **114/114** / 114/114 | 114/114 |
| 004 (standalone; 005 setup bilan) | **50/50**; 50/50 | 50/50 |
| Phase 1 (004 + 005 + 005d + 005e) | **32/32** | 32/32 |
| Staging fayllari lokal: `005d_04` / rol matritsasi / `production/44` | 54/54 / 62/62 / 54/54 | bir xil |

**Yangi va o'zgargan testlar (+22):**
- Reception: RC00–RC08 (9).
- Klinik bo'lmagan matritsa: NC01–NC04 (4).
- Klinik: CL01–CL07 (7).
- G09, G10 (2).
- G08 yangilandi: endi `changes_requested → review_required / review_due / evidence_changes_requested, yaroqsiz, qayta nashr rad` kutiladi. Maqsad saqlandi — `changes_requested` ta'sirini va ma'lumot saqlanishini tekshiradi.
- F05 yangilandi: RECEPTION_START endi klinik emas.
- H06 va H07 ga `changes_requested` qo'shildi.

Testlar kuchsizlantirilmadi. Yangi to'plam avvalgi 005e (`86fc8ef`) ustida ishga tushirilganda 16 ta test FAIL bo'ldi: CL01, CL02, F05, G08, G09, NC01–NC04, RC00–RC03, RC06–RC08. Ya'ni testlar ikkala qarorni haqiqatan tekshiradi.

Lokal muhitdagi eslatma (oldindan mavjud, 005e'ga bog'liq emas): PGlite'da `X13` / `H1` (anon → barcha jadvallar) grant modeli sababli farq qiladi. Staging'da ikkalasi ham PASS.

## 10. Staging test natijalari

Staging `zwzxyikocqxbeyejeyga`, yangilangan 005e qo'llangandan keyin:

| To'plam | Natija |
|---|---|
| 005e | **146/146** (18 guruh) |
| 005d `005d_04_tests` | **54/54** |
| 005 staging regressiyasi (`005d_05`) | **26/26** |
| Rol matritsasi (`005d_06`) | **62/62** |
| 004 to'plami | **50/50** |
| 005 to'plami | **114/114** |

## 11. Rollback natijalari

| Qadam | Natija |
|---|---|
| Boshlang'ich holat S0 (eski 005e, `787a1084…`) | fn `2be00416…`, policy `01080a07…`, RECEPTION = medical |
| Eski 005e rollback (`802aa04e…`) | S_pre = asl 005e'dan oldingi F0 (2026-11-23): **0 farq**; `courses` = `backup.courses_pre005e_20261123` (md5 teng) |
| Yangi 005e rollback (`56ec44dd…`) | S2 = S_pre: **0 farq**; F0 bilan ham **0 farq**; RECEPTION_START = medical |

Rollback'dan keyin quyidagilarning barchasida farq 0: ma'lumot (savollar, review'lar, dalillar, versiyalar, nashrlar, manbalar, urinishlar, sertifikatlar, profillar, kurslar, configlar), sxema (ustunlar, constraint'lar, indekslar), RLS, ruxsatlar (permissions va role_permissions), funksiyalar, trigger'lar, jadval ACL.

Lokal B-rejim: 005e davrida review yozilgan bo'lsa, `reviewer_role_at_creation` va `review_seq` tarixiy metadata sifatida saqlanadi. Funksiya, RLS va ruxsatlar baribir aniq tiklanadi (B05–B08).

## 12. Qayta qo'llash natijalari

- S3 (rollback'dan keyin qayta qo'llash) = S1 (birinchi qo'llash): **0 farq**.
- Regressiya: 005e 146/146, 005d 54/54, 005 to'plami 114/114.
- Barcha testlardan keyingi barmoq izi S3 bilan **0 farq** — test izi qolmadi.
- **Staging yakuniy holati:** yangilangan 005e (SHA `06db1d7d…`), RECEPTION_START = communication.

## 13. Idempotentlik

- Staging'da ikkinchi qo'llash: barmoq izi S1 bilan **0 farq**. Lokal: 2-qo'llash = 1-qo'llash (A01, B01).
- **Takrorlanish yo'q:**
  - `medical.review` qatorlari tashkilotlar soniga teng (A03);
  - CHECK, indeks va constraint bittadan (Z02);
  - snapshot'lar bir marta yoziladi (Z01, RC02);
  - `role_permissions` soni o'zgarmadi (222);
  - RECEPTION_START: ikkinchi marta o'zgarish yo'q.
- Funksiyalar `create or replace`, policy'lar `drop if exists` + `create` — dublikat paydo bo'lmaydi.

## 14. Tashkilot izolyatsiyasi

X01–X15 (005e testlari) va CL07:
- Org A foydalanuvchisi Org B savoli, review'i va dalillari bilan ishlay olmaydi: review yaratish (medical, evidence, `changes_requested`), o'qish va nashr — barchasi rad yoki 0 qator.
- Org B'dagi MR, EM, Instructor ham Org A'ga nisbatan xuddi shunday cheklangan.
- Global manba ikkala tashkilotga ko'rinadi (X06) — mavjud arxitektura bo'yicha.
- Org B o'z savolini o'z MR'i va EM'i orqali nashr qiladi (X09, X12).

## 15. Performance

| So'rov (600 nashr qilingan klinik savol) | 005d | 005e (avval) | 005e (yakuniy) |
|---|---|---|---|
| `question_meta()` — xodim ro'yxati | ~21 ms | ~38 ms | **~37 ms** |
| Savollar banki (EM) | ~24 ms | ~24 ms | ~23 ms |
| Review navbati (1 800 qator) | ~215 ms | ~210 ms | ~215 ms |
| Medical navbat | <1 ms | <2 ms | <1 ms |

Sezilarli o'zgarish yo'q. `changes_requested` mavjud indeksli tekshiruvga (`review_seq`) faqat `in ('rejected','changes_requested')` qo'shdi. Lokal PGlite o'lchovi — nisbiy taqqoslash uchun.

## 16. Production — faqat SELECT tekshiruvi (2026-11-24)

| Tekshiruv | Natija |
|---|---|
| Migratsiyalar | `001…005d`, 005e qatori yo'q ✅ |
| `RECEPTION_START.domain` | `medical` ✅ (o'zgarmagan) |
| 005e obyektlari: `medical.review` ruxsati va qatorlari, `_q_latest_review`, yangi ustunlar, `role_permissions_005e_chk`, `question_reviews_reviewer_role_chk`, `question_reviews_latest_idx`, `backup.security_pre005e` | hammasi 0 / yo'q ✅ |
| Profillar / auth foydalanuvchilar / tashkilotlar | 1 (super_admin, faol) / 1 / 1 — yangi rol yoki akkaunt yo'q ✅ |
| Savollar | 131 ✅ (005d hisoboti bilan bir xil) |
| Urinishlar / sertifikatlar | 2 / 0 ✅ |
| Funksiyalar / policy'lar | 72 / 97; funksiya md5 `88c2bbfa…`, policy md5 `7384de1f…` |
| Sxema barmoq izi | funksiya, policy, constraint, ustun, indeks, trigger, ACL va permissions md5 — **staging'ning 005e'dan oldingi holati bilan aynan bir xil** ✅ |
| 005e o'zgartiradigan 7 funksiya | md5 `32737926…` — lokal va staging bilan bir xil ✅ |
| Yaroqli savollar / review'lar / dalillar | 0 / 0 / 0 |
| `docs` | 24 (005d'dan keyin 23) — ilovaning oddiy login audit yozuvi, 005e'ga bog'liq emas |

Production'ga hech qanday INSERT, UPDATE, DELETE yoki DDL yuborilmadi. So'rov oldidan matnda yozish buyrug'i yo'qligi avtomatik tekshirildi. Xavfli so'rov dialogi chiqmadi.

## 17. Yakuniy SHA-256

| Fayl | SHA-256 | Bayt |
|---|---|---|
| `005e_medical_review_authorization.sql` | `06db1d7de5e611a6e7dc738f0d82691d5c44441ae0fcbd13ca909c24a198ffb5` | 34 968 |
| `005e_rollback.sql` | `56ec44dd2fda79d3998993a271fcb27a6ff397dd51e6461aeb3100fb82a333be` | 6 006 |
| `005e_02_tests.sql` | `b83fcc75de69ca16e13bd184f9d69b5c0328d42e75a7c22dee27ad3642288617` | — |
| `005e_01_fingerprint.sql` | `238355fa10c942728a03a9054a168719c29a4b2a1bbe056f41e0203c429087d7` | — |

- **Lokal fayl = staging'da qo'llangan fayl:** brauzerda yuklangan fayl va SQL editor matni SHA-256 bo'yicha `06db1d7d…` (birinchi va yakuniy qo'llashda tekshirildi).
- **Git fayli:** `migration-005e` branch'idan (`bf7c4e7`) olingan fayl ham `06db1d7d…`, 34 968 bayt. **Lokal = staging = Git.**
- **Avvalgi versiya** (`86fc8ef`, `787a1084…`) staging'dan to'liq olib tashlandi va almashtirildi.

## 18. Git commit

- Branch: `migration-005e` (mavjud). Yangi commit: `fix: finalize 005e reception and evidence eligibility rules`.
- Papka: `backend/migration-005e/`. Yangilangan fayllar: migratsiya, rollback, fingerprint, 005e testlari, lokal natijalar, ushbu hisobot, staging sikli qaydi, production SELECT so'rovi va natijasi.
- `main`'ga merge qilinmagan, PR ochilmagan. Parol, kalit, javob kaliti, soxta dalil yo'q.
- Commit: **`bf7c4e7`**, ota-commit `86fc8ef`, branch `74692ee` (main) ustida. 9 fayl.

## 19. Admin Panelda qolgan blokerlar

005e backend'i tayyor. Admin Panel alohida tasdiq bilan, faqat branch'da quyidagicha moslanadi (avvalgi hisobot §21 bilan bir xil):

1. `pages_evidence.js:75` — "Medical review" varianti faqat `PERMS.can('medical.review')` bo'lsa. Hozir EM'ga ko'rinadi, lekin server rad etadi.
2. `pages_evidence.js:90` — instructor/editorial turi uchun `mark_*` variantlarini yashirish.
3. `pages_evidence.js:100` — "Medical review'ga yuborish" formasi faqat SA/EM uchun.
4. `pages_questions.js:89` — nashr shartlari paneli: oxirgi medical **va** oxirgi evidence qarorini ko'rsatish. `changes_requested` / `rejected` → "tuzatish kerak".
5. `perms.js:26` — medical navbat (`medical.review`) va evidence navbati (`evidence.review`) alohida.
6. Review tarixida `reviewer_role_at_creation`, `review_seq` bo'yicha tartiblash; `review_reason = evidence_changes_requested` uchun yorliq.
7. Admin UI testlari: W11 nashrni EM qiladi; E08 MR bilan; E09 fixture'iga medical tasdiq qo'shish.
8. Boshqa (005e'dan tashqari) blokerlar: staging'da haqiqiy login bilan UI testi; 006a audit; `docs` / `exam_configs` DELETE hardening; branch'ni `main`ga moslash (rebase).

UI xavfsizlik vositasi emas — yuqoridagi barcha holatlarda server rad etadi.

## 20. Production deploy uchun shartlar

**Precheck (faqat SELECT; har biri bajarilmasa — TO'XTASH):**
1. `schema_migrations`: `005d` bor, `005e%` yo'q.
2. `RECEPTION_START.domain = 'medical'`.
3. Funksiya md5 `88c2bbfafacc68c5cfe6f47e1bb5da44` (72 ta), policy md5 `7384de1f13d7253227afc881d887bcd4` (97 ta), constraint `52ce7426…`, ustun `01e21beb…`, indeks `65e14186…`, trigger `b1507cb9…`, ACL `dfa96ba7…`, permissions `41bcebd9…`. Bular 2026-11-24 production o'lchovi.
4. 7 ta maqsadli funksiya md5 `32737926276c9ed1cc5043810c0f7dee`.
5. `question_reviews = 0`; 005e obyektlari yo'q; `backup.security_pre005e` yo'q.
6. Ma'lumot bazasi: savollar 131, urinishlar 2, sertifikatlar 0, profillar 1 (yoki deploy kunidagi qayd etilgan qiymat).

**Deploy tartibi (005d bilan bir xil):**
1. To'liq backup (`005e_00_backup.sql` mantiqi, production nomi bilan): 100% bir xil.
2. Precheck.
3. Apply: SHA `06db1d7d…`, 34 968 bayt — baytma-bayt shu fayl, qo'shimcha SQL yo'q.
4. Barmoq izi: kutilgan o'zgarishlar faqat funksiya, policy, constraint, ustun, indeks, permissions, role_perm, `courses` (RECEPTION_START).
5. `005e_02_tests.sql` (ROLLBACK bilan).
6. Regressiya: `production/44` va `45`ning 005e-ga moslashgan nusxasi (staging nusxasi: `005e_05_regress_005_staging.sql`).
7. Live smoke (logout qilmasdan).
8. `main`'ga commit.

**Kutilgan production ta'siri:** yaroqli savollar 0 → 0; urinish va sertifikatlar o'zgarmaydi. O'zgaradiganlar: 2 ta ruxsat qatori (+1/−1), 1 ta kurs domain'i, 2 ta ustun, 1 ta indeks, 2 ta CHECK, 1 ta yangi ichki funksiya, 7 ta funksiya ta'rifi, 2 ta policy.

**Tavsiya:** EM, Instructor va MR akkauntlari 005e production'ga chiqqandan keyin ochilsin.
