# MedAcademy — PHASE 3 STEP 4 — Migration 007a Production Review

**Sana:** 2026-11-25
**Production:** faqat READ ONLY tranzaksiyada o'qildi. 007a production'ga **qo'llanmagan**.

## A. Artefaktlar yaxlitligi

| Fayl | SHA-256 |
|---|---|
| `migration-007a.sql` | `d8bacfc0f7c39ec4e0c332366a4ce81bab45c3e97841b81d0e0d8813a28b151a` — STEP 2 / STEP 3 bilan bir xil (o'zgarmagan) |
| `rollback-007a.sql` | `fb9a540b97733def43f375420f18a33c22286e3b464ba4ca3625fd37c0d54ccf` — o'zgarmagan |
| `production/73_apply_007a.sql` | migration bilan baytma-bayt bir xil (`cmp` = IDENTICAL) |
| `production/79_rollback_007a.sql` | rollback bilan baytma-bayt bir xil |

Har bir Supabase ijrosida fayl matnining SHA-256'i editor ichida qayta hisoblandi va mos keldi.

## B. Staging (yakuniy qayta tekshiruv, 2026-11-25)

| To'plam | Natija |
|---|---|
| 007a | **55/55**, FAIL 0 (har bir ID: R01–R15, S01–S09, P, Z, I — hammasi PASS) |
| 005d_04 | **54/54**, FAIL 0 |
| 005d_06 role matrix | **62/62**, FAIL 0 |
| 006b | 34/34 |
| 006a | 83/83 |
| 005e security | 146/146 |
| Rollback | katalog backup snapshot bilan obyekt-darajasida aynan; ma'lumotlar aynan |
| Reapply ×2 | birinchi qo'llash bilan bir xil (idempotent) |
| Residue | 0 (fingerprint testlardan oldin = keyin) |
| Production verify skripti (`74`) staging'da | `ok: true` |

**Unumdorlik** (staging, 1000×50; STEP 2 lokal / STEP 3 staging):

| O'lchov | Natija |
|---|---|
| `my_learning_progress` | median 2.1 / p95 6.3 ms (lokal 3.9) |
| SA summary | 59.9 / 61.8 ms (lokal 37.5) |
| Head summary | 23.2 / 23.5 ms (lokal 14.6) |
| Trigger | median 5.4 ms (lokal 9.8) |

Moddiy regressiya yo'q.

## C. Anomaliyalar tekshiruvi

### 005d_04 — "54/0 FAIL"

| | |
|---|---|
| Asl natija | Test faylining o'z SUMMARY qatori: `SUMMARY total 54 / FAIL 0`. STEP 3 hisobotida jadvalga "54 / FAIL 0" deb yozilgan, ChatGPT xulosasida "54/0" ko'rinishiga qisqargan. |
| Asosiy sabab | **Hisobot formati** (maxraj emas). "0" — FAIL soni, o'tgan testlar soni emas. Bu fayl 006a/006b/007a fayllaridagi `total / pass / fail` JSON formatidan oldin yozilgan va faqat `total` va `FAIL` sonini chiqaradi. Supabase natija jadvali virtual (faqat ko'rinib turgan ~8 qatorni DOM'da ushlaydi), shuning uchun STEP 3'da har bir qator dalil sifatida olinmagan. |
| Tuzatish | `005d_04_tests_evidence.sql`. Test mantig'i **o'zgarmagan**: faqat oxiriga to'liq natijani bitta JSON qatorga yig'uvchi SELECT qo'shilgan (`total` / `pass` / `fail` / `fail_ids` / `pass_ids` / `groups` / `expected_ne_actual_but_pass`). |
| Qayta ijro | **Lokal:** 54/54. **Staging:** 54/54, fail_ids `[]`. |
| Guruhlar | Grants 21/21, Lifecycle 10/10, Employee 4/4, RESTRICT 3/3, Certificate 3/3, Cross-org 2/2, Leakage 2/2, FK 2/2, Public / Audit / History / Historical / Fixture / Attempt / Admin 1/1. |
| `expected_ne_actual_but_pass` | Faqat predikatli kutilmalar (masalan "> 0" → 12; "DENIED (permission)" → DENIED). Majburan PASS qilingan test yo'q. |
| Yakuniy natija | **GENUINE PASS (54/54)**, xavfsizlik regressiyasi yo'q. |

### Role matrix — "62/0 FAIL"

| | |
|---|---|
| Asl natija | `SUMMARY total 62 / FAIL 0`. |
| Asosiy sabab | 005d_04 bilan aynan bir xil (hisobot formati). |
| Tuzatish | `005d_06_role_matrix_evidence.sql`, test mantig'i o'zgarmagan. |
| Qayta ijro | **Lokal:** 62/62. **Staging:** 62/62, fail_ids `[]`. |
| Guruhlar | Org isolation 16/16, Clinical workflow 15/15, Non-clinical 5/5, Question security 5/5, Employee 4/4, HR 3/3, Instructor 3/3, Department Head 2/2, Medical Reviewer 2/2, Education Manager 2/2, Historical 2/2, Policy finding 2/2, Super Admin 1/1. |
| "Policy finding" M01 / R09 | 005c davridagi topilmalar. Endi haqiqiy natija `DENIED` — 005e tuzatgan holat tasdiqlandi. |

**007a ruxsatlari** (007a evidence, staging):

| Rol | `course_progress_summary` |
|---|---|
| SA | organization (R01, R02) |
| EM | organization (R03) |
| HR | organization (R04) |
| Head | department, faqat o'z bo'limi (R05) |
| Instructor (o'z kursi emas) | DENIED (R06) |
| Instructor (o'z kursi) | course_instructor (R07) |
| MR | DENIED (R08) |
| Employee | DENIED (R09) |
| anon | DENIED (R10) |
| Org B → Org A | DENIED (R11) |
| Org B o'zi | organization (R12) |
| Head → Org B | DENIED (R13) |
| Cancelled alohida | (R14) |
| Mavjud bo'lmagan kurs | DENIED (R15) |

`my_learning_progress`:
- faqat o'z xodimi (S01–S03);
- anon DENIED (S04);
- 12 maydon (S05);
- RLS bo'yicha boshqa xodimlar 0 (S06, S07);
- boshqa xodim nomidan yozish DENIED (S08);
- nofaol xodim — bo'sh ro'yxat (S09).

**Yakuniy natija:** role matrix **GENUINE PASS (62/62)**, 007a rollari **PASS (24/24)**.

## D. Production (READ ONLY)

**Tekshiruv sharoiti:**
- Target: `buuwjhpzptiiyggybvwr` (URL + skriptdagi ref tekshiruvi).
- Fayl: `production/70_readonly_review_007a.sql`, SHA `bbe2c64c…`.
- `begin; set transaction read only; … rollback;`, `transaction_read_only = on`.
- Runner faqat shu shablondagi fayllarni ishga tushiradi va "destructive" tasdiq oynasini hech qachon tasdiqlamaydi.

| | Qiymat |
|---|---|
| 005e / 006a / 006b | 1 / 1 / 1 |
| 007a | 0; `lessons.is_required` yo'q |
| courses / questions / exam_configs | 13 / 131 / 13 |
| attempts / certificates | 2 / 0 |
| profiles / employees | 1 / 1 |
| audit_logs | 307 (o'zgarmagan) |
| course_modules / lessons / lesson_progress / course_assignments / learning_paths | 34 / 47 / 0 / 0 / 9 |
| Jadvallar / funksiyalar / triggerlar / policy / indekslar | 44 / 89 / 90 / 98 / 102 |
| CASCADE | 0 |
| anon EXECUTE | faqat `verify_certificate` |

**Drift tahlili.** Production sxema hash'lari staging'ning 007a'dan oldingi (rollback'dan keyingi, v2) holati bilan **aynan bir xil**:

| Hash | Qiymat |
|---|---|
| fn | `172209c6…` |
| trg | `65977d7e…` |
| cols | `4e92bd08…` |
| idx | `9e0c0009…` |
| policy | `f27165f6…` (006 deploy'dan keyingi qayd bilan bir xil) |
| grants | `284356db…` |
| fcat | `e151b4c5…` |

Demak 007a sinalgan muhit bilan production sxemasi o'rtasida farq yo'q. Ma'lumot farqlari (kurslar soni, test akkauntlari) faqat staging'dagi test ma'lumotlari.

## E. Production yozuvlari

| | |
|---|---|
| Production writes | **0** |
| Production migrations | **0** |
| Production data changed | **NO** |
| Production schema changed | **NO** |

## F. STEP 5 deploy paketi (tayyor, bajarilmagan)

**Ketma-ketlik** (`backend/migration-007a/production/`):

1. `71_backup_pre007a.sql` — `backup.*_pre007a`: 44 jadval to'liq nusxa; ustun / constraint / indeks / policy / funksiya (ta'rif + EXECUTE) / trigger / default ACL / RLS / fingerprint snapshot. O'z-o'zini tekshiradi: `tables_identical = 44`.
2. `72_precheck_007a.sql` — faqat SELECT. `ok` sharti:
   - 006b = 1, 007a = 0, ustun yo'q;
   - 13 / 131 / 13 / 2 / 0;
   - CASCADE 0, anon = `verify_certificate`, 44 jadval, backup 44 jadval + fingerprint;
   - fn / trg / cols / idx / policy / grant hash'lari yuqoridagi production qiymatlariga teng.
   - `ok ≠ true` → TO'XTASH.
3. Freeze baseline — 72 natijasi va `backup.fingerprint_pre007a`.
4. `73_apply_007a.sql` — 007a (SHA `d8bacfc0…`).
5–11. `74_verify_007a.sql` — faqat SELECT. `ok` sharti:
   - 007a = 1; ustun `NO/true`; ixtiyoriy darslar 0;
   - trigger 1, indeks 2;
   - RPC authenticated ✓ / anon ✗; ichki funksiyalar authenticated'ga yopiq;
   - anon = `verify_certificate`; CASCADE 0; 44 jadval;
   - qator sonlari backup bilan teng;
   - questions / courses / exam_configs / attempts / certificates / modules / lessons / assignments / progress ma'lumoti backup bilan aynan;
   - katalog farqi faqat kutilgan: +5 funksiya, trigger 1, indeks 2, ustun 1, policy 0.
   - Staging'da `ok: true`.
12. `75_security_tests_007a.sql` — 55 test. Vaqtinchalik test identifikatorlari (`@test.local`, parolsiz) faqat tranzaksiya ichida yaratiladi, oxirida ROLLBACK. 65/66 usuli.
13. Smoke — anon REST: yangi RPC'lar 401; `verify_certificate` 200. Employee ilovasi va Admin Panel ochiladi.
14. `74_verify_007a.sql` qayta — residue 0 (birinchi verify bilan bir xil).
15. Yakuniy hisobot.

**Rollback** (faqat incident, alohida qaror bilan):
- `79_rollback_007a.sql`, keyin `staging/007a_04_compare_pre.sql` (hammasi 0 / `-` bo'lishi kerak).

**Lokal production simulyatsiyasi** (`tests/prod007a_sim.mjs`, production-like zanjir, test akkauntlarisiz):
- `70 → 71 → 72 → 73 → 74` (`ok: true`) `→ 75` (55/55) `→ 74` (residue 0) `→ 79` (compare: hammasi 0) `→ 73 → 74` (birinchi bilan bir xil).

## G. Git

- Faqat admin branch:
  - `backend/migration-007a/production/` (7 fayl);
  - `staging/` evidence + `compare_pre` tuzatishi (`string_agg` tartibi);
  - `tests/prod007a_sim.mjs`;
  - shu hisobot.
- Migratsiya SQL o'zgarmagan.
- Sir, parol, token yoki dump yo'q.
- `main` / Pages / employee build o'zgarmagan.

## Yakuniy gate

**PHASE 3 STEP 4 — 007a PRODUCTION REVIEW PASSED — READY FOR EXPLICIT DEPLOYMENT APPROVAL**

Production deploy hali bajarilmagan. Foydalanuvchining aniq "DEPLOY TO PRODUCTION" tasdig'i talab qilinadi.
