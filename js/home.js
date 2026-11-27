// Matutar Games · home: só o botão de convidar.
const botao = document.getElementById('compartilhar');
const status = document.getElementById('status');
// Endereço fixo da home: prévias e testes locais não viram link compartilhado.
const endereco = 'https://matutargames.com.br/';
const texto = 'Matutar Games · Ideias que dão jogo.\nJogos para despertar a curiosidade, testar suas ideias e se surpreender.';

// Medir só depois que deu certo: clicar e desistir no menu do aparelho não é convite feito.
const medir = (nome) => { try { window.medir && window.medir(nome); } catch { /* medição nunca atrapalha */ } };

botao.addEventListener('click', async () => {
  status.textContent = '';
  if (navigator.share) {
    try { await navigator.share({ title: 'Matutar Games', text: texto, url: endereco || undefined }); medir('hub-convida'); return; }
    catch (e) { if (e && e.name === 'AbortError') return; }
  }
  try {
    await navigator.clipboard.writeText(endereco ? `${texto}\n${endereco}` : texto);
    status.textContent = 'Link copiado!';
    medir('hub-convida');
  }
  catch { status.textContent = endereco ? `Copie o link: ${endereco}` : 'Não deu para copiar o link.'; }
});
