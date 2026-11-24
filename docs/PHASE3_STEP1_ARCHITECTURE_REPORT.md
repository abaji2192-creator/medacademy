# MedAcademy — PHASE 3 STEP 1 — ARCHITECTURE REPORT

**Sana:** 2026-11-24
**Turi:** faqat dizayn (kod, migratsiya, sxema o'zgarishi YO'Q; production va staging'ga tegilmadi)
**Manba:** production bilan bir xil sxema (005e + 006a + 006b) lokal nusxasi, `site/js` (xodim ilovasi) va `site/js/admin` (Admin Panel) kodi.

---

## Current State

### Phase 2 production holati
- 005e / 006a / 006b — production'da; courses 13, questions 131, exam_configs 13, attempts 2, certificates 0, profiles 1, audit_logs 307 (2026-11-24 16:45 UTC read-only tekshiruv).
- Xodim ilovasi live smoke — PASS (Super Admin sessiyasi, 11 sahifa, JS xatolari 0).
- Admin Panel live UI acceptance — **BLOCKED — USER LOGIN REQUIRED** (admin.html alohida sessiya). Phase 3 ni bloklamaydi, lekin Phase 3 production deploy'idan oldingi gate.

### Mavjud arxitektura (A. Current architecture map)

| Soha | Jadvallar (RLS yoqilgan, org_id NOT NULL, FK RESTRICT) | Ishlatilishi |
|---|---|---|
| Tashkilot | organizations, branches, departments, positions (family, academy), specialties, employees (employment_status), profiles (8 rol), org_invitations | Admin Panel (pages_org) |
| Ruxsatlar | permissions, role_permissions (45 ta kalit) | `has_perm()`, `my_role()`, `my_org()`, `my_employee_id()` |
| Kontent | courses (status 5 holat, domain, scope_type, valid_months), course_modules (draft/published/archived), lessons (content_type: text / video / document / presentation / clinical_case / quiz, estimated_minutes) — 13 / 35 / 48 qator | Admin Panel (pages_edu) |
| O'qish jarayoni | **course_assignments** (assigned / in_progress / completed / overdue / cancelled, due_date, started_at, completed_at), **lesson_progress** (not_started / in_progress / completed, progress_percent, last_accessed_at), **learning_paths** (+ target_position_family), **learning_path_courses** (order_index, is_required) — ma'lumot hozircha 0 / 0 / 10 / — | Admin Panel'da tayinlash; trigger'lar: `guard_lesson_progress`, `progress_marks_assignment`, `guard_course_assignment`, `enforce_same_org_005`, `audit_row` |
| Savollar va dalil | questions, question_versions, question_publications, question_reviews (005e), question_review_assignments, question_evidence, question_quality_scores, evidence_* (7 jadval), medical_topics, research_queries/results, content_policies | 005–005e, 006a `question_eligibility` |
| Imtihon | exam_configs, exam_attempts (o'zgarmas), attempt_resets, attempt_reset_events (006a), RPC: `start_exam`, `save_answers`, `submit_exam`, `get_attempt_review` | xodim ilovasi |
| Sertifikat | certificates (o'zgarmas, revoke qaytarilmas), `verify_certificate` (anon) | xodim ilovasi |
| Audit | audit_logs (006a: o'zgarmas, server trigger'lari) | Admin Panel |
| AI | ai_jobs (task_type: question_review / evidence_search / evidence_summary / question_generation / update_detection / guideline_comparison) | backend |
| Eski (Phase 1) | `docs` (collection: employees, plans, progress, attempts, certificates, notifications, skill_assess, settings, questions_custom, exam_overrides, initial, audit) | **xodim ilovasi hali shu yerdan o'qiydi**: ko'nikmalar (`skill_assess`), bildirishnomalar, reja, progress |

**Asosiy xulosa:** Phase 3.1 uchun LMS poydevori (kurs → modul → dars → dars progressi → tayinlash → learning path) Phase 2'da allaqachon relyatsion jadvallarda, RLS va audit bilan mavjud — lekin bo'sh va xodim ilovasiga ulanmagan. Ko'nikmalar, bildirishnomalar va kompetensiyalar esa hali faqat eski `docs` JSON'da. Shuning uchun Phase 3 = "yangi katta sxema" emas, balki mavjud jadvallarni **ulash + yetishmayotgan kichik qatlamlarni qo'shish**.

---

## B. Qayta ishlatiladigan jadvallar
courses, course_modules, lessons, lesson_progress, course_assignments, learning_paths, learning_path_courses, employees, positions, specialties, departments, role_permissions / permissions, audit_logs (006a `_audit006`), exam_configs (faqat o'qish), certificates (faqat o'qish).

## C. O'zgartirilmaydigan jadvallar
exam_attempts, certificates, attempt_resets, attempt_reset_events, audit_logs (faqat server yozuvi), questions / question_versions / question_reviews / question_publications / evidence_*, profiles rol modeli, 005e/006a/006b funksiyalari va trigger'lari. Imtihon dvigateli (`start_exam` / `submit_exam`) va baholash o'zgarmaydi.

---

## Proposed

### Learning progress (007a) — yangi jadvalsiz
- **Module / course progress** — jadval emas, server hisoblaydi (`lesson_progress` + `lessons` + `course_modules` dan): dars soni, tugallangan, foiz, oxirgi faollik. Ikki nusxali (denormalizatsiya) ma'lumot yo'q.
- **Statuslar:** not_started / in_progress / completed / overdue. `overdue` saqlanmaydi, o'qishda hisoblanadi (`due_date < current_date` va tugallanmagan) — cron kerak emas.
- `course_assignments` mavjud holat mashinasi va `progress_marks_assignment` trigger'i saqlanadi; kurs tugallanishi (barcha majburiy darslar completed) uchun `course.completed` audit hodisasi.
- **Imtihonga bog'liqlik:** kurs "completed" = darslar tugallangan; sertifikat esa avvalgidek faqat `submit_exam` orqali. Ikkisi aralashtirilmaydi.

### Learning paths (007b)
- Yangi jadval **`learning_path_assignments`**: org_id, path_id, nishon — aniq xodim YOKI qoida (position_id / specialty_id / department_id / role, bittasi majburiy), assigned_by, due_days, status (active / cancelled), reason, created_at.
- Server RPC `apply_learning_path(p_assignment)` — qoidaga mos xodimlar uchun `course_assignments` qatorlarini idempotent yaratadi (mavjudini takrorlamaydi, tugallanganini o'zgartirmaydi). Har bir chaqiruv audit qilinadi.

### Competencies / skills (007c)
- **`skills`** (katalog): org_id, code, name, category, specialty_id, description, assessment_criteria (jsonb), reassess_months, status.
- **`skill_assessments`** (o'zgarmas, faqat INSERT): org_id, skill_id, employee_id, assessor_id (= auth.uid()), assessed_at (server), level (novice / beginner / competent / proficient / expert), score, result (pass / fail), comments, evidence_note, reassess_at. Tuzatish = yangi qator (eski qator o'zgarmaydi) — 006a audit prinsipi bilan bir xil.
- **`competency_requirements`**: org_id, nishon (position_id / specialty_id / role), talab turi (course / skill / exam), talab id'si, is_required. Kompetensiya matritsasi = shu jadval + progress + skill_assessments + exam_attempts (faqat o'qish).
- Eski `docs.skill_assess` ma'lumoti: avtomatik ko'chirilmaydi; alohida, tasdiqlangan bir martalik import (lokal/staging'da sinovdan keyin).

### Notifications (007d) — faqat in_app
- **`notifications`**: org_id, recipient_profile_id, type (course_assigned, course_due, course_overdue, exam_due, exam_failed, certificate_issued, certificate_expiring, skill_assessment_due, learning_path_assigned), entity, entity_id, title, body (qisqa, maxfiy ma'lumotsiz), created_at, read_at.
- Faqat server trigger'lari / RPC yaratadi (client INSERT yo'q); foydalanuvchi faqat o'zinikini ko'radi va faqat `read_at` ni belgilaydi (`mark_notification_read` RPC). Email / Telegram / WhatsApp — yo'q.
- Muddatli (due / expiring / overdue) bildirishnomalar: o'qishda hisoblanadi yoki keyingi bosqichda rejalashtiriladi; 007d da faqat hodisa asosidagilari.

### Compliance / analytics (007e)
- RPC `training_compliance(p_scope)` — server tomonida agregatsiya: assigned / started / completed / overdue / failed / expiring / certified, xodim bo'yicha compliance %; HR / EM / SA (butun org), Department Head (o'z bo'limi). Mavjud analytics o'zgarmaydi.

### Faqat arxitektura (jadvalsiz)
- **AI Tutor:** faqat `published` dars / kurs / tasdiqlangan evidence xulosalari manbasi; savol banki, javob kalitlari, ichki izohlar, medical review izohlari, nashr qilinmagan kontent — yopiq. Kelajakda alohida server RPC (`tutor_context(p_lesson)`) faqat ruxsat etilgan maydonlarni qaytaradi.
- **Clinical Academy:** `positions.academy` va `specialties` orqali guruhlash (yangi jadval keyinroq); soxta klinik kontent yaratilmaydi.
- **Clinical cases:** `lessons.content_type = 'clinical_case'` allaqachon bor; yechim/javob xodim endpoint'iga chiqmasligi uchun keyinchalik alohida jadval (case_solutions, faqat reviewer/admin) — Phase 3.1 dan tashqarida.
- **Evidence kengaytmasi:** mavjud evidence_* boshqaruvi saqlanadi; soxta PMID / DOI / guideline yaratilmaydi.

---

## D. Yangi jadvallar

| Jadval | Maqsad | Org izolyatsiyasi | RLS | FK strategiyasi |
|---|---|---|---|---|
| learning_path_assignments | yo'lni xodim / qoidaga tayinlash | org_id NOT NULL + `enforce_same_org` | SELECT: SA/HR/EM (+Head o'z bo'limi); yozish: `learning_path.manage` | RESTRICT (paths, positions, specialties, departments, employees) |
| skills | ko'nikma katalogi | org_id NOT NULL | SELECT: org a'zolari (active); yozish: `skill.manage` | RESTRICT |
| skill_assessments | baholash tarixi (o'zgarmas) | org_id NOT NULL | SELECT: o'zi / assessor / SA/HR/EM / Head (bo'lim); INSERT: `skill.assess`; UPDATE/DELETE: yo'q (trigger rad etadi) | RESTRICT (skills, employees) |
| competency_requirements | rol / lavozim / mutaxassislik talablari | org_id NOT NULL | SELECT: org a'zolari; yozish: `competency.manage` | RESTRICT |
| notifications | in_app bildirishnomalar | org_id NOT NULL | SELECT: faqat qabul qiluvchi; INSERT: faqat server; UPDATE: faqat `read_at` RPC orqali | RESTRICT (profiles) |

Hech qayerda ON DELETE CASCADE yo'q; tarixiy yozuvlar o'chirilmaydi (006a/006b prinsipi).

## E. Yangi RLS policy'lar
Har yangi jadvalga SELECT / INSERT / UPDATE policy'lari (yuqoridagi jadval); DELETE policy yo'q. Mavjud policy'lar o'zgarmaydi. Policy soni migratsiyadan oldin/keyin fingerprint bilan solishtiriladi (006a usuli).

## F. Yangi funksiyalar / RPC'lar

| RPC | Kim | Natija |
|---|---|---|
| `my_learning_progress()` | xodim (o'zi) | tayinlangan kurslar, modul/kurs foizi, due / overdue, oxirgi faollik |
| `course_progress_summary(p_course)` | SA/HR/EM, Instructor (o'z kursi), Head (bo'limi) | agregat, sahifalangan |
| `apply_learning_path(p_assignment)` | `learning_path.manage` | idempotent course_assignments |
| `record_skill_assessment(...)` | `skill.assess` | yangi o'zgarmas qator + audit + bildirishnoma |
| `competency_matrix(p_scope)` | SA/HR/EM/Head | talab × holat matritsasi |
| `training_compliance(p_scope)` | SA/HR/EM/Head | compliance % |
| `mark_notification_read(p_id)` | qabul qiluvchi | read_at |

Hammasi SECURITY DEFINER + aniq `my_org()` / rol tekshiruvi; anon EXECUTE yo'q (005d default'lari bilan); `backup.function_categories_005d` ga ro'yxatdan o'tkaziladi.

## G. Yangi ruxsatlar

| Ruxsat | Rollar (taklif) |
|---|---|
| `skill.manage` | super_admin, education_manager |
| `skill.assess` | super_admin, education_manager, instructor, department_head |
| `competency.manage` | super_admin, education_manager, hr |
| `notification.view` (o'zinikini) | barcha faol rollar |

Mavjudlari qayta ishlatiladi: `assignment.manage`, `assignment.view`, `learning_path.manage`, `progress.view`, `assessment.view`, `report.view`. **Yangi rol qo'shilmaydi.** Yangi kalitlar `permissions` jadvaliga qo'shiladi; 005e'dagi `role_permissions_005e_chk` cheklovi bilan mosligi 007c lokal testida tekshiriladi.

## H. Audit hodisalari (006a `_audit006` orqali, o'zgarmas)
`learning_path.assigned`, `learning_path.applied`, `course.assigned` (mavjud audit_row bor — action nomi aniqlashtiriladi), `course.completed`, `skill.assessed`, `competency.requirement_changed`, `notification.created` (faqat hisob, matnsiz), `admin.config_changed`. Actor = auth.uid(), rol = my_role(), vaqt = server, sabab kerak joyda.

## I. API / ma'lumot oqimi
Admin Panel (yo'l / talab / baholash) → RLS + RPC → jadvallar → trigger'lar (audit, bildirishnoma) → xodim ilovasi faqat `my_learning_progress()` va o'zining `notifications` orqali o'qiydi. Xodim ilovasining eski `docs` (progress, skill_assess, notifications) o'qishi bosqichma-bosqich RPC'larga ko'chiriladi; ko'chirish tugaguncha eski yo'l o'zgarmaydi.

## J. UI sahifalari
- **Admin Panel:** Learning Paths (yaratish + tayinlash qoidalari), Assignments (mavjud sahifa kengaytiriladi: progress ustunlari), Skills katalogi, Skill assessment formasi, Competency matrix, Compliance dashboard. Mavjud navigatsiya / dizayn saqlanadi; loading / empty / error holatlari; ruxsatga qarab ko'rinish.
- **Xodim ilovasi:** "Mening o'qishim" — tayinlangan kurslar, progress bar, muddat, keyingi dars; bildirishnomalar ro'yxati (in_app). Mobile-first; matnlar uz (ru/en keyinroq).

## K. Migratsiya rejasi (har biri alohida, `backend/migration-007x/`)

| # | Tarkib | Yangi jadval |
|---|---|---|
| 007a | progress RPC'lari, `course.completed` audit, indekslar (lesson_progress(employee_id, lesson_id), course_assignments(employee_id, status, due_date)) | — |
| 007b | learning_path_assignments + `apply_learning_path` | 1 |
| 007c | skills, skill_assessments, competency_requirements + RPC'lar + ruxsatlar | 3 |
| 007d | notifications (in_app) + trigger'lar + RPC | 1 |
| 007e | compliance / matrix agregatsiya RPC'lari | — |

Har biri uchun: migratsiya SQL, rollback SQL, lokal testlar, staging testlar, SHA-256, idempotentlik, rollback/reapply, xavfsizlik, performance, hisobot (006a/006b andozasi).

## L. Rollback rejasi
Har migratsiyaning `_rollback.sql`i: yangi trigger / funksiya / policy'larni olib tashlaydi; yangi jadvallardagi tarixiy qatorlar (skill_assessments, notifications, path assignments) **o'chirilmaydi** — jadval saqlanib, yozish to'xtatiladi (006a rollback prinsipi). Rollback'dan keyin fingerprint oldingi holat bilan solishtiriladi.

## M. Xavfsizlik riskleri va choralar

| Risk | Chora |
|---|---|
| Xodim boshqalarning progress / baholashini ko'rishi | RLS: faqat o'zi; Head — faqat o'z bo'limi (mavjud `my_department_id()`); test: cross-employee / cross-dept / cross-org |
| Baholash natijasini soxtalashtirish | skill_assessments faqat INSERT, assessor = auth.uid(), UPDATE/DELETE trigger rad etadi |
| Bildirishnoma orqali maxfiy ma'lumot sizishi | body qisqa, javob kaliti / ichki izoh / ball tafsiloti yo'q; faqat server yaratadi |
| Learning path qoidasi orqali boshqa org xodimlariga tayinlash | `enforce_same_org` + RPC ichida `my_org()` |
| `lesson_progress` orqali kursni "soxta tugatish" | mavjud `guard_lesson_progress` saqlanadi; kurs tugashi sertifikat bermaydi (sertifikat faqat imtihon) |
| AI Tutor kontent sizishi | Phase 3'da faqat arxitektura; alohida RPC va ruxsat ro'yxati |
| Eski `docs` va yangi jadvallar o'rtasida nomuvofiqlik | ko'chirish bosqichma-bosqich, ikki tomonlama yozish yo'q; eski yo'l o'chirilgunga qadar manba aniq belgilanadi |

## N. Performance riskleri
- So'rov shakllari: xodim — o'z kurslari (≤ 50), dars progressi (≤ 500); admin — org bo'yicha agregat (xodimlar × kurslar).
- Indekslar: lesson_progress (employee_id, lesson_id) unique, (org_id, last_accessed_at); course_assignments (org_id, employee_id, status), (org_id, due_date) where status not in ('completed','cancelled'); skill_assessments (org_id, employee_id, skill_id, assessed_at desc); notifications (recipient_profile_id, read_at, created_at desc).
- Agregatsiya faqat serverda, sahifalangan; to'liq jadval yuklash va N+1 yo'q. Sinov: lokal'da sintetik 1 000 xodim × 50 kurs × 30 dars hajmida.

## O. Test rejasi
- **Lokal (PGlite, haqiqiy RLS):** sxema, RLS rol matritsasi (8 rol), cross-org (Org B), cross-department, negativ avtorizatsiya, o'zgarmaslik (skill_assessments, audit), audit hodisalari, idempotentlik (`apply_learning_path` ikki marta), rollback/reapply, performance.
- **Regressiya:** 006b 34, 006a 83, 005e 146, 005d 101/54, role matrix 62, 005 114, 004 50, Phase 1 32, Admin 109 — hammasi o'zgarmasdan o'tishi shart.
- **Staging:** apply → testlar → rollback (fingerprint aynan) → reapply → testlar → residue 0; UI testlari (staging login bo'lsa).

## P. Staging rollout rejasi
007a → (testlar, hisobot, tasdiq) → 007b → … → 007e; har biridan keyin to'liq regressiya. Production — faqat foydalanuvchining alohida aniq tasdig'i va Phase 2 Admin UI acceptance yopilgandan keyin.

---

## Production Impact

**NONE — PHASE 3 STEP 1 IS DESIGN ONLY**

(Production'ga faqat bitta read-only SELECT — baseline tekshiruvi; yozish 0. Staging'ga tegilmadi. Git: faqat ushbu hisobot fayli.)

## Final Status

**PHASE 3 STEP 1 — DESIGN READY FOR USER REVIEW**

Implementatsiya (Phase 3 STEP 2 — 007a lokal) faqat foydalanuvchi arxitekturani aniq tasdiqlagandan keyin boshlanadi. Tasdiqlash uchun ochiq savollar:
1. Kurs "completed" = barcha majburiy darslar tugallangan (imtihonsiz) — ma'qulmi, yoki imtihon ham shartmi?
2. `skill.assess` — Department Head ham baholay oladimi?
3. Eski `docs.skill_assess` / `progress` ma'lumotini import qilish kerakmi (production'da hozir 1 xodim, deyarli bo'sh)?
