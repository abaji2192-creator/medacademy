import asyncio, sys
from playwright.async_api import async_playwright
BASE='http://localhost:54321/admin.html'
async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(channel='chrome', headless=True)
        pg = await b.new_page(viewport={'width':1400,'height':900})
        errs=[]; pg.on('console', lambda m: errs.append(m.text) if m.type=='error' else None); pg.on('pageerror', lambda e: errs.append('PAGEERR '+str(e)))
        await pg.goto(BASE); await pg.wait_for_selector('[data-login]')
        await pg.fill('input[name=email]','sa@test.local'); await pg.fill('input[name=password]','test-pass-123'); await pg.click('[data-login] button')
        await pg.wait_for_selector('[data-kpi]', timeout=20000); await pg.wait_for_timeout(1500)
        await pg.screenshot(path='/home/claude/medacademy/tests/admin/shots/dashboard.png', full_page=True)
        print('KPIS', await pg.eval_on_selector_all('[data-kpi]', 'els=>els.map(e=>e.dataset.kpi+"="+e.querySelector(".v").innerText)'))
        for h in ['#/questions','#/questions/Q001','#/questions/Q001?tab=answer','#/evidence/queue','#/evidence/review/Q001','#/evidence/library','#/employees','#/org/departments','#/edu/courses','#/edu/courses/ETHICS','#/edu/assignments','#/edu/instructors','#/exams/configs','#/exams/attempts','#/exams/results','#/audit']:
            await pg.goto(BASE+h); await pg.wait_for_timeout(1800)
            st = await pg.evaluate("()=>{const v=document.getElementById('view'); return (v.querySelector('[data-state]')?.dataset.state||'')+' | '+(v.querySelectorAll('table.t tbody tr').length)+' rows | '+v.innerText.slice(0,90).replace(/\\n/g,' ')}")
            print(h, '=>', st)
            await pg.screenshot(path='/home/claude/medacademy/tests/admin/shots/'+h.replace('#/','').replace('/','_').replace('?','_').replace('=','-')+'.png', full_page=False)
        print('ERRORS', errs[:20])
        await b.close()
asyncio.run(main())
