-- Matutar Games · PROVA DE CONCEITO: conta anônima -> conta Google, com transferência segura.
-- Rodar SOMENTE no projeto matutar-teste (SQL Editor). Nada aqui é de jogo: "pontos" são de mentira.
--
-- Regras demonstradas
-- * O navegador não lê nem escreve tabelas: só chama funções (security definer, search_path vazio).
-- * Um resultado válido por (pessoa, desafio): índice único parcial. Nunca há segunda tentativa válida.
-- * Transferência só com um código de uso único, guardado como hash, válido por 15 minutos,
--   criado por uma sessão anônima e resgatado por uma conta Google (não anônima).
-- * Conflito: vale o resultado que já estava na conta; o anônimo fica "descartado_conflito" (auditoria).
-- * Tudo numa transação: se algo falha, nada muda e o código continua válido até expirar.
--
-- Para desfazer a prova de conceito: rodar 003_poc_remover.sql.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.poc_resultados (
  id              uuid primary key default gen_random_uuid(),
  usuario_id      uuid not null references auth.users(id) on delete cascade,
  desafio         date not null,
  pontos          int  not null check (pontos between 0 and 100),
  situacao        text not null default 'valido' check (situacao in ('valido', 'descartado_conflito')),
  transferido_de  uuid,
  criado_em       timestamptz not null default now()
);
-- uma tentativa válida por pessoa e desafio
create unique index if not exists poc_resultados_um_valido
  on public.poc_resultados (usuario_id, desafio) where situacao = 'valido';

create table if not exists public.poc_transferencias (
  id           uuid primary key default gen_random_uuid(),
  codigo_hash  text not null unique,
  origem       uuid not null references auth.users(id) on delete cascade,
  expira_em    timestamptz not null,
  usado_em     timestamptz,
  destino      uuid,
  criado_em    timestamptz not null default now()
);

alter table public.poc_resultados     enable row level security;
alter table public.poc_transferencias enable row level security;
revoke all on public.poc_resultados, public.poc_transferencias from anon, authenticated;
-- sem políticas: nenhuma leitura ou escrita direta pelo navegador

create or replace function public._poc_anonimo() returns boolean
language sql stable set search_path = '' as $$
  select coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false)
$$;

-- quem é a sessão atual (sem e-mail, sem nome)
create or replace function public.poc_quem_sou() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'sem_sessao'; end if;
  return jsonb_build_object('id', auth.uid(), 'anonimo', public._poc_anonimo());
end $$;

-- "jogar" um desafio de mentira. Repetir devolve a tentativa que já existe.
create or replace function public.poc_jogar(p_desafio date, p_pontos int) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r public.poc_resultados;
begin
  if auth.uid() is null then raise exception 'sem_sessao'; end if;
  if p_desafio is null or p_pontos is null or p_pontos < 0 or p_pontos > 100 then raise exception 'jogada_invalida'; end if;
  insert into public.poc_resultados (usuario_id, desafio, pontos)
  values (auth.uid(), p_desafio, p_pontos)
  on conflict (usuario_id, desafio) where situacao = 'valido' do nothing;
  select * into r from public.poc_resultados
   where usuario_id = auth.uid() and desafio = p_desafio and situacao = 'valido';
  return jsonb_build_object('desafio', r.desafio, 'pontos', r.pontos, 'transferido_de', r.transferido_de);
end $$;

create or replace function public.poc_meus_resultados() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'sem_sessao'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('desafio', desafio, 'pontos', pontos, 'veio_de_outra_sessao', transferido_de is not null)
                     order by desafio)
      from public.poc_resultados where usuario_id = auth.uid() and situacao = 'valido'), '[]'::jsonb);
end $$;

-- sessão anônima pede um código de transferência (antes de ir para o Google)
create or replace function public.poc_criar_transferencia() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare codigo text;
begin
  if auth.uid() is null then raise exception 'sem_sessao'; end if;
  if not public._poc_anonimo() then raise exception 'so_sessao_anonima'; end if;
  codigo := translate(encode(extensions.gen_random_bytes(24), 'base64'), '+/', '-_');
  -- um código vivo por sessão anônima: os anteriores, ainda não usados, deixam de valer
  update public.poc_transferencias set expira_em = least(expira_em, now())
   where origem = auth.uid() and usado_em is null;
  insert into public.poc_transferencias (codigo_hash, origem, expira_em)
  values (encode(extensions.digest(codigo, 'sha256'), 'hex'), auth.uid(), now() + interval '15 minutes');
  return jsonb_build_object('codigo', codigo, 'expira_em', now() + interval '15 minutes');
end $$;

-- conta Google resgata o que a sessão anônima jogou
create or replace function public.poc_reivindicar_transferencia(p_codigo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare t public.poc_transferencias; r public.poc_resultados; itens jsonb := '[]'::jsonb; ainda_anonima boolean;
begin
  if auth.uid() is null then raise exception 'sem_sessao'; end if;
  if public._poc_anonimo() then raise exception 'precisa_conta_google'; end if;
  if p_codigo is null or length(p_codigo) < 20 then raise exception 'codigo_invalido'; end if;

  select * into t from public.poc_transferencias
   where codigo_hash = encode(extensions.digest(p_codigo, 'sha256'), 'hex')
   for update;
  if not found then raise exception 'codigo_invalido'; end if;
  if t.usado_em is not null then raise exception 'codigo_ja_usado'; end if;
  if t.expira_em <= now() then raise exception 'codigo_expirado'; end if;

  -- a própria sessão virou conta (linkIdentity deu certo): não há o que mover
  if t.origem = auth.uid() then
    update public.poc_transferencias set usado_em = now(), destino = auth.uid() where id = t.id;
    return jsonb_build_object('mesma_conta', true, 'itens', itens);
  end if;

  select u.is_anonymous into ainda_anonima from auth.users u where u.id = t.origem;
  if not coalesce(ainda_anonima, false) then raise exception 'origem_nao_anonima'; end if;

  -- uma transferência por vez para a mesma conta (evita corrida entre dois aparelhos)
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 0));

  for r in select * from public.poc_resultados
            where usuario_id = t.origem and situacao = 'valido' order by desafio for update loop
    if exists (select 1 from public.poc_resultados
                where usuario_id = auth.uid() and desafio = r.desafio and situacao = 'valido') then
      update public.poc_resultados set situacao = 'descartado_conflito' where id = r.id;
      itens := itens || jsonb_build_object('desafio', r.desafio, 'resultado', 'conflito_vale_o_da_conta');
    else
      update public.poc_resultados set usuario_id = auth.uid(), transferido_de = t.origem where id = r.id;
      itens := itens || jsonb_build_object('desafio', r.desafio, 'resultado', 'transferido');
    end if;
  end loop;

  update public.poc_transferencias set usado_em = now(), destino = auth.uid() where id = t.id;
  return jsonb_build_object('mesma_conta', false, 'itens', itens);
end $$;

revoke all on function public._poc_anonimo(), public.poc_quem_sou(), public.poc_jogar(date, int),
  public.poc_meus_resultados(), public.poc_criar_transferencia(), public.poc_reivindicar_transferencia(text)
  from public, anon;
grant execute on function public.poc_quem_sou(), public.poc_jogar(date, int), public.poc_meus_resultados(),
  public.poc_criar_transferencia(), public.poc_reivindicar_transferencia(text) to authenticated;
