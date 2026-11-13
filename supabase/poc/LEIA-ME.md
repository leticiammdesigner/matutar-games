# Prova de conceito: conta anônima e conta Google

Só para o projeto Supabase **matutar-teste**. Nada aqui é jogo nem vai para produção.

| Arquivo | Para quê |
|---|---|
| `001_poc_conta.sql` | Tabelas de mentira (`poc_resultados`, `poc_transferencias`) e as funções da transferência |
| `002_poc_testes.sql` | 16 casos automáticos. Cria usuários temporários, simula as sessões e apaga tudo no fim |
| `003_poc_remover.sql` | Remove a prova de conceito |
| `testar_local.mjs` | Roda os mesmos testes num Postgres local (PGlite), sem Supabase |
| `../../poc-conta/index.html` | Página de teste no navegador. Só funciona nas prévias, nunca no endereço oficial |

Regras demonstradas: uma tentativa válida por pessoa e desafio; código de transferência de uso único, só em hash, 15 minutos, criado por sessão anônima e resgatado por conta Google; em conflito vale o resultado da conta; tudo numa transação.
