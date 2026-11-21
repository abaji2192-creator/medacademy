select u.email, p.full_name, p.role, p.status, p.department, p.org_id,
  (select count(*) from public.profiles) profiles, (select count(*) from public.docs) docs, (select count(*) from public.organizations) orgs,
  (select count(*) from public.courses) courses, (select count(*) from public.questions) questions, (select count(*) from public.exam_configs) configs,
  (select count(*) from public.exam_attempts) attempts, (select count(*) from public.exam_attempts where kind='initial') initial, (select count(*) from public.certificates) certs,
  (select count(*) from auth.users) users
from public.profiles p join auth.users u on u.id = p.id where u.email = 'abaji2192@gmail.com';
