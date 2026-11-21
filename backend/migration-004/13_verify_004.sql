select chk, val, ok from (
  select 1 o, 'jadvallar (9 ta yangi)' chk, (select count(*) from pg_tables where schemaname='public' and tablename in ('schema_migrations','branches','departments','positions','specialties','employees','permissions','role_permissions','audit_logs'))::text val,
         (select count(*) from pg_tables where schemaname='public' and tablename in ('schema_migrations','branches','departments','positions','specialties','employees','permissions','role_permissions','audit_logs')) = 9 ok
  union all select 2, 'RLS o''chiq public jadvallar', coalesce((select string_agg(tablename, ',') from pg_tables where schemaname='public' and not rowsecurity), '0'),
         not exists (select 1 from pg_tables where schemaname='public' and not rowsecurity)
  union all select 3, 'FK (yangi jadvallar)', (select count(*) from pg_constraint where contype='f' and conrelid::regclass::text in ('branches','departments','positions','specialties','employees','role_permissions','audit_logs'))::text,
         (select count(*) from pg_constraint where contype='f' and conrelid::regclass::text in ('branches','departments','positions','specialties','employees','role_permissions','audit_logs')) >= 15
  union all select 4, 'CASCADE FK (yangi)', (select count(*) from pg_constraint where contype='f' and confdeltype='c' and conrelid::regclass::text in ('branches','departments','positions','specialties','employees','audit_logs'))::text,
         (select count(*) from pg_constraint where contype='f' and confdeltype='c' and conrelid::regclass::text in ('branches','departments','positions','specialties','employees','audit_logs')) = 0
  union all select 5, 'unique (org_id, code)', (select string_agg(conname, ',' order by conname) from pg_constraint where contype='u' and conrelid::regclass::text in ('branches','departments','positions','specialties','employees')),
         (select count(*) from pg_constraint where contype='u' and conrelid::regclass::text in ('branches','departments','positions','specialties','employees')) >= 6
  union all select 6, 'indekslar (yangi jadvallar)', (select count(*) from pg_indexes where schemaname='public' and tablename in ('branches','departments','positions','specialties','employees','role_permissions','audit_logs'))::text, true
  union all select 7, 'org_id NULL qatorlar', ((select count(*) from public.employees where org_id is null)+(select count(*) from public.departments where org_id is null)+(select count(*) from public.docs where org_id is null)+(select count(*) from public.exam_attempts where org_id is null)+(select count(*) from public.attempt_resets where org_id is null))::text,
         ((select count(*) from public.employees where org_id is null)+(select count(*) from public.departments where org_id is null)+(select count(*) from public.docs where org_id is null)+(select count(*) from public.exam_attempts where org_id is null)+(select count(*) from public.attempt_resets where org_id is null)) = 0
  union all select 8, 'profiles', (select count(*) from public.profiles)::text, (select count(*) from public.profiles) = 1
  union all select 9, 'docs (backup bilan teng)', (select count(*) from public.docs)::text, (select count(*) from public.docs) = (select count(*) from backup.docs_pre004_20261122)
  union all select 10, 'courses', (select count(*) from public.courses)::text, (select count(*) from public.courses) = 13
  union all select 11, 'questions', (select count(*) from public.questions)::text, (select count(*) from public.questions) = 131
  union all select 12, 'exam_configs', (select count(*) from public.exam_configs)::text, (select count(*) from public.exam_configs) = 13
  union all select 13, 'initial assessment urinish', (select count(*) from public.exam_attempts where kind='initial')::text, (select count(*) from public.exam_attempts where kind='initial') = 1
  union all select 14, 'barcha urinishlar (backup bilan teng)', (select count(*) from public.exam_attempts)::text, (select count(*) from public.exam_attempts) = (select count(*) from backup.exam_attempts_pre004_20261122)
  union all select 15, 'certificates', (select count(*) from public.certificates)::text, (select count(*) from public.certificates) = 0
  union all select 16, 'Abdulaziz', (select role||' / '||status||' / '||department from public.profiles where id='262a128c-6fb7-470e-9452-5468cd6797c0'),
         (select role||' / '||status||' / '||department from public.profiles where id='262a128c-6fb7-470e-9452-5468cd6797c0') = 'super_admin / active / Kardiologiya'
  union all select 17, 'Abdulaziz employee yozuvi', (select e.employee_code||' / '||coalesce(d.code,'-')||' / '||coalesce(p.code,'-') from public.employees e left join public.departments d on d.id=e.department_id left join public.positions p on p.id=e.position_id where e.profile_id='262a128c-6fb7-470e-9452-5468cd6797c0'),
         exists (select 1 from public.employees e join public.departments d on d.id=e.department_id where e.profile_id='262a128c-6fb7-470e-9452-5468cd6797c0' and d.code='CARDIO')
  union all select 18, 'employees jami', (select count(*) from public.employees)::text, (select count(*) from public.employees) = 1
  union all select 19, 'organizations (test org yo''q)', (select string_agg(coalesce(code,'-'), ',') from public.organizations), (select count(*) from public.organizations) = 1
  union all select 20, 'schema_migrations', (select string_agg(version, ',' order by version) from public.schema_migrations), (select count(*) from public.schema_migrations) = 5
  union all select 21, 'role_permissions (Impuls)', (select count(*) from public.role_permissions)::text, (select count(*) from public.role_permissions) = 56
  union all select 22, 'permissions', (select count(*) from public.permissions)::text, (select count(*) from public.permissions) = 29
  union all select 23, 'tuzilma seed (bo''lim/lavozim/mutaxassislik)', (select count(*) from public.departments)||'/'||(select count(*) from public.positions)||'/'||(select count(*) from public.specialties), (select count(*) from public.departments) = 10 and (select count(*) from public.positions) = 18
  union all select 24, 'auth.users o''zgarmagan', (select count(*) from auth.users)::text, (select count(*) from auth.users) = 1
) x order by o;
