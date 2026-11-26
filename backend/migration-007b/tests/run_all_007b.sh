#!/bin/bash
# 006a+006b+007a lokal to'liq test sikli
cd /home/claude/medacademy/tests
{
echo "== 007b suite";                     node m007b_local.mjs | head -1
echo "== 007b rollback/recovery";         node m007b_rollback_local.mjs | tail -1
echo "== 007a suite (007b bilan)";          T7B=1 node m007a_local_b.mjs | head -1
echo "== 007a rollback/recovery";         node m007a_rollback_local.mjs | tail -1
echo "== 006b suite";                     T7A=1 T7B=1 node m006b_local.mjs | head -1
echo "== 006b rollback/recovery";         node m006b_rollback_local.mjs | tail -1
echo "== 006a suite (006b bilan)";        T6B=1 T7A=1 T7B=1 node m006a_local.mjs | head -1
echo "== 006a rollback/recovery";         node m006a_rollback_local.mjs | tail -1
echo "== 005e security (006a bilan)";     T6A=1 T6B=1 T7A=1 T7B=1 node m005e_local.mjs | head -1
echo "== 005e rollback/recovery (006a'siz zanjir)"; node m005e_rollback_local.mjs | tail -1
echo "== 005d suite (005e+006a bilan)";   T6A=1 T6B=1 T7A=1 T7B=1 T5E=1 Q=1 node m005d_local.mjs | tail -1
echo "== 005 suite (005e+006a bilan)";    T6A=1 T6B=1 T7A=1 T7B=1 T5D=1 T5E=1 T005=1 Q=1 node m005_local.mjs | grep -E "^005:|ERROR"
echo "== 004 suite (005 setup, 005e+006a bilan)"; T6A=1 T6B=1 T7A=1 T7B=1 T5D=1 T5E=1 T45=1 Q=1 node m005_local.mjs | grep -E "^004|ERROR"
echo "== 004 suite (standalone)";         node m004_local.mjs | grep -E "test,"
echo "== Phase 1 (005e+006a bilan)";      WITH004=1 WITH005=1 WITH005D=1 WITH005E=1 WITH006A=1 WITH006B=1 WITH007A=1 WITH007B=1 node sql_test.mjs | grep -cE "^PASS"; WITH004=1 WITH005=1 WITH005D=1 WITH005E=1 WITH006A=1 WITH006B=1 WITH007A=1 WITH007B=1 node sql_test.mjs | grep -E "^FAIL|o'tdi"
echo "== Phase 1 (faqat 002/003)";        node sql_test.mjs | grep -cE "^PASS"
for f in staging/005d_04_tests.sql staging/005d_06_role_matrix.sql production/44_security_tests_005d.sql; do echo "== $f (005e+006a bilan)"; T6A=1 T6B=1 T7A=1 T7B=1 node run_sqlfile_005e.mjs $f | head -1; done
echo "== P01-P20 probe (005e+006a)"; T6A=1 T6B=1 T7A=1 T7B=1 T5E=1 node mr_probe_005e.mjs | cut -c1-120
} 2>&1 | tee run_all_007b.out
