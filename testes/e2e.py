"""Teste de ponta a ponta da home da Matutar Games (Playwright, Chromium).
Uso:  python3 -m http.server 8790  (na raiz do repositório)
      python3 testes/e2e.py http://localhost:8790
"""
import sys
from playwright.sync_api import sync_playwright
BASE=sys.argv[1].rstrip('/') if len(sys.argv)>1 else 'http://localhost:8790'
JOGOS=['https://duelo-matutar.netlify.app/','https://qualopreco.netlify.app/','https://confia-matutar.netlify.app/']
res=[]
def ok(n,c,x=''): res.append(bool(c)); print(('OK  ' if c else 'FALHA ')+n+(' · '+str(x) if not c and x!='' else ''))
with sync_playwright() as p:
    b=p.chromium.launch()
    for w in (320,360,390,1280):
        ctx=b.new_context(viewport={'width':w,'height':800},has_touch=w<500,is_mobile=w<500); pg=ctx.new_page(); err=[]
        pg.on('pageerror',lambda e:err.append(str(e))); pg.on('console',lambda m:m.type=='error' and err.append(m.text))
        pg.goto(BASE+'/'); pg.wait_for_timeout(400)
        ok(f'[{w}] sem rolagem lateral', pg.evaluate('document.documentElement.scrollWidth<=innerWidth'))
        pequenos=pg.evaluate("[...document.querySelectorAll('a,button')].filter(e=>e.offsetParent&&!e.classList.contains('pular')&&e.getBoundingClientRect().height<44).map(e=>e.textContent.trim().slice(0,20))")
        ok(f'[{w}] alvos de toque >= 44px', not pequenos, pequenos)
        ok(f'[{w}] três jogos apontam para os endereços de produção', pg.evaluate("[...document.querySelectorAll('a.jogar')].map(a=>a.href)")==JOGOS)
        ok(f'[{w}] fontes da casa carregadas', pg.evaluate("document.fonts.ready.then(()=>[...document.fonts].some(f=>f.family.includes('Bricolage')&&f.status==='loaded'))"))
        ok(f'[{w}] sem erros', not err, err[:3])
        ctx.close()
    pg=b.new_page(); r=pg.goto(BASE+'/'); txt=pg.inner_text('body')
    ok('texto do Duelo sem prometer desafio entre pessoas', 'Quanto mais palavras, mais pontos.' in txt and 'desafie' not in txt.lower())
    ok('próximo jogo sem nome nem data', 'Tem mais jogo sendo matutado por aqui. Em breve, novidades!' in txt)
    meta=lambda q: pg.get_attribute(q,'content')
    ok('og:url e og:image absolutos', meta('meta[property="og:url"]')=='https://matutar-games.netlify.app/' and meta('meta[property="og:image"]')=='https://matutar-games.netlify.app/img/og.png')
    ok('twitter:card com imagem grande', meta('meta[name="twitter:card"]')=='summary_large_image')
    dim=pg.evaluate("new Promise(r=>{const i=new Image();i.onload=()=>r([i.naturalWidth,i.naturalHeight]);i.onerror=()=>r(null);i.src='img/og.png'})")
    ok('imagem de compartilhamento 1200x630', dim==[1200,630], dim)
    for sel in ['link[rel=icon][type="image/svg+xml"]','link[rel=icon][type="image/png"]','link[rel=apple-touch-icon]']:
        href=pg.get_attribute(sel,'href'); ok(f'ícone {href} publicado', pg.request.get(BASE+'/'+href).status==200)
    ctx=b.new_context(permissions=['clipboard-read','clipboard-write']); pg=ctx.new_page(); pg.goto(BASE+'/')
    pg.evaluate("delete Navigator.prototype.share"); pg.click('#compartilhar'); pg.wait_for_timeout(300)
    clip=pg.evaluate('navigator.clipboard.readText()')
    ok('"Convidar alguém" copia texto com o endereço da home', 'Matutar Games' in clip and 'https://matutar-games.netlify.app' in clip, clip)
    ctx.close(); b.close()
print(f'{sum(res)} de {len(res)} OK')
