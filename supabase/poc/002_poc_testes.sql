-- Matutar Games · PROVA DE CONCEITO · testes automáticos da transferência.
-- Rodar no SQL Editor do projeto matutar-teste DEPOIS de 001_poc_conta.sql.
-- Cria usuários de teste temporários, simula as sessões (anônima e Google) e apaga tudo no fim.
-- O resultado é uma tabela: cada linha é um caso, com "ok" verdadeiro ou falso.

create temp table if not exists poc_teste (n serial, caso text, ok boolean, detalhe text);
truncate poc_teste;
grant all on poc_teste to authenticated, anon;
grant usage, select on sequence poc_teste_n_seq to authenticated, anon;

do $teste$
declare
  a uuid := gen_random_uuid();  -- anônima que joga e depois entra numa conta Google existente
  b uuid := gen_random_uuid();  -- anônima para os casos de código
  c uuid := gen_random_uuid();  -- anônima que vira conta Google nova (linkIdentity)
  d uuid := gen_random_uuid();  -- anônima convertida por outro caminho
  g uuid := gen_random_uuid();  -- conta Google que já existe
  h uuid := gen_random_uuid();  -- outra conta Google
  dia1 date := date '2026-11-10';
  dia2 date := date '2026-11-11';
  c1 text; c2 text; c4 text; c5 text; c6 text; c7 text; j jsonb; n int; erro text;
begin
  insert into auth.users (id, instance_id, aud, role, is_anonymous, email) values
    (a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', true,  null),
    (b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', true,  null),
    (c, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', true,  null),
    (d, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', true,  null),
    (g, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', false, 'poc-g-' || g || '@teste.invalid'),
    (h, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', false, 'poc-h-' || h || '@teste.invalid');

  -- 1. uma tentativa por desafio
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated', 'is_anonymous', true)::text, true);
  execute 'set local role authenticated';
  perform public.poc_jogar(dia1, 50);
  perform public.poc_jogar(dia2, 60);
  j := public.poc_jogar(dia1, 99);
  insert into poc_teste (caso, ok, detalhe) values
    ('1. repetir o mesmo desafio devolve a primeira tentativa', (j->>'pontos')::int = 50, j::text);

  -- 2. conta Google existente já tem o desafio do dia 2
  perform set_config('request.jwt.claims', json_build_object('sub', g, 'role', 'authenticated', 'is_anonymous', false)::text, true);
  perform public.poc_jogar(dia2, 70);

  -- 3. anônima cria código, conta existente resgata: dia 1 vem, dia 2 é conflito e vale o da conta
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated', 'is_anonymous', true)::text, true);
  c1 := public.poc_criar_transferencia() ->> 'codigo';
  perform set_config('request.jwt.claims', json_build_object('sub', g, 'role', 'authenticated', 'is_anonymous', false)::text, true);
  j := public.poc_reivindicar_transferencia(c1);
  insert into poc_teste (caso, ok, detalhe) values
    ('3a. conta existente: desafio sem conflito é transferido',
      j->'itens' @> jsonb_build_array(jsonb_build_object('desafio', dia1, 'resultado', 'transferido')), j::text),
    ('3b. conta existente: no conflito vale o resultado da conta',
      j->'itens' @> jsonb_build_array(jsonb_build_object('desafio', dia2, 'resultado', 'conflito_vale_o_da_conta')), j::text);
  j := public.poc_meus_resultados();
  insert into poc_teste (caso, ok, detalhe) values
    ('3c. a conta ficou com dia 1 = 50 e dia 2 = 70 (o dela), sem duplicar',
      jsonb_array_length(j) = 2 and (j->0->>'pontos')::int = 50 and (j->1->>'pontos')::int = 70, j::text);

  -- 4. o mesmo código não serve duas vezes
  begin
    perform public.poc_reivindicar_transferencia(c1);
    insert into poc_teste (caso, ok, detalhe) values ('4. código usado não serve de novo', false, 'aceitou');
  exception when others then
    insert into poc_teste (caso, ok, detalhe) values ('4. código usado não serve de novo', sqlerrm = 'codigo_ja_usado', sqlerrm);
  end;

  -- 5. código expirado
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated', 'is_anonymous', true)::text, true);
  perform public.poc_jogar(dia1, 30);
  c2 := public.poc_criar_transferencia() ->> 'codigo';
  execute 'reset role';
  update public.poc_transferencias set expira_em = now() - interval '1 minute' where origem = b;
  perform set_config('request.jwt.claims', json_build_object('sub', h, 'role', 'authenticated', 'is_anonymous', false)::text, true);
  execute 'set local role authenticated';
  begin
    perform public.poc_reivindicar_transferencia(c2);
    insert into poc_teste (caso, ok, detalhe) values ('5. código expirado é recusado e nada se move', false, 'aceitou');
  exception when others then
    insert into poc_teste (caso, ok, detalhe) values ('5. código expirado é recusado e nada se move', sqlerrm = 'codigo_expirado', sqlerrm);
  end;
  j := public.poc_meus_resultados();
  insert into poc_teste (caso, ok, detalhe) values ('5b. a outra conta continua sem resultados', jsonb_array_length(j) = 0, j::text);

  -- 6. sessão anônima não pode resgatar
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated', 'is_anonymous', true)::text, true);
  c4 := public.poc_criar_transferencia() ->> 'codigo';
  begin
    perform public.poc_reivindicar_transferencia(c4);
    insert into poc_teste (caso, ok, detalhe) values ('6. sessão anônima não resgata código', false, 'aceitou');
  exception when others then
    insert into poc_teste (caso, ok, detalhe) values ('6. sessão anônima não resgata código', sqlerrm = 'precisa_conta_google', sqlerrm);
  end;

  -- 7. só o código mais novo de cada sessão vale
  c5 := public.poc_criar_transferencia() ->> 'codigo';
  perform set_config('request.jwt.claims', json_build_object('sub', h, 'role', 'authenticated', 'is_anonymous', false)::text, true);
  begin
    perform public.poc_reivindicar_transferencia(c4);
    insert into poc_teste (caso, ok, detalhe) values ('7. código antigo deixa de valer quando sai um novo', false, 'aceitou');
  exception when others then
    insert into poc_teste (caso, ok, detalhe) values ('7. código antigo deixa de valer quando sai um novo', sqlerrm = 'codigo_expirado', sqlerrm);
  end;

  -- 8. código inventado
  begin
    perform public.poc_reivindicar_transferencia('codigo-inventado-que-nao-existe-0000');
    insert into poc_teste (caso, ok, detalhe) values ('8. código inventado é recusado', false, 'aceitou');
  exception when others then
    insert into poc_teste (caso, ok, detalhe) values ('8. código inventado é recusado', sqlerrm = 'codigo_invalido', sqlerrm);
  end;

  -- 9. conta Google não cria código (só a sessão anônima cria)
  begin
    perform public.poc_criar_transferencia();
    insert into poc_teste (caso, ok, detalhe) values ('9. conta Google não cria código de transferência', false, 'aceitou');
  exception when others then
    insert into poc_teste (caso, ok, detalhe) values ('9. conta Google não cria código de transferência', sqlerrm = 'so_sessao_anonima', sqlerrm);
  end;

  -- 10. anônima vira conta Google nova (linkIdentity): mesma pessoa, nada a mover
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated', 'is_anonymous', true)::text, true);
  perform public.poc_jogar(dia1, 40);
  c6 := public.poc_criar_transferencia() ->> 'codigo';
  execute 'reset role';
  update auth.users set is_anonymous = false, email = 'poc-c-' || c || '@teste.invalid' where id = c;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated', 'is_anonymous', false)::text, true);
  execute 'set local role authenticated';
  j := public.poc_reivindicar_transferencia(c6);
  insert into poc_teste (caso, ok, detalhe) values ('10a. conta nova: a própria sessão vira conta, sem mover nada', (j->>'mesma_conta')::boolean, j::text);
  j := public.poc_meus_resultados();
  insert into poc_teste (caso, ok, detalhe) values ('10b. conta nova mantém o resultado jogado sem conta',
    jsonb_array_length(j) = 1 and (j->0->>'pontos')::int = 40, j::text);

  -- 11. código de uma sessão que já não é anônima não pode ser levado para outra conta
  perform set_config('request.jwt.claims', json_build_object('sub', d, 'role', 'authenticated', 'is_anonymous', true)::text, true);
  perform public.poc_jogar(dia1, 20);
  c7 := public.poc_criar_transferencia() ->> 'codigo';
  execute 'reset role';
  update auth.users set is_anonymous = false where id = d;
  perform set_config('request.jwt.claims', json_build_object('sub', g, 'role', 'authenticated', 'is_anonymous', false)::text, true);
  execute 'set local role authenticated';
  begin
    perform public.poc_reivindicar_transferencia(c7);
    insert into poc_teste (caso, ok, detalhe) values ('11. outra conta não leva resultados de quem já virou conta', false, 'aceitou');
  exception when others then
    insert into poc_teste (caso, ok, detalhe) values ('11. outra conta não leva resultados de quem já virou conta', sqlerrm = 'origem_nao_anonima', sqlerrm);
  end;

  -- 12. o navegador não lê tabelas diretamente
  begin
    execute 'select count(*) from public.poc_resultados' into n;
    insert into poc_teste (caso, ok, detalhe) values ('12. sessão não lê a tabela de resultados direto', false, 'leu ' || n);
  exception when insufficient_privilege then
    insert into poc_teste (caso, ok, detalhe) values ('12. sessão não lê a tabela de resultados direto', true, sqlerrm);
  end;

  -- 13. sem sessão (papel anon) não chama as funções
  execute 'reset role';
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
  begin
    perform public.poc_jogar(dia1, 10);
    insert into poc_teste (caso, ok, detalhe) values ('13. sem sessão não joga', false, 'aceitou');
  exception when insufficient_privilege then
    insert into poc_teste (caso, ok, detalhe) values ('13. sem sessão não joga', true, sqlerrm);
  end;

  -- 14. o banco recusa uma segunda tentativa válida, mesmo escrevendo direto como administrador
  execute 'reset role';
  begin
    insert into public.poc_resultados (usuario_id, desafio, pontos) values (g, dia1, 99);
    insert into poc_teste (caso, ok, detalhe) values ('14. índice único barra segunda tentativa válida', false, 'aceitou');
  exception when unique_violation then
    insert into poc_teste (caso, ok, detalhe) values ('14. índice único barra segunda tentativa válida', true, sqlerrm);
  end;

  -- 15. em nenhum momento alguém ficou com duas tentativas válidas no mesmo desafio
  select count(*) into n from (
    select usuario_id, desafio from public.poc_resultados where situacao = 'valido'
     group by 1, 2 having count(*) > 1) x;
  insert into poc_teste (caso, ok, detalhe) values ('15. nenhuma pessoa com duas tentativas válidas no mesmo desafio', n = 0, n || ' duplicadas');

  -- 16. o resultado anônimo em conflito ficou guardado como descartado (auditoria), fora dos válidos
  select count(*) into n from public.poc_resultados where usuario_id = a and desafio = dia2 and situacao = 'descartado_conflito';
  insert into poc_teste (caso, ok, detalhe) values ('16. o anônimo em conflito fica como descartado, sem valer', n = 1, n::text);

  -- limpeza: apaga os usuários de teste (resultados e códigos vão junto)
  delete from auth.users where id in (a, b, c, d, g, h);
end
$teste$;

select n, caso, ok, detalhe from poc_teste order by n;
