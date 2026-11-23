# MedAcademy — Migration 005d Production Report (Security Hardening)

**Holat: ✅ 005d PRODUCTION'DA.**
- Loyiha: `medacademy` (`buuwjhpzptiiyggybvwr`).
- Apply: 2026-11-23 15:11 UTC (20:11 Toshkent).
- Doira: **faqat 005d**. Admin Panel va 006a kirmagan; xodim ilovasi va GitHub Pages o'zgarmagan.

## A. Backup

| Band | Natija |
|---|---|
| Skript | `40_backup_pre005d.sql` — staging'da sinalgan backup skripti bilan bayt-ma-bayt bir xil (sha256 `cda75464…`) |
| Holat | **BACKUP COMPLETE**: 43/43 jadval nusxalandi, **43/43 md5 bo'yicha aynan**, mos kelmagan jadval yo'q |
| Ma'lumot | 1114 qator, `backup.*_pre005d_20261123`: profiles, docs, courses, questions, exam_configs, exam_attempts, certificates, attempt_resets, organizations, departments, positions, specialties, employees, barcha evidence va 005 jadvallari |
| Schema snapshot | Ustunlar, 286 constraint (FK'lar bilan), indekslar |
| Security snapshot | 97 RLS policy; 69 funksiya (ta'rif + anon/auth EXECUTE); 75 trigger; anon/authenticated jadval grant'lari; 6 default-ACL qatori. Bundan tashqari migratsiyaning o'z rollback snapshot'i: `backup.security_pre005d` |

## B. Deployment

| Band | Qiymat |
|---|---|
| Migratsiya fayli | `005d_security_hardening.sql` (production nusxasi: `42_apply_005d.sql`) |
| sha256 | `b3e93884784ad79fe820f2a7dbd10ee3c7c2edc9c927fe762194d9b0ac3c1f57`, 16 649 bayt |
| Moslik tekshiruvi | Lokal fayl = GitHub `4116384` (staging'da PASS bo'lgan commit) = SQL Editor'ga yuklangan matn (brauzerda sha256 hisoblangan) — **bayt-ma-bayt bir xil**. Production uchun qo'shimcha SQL yozilmadi |
| Precheck (`41_precheck_005d.sql`, faqat SELECT) | Barcha 13 band `true`: courses 13, questions 131, exam_configs 13, exam_attempts 2, certificates 0, docs = backup (22), anon 58, target CASCADE 6, policy 97, funksiya 69, inactive/deactivated 0, 005d qo'llanmagan, backup 43. Verify: `ORIGINAL`, barcha diff 0 |
| Apply | **OK**, bitta tranzaksiya. Natija: CASCADE 0, RESTRICT 6, anon 1 (`verify_certificate`) |
| Timestamp | 2026-11-23T15:11:4x Z |

## C. Security

| Ko'rsatkich | Oldin | Keyin |
|---|---|---|
| Target CASCADE FK (profiles, docs, exam_attempts, certificates, exam_configs, attempt_resets) | 6 | **0** |
| Target RESTRICT | 0 | **6/6** |
| public'dagi jami CASCADE | 6 | 0 |
| anon EXECUTE funksiyalar | 58 | **1** (`verify_certificate`) |
| Funksiyalar | 69 | 72 (+`set_employee_status`, +2 guard). Oldingi 69 tadan **bittasi ham o'chmagan** |
| RLS | 97 policy | 97 policy, **policy_diff = 0**; RLS'siz jadval yo'q |
| authenticated → ichki/trigger funksiyalar | 10 + trigger'lar | **0** |
| Tasniflanmagan funksiya | 0 | 0 |
| Kerakli ilova RPC'lari (authenticated) | bor | bor (`auth_missing_required = "-"`) |
| Trigger'lar | — | `certificates_history_guard_trg` (UPDATE/DELETE), `exam_attempts_history_guard_trg` (UPDATE/DELETE) |
| `set_employee_status` guard'lari | — | reason, self, HR→SA, reactivate faqat SA, org, oxirgi SA, audit — **hammasi bor** |

**Production'da jonli anon tekshiruvi** (faqat publishable key, sessiyasiz):
- `verify_certificate` → 200 (mavjud bo'lmagan kod uchun `null`);
- `_q_full`, `_q_refs`, `question_meta`, `start_exam`, `set_employee_status`, `revoke_certificate` → **401 permission denied**;
- REST `questions`, `employees`, `evidence_sources`, `exam_attempts`, `profiles` → **401**.

**`verify_certificate` maydonlari:** id, name, courseTitle, position, department, issuedAt, expiresAt, status. Email, ball, javob, evidence, izoh yoki ichki tashkilot ma'lumoti yo'q.

## D. Data integrity

| Jadval | Oldin | Keyin |
|---|---|---|
| profiles | 1 | 1 |
| courses | 13 | 13 |
| questions | 131 | 131 |
| exam_configs | 13 | 13 |
| exam_attempts | 2 | 2 |
| certificates | 0 | 0 |
| attempt_resets | 0 | 0 |
| employees | 1 | 1 |
| audit_logs | 305 | 305 |
| docs | 22 | 23 (pastga qarang) |

- Verify: `data_tables_changed = 0` — apply'dan keyin barcha 43 jadval backup bilan md5 bo'yicha aynan.
- **Tarixiy urinishlar:** 2 ta urinish backup bilan aynan (`attempts_vs_backup = true`).
- Initial assessment tahlili (`get_attempt_review`) ishlaydi: 10 savol.
- **Sertifikat:** production'da 0 ta. O'zgarmaslik trigger'i o'rnatilgan va testlarda sinalgan (E-bo'lim). Avtomatik "Anonimlashtirilgan" yo'q.
- **docs 22 → 23:** bitta yangi yozuv `audit` / `Asfmdi8qoq1ui` (`action: "login"`, Abdulaziz, 15:14:54 UTC). Bu xodim ilovasining o'z faollik yozuvi: live smoke uchun ilova ochilganda yaratilgan. **Test ma'lumoti emas**; production'ga yozish taqiqlangani uchun o'chirilmadi.

## E. Regression

| Suite | Qayerda | Natija |
|---|---|---|
| **005d xavfsizlik testlari** (`44_security_tests_005d.sql`) | **Production**, bitta tranzaksiya, `ROLLBACK` | **54/54 PASS** |
| **005 regressiyasi** (`45_regression_005_after_005d.sql`; Phase 1 + 004 + 005 asosiy oqimlari, X01–X26) | **Production**, `ROLLBACK` | **26/26 PASS** |
| 005 to'liq suite | Prod bilan bir xil zanjir (lokal) + 005d | **114/114 PASS** |
| 004 to'liq suite | xuddi shunday | **50/50 PASS** |
| Phase 1 SQL suite | xuddi shunday | **32/32 PASS** |
| 005d to'liq lokal suite | xuddi shunday | **101/101 PASS** |

**005d testlari qamrovi (production, ROLLBACK):**
- struktura;
- RESTRICT: super admin auth user'i, xodim, exam config'li kurs — o'chirish rad etiladi;
- anon va xodim → 9 ta ichki funksiya DENIED; anon → 8 ta RPC `permission denied`;
- vaqtinchalik xodim bilan imtihon oqimi: start → save → submit → 100% → sertifikat;
- payload'da javob yo'q; xodim savollar, versiyalar, review'lar va evidence'ni ko'rmaydi;
- anon QR tekshiruvi ishlaydi;
- Org B → Org A: 0 / DENIED;
- sertifikat va urinish o'zgarmas, DELETE rad etiladi;
- savol yangilangandan keyin urinish aynan, tahlil v1 savolini ko'rsatadi;
- lifecycle: xodim/department head/sababsiz/o'zi/HR→SA/cross-org → DENIED; HR deactivate + audit; deactivated → `my_role` null va imtihon DENIED; sertifikat va QR o'zgarishsiz;
- revoke qaytarilmaydi; HR deactivated'ni tiklay olmaydi; SA tiklaydi.

**Toza holat (yakuniy):**
- test markerlari **0**: test emaillari, TRM/PERF savollari, test manbalari, Org B, sertifikatlar, kutilmagan urinishlar;
- `auth.users` = 1;
- organizations = 1;
- evidence_sources = 0;
- question_reviews = 0;
- 2 soat ichida `audit_logs`'ga yangi yozuv yo'q.

## F. Application (live smoke — xodim ilovasi, mavjud sessiya; logout qilinmadi)

| Sahifa | Natija |
|---|---|
| Login (mavjud sessiya), Store `live` rejimi | ✅. `loadAll` xatosiz: profiles, docs, exam_attempts, certificates, exam_configs, attempt_resets, `question_meta` RPC |
| Dashboard | ✅ "Admin Dashboard" |
| Profile | ✅ |
| Courses / kurs sahifasi (ETHICS) | ✅ |
| Question Bank (Super Admin) | ✅ "Savollar banki" (131 savol, kurs bo'yicha) |
| My Exams / History | ✅ Initial attempt ro'yxatda ko'rinmaydi (dizayn bo'yicha); ETHICS urinishi preview bo'lgani uchun "Hali imtihon topshirilmagan" |
| Initial assessment natijasi | ✅ Results sahifasi: 85.7% / Advanced, soha bo'yicha; `get_attempt_review` (initial) → 10 savol |
| Certificates | ✅ "Hali sertifikat yo'q" (0 — kutilgan) |
| Exams-admin, Certs-admin, Employees, Departments, Analytics, Skills, Notifications | ✅ |
| Console xatolari / JS exception | **0** |
| Ruxsat xatolari / bo'sh sahifa | Yo'q |

## G. Git

`main`'ga faqat 005d production holati commit qilindi: `feat: deploy migration 005d security hardening`. Hash yakuniy xabarda.

Fayllar: `backend/migration-005d/`:
- `005d_security_hardening.sql` (sha256 `b3e93884…`), `005d_rollback.sql`;
- `40_backup_pre005d.sql`, `41_precheck_005d.sql`, `43_verify_005d.sql`, `44_security_tests_005d.sql`, `45_regression_005_after_005d.sql`, `49_rollback_005d.sql`, `005d_07_readiness_audit.sql`;
- `MIGRATION_005D_PRODUCTION_REPORT.md`.

**Kiritilmagan:** Admin Panel, 006a, test harness'lar, parol, maxfiy kalit, javob kaliti. Admin Panel alohida branch'da qoladi (`phase2-step3-005d-admin-local`).

## H. Admin Panel

**NOT DEPLOYED.**

Ochiq blockerlar:
1. Staging'da real UI login testi;
2. EM medical review qila olmasligi kerak;
3. Instruktorning chalg'ituvchi "medical" yozuvi;
4. Audit bo'shliqlari;
5. `docs` / `exam_configs` DELETE'ni cheklash.

## I. 006a

**NOT CREATED.** Kelajakdagi taklif (SQL yo'q), "006a Audit Hardening":
- question publish auditi;
- course status auditi;
- certificate revoke auditi;
- profile rol/holat auditi;
- attempt reset auditi;
- server-side audit `metadata`;
- sezgir maydonlarni maskalash (answer, explanation, options).

## Qayd etilgan siyosat: Medical Review (keyingi Admin Panel uchun)

| Medical Review qila oladi | Qila olmaydi |
|---|---|
| `medical_reviewer`, `super_admin` | HR, Education Manager, Instructor, Department Head, Employee |

- Instructor review ≠ Medical Review.
- Education approval ≠ Medical Review.
- Hozirgi server (005c) EM'ga ham ruxsat beradi, instruktorga esa "medical" yozuvini yaratishga yo'l qo'yadi. Publish gate instruktor yozuvini hisobga olmaydi.
- Bularni moslashtirish keyingi alohida migratsiyada tasdiq bilan bajariladi.

**Rollback** (faqat incident bo'lsa): `49_rollback_005d.sql`.
- Non-destructive, snapshot'dan aynan tiklaydi.
- Staging'da sinalgan: acl/constraint/policy/data diff = 0.
- Inactive/deactivated akkaunt bo'lsa o'zini to'xtatadi.

**TO'XTADIM.**
