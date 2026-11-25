# MedAcademy — PHASE 3 STEP 3 — Migration 007a STAGING hisoboti

**Sana:** 2026-11-25, 18:26–18:45 UTC

## A. Muhit

| Parametr | Qiymat |
|---|---|
| Target | STAGING — Supabase loyihasi `medacademy-staging`, ref `zwzxyikocqxbeyejeyga` |
| Ijro | SQL Editor URL'i va har bir ijrodan oldingi avtomatik tekshiruv `zwzxyikocqxbeyejeyga` ni tasdiqladi |
| Production ref | `buuwjhpzptiiyggybvwr` — umuman ochilmadi va so'rov yuborilmadi |
| Production touched | **NO** |

## B. Migratsiya

| Parametr | Qiymat |
|---|---|
| 007a applied | **YES** (yakuniy holat: to'liq qo'llangan) |
| Migration SHA-256 | `d8bacfc0f7c39ec4e0c332366a4ce81bab45c3e97841b81d0e0d8813a28b151a` (editor matnida qayta hisoblandi — mos) |
| Rollback SHA-256 | `fb9a540b97733def43f375420f18a33c22286e3b464ba4ca3625fd37c0d54ccf` (mos) |

**Migratsiya natijasi:**

```
{"migration":"007a","is_required_column":1,"lessons_required":48,"trigger":1,"anon_exec":"verify_certificate","attempts":1,"certificates":0}
```

Migratsiya fayli deploy paytida o'zgartirilmadi.

## C. Backup

- Fayl: `staging/007a_00_backup.sql`, SHA `9a796dfe…`. Snapshot: `backup.*_pre007a`.
- Natija:
  - jadvallar 44/44 aynan nusxalandi (mismatched `-`), jami 1 545 qator;
  - policy 98, funksiya 89, trigger 90, constraint 290, FK 120;
  - RLS 44/44; anon EXECUTE 1 ta; fingerprint saqlandi.
- Tiklashga tayyorlik:
  - `007a_rollback.sql` + `backup.*_pre007a` jadvallari;
  - `007a_04_compare_pre.sql` katalogni backup bilan solishtiradi.

## D. Baseline (007a dan oldin) va drift

| | Qiymat |
|---|---|
| Migratsiyalar | 001…006b (005e / 006a / 006b mavjud) |
| Jadvallar | 44 |
| Funksiyalar | 89 |
| Triggerlar | 90 |
| Policy'lar | 98 |
| Indekslar | 102 |
| CASCADE FK | 0 |
| anon EXECUTE | faqat `verify_certificate` |
| policy_md5 | `f27165f6…` (production'ning 006 dan keyingi qiymati bilan bir xil) |

**Ma'lumotlar:**

| Jadval | Soni |
|---|---|
| courses | 14 |
| questions | 132 |
| exam_configs | 14 |
| exam_attempts | 1 |
| certificates | 0 |
| profiles | 11 |
| employees | 11 |
| audit_logs | 464 |
| course_modules | 35 |
| lessons | 48 |
| lesson_progress | 0 |
| course_assignments | 0 |
| learning_paths | 10 |

**Drift:** staging production'dan test identifikatorlari (profiles / employees) va bitta test kursi bilan farq qiladi. Bu kutilgan holat va 007a'ga ta'sir qilmaydi.

**Sxema:** `lessons` / `course_modules` / `lesson_progress` / `course_assignments` lokal sinovdagi tuzilma bilan mos keldi. Migratsiya va 55 ta test o'zgarishsiz ishladi.

## E. Natijalar (faqat haqiqatda bajarilgan)

| Tekshiruv | Natija |
|---|---|
| 007a SQL testlari (qo'llashdan keyin) | **55/55 PASS** |
| 007a SQL testlari (rollback → reapply ×2 dan keyin) | **55/55 PASS** |
| 006b regressiya | 34/34 |
| 006a regressiya | 83/83 |
| 005e security | 146/146 |
| 005d_04 | 54 / FAIL 0 |
| 005d_06 role matrix | 62 / FAIL 0 |
| Rollar (SA, HR, EM, Instructor, Head, MR, Employee, anon) | PASS (R01–R15, S01–S09) |
| Cross-org (Org B xodimi / admin, Org A Head → Org B kursi) | PASS |
| Chegaraviy holatlar A–L (0 majburiy, qisman, to'liq, ixtiyoriy, cancelled, kecha / bugun / kelajak, qatorsiz, takror qator rad, arxiv, nofaol xodim) | PASS |
| `course.completed` audit: aniq 1 ta; o'qish audit yozmaydi; takroriy belgilash takroriy audit bermaydi | PASS (P10–P12) |
| Sertifikat / urinishlar o'zgarmagan | PASS (P13, I04) |
| Ma'lumot oqishi: `my_learning_progress` faqat 12 hujjatlashtirilgan maydon | PASS (S05) |
| Test residue (fingerprint testlardan oldin = keyin) | 0 |

### Unumdorlik (staging, haqiqiy Supabase Postgres)

**Yuklama:** 1000 xodim × 50 kurs; 50 000 tayinlash, 249 791 progress qatori. Hammasi bitta tranzaksiyada yaratilib, oxirida ROLLBACK qilindi (residue 0).

| O'lchov | median | p95 | max | Lokal ma'lumot |
|---|---|---|---|---|
| `my_learning_progress()` — 50 kurs | 2.09 ms | 6.32 ms | 53.0 ms (birinchi chaqiruv) | 3.9 ms |
| `course_progress_summary` — SA, 1000 xodim | 59.9 ms | 61.8 ms | 79.2 ms | 37.5 ms |
| `course_progress_summary` — Head, 250 xodim | 23.2 ms | 23.5 ms | 27.1 ms | 14.6 ms |
| Tugallash trigger'i | 5.4 ms | — | 103 ms (2 ta insert, birinchisi sovuq kesh) | 9.8 ms |

- Tugallash trigger'i natijasi: `completed`, `course.completed` audit = 1.
- Moddiy regressiya yo'q. SA summary 1000 xodim uchun ~60 ms — maqbul.
- Har bir chaqiruv bitta SQL so'rov bilan bajariladi (N+1 yo'q).

### Rollback / Reapply / Idempotentlik

- Rollback natijasi: `{"migration_007a":0,"is_required_column":0,"trigger":0}`.
- Katalogni backup snapshot bilan solishtirish (`007a_04_compare_pre.sql`) — barchasi 0: `functions_extra -`, `functions_missing -`, `functions_def_changed 0`, `triggers_diff 0`, `indexes_diff 0`, `columns_diff 0`, `policies_diff 0`.
- Rollback'dan keyingi ma'lumotlar (counts + data_md5) 007a dan oldingi holatga **aynan teng**.
- Reapply #1 va reapply #2 (idempotentlik) fingerprint'i birinchi qo'llash bilan **aynan bir xil** (diff: none).
- Takroriy obyekt, indeks yoki audit yo'q.

> **Topilgan va tuzatilgan muammo (test vositasida, migratsiyada emas):**
> - Fingerprint v1 `string_agg(... order by 1)` ishlatgan. Bu doimiy qiymat bo'yicha tartiblaydi, shuning uchun obyektlar qayta yaratilganda `fn_md5` / `trg_md5` tasodifiy o'zgargan.
> - v2'da tartib aniq ifoda bo'yicha qilindi.
> - Rollback tekshiruvi qo'shimcha ravishda backup katalogiga nisbatan obyekt-darajasida qilindi.
> - Ma'lumot maydonlari v1'da ham teng bo'lgan.

## F. Ma'lumotlar yaxlitligi

- Yakuniy staging holati (007a qo'llangan): barcha qator sonlari va `data_md5` qiymatlari 007a dan oldingi holat bilan **bir xil**.
- Bu jadvallar uchun to'g'ri: courses, questions, exam_configs, exam_attempts, certificates, profiles, course_modules, lessons (asosiy ustunlar), lesson_progress, course_assignments, audit_logs.
- Barcha test va perf ma'lumotlari ROLLBACK qilindi.
- O'zgargan qatorlar: **yo'q** (faqat sxema: +1 ustun, +5 funksiya, +1 trigger, +2 indeks).
- Yakuniy sxema: jadvallar 44, funksiyalar 94, triggerlar 91, policy'lar 98 (`f27165f6`, o'zgarmagan), indekslar 104, CASCADE 0, anon EXECUTE faqat `verify_certificate`.
- Qo'shimcha: `backup` sxemasida `*_pre007a` snapshot jadvallari (RLS yoqilgan, anon / authenticated'ga yopiq).

## G. Production

| Parametr | Qiymat |
|---|---|
| Production writes | 0 |
| Production migrations | 0 |
| Production data changed | NO |

Production'ga bu bosqichda hech qanday so'rov (hatto read-only) yuborilmadi. Oxirgi tasdiqlangan baseline: 005e / 006a / 006b = 1; courses 13; questions 131; exam_configs 13; attempts 2; certificates 0; profiles 1; audit_logs 307.

## H. Git

- Faqat admin branch `phase2-step3-005d-admin-local`:
  - `backend/migration-007a/staging/` (4 SQL);
  - `README.md` yangilandi (holat; indeks tavsifi aniqlashtirildi: bittasi qisman, bittasi oddiy);
  - shu hisobot.
- `main` / GitHub Pages / employee build — o'zgarmagan.
- Commit'larda sir, token, parol yoki dump yo'q.

## Yakuniy qaror

**PHASE 3 STEP 3 — 007a STAGING DEPLOYMENT COMPLETE — READY FOR PRODUCTION REVIEW**
