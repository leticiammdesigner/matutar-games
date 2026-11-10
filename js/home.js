// Matutar Games · home. Só duas coisas: a data da folha e o botão de chamar alguém para jogar.

const folha = document.getElementById('folhaDoDia');
try {
  folha.textContent = 'Folha de ' + new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: 'short', timeZone: 'America/Sao_Paulo' }).format(new Date()).replace('.', '');
} catch { /* fica "Folha de hoje" */ }

const botao = document.getElementById('compartilhar');
const status = document.getElementById('statusCompartilhar');
const endereco = /^https?:$/.test(location.protocol) ? location.origin + '/' : '';
const texto = 'MATUTAR GAMES · Ideias que dão jogo.\nTrês jogos rápidos para jogar no celular.';

botao.addEventListener('click', async () => {
  status.textContent = '';
  if (navigator.share) {
    try { await navigator.share({ title: 'Matutar Games', text: texto, url: endereco || undefined }); return; }
    catch (e) { if (e && e.name === 'AbortError') return; }
  }
  try { await navigator.clipboard.writeText(endereco ? `${texto}\n${endereco}` : texto); status.textContent = 'Link copiado!'; }
  catch { status.textContent = endereco ? `Copie o link: ${endereco}` : 'Não deu para copiar o link.'; }
});
