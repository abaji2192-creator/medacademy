#!/bin/bash
# 005e lokal to'liq test sikli (bazaviy + 005e). Natijalar: /home/claude/medacademy/tests/run_all_005e.out
cd /home/claude/medacademy/tests
{
echo "== 005e security suite";            node m005e_local.mjs | head -1
echo "== 005e rollback/recovery";         node m005e_rollback_local.mjs | tail -1
echo "== 005d suite (005e bilan)";        T5E=1 Q=1 node m005d_local.mjs | tail -1
echo "== 005d suite (005e'siz)";          Q=1 node m005d_local.mjs | tail -1
echo "== 005 suite (005e bilan)";         T5D=1 T5E=1 T005=1 Q=1 node m005_local.mjs | grep -E "^005:|ERROR"
echo "== 005 suite (005e'siz)";           T5D=1 T005=1 Q=1 node m005_local.mjs | grep -E "^005:|ERROR"
echo "== 004 suite (005 setup, 005e bilan)"; T5D=1 T5E=1 T45=1 Q=1 node m005_local.mjs | grep -E "^004|ERROR"
echo "== 004 suite (standalone)";         node m004_local.mjs | grep -E "test,"
echo "== Phase 1 (005e bilan)";           WITH004=1 WITH005=1 WITH005D=1 WITH005E=1 node sql_test.mjs | grep -cE "^PASS"; WITH004=1 WITH005=1 WITH005D=1 WITH005E=1 node sql_test.mjs | grep -E "^FAIL|o'tdi"
echo "== Phase 1 (005e'siz)";             WITH004=1 WITH005=1 WITH005D=1 node sql_test.mjs | grep -cE "^PASS"
echo "== Phase 1 (faqat 002/003)";        node sql_test.mjs | grep -cE "^PASS"
for f in staging/005d_04_tests.sql staging/005d_06_role_matrix.sql production/44_security_tests_005d.sql; do echo "== $f (005e bilan)"; node run_sqlfile_005e.mjs $f | head -1; done
echo "== P01-P20 probe (005e)"; T5E=1 node mr_probe_005e.mjs | cut -c1-120
} 2>&1 | tee run_all_005e.out
