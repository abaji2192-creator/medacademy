/* Ruxsatlar: role_permissions jadvalidan o'z rolining ruxsatlari (RLS: role = my_role()). super_admin — hammasi.
   UI faqat ko'rsatish/yashirish uchun; har bir amal serverda RLS + trigger + RPC orqali qayta tekshiriladi. */
(function () {
  const ADMIN_ROLES = ['super_admin', 'hr', 'education_manager', 'instructor', 'department_head', 'medical_reviewer', 'content_author'];
  const ROLE_LABEL = { super_admin: 'Super Admin', hr: 'HR', education_manager: 'Education Manager', instructor: 'Instructor', department_head: 'Department Head',
    medical_reviewer: 'Medical Reviewer', content_author: 'Content Author', employee: 'Employee' };
  const state = { profile: null, perms: new Set() };
  async function load(uid) {
    const p = await API.get('profiles', 'id', uid, 'id,email,full_name,role,status,org_id,department');
    state.profile = p; state.perms = new Set();
    if (p && p.status === 'active' && p.role !== 'super_admin') {
      const r = await API.list('role_permissions', { select: 'permission_key', eq: { role: p.role, org_id: p.org_id }, all: true, count: false });
      r.rows.forEach(x => state.perms.add(x.permission_key));
    }
    return p;
  }
  const role = () => state.profile && state.profile.role;
  const can = k => !!state.profile && state.profile.status === 'active' && (state.profile.role === 'super_admin' || state.perms.has(k));
  const any = (...ks) => ks.some(can);
  const isAdminUser = () => !!state.profile && state.profile.status === 'active' && ADMIN_ROLES.includes(state.profile.role);
  // 005e: server qoidalari bilan bir xil (UX uchun; haqiqiy tekshiruv — guard_question_review / question_workflow trigger'lari)
  const MEDICAL_REVIEW_ROLES = ['super_admin', 'medical_reviewer'];
  const PUBLISH_ROLES = ['super_admin', 'education_manager'];
  const canMedicalReview = () => can('medical.review') && MEDICAL_REVIEW_ROLES.includes(role());
  const canPublish = () => can('question.publish') && PUBLISH_ROLES.includes(role());
  const canAssignReview = () => PUBLISH_ROLES.includes(role()) && !!state.profile && state.profile.status === 'active';

  // Bo'limlar → kerakli ruxsat (server ham shu ruxsatlarni tekshiradi)
  const SECTIONS = {
    dashboard: () => isAdminUser(),
    questions: () => can('question.view'),
    evidence_queue: () => any('evidence.review', 'question.review', 'medical.review'),
    evidence_library: () => can('evidence.view'),
    employees: () => can('employee.view') || role() === 'department_head',
    organization: () => any('department.view', 'department.manage', 'position.manage', 'specialty.manage') && role() !== 'instructor' && role() !== 'content_author' && role() !== 'medical_reviewer',
    education: () => any('course.edit', 'assignment.view', 'instructor.assign') || role() === 'instructor',
    exams: () => can('exam.view'),
    audit: () => can('audit.view'),
  };
  const section = s => !!(SECTIONS[s] && SECTIONS[s]());
  window.PERMS = { load, can, any, role, section, isAdminUser, state, ROLE_LABEL, ADMIN_ROLES, canMedicalReview, canPublish, canAssignReview };
})();
