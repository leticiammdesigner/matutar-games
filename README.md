# Matutar Games · home

*Ideias que dão jogo.* Página inicial do hub: um almanaque de jogos com os três jogos do lançamento e acesso direto a cada um.

## Rodar
Site estático, sem build. Localmente: `python3 -m http.server 8000` na raiz e abrir http://localhost:8000.
Netlify publica a raiz do repositório (`netlify.toml`).

## Jogos e endereços
Cada jogo tem repositório e publicação próprios. A home só aponta para eles. Só entram links de endereços confirmados.

| Nº | Jogo | Repositório | Endereço | Situação |
|---|---|---|---|---|
| 1 | Duelo de Palavras | a confirmar | a confirmar | card sem link, com "Link de publicação em confirmação" |
| 2 | Qual o Preço? | `leticiammdesigner/qual-o-preco` | https://qualopreco.netlify.app | no ar com a versão da `main` |
| 3 | Confia? | `leticiammdesigner/confia` | https://confia-matutar.netlify.app | v1.0 da Partida Rápida |

Para ligar um jogo: em `index.html`, trocar o bloco `.em-confirmacao` do card por
`<a class="btn btn-principal jogar" href="ENDEREÇO">Jogar NOME</a>`.

## Identidade
- Base compartilhada: `css/matutar-base.css` (mesma cópia usada no Confia?): papel creme, tinta preta, traço de 3px, grão, botões.
- Home: `css/home.css`. Cada card usa a cor-dupla e a fonte de voz do jogo, conforme a direção de arte aprovada: Duelo azul × coral em Anybody; Qual o Preço? sol × musgo em Bowlby One; Confia? lilás × coral em Bungee.
- Fontes locais em `assets/fontes/` (Fontsource, licença SIL OFL 1.1).

## Depois que a home estiver no ar
- No Confia?, preencher `URL_HUB` em `js/config.js` com o endereço confirmado da home, para a marca MATUTAR GAMES do topo levar de volta para cá.
- Fazer o mesmo no Qual o Preço? e no Duelo de Palavras quando cada um tiver esse ajuste.

## Fora do escopo do lançamento
Sem contas, ranking, sequência de dias, anúncios ou coleta de dados. O quarto jogo (Brasil de Onde?) entra numa atualização futura.
