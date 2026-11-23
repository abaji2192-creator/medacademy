"""MedAcademy build: site/ → dist/live/index.html (ommaviy, savollar bankisiz) va dist/demo/index.html (to'liq demo)."""
import re, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SITE = os.path.join(ROOT, 'site')
def bundle(target, live):
    html = open(os.path.join(SITE, 'index.html')).read()
    css = open(os.path.join(SITE, 'css/app.css')).read()
    html = html.replace('<link rel="stylesheet" href="css/app.css">', '<style>\n' + css + '\n</style>')
    def rep(m):
        src = m.group(1)
        if live and src == 'js/questions.js': return '<!-- questions.js: live build\'da yo\'q (savollar serverda) -->'
        js = open(os.path.join(SITE, src)).read()
        if not live and src == 'js/config.js': js = 'window.MEDACADEMY_CONFIG = {};'
        if live and src == 'vendor/supabase.js': pass
        return '<script>/* ' + src + ' */\n' + js.replace('</script', '<\\/script') + '\n</script>'
    html = re.sub(r'<script src="([^"]+)"></script>', rep, html)
    if live:
        # himoya: live build'da to'g'ri javob kalitlari qolmaganini tekshirish
        assert 'window.SEED.QUESTIONS = Q.map' not in html and '"Q001"' not in html, 'Live build savollar bankini o\'z ichiga olmoqda!'
    os.makedirs(os.path.dirname(target), exist_ok=True)
    open(target, 'w').write(html)
    print(target, len(html))
bundle(os.path.join(ROOT, 'dist/live/index.html'), True)
bundle(os.path.join(ROOT, 'dist/demo/index.html'), False)


def bundle_admin(target, config_js):
    """Admin Panel: alohida sahifa (admin.html). Kontent (savollar, javoblar, evidence) bundle'da YO'Q — faqat serverdan RLS ostida."""
    html = open(os.path.join(SITE, 'admin.html')).read()
    css = open(os.path.join(SITE, 'css/app.css')).read() + '\n' + open(os.path.join(SITE, 'css/admin.css')).read()
    html = html.replace('<link rel="stylesheet" href="css/app.css">\n<link rel="stylesheet" href="css/admin.css">', '<style>\n' + css + '\n</style>')
    def rep(m):
        src = m.group(1)
        js = config_js if src == 'js/config.js' else open(os.path.join(SITE, src)).read()
        return '<script>/* ' + src + ' */\n' + js.replace('</script', '<\\/script') + '\n</script>'
    html = re.sub(r'<script src="([^"]+)"></script>', rep, html)
    assert not re.search(r'service_role|sb_secret_', config_js), 'Admin config maxfiy kalitni o\'z ichiga olmoqda'
    for bad in ['window.SEED.QUESTIONS = Q.map', '"Q001"']:
        assert bad not in html, 'Admin bundle taqiqlangan kontentni o\'z ichiga olmoqda: ' + bad
    assert not re.search(r'sb_secret_[A-Za-z0-9_-]{8,}', html), 'Admin bundle maxfiy kalitni o\'z ichiga olmoqda'
    assert 'js/questions.js' not in html and 'js/data.js' not in html, 'Admin bundle savollar/seed faylini o\'z ichiga olmoqda'
    os.makedirs(os.path.dirname(target), exist_ok=True)
    open(target, 'w').write(html)
    print(target, len(html))

if '--admin' in sys.argv or True:
    live_cfg = open(os.path.join(SITE, 'js/config.js')).read()
    bundle_admin(os.path.join(ROOT, 'dist/admin/admin.html'), live_cfg)
    bundle_admin(os.path.join(ROOT, 'dist/admin-local/admin.html'),
                 'window.MEDACADEMY_CONFIG = { supabaseUrl: "http://localhost:54321", supabaseAnonKey: "local-test-publishable-key" };')
