# Migration 007b — Learning Path Assignments

**Holat:** faqat LOKAL tekshirilgan. Staging va production'ga QO'LLANMAGAN.
**Oldingi shart:** `schema_migrations` da `007a` bo'lishi kerak.

## Fayllar

| Fayl | Vazifa | SHA-256 |
|---|---|---|
| `migration-007b.sql` | Migratsiya (bitta tranzaksiya, idempotent) | `36b2994eefa758a7db169ed3dab3d50ac9009c7b53043a0ab7ba7acada5f8553` |
| `rollback-007b.sql` | Faqat incident uchun bekor qilish | `1c4fbfc663c7a6017589468beabe5a466946b22c237047a3a644d8f1542f31f5` |
| `tests/007b_tests.sql` | 77 ta SQL test, oxirida ROLLBACK | |
| `tests/m007b_local.mjs` | Lokal test | |
| `tests/m007b_rollback_local.mjs` | Rollback / reapply tekshiruvi (25 ta) | |
| `tests/perf007b.mjs` | 1000 xodim × 50 yo'nalish yuklama testi | |
| `tests/run_all_007b.sh` / `.out` | To'liq regressiya | |

## Nima o'zgaradi

- **Jadval:** `learning_path_assignments`.
  - Har bir qoidada aniq bitta nishon bo'ladi: xodim, bo'lim, lavozim, mutaxassislik yoki rol.
  - Holat: `active` yoki `cancelled`. DELETE yo'q.
  - RLS faqat o'qishga ruxsat beradi; yozuv faqat RPC orqali.
- **RPC'lar:**
  - `apply_learning_path(path, target_type, target_id, due_date)`
  - `reapply_learning_path_assignment(id)`
  - `cancel_learning_path_assignment(id, reason)`
- **Ruxsat:** mavjud `learning_path.manage` (Super Admin va Education Manager). Boshqa rollar rad etiladi.

## Semantika

- Faqat `published` yo'nalish tayinlanadi.
- Faqat majburiy va `published` kurslar tayinlanadi.
- Faqat faol (`active`) va ta'tildagi (`on_leave`) xodimlar qamrab olinadi.
- Takror yo'q: xodim × kurs bo'yicha qator mavjud bo'lsa, yangisi yaratilmaydi.
- `completed` va `in_progress` tayinlashlar saqlanadi; `cancelled` tayinlash qayta yoqilmaydi.
- Qoidani bekor qilish yaratilgan kurs tayinlashlariga tegmaydi.

## Rollback

`rollback-007b.sql` faqat 007b obyektlarini olib tashlaydi.

`course_assignments` va audit yozuvlari saqlanadi.
