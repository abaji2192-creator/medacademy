# MedAcademy — PHASE 3 STEP 2 — Migration 007a hisoboti (LOCAL ONLY)

**Sana:** 2026-11-24
**Doira:**

- faqat lokal (PGlite, production zanjirining nusxasi: 002/003 → 004 → 005 → 005d → 005e → 006a → 006b → 007a);
- staging, production va `main` ga hech narsa yuborilmagan.

**Yakuniy holat: LOCAL PASS — staging uchun tayyor (tasdiq kutilmoqda).**

## 1. Qabul qilingan qarorlar (foydalanuvchi tasdig'i)

| Masala | Qaror |
|---|---|
| Kurs tugallanishi | Barcha majburiy darslar tugallanganda (imtihon shart emas) |
| Majburiy / ixtiyoriy dars | `lessons.is_required` ustuni qo'shildi, default `true` |
| Department Head | Progress'ni ko'radi — faqat o'z bo'limi (skill.assess 007c'da) |
| Legacy docs JSON | Import qilinmaydi |

## 2. Artefaktlar

| Fayl | Hajm | SHA-256 |
|---|---|---|
| `backend/migration-007a/migration-007a.sql` | 13 939 B | `d8bacfc0f7c39ec4e0c332366a4ce81bab45c3e97841b81d0e0d8813a28b151a` |
| `backend/migration-007a/rollback-007a.sql` | 1 718 B | `fb9a540b97733def43f375420f18a33c22286e3b464ba4ca3625fd37c0d54ccf` |
| `backend/migration-007a/tests/007a_tests.sql` | — | `25bb5c25fa3c1d71059f7d41a66d214488206b029b9ece6335fb4c61a8ca7bc6` |

## 3. Migratsiya mazmuni

**Ustun:**

- `lessons.is_required` (NOT NULL DEFAULT true) — additive.
- Mavjud qatorlar qayta yozilmaydi.

**Indekslar:**

- Avval mavjudlari tekshirildi: `lesson_progress_uq`, `lesson_progress_employee_idx`, `course_assignments_employee_idx`, `course_assignments_org_status_idx`, `course_modules_course_idx`, `lessons_module_idx`.
- Faqat ikkitasi qo'shildi:
  - `lesson_progress_completed_007a_idx (employee_id, lesson_id) WHERE status='completed'`;
  - `course_assignments_course_007a_idx (org_id, course_id, status)`.

**RPC'lar** (SECURITY DEFINER, `search_path=public`, anon'dan REVOKE, faqat authenticated):

- `my_learning_progress()`:
  - faqat `my_employee_id()` va `my_org()`;
  - faol xodim yozuvi bo'lmasa — bo'sh ro'yxat;
  - 12 maydon qaytaradi: course_id, course_title, assignment_id, assignment_status, assigned_at, due_date, completed_at, total_required_lessons, completed_required_lessons, progress_percent, computed_status, last_activity_at.
- `course_progress_summary(p_course)`:
  - jsonb qaytaradi: scope, total_required_lessons, assigned/not_started/in_progress/completed/overdue/cancelled soni, average_progress.

**Ichki funksiyalar** (authenticated uchun EXECUTE yo'q; `function_categories_005d` da `internal`): `_lp_course_stats_007a`, `_lp_status_007a`, `lesson_progress_completion_007a`.

**Tugallash trigger'i** — `lesson_progress_completion_007a_trg`, AFTER INSERT / UPDATE OF status:

- faqat holat `completed` ga o'tganda ishlaydi;
- faol tayinlashni (assigned / in_progress / overdue) `completed` ga o'tkazadi;
- `_audit006` orqali bitta `course.completed` yozadi (old/new status, required_lessons);
- qayta belgilash audit yozmaydi;
- o'qish RPC'lari audit yozmaydi;
- sertifikat bermaydi.

**Hisobga olish:** `schema_migrations '007a'`; oldingi shart sifatida 006b talab qilinadi.

## 4. Test natijalari

| To'plam | Natija |
|---|---|
| 007a SQL testlari (P progress, Z chegaraviy, S xavfsizlik, R rollar/doira, I invariantlar) | **55 / 55 PASS** |
| 007a rollback / recovery (apply → rollback = boshlang'ich holat → reapply ×2 → testlar → residue 0 → qayta rollback/reapply) | **27 / 27 PASS** |
| Idempotentlik (007a ikki marta ketma-ket) | PASS |
| 006b (007a bilan) | 34 / 34 |
| 006b rollback | 18 / 18 |
| 006a (006b+007a bilan) | 83 / 83 |
| 006a rollback | 21 / 21 |
| 005e security | 146 / 146 |
| 005e rollback | 21 / 21 |
| 005d suite | 101 / 0 FAIL |
| 005 suite | 114 / 0 FAIL |
| 004 suite (005 setup bilan) | 50 / 0 FAIL |
| 004 suite (standalone) | 50 / 0 FAIL |
| Phase 1 SQL | barchasi o'tdi |
| 005d_04 | 54 / 0 FAIL |
| 005d_06 role matrix | 62 / 0 FAIL |
| 44_security_tests_005d | 54 / 0 FAIL |
| P01–P20 probe | o'zgarishsiz (005e kutilgan natijalari) |

Admin Panel kodi o'zgarmagan (109/109 oldingi natija amalda).

### Qamrab olingan holatlar

- **Progress:**
  - 0/10, 1/10 (10%), 9/10 (90%) va 10/10 (100%, completed);
  - ixtiyoriy dars foizni o'zgartirmaydi;
  - draft dars va draft modul maxrajga kirmaydi.
- **Holatlar:**
  - muddati kecha → overdue;
  - muddati bugun → overdue emas;
  - bekor qilingan + muddati o'tgan → cancelled;
  - overdue bazaga yozilmaydi;
  - majburiy darssiz kurs → 0%, avtomatik tugallanmaydi;
  - faqat ixtiyoriy dars tugallangan bo'lsa → in_progress;
  - arxivlangan kurs tarixiy progress'ni ko'rsatadi.
- **Xavfsizlik:**
  - xodim faqat o'zini ko'radi;
  - boshqa xodim progress'i yoki tayinlashi RLS bilan yopiq;
  - boshqa xodim nomidan yozish rad etiladi;
  - Org B izolyatsiyasi;
  - anon rad etiladi;
  - nofaol xodim bo'sh ro'yxat oladi;
  - (lesson, employee) takror qatori rad etiladi.
- **Rollar (8 ta + anon):**

  | Rol | Natija |
  |---|---|
  | SA / EM / HR | butun tashkilot |
  | Department Head | faqat o'z bo'limi (Kardiologiya: 1 tayinlash; Terapiya ko'rinmaydi) |
  | Instructor | faqat o'z kursi (CARDIO_BASIC) |
  | MR / Employee / anon | rad |
  | Org B admin → Org A kursi | rad |
  | Mavjud bo'lmagan kurs | rad |

- **Invariantlar:**
  - anon EXECUTE faqat `verify_certificate`;
  - RLS policy md5 o'zgarmagan;
  - exam_attempts va certificates o'zgarmagan;
  - public jadvallar 44 (yangi jadval yo'q);
  - CASCADE FK yo'q.

## 5. Unumdorlik (PGlite, 1000 xodim × 50 kurs)

**Yuklama:** 50 000 tayinlash, 248 623 progress qatori, 500 dars.

| O'lchov | Natija (median) |
|---|---|
| `my_learning_progress()` — 50 kurs | 3.9 ms |
| `course_progress_summary` — SA, 1000 xodim | 37.5 ms |
| `course_progress_summary` — Head, 250 xodim | 14.6 ms |
| Tugallash trigger'i (INSERT boshiga) | 9.8 ms |

- Tugallash trigger'i to'g'ri ishladi: completed, audit = 1.
- Rejada `lesson_progress_completed_007a_idx` ishlatildi (Index Only Scan).
- Haqiqiy Postgres'da (Supabase) bu ko'rsatkichlar odatda bundan tezroq bo'ladi.

## 6. Cheklovlar va eslatmalar

- `my_learning_progress().last_activity_at` — `lesson_progress.last_accessed_at` ning eng kattasi. Agar ilova bu ustunni yangilamasa, qiymat NULL bo'ladi.
- `course.completed` audit'ida `old_value.status` — tugallashdan oldingi haqiqiy holat (odatda `in_progress`).
- Tugallash faqat `lesson_progress` o'zgarishida tekshiriladi. Kursga keyinroq yangi majburiy dars qo'shilsa, avval tugallangan tayinlash qayta ochilmaydi. Bu ataylab shunday qilingan: tarix saqlanadi.
- Rollback `is_required` ustunini olib tashlaydi. Production'da `false` belgilangan darslar bo'lsa, ular yo'qoladi (README'da ogohlantirilgan).
- Employee ilovasi hali legacy docs JSON'dan foydalanadi. UI integratsiyasi keyingi bosqichda.

## 7. Keyingi qadam (tasdiq talab qilinadi)

**STEP 3 — 007a staging:**

1. Backup va fingerprint.
2. Apply.
3. `007a_tests.sql` (ROLLBACK bilan).
4. Rollback / reapply.
5. Regressiya (006a / 006b / 005e).

Production — alohida tasdiq bilan.
