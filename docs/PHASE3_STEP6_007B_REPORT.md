# MedAcademy — PHASE 3 STEP 6 — Migration 007b (Learning Path Assignments) — LOCAL hisobot

**Sana:** 2026-11-26
**Doira:** faqat lokal (PGlite; zanjir: 002/003 → 004 → 005 → 005d → 005e → 006a → 006b → 007a → 007b).
**Yakuniy holat:** **PHASE 3 STEP 6 — 007b LOCAL IMPLEMENTATION COMPLETE — READY FOR STAGING REVIEW**

## 1. Arxitektura — haqiqiy sxema tekshiruvi

Quyidagilar lokal bazadan o'qildi (taxmin qilinmadi).

| Obyekt | Tuzilma va qoidalar |
|---|---|
| `learning_paths` | `id uuid`, `org_id`, `code` (org bo'yicha unique), `title`, `status` draft / published / archived, `target_position_family` |
| `learning_path_courses` | `path_id`, `course_id text`, `order_index`, `is_required` |
| `course_assignments` | `course_id text`, `employee_id uuid`, `due_date date`, `status` assigned / in_progress / completed / overdue / cancelled |
| `course_assignments` cheklovlari | `UNIQUE (course_id, employee_id) WHERE status <> 'cancelled'`; trigger'lar: guard (`assigned_by` = `auth.uid()`), audit_row, same_org |
| `employees` | `department_id`, `position_id`, `specialty_id`, `profile_id`, `employment_status` active / on_leave / inactive / terminated |
| Rol | `profiles.role` — 8 qiymat |
| Ruxsatlar | `learning_path.manage` mavjud (role_permissions'da faqat education_manager); `super_admin` `has_perm` orqali hamma ruxsatga ega |

Yangi ruxsat qo'shilmadi.

## 2. Dizayn va semantika

| Masala | Qaror |
|---|---|
| Model | `learning_path_assignments` — tayinlash QOIDASI. CHECK orqali aniq **bitta** nishon (employee / department / position / specialty / role). `target_key` — generatsiya qilingan ustun. |
| Takror qoida | `UNIQUE (path_id, target_type, target_key) WHERE status = 'active'` |
| Yo'nalish holati | Faqat `published` tayinlanadi. `draft` va `archived` rad etiladi. Arxivlangan yo'nalish reapply'da ham rad. Avval yaratilgan kurs tayinlashlari saqlanadi. |
| Kurslar | Faqat `is_required = true` va `courses.status = 'published'` kurslar tayinlanadi. Ixtiyoriy kurslar xodim tanloviga qoladi; draft kurs tayinlanmaydi. |
| Mos xodimlar | Faqat `employment_status IN (active, on_leave)`. `role` nishonida qo'shimcha `profiles.status = 'active'`. Nofaol xodimga to'g'ridan-to'g'ri tayinlash rad etiladi; guruh ichidagi nofaol xodim o'tkazib yuboriladi. |
| Takrorlanmaslik | Xodim × kurs uchun **har qanday** mavjud qator bo'lsa, yangisi yaratilmaydi: `NOT EXISTS` + `ON CONFLICT … DO NOTHING` (mavjud unique index). |
| Mavjud tayinlashlar | Tugallangan → saqlanadi. Jarayondagi → progress saqlanadi. Bekor qilingan → jim qayta faollashtirilmaydi (admin qo'lda tayinlashi mumkin). |
| Muddat | `due_date` mutlaq sana, ixtiyoriy, o'tgan sana rad etiladi. Faqat shu qoida yangi yaratgan kurs tayinlashlariga qo'yiladi; mavjud tayinlashlar muddati o'zgarmaydi. Mavjud qoidaga yangi muddat berilsa → `assignment_updated`. |
| Qoida holati | `active` / `cancelled` (sabab majburiy). Bekor qilish yaratilgan kurs tayinlashlarini **bekor qilmaydi**. Qayta faollashtirish va DELETE guard trigger bilan taqiqlangan; yangi qoida yaratish mumkin. |
| Idempotentlik | Qayta chaqiruv yangi qator yoki audit yaratmaydi. `reapply_learning_path_assignment` keyin qo'shilgan xodimlarni qamraydi. |
| Ruxsat | SA va `learning_path.manage` egalari (EM) — tashkilot doirasida. HR, Department Head (o'z bo'limi ham), Instructor, MR, Employee, anon — **rad** (mavjud ruxsat modelida ularda `learning_path.manage` yo'q). |
| 007a | O'zgarmaydi. 007b yaratgan tayinlash 007a trigger'i orqali tugallanadi (Q01, Q02). |

## 3. Migratsiya obyektlari

**Artefaktlar:**

| Fayl | SHA-256 |
|---|---|
| `backend/migration-007b/migration-007b.sql` (21 215 B) | `36b2994eefa758a7db169ed3dab3d50ac9009c7b53043a0ab7ba7acada5f8553` |
| `backend/migration-007b/rollback-007b.sql` (1 785 B) | `1c4fbfc663c7a6017589468beabe5a466946b22c237047a3a644d8f1542f31f5` |
| `tests/007b_tests.sql` | `075dc3c7…` |

**Jadval:** `learning_path_assignments`
- FK'lar hammasi `ON DELETE RESTRICT`;
- CHECK: `lpa_exactly_one_target`, `lpa_cancel_consistent`, `target_type` / `status` / rol ro'yxatlari.

**Indekslar:**
- `lpa_active_target_uq` — unique partial;
- `lpa_org_status_idx`;
- `employees_org_dept_007b_idx`.
- Xodim × kurs qidiruvi mavjud `course_assignments_active_uq` / `employee_idx` indekslaridan foydalanadi.

**RLS va huquqlar:**
- `lpa_select_007b`: `org_id = my_org()` va (`learning_path.manage` yoki `assignment.view`).
- INSERT / UPDATE / DELETE policy yo'q; anon / authenticated'dan yozish grant'lari olib tashlangan. Yozuv faqat RPC orqali.

**Trigger:** `lpa_guard_007b_trg` (BEFORE INSERT / UPDATE / DELETE):
- tashkilot mosligi (path / employee / department / position / specialty);
- o'zgarmas maydonlar;
- qayta faollashtirish va DELETE taqiqi.

**Funksiyalar** (hammasi SECURITY DEFINER, `search_path = public`):

| Funksiya | Turi | Vazifa |
|---|---|---|
| `apply_learning_path(p_path, p_target_type, p_target_id, p_due_date)` | RPC | Qoidani yaratadi yoki qayta ishlatadi va kurslarni tayinlaydi |
| `reapply_learning_path_assignment(p_assignment)` | RPC | Qoidani qayta qo'llaydi |
| `cancel_learning_path_assignment(p_assignment, p_reason)` | RPC | Qoidani bekor qiladi |
| `_lpa_apply_rule_007b` | ichki | Set-based: bitta CTE + bitta INSERT (N+1 yo'q) |
| `_lpa_can_manage_007b` | ichki | Ruxsat tekshiruvi |
| `guard_lpa_007b` | ichki | Trigger funksiyasi |

Ichki funksiyalar authenticated'ga yopiq; barchasi `backup.function_categories_005d`'da ro'yxatga olingan.

**Audit** (`_audit006`, mavjud `entity.action` konvensiyasi):
- `learning_path.assignment_created`, `learning_path.assignment_updated`, `learning_path.assignment_cancelled`, `learning_path.courses_applied` (faqat haqiqiy o'zgarishda).
- Kurs tayinlashlari mavjud `audit_row` trigger'i bilan qayd etiladi.

Yangi jadvaldan boshqa sxema o'zgarishi yo'q; CASCADE yo'q; mavjud ma'lumot qayta yozilmaydi.

## 4. Testlar — `007b_tests.sql`: **77/77 PASS**

| Guruh | Qamrov |
|---|---|
| A — employee nishoni | A01–A08: yaratish 1 xodim / 2 kurs (ixtiyoriy va draft kurs yo'q); 2 marta qayta → existing / 0; bitta active qoida; audit created 1, applied 1; muddat bilan → updated, audit 1, eski muddatlar o'zgarmagan |
| B — department | Barcha faol a'zolar; HEAD'ning bekor qilingan C1 saqlangan, C2 yangi; qoida muddati yangi qatorlarda; nofaol a'zo 0 |
| C / D — position, specialty | Mos keldi, takror 0 |
| E — role | Org A faol employee-rolli xodimlar |
| I — takrorlanmaslik | EMP 4 qoidaga mos → C1 = 1, C2 = 1 qator; butun tashkilot bo'yicha takror 0 |
| J / K — mavjud tayinlashlar | Tugallangan (`completed_at` o'zgarmagan) va jarayondagi saqlangan |
| G — yo'nalish holati | Arxivlangan / draft rad; arxivdan keyin reapply rad, mavjud tayinlashlar saqlangan |
| F / O — cross-org | Org A path → Org B employee / department / position / specialty rad; Org A EM → Org B path rad; Org B admin → Org A path rad; Org B role nishoni faqat Org B xodimlariga; Org A'ga Org B kursi 0 |
| M — validatsiya | Bo'sh nishon, noma'lum tur, noto'g'ri UUID, noma'lum rol, o'tgan muddat, mavjud bo'lmagan path — rad |
| N — nofaol xodim | To'g'ridan-to'g'ri tayinlash rad |
| P — role matrix | SA ✓; HR, Head, Instructor, MR, Employee, anon — rad; Employee / anon reapply va cancel — rad; Org B admin Org A qoidasiga — rad |
| S — RLS | Employee 0, EM 6, Head (assignment.view) 6, Org B admin 1, MR 0, anon rad; EM to'g'ridan-to'g'ri INSERT / UPDATE / DELETE rad; SQL darajasida ikki nishonli qoida va cross-org (guard) rad |
| R / X — reapply va cancel | Yangi xodim → reapply 2 kurs, qayta 0; sababsiz cancel rad; cancel OK, kurs tayinlashlari o'zgarmagan; qayta cancel → changed false, audit 1; bekor qilinganni reapply rad; SQL qayta faollashtirish / DELETE rad; yangi qoida mumkin, takror kurs 0 |
| Q — 007a mosligi | 007b tayinlashi darsni tugatish bilan completed + `course.completed` 1; `my_learning_progress` 1/1/100/completed |
| V — invariantlar | anon faqat `verify_certificate`; ichki funksiyalar yopiq; urinish / sertifikat md5 o'zgarmagan; CASCADE 0; jadvallar 45; RLS bor, yozish grant'lari 0 |

## 5. Rollback / Reapply / Idempotentlik — **25/25 PASS**

- **Apply:** biznes ma'lumoti va sonlar o'zgarmagan; policy +1; anon `verify_certificate`; jadval +1; CASCADE 0.
- **Rollback:** fingerprint v2'ning har bir maydoni 007b'dan oldingi holatga **aynan** teng.
- **Reapply ×2:** birinchi qo'llash bilan bir xil.
- **Testlar:** 77/77, residue 0.
- **Ikkinchi rollback → reapply:** birinchi qo'llash bilan bir xil.
- **Rollback nimani saqlaydi:** 007b yaratgan `course_assignments` va `learning_path.*` audit yozuvlari. 007a va Phase 2 obyektlariga tegmaydi.

## 6. Unumdorlik (PGlite: 1000 xodim, 4 bo'lim, 50 yo'nalish × 5 majburiy kurs)

| Operatsiya | median | p95 | max |
|---|---|---|---|
| Bo'lim qoidasi yaratish + qo'llash (~250 xodim × 5 kurs = 1 250 tayinlash, har qatorda mavjud audit / guard trigger'lari) | 314 ms | 385 ms | 394 ms |
| Qayta qo'llash (idempotent) | 10.4 ms | 12.1 ms | 12.5 ms |
| Rol qoidasi (bo'lim qoidalari bilan ustma-ust) | 12.2 ms | — | — |

- 50 qoida jami 62 500 kurs tayinlashini yaratdi.
- Takror (xodim × kurs, faol): **0**.
- Har bir apply = bitta set-based INSERT (N+1 yo'q).

## 7. Regressiya (007a + 007b qo'llangan holda)

| To'plam | Natija |
|---|---|
| 007a rollback | 27/27 |
| 006b | 34/34 |
| 006b rollback | 18/18 |
| 006a rollback | 21/21 |
| 005e | 146/146 |
| 005e rollback | 21/21 |
| 005d | 101 / 0 FAIL |
| 005 | 114 / 0 FAIL |
| 004 | 50 + 50 / 0 FAIL |
| Phase 1 | barchasi o'tdi |
| 005d_04 | 54 / 0 FAIL |
| Role matrix | 62 / 0 FAIL |
| 44 security | 54 / 0 FAIL |
| P01–P20 | o'zgarishsiz |

**Kutilgan sanoq invariantlari (regressiya emas):**
- 007a I05 "public jadvallar = 44" → 45 (`learning_path_assignments`);
- 006a J02 "policy soni = 006a'dan oldingi + 1" → +2 (`lpa_select_007b`).

Bu ikki test oldingi bosqich holatini qayd etadi; 007b'ning hujjatlashtirilgan qo'shimchasi bilan farq qiladi. 007b'siz ikkalasi ham PASS. Staging / production'ga chiqishda bu invariantlar 007b holatiga moslab yangilanadi.

## 8. Muhit

| | |
|---|---|
| Production writes | 0 |
| Production migrations | 0 |
| Production data changed | NO |
| Staging writes | 0 |
| Staging migrations | 0 |
| Staging data changed | NO |

**Git:** faqat admin branch (`backend/migration-007b/`, shu hisobot). `main` / Pages o'zgarmagan. 007c–007e boshlanmagan. Legacy import yo'q.
