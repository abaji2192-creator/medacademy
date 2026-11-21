# Migration 004 — Production deployment (2026-11-22)

Project: `buuwjhpzptiiyggybvwr`. Applied: `004a_org_structure.sql` + `004b_org_isolation_existing.sql` (same bytes as staging, 51 471 bytes). Not applied: 005, Admin Panel; frontend unchanged.

## Backup (10_backup_pre004.sql) — PASS
Schema `backup.*_pre004_20261122`: profiles 1/1, docs 19/19, organizations 1/1, courses 13/13, questions 131/131, exam_configs 13/13, exam_attempts 2/2, certificates 0/0, attempt_resets 0/0.
Plus snapshots for rollback: 18 RLS policies, 22 functions, triggers. There were no 004 tables before the migration (0).

## Pre-check (11_precheck_004.sql)
Abdulaziz Isabaev · abaji2192@gmail.com · super_admin / active / Kardiologiya · org 00000000-…-0001.
profiles 1, docs 19, orgs 1, courses 13, questions 131, configs 13, attempts 2 (1 initial + 1 preview), certificates 0, auth users 1.

## Post-check (13_verify_004.sql) — 24/24 PASS
- 9 new tables.
- RLS: 0 public tables without RLS.
- 17 FKs on the new tables, 0 of them CASCADE.
- 6 unique constraints, 21 indexes.
- 0 rows with NULL `org_id`.
- Existing data unchanged: 1 profile, 19 docs, 13 courses, 131 questions, 13 configs, 1 initial attempt, 2 attempts in total, 0 certificates.
- Admin remains super_admin / active / Kardiologiya; employee record `EMP-262A128C / CARDIO / DOCTOR`.
- 1 organization (IMPULS), schema_migrations 001–004b, 56 role_permissions, 29 permissions, structure seed 10/18/11.

## Phase 1 regression (14_regression_004.sql, within ROLLBACK) — 16/16 PASS
Login, dashboard data, course list, initial assessment (12 questions, no answers), exam start, answer save, submit → 100% plus certificate, QR verify, correct-answer protection, review protection, employee isolation (SELECT/UPDATE), role escalation (role, permission), anon 18/18 denied, super admin org scope.
The temporary user, attempt and certificate were removed by the ROLLBACK. A repeat post-check showed certificates 0, profiles 1, auth users 1, attempts 2.

## Live site (real PostgREST, admin session)
- Dashboard, Courses, Question Bank and Results all render; the initial result is 85.7%; no errors in the console.
- REST: admin sees 13 courses, 131 questions, 1 employee, 10 departments, 56 permission rows.
- Anon gets 401 on profiles, questions, employees, departments, audit_logs and docs.
- `question_meta` returns 200. `verify_certificate` (anon) returns 200, and `null` for a code that does not exist. `start_exam` (anon) is denied.
- Docs: 19 → 20, because when the page was reloaded the app wrote its normal session `audit` record (not test data).

## Rollback
`19_rollback_004.sql` restores the policies, functions and triggers from the snapshot. Tested locally: policies and functions come back byte-identical, and no data is deleted. It was not used in production.
