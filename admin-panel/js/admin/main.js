/* Admin Panel: login, sessiya, router (#/bo'lim/...), layout. */
(function () {
  const { esc } = UI;
  const root = document.getElementById('adm');
  const NAV = [
    ['', [['dashboard', '#/', 'Dashboard', '▦']]],
    ['Tashkilot', [['employees', '#/employees', 'Xodimlar', '👥'], ['organization', '#/org/departments', 'Bo\'limlar / Lavozimlar / Mutaxassisliklar', '🏥']]],
    ['Ta\'lim', [['education', '#/edu/courses', 'Kurslar', '📚'], ['education', '#/edu/assignments', 'Tayinlashlar', '🗓'], ['education', '#/edu/instructors', 'Instruktorlar', '🎓']]],
    ['Savollar banki', [['questions', '#/questions', 'Barcha savollar', '❓']]],
    ['Evidence', [['evidence_queue', '#/evidence/queue', 'Review Queue', '🔎'], ['evidence_library', '#/evidence/library', 'Evidence Library', '📑']]],
    ['Imtihonlar', [['exams', '#/exams/configs', 'Imtihon sozlamalari', '📝'], ['exams', '#/exams/attempts', 'Urinishlar va natijalar', '📊']]],
    ['Tizim', [['audit', '#/audit', 'Audit Logs', '🛡']]],
  ];
  const routes = ADMIN.routes;

  function layout() {
    const p = PERMS.state.profile;
    const nav = NAV.map(([g, items]) => { const vis = items.filter(i => PERMS.section(i[0])); if (!vis.length) return '';
      return (g ? `<div class="adm-grp">${esc(g)}</div>` : '') + vis.map(i => `<a href="${i[1]}" data-nav="${esc(i[1])}"><span>${i[3]}</span>${esc(i[2])}</a>`).join(''); }).join('');
    root.innerHTML = `<div class="adm"><aside class="adm-side" data-side><div class="adm-brand"><i>A</i>MedAcademy Admin</div><nav class="adm-nav">${nav}</nav>
      <div class="adm-grp" style="margin-top:22px">Ilova</div><nav class="adm-nav"><a href="./index.html">↩ Xodim ilovasi</a></nav></aside>
      <main class="adm-main"><div class="adm-top"><button class="btn sm adm-burger" data-burger>☰</button><b data-title></b>
      <div class="who"><div><b>${esc(p.full_name || p.email)}</b></div><div class="tiny" data-role="${esc(p.role)}">${esc(PERMS.ROLE_LABEL[p.role] || p.role)}</div></div>
      <button class="btn sm" data-logout>Chiqish</button></div><div class="adm-body" id="view"></div></main></div>`;
    root.querySelector('[data-logout]').onclick = logout;
    root.querySelector('[data-burger]').onclick = () => root.querySelector('[data-side]').classList.toggle('open');
  }

  async function render() {
    const view = document.getElementById('view'); if (!view) return;
    const gen = ++ADMIN.gen;
    const full = (location.hash || '#/').slice(1) || '/'; const [path, qstr] = full.split('?');
    const params = Object.fromEntries(new URLSearchParams(qstr || ''));
    document.querySelectorAll('[data-nav]').forEach(a => a.classList.toggle('on', path === a.getAttribute('data-nav').slice(1) || (a.getAttribute('data-nav') !== '#/' && path.startsWith(a.getAttribute('data-nav').slice(1)))));
    root.querySelector('[data-side]')?.classList.remove('open');
    const r = routes.find(x => x.re.test(path));
    if (!r) { view.innerHTML = `<div class="card">${UI.empty('Sahifa topilmadi', path)}</div>`; return; }
    if (!PERMS.section(r.section)) { view.innerHTML = UI.denied(); document.querySelector('[data-title]').textContent = 'Ruxsat yo\'q'; return; }
    const m = path.match(r.re); view.innerHTML = UI.skeleton();
    const ctx = { params: { ...(m.groups || {}), ...params }, gen, alive: () => gen === ADMIN.gen,
      setTitle: t => { const el = document.querySelector('[data-title]'); if (el) el.textContent = t; document.title = t + ' — MedAcademy Admin'; },
      query: params, setQuery: (patch) => { const q = new URLSearchParams({ ...params, ...patch }); [...q.keys()].forEach(k => { if (q.get(k) === '' || q.get(k) === null || q.get(k) === 'undefined') q.delete(k); });
        const s = q.toString(); history.replaceState(null, '', '#' + path + (s ? '?' + s : '')); Object.assign(params, patch); } };
    try { await r.render(view, ctx); } catch (e) { if (ctx.alive()) view.innerHTML = `<div class="card">${UI.errorBox(API.friendly(e))}</div>`; }
  }

  function loginScreen(msg) {
    root.innerHTML = `<div class="login"><div class="card"><h2>MedAcademy Admin</h2><div class="muted small" style="margin-bottom:8px">Faqat ruxsatli xodimlar uchun. Barcha amallar serverda tekshiriladi va audit qilinadi.</div>
      ${msg ? `<div class="note warn" data-login-msg>${esc(msg)}</div>` : ''}
      <form data-login><label>Email</label><input name="email" type="email" required autocomplete="username"><label>Parol</label><input name="password" type="password" required autocomplete="current-password">
      <div class="small" data-err style="color:#b91c1c;margin-top:8px"></div><button class="btn primary" style="margin-top:12px;width:100%">Kirish</button></form></div></div>`;
    const f = root.querySelector('[data-login]');
    f.onsubmit = async e => { e.preventDefault(); const btn = f.querySelector('button'); btn.disabled = true;
      const { error } = await API.sb.auth.signInWithPassword({ email: f.email.value.trim(), password: f.password.value });
      btn.disabled = false; if (error) { f.querySelector('[data-err]').textContent = error.message === 'Invalid login credentials' ? 'Email yoki parol noto\'g\'ri' : error.message; return; }
      await boot(); };
  }
  function deniedScreen(p) {
    root.innerHTML = `<div class="login"><div class="card" data-state="no-admin"><h2>Admin Panel</h2><p class="muted">${p && p.status !== 'active' ? 'Akkauntingiz faol emas (holat: ' + esc(p.status) + ').' : 'Rolingiz (' + esc(p ? PERMS.ROLE_LABEL[p.role] || p.role : '—') + ') uchun Admin Panel mavjud emas.'}</p>
      <div class="row"><a class="btn" href="./index.html">Xodim ilovasiga o'tish</a><button class="btn" data-logout>Chiqish</button></div></div></div>`;
    root.querySelector('[data-logout]').onclick = logout;
  }
  async function logout() { try { await API.sb.auth.signOut(); } catch (e) {} PERMS.state.profile = null; loginScreen('Tizimdan chiqdingiz.'); }

  let booted = false;
  async function boot() {
    if (!API.configured) { root.innerHTML = `<div class="login"><div class="card">${UI.errorBox('Supabase sozlanmagan (config.js)')}</div></div>`; return; }
    const { data } = await API.sb.auth.getSession();
    if (!data.session) return loginScreen();
    let p; try { p = await PERMS.load(data.session.user.id); } catch (e) { return loginScreen(e.code === 'expired' ? 'Sessiya muddati tugadi. Qayta kiring.' : e.message); }
    if (!PERMS.isAdminUser()) return deniedScreen(p);
    layout(); booted = true; render();
  }
  window.addEventListener('hashchange', () => { if (booted && PERMS.state.profile) render(); });
  API.configured && API.setOnExpired(async () => { try { await API.sb.auth.signOut({ scope: 'local' }); } catch (e) {} booted = false; PERMS.state.profile = null; loginScreen('Sessiya muddati tugadi. Qayta kiring.'); });
  API.configured && API.sb.auth.onAuthStateChange((ev) => { if (ev === 'SIGNED_OUT' && booted) { booted = false; PERMS.state.profile = null; loginScreen('Sessiya tugadi. Qayta kiring.'); } });
  // Jadval qatoriga bosish / sahifalash (delegatsiya)
  document.addEventListener('click', e => { const tr = e.target.closest('tr[data-href]'); if (tr && !e.target.closest('a,button,input,select')) location.hash = tr.getAttribute('data-href'); });
  window.ADMIN.render = render;
  setTimeout(boot, 0);
})();
