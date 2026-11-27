# MedAcademy — Phase 3 STEP 10: Migration 007d (In-App Notifications)

**Holat:** PHASE 3 STEP 10 — 007d LOCAL + STAGING + PRODUCTION READ-ONLY REVIEW PASSED — READY FOR EXPLICIT PRODUCTION DEPLOYMENT APPROVAL
**Sana:** 2026-11-27 · **Production'ga hech narsa yozilmadi.** Production'da faqat READ ONLY tranzaksiya va anon REST o'qish so'rovlari bajarildi.

## 1. Sxema tekshiruvi va qarorlar

**Nima topildi.** Bildirishnoma jadvali va `notification.*` ruxsati yo'q edi. Legacy `docs.collection = 'notifications'` (JSON) mavjud, lekin u import qilinmaydi va unga tegilmaydi.

**Qabul qiluvchi.** Qabul qiluvchi — `profiles.id`, ya'ni `auth.uid()`. Xodim bilan bog'lanish `employees.profile_id` orqali. Akkaunti yo'q xodimga bildirishnoma yozilmaydi.

**Faqat in-app.** Email, Telegram, WhatsApp, SMS va push bu bosqichga kirmaydi.

**Bildirishnoma yaratish.** Yaratish faqat server tomonida, manba jadvallardagi SECURITY DEFINER trigger'lar orqali. Trigger'lar statement-level ishlaydi va `REFERENCING NEW/OLD TABLE` (transition tables) dan foydalanadi. Shuning uchun ishlov set-based, N+1 muammosi yo'q. 007a, 007b va 007c funksiyalari o'zgartirilmadi.

**Ruxsat.** Yangi ruxsat qo'shilmadi. O'z bildirishnomalarini ko'rish identifikatsiyaga bog'liq: `recipient_id = auth.uid()`. Super Admin ham faqat o'zinikini ko'radi. Administrator tomonidan ixtiyoriy bildirishnoma yaratish MVP'ga kiritilmadi.

**Audit.** Bildirishnomani yaratish ham, o'qish ham audit qilinmaydi. Manba hodisa allaqachon audit qilingan, shu bilan audit oqimi ortiqcha ko'paymaydi.

### Hodisalar (MVP)
| Tur | Manba | Dublikatni oldini olish kaliti (`event_key`) |
|---|---|---|
| `course_assigned` | `course_assignments` INSERT (status ≠ cancelled) | `course_assigned:<assignment_id>` |
| `course_completed` | `course_assignments` statusi `completed` ga o'tganda | `course_completed:<assignment_id>` |
| `learning_path_assigned` | `learning_path_assignments` INSERT. Shart: qoida active, yo'nalish published. Bildirishnoma 007b nishon qoidasiga mos xodimlarga boradi | `learning_path_assigned:<rule_id>` |
| `skill_assessment_created` | `skill_assessments` INSERT | `skill_assessment_created:<assessment_id>` |
| `competency_achieved` | Yangi baholash faol talab darajasini qoplaganda, agar oldingi so'nggi daraja talabdan past bo'lgan bo'lsa | `competency_achieved:<employee>:<skill>:<assessment_id>` |
| `certificate_issued` | `certificates` INSERT (revoked = false) | `certificate_issued:<certificate_id>` |

**Kiritilmagan hodisalar:**
- `course_due_soon` / `course_overdue` — rejalashtiruvchi (cron) kerak.
- `exam_result` — imtihon dvigateliga tegilmaydi; ball bildirishnomaga chiqmaydi.
- `competency_gap` — har bir baholashda takrorlanib, ortiqcha xabarlar oqimiga aylanadi. Bu holat `employee_competency_summary` orqali ko'rinadi.

### Jadval va RPC
- **`notifications` jadvali:**
  - Ustunlar: `org_id`, `recipient_id`, `notification_type`, `title`, `body`, `related_entity_type/id`, `metadata`, `event_key`, `created_at`, `read_at` — jami 12 ustun.
  - Cheklov: `unique (recipient_id, event_key)`.
  - Indekslar: `(recipient_id, created_at desc, id desc)`, `(recipient_id) where read_at is null`, `(org_id)`.
- **O'zgarmaslik:**
  - Faqat `read_at` o'zgaradi. Qolgan barcha maydonlarni guard trigger rad etadi; bu server darajasida ham amal qiladi.
  - DELETE va TRUNCATE rad etiladi. CASCADE yo'q.
- **Grant va RLS:**
  - `authenticated` uchun faqat SELECT grant beriladi. RLS sharti: `recipient_id = auth.uid()` va `org_id = my_org()`.
  - INSERT, UPDATE va DELETE grantlari yo'q, ularni faqat RPC va trigger'lar bajaradi.
- **RPC'lar** (faqat joriy foydalanuvchi uchun, anon uchun yopiq):
  - `my_notifications(p_limit = 20, p_before_created, p_before_id, p_unread_only)` — keyset sahifalash, eng ko'pi 100 ta.
  - `unread_notification_count()`.
  - `mark_notification_read(id, p_read = true)` — o'qildi va o'qilmadi holatlari o'rtasida almashtiradi, idempotent.
  - `mark_all_notifications_read()`.
- **Kontent:** faqat kurs, yo'nalish yoki ko'nikma nomi va daraja ko'rsatiladi. Ball, javob kaliti, baholovchi izohi va shaxsiy ma'lumotlar (PII) bildirishnomaga kirmaydi. `metadata` kalitlari oq ro'yxat bilan cheklangan.

## 2. Fayllar va SHA-256
| Fayl | SHA-256 |
|---|---|
| `migrations/007d_in_app_notifications.sql` = `production/103_apply_007d.sql` | `ad701284f61e2201b0796a1215184e4c91221801dbd51b22b95ce8c81ae49392` |
| `migrations/007d_rollback.sql` = `production/109_rollback_007d.sql` | `ccac09432261ab6f398bc3d818e25b4ce4059a033c21f00fb69b402268c0acb2` |
| `production/100_readonly_review_007d.sql` | `9379eb8315b0520ed51e38988b19a9dd020570eba322ae90345a85c50995a50a` |
| `production/101_backup_pre007d.sql` = `staging/007d_00_backup.sql` | `d79816a1349b735e1c981b52c93cf5d9dfad6aee38c840250a91b3eee0cf17a7` |
| `production/102_precheck_007d.sql` | `1ebec9c5732def860e4131b1b9c22192765154afed943396e9e7a619c79ed58b` |
| `production/104_verify_007d.sql` | `d4fb60c7ca18da916a2fb297fae090e3ca43878e1abb34dcd3ef2315458b83f2` |
| `production/105_security_tests_007d.sql` (tranzaksiya ichidagi vaqtinchalik @test.local muhit, ROLLBACK) | `6825f77602f56969cb7dbdc49d1ce6fb2da1b0c54c47560ef440fefbcf78080d` |
| `staging/007d_02_tests.sql` | `cf5d5ef47a4cf832023b3576dac8a65e7ee49d284ed7ee79c9d38085a81e3489` |
| `staging/007d_03_perf.sql` | `e9a2e28d6700b660607b28887f6576ffaf4ade501ba748f2a8f6074084b9fa7a` |
| `staging/007d_04_compare_pre.sql` | `af29bbb1aec39ce26a4e0eb1d253a7f3e93d89d72c7e366c43140fddbeeec65b` |

**Rollback:** faqat 007d obyektlarini olib tashlaydi. Bildirishnomalar avval `backup.notifications_rb007d` ga to'liq nusxalanadi. 007a, 007b va 007c ma'lumotlariga tegilmaydi.

## 3. LOCAL (PGlite)
| Tekshiruv | Natija |
|---|---|
| 007d test to'plami | **58 / 58 PASS**: Events 14, Idempotency 2, Read 9, Role matrix 1, Write 5, Immutability 3, Read status 8, Race 5, Content 4, Audit 1, Invariants 6 |
| Rollback / recovery | **28 / 28 PASS**: apply → rollback qilingan holat 007d'dan oldingisiga teng → reapply 2 marta → testlar 58/58 → qoldiq 0. Ma'lumot bilan rollback: bildirishnomalar backup'ga ko'chadi, course_assignments o'zgarmaydi |
| To'liq regressiya (`run_all_007d.sh`, T7A–T7D) | 007c 74/74 · 007c rb 26/26 · 007b 78/78 · 007b rb 25/25 · 007a 55/55 · 007a rb 27/27 · 006b 34/34 · 006b rb 18/18 · 006a 83/83 · 006a rb 21/21 · 005e 146/146 · 005e rb 21/21 · 005d 101/101 · 005 114/114 · 004 50/50 (standalone ham 50/50) · Phase 1 · 005d SQL 54/54 · role matrix 62/62 · P01–P20. **Natija: 0 FAIL** |
| Production simulyatsiyasi (staging test akkauntlarisiz) | 105: 58/58, qoldiq 0 · 85: 78/78 · 75: 55/55 · 65: 83/83 · 66: 34/34 · 95: 74/74 · 44: 54/54 · 55: 62/62 |

**Test invariantlari.** Jadval va policy sonini tekshiruvchi testlar 007d'ga moslashtirildi, 007d qo'llanganda ular +1 ni hisobga oladi. O'zgargan testlar: 006a J02, 007a I05, 007b V06, 007c V05 — staging va production variantlarida. Migratsiya SQL fayllari o'zgarmadi.

**Poyga (race) testi.** Bir xil hodisa + qabul qiluvchi uchun 20 ta takroriy urinish va bitta statement ichida 15 ta dublikat — ikkala holatda ham aynan 1 ta qator. `ON CONFLICT` siz takroriy INSERT unique cheklov bilan rad etiladi.
Kafolat `unique (recipient_id, event_key)` indeksidan keladi: Postgres bir vaqtdagi (concurrent) tranzaksiyalarda ham shu indeks orqali bitta qatorni ta'minlaydi. PGlite bitta ulanishda ishlaydi, shuning uchun haqiqiy parallel ulanishlar sinovi alohida o'tkazilmadi.

## 4. STAGING (`zwzxyikocqxbeyejeyga`)
| Qadam | Natija |
|---|---|
| Pre-baseline (READ ONLY) | 007c = 1, 007d = 0; 48 jadval / 116 funksiya / 97 trigger / 102 policy / 117 indeks; to'qnashuv yo'q; hashlar fn `a35223b6`, trg `f329c02c`, cols `f5f0eae5`, idx `3586745b`, policy `37c11f51`, grant `0d9a87ce` |
| Backup `*_pre007d` | 48 / 48 aynan, 1 616 qator |
| Apply (sha ad701284…) | OK |
| Verify | **ok = true**: 49 / 127 / 104 / 103 / 122. Yozuv, anon va policy grantlari 0. Unique cheklov bor. Ruxsatlar o'zgarmagan. internal→auth 0, kategoriyasiz funksiya 0, RPC 4/4 ishlaydi, CASCADE 0. 13 jadvaldagi ma'lumot o'zgarmagan (audit_logs ham). Katalog farqi: trg 7, idx 5, col 12, pol 1; +11 funksiya aniq ro'yxat bo'yicha |
| 007d testlari | **58 / 58** |
| Perf (106 000 bildirishnoma, 1 000 qabul qiluvchi, ROLLBACK) | p95: birinchi sahifa 0.3 ms · kursor sahifa 0.3 · faqat o'qilmaganlar 0.1 · unread son 0.3 · RLS SELECT 0.4 · mark read 1.6 · mark all 6.6 ms; dublikat 0 |
| Trigger yuklamasi | 007b apply, 4 bo'lim × ~250 xodim × 5 kurs: median 1 054 ms. Natija: 6 000 bildirishnoma (5 000 course_assigned + 1 000 learning_path_assigned). 007b'ning o'zida median 862 ms edi, demak qo'shimcha yuk ~20%. Reapply 268 ms, yangi bildirishnoma 0 |
| Rollback | `migration_007d=0`, jadval yo'q, funksiya qolmadi |
| Compare pre-007d | **barcha farqlar 0** |
| Reapply → verify → testlar | ok = true · 58 / 58 |
| Regressiya | 007c 74/74 · 007b 78/78 · 007a 55/55 · 006a 83/83 · 006b 34/34 · 005d 54/54 |
| Qoldiq | bildirishnomalar 0 |

## 5. PRODUCTION READ-ONLY REVIEW (`buuwjhpzptiiyggybvwr`)
Barcha so'rovlar `begin; set transaction read only; … rollback;` ichida bajarildi (`read_only = on`).

| Ko'rsatkich | Qiymat |
|---|---|
| Migratsiyalar | 001 … 007b, 007c; **007d = 0** |
| To'qnashuvlar | jadval yo'q / funksiya yo'q / `notification.*` ruxsati 0 |
| Katalog | 48 / 116 / 97 / 102 / 117; CASCADE 0 |
| Katalog hashlari | **staging pre-007d bilan 6/6 aynan mos — drift yo'q** |
| anon execute | faqat `verify_certificate` |
| Ma'lumot | courses 13, questions 131, exam_configs 13, attempts 2, certificates 0, profiles 1, employees 1, departments 10, audit_logs 315, course_assignments 0, lpa 0, skills 0, skill_assessments 0, competency_requirements 0 |
| Tashkilot / role_permissions | 1 / 119 |
| anon REST | `notifications` 404, `rpc/my_notifications` 404, `rpc/unread_notification_count` 404, `rpc/mark_all_notifications_read` 404 (obyektlar hali yo'q); `verify_certificate` 200 |

Precheck (102) production hashlariga bog'langan: fn `a35223b6…`, trg `f329c02c…`, cols `f5f0eae5…`, idx `3586745b…`, policy `37c11f51…`, grant `0d9a87ce…`.

## 6. Production deploy rejasi ("DEPLOY TO PRODUCTION" tasdig'idan keyin)
1. `101_backup_pre007d.sql`
2. `102_precheck_007d.sql` — `ok = true` bo'lishi shart.
3. `103_apply_007d.sql` (sha ad701284…)
4. `104_verify_007d.sql` — `ok = true`; kutilgan qiymatlar: 49 / 127 / 104 / 103 / 122.
5. `105_security_tests_007d.sql` — ROLLBACK bilan, 58/58.
6. Regressiya: 95 / 85 / 75 / 65 / 66 / 44 / 55 / 56.
7. anon REST tekshiruvi.

Muammo chiqsa, `109_rollback_007d.sql` alohida qaror bilan ishga tushiriladi.

## 7. Cheklovlar (o'zgarmagan)
- Main'ga merge qilinmadi, Pages deploy qilinmadi.
- Employee build o'zgarmagan.
- questions.js va javob banki public build'ga kirmagan.
- "Confirm email" sozlamasiga tegilmagan.
- Test yozuvlari qoldirilmagan.
