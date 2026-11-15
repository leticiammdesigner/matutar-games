/* Matutar UI · conta (1.1.0-beta). Camada de contas compartilhada pelos jogos da Matutar Games.
 *
 * O que faz: botão de conta no cabeçalho + painel com entrar com o Google, apelido, Meu perfil,
 * participação no ranking (com consentimento), sair e excluir conta.
 *
 * Onde liga:
 *   - endereço oficial do jogo ........ DESLIGADA (a conta ainda não foi aprovada para produção)
 *   - prévias do Netlify ................ Supabase de TESTE
 *   - localhost ......................... só se o teste definir window.MT_CONTA_AMBIENTE (ambiente local)
 *
 * Regras que este arquivo garante no navegador (o servidor garante as mesmas no banco):
 *   - Jogar não exige conta. A sessão sem conta só nasce quando o jogo chama garantirSessao().
 *   - Sessão sem conta que entra com o Google: primeiro tenta VINCULAR (mesmo usuário, nada a migrar).
 *     Se o Google já tem conta, entra nela e resgata os resultados com um código de uso único
 *     criado pela própria sessão sem conta (prova de posse). Nunca por ID.
 *   - Erro ou cancelamento na volta do Google: a URL é limpa ANTES de o supabase-js iniciar,
 *     porque ele apaga a sessão guardada quando encontra um erro na URL.
 *   - Antes de sair para o Google, chama window.matutarAntesDeSair() para o jogo guardar a partida.
 *
 * O jogo pode definir window.matutarContaJogo = { id, nome, historico(linha) -> texto }.
 * API: window.MatutarConta = { ativa, config, pronto(), rpc(), garantirSessao(), estado(), abrir(tela), aoMudar(fn) }.
 */
(function () {
  'use strict';
  var TESTE = {
    nome: 'teste',
    url: 'https://dqaaqmolhvhhcknqfwlr.supabase.co',
    chave: 'sb_publishable_c1Iq5EOc3qNmJOlzwnpX-Q_XPKo_vvw', // publicável: pode ficar no navegador
    supabaseJs: 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.js',
    privacidade: 'https://deploy-preview-4--matutar-games.netlify.app/privacidade/',
    diarioNoServidor: false   // cada jogo liga a sua cópia quando o SQL dele estiver aplicado no projeto de teste
  };
  function ambiente() {
    var h = location.hostname;
    if (h === 'localhost' || h === '127.0.0.1') {
      if (window.MT_CONTA_AMBIENTE) return window.MT_CONTA_AMBIENTE;
      try { return JSON.parse(sessionStorage.getItem('mt-conta-ambiente-local')); } catch (e) { return null; }
    }
    if (/^deploy-preview-\d+--[a-z0-9-]+\.netlify\.app$/.test(h)) return TESTE;
    return null;
  }
  var cfg = ambiente();
  var API = window.MatutarConta = { ativa: !!cfg, config: cfg || {} };
  if (!cfg) { API.pronto = function () { return Promise.resolve(null); }; API.aoMudar = function () {}; return; }

  // ---------- volta do Google: ler e LIMPAR a URL antes de qualquer coisa
  var volta = location.origin + location.pathname;
  var par = new URLSearchParams(location.search.replace(/^\?/, '') + '&' + location.hash.replace(/^#/, ''));
  var erroVolta = par.get('error_code') || par.get('error'), erroTexto = par.get('error_description') || '';
  var voltouComCodigo = par.has('code');
  if (erroVolta) history.replaceState(null, '', volta);

  var CODIGO = 'mt-conta-codigo', TENTOU = 'mt-conta-tentou-ligar';
  var sb = null, sessao = null, anonimo = false, perfil = null, historico = null;
  var tela = 'conta', aviso = '', avisoTipo = '', ouvintes = [], ocupado = false;
  var jogo = function () { return window.matutarContaJogo || { id: null, nome: 'este jogo' }; };

  var MSG = {
    apelido_tamanho: 'Use de 3 a 20 caracteres.',
    apelido_caracteres: 'Use só letras, números e espaço.',
    apelido_nao_permitido: 'Esse apelido não pode ser usado. Escolha outro.',
    apelido_em_uso: 'Esse apelido já tem dono. Escolha outro.',
    apelido_troca_recente: 'Você trocou de apelido há pouco. Dá para trocar de novo depois de 30 dias.',
    precisa_apelido: 'Escolha um apelido antes de entrar no ranking.',
    codigo_expirado: 'Demorou demais para entrar, e os resultados deste aparelho ficaram aqui. Entre de novo para trazer.',
    codigo_ja_usado: 'Os resultados deste aparelho já foram trazidos antes.'
  };

  // ---------- cliente
  var prontoP = null;
  function carregar(src) {
    return new Promise(function (ok, erro) {
      if (window.supabase && window.supabase.createClient) return ok();
      var s = document.createElement('script'); s.src = src; s.onload = ok; s.onerror = erro; document.head.appendChild(s);
    });
  }
  API.pronto = function () {
    if (!prontoP) prontoP = carregar(cfg.supabaseJs).then(async function () {
      sb = window.supabase.createClient(cfg.url, cfg.chave, { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, flowType: 'pkce', storageKey: 'mt-conta-' + cfg.nome } });
      await ler();
      return sb;
    });
    return prontoP;
  };
  async function ler() {
    var s = await sb.auth.getSession(); sessao = s.data.session;
    anonimo = !!(sessao && sessao.user && sessao.user.is_anonymous);
    perfil = null; historico = null;
    if (sessao && !anonimo) { try { perfil = await chamar('meu_perfil'); } catch (e) { perfil = null; } }
  }
  function rpc(nome, args) { return API.pronto().then(function () { return chamar(nome, args); }); }
  async function chamar(nome, args) {   // sem esperar pronto(): é usada dentro dele
    var r = await sb.rpc(nome, args || {});
    if (r.error) { var e = new Error(r.error.message || 'falha'); e.codigo = String(r.error.message || '').trim(); throw e; }
    return r.data;
  }
  API.rpc = rpc;
  API.estado = function () { return { sessao: !!sessao, anonimo: anonimo, conta: !!(sessao && !anonimo), perfil: perfil, usuario: sessao ? sessao.user.id : null }; };
  API.aoMudar = function (fn) { ouvintes.push(fn); };
  function mudou() { ouvintes.forEach(function (fn) { try { fn(API.estado()); } catch (e) {} }); }
  // o jogo chama quando precisa gravar algo no servidor (ex.: enviar o palpite do dia)
  API.garantirSessao = async function () {
    await API.pronto();
    if (!sessao) {
      var r = await sb.auth.signInAnonymously();
      if (r.error) { var e = new Error(r.error.message); e.codigo = 'sem_sessao'; throw e; }
      await ler(); desenhar();
    }
    return API.estado();
  };

  // ---------- botão do cabeçalho
  var ICONE = '<svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true" focusable="false"><circle cx="12" cy="8.5" r="3.6" fill="none" stroke="currentColor" stroke-width="2"/><path d="M4.8 19.5c1.2-3.4 4-5 7.2-5s6 1.6 7.2 5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>';
  var botao = document.createElement('button');
  botao.type = 'button'; botao.className = 'mt-conta'; botao.setAttribute('aria-haspopup', 'dialog');
  botao.setAttribute('aria-label', 'Entrar na sua conta'); botao.innerHTML = ICONE;
  var antes = document.querySelector('[data-mt-conta-antes]');
  if (antes) { antes.parentNode.insertBefore(botao, antes); document.documentElement.classList.add('mt-tem-conta'); }

  var painel = document.createElement('dialog');
  painel.className = 'mt-aviso mt-conta-painel'; painel.setAttribute('aria-labelledby', 'mt-conta-titulo');
  document.body.appendChild(painel);
  painel.addEventListener('click', function (e) { if (e.target === painel) painel.close(); });   // toque fora fecha

  // ---------- desenho
  function el(tag, cls, txt) { var x = document.createElement(tag); if (cls) x.className = cls; if (txt != null) x.textContent = txt; return x; }
  function bt(cls, txt, fn) { var b = el('button', cls, txt); b.type = 'button'; b.onclick = fn; return b; }
  function dataBR(iso) { var p = String(iso).slice(0, 10).split('-'); return p[2] + '/' + p[1] + '/' + p[0]; }
  function avisar(txt, tipo) { aviso = txt || ''; avisoTipo = tipo || ''; desenhar(); }
  function ir(t) { tela = t; aviso = ''; avisoTipo = ''; desenhar(); var f = painel.querySelector('[data-foco]'); if (f) f.focus(); }

  function desenhar() {
    var comConta = !!(sessao && !anonimo);
    botao.classList.toggle('conectada', comConta);
    botao.setAttribute('aria-label', comConta ? 'Meu perfil' : 'Entrar na sua conta');
    botao.innerHTML = comConta && perfil && perfil.apelido ? '<span aria-hidden="true">' + perfil.apelido.charAt(0).toUpperCase() + '</span>' : ICONE;
    if (!comConta && tela !== 'conta') tela = 'conta';
    if (comConta && tela === 'conta') tela = perfil && perfil.apelido ? 'perfil' : 'apelido';

    painel.innerHTML = '';
    var c = el('div', 'mt-conta-corpo'); c.setAttribute('data-tela', tela);
    var titulos = { conta: 'Sua conta', apelido: perfil && perfil.apelido ? 'Trocar apelido' : 'Escolha seu apelido', perfil: 'Meu perfil', ranking: 'Participar do ranking', excluir: 'Excluir conta' };
    var topo = el('div', 'mt-conta-topo');
    var h = el('h2', null, titulos[tela]); h.id = 'mt-conta-titulo'; topo.appendChild(h);
    var x = bt('mt-conta-fechar', '', function () { painel.close(); });
    x.innerHTML = '<svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false"><path d="M6 6l12 12M18 6L6 18" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"/></svg>';
    x.setAttribute('aria-label', 'Fechar'); x.title = 'Fechar'; topo.appendChild(x);
    c.appendChild(topo);
    var st = el('p', 'mt-conta-status' + (avisoTipo ? ' ' + avisoTipo : ''), aviso); st.setAttribute('role', 'status'); c.appendChild(st);
    ({ conta: telaConta, apelido: telaApelido, perfil: telaPerfil, ranking: telaRanking, excluir: telaExcluir })[tela](c);
    painel.appendChild(c);
  }

  function telaConta(c) {
    c.appendChild(el('p', null, 'Entre com o Google para guardar os resultados dos desafios diários e ver em qualquer aparelho.'));
    c.appendChild(el('p', 'mt-conta-nota', 'Jogar não exige conta. Partidas livres continuam só neste aparelho. Seu nome e seu e-mail do Google não aparecem no jogo.'));
    var g = bt('mt-btn mt-conta-google', 'Entrar com o Google', entrar); g.setAttribute('data-foco', ''); c.appendChild(g);
    c.appendChild(bt('mt-conta-texto', 'Agora não', function () { painel.close(); }));
    linkPrivacidade(c);
  }

  function telaApelido(c) {
    var primeiro = !(perfil && perfil.apelido);
    c.appendChild(el('p', null, primeiro ? 'É o nome que representa você na Matutar Games.' : 'A troca vale para todos os jogos.'));
    c.appendChild(el('p', 'mt-conta-nota', 'Seu apelido fica privado. Só aparece em público se você escolher participar do ranking.'));
    var f = el('form', 'mt-conta-form'); f.noValidate = true;
    var l = el('label', null, 'Apelido'); l.htmlFor = 'mt-apelido';
    var i = el('input'); i.id = 'mt-apelido'; i.type = 'text'; i.maxLength = 20; i.autocomplete = 'off'; i.setAttribute('autocapitalize', 'words'); i.setAttribute('data-foco', '');
    i.setAttribute('aria-describedby', 'mt-apelido-regra mt-apelido-erro'); i.value = perfil && perfil.apelido ? perfil.apelido : '';
    var regra = el('p', 'mt-conta-nota', 'De 3 a 20 caracteres: letras, números e espaço.'); regra.id = 'mt-apelido-regra';
    var erro = el('p', 'mt-conta-erro'); erro.id = 'mt-apelido-erro'; erro.setAttribute('role', 'alert');
    var salvar = el('button', 'mt-btn', primeiro ? 'Salvar apelido' : 'Trocar apelido'); salvar.type = 'submit';
    f.appendChild(l); f.appendChild(i); f.appendChild(regra); f.appendChild(erro); f.appendChild(salvar);
    f.onsubmit = async function (e) {
      e.preventDefault(); var v = i.value.replace(/\s+/g, ' ').trim(); erro.textContent = '';
      if (v.length < 3 || v.length > 20) { erro.textContent = MSG.apelido_tamanho; i.setAttribute('aria-invalid', 'true'); i.focus(); return; }
      if (!/^[A-Za-zÀ-ÖØ-öø-ÿ0-9 ]+$/.test(v)) { erro.textContent = MSG.apelido_caracteres; i.setAttribute('aria-invalid', 'true'); i.focus(); return; }
      salvar.disabled = true;
      try { perfil = await rpc('definir_apelido', { p_apelido: v }); tela = 'perfil'; avisar(primeiro ? 'Apelido salvo.' : 'Apelido trocado.', 'ok'); mudou(); }
      catch (x) { salvar.disabled = false; erro.textContent = MSG[x.codigo] || 'Não deu para salvar agora. Tente de novo.'; i.setAttribute('aria-invalid', 'true'); i.focus(); }
    };
    c.appendChild(f);
    if (primeiro) {
      rpc('sugerir_apelido').then(function (s) { if (s && !i.value && document.body.contains(i)) { i.value = s; i.select(); } }, function () {});
      c.appendChild(bt('mt-conta-texto', 'Agora não', function () { painel.close(); }));
    } else c.appendChild(bt('mt-conta-texto', 'Voltar', function () { ir('perfil'); }));
  }

  function telaPerfil(c) {
    var semApelido = !(perfil && perfil.apelido);
    // apelido
    var a = el('div', 'mt-conta-bloco');
    a.appendChild(el('span', 'mt-conta-rotulo', 'Apelido'));
    a.appendChild(el('strong', 'mt-conta-valor', semApelido ? 'Ainda sem apelido' : perfil.apelido));
    var quando = perfil && perfil.pode_trocar_apelido_em && new Date(perfil.pode_trocar_apelido_em) > new Date() ? perfil.pode_trocar_apelido_em : null;
    if (quando) a.appendChild(el('span', 'mt-conta-nota', 'Dá para trocar de novo a partir de ' + dataBR(quando) + '.'));
    else a.appendChild(bt('mt-btn mt-btn-claro mt-conta-menor', semApelido ? 'Escolher apelido' : 'Trocar apelido', function () { ir('apelido'); }));
    c.appendChild(a);
    // ranking
    var r = el('div', 'mt-conta-bloco');
    r.appendChild(el('span', 'mt-conta-rotulo', 'Ranking público'));
    var participa = !!(perfil && perfil.ranking_publico);
    r.appendChild(el('strong', 'mt-conta-valor', participa ? 'Participando' : 'Não participando'));
    r.appendChild(el('span', 'mt-conta-nota', participa ? 'Seu apelido e seus resultados dos desafios diários aparecem nos placares.' : 'Seus resultados ficam só no seu histórico.'));
    if (participa) r.appendChild(bt('mt-btn mt-btn-claro mt-conta-menor', 'Sair do ranking', async function () {
      try { perfil = await rpc('definir_ranking_publico', { p_participar: false }); avisar('Você saiu do ranking. Seu apelido não aparece mais nos placares.', 'ok'); mudou(); }
      catch (x) { avisar('Não deu para sair do ranking agora. Tente de novo.', 'erro'); }
    }));
    else r.appendChild(bt('mt-btn mt-btn-claro mt-conta-menor', 'Participar do ranking', function () { ir(semApelido ? 'apelido' : 'ranking'); }));
    c.appendChild(r);
    // histórico (só desafios diários salvos no servidor)
    var hb = el('div', 'mt-conta-bloco');
    hb.appendChild(el('span', 'mt-conta-rotulo', 'Histórico em ' + jogo().nome));
    var lista = el('div', 'mt-conta-historico'); lista.setAttribute('aria-live', 'polite'); hb.appendChild(lista);
    hb.appendChild(el('span', 'mt-conta-nota', 'Só os desafios diários ficam na conta. Partidas livres continuam só neste aparelho.'));
    c.appendChild(hb);
    var preencher = function () {
      lista.innerHTML = '';
      if (historico === null) { lista.appendChild(el('p', 'mt-conta-nota', 'Buscando…')); return; }
      if (historico === false) { lista.appendChild(el('p', 'mt-conta-nota', 'Não deu para buscar o histórico agora.')); return; }
      if (!historico.length) { lista.appendChild(el('p', 'mt-conta-vazio', 'Nenhum desafio diário na conta ainda. O primeiro que você jogar aparece aqui.')); return; }
      lista.appendChild(el('p', 'mt-conta-resumo', historico.length === 1 ? '1 dia jogado' : historico.length + ' dias jogados'));
      var ul = el('ul');
      historico.slice(0, 10).forEach(function (x) {
        var li = el('li'); li.appendChild(el('span', 'mt-conta-dia', dataBR(x.data).slice(0, 5)));
        li.appendChild(el('span', null, jogo().historico ? jogo().historico(x) : x.pontos + ' pontos')); ul.appendChild(li);
      });
      lista.appendChild(ul);
    };
    preencher();
    if (historico === null) rpc('meu_historico', { p_jogo: jogo().id }).then(function (hh) { historico = hh || []; }, function () { historico = false; }).then(function () { if (document.body.contains(lista)) preencher(); });
    // conta
    linkPrivacidade(c);
    var rodape = el('div', 'mt-conta-rodape');
    rodape.appendChild(bt('mt-conta-texto', 'Sair', sair));
    rodape.appendChild(bt('mt-conta-texto mt-conta-perigo', 'Excluir conta', function () { ir('excluir'); }));
    c.appendChild(rodape);
  }

  function telaRanking(c) {
    c.appendChild(el('p', null, 'É assim que você vai aparecer nos placares:'));
    var previa = el('div', 'mt-conta-previa'); previa.appendChild(el('strong', null, perfil.apelido)); previa.appendChild(el('span', null, 'sua posição e seu resultado de cada dia')); c.appendChild(previa);
    c.appendChild(el('p', null, 'Seu apelido e seus resultados nos desafios diários ficam visíveis para qualquer pessoa no placar de cada jogo da Matutar Games.'));
    c.appendChild(el('p', 'mt-conta-nota', 'Seu nome e seu e-mail do Google nunca aparecem. Você pode sair do ranking quando quiser.'));
    var sim = bt('mt-btn', 'Quero aparecer no ranking', async function () {
      sim.disabled = true;
      try { perfil = await rpc('definir_ranking_publico', { p_participar: true }); tela = 'perfil'; avisar('Pronto, você está no ranking.', 'ok'); mudou(); }
      catch (x) { sim.disabled = false; avisar(MSG[x.codigo] || 'Não deu para entrar no ranking agora. Tente de novo.', 'erro'); }
    }); sim.setAttribute('data-foco', ''); c.appendChild(sim);
    c.appendChild(bt('mt-conta-texto', 'Agora não', function () { ir('perfil'); }));
  }

  function telaExcluir(c) {
    c.appendChild(el('p', null, 'Isso apaga de vez a sua conta de login, o apelido, os resultados dos desafios diários e a participação no ranking, em todos os jogos.'));
    c.appendChild(el('p', 'mt-conta-nota', 'Não dá para desfazer. O que está só neste aparelho (partidas livres e recordes) não muda.'));
    var f = el('form', 'mt-conta-form'); f.noValidate = true;
    var l = el('label', null, 'Para confirmar, digite EXCLUIR'); l.htmlFor = 'mt-excluir';
    var i = el('input'); i.id = 'mt-excluir'; i.type = 'text'; i.autocomplete = 'off'; i.setAttribute('autocapitalize', 'characters'); i.setAttribute('data-foco', ''); i.setAttribute('aria-describedby', 'mt-excluir-erro');
    var erro = el('p', 'mt-conta-erro'); erro.id = 'mt-excluir-erro'; erro.setAttribute('role', 'alert');
    var b = el('button', 'mt-btn mt-conta-apagar', 'Excluir minha conta'); b.type = 'submit';
    f.appendChild(l); f.appendChild(i); f.appendChild(erro); f.appendChild(b);
    f.onsubmit = async function (e) {
      e.preventDefault(); erro.textContent = '';
      if (i.value !== 'EXCLUIR') { erro.textContent = 'Digite EXCLUIR, em maiúsculas, para confirmar.'; i.setAttribute('aria-invalid', 'true'); i.focus(); return; }
      b.disabled = true; b.textContent = 'Excluindo…';
      var r; try { r = await sb.functions.invoke('excluir-conta', { body: { confirmacao: 'EXCLUIR' } }); } catch (x) { r = { error: x }; }
      if (r.error || !(r.data && r.data.ok)) { b.disabled = false; b.textContent = 'Excluir minha conta'; erro.textContent = 'Não deu para excluir agora. Nada foi apagado. Tente de novo.'; return; }
      try { await sb.auth.signOut({ scope: 'local' }); } catch (x) {}
      sessionStorage.removeItem(CODIGO); await ler(); tela = 'conta';
      avisar('Conta excluída. O login, o apelido e os resultados foram apagados.', 'ok'); mudou();
    };
    c.appendChild(f);
    c.appendChild(bt('mt-conta-texto', 'Voltar sem excluir', function () { ir('perfil'); }));
  }

  function linkPrivacidade(c) { var a = el('a', 'mt-conta-link', 'Como cuidamos dos seus dados'); a.href = cfg.privacidade; a.target = '_blank'; a.rel = 'noopener'; c.appendChild(a); }

  function mostrar(t, msg, tipo) {   // abre (ou troca) o painel já com a mensagem
    if (t) tela = t; aviso = msg || ''; avisoTipo = tipo || '';
    if (!painel.open) historico = null;   // o histórico é buscado de novo a cada abertura
    desenhar();
    if (!painel.open) { if (painel.showModal) painel.showModal(); else painel.setAttribute('open', ''); }
  }
  API.abrir = function (t) { API.pronto().then(function () { mostrar(t); }, function () {}); };
  botao.addEventListener('click', function () { API.abrir(sessao && !anonimo ? (perfil && perfil.apelido ? 'perfil' : 'apelido') : 'conta'); });

  // ---------- entrar e sair
  async function entrar() {
    if (ocupado) return; ocupado = true; avisar('Abrindo o Google…');
    try { if (typeof window.matutarAntesDeSair === 'function') window.matutarAntesDeSair(); } catch (e) {}   // o jogo guarda a partida
    var r;
    if (sessao && anonimo) {
      // prova de posse: só esta sessão sem conta consegue criar o código, e só esta aba o conhece
      try { var c = await rpc('criar_transferencia'); sessionStorage.setItem(CODIGO, c.codigo); } catch (e) { sessionStorage.removeItem(CODIGO); }
      sessionStorage.setItem(TENTOU, '1');
      r = await sb.auth.linkIdentity({ provider: 'google', options: { redirectTo: volta } });
    } else r = await sb.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: volta } });
    if (r.error) { ocupado = false; sessionStorage.removeItem(TENTOU); avisar('Não deu para abrir o Google. Nada mudou. Tente de novo.', 'erro'); }
  }
  async function sair() {
    try { await sb.auth.signOut(); } catch (e) {}
    sessionStorage.removeItem(CODIGO); await ler(); tela = 'conta';
    avisar('Você saiu. Seus resultados continuam na conta.', 'ok'); mudou();
  }
  async function resgatar(codigo) {
    try {
      var r = await rpc('reivindicar_transferencia', { p_codigo: codigo });
      if (r.mesma_conta || !r.itens.length) return '';
      var vieram = r.itens.filter(function (i) { return i.resultado === 'transferido'; }).length, conflito = r.itens.length - vieram;
      return [vieram ? (vieram === 1 ? '1 resultado deste aparelho foi salvo na sua conta.' : vieram + ' resultados deste aparelho foram salvos na sua conta.') : '',
              conflito ? 'Nos desafios que você já tinha jogado com esta conta, vale o resultado da conta.' : ''].filter(Boolean).join(' ');
    } catch (e) { return MSG[e.codigo] || 'Não deu para trazer os resultados deste aparelho. Eles não foram alterados.'; }
  }

  // ---------- início
  var haSessaoGuardada = false;
  try { haSessaoGuardada = !!localStorage.getItem('mt-conta-' + cfg.nome); } catch (e) {}
  var tentou = false; try { tentou = !!sessionStorage.getItem(TENTOU); } catch (e) {}
  if (erroVolta || voltouComCodigo || haSessaoGuardada || tentou) (async function () {
    try { await API.pronto(); } catch (e) { botao.hidden = true; return; }
    if (voltouComCodigo) history.replaceState(null, '', volta);
    desenhar();

    if (erroVolta) {
      var jaExiste = /identity_already_exists|already linked|already exists/i.test(erroVolta + ' ' + erroTexto);
      if (jaExiste && tentou && sessao && anonimo) {
        // o Google já tem conta: entra nela (o código de transferência continua guardado nesta aba)
        sessionStorage.removeItem(TENTOU);
        mostrar('conta', 'Você já tem conta. Entrando nela…');
        var o = await sb.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: volta } });
        if (o.error) avisar('Não deu para entrar. Nada mudou. Tente de novo.', 'erro');
        return;
      }
      sessionStorage.removeItem(TENTOU); sessionStorage.removeItem(CODIGO);
      mostrar('conta', /access_denied/i.test(erroVolta) ? 'Login cancelado. Nada mudou: você continua jogando sem conta.' : 'Não deu para entrar agora. Nada mudou: você continua jogando sem conta. Tente de novo.', /access_denied/i.test(erroVolta) ? '' : 'erro');
      return;
    }

    var codigo = sessionStorage.getItem(CODIGO);
    if (sessao && !anonimo && (voltouComCodigo || tentou)) {
      sessionStorage.removeItem(TENTOU);
      var msg = codigo ? await resgatar(codigo) : '';
      sessionStorage.removeItem(CODIGO);
      await ler(); mudou();
      mostrar(perfil && perfil.apelido ? 'perfil' : 'apelido', msg || 'Pronto, você entrou com o Google.', /Não deu|Demorou/.test(msg) ? 'erro' : 'ok');
    } else if (tentou && !voltouComCodigo) {
      // voltou pelo botão "voltar" do navegador, sem concluir o login: nada mudou
      sessionStorage.removeItem(TENTOU); sessionStorage.removeItem(CODIGO);
    }
  })();
  // página restaurada pelo navegador ao voltar (sem recarregar): destrava o botão
  window.addEventListener('pageshow', function (e) { if (e.persisted) { ocupado = false; try { sessionStorage.removeItem(TENTOU); sessionStorage.removeItem(CODIGO); } catch (x) {} if (painel.open) avisar(''); } });
})();
