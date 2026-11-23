# MedAcademy Admin Panel (MVP) — faqat lokal/staging

**Production'ga deploy qilinmagan.** Bu papka GitHub Pages'ga (main branch'dagi `index.html`) ta'sir qilmaydi. Xodim ilovasining live build'i o'zgarmagan (sha1 `e8dc98a4…`).

- `admin.html`, `css/admin.css`, `js/admin/*.js` — Admin Panel manba kodi (vanilla JS, `supabase-js` + publishable key + RLS).
- `build.py` — `site/admin.html` → `dist/admin/admin.html` (live config) va `dist/admin-local/admin.html` (lokal mock). Bundle'da savollar banki, javob kalitlari va maxfiy kalit yo'qligi build vaqtida tekshiriladi.
- `tests/mock_supabase.mjs` — FAQAT TEST: PGlite (haqiqiy Postgres, barcha migratsiyalar 002…005d, RLS, trigger, RPC) ustida PostgREST/GoTrue kichik to'plami.
- `tests/admin_tests.py` — Playwright + Chrome test matritsasi (85 test): rollar, org izolyatsiya, javob kaliti sizib chiqishi, evidence workflow, eligibility, tarixiy va sertifikat yaxlitligi, audit, UI holatlari.

Har bir amal uch darajada himoyalangan: UI (yashirish/403) + server (RLS, trigger guard, RPC tekshiruvi). UI tekshiruvi faqat qulaylik uchun.
