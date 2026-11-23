/* Admin API qatlami: supabase-js (publishable key) + RLS. Service role kaliti frontend'da HECH QACHON yo'q.
   Barcha ruxsat tekshiruvlari serverda (RLS, trigger guard'lar, RPC). UI tekshiruvi faqat qulaylik uchun. */
(function () {
  const cfg = window.MEDACADEMY_CONFIG || {};
  if (!cfg.supabaseUrl || !cfg.supabaseAnonKey) { window.API = { configured: false }; return; }
  if (/service_role|sb_secr[e]t_/i.test(cfg.supabaseAnonKey)) throw new Error('Xavfsizlik: frontend konfiguratsiyasida maxfiy kalit bo\'lmasligi kerak');
  const sb = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey, { auth: { persistSession: true, autoRefreshToken: true, storageKey: 'medacademy-admin-auth' } });
  let onExpired = () => {};

  const friendly = e => {
    if (!e) return new Error('Noma\'lum xato');
    const m = e.message || String(e);
    if (e.code === 'PGRST301' || /JWT expired/i.test(m)) { setTimeout(() => onExpired(), 0); return Object.assign(new Error('Sessiya muddati tugadi. Qayta kiring.'), { code: 'expired' }); }
    if (e.code === '42501' || /permission denied|row-level security/i.test(m)) return Object.assign(new Error('Ruxsat yo\'q (server rad etdi): ' + m), { code: 'denied' });
    if (e.code === '23503') return Object.assign(new Error('Bog\'liq yozuvlar mavjud — o\'chirib/uzib bo\'lmaydi: ' + m), { code: e.code });
    return Object.assign(new Error(m), { code: e.code });
  };
  const unwrap = async p => { const r = await p; if (r.error) throw friendly(r.error); return r; };

  // list(table, {select, eq:{}, in:{}, ilike:{col:q}, search:{cols:[],q}, or:'', gte:{}, lte:{}, is:{}, neq:{}, order:[col,asc], page, size})
  function applyFilters(q, o) {
    Object.entries(o.eq || {}).forEach(([k, v]) => { if (v !== '' && v !== undefined && v !== null) q = q.eq(k, v); });
    Object.entries(o.neq || {}).forEach(([k, v]) => { q = q.neq(k, v); });
    Object.entries(o.in || {}).forEach(([k, v]) => { q = q.in(k, v.length ? v : ['__none__']); });
    Object.entries(o.gte || {}).forEach(([k, v]) => { q = q.gte(k, v); });
    Object.entries(o.lte || {}).forEach(([k, v]) => { q = q.lte(k, v); });
    Object.entries(o.is || {}).forEach(([k, v]) => { q = q.is(k, v); });
    if (o.search && o.search.q) { const s = o.search.q.replace(/[(),*%]/g, ' ').trim(); if (s) q = q.or(o.search.cols.map(c => `${c}.ilike.*${s}*`).join(',')); }
    if (o.or) q = q.or(o.or);
    return q;
  }
  async function list(table, o = {}) {
    const size = o.size || 25, page = o.page || 0;
    let q = sb.from(table).select(o.select || '*', { count: o.count === false ? undefined : 'exact' });
    q = applyFilters(q, o);
    if (o.order) q = q.order(o.order[0], { ascending: o.order[1] !== false });
    if (o.all) q = q.range(0, (o.max || 999)); else q = q.range(page * size, page * size + size - 1);
    const r = await unwrap(q);
    return { rows: r.data || [], count: r.count ?? (r.data || []).length };
  }
  async function count(table, o = {}) { let q = sb.from(table).select('*', { count: 'exact', head: true }); q = applyFilters(q, o); const r = await unwrap(q); return r.count || 0; }
  async function get(table, col, val, select = '*') { const r = await unwrap(sb.from(table).select(select).eq(col, val).limit(1)); return (r.data || [])[0] || null; }
  async function insert(table, row) { const r = await unwrap(sb.from(table).insert(row).select()); return (r.data || [])[0]; }
  async function update(table, col, val, patch) { const r = await unwrap(sb.from(table).update(patch).eq(col, val).select()); if (!r.data || !r.data.length) throw new Error('Yozuv yangilanmadi (ruxsat yo\'q yoki topilmadi)'); return r.data[0]; }
  async function remove(table, col, val) { await unwrap(sb.from(table).delete().eq(col, val)); }
  async function rpc(fn, args) { const r = await unwrap(sb.rpc(fn, args || {})); return r.data; }

  window.API = { configured: true, sb, list, count, get, insert, update, remove, rpc, friendly, setOnExpired: f => { onExpired = f; } };
})();
