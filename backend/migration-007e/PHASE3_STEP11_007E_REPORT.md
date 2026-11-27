# MedAcademy — Phase 3 STEP 11: Migration 007e (Training Compliance + Competency Matrix)

**Holat:** PHASE 3 STEP 11 — 007e LOCAL + STAGING + PRODUCTION READ-ONLY REVIEW PASSED — READY FOR EXPLICIT PRODUCTION DEPLOYMENT APPROVAL
**Sana:** 2026-11-27.

Production'ga hech narsa yozilmadi. Production'da faqat READ ONLY tranzaksiya va anon REST orqali o'qish so'rovlari bajarildi.

## 1. Old shartlar va sxema tekshiruvi
Production holati:
- Migratsiyalar 007a … 007d qo'llangan (har biri = 1), 007e = 0.
- Katalog: 49 jadval / 127 funksiya / 104 trigger / 103 policy / 122 indeks.
- CASCADE 0. Anon faqat `verify_certificate` ni ishga tushira oladi.

Compliance yoki matrix obyekti hali mavjud emas, nom, funksiya va ruxsat bo'yicha to'qnashuv yo'q. Legacy docs JSON (progress, skills, notifications) import qilinmaydi va unga tegilmaydi.

## 2. Arxitektura
007e faqat o'qish va hisobot qatlami: yangi jadval, view, trigger, indeks, permission yoki rol qo'shilmaydi. U mavjud jadvallar ustida hisoblaydigan 3 ta RPC va 3 ta ichki funksiyadan iborat. Barcha 6 funksiya `STABLE`, `SECURITY DEFINER` va `search_path = public` bilan yozilgan, dinamik SQL ishlatilmaydi.

| Obyekt | Turi | Vazifasi |
|---|---|---|
| `_cmp_training_007e(org, uuid[])` | internal | Ko'p xodim uchun bir vaqtda (set-based) kurs holati. Formula 007a bilan bir xil: `_lp_status_007a` va majburiy published darslar. lesson_progress bitta skan bilan o'qiladi |
| `_cmp_can_view_training_007e(emp)` | internal | Trening ma'lumotini kim ko'ra olishini tekshiradi |
| `_cmp_emp_json_007e(emp)` | internal | Xodim maydonlari: ism, kod, bo'lim, lavozim, mutaxassislik, rol, holat |
| `employee_training_compliance(p_employee = null)` | role_rpc | Bitta xodimning compliance summary'si + kurslar ro'yxati (`null` = o'zi) |
| `employee_competency_matrix(p_employee = null)` | role_rpc | Bitta xodimning kompetensiya summary'si + har skill bo'yicha talab manbalari |
| `department_compliance_matrix(p_department = null)` | role_rpc | Bo'lim: har xodim bo'yicha qator. `null` bo'lsa butun tashkilot: bo'limlar bo'yicha agregat |

**Qayta ishlatilgan mavjud obyektlar:**
- 007a: `_lp_status_007a` — kurs holatini aniqlash formulasi.
- 007c: `_sk_emp_competency_007c` — kompetensiya semantikasi.
- 007c: `_sk_can_view_employee_007c` — kompetensiya ma'lumotini ko'rish qamrovi.
- Umumiy yordamchilar: `my_org`, `my_role`, `has_perm`, `my_employee_id`, `my_department_id`.

**Snapshot jadval kerak emas.** 1 000 xodimli butun tashkilot uchun hisob staging'da p95 330 ms (maqsad < 500 ms). Shuning uchun natijalarni oldindan saqlab qo'yadigan (materialized) jadval qo'shilmadi.

## 3. Compliance semantikasi
**Kurs holati** 007a bilan bir xil hisoblanadi:
- `cancelled`
- `completed` — tayinlash completed bo'lsa yoki barcha majburiy published darslar tugallangan bo'lsa
- `overdue` — `due_date < bugun`; `due_date` NULL bo'lsa hech qachon overdue bo'lmaydi
- `in_progress` — progress bor yoki `started_at` belgilangan
- `not_started`

Optional, draft dars va draft modul maxrajga kirmaydi. Yakuniy imtihon kurs tugallanishining qismi emas. Kurs tugallanishi sertifikatlash degani emas.

**Hisob qoidalari:**
- `total_required` — bekor qilinmagan tayinlashlar soni. `cancelled` alohida sanaladi va maxrajga kirmaydi.
- `compliance_percent = round(100 × completed / total_required, 1)`. Agar `total_required = 0` bo'lsa, natija 0.0.

**Learning path.** 007b yaratgan `course_assignments` hisobga olinadi. 007e learning path'ni qayta apply qilmaydi va tayinlash yaratmaydi.

## 4. Kompetensiya matritsasi semantikasi
Matritsa 007c bilan bir xil hisoblanadi:
- Har skill bo'yicha bitta qator chiqadi, dublikat bo'lmaydi.
- Bir xodimga bir nechta faol talab mos kelishi mumkin (bo'lim, lavozim, mutaxassislik va rol bo'yicha). Shunda `required_level` = ular ichidagi eng yuqorisi. Barcha manbalar `requirements` ro'yxatida beriladi: requirement_id, target_type, target_id, required_level.
- Rol bo'yicha talab faqat profil faol bo'lsa hisobga olinadi. Arxivlangan skill matritsaga chiqmaydi.
- `current_level` = eng so'nggi baholash (`assessed_at desc`, `assessment_seq desc`).
- Status: `achieved`, `not_achieved` (ya'ni gap) yoki `not_assessed`.
- Umumiy kompetensiya balli yoki og'irlikli KPI yo'q. Gap holati uchun bildirishnoma yaratilmaydi.

## 5. Ruxsat va qamrov matritsasi
Faqat mavjud ruxsatlar ishlatiladi: `progress.view` va `skill.view`. Yangi permission qo'shilmadi.

| Rol | Trening (xodim) | Kompetensiya (xodim) | Bo'lim / tashkilot matritsasi |
|---|---|---|---|
| Xodim | faqat o'zi | faqat o'zi | rad |
| Department Head | o'zi + o'z bo'limi | o'zi + o'z bo'limi | faqat o'z bo'limi |
| HR | tashkilot | tashkilot | tashkilot (bo'lim / jami) |
| Education Manager | tashkilot | tashkilot | tashkilot |
| Super Admin | tashkilot | tashkilot | tashkilot |
| Instructor | faqat o'zi | faqat o'zi | rad |
| Medical Reviewer | faqat o'zi | faqat o'zi | rad |
| Boshqa tashkilot | rad | rad | rad |
| Anonim | EXECUTE yo'q | EXECUTE yo'q | EXECUTE yo'q |

Mijoz `employee_id` yuborishi o'z-o'zidan ruxsat bermaydi — qamrov server tomonida tekshiriladi. Mavjud bo'lmagan ID ham rad etiladi va ma'lumot oshkor qilinmaydi.

**Yon ta'sirlar yo'q.** RPC'lar bildirishnoma, audit yozuvi, tayinlash, baholash, talab yoki yo'nalish yaratmaydi. Bu test bilan tekshirildi.

**Javobda maxfiy maydonlar yo'q:** javob kaliti, ball, baholovchi izohi, `assessor_id`, parol yoki token qaytarilmaydi.

## 6. Fayllar va SHA-256
| Fayl | SHA-256 |
|---|---|
| `migrations/007e_compliance_matrix.sql` = `production/113_apply_007e.sql` | `fd6ffc51dd239a1fd0c1be7a228f0045917d3ed0e87bcb2279bc1aa62e7d0428` |
| `migrations/007e_rollback.sql` = `production/119_rollback_007e.sql` | `0294adcddc7b7ad4ad1192d80b69cbd53484e920b6831b5124c0b2e43919b3f7` |
| `production/110_readonly_review_007e.sql` | `101b14678a4a7f7a561532ff1fcb139370426b3c12bcd695cf5a28144a6dcab5` |
| `production/111_backup_pre007e.sql` = `staging/007e_00_backup.sql` | `98404ffe04da55146287e49923cd81a5059e9832ab54d6a35e69a28ac848b92b` |
| `production/112_precheck_007e.sql` | `88cc205dbb60bb3c6f8592caf6210f213db87b89f2ea9fe69690d4c58d99049b` |
| `production/114_verify_007e.sql` | `343a62591272807c7ee5b5d5a228d077fd6429da348ed0c41470766486d5547a` |
| `production/115_security_tests_007e.sql` (vaqtinchalik @test.local, ROLLBACK) | `38c5a2a4e5e6b90771f09930f345e4dac6d712d67b67f48716e6272684547f87` |
| `staging/007e_02_tests.sql` | `e69b63fd44a6835844fa5af31ae2a3e0f69503a2b81c73adf07169a1472fa7d6` |
| `staging/007e_03_perf.sql` | `b62b5d85d65a1a379cf4a296ee4c786b5eb6753191cf057964cb0e02cce0b72e` |
| `staging/007e_04_compare_pre.sql` | `8bb25f429abf4fb5facdf592727355b55cb1553137422135f3d2d461946b4af3` |

Rollback faqat 6 funksiyani olib tashlaydi. 007e ma'lumot saqlamaydi, shuning uchun hech bir ma'lumot o'zgarmaydi.

## 7. LOCAL natijalari
**007e = 48/48 PASS.** Testlar guruhlar bo'yicha:

| Guruh | Natija | Nimani tekshiradi |
|---|---|---|
| Training | 12/12 | Tayinlashsiz xodim; faqat optional darsli kurs; 0 majburiy dars; bekor qilingan; overdue; kelajak muddat; NULL muddat; draft dars va modul; ixtiyoriy dars; arxivlangan kurs; tugallangan; 0% va 100% oralig'i |
| Parity 007a | 2/2 | Natija `my_learning_progress` va `course_progress_summary` bilan aynan bir xil |
| Learning path | 2/2 | Apply, reapply va takroriy apply'da dublikat yo'q |
| Competency | 7/7 | Talab yo'q; baholash yo'q; bir skill ikki nishon orqali → bitta qator, max talab; so'nggi baholash pastroq bo'lsa gap; arxivlangan skill; mos kelmagan mutaxassislik; izoh yo'q |
| Parity 007c | 1/1 | Natija `employee_competency_summary` bilan aynan bir xil |
| Scope | 11/11 | Xodim A → B; Head boshqa bo'lim; HR, EM, SA boshqa tashkilot; Instructor va MR; Org B admin; anonim; mavjud bo'lmagan ID; bo'lim va lavozim almashsa qamrov va talab ham almashadi |
| Department | 7/7 | — |
| Side effects | 1/1 | — |
| Invariants | 5/5 | — |

**Boshqa lokal natijalar:**
- Rollback / recovery: **27/27 PASS**. Rollback dan keyin holat 007e'dan oldingisi bilan aynan bir xil, funksiyalar soni ham. Reapply ikki marta bajarildi, testlar 48/48, ikkinchi rollback → reapply.
- Reapply: **48/48 PASS**, ikki marta.
- To'liq regressiya (`run_all_007e.sh`, T7A–T7E): **0 FAIL**.

| To'plam | Natija |
|---|---|
| 007e | 48/48 |
| 007d | 58/58 |
| 007c | 74/74 · rollback 26 |
| 007b | 78/78 · rollback 25 |
| 007a | 55/55 · rollback 27 |
| 006b | 34/34 · rollback 18 |
| 006a | 83/83 · rollback 21 |
| 005e | 146/146 · rollback 21 |
| 005d | 101/101 |
| 005 | 114/114 |
| 004 | 50/50 (standalone ham 50/50) |
| Phase 1 | PASS |
| 005d SQL | 54/54 |
| Role matrix | 62/62 |
| P01–P20 | PASS |

- Production simulyatsiyasi (staging test akkauntlarisiz): 115 → 48/48, qoldiq 0. Verify `ok`. Rollback → compare: farq 0.

**Perf** — 1 011 xodim, 50 bo'lim, 100 lavozim, 50 mutaxassislik, 20 020 tayinlash, 110 110 lesson_progress, 500 ko'nikma, 300 talab, 10 000 baholash. Natijalar (p95):
- Xodimning trening holati: 3–5 ms
- Xodimning kompetensiyasi: 2–6 ms
- Bo'lim matritsasi: 7–8 ms
- Tashkilot (1 000 xodim): 289 ms

Optimallashtirish: dastlab lesson_progress ikki marta skanerlanardi va tashkilot p95 419 ms edi. Ikki skan bitta agregatsiyaga birlashtirildi — natija 289 ms.

## 8. STAGING (`zwzxyikocqxbeyejeyga`)
| Qadam | Natija |
|---|---|
| Pre-baseline (READ ONLY) | 007d = 1, 007e = 0; 49 / 127 / 104 / 103 / 122. Hashlar: fn `88602bc9`, trg `a01a0b7e`, cols `110933cd`, idx `21abaac8`, policy `4f61b5a9`, grant `bcdd6b57` |
| Backup `*_pre007e` | 49 / 49 jadval aynan, 1 617 qator |
| Apply (sha fd6ffc51…) | 6 funksiya qo'shildi; anon faqat `verify_certificate` |
| Verify | **ok = true**. Katalog: 49 / 133 / 104 / 103 / 122. 3 ta RPC ishlaydi, 6 funksiyaning hammasi STABLE + DEFINER + search_path. internal→auth 0, kategoriyasiz funksiya 0, CASCADE 0. 14 jadvaldagi ma'lumot o'zgarmagan (notifications va audit_logs ham). Katalog farqi: +6 funksiya (aniq ro'yxat bo'yicha), trigger, indeks, ustun va policy farqi 0. Ruxsatlar o'zgarmagan |
| 007e testlari | **48 / 48** |
| Perf (ROLLBACK) | p95: o'z treningi 4.7 ms · o'z kompetensiyasi 4.0 · EM → xodim treningi 5.2 · EM → xodim kompetensiyasi 3.8 · Head → xodim 5.2 · Head bo'lim matritsasi 13.3 · EM bo'lim matritsasi 11.7 · tashkilot (1 000 xodim) 330 ms. Barcha maqsadlar bajarildi |
| Rollback | `migration_007e = 0`, funksiya qolmadi |
| Compare pre-007e | **barcha farqlar 0** |
| Reapply → verify → testlar | ok = true · 48 / 48 |
| Regressiya | 007d 58/58 · 007c 74/74 · 007b 78/78 · 007a 55/55 · 006a 83/83 · 006b 34/34 · 005d 54/54 |
| Yakuniy verify | ok, ma'lumot o'zgarmagan, qoldiq 0 |

## 9. PRODUCTION READ-ONLY REVIEW (`buuwjhpzptiiyggybvwr`)
Barcha so'rovlar `read_only = on` rejimida bajarildi. Production'ga yozish = 0.

| Ko'rsatkich | Qiymat |
|---|---|
| Migratsiyalar | 001 … 007c, 007d; **007e = 0** |
| To'qnashuvlar | yo'q / yo'q / 0 |
| Katalog | 49 / 127 / 104 / 103 / 122; CASCADE 0 |
| Katalog hashlari | **staging pre-007e bilan 6/6 aynan mos — drift yo'q** |
| anon execute | faqat `verify_certificate` |
| Ma'lumot | organizations 1, profiles 1, employees 1, departments 10, courses 13, lessons 47, questions 131, exam_configs 13, attempts 2, certificates 0, audit_logs 315, learning_paths 9, lpa 0, course_assignments 0, lesson_progress 0, skills 0, skill_assessments 0, competency_requirements 0, notifications 0; role_permissions 119 |
| anon REST | 3 ta yangi RPC → 404 (hali yo'q); `verify_certificate` → 200 |

Precheck (112) production hashlariga bog'langan: fn `88602bc9…`, trg `a01a0b7e…`, cols `110933cd…`, idx `21abaac8…`, policy `4f61b5a9…`, grant `bcdd6b57…`.

## 10. Production deploy rejasi
Bu reja faqat "DEPLOY TO PRODUCTION" tasdig'idan keyin bajariladi:
1. `111_backup_pre007e.sql`
2. `112_precheck_007e.sql` — `ok = true` bo'lishi shart.
3. `113_apply_007e.sql`
4. `114_verify_007e.sql` — `ok = true`; kutilgan katalog 49 / 133 / 104 / 103 / 122.
5. `115_security_tests_007e.sql` — ROLLBACK bilan, 48/48.
6. Regressiya: 105, 95, 85, 75, 65, 66, 44, 55, 56.
7. anon REST tekshiruvi — kutilgan javob 401.

Muammo chiqsa, `119_rollback_007e.sql` ishga tushiriladi. U faqat funksiyalarni olib tashlaydi.

## 11. Ma'lum cheklovlar
- Compliance faqat tayinlangan kurslarga asoslanadi. Lavozim yoki bo'lim bo'yicha "majburiy kurs katalogi" yo'q — bunday tuzilma mavjud sxemada ham yo'q. Majburiylik tayinlash yoki learning path orqali belgilanadi.
- Kurs arxivlansa ham uning tayinlashi hisobda qoladi. Bu 007a bilan bir xil xatti-harakat.
- Kurs `due_soon` holatini hisoblash va kunlik eslatmalar uchun cron yo'q — bu keyingi bosqichga qoldirildi.
- Tashkilot darajasidagi matritsa har chaqiruvda qayta hisoblanadi. 1 000 xodimda ~0.3 s ketadi. 5 000+ xodimda qayta baholash kerak bo'ladi: kesh yoki snapshot.

## 13. PRODUCTION DEPLOY (2026-11-27)
| Qadam | Natija |
|---|---|
| 111 backup | 49 / 49 jadval aynan, 1 162 qator, 103 policy, 127 funksiya, 104 trigger |
| 112 precheck | **ok = true** (007d = 1, 007e = 0, to'qnashuv 0, 13 / 131 / 2, org 1, role_permissions 119, 6 katalog hashi mos) |
| 113 apply (sha fd6ffc51…) | 18:39:39 → 18:39:47 UTC (bir marta); 6 funksiya; anon faqat `verify_certificate` |
| 114 verify | **ok = true**: 49 / 133 / 104 / 103 / 122; RPC 3/3; 6/6 STABLE + DEFINER + search_path; internal→auth 0; kategoriyasiz 0; ruxsatlar o'zgarmagan; CASCADE 0; 14 jadval + notifications + audit_logs o'zgarmagan; diff faqat +6 funksiya |
| 115 testlar (vaqtinchalik @test.local, ROLLBACK) | **007e 48/48** |
| Regressiya | 007d 58/58 · 007c 74/74 · 007b 78/78 · 007a 55/55 · 006a 83/83 · 006b 34/34 · 005d 54/54 · role matrix 62/62 · 005 regression 26/26 — fail 0 |
| Yakuniy verify | ok = true, ma'lumot o'zgarmagan, qoldiq 0 |
| anon REST | `employee_training_compliance` (ID bilan ham) / `employee_competency_matrix` / `department_compliance_matrix` 401; `verify_certificate` 200 |

Rollback bajarilmadi. Production: migratsiyalar 001 … 007d, 007e; 49 jadval / 133 funksiya / 104 trigger / 103 policy / 122 indeks; CASCADE 0; anon faqat `verify_certificate`.

## 12. Cheklovlar (o'zgarmagan)
- Main'ga merge qilinmadi, Pages deploy qilinmadi.
- Employee build, Phase 1 frontend va admin UI o'zgarmagan.
- questions.js va javob banki public build'da yo'q.
- "Confirm email" sozlamasiga tegilmagan.
- Test yozuvlari qoldirilmagan.

PHASE 3 STEP 11 — 007e LOCAL + STAGING + PRODUCTION READ-ONLY REVIEW PASSED — READY FOR EXPLICIT PRODUCTION DEPLOYMENT APPROVAL
