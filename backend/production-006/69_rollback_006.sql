-- FAQAT REAL INCIDENT UCHUN (alohida qaror bilan): 006b, keyin 006a ni bekor qilish. Ma'lumot o'chirilmaydi
-- (audit_logs va attempt_reset_events tarixi saqlanadi). Har bir fayl o'z tranzaksiyasida; ketma-ketlik: 006b → 006a.
\echo '1/2: migrations/006b_rollback.sql'
\echo '2/2: migrations/006a_rollback.sql'
-- SQL Editor'da: avval 006b_rollback.sql mazmunini, keyin 006a_rollback.sql mazmunini alohida ishga tushiring; keyin 61_precheck_006.sql
-- ("m006a = 0, m006b = 0", fn_md5 / policy_md5 bazaviy qiymatga qaytgani) bilan tekshiring.
