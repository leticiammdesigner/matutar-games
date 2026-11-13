# Base da plataforma (contas e resultados)

Primeiro no projeto **matutar-teste**. Produção só depois de aprovado.

| Arquivo | Para quê |
|---|---|
| `010_base.sql` | `perfis` (apelido, participação no ranking desligada por padrão), `resultados` (uma tentativa válida por pessoa, jogo e desafio), `transferencias` e as funções que o navegador pode chamar |
| `011_base_testes.sql` | 24 casos automáticos, com usuários temporários apagados no fim |
| `testar_local.mjs` | Os mesmos testes num Postgres local (PGlite) |

O que fica onde: partidas livres continuam só no aparelho. Aqui entram só desafios diários, registrados por funções do servidor de cada jogo (`_registrar_resultado`, que o navegador não chama).
