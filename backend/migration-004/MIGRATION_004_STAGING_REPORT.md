# MedAcademy — Migration 004 hisoboti (LOCAL + STAGING)

Sana: 2026-11-21 · Holat: **STAGING PASS · PRODUCTION'GA QO'LLANMAGAN**

## 1. Xulosa
- Migration 004 (004a + 004b) avval lokal muhitda, keyin staging'da (`zwzxyikocqxbeyejeyga`) qo'llandi va sinovdan o'tdi.
- Natija: lokal 50/50 PASS, staging 50/50 PASS. Phase 1 regressiyasi 32/32 PASS.
- Production (`buuwjhpzptiiyggybvwr`) ga tegilmadi. Frontend o'zgarmadi.

## 2. Fayllar
| Fayl | Vazifasi |
|---|---|
| `backend/migrations/004a_org_structure.sql` | Yangi jadvallar, ruxsatlar, audit, RLS, seed, ko'chirish |
| `backend/migrations/004b_org_isolation_existing.sql` | Phase 1 jadvallari va RPC'larga `org_id` izolyatsiyasi |
| `backend/staging/004_apply.sql` | 004a+004b birlashtirilgan (staging uchun) |
| `backend/tests/004_test_setup.sql` | Org B va 8 ta test foydalanuvchi (production'da o'zini bloklaydi) |
| `backend/tests/004_tests.sql` | 50 ta test; bitta tranzaksiya, oxirida ROLLBACK |
| `tests/m004_local.mjs` | Lokal PGlite harness |

## 3. Mavjud sxema bilan konfliktlar (jadval yaratishdan oldin tekshirildi)
- `roles` jadvali yaratilmadi. Mavjud `profiles.role` mexanizmi ishlatiladi.
- `profiles` almashtirilmadi. `employees.profile_id` unga FK bo'lib bog'lanadi (unique).
- `profiles.department` (matn) saqlab qolindi va `departments.id` ga map qilindi.
- `departments` nomli jadval avval yo'q edi, shuning uchun konflikt bo'lmadi.
- **005 uchun ochiq masala:** `courses.id` va `questions.id` global text PK. Bu ko'p-tashkilotli kontent bilan to'qnashadi. 004'da tegilmadi.

## 4. Yangi jadvallar (9 ta)
- `schema_migrations`
- `branches`
- `departments` (`parent_id`, `head_employee_id`)
- `positions` (`academy`, `family`)
- `specialties`
- `employees`
- `permissions` (29 ta kalit)
- `role_permissions`
- `audit_logs`

`organizations` jadvaliga `code`, `status`, `updated_at` ustunlari qo'shildi (Impuls → `IMPULS`).

## 5. Ruxsatlar matritsasi (`seed_org_defaults`)
- Har bir tashkilot uchun seed qilinadi: org A'da 56 qator. Yangi tashkilot yaratilganda trigger avtomatik ishga tushiradi.
- `super_admin` uchun `has_perm()` har doim `true`.
- `department_head` da `employee.view` va `department.view` yo'q. U faqat o'z bo'limini RLS orqali ko'radi.
- `instructor` da `employee.view` yo'q.

## 6. Tashkilot izolyatsiyasi (RLS)
- Barcha jadvallarda `org_id NOT NULL`.
- Barcha siyosatlarda `org_id = my_org()` sharti bor (SELECT, INSERT, UPDATE).
- Delete siyosati yo'q, ya'ni API orqali hard delete qilib bo'lmaydi.
- `enforce_same_org()` trigger'i cross-org bog'lanishni va `org_id` o'zgartirishni RLS'dan tashqari ham bloklaydi.
- Phase 1 jadvallari va RPC'lari ham org bo'yicha filtrlangan: `start_exam`, `get_attempt_review`, `question_meta`, `admin_reset_attempts`, `revoke_certificate`.

## 7. Department Head izolyatsiyasi
- Bo'lim boshlig'i o'z bo'limi xodimlarini ko'radi (`my_department_id()`).
- Boshqa bo'limlar, ularning xodimlari va profillari ko'rinmaydi.
- `employee.edit` ruxsati yo'q, shuning uchun tahrirlay olmaydi.

## 8. Server-side audit
- `audit_row()` trigger'i 5 ta tuzilma jadvali va `role_permissions` ustida ishlaydi.
- Amallar: `created`, `updated`, `deleted`, `deactivated`, `permission.granted`, `permission.revoked`.
- Har bir yozuvda `old_value` va `new_value` (jsonb), aktor, org va IP saqlanadi.
- `audit_logs` klient uchun faqat o'qish uchun ochiq.

## 9. FK, UNIQUE va indekslar
- `(org_id, code)` har bir tashkilot ichida unique. Kod formati: `^[A-Z0-9_-]{2,32}$`.
- `employees`: `(org_id, employee_code)` unique va `profile_id` unique.
- FK'lar: `RESTRICT` yoki `SET NULL`. CASCADE ishlatilmagan.
- 8 ta indeks, faqat RLS va FK filtrlari uchun.

## 10. Mavjud ma'lumot ko'chirilishi
- `profiles` va `docs.employees` dan `employees` yozuvlari yaratildi (kod: `EMP-XXXXXXXX`).
- Admin `EMP-262A128C` sifatida `CARDIO` bo'limiga bog'landi; `profiles.department` = "Kardiologiya" saqlanib qoldi.
- O'tish davri: `docs → employees` sinxron trigger ishlaydi. Xodim faqat bo'sh maydonlarni to'ldira oladi; HR maydonlarini (bo'lim, ism) o'zgartira olmaydi. Trigger docs yozuvini hech qachon bloklamaydi.

## 11. Migratsiya sifati
- DROP TABLE, TRUNCATE yoki DELETE yo'q (grep orqali tekshirildi).
- Idempotent: lokal va staging'da 2 martadan ishga tushirildi, xatosiz.
- `anon` rolidan barcha huquqlar olingan. Service role key frontend'da yo'q, repoda sir yo'q.
- `drop policy if exists` va `drop trigger if exists` faqat siyosat va trigger'larni qayta yaratish uchun ishlatilgan. Supabase shu sababli "destructive" ogohlantirishini ko'rsatadi; ma'lumot o'chirilmaydi.

## 12. Lokal test natijalari (PGlite)
- 004 testlari: **50/50 PASS**.
- Testdan keyin ROLLBACK tekshirildi: sertifikat 0, urinish 1 (o'zgarmagan).
- `sql_test.mjs` (Phase 1, 004 bilan): **32/32 PASS**.
- `guard_test.mjs` (004 bilan): API sharoitida self-promote bloklandi. Natija 004'siz holat bilan bir xil.

## 13. Staging test natijalari (50 ta, barchasi PASS)
| ID | Test | Natija |
|---|---|---|
| A1 | Org A Super Admin → Org B, 9 jadvalda SELECT (0 qator) | PASS |
| A2 | Org A → Org B'da department INSERT (DENIED) | PASS |
| A3 | Org A → Org B'da department UPDATE (0 qator) | PASS |
| A4 | Org A → Org B'da role_permissions DELETE (0 qator) | PASS |
| A5 | Org B Admin → Org A: employees, profiles, docs, attempts, certs, questions, courses, configs (0 qator) | PASS |
| A6 | Xodimni Org B bo'limiga API orqali bog'lash (DENIED) | PASS |
| A6b | Cross-org bog'lash, RLS'siz (DB trigger DENIED) | PASS |
| A7 | Org B → Org A kursi bo'yicha imtihon RPC (DENIED) | PASS |
| A8 | Org B → Org A savollar meta (0) | PASS |
| A9 | Org A → Org B xodimining urinishlarini tiklash (DENIED) | PASS |
| B1 | Employee → boshqa xodimlar ma'lumoti (0) | PASS |
| B2 | Employee → boshqa xodimni UPDATE (0) | PASS |
| C1 | Dept Head → o'z bo'limi xodimlari (3) | PASS |
| C2 | Dept Head → boshqa bo'lim xodimlari (0) | PASS |
| C3 | Dept Head → boshqa bo'limlar (0) | PASS |
| C4 | Dept Head → boshqa bo'lim profillari (0) | PASS |
| C5 | Dept Head → xodimni tahrirlash (0) | PASS |
| D1 | Instructor → boshqa tashkilot ma'lumoti (0) | PASS |
| D2 | Instructor → xodimlar ro'yxati (0) | PASS |
| D3 | Instructor → bo'lim yaratish (DENIED) | PASS |
| E1 | Super Admin → o'z tashkilotining barcha xodimlari (7/7) | PASS |
| E2 | Super Admin → bo'lim yaratish va tahrirlash, audit=2 | PASS |
| F1 | Employee → o'z employee yozuvi va profili (1+1) | PASS |
| F2 | Employee → faqat o'z bo'limi (1) | PASS |
| G1 | Employee → o'ziga super_admin roli (DENIED) | PASS |
| G2 | Employee → o'z roliga ruxsat qo'shish (DENIED) | PASS |
| G3 | HR → kimgadir super_admin roli (DENIED) | PASS |
| G4 | Employee → o'zini boshqa tashkilotga o'tkazish (DENIED) | PASS |
| H1 | Anonim → 15 ta jadval (15/15 DENIED) | PASS |
| I1 | Employee → soxta audit yozuvi (DENIED) | PASS |
| I2 | Employee → xodim yaratish (DENIED) | PASS |
| I3 | Employee → `seed_org_defaults()` chaqirish (DENIED) | PASS |
| I4 | `employee.deactivate` ruxsatisiz faolsizlantirish (DENIED) | PASS |
| I5 | HR ruxsat bilan faolsizlantiradi, audit old/new=1 | PASS |
| I6 | Ruxsat berish va olish audit qilinadi (2) | PASS |
| K1 | Filialni o'chirish (FK RESTRICT, 23503) | PASS |
| K2 | Xodimi bor bo'limni o'chirish (FK RESTRICT, 23503) | PASS |
| K3 | Mavjud bo'lmagan bo'limga bog'lash (DENIED) | PASS |
| K4 | API orqali xodimni hard delete (0) | PASS |
| R1 | Mavjud ma'lumot: 13 kurs, 131 savol, admin super_admin, bo'lim matni | PASS |
| R2 | Phase 1: imtihon payload'ida javoblar yo'q | PASS |
| R3 | Phase 1: to'g'ri javoblar → 100%, sertifikat org A'da | PASS |
| R4 | Phase 1: QR tekshiruv "Amalda" | PASS |
| R5 | Phase 1: initial assessment 12 savol, org A | PASS |
| R6 | Phase 1: fail bo'lgandan keyin retake bloklanadi | PASS |
| S1 | `docs → employees` sinxron, HR maydonlari himoyalangan | PASS |
| U1 | Bir tashkilotda takroriy `department.code` (unique_violation) | PASS |
| U2 | Turli tashkilotlarda bir xil `CARDIO` kodi (2) | PASS |
| U3 | Takroriy `employee_code` (unique_violation) | PASS |
| U4 | Takroriy `position.code` (unique_violation) | PASS |

## 14. Staging ma'lumotlari: oldin va keyin
| | Oldin | 004 dan keyin (setup va testlardan so'ng) |
|---|---|---|
| profiles | 1 | 9 (1 + 8 test foydalanuvchi) |
| docs / courses / questions / configs | 5 / 13 / 131 / 13 | 5 / 13 / 131 / 13 |
| exam_attempts / certificates | 1 / 0 | 1 / 0 (test ROLLBACK ishladi) |
| admin | super_admin/active/Kardiologiya | o'zgarmagan, `EMP-262A128C/CARDIO` |
| `org_id` NULL qatorlar | — | 0 |
| RLS'siz public jadvallar | — | 0 |
| schema_migrations | yo'q | 001, 002, 003, 004a, 004b |

## 15. Ma'lum cheklovlar va xavflar
1. Staging'da brauzer orqali (PostgREST) frontend smoke test o'tkazilmadi, chunki staging anon key frontend'ga ulanmagan. API holati SQL'da `authenticated`/`anon` rollari va JWT claim'lari bilan simulyatsiya qilindi. Lokal guard_test esa `authenticator` sessiyasini to'liq simulyatsiya qildi.
2. K3: mavjud bo'lmagan bo'lim uchun xato matni "Boshqa tashkilotga tegishli…" deb chiqadi. Bloklash to'g'ri ishlaydi, faqat matn noaniq; 005'da tuzatsa bo'ladi.
3. Yangi ro'yxatdan o'tgan har bir foydalanuvchi avtomatik Impuls tashkilotiga tushadi (`handle_new_user`). Ko'p tashkilotli onboarding hali yo'q.
4. Kurs darajasida instruktor biriktirish (`course_instructors`) 005 rejasida.
5. `courses.id` va `questions.id` global PK: 005'da hal qilinadi.
6. Free tier: avtomatik backup yo'q. Production'ga qo'llashdan oldin qo'lda backup shart (Phase 1'dagi kabi).
7. SMTP hal qilinmagan, xodimlarning ro'yxatdan o'tishi hali bloklangan.

## 16. Tavsiya va keyingi qadam
- Staging PASS. Production'ga **qo'llanmadi**.
- Production uchun taklif qilinadigan tartib (sizning tasdig'ingizdan keyin):
  1. Backup schema yaratish.
  2. `004_apply.sql` ni qo'llash. Test setup **ishlatilmaydi**.
  3. Verify so'rovi.
  4. Live sayt smoke test.
- To'xtadim: production 004, migration 005, Admin Panel kodi va sxemani qayta yozish — sizning alohida tasdig'ingizni kutadi.
