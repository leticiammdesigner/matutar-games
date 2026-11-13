-- Matutar Games · base da plataforma: perfil, resultados e transferência de sessão sem conta.
-- Rodar no projeto matutar-teste. (Produção só depois de aprovado, com o mesmo arquivo.)
--
-- O navegador nunca lê nem escreve tabelas: só chama as funções do fim deste arquivo.
-- Nada de e-mail, nome ou foto do Google sai de auth.users. O perfil guarda só o apelido.
-- Participar do ranking começa DESLIGADO e só liga por um pedido explícito (com data do aceite).
-- Resultados só entram por funções internas de cada jogo (nunca pelo navegador).

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------- tabelas
create table if not exists public.perfis (
  id                  uuid primary key references auth.users(id) on delete cascade,
  apelido             text,
  apelido_chave       text unique,               -- minúsculas, sem espaços duplicados: "Ana  Lu" = "ana lu"
  apelido_trocado_em  timestamptz,
  ranking_publico     boolean not null default false,
  ranking_aceito_em   timestamptz,
  criado_em           timestamptz not null default now()
);

create table if not exists public.apelidos_reservados (
  chave text primary key                           -- comparado com apelido_chave; inclui palavras proibidas
);
insert into public.apelidos_reservados (chave) values
  ('matutar'), ('matutar games'), ('admin'), ('administrador'), ('moderador'), ('suporte'), ('equipe'), ('oficial')
on conflict do nothing;

create table if not exists public.resultados (
  id              uuid primary key default gen_random_uuid(),
  usuario_id      uuid not null references auth.users(id) on delete cascade,
  jogo            text not null check (jogo in ('qop', 'duelo', 'confia')),
  modo            text not null default 'diario' check (modo in ('diario')),
  desafio_data    date not null,
  pontos          int  not null,
  metrica         numeric,                        -- critério principal do jogo (ex.: erro no Qual o Preço?)
  situacao        text not null default 'valido' check (situacao in ('valido', 'descartado_conflito')),
  transferido_de  uuid,
  concluido_em    timestamptz not null default now()
);
-- uma tentativa válida por pessoa, jogo e desafio
create unique index if not exists resultados_uma_valida
  on public.resultados (usuario_id, jogo, desafio_data) where situacao = 'valido';

create table if not exists public.transferencias (
  id           uuid primary key default gen_random_uuid(),
  codigo_hash  text not null unique,
  origem       uuid not null references auth.users(id) on delete cascade,
  expira_em    timestamptz not null,
  usado_em     timestamptz,
  destino      uuid,
  criado_em    timestamptz not null default now()
);

alter table public.perfis              enable row level security;
alter table public.apelidos_reservados enable row level security;
alter table public.resultados          enable row level security;
alter table public.transferencias      enable row level security;
revoke all on public.perfis, public.apelidos_reservados, public.resultados, public.transferencias from anon, authenticated;

-- ---------------------------------------------------------------- funções internas (não expostas)
create or replace function public._eh_anonimo() returns boolean
language sql stable set search_path = '' as $$
  select coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false)
$$;

create or replace function public._exigir_conta() returns uuid
language plpgsql stable set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'sem_sessao'; end if;
  if public._eh_anonimo() then raise exception 'precisa_conta_google'; end if;
  return auth.uid();
end $$;

create or replace function public._chave_apelido(p text) returns text
language sql immutable set search_path = '' as $$
  select lower(regexp_replace(btrim(coalesce(p, '')), '\s+', ' ', 'g'))
$$;

-- usada pelas funções de cada jogo (ex.: qop_registrar_palpite) depois de validar a jogada no servidor
create or replace function public._registrar_resultado(p_usuario uuid, p_jogo text, p_data date, p_pontos int, p_metrica numeric)
returns public.resultados
language plpgsql security definer set search_path = '' as $$
declare r public.resultados;
begin
  insert into public.resultados (usuario_id, jogo, desafio_data, pontos, metrica)
  values (p_usuario, p_jogo, p_data, p_pontos, p_metrica)
  on conflict (usuario_id, jogo, desafio_data) where situacao = 'valido' do nothing;
  select * into r from public.resultados
   where usuario_id = p_usuario and jogo = p_jogo and desafio_data = p_data and situacao = 'valido';
  return r;
end $$;

-- ---------------------------------------------------------------- perfil e apelido
create or replace function public.meu_perfil() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare p public.perfis;
begin
  if auth.uid() is null then raise exception 'sem_sessao'; end if;
  select * into p from public.perfis where id = auth.uid();
  return jsonb_build_object(
    'anonimo', public._eh_anonimo(),
    'apelido', p.apelido,
    'ranking_publico', coalesce(p.ranking_publico, false),
    'pode_trocar_apelido_em', case when p.apelido_trocado_em is null then null else p.apelido_trocado_em + interval '30 days' end);
end $$;

create or replace function public.sugerir_apelido() returns text
language plpgsql volatile security definer set search_path = '' as $$
declare s text; i int := 0;
begin
  perform public._exigir_conta();
  loop
    s := 'Matutador ' || lpad((floor(random() * 10000))::int::text, 4, '0');
    exit when not exists (select 1 from public.perfis where apelido_chave = public._chave_apelido(s)) or i > 20;
    i := i + 1;
  end loop;
  return s;
end $$;

create or replace function public.definir_apelido(p_apelido text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := public._exigir_conta(); a text; k text; atual public.perfis;
begin
  a := regexp_replace(btrim(coalesce(p_apelido, '')), '\s+', ' ', 'g');
  k := public._chave_apelido(a);
  if char_length(a) < 3 or char_length(a) > 20 then raise exception 'apelido_tamanho'; end if;
  if a !~ '^[A-Za-zÀ-ÖØ-öø-ÿ0-9 ]+$' then raise exception 'apelido_caracteres'; end if;
  if exists (select 1 from public.apelidos_reservados r where k = r.chave or k like '%' || r.chave || '%') then
    raise exception 'apelido_nao_permitido';
  end if;

  select * into atual from public.perfis where id = uid for update;
  if found and atual.apelido_chave = k then
    update public.perfis set apelido = a where id = uid;      -- só mudou maiúscula/minúscula: não conta como troca
    return public.meu_perfil();
  end if;
  if found and atual.apelido_trocado_em is not null and atual.apelido_trocado_em > now() - interval '30 days' then
    raise exception 'apelido_troca_recente';
  end if;
  if exists (select 1 from public.perfis where apelido_chave = k and id <> uid) then raise exception 'apelido_em_uso'; end if;

  insert into public.perfis (id, apelido, apelido_chave, apelido_trocado_em)
  values (uid, a, k, null)
  on conflict (id) do update
     set apelido = excluded.apelido, apelido_chave = excluded.apelido_chave,
         apelido_trocado_em = case when public.perfis.apelido is null then null else now() end;
  return public.meu_perfil();
exception when unique_violation then
  raise exception 'apelido_em_uso';
end $$;

-- participar (ou sair) do ranking público. Ligar exige apelido e grava a data do aceite.
create or replace function public.definir_ranking_publico(p_participar boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := public._exigir_conta();
begin
  if p_participar is null then raise exception 'pedido_invalido'; end if;
  if p_participar and not exists (select 1 from public.perfis where id = uid and apelido is not null) then
    raise exception 'precisa_apelido';
  end if;
  update public.perfis
     set ranking_publico = p_participar,
         ranking_aceito_em = case when p_participar then now() else ranking_aceito_em end
   where id = uid;
  return public.meu_perfil();
end $$;

-- histórico privado: só desafios diários salvos no servidor (partidas livres ficam no aparelho)
create or replace function public.meu_historico(p_jogo text default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'sem_sessao'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('jogo', jogo, 'data', desafio_data, 'pontos', pontos, 'metrica', metrica,
                                        'veio_de_sessao_sem_conta', transferido_de is not null)
                     order by desafio_data desc)
      from public.resultados
     where usuario_id = auth.uid() and situacao = 'valido' and (p_jogo is null or jogo = p_jogo)), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------- transferência (mesmas regras da prova de conceito)
create or replace function public.criar_transferencia() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare codigo text;
begin
  if auth.uid() is null then raise exception 'sem_sessao'; end if;
  if not public._eh_anonimo() then raise exception 'so_sessao_anonima'; end if;
  codigo := translate(encode(extensions.gen_random_bytes(24), 'base64'), '+/', '-_');
  update public.transferencias set expira_em = least(expira_em, now()) where origem = auth.uid() and usado_em is null;
  insert into public.transferencias (codigo_hash, origem, expira_em)
  values (encode(extensions.digest(codigo, 'sha256'), 'hex'), auth.uid(), now() + interval '15 minutes');
  return jsonb_build_object('codigo', codigo, 'expira_em', now() + interval '15 minutes');
end $$;

create or replace function public.reivindicar_transferencia(p_codigo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := public._exigir_conta(); t public.transferencias; r public.resultados; itens jsonb := '[]'::jsonb; ainda_anonima boolean;
begin
  if p_codigo is null or length(p_codigo) < 20 then raise exception 'codigo_invalido'; end if;
  select * into t from public.transferencias where codigo_hash = encode(extensions.digest(p_codigo, 'sha256'), 'hex') for update;
  if not found then raise exception 'codigo_invalido'; end if;
  if t.usado_em is not null then raise exception 'codigo_ja_usado'; end if;
  if t.expira_em <= now() then raise exception 'codigo_expirado'; end if;

  if t.origem = uid then
    update public.transferencias set usado_em = now(), destino = uid where id = t.id;
    return jsonb_build_object('mesma_conta', true, 'itens', itens);
  end if;

  select u.is_anonymous into ainda_anonima from auth.users u where u.id = t.origem;
  if not coalesce(ainda_anonima, false) then raise exception 'origem_nao_anonima'; end if;

  perform pg_advisory_xact_lock(hashtextextended(uid::text, 0));
  for r in select * from public.resultados where usuario_id = t.origem and situacao = 'valido' order by jogo, desafio_data for update loop
    if exists (select 1 from public.resultados where usuario_id = uid and jogo = r.jogo and desafio_data = r.desafio_data and situacao = 'valido') then
      update public.resultados set situacao = 'descartado_conflito' where id = r.id;
      itens := itens || jsonb_build_object('jogo', r.jogo, 'data', r.desafio_data, 'resultado', 'conflito_vale_o_da_conta');
    else
      update public.resultados set usuario_id = uid, transferido_de = t.origem where id = r.id;
      itens := itens || jsonb_build_object('jogo', r.jogo, 'data', r.desafio_data, 'resultado', 'transferido');
    end if;
  end loop;
  update public.transferencias set usado_em = now(), destino = uid where id = t.id;
  return jsonb_build_object('mesma_conta', false, 'itens', itens);
end $$;

-- ---------------------------------------------------------------- permissões
revoke all on function public._eh_anonimo(), public._exigir_conta(), public._chave_apelido(text),
  public._registrar_resultado(uuid, text, date, int, numeric),
  public.meu_perfil(), public.sugerir_apelido(), public.definir_apelido(text), public.definir_ranking_publico(boolean),
  public.meu_historico(text), public.criar_transferencia(), public.reivindicar_transferencia(text)
  from public, anon, authenticated;
grant execute on function public.meu_perfil(), public.sugerir_apelido(), public.definir_apelido(text),
  public.definir_ranking_publico(boolean), public.meu_historico(text),
  public.criar_transferencia(), public.reivindicar_transferencia(text) to authenticated;
