// Lokal "mini-Supabase" (FAQAT TEST UCHUN): PGlite (haqiqiy Postgres + barcha migratsiyalar + RLS) ustida
// PostgREST va GoTrue'ning Admin Panel ishlatadigan qismi. Har so'rov foydalanuvchi roli (anon/authenticated) va JWT claim'lari bilan
// bajariladi — ya'ni RLS, trigger guard'lari va RPC tekshiruvlari production'dagidek ishlaydi. Production'ga hech qanday aloqasi yo'q.
import { PGlite } from '/tmp/pgt/node_modules/@electric-sql/pglite/dist/index.js';
import http from 'http';
import fs from 'fs';
import path from 'path';

const B = '/home/claude/medacademy/site/backend/';
const PORT = +(process.env.PORT || 54321);
const STATIC = process.env.STATIC_DIR || '/home/claude/medacademy/dist/admin-local';
const PASSWORD = 'test-pass-123';

export async function makeDb() {
  const db = new PGlite();
  await db.exec(`create role anon nologin; create role authenticated nologin; create role authenticator nologin; create role service_role nologin bypassrls; grant anon, authenticated to authenticator;
  create schema auth; create table auth.users (id uuid primary key, instance_id uuid, aud text, role text, email text, raw_user_meta_data jsonb, created_at timestamptz, updated_at timestamptz);
  create function auth.uid() returns uuid language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claim.sub', true),''), (nullif(current_setting('request.jwt.claims', true),'')::jsonb ->> 'sub'))::uuid $$;
  grant usage on schema auth to authenticated, anon; grant execute on function auth.uid() to authenticated, anon;
  alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
  alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
  grant usage on schema public to anon, authenticated, service_role;`);
  for (const f of ['supabase.sql', 'staging/01_prod_like_data.sql', 'production/01_apply_002_003.sql', 'production/12_apply_004.sql', 'production/22_apply_005.sql',
                   'migrations/005d_security_hardening.sql', 'migrations/005e_medical_review_authorization.sql', ...(process.env.WITH006A || process.env.WITH007 ? ['migrations/006a_audit_hardening.sql', ...(process.env.WITH006B || process.env.WITH007 ? ['migrations/006b_course_delete_hardening.sql'] : [])] : []), ...(process.env.WITH007 ? ['007a_learning_progress', '007b_learning_path_assignments', '007c_skills_competency', '007d_in_app_notifications', '007e_compliance_matrix'].map(x => 'migrations/' + x + '.sql') : []), 'tests/004_test_setup.sql', 'tests/005_test_setup.sql']) await db.exec(fs.readFileSync(B + f, 'utf8'));
  // Org A super admin'ni test uchun email bilan aniqlash + xodim yozuvlari (Admin Panel employees jadvalidan foydalanadi)
  await db.exec(`update auth.users set email = 'sa@test.local' where id = '262a128c-6fb7-470e-9452-5468cd6797c0';
    update public.profiles set email = u.email, full_name = coalesce(public.profiles.full_name, u.raw_user_meta_data->>'full_name') from auth.users u where u.id = public.profiles.id;
    insert into public.employees (org_id, profile_id, employee_code, first_name, last_name, department_id, employment_status)
    select p.org_id, p.id, 'T-' || left(p.id::text, 4) || right(p.id::text, 2), split_part(coalesce(p.full_name, 'Test'), ' ', 1), split_part(coalesce(p.full_name, ''), ' ', 2),
           (select id from public.departments d where d.org_id = p.org_id order by code limit 1), 'active'
    from public.profiles p where not exists (select 1 from public.employees e where e.profile_id = p.id) on conflict do nothing;`);
  return db;
}

// ---- PostgREST subset ----
const IDENT = /^[a-z_][a-z0-9_]*$/;
const ident = s => { if (!IDENT.test(s)) throw Object.assign(new Error('bad identifier ' + s), { code: 'PGRST100', status: 400 }); return '"' + s + '"'; };
const OPS = { eq: '=', neq: '<>', gt: '>', gte: '>=', lt: '<', lte: '<=', like: 'like', ilike: 'ilike' };
function parseCond(col, expr, params) {
  let neg = false; if (expr.startsWith('not.')) { neg = true; expr = expr.slice(4); }
  const dot = expr.indexOf('.'); const op = expr.slice(0, dot); let val = expr.slice(dot + 1);
  let sql;
  if (op === 'is') sql = `${ident(col)} is ${val === 'null' ? 'null' : val === 'true' ? 'true' : val === 'false' ? 'false' : (() => { throw new Error('bad is'); })()}`;
  else if (op === 'in') { const items = val.replace(/^\(|\)$/g, '').split(',').map(x => x.replace(/^"|"$/g, '')); params.push(items); sql = `${ident(col)}::text = any($${params.length}::text[])`; }
  else if (op === 'cs') { params.push(val); sql = `${ident(col)} @> $${params.length}`; }
  else if (OPS[op]) { if (op === 'like' || op === 'ilike') val = val.replace(/\*/g, '%'); params.push(val); sql = `${ident(col)}${op === 'ilike' || op === 'like' ? '::text' : ''} ${OPS[op]} $${params.length}`; }
  else throw Object.assign(new Error('unsupported operator ' + op), { status: 400 });
  return neg ? `not (${sql})` : sql;
}
function splitTop(s) { const out = []; let d = 0, cur = ''; for (const ch of s) { if (ch === '(') d++; if (ch === ')') d--; if (ch === ',' && d === 0) { out.push(cur); cur = ''; } else cur += ch; } if (cur) out.push(cur); return out; }
function parseOr(s, params) { // or=(a.ilike.*x*,b.eq.1)
  return '(' + splitTop(s.replace(/^\(|\)$/g, '')).map(p => { const i = p.indexOf('.'); return parseCond(p.slice(0, i), p.slice(i + 1), params); }).join(' or ') + ')';
}
function buildWhere(qs, params) {
  const conds = [];
  for (const [k, v] of qs) {
    if (['select', 'order', 'limit', 'offset', 'columns', 'on_conflict'].includes(k)) continue;
    if (k === 'or') conds.push(parseOr(v, params)); else conds.push(parseCond(k, v, params));
  }
  return conds.length ? ' where ' + conds.join(' and ') : '';
}
function buildSelect(sel) { if (!sel || sel === '*') return '*'; return sel.split(',').map(c => c.trim()).filter(Boolean).map(ident).join(', '); }
function buildOrder(o) { if (!o) return ''; return ' order by ' + o.split(',').map(p => { const [c, dir, nulls] = p.split('.'); return ident(c) + (dir === 'desc' ? ' desc' : ' asc') + (nulls === 'nullslast' ? ' nulls last' : nulls === 'nullsfirst' ? ' nulls first' : ''); }).join(', '); }

// ---- tokens ----
const sessions = new Map(); // refresh -> {uid, revoked}
const b64 = o => Buffer.from(JSON.stringify(o)).toString('base64url');
let EXPIRE_BEFORE = 0;
const mkToken = (uid, ttl) => { const exp = Math.floor(Date.now() / 1000) + ttl; return 'h.' + b64({ sub: uid, role: 'authenticated', exp, iat: Date.now() }) + '.s'; };
const readToken = t => { try { const p = JSON.parse(Buffer.from(t.split('.')[1], 'base64url').toString()); return p; } catch { return null; } };
let TOKEN_TTL = 3600;

export function startServer(db, { port = PORT, staticDir = STATIC } = {}) {
  let queue = Promise.resolve();
  const serial = fn => { const p = queue.then(fn, fn); queue = p.catch(() => {}); return p; };
  const asUser = (claims, fn) => serial(async () => {
    await db.exec('begin');
    try {
      if (claims) { await db.query(`select set_config('request.jwt.claims', $1, true), set_config('request.jwt.claim.sub', $2, true)`, [JSON.stringify(claims), claims.sub]); await db.exec('set local role authenticated'); }
      else { await db.query(`select set_config('request.jwt.claims', '{"role":"anon"}', true), set_config('request.jwt.claim.sub', '', true)`); await db.exec('set local role anon'); }
      const r = await fn(); await db.exec('commit'); return r;
    } catch (e) { await db.exec('rollback').catch(() => {}); throw e; }
  });
  const log = [];
  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://x');
    const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*', 'access-control-expose-headers': 'content-range' };
    if (req.method === 'OPTIONS') { res.writeHead(204, cors); return res.end(); }
    let body = ''; for await (const c of req) body += c;
    const send = (st, obj, extra = {}) => { res.writeHead(st, { 'content-type': 'application/json', ...cors, ...extra }); res.end(obj === undefined ? '' : JSON.stringify(obj)); };
    try {
      // static
      if (!url.pathname.startsWith('/rest/') && !url.pathname.startsWith('/auth/') && !url.pathname.startsWith('/__test/')) {
        const f = path.join(staticDir, url.pathname === '/' ? 'admin.html' : url.pathname.replace(/^\//, ''));
        if (fs.existsSync(f) && fs.statSync(f).isFile()) { res.writeHead(200, { 'content-type': f.endsWith('.html') ? 'text/html; charset=utf-8' : 'application/javascript' }); return res.end(fs.readFileSync(f)); }
        res.writeHead(404); return res.end('not found');
      }
      // test hooks
      if (url.pathname === '/__test/expire') { for (const s of sessions.values()) s.revoked = true; EXPIRE_BEFORE = Date.now(); return send(200, { ok: true }); }
      if (url.pathname === '/__test/ttl') { TOKEN_TTL = +url.searchParams.get('s') || 3600; return send(200, { ok: true }); }
      if (url.pathname === '/__test/log') return send(200, log.splice(0));
      if (url.pathname === '/__test/sql') { const r = await serial(() => db.exec(JSON.parse(body).sql)); const last = r.filter(x => x.fields && x.fields.length).pop(); return send(200, last ? last.rows : []); }
      // auth
      if (url.pathname === '/auth/v1/token') {
        const b = JSON.parse(body || '{}'); const gt = url.searchParams.get('grant_type');
        let uid, email;
        if (gt === 'password') {
          const u = (await serial(() => db.query(`select id::text, email from auth.users where lower(email) = lower($1)`, [b.email]))).rows[0];
          if (!u || b.password !== PASSWORD) return send(400, { error: 'invalid_grant', error_description: 'Invalid login credentials', msg: 'Invalid login credentials', code: 'invalid_credentials' });
          uid = u.id; email = u.email;
        } else if (gt === 'refresh_token') {
          const s = sessions.get(b.refresh_token); if (!s || s.revoked) return send(400, { error: 'invalid_grant', error_description: 'Invalid Refresh Token', code: 'refresh_token_not_found' });
          uid = s.uid; email = s.email; sessions.delete(b.refresh_token);
        } else return send(400, { error: 'unsupported_grant_type' });
        const rt = 'rt-' + Math.random().toString(36).slice(2); sessions.set(rt, { uid, email, revoked: false });
        return send(200, { access_token: mkToken(uid, TOKEN_TTL), token_type: 'bearer', expires_in: TOKEN_TTL, expires_at: Math.floor(Date.now() / 1000) + TOKEN_TTL, refresh_token: rt,
          user: { id: uid, aud: 'authenticated', role: 'authenticated', email, app_metadata: {}, user_metadata: {}, created_at: new Date().toISOString() } });
      }
      if (url.pathname === '/auth/v1/logout') return send(204);
      const bearer = (req.headers.authorization || '').replace(/^Bearer /, '');
      const claims = readToken(bearer);
      const isUser = claims && claims.sub;
      if (isUser && (claims.exp * 1000 < Date.now() || (claims.iat || 0) < EXPIRE_BEFORE)) return send(401, { code: 'PGRST301', message: 'JWT expired' });
      if (url.pathname === '/auth/v1/user') { if (!isUser) return send(401, { msg: 'no user' }); return send(200, { id: claims.sub, aud: 'authenticated', role: 'authenticated', app_metadata: {}, user_metadata: {} }); }
      const m = url.pathname.match(/^\/rest\/v1\/(rpc\/)?([a-z_][a-z0-9_]*)$/); if (!m) return send(404, { message: 'not found' });
      const qs = [...url.searchParams.entries()];
      const prefer = req.headers.prefer || '';
      const cl = isUser ? { sub: claims.sub, role: 'authenticated' } : null;
      log.push({ m: req.method, p: url.pathname, uid: cl && cl.sub, q: url.search });
      if (m[1]) { // RPC
        const args = body ? JSON.parse(body) : Object.fromEntries(qs);
        const params = []; const parts = Object.entries(args).map(([k, v]) => { params.push(typeof v === 'object' && v !== null ? JSON.stringify(v) : v); return `${ident(k)} => $${params.length}`; });
        const srf = (await db.query(`select bool_or(proretset) s from pg_proc where proname = $1 and pronamespace = 'public'::regnamespace`, [m[2]])).rows[0].s;
        if (srf) { // PostgREST: set-returning RPC -> JSON massiv
          const r = await asUser(cl, () => db.query(`select to_jsonb(x) as r from public.${ident(m[2])}(${parts.join(', ')}) x`, params));
          return send(200, r.rows.map(x => x.r));
        }
        const r = await asUser(cl, () => db.query(`select public.${ident(m[2])}(${parts.join(', ')}) as r`, params));
        return send(200, r.rows[0].r);
      }
      const t = 'public.' + ident(m[2]);
      if (req.method === 'GET' || req.method === 'HEAD') {
        const params = []; const where = buildWhere(qs, params);
        const lim = url.searchParams.get('limit'), off = url.searchParams.get('offset');
        let range = req.headers.range; let from = off ? +off : 0, to = null;
        if (range) { const [a, bb] = range.split('-'); from = +a; to = +bb; }
        const limit = lim ? +lim : to !== null ? to - from + 1 : null;
        const { rows, total } = await asUser(cl, async () => {
          const rows = req.method === 'HEAD' ? [] : (await db.query(`select ${buildSelect(url.searchParams.get('select'))} from ${t}${where}${buildOrder(url.searchParams.get('order'))}${limit !== null ? ' limit ' + limit : ''}${from ? ' offset ' + from : ''}`, params)).rows;
          const total = /count=exact/.test(prefer) ? (await db.query(`select count(*)::int n from ${t}${where}`, params)).rows[0].n : null;
          return { rows, total };
        });
        const cr = `${rows.length ? from + '-' + (from + rows.length - 1) : '*'}/${total === null ? '*' : total}`;
        if (/application\/vnd\.pgrst\.object/.test(req.headers.accept || '')) { if (rows.length !== 1) return send(406, { code: 'PGRST116', message: 'JSON object requested, multiple (or no) rows returned' }); return send(200, rows[0], { 'content-range': cr }); }
        return send(200, req.method === 'HEAD' ? undefined : rows, { 'content-range': cr });
      }
      if (req.method === 'POST' || req.method === 'PATCH' || req.method === 'DELETE') {
        const data = body ? JSON.parse(body) : null;
        const out = await asUser(cl, async () => {
          const res2 = [];
          if (req.method === 'POST') {
            for (const row of (Array.isArray(data) ? data : [data])) {
              const cols = Object.keys(row).map(ident);
              const r = await db.query(`insert into ${t} (${cols.join(',')}) select ${cols.join(',')} from jsonb_populate_record(null::${t}, $1::jsonb) returning *`, [JSON.stringify(row)]);
              res2.push(...r.rows);
            }
          } else if (req.method === 'PATCH') {
            const params = [JSON.stringify(data)]; const where = buildWhere(qs, params);
            if (!where) throw Object.assign(new Error('UPDATE requires a WHERE clause'), { status: 400 });
            const cols = Object.keys(data).map(ident);
            const r = await db.query(`update ${t} set (${cols.join(',')}) = (select ${cols.join(',')} from jsonb_populate_record(null::${t}, $1::jsonb))${where} returning *`, params);
            res2.push(...r.rows);
          } else {
            const params = []; const where = buildWhere(qs, params); if (!where) throw Object.assign(new Error('DELETE requires a WHERE clause'), { status: 400 });
            const r = await db.query(`delete from ${t}${where} returning *`, params); res2.push(...r.rows);
          }
          return res2;
        });
        if (/return=representation/.test(prefer)) {
          if (/application\/vnd\.pgrst\.object/.test(req.headers.accept || '')) return send(out.length === 1 ? 201 : 406, out.length === 1 ? out[0] : { code: 'PGRST116', message: 'no rows' });
          return send(req.method === 'POST' ? 201 : 200, out);
        }
        return send(req.method === 'POST' ? 201 : 204, undefined);
      }
      return send(405, { message: 'method' });
    } catch (e) {
      const code = e.code || 'XX000';
      const st = e.status || (code === '42501' ? (isUserReq(req) ? 403 : 401) : code === '23503' || code === '23505' || code === '23514' ? 409 : 400);
      send(st, { code, message: e.message, details: e.detail || null, hint: e.hint || null });
    }
  });
  const isUserReq = req => !!readToken((req.headers.authorization || '').replace(/^Bearer /, ''))?.sub;
  return new Promise(r => server.listen(port, () => r(server)));
}

if (process.argv[1] && process.argv[1].endsWith('mock_supabase.mjs')) {
  const db = await makeDb(); await startServer(db);
  console.log('mock supabase on http://localhost:' + PORT);
}
