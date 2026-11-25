# MedAcademy — PHASE 3 STEP 5 — Migration 007a PRODUCTION DEPLOYMENT hisoboti

## Tasdiq

| | |
|---|---|
| Foydalanuvchi tanlovi | **"DEPLOY TO PRODUCTION"** (AskUserQuestion) |
| Vaqt | 2026-11-25 ~18:58 UTC (23:58 Toshkent) |

## Target

| | |
|---|---|
| Production | `buuwjhpzptiiyggybvwr` (Supabase loyihasi `medacademy`) |
| Tekshiruv | Har bir ijrodan oldin runner URL'dagi ref va sahifa sarlavhasini tekshirdi |
| Staging | Bu bosqichda ishlatilmadi |

## Artefaktlar

| | |
|---|---|
| Migration (`73_apply_007a.sql` = `migration-007a.sql`) | SHA-256 `d8bacfc0f7c39ec4e0c332366a4ce81bab45c3e97841b81d0e0d8813a28b151a` |
| Rollback (`79_rollback_007a.sql`) | SHA-256 `fb9a540b97733def43f375420f18a33c22286e3b464ba4ca3625fd37c0d54ccf` (ishlatilmadi) |
| Tekshiruv | Har bir fayl matnining SHA-256'i Supabase editori ichida qayta hisoblandi va mos keldi |

## 1. Pre-flight (READ ONLY) — 18:58:41 UTC

**Fayl:** `70_readonly_review_007a.sql`, ijro rejimi `transaction_read_only = on`.

| Ko'rsatkich | Qiymat |
|---|---|
| 007a | 0 |
| courses / questions / exam_configs | 13 / 131 / 13 |
| attempts / certificates | 2 / 0 |
| profiles / employees | 1 / 1 |
| audit_logs | 307 |
| modules / lessons | 34 / 47 |
| progress / assignments | 0 / 0 |
| learning_paths | 9 |

STEP 4 baseline bilan bir xil.

## 2. Backup — `71_backup_pre007a.sql`

- Natija: `tables_backed_up 44`, `tables_identical 44`, `mismatched -`.
- Hajm: jami 1 138 qator.
- Snapshot: policy 98, funksiya 89, trigger 90, constraint 290, FK 120, RLS 44/44, anon EXECUTE 1, `fingerprint_saved 1`.
- Joylashuv: `backup.*_pre007a` (RLS yoqilgan).

## 3. Precheck — `72_precheck_007a.sql`

**`ok: true`.** Tekshirilgan shartlar:

- 006b = 1, 007a = 0, ustun yo'q;
- 13 / 131 / 13 / 2 / 0;
- CASCADE 0; anon = `verify_certificate`;
- 44 jadval; backup 44 jadval + fingerprint;
- fn / trg / cols / idx / policy / grant hash'lari STEP 4 qiymatlariga teng.

Eslatma: profiles = 1, audit_logs = 307.

## 4. Apply — `73_apply_007a.sql`

| | |
|---|---|
| Boshlanish | 18:59:05.8 UTC |
| Tugash | 18:59:15.5 UTC |
| Natija | `{"migration":"007a","is_required_column":1,"lessons_required":47,"trigger":1,"anon_exec":"verify_certificate","attempts":2,"certificates":0}` |

## 5. Verify — `74_verify_007a.sql`

**`ok: true`.**

| Tekshiruv | Natija |
|---|---|
| `lessons.is_required` | `NO/true`; ixtiyoriy darslar 0 (barcha 47 dars majburiy) |
| Trigger | `lesson_progress_completion_007a_trg` = 1 |
| Indekslar | 2 (`lesson_progress_completed_007a_idx` qisman; `course_assignments_course_007a_idx`) |
| RPC grantlari | `my_learning_progress` / `course_progress_summary`: authenticated ✓, anon ✗ |
| Ichki funksiyalar | authenticated EXECUTE 0 |
| anon EXECUTE | faqat `verify_certificate` |
| CASCADE | 0 |
| Jadvallar | 44 (yangi jadval yo'q) |
| Ma'lumotlar (backup bilan aynan) | questions, courses, exam_configs, exam_attempts, certificates, course_modules, lessons, course_assignments, lesson_progress — barchasi `true` |
| Katalog farqi (backup'ga nisbatan) | Faqat kutilgan: +5 funksiya, trigger 1, indeks 2, ustun 1, policy 0; o'zgargan yoki yo'qolgan funksiya 0 |
| `course.completed` audit | 0 (haqiqiy xodim progressi yo'q, kutilgan) |

## 6. Testlar (production, hammasi bitta tranzaksiyada → ROLLBACK)

Vaqtinchalik test identifikatorlari (`@test.local`, parolsiz, tizimga kira olmaydi) faqat tranzaksiya ichida yaratildi va ROLLBACK bilan yo'qoldi.

| To'plam | Natija |
|---|---|
| **007a** (`75_security_tests_007a.sql`) — progress, chegaraviy holatlar (0 majburiy, qisman, to'liq, ixtiyoriy, cancelled, overdue kecha / bugun / kelajak, qatorsiz, takror qator rad, arxiv, nofaol), `course.completed` (aniq 1; o'qishda 0; takrorda 0), sertifikat / urinish o'zgarmagan, rollar va cross-org, 12 maydon | **55/55**, fail_ids `[]` |
| 005d xavfsizlik (`44_…_evidence`) | **54/54** |
| 005e xavfsizlik (`54`) | **146/146** |
| Role matrix (`55_…_evidence`) | **62/62** |
| 005 regressiya (`56_…_evidence`) — exam engine, sertifikat tekshiruvi, tarixiy urinishlar | **26/26** |
| 006a (`65`) — audit immutability, reset, delete guard'lar | **83/83** |
| 006b (`66`) — kurs arxivi va delete himoyasi | **34/34** |

**Residue:** testlardan keyingi `74_verify` natijasi birinchi verify bilan **baytma-bayt bir xil**, ya'ni 0.

## 7. Ma'lumotlar yaxlitligi

| | |
|---|---|
| O'zgarmagan (backup bilan md5 aynan) | courses, questions, exam_configs, exam_attempts, certificates, course_modules, lessons (asosiy ustunlar), course_assignments, lesson_progress |
| Qator soni o'zgarmagan | profiles 1, audit_logs 307 |
| Kutilgan o'zgarishlar | faqat sxema: `lessons.is_required` (default true), 5 funksiya, 1 trigger, 2 indeks, `schema_migrations` '007a' qatori |
| Qo'shimcha | `backup.*_pre007a` snapshot jadvallari |

Tarixiy ma'lumot qayta yozilmadi; DELETE, CASCADE, sertifikat berish yo'q.

## 8. Yakuniy production holati (READ ONLY)

| | |
|---|---|
| Migratsiyalar | 001 … 006b, **007a** |
| `is_required` ustuni | bor |
| Jadvallar / funksiyalar / triggerlar / policy / indekslar | 44 / 94 / 91 / 98 / 104 |
| CASCADE | 0 |
| anon EXECUTE | faqat `verify_certificate` |
| policy_md5 | `f27165f6…` (o'zgarmagan) |
| Qator sonlari | courses 13, questions 131, exam_configs 13, attempts 2, certificates 0, profiles 1, employees 1, audit_logs 307 |

## 9. Smoke (anon REST, publishable kalit)

| So'rov | HTTP | Izoh |
|---|---|---|
| `rpc/my_learning_progress` | **401** | |
| `rpc/course_progress_summary` | **401** | |
| `rpc/_lp_course_stats_007a` | **401** | |
| `rpc/lesson_progress_completion_007a` | 404 | trigger funksiyasi RPC sifatida mavjud emas |
| `rpc/verify_certificate` | **200** | ommaviy tekshiruv ishlaydi |

## 10. Rollback

**Bajarilmadi.** Zarurat yo'q: barcha tekshiruvlar PASS.

Tayyor holatda: `79_rollback_007a.sql` + `007a_04_compare_pre.sql`.

## 11. Git

- Faqat admin branch:
  - shu hisobot;
  - `production/44_…_evidence`, `55_…_evidence`, `56_…_evidence` (test mantig'i o'zgarmagan, faqat JSON natija qo'shilgan).
- `main` / GitHub Pages / employee build o'zgarmagan.
- 007b–007e boshlanmagan.

## Yakuniy holat

**PHASE 3 STEP 5 — 007a PRODUCTION DEPLOYMENT COMPLETE — 007a = 1, ALL GATES PASS**
