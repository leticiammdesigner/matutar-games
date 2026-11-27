"""Medição: só o endereço oficial conta, e os eventos saem de verdade.

O problema de testar isto é que medir.js só age em matutargames.com.br, e o teste roda em
localhost. Então aqui o navegador é levado a acreditar que está no endereço oficial: as
requisições para https://matutargames.com.br são atendidas com os arquivos do disco, e o script
do GoatCounter é trocado por um dublê que anota o que teria sido enviado, sem rede nenhuma.

Com isso dá para cobrar as duas metades:
  - no endereço oficial, o script é pedido e os eventos saem com o nome certo
  - em prévia e em localhost, o script não chega a ser pedido e nada é enviado

A segunda metade é a que protege o número: sem ela, cada teste nosso e cada prévia do Netlify
entraria na conta e o dado nasceria sujo.

Uso:  python3 -m http.server 8796   (na raiz do repositório)
      python3 testes/medicao.py http://localhost:8796
"""
import sys
from playwright.sync_api import sync_playwright

BASE = sys.argv[1].rstrip('/') if len(sys.argv) > 1 else 'http://localhost:8796'
CASA = 'https://matutargames.com.br'
res = []
def ok(n, c, x=''):
    res.append(bool(c)); print(('OK  ' if c else 'FALHA ') + n + (' · ' + str(x) if not c and x != '' else ''))

DUBLE = """
  window.__pedidos = [];
  window.goatcounter = { count: function (d) { window.__pedidos.push(d); } };
"""

def preparar(ctx, pedidos_de_rede, fingir_casa=True):
    """Atende o endereço oficial com os arquivos locais e troca o GoatCounter por um dublê."""
    if fingir_casa:
        def servir(route, request):
            caminho = request.url[len(CASA):].split('?')[0] or '/'
            alvo = BASE + (caminho if caminho != '/' else '/index.html')
            r = ctx.request.get(alvo)
            route.fulfill(status=r.status, body=r.body(), headers={'content-type': r.headers.get('content-type', 'text/html')})
        ctx.route(CASA + '/**', servir)

    def contador(route, request):
        pedidos_de_rede.append(request.url)
        route.fulfill(status=200, content_type='application/javascript', body=DUBLE)
    ctx.route('**/gc.zgo.at/**', contador)

with sync_playwright() as p:
    b = p.chromium.launch()

    # ---------------- no endereço oficial: mede ----------------
    ctx = b.new_context(viewport={'width': 1200, 'height': 800})
    rede = []
    preparar(ctx, rede)
    pg = ctx.new_page()
    erros = []
    pg.on('pageerror', lambda e: erros.append(str(e)))
    pg.goto(CASA + '/', wait_until='networkidle')
    pg.wait_for_timeout(600)

    ok('no endereço oficial o contador é carregado', any('count.js' in u for u in rede), rede)
    conta = pg.evaluate("() => (document.querySelector('script[data-goatcounter]') || {}).dataset")
    ok('aponta para a conta certa do GoatCounter',
       conta and 'maturar.goatcounter.com' in (conta.get('goatcounter') or ''), conta)
    ok('medir existe para o resto do site chamar', pg.evaluate("() => typeof window.medir") == 'function')
    ok('carregar a home não gera erro de script', not erros, erros[:2])

    # o convite só conta quando deu certo, então é preciso passar pelo caminho de cópia
    pg.evaluate("""() => {
      navigator.clipboard.writeText = () => Promise.resolve();
      Object.defineProperty(navigator, 'share', { configurable: true, value: undefined });
    }""")
    pg.click('#compartilhar')
    pg.wait_for_timeout(400)
    nomes = [d.get('path') for d in pg.evaluate("() => window.__pedidos || []")]
    ok('convidar alguém vira evento', 'hub-convida' in nomes, nomes)
    enviado = pg.evaluate("() => (window.__pedidos || []).find(d => d.path === 'hub-convida')") or {}
    ok('o evento vai marcado como evento, não como página', enviado.get('event') is True, enviado)
    ok('cada convite conta, não um por sessão', enviado.get('no_session') is True, enviado)
    ok('o evento não leva nada além do nome',
       set(enviado.keys()) <= {'path', 'title', 'event', 'no_session'}, list(enviado.keys()))

    # ---------------- a linha de transparência ----------------
    texto = (pg.text_content('.rodape') or '').lower()
    ok('o rodapé diz que a medição é anônima e sem cookies',
       'anônima' in texto and 'cookies' in texto, texto[:90])

    # ---------------- em prévia: não conta ----------------
    ctx2 = b.new_context(viewport={'width': 1200, 'height': 800})
    rede2 = []
    preparar(ctx2, rede2, fingir_casa=False)
    previa = ctx2.new_page()
    previa.goto(BASE + '/', wait_until='networkidle')
    previa.wait_for_timeout(600)

    ok('fora do endereço oficial o contador nem é pedido', rede2 == [], rede2)
    ok('fora do endereço oficial não existe tag do GoatCounter',
       previa.evaluate("() => document.querySelectorAll('script[data-goatcounter]').length") == 0)
    ok('medir continua existindo, para nenhuma chamada quebrar',
       previa.evaluate("() => typeof window.medir") == 'function')
    previa.evaluate("""() => {
      navigator.clipboard.writeText = () => Promise.resolve();
      Object.defineProperty(navigator, 'share', { configurable: true, value: undefined });
    }""")
    previa.click('#compartilhar')
    previa.wait_for_timeout(400)
    ok('clicar em prévia não envia nada', rede2 == [] and not previa.evaluate("() => window.__pedidos"), rede2)

    b.close()

print('%d de %d OK' % (sum(res), len(res)))
sys.exit(0 if all(res) else 1)
