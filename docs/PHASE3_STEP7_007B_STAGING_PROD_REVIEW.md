# MedAcademy — PHASE 3 STEP 7 — 007b STAGING DEPLOYMENT + PRODUCTION READ-ONLY REVIEW

**Sana:** 2026-11-26
**Muhitlar:**
- staging `zwzxyikocqxbeyejeyga` — yozildi;
- production `buuwjhpzptiiyggybvwr` — faqat `SET TRANSACTION READ ONLY` bilan o'qildi.

**Yakuniy holat:** **PHASE 3 STEP 7 — 007b STAGING DEPLOYMENT + PRODUCTION READ-ONLY REVIEW PASSED — READY FOR EXPLICIT PRODUCTION DEPLOYMENT APPROVAL**

## Artefaktlar

| Fayl | SHA-256 |
|---|---|
| `migration-007b.sql` (= `production/83_apply_007b.sql`) | `36b2994eefa758a7db169ed3dab3d50ac9009c7b53043a0ab7ba7acada5f8553` |
| `rollback-007b.sql` (= `production/89_rollback_007b.sql`) | `1c4fbfc663c7a6017589468beabe5a466946b22c237047a3a644d8f1542f31f5` |

Ikkala fayl ham editor ichida qayta hisoblanib tekshirildi va mos keldi.

## Test vositasidagi tuzatishlar (migratsiya SQL o'zgarmagan)

- **007b testlariga B05 qo'shildi:** ta'tildagi (`on_leave`) xodim qamrab olinishi tekshiriladi. Jami 78 ta test.
- **Ikki sanoq invarianti migratsiya holatiga moslashtirildi.** Ikkalasi 007b'siz va 007b bilan PASS:

  | Test | Avval | Endi |
  |---|---|---|
  | 007a I05 | 44 | `44 + (007b qo'llangan bo'lsa 1)` |
  | 006a J02 | 006a'dan oldingi + 1 | 006a'dan oldingi + 1 + (007b qo'llangan bo'lsa 1) |

  Fayllar: `staging/007a_02`, `006a_02`, `production/65`, `production/75`.

## STAGING

**Precheck va baseline (007b'dan oldin):**

| Ko'rsatkich | Qiymat |
|---|---|
| 007a / 007b | 1 / 0 |
| jadvallar / funksiyalar / triggerlar / policy / indekslar | 44 / 94 / 91 / 98 / 104 |
| CASCADE | 0 |
| anon EXECUTE | faqat `verify_certificate` |
| fn_md5 | `c89ecd14…` — production'ning 007a'dan keyingi qiymati bilan bir xil |

Hash'lar:

| Hash | Qiymat |
|---|---|
| trg | `2043c7e8…` |
| cols | `96d9924e…` |
| idx | `c62b9ffc…` |
| policy | `f27165f6…` |
| grant | `284356db…` |

**Backup:** `backup.*_pre007b` — 44/44 jadval aynan (1 546 qator); katalog snapshot va fingerprint saqlandi.

**Apply:** `{"migration":"007b","table":true,"rls":true,"rules":0,"anon_exec":"verify_certificate","course_assignments":0,"attempts":1,"certificates":0}`

**Verify (`84_verify_007b.sql`): `ok: true`.** Tekshirilganlar:

- jadval bor, RLS yoqilgan, 18 ustun;
- yozish grant'lari 0;
- RPC'lar: authenticated ✓, anon ✗; ichki funksiyalar yopiq;
- anon EXECUTE faqat `verify_certificate`; CASCADE 0; 45 jadval;
- ma'lumotlar backup bilan aynan: courses, questions, exam_configs, attempts, certificates, employees, learning_paths, learning_path_courses, course_assignments, lesson_progress, profiles soni;
- katalog farqi faqat kutilgan: +6 funksiya, trigger 1, indeks 4, ustun 18, policy 1, o'zgargan funksiya 0.

**Testlar (staging, ROLLBACK bilan):**

| To'plam | Natija |
|---|---|
| 007b | **78/78** |
| 007a | 55/55 |
| 006b | 34/34 |
| 006a | 83/83 |
| 005e | 146/146 |
| 005d_04 (evidence) | 54/54 |
| Role matrix (evidence) | 62/62 |

Hammasida fail_ids `[]`, SKIPPED 0. Residue 0: testlardan keyingi verify birinchisi bilan bir xil.

**Unumdorlik (staging, 1000 xodim, 4 bo'lim, 50 yo'nalish × 5 kurs; ROLLBACK, residue 0):**

| Operatsiya | median | p95 | max |
|---|---|---|---|
| Birinchi apply (har biri 1 250 tayinlash) | 862 ms | 932 ms | 1 016 ms |
| Idempotent reapply | 25.7 ms | 44.3 ms | 48 ms |

- Jami 62 500 tayinlash yaratildi; takror 0.
- Birinchi apply vaqtiga har qatorda ishlaydigan mavjud `audit_row`, guard va same_org trigger'lari kiradi.
- Test bitta tranzaksiyada, statistika yangilanmagan holatda o'tkazildi (eng yomon holat).
- Har bir apply = bitta set-based INSERT (N+1 yo'q).

**Rollback / reapply:**

1. **Rollback:** `{"migration_007b":0,"table":false,"functions":0}`.
2. **Katalogni backup bilan solishtirish:** hammasi 0 / `-`.
3. **Fingerprint:** 007b'dan oldingi holat bilan **aynan bir xil** (diff: none).
4. **Reapply ×2:** verify birinchi apply bilan bir xil. Ikkinchi reapply'da runner natija o'zgarishini kutib TIMEOUT bergan; bu vosita xususiyati, apply bajarilgan va verify buni tasdiqlaydi.
5. **Reapply'dan keyingi testlar:** 78/78, residue 0.

**Yakuniy staging holati:** 007b qo'llangan, verify `ok: true`.

## PRODUCTION (READ ONLY)

**Tekshiruv:** `80_readonly_review_007b.sql`, `transaction_read_only = on`.

| Ko'rsatkich | Qiymat |
|---|---|
| Migratsiyalar | 001…006b, 007a; 007b = 0; `learning_path_assignments` yo'q |
| jadvallar / funksiyalar / triggerlar / policy / indekslar | 44 / 94 / 91 / 98 / 104 |
| CASCADE | 0 |
| anon | faqat `verify_certificate` |
| Ma'lumotlar | courses 13, questions 131, exam_configs 13, attempts 2, certificates 0, profiles 1, employees 1, audit_logs 307 |

**Drift:** production'ning fn / trg / cols / idx / policy / grant hash'lari staging'ning 007b'dan oldingi holati bilan **aynan bir xil** → drift yo'q.

**Anon REST:**

| So'rov | HTTP | Izoh |
|---|---|---|
| `apply` / `reapply` / `cancel` RPC | 404 | hali mavjud emas — kutilgan |
| `learning_path_assignments` | 404 | jadval hali yo'q |
| `my_learning_progress` | 401 | himoya joyida |
| `verify_certificate` | 200 | ommaviy tekshiruv ishlaydi |

Deploy'dan keyin RPC'lar 401 bo'lishi kerak; bu STEP 8 smoke-testida tekshiriladi.

| | |
|---|---|
| Production writes | 0 |
| Production migrations | 0 |
| Production data changed | NO |
| Production schema changed | NO |

## STEP 8 deploy paketi (bajarilmagan)

| Qadam | Fayl | Vazifa |
|---|---|---|
| 1 | `81_backup_pre007b` | Backup |
| 2 | `82_precheck_007b` | Precheck, faqat SELECT. `ok` sharti: 007a = 1, 007b = 0, jadval yo'q, 13 / 131 / 13 / 2 / 0, CASCADE 0, anon, 44 jadval, backup 44 + fingerprint, hash'lar yuqoridagi production qiymatlariga teng |
| 3 | `83_apply_007b` | 007b'ni qo'llash |
| 4 | `84_verify_007b` | Tekshiruv |
| 5 | `85_security_tests_007b` (78) + `75` (007a) + `65` (006a) + `66` / `54` / `55` / `56` / `44` | Testlar, hammasi ROLLBACK bilan |
| 6 | `84` qayta | Residue 0 tekshiruvi |
| 7 | — | Anon smoke |

**Incident bo'lsa:** `89_rollback_007b` + `007b_04_compare_pre`.

**Lokal production simulyatsiyasi** (`tests/prod007b_sim.mjs`):

| Qadam | Natija |
|---|---|
| 84 verify | `ok: true` |
| 85 testlar | 78/78 |
| 75 testlar | 55/55 |
| 65 testlar | 83/83 |
| Residue | 0 |
| Rollback compare | 0 |
| Reapply | birinchi bilan bir xil |

## Git

Faqat admin branch:

- `backend/migration-007b/` — staging/, production/, tests/;
- invariant tuzatilgan test fayllari;
- shu hisobot.

`main` / Pages / employee build o'zgarmagan.

---

# PHASE 3 STEP 8 — 007b PRODUCTION DEPLOYMENT (shu hujjatga qo'shimcha)

## Tasdiq va target

| | |
|---|---|
| Tasdiq | Foydalanuvchi **"DEPLOY TO PRODUCTION"** tanladi, 2026-11-26 ~15:58 UTC (20:58 Toshkent) |
| Target | production `buuwjhpzptiiyggybvwr` |

## Bajarilgan qadamlar

| Qadam | Natija |
|---|---|
| Pre-flight (READ ONLY) | 007b = 0; 13 / 131 / 13 / 2 / 0; profiles 1; audit_logs 307 |
| `81` backup | `backup.*_pre007b` — 44/44 jadval aynan (1 139 qator); policy 98, funksiya 94, trigger 91, RLS 44/44, fingerprint saqlandi |
| `82` precheck | **ok: true** |
| `83` apply | 15:59:26.9 → 15:59:36.6 UTC. Natija: `{"migration":"007b","table":true,"rls":true,"rules":0,"anon_exec":"verify_certificate","course_assignments":0,"attempts":2,"certificates":0}`. SHA `36b2994e…` editor ichida mos keldi |
| `84` verify | **ok: true** (tafsilotlar quyida) |

**Verify tafsilotlari:**

- jadval bor, RLS yoqilgan, 18 ustun, qoidalar 0;
- yozish grant'lari 0;
- RPC'lar: authenticated ✓, anon ✗; ichki funksiyalar yopiq;
- anon EXECUTE faqat `verify_certificate`; CASCADE 0; 45 jadval;
- 11 ta ma'lumot tekshiruvi backup bilan aynan;
- katalog farqi faqat kutilgan: +6 funksiya, trigger 1, indeks 4, ustun 18, policy 1, o'zgargan funksiya 0.

## Production testlari

Barcha testlar vaqtinchalik test identifikatorlari bilan ishladi va ROLLBACK qilindi.

| To'plam | Natija |
|---|---|
| 007b (`85`) | 78/78 |
| 007a (`75`) | 55/55 |
| 006b (`66`) | 34/34 |
| 006a (`65`) | 83/83 |
| 005e (`54`) | 146/146 |
| Role matrix (`55`) | 62/62 |
| 005 regressiya (`56`) | 26/26 |
| 005d (`44`) | 54/54 |

- Hammasida fail_ids `[]`.
- **Residue 0:** ikkinchi verify birinchisi bilan baytma-bayt bir xil.

## Smoke (anon REST)

| So'rov | HTTP |
|---|---|
| `apply_learning_path` | 401 |
| `reapply_learning_path_assignment` | 401 |
| `cancel_learning_path_assignment` | 401 |
| `learning_path_assignments` SELECT | 401 |
| `learning_path_assignments` INSERT | 401 |
| `verify_certificate` | 200 |

## Yakuniy production holati (READ ONLY)

| | |
|---|---|
| Migratsiyalar | 001…007a, **007b** |
| jadvallar / funksiyalar / triggerlar / policy / indekslar | 45 / 100 / 92 / 99 / 104→108 |
| CASCADE | 0 |
| anon | faqat `verify_certificate` |
| Ma'lumotlar | courses 13, questions 131, exam_configs 13, attempts 2, certificates 0, profiles 1, employees 1, audit_logs 307, course_assignments 0 — o'zgarmagan |

## Rollback

Bajarilmadi, zarurat yo'q.

**PHASE 3 STEP 8 — 007b PRODUCTION DEPLOYMENT COMPLETE — 007b = 1, ALL GATES PASS**
