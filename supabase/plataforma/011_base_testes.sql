-- Matutar Games · testes de 010_base.sql (rodar no SQL Editor do matutar-teste, depois do 010).
-- Cria usuários temporários, simula as sessões e apaga tudo no fim. Cada linha é um caso.
-- Se o editor perguntar sobre RLS na tabela temporária "base_teste", escolha "Run without RLS".

create temp table if not exists base_teste (n serial, caso text, ok boolean, detalhe text);
truncate base_teste;
grant all on base_teste to authenticated, anon;
grant usage, select on sequence base_teste_n_seq to authenticated, anon;

do $teste$
declare
  g uuid := gen_random_uuid();   -- conta Google
  h uuid := gen_random_uuid();   -- outra conta Google
  a uuid := gen_random_uuid();   -- sessão sem conta
  b uuid := gen_random_uuid();   -- sessão sem conta
  d1 date := date '2026-11-10'; d2 date := date '2026-11-11';
  j jsonb; n int; c text;
begin
  insert into auth.users (id, instance_id, aud, role, is_anonymous, email) values
    (g, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', false, 'base-g-' || g || '@teste.invalid'),
    (h, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', false, 'base-h-' || h || '@teste.invalid'),
    (a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', true, null),
    (b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', true, null);

  -- ---------- apelido
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated', 'is_anonymous', true)::text, true);
  execute 'set local role authenticated';
  begin
    perform public.definir_apelido('Sem Conta');
    insert into base_teste (caso, ok, detalhe) values ('1. sessão sem conta não escolhe apelido', false, 'aceitou');
  exception when others then
    insert into base_teste (caso, ok, detalhe) values ('1. sessão sem conta não escolhe apelido', sqlerrm = 'precisa_conta_google', sqlerrm);
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', g, 'role', 'authenticated', 'is_anonymous', false)::text, true);
  j := public.meu_perfil();
  insert into base_teste (caso, ok, detalhe) values ('2. conta nova começa sem apelido e FORA do ranking',
    j->>'apelido' is null and (j->>'ranking_publico')::boolean = false, j::text);

  c := public.sugerir_apelido();
  insert into base_teste (caso, ok, detalhe) values ('3. sugestão de apelido no formato Matutador 0000', c ~ '^Matutador [0-9]{4}$', c);

  j := public.definir_apelido('  Ana   Lu  ');
  insert into base_teste (caso, ok, detalhe) values ('4. apelido sem espaços sobrando e ainda fora do ranking',
    j->>'apelido' = 'Ana Lu' and (j->>'ranking_publico')::boolean = false, j::text);

  perform set_config('request.jwt.claims', json_build_object('sub', h, 'role', 'authenticated', 'is_anonymous', false)::text, true);
  begin
    perform public.definir_apelido('ANA lu');
    insert into base_teste (caso, ok, detalhe) values ('5. apelido repetido (sem diferenciar maiúsculas) é recusado', false, 'aceitou');
  exception when others then
    insert into base_teste (caso, ok, detalhe) values ('5. apelido repetido (sem diferenciar maiúsculas) é recusado', sqlerrm = 'apelido_em_uso', sqlerrm);
  end;
  begin
    perform public.definir_apelido('ab');
    insert into base_teste (caso, ok, detalhe) values ('6. apelido curto demais é recusado', false, 'aceitou');
  exception when others then
    insert into base_teste (caso, ok, detalhe) values ('6. apelido curto demais é recusado', sqlerrm = 'apelido_tamanho', sqlerrm);
  end;
  begin
    perform public.definir_apelido('<script>');
    insert into base_teste (caso, ok, detalhe) values ('7. apelido com símbolos é recusado', false, 'aceitou');
  exception when others then
    insert into base_teste (caso, ok, detalhe) values ('7. apelido com símbolos é recusado', sqlerrm = 'apelido_caracteres', sqlerrm);
  end;
  begin
    perform public.definir_apelido('Equipe Matutar');
    insert into base_teste (caso, ok, detalhe) values ('8. apelido reservado é recusado', false, 'aceitou');
  exception when others then
    insert into base_teste (caso, ok, detalhe) values ('8. apelido reservado é recusado', sqlerrm = 'apelido_nao_permitido', sqlerrm);
  end;
  j := public.definir_apelido('João Ávila 7');
  insert into base_teste (caso, ok, detalhe) values ('9. apelido com acento e número é aceito', j->>'apelido' = 'João Ávila 7', j::text);

  -- troca: a primeira troca é livre (corrigir digitação); depois, uma a cada 30 dias
  perform set_config('request.jwt.claims', json_build_object('sub', g, 'role', 'authenticated', 'is_anonymous', false)::text, true);
  j := public.definir_apelido('Ana Luiza');
  insert into base_teste (caso, ok, detalhe) values ('10. primeira troca de apelido é livre', j->>'apelido' = 'Ana Luiza', j::text);
  begin
    perform public.definir_apelido('Ana L');
    insert into base_teste (caso, ok, detalhe) values ('11. segunda troca em menos de 30 dias é recusada', false, 'aceitou');
  exception when others then
    insert into base_teste (caso, ok, detalhe) values ('11. segunda troca em menos de 30 dias é recusada', sqlerrm = 'apelido_troca_recente', sqlerrm);
  end;
  j := public.definir_apelido('ana luiza');
  insert into base_teste (caso, ok, detalhe) values ('12. mudar só maiúsculas não conta como troca', j->>'apelido' = 'ana luiza', j::text);

  -- ---------- ranking público: só com pedido explícito
  perform set_config('request.jwt.claims', json_build_object('sub', h, 'role', 'authenticated', 'is_anonymous', false)::text, true);
  execute 'reset role';
  delete from public.perfis where id = h;          -- h volta a não ter apelido
  execute 'set local role authenticated';
  begin
    perform public.definir_ranking_publico(true);
    insert into base_teste (caso, ok, detalhe) values ('13. sem apelido não entra no ranking', false, 'aceitou');
  exception when others then
    insert into base_teste (caso, ok, detalhe) values ('13. sem apelido não entra no ranking', sqlerrm = 'precisa_apelido', sqlerrm);
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', g, 'role', 'authenticated', 'is_anonymous', false)::text, true);
  j := public.definir_ranking_publico(true);
  execute 'reset role';
  select count(*) into n from public.perfis where id = g and ranking_publico and ranking_aceito_em is not null;
  execute 'set local role authenticated';
  insert into base_teste (caso, ok, detalhe) values ('14. aceitar o ranking liga e grava a data do aceite', n = 1 and (j->>'ranking_publico')::boolean, j::text);
  j := public.definir_ranking_publico(false);
  insert into base_teste (caso, ok, detalhe) values ('15. sair do ranking desliga na hora', (j->>'ranking_publico')::boolean = false, j::text);

  -- ---------- resultados e histórico
  execute 'reset role';
  perform public._registrar_resultado(a, 'qop', d1, 80, 0.05);
  perform public._registrar_resultado(a, 'qop', d2, 60, 0.20);
  perform public._registrar_resultado(g, 'qop', d2, 90, 0.01);
  perform public._registrar_resultado(g, 'qop', d2, 10, 0.90);   -- segunda tentativa no mesmo desafio
  select count(*) into n from public.resultados where usuario_id = g and jogo = 'qop' and desafio_data = d2 and situacao = 'valido';
  insert into base_teste (caso, ok, detalhe) values ('16. segunda tentativa no mesmo desafio não entra', n = 1, n::text);
  select pontos into n from public.resultados where usuario_id = g and jogo = 'qop' and desafio_data = d2 and situacao = 'valido';
  insert into base_teste (caso, ok, detalhe) values ('17. vale a primeira tentativa', n = 90, n::text);

  -- o navegador não registra resultado direto
  perform set_config('request.jwt.claims', json_build_object('sub', g, 'role', 'authenticated', 'is_anonymous', false)::text, true);
  execute 'set local role authenticated';
  begin
    perform public._registrar_resultado(g, 'qop', date '2026-11-12', 100, 0);
    insert into base_teste (caso, ok, detalhe) values ('18. navegador não registra resultado direto', false, 'aceitou');
  exception when insufficient_privilege then
    insert into base_teste (caso, ok, detalhe) values ('18. navegador não registra resultado direto', true, sqlerrm);
  end;
  begin
    execute 'select count(*) from public.perfis' into n;
    insert into base_teste (caso, ok, detalhe) values ('19. navegador não lê perfis direto', false, 'leu ' || n);
  exception when insufficient_privilege then
    insert into base_teste (caso, ok, detalhe) values ('19. navegador não lê perfis direto', true, sqlerrm);
  end;

  -- ---------- transferência no formato definitivo
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated', 'is_anonymous', true)::text, true);
  c := public.criar_transferencia() ->> 'codigo';
  perform set_config('request.jwt.claims', json_build_object('sub', g, 'role', 'authenticated', 'is_anonymous', false)::text, true);
  j := public.reivindicar_transferencia(c);
  insert into base_teste (caso, ok, detalhe) values ('20. transferência: data nova vem, conflito mantém o da conta',
    j->'itens' @> jsonb_build_array(jsonb_build_object('jogo', 'qop', 'data', d1, 'resultado', 'transferido'),
                                    jsonb_build_object('jogo', 'qop', 'data', d2, 'resultado', 'conflito_vale_o_da_conta')), j::text);
  j := public.meu_historico('qop');
  insert into base_teste (caso, ok, detalhe) values ('21. histórico da conta: 2 datas, d2 com 90 (o da conta)',
    jsonb_array_length(j) = 2 and (j->0->>'pontos')::int = 90 and (j->1->>'pontos')::int = 80
    and (j->1->>'veio_de_sessao_sem_conta')::boolean, j::text);
  begin
    perform public.reivindicar_transferencia(c);
    insert into base_teste (caso, ok, detalhe) values ('22. código usado não serve de novo', false, 'aceitou');
  exception when others then
    insert into base_teste (caso, ok, detalhe) values ('22. código usado não serve de novo', sqlerrm = 'codigo_ja_usado', sqlerrm);
  end;
  -- código vencido
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated', 'is_anonymous', true)::text, true);
  c := public.criar_transferencia() ->> 'codigo';
  execute 'reset role';
  update public.transferencias set expira_em = now() - interval '1 minute' where origem = b;
  perform set_config('request.jwt.claims', json_build_object('sub', h, 'role', 'authenticated', 'is_anonymous', false)::text, true);
  execute 'set local role authenticated';
  begin
    perform public.reivindicar_transferencia(c);
    insert into base_teste (caso, ok, detalhe) values ('23. código vencido é recusado', false, 'aceitou');
  exception when others then
    insert into base_teste (caso, ok, detalhe) values ('23. código vencido é recusado', sqlerrm = 'codigo_expirado', sqlerrm);
  end;

  -- ---------- excluir conta: apagar o usuário leva perfil, resultados e códigos junto
  execute 'reset role';
  delete from auth.users where id = g;
  select (select count(*) from public.perfis where id = g) + (select count(*) from public.resultados where usuario_id = g) into n;
  insert into base_teste (caso, ok, detalhe) values ('24. excluir a conta apaga perfil e resultados', n = 0, n || ' sobras');

  delete from auth.users where id in (h, a, b);
end
$teste$;

select n, caso, ok, detalhe from base_teste order by n;
