# Base da plataforma (contas e resultados)

Primeiro no projeto **matutar-teste**. Produção só depois de aprovado.

| Arquivo | Para quê |
|---|---|
| `010_base.sql` | `perfis` (apelido, participação no ranking desligada por padrão), `resultados` (uma tentativa válida por pessoa, jogo e desafio), `transferencias` e as funções que o navegador pode chamar |
| `011_base_testes.sql` | 24 casos automáticos, com usuários temporários apagados no fim |
| `testar_local.mjs` | Os mesmos testes num Postgres local (PGlite) |

O que fica onde: partidas livres continuam só no aparelho. Aqui entram só desafios diários, registrados por funções do servidor de cada jogo (`_registrar_resultado`, que o navegador não chama).

## Como o SQL de cada jogo se encaixa

A base não sabe nada das mecânicas. Cada jogo tem o seu arquivo e, depois de validar a jogada no servidor, chama
`public._registrar_resultado(auth.uid(), '<jogo>', data, pontos, metrica)`. Só por aí um resultado entra em `public.resultados`,
que é o que alimenta histórico, transferência e ranking.

Se o jogo guarda a jogada numa tabela própria, ela precisa de:

- chave estrangeira para `auth.users` com `on delete cascade`, senão excluir a conta deixa registros órfãos;
- um gatilho em `public.resultados` que faça a jogada acompanhar a troca de dono e sair das comparações quando o resultado
  for marcado como `descartado_conflito`.

Exemplo completo, com ranking do dia: `qual-o-preco`, `supabase/002_conta_e_ranking.sql`, branch `feat/contas-mobile-e2e`.
