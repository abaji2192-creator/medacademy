# Migration 007a — Learning Progress RPC Foundation

**Holat:** lokal PASS; STAGING'ga qo'llangan va tekshirilgan (2026-11-25). Production'ga QO'LLANMAGAN.
**Oldingi shart:** `schema_migrations` da `006b` bo'lishi kerak (aks holda migratsiya to'xtaydi).

## Fayllar

| Fayl | Vazifa | SHA-256 |
|---|---|---|
| `migration-007a.sql` | Migratsiya (bitta tranzaksiya, idempotent) | `d8bacfc0f7c39ec4e0c332366a4ce81bab45c3e97841b81d0e0d8813a28b151a` |
| `rollback-007a.sql` | Faqat incident uchun bekor qilish | `fb9a540b97733def43f375420f18a33c22286e3b464ba4ca3625fd37c0d54ccf` |
| `tests/007a_tests.sql` | 55 ta SQL test (vaqtinchalik fixture, oxirida ROLLBACK) | `25bb5c25…` |
| `tests/m007a_local.mjs` | Lokal PGlite: 007a ×2 (idempotentlik) → testlar | |
| `tests/m007a_rollback_local.mjs` | Apply → rollback → reapply ×2 → testlar → rollback → reapply (27 tekshiruv) | |
| `tests/perf007a.mjs` | 1000 xodim × 50 kurs yuklama testi | |
| `tests/run_all_007a.sh` / `.out` | To'liq Phase 2 regressiyasi 007a qo'llangan holda | |

## Nima o'zgaradi

1. `lessons.is_required boolean NOT NULL DEFAULT true` — yangi ustun; mavjud darslar majburiy bo'lib qoladi.
2. RPC `my_learning_progress()` — faqat joriy xodimning o'z tayinlashlari (12 maydon).
3. RPC `course_progress_summary(p_course)` — tayinlangan / boshlanmagan / jarayonda / tugallangan / muddati o'tgan / bekor qilingan soni va o'rtacha progress.
   - SA, EM, HR: butun tashkilot.
   - Department Head: faqat o'z bo'limi.
   - Instructor: faqat o'z kursi.
   - Boshqalar va anon: rad etiladi.
4. Kurs tugallanishi: oxirgi majburiy dars tugallanganda tayinlash `completed` ga o'tadi va bitta `course.completed` audit yoziladi. Sertifikat berilmaydi.
5. Ikkita indeks: `lesson_progress_completed_007a_idx` (qisman, `status='completed'`) va `course_assignments_course_007a_idx` (oddiy, `org_id, course_id, status`).

Yangi jadval yo'q. RLS policy'lari, mavjud funksiyalar va ma'lumotlar o'zgarmaydi.

## Progress qoidalari

- **Majburiy dars:** `is_required` va dars hamda moduli `published`.
- **Ixtiyoriy darslar:** maxrajga kirmaydi.
- **Majburiy darsi yo'q kurs:** progress 0%, avtomatik tugallanmaydi.
- **Holat ustuvorligi:** `cancelled` > `completed` > `overdue` > `in_progress` > `not_started`.
- **Overdue:** faqat o'qishda hisoblanadi, bazaga yozilmaydi. Muddati bugun bo'lsa — overdue emas.

## Rollback

`rollback-007a.sql` quyidagilarni olib tashlaydi:

- trigger;
- funksiyalar;
- indekslar;
- `is_required` ustuni;
- `schema_migrations` dagi `'007a'` yozuvi.

Tarixiy ma'lumotlar saqlanadi:

- `completed` tayinlashlar;
- `course.completed` audit yozuvlari;
- `lesson_progress`.

**Diqqat:** agar production'da ba'zi darslar `is_required = false` qilib belgilangan bo'lsa, rollback bu belgini yo'qotadi.

## Staging skriptlari (`staging/`)

| Fayl | Vazifa |
|---|---|
| `007a_00_backup.sql` | `backup.*_pre007a` snapshot (jadvallar, ustunlar, indekslar, policy, funksiya, trigger) |
| `007a_01_fingerprint.sql` | Faqat SELECT; sxema / huquq / ma'lumot barmoq izi (v2) |
| `007a_03_perf.sql` | 1000 xodim × 50 kurs yuklama testi, oxirida ROLLBACK |
| `007a_04_compare_pre.sql` | Joriy katalogni `backup.*_pre007a` bilan solishtirish (rollback tekshiruvi) |
