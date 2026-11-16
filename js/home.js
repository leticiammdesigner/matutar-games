// Matutar Games · home: só o botão de convidar.
const botao = document.getElementById('compartilhar');
const status = document.getElementById('status');
// Endereço fixo da home: prévias e testes locais não viram link compartilhado.
const endereco = 'https://matutar-games.netlify.app/';
const texto = 'Matutar Games · Ideias que dão jogo.\nTrês jogos para pensar, arriscar e se surpreender.';

botao.addEventListener('click', async () => {
  status.textContent = '';
  if (navigator.share) {
    try { await navigator.share({ title: 'Matutar Games', text: texto, url: endereco || undefined }); return; }
    catch (e) { if (e && e.name === 'AbortError') return; }
  }
  try { await navigator.clipboard.writeText(endereco ? `${texto}\n${endereco}` : texto); status.textContent = 'Link copiado!'; }
  catch { status.textContent = endereco ? `Copie o link: ${endereco}` : 'Não deu para copiar o link.'; }
});
