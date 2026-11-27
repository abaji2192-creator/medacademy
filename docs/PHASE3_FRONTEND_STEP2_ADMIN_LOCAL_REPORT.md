# MedAcademy — Phase 3 Frontend Integration, STEP 2: Admin Panel (LOCAL)

Sana: 2026-11-28 · Holat: **LOCAL COMPLETE — staging tasdig'ini kutmoqda**

Bu bosqichda faqat Admin Panel 007a–007e backend imkoniyatlariga ulandi. Staging va production'ga deploy **qilinmadi**. `main`, GitHub Pages va xodim (employee) build'iga tegilmadi. Backend migratsiyalari (007a–007e) o'zgartirilmadi.

## 1. Qo'shilgan modullar

| Fayl | Qatorlar | Tarkibi |
|---|---|---|
| `js/admin/pages_learning.js` | 139 | Learning Paths ro'yxati va tafsiloti (apply / reapply / cancel — faqat RPC), Course Progress (`course_progress_summary`) |
| `js/admin/pages_skills.js` | 121 | Skills (upsert / archive), Competency Requirements (set / archive), Skill Assessments (insert-only tarix + baholash) |
| `js/admin/pages_compliance.js` | 146 | Bo'lim / tashkilot matritsasi (`department_compliance_matrix`), xodim bo'yicha trening compliance va kompetensiya matritsasi, Notifications (bell, ro'yxat, keyset paging, mark read / mark all) |

Shell o'zgarishlari:
- `main.js`: yangi NAV guruhi "O'quv rivojlanish" (4 havola) va yuqori paneldagi 🔔 bildirishnoma qo'ng'irog'i (o'qilmaganlar soni).
- `perms.js`: `learning_paths`, `progress`, `skills`, `compliance`, `notifications` bo'limlari. Ular faqat UX uchun; haqiqiy himoya serverda (RLS + RPC).
- `admin.html`: 3 ta yangi script tegi (`pages_edu.js`dan keyin).
- `admin.css`: Phase 3 badge / KPI / progress bar uslublari va mobil yuqori panel tuzatishi.

## 2. Asosiy qoidalar (amalda)

- **Barcha yozish amallari faqat RPC orqali.** UI jadvallarga to'g'ridan-to'g'ri INSERT/UPDATE qilmaydi.
- **Hisob-kitob faqat serverda.** Foizlar, statuslar va o'rtacha progress backend qaytargan qiymatdan olinadi; frontend o'zi hisoblamaydi.
- **Kompetensiya statusi** faqat `achieved` / `not_achieved` / `not_assessed`. Hech qanday "ball" o'ylab topilmaydi.
- **Baholash tarixi insert-only.** UI'da tahrirlash yoki o'chirish tugmasi yo'q; server PATCH'ni ham rad etadi.
- **Department Head** faqat o'z bo'limini ko'radi: bo'lim filtri qulflangan, server boshqa bo'limni rad etadi.
- **N+1 yo'q:** nomlar lookup keshidan yoki bitta `in (...)` so'rovidan olinadi; xodim sahifasi = 2 RPC.
- **Holatlar:** loading skeleton, empty state, server xatosida tushunarli xabar + "Qayta urinish".

## 3. Test natijalari (mini-Supabase, PGlite, WITH007=1: 006a, 006b, 007a–007e)

| Suite | Testlar | FAIL |
|---|---|---|
| Mavjud Admin Panel suite (`admin_tests.py`) | 109 | 0 |
| Yangi Phase 3 suite (`admin_tests_p3.py`) | 64 | 0 |
| **Jami** | **173** | **0** |

Phase 3 qamrovi:

| Guruh | Soni |
|---|---|
| Bundle | 3 |
| Roles | 7 |
| Learning | 9 |
| Progress | 4 |
| Skills | 11 |
| Compliance | 7 |
| Notifications | 9 |
| Isolation (cross-org / anonim) | 8 |
| UI | 6 |

Muhim tekshiruvlar:
- Takroriy tayinlash va qayta qo'llash dublikat yaratmaydi.
- Qoidani bekor qilish mavjud kurs tayinlashlarini saqlaydi.
- KPI qiymatlari server RPC bilan teng.
- not_assessed → not_achieved → achieved o'tishi.
- Keyset paging dublikatsiz.
- Boshqa foydalanuvchi bildirishnomasini o'zgartirib bo'lmaydi.
- Org B → Org A rad etiladi.
- Server xatosidan "Qayta urinish" bilan tiklanadi.
- Mobil (390px) gorizontal overflow yo'q.
- pageerror 0.

Mock o'zgarishlari:
- `WITH007` zanjiri qo'shildi.
- Set-returning RPC'lar (`my_notifications`) PostgREST kabi JSON massiv qaytaradi.

## 4. Build va xavfsizlik

| Bundle | sha1 | Holat |
|---|---|---|
| `dist/live/index.html` (xodim) | `e8dc98a4…` | **o'zgarmagan** (production bilan teng) |
| `dist/admin-local/admin.html` | `66bf6a38…` | yangi |
| `dist/admin/admin.html` | `f6eb24d5…` | yangi, deploy qilinmagan |

- Xodim `site/js` va `css/app.css` o'zgarmagan.
- Bundle'da service-role yoki secret kalit qiymati yo'q.
- `questions.js` / javob banki public build'ga kirmagan.

## 5. Production backend READ-ONLY smoke

Fayl: `production/121_readonly_admin_step2_smoke.sql` (sha256 `2d11575f…`, `set transaction read only` … `rollback`). Hech qanday yozish bajarilmadi.

| Tekshiruv | Natija |
|---|---|
| UI chaqiradigan RPC'lar | 16/16 mavjud, hammasi SECURITY DEFINER |
| `authenticated` execute | hammasida bor |
| `anon` execute | 0 |
| Jadvallarda RLS o'chiq | 0 |
| Anon select | 0 |
| Oxirgi migratsiya | `007e` |
| Production obyektlari | 49 jadval / 133 funksiya / 103 policy (kutilganidek) |

## 6. Ma'lum cheklovlar

- Notification bell faqat sahifa yuklanganda va amallardan keyin yangilanadi (realtime yo'q — 007d dizayni bo'yicha).
- Learning path va ko'nikma tanlash dialoglari kichik ro'yxatlar uchun mo'ljallangan (select). Katta tashkilotda qidiruvli tanlovga o'tkazish keyingi bosqich uchun tavsiya etiladi.

## 7. Keyingi qadam

STEP 3 — staging admin. Bu bosqich faqat foydalanuvchining aniq **"APPROVE STAGING"** tasdig'idan keyin boshlanadi.
