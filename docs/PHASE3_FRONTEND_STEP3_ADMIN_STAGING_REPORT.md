# MedAcademy — Phase 3 Frontend Integration, STEP 3: Admin Panel STAGING + QA

Sana: 2026-11-28
Tasdiq: foydalanuvchi **"APPROVE STAGING"** (to'g'ridan-to'g'ri, chat orqali).
Holat: **STAGING SERVER QA COMPLETE**. Staging'da UI orqali login testi bajarilmadi (**USER LOGIN REQUIRED** — sababi 3-bo'limda).

Production'ga hech narsa yozilmadi. Production frontend deploy qilinmadi. `main` va GitHub Pages o'zgarmadi. Backend (migratsiya, sxema, RLS, funksiyalar) o'zgarmadi.

## 1. Pre-flight

| Band | Natija |
|---|---|
| Branch | `phase2-step3-005d-admin-local` |
| Tasdiqlangan commit zanjiri | `5116a8b → 9724c81` (STEP 2) |
| `main` | `f5ecf25` — o'zgarmagan |
| Diff qamrovi (STEP 2) | `admin-panel/**` va `docs/**` |

Diff'da xodim fayllari, Exam Engine fayllari va backend migratsiyalari yo'q.

## 2. Build

| Bundle | Hash | Izoh |
|---|---|---|
| `dist/live/index.html` (xodim ilovasi) | sha1 `e8dc98a4…` | deploydan oldin va keyin **o'zgarmagan** |
| `dist/admin-staging/admin.html` | sha1 `e6b5eee8…`, sha256 `f054a289…` | staging konfiguratsiyasi, staging publishable key |

Staging bundle tekshiruvi:
- Production URL'iga havola: 0.
- `sb_secret_`, service-role, `answer_key`, `correct_answer`, `"Q001"`: 0.
- Phase 3 modullari: 3/3.

## 3. Staging "deploy" va UI login

- MedAcademy'da staging frontend hosting yo'q: GitHub Pages faqat `main`'dan ishlaydi, `main`'ga merge esa production'ga chiqish demakdir.
- Shuning uchun staging Admin Panel staging backend'ga ulangan alohida build sifatida tayyorlandi: `admin-panel/staging/admin-staging.html`.
- Staging test akkauntlarida parol yo'q. Claude parol kiritmaydi va yaratmaydi.
- Shu sababli UI login testi **BLOCKED — USER LOGIN REQUIRED**. Bu Phase 2'dagi kabi.
- UI xatti-harakati lokal mock'da (haqiqiy 006a–007e RLS / trigger / RPC) 173/173 bilan tasdiqlangan.

## 4. Staging backend precheck (READ-ONLY)

Fayl: `step3_00_readonly_precheck.sql` (sha256 `9716bb08…`).

| Ko'rsatkich | Kutilgan | Staging | Holat |
|---|---|---|---|
| 007a–007e migratsiyalari | har biri 1 | har biri 1 | ✅ |
| Jadvallar | 49 | 49 | ✅ |
| Funksiyalar | 133 | 133 | ✅ |
| Triggerlar | 104 | 104 | ✅ |
| Policy'lar | 103 | 103 | ✅ |
| Indekslar | 122 | 122 | ✅ |
| CASCADE | 0 | 0 | ✅ |
| Anon execute | 1 (`verify_certificate`) | 1 | ✅ |

## 5. Staging server QA

Fayl: `step3_admin_staging_qa.sql` (sha256 `f5fd6144…`).

UI chaqiradigan RPC'lar aynan frontend argumentlari bilan chaqirildi. Har bir rol haqiqiy RLS / trigger / RPC orqali, JWT claim'lari bilan tekshirildi. Hammasi bitta tranzaksiyada bajarilib, oxirida ROLLBACK qilindi.

| Guruh | Natija | Tarkibi |
|---|---|---|
| Learning Paths | 13/13 | apply (UI argumentlari) → created; takroriy apply → existing, +0; reapply +0; cancel kurs tayinlashlarini saqlaydi; qayta cancel → changed=false; HR INSERT, Head, Employee, Instructor, Org B — rad |
| Course Progress | 5/5 | `assigned_count` = jadval; statuslar yig'indisi izchil; biriktirilmagan instructor → rad yoki instructor scope; Employee va anonim — rad |
| Skills / Requirements / Assessments | 18/18 | yaratish, tahrir, instructor rad; talab daraja 3; not_assessed → (2) not_achieved → (4) achieved; tarix insert-only (UPDATE/DELETE ta'sirsiz); Head boshqa bo'lim — rad; arxivlash; arxivlangan ko'nikmani baholash — rad; Org B ko'rmaydi |
| Compliance | 16/16 | EM tashkilot scope va xodimlar = server; bo'limlar yig'indisi = jami; bo'lim filtri rows = xodimlar; HR ko'radi; Head faqat o'z bo'limi (tashkilot va boshqa bo'lim, jumladan URL orqali urinish — rad); Instructor, MR, Employee — rad; trening va kompetensiya statuslari ruxsat etilgan to'plamda; Org B — rad |
| Notifications | 9/9 | apply'dan keyin o'qilmagan > 0; keyset paging kesishmaydi; mark read −1; boshqa foydalanuvchi o'zgartira olmaydi; qo'lda INSERT rad; mark all → 0; (recipient, event_key) dublikati 0; Org B ko'rmaydi |
| Anonim | 6/6 | 5 ta yangi RPC → rad; `verify_certificate` ishlaydi |
| Integrity | 1/1 | exam attempts, sertifikatlar va savollar md5 o'zgarmagan |
| **Jami** | **68/68 PASS** | |

Xuddi shu fayl lokal mock'da ham 68/68.

**Qoldiq tekshiruvi** (`step3_99_residue.sql`, READ-ONLY):
- STEP3 ko'nikma / qoida / talab / soxta bildirishnoma: 0.
- Notifications / course_assignments / skill_assessments / competency_requirements / learning_path_assignments: 0 / 0 / 0 / 0 / 0 (QA'dan oldingi holat bilan bir xil).
- audit_logs: 512 (o'zgarmagan).

## 6. Rollar matritsasi (server, staging)

| Rol | Natija |
|---|---|
| Super Admin | tashkilot scope — mavjud 109 suite + lokal UI'da PASS |
| Education Manager | ruxsat etilgan learning / skills / compliance — PASS |
| HR | trening / kompetensiya ko'rish — PASS; yozish (LPA INSERT) — rad |
| Department Head | faqat o'z bo'limi — PASS; tashkilot va boshqa bo'lim — rad |
| Instructor | skills ko'rish; yozish va compliance — rad |
| Medical Reviewer | compliance — rad |
| Employee | admin RPC'lar — rad |
| Org B (cross-org) | rad |
| Anonim | rad; `verify_certificate` ishlaydi |

## 7. UI QA (lokal, haqiqiy 007 backend bilan)

- Avtomatlashtirilgan testlar: 109 + 64 = 173/173.
- Responsive (8 ta Phase 3 sahifa, gorizontal overflow): 390px 8/8, 768px 8/8, 1280px 8/8.
- pageerror: 0.
- N+1: xodim sahifasi 2 RPC; bo'lim matritsasi ≤ 3 so'rov; learning paths ≤ 5 so'rov.
- Mavjud Admin Panel regressiyasi (auth, organization, employees, courses, questions, evidence, certificates, dashboard): 109/109.

## 8. Production xavfsizligi

Production READ-ONLY baseline: migratsiyalar 007a–007e har biri 1; 49 / 133 / 104 / 103 / 122; CASCADE 0; anon 1 — o'zgarmagan.

| Band | Holat |
|---|---|
| Production backend | UNCHANGED |
| Production frontend | NOT DEPLOYED |
| Employee build | UNCHANGED |
| main / Pages | UNCHANGED |

## 9. Ochiq band

Staging'da UI orqali login qabul testi. Uni foydalanuvchi o'zi bajaradi:
1. `admin-staging.html`'ni brauzerda ochadi.
2. Staging test akkauntiga o'zi parol beradi va login qiladi.

Production release faqat alohida **"RELEASE TO PRODUCTION"** / **"DEPLOY FRONTEND TO PRODUCTION"** tasdig'i bilan bo'ladi.
