-- Matutar Games · PROVA DE CONCEITO · remove tudo o que 001_poc_conta.sql criou (projeto matutar-teste).
drop function if exists public.poc_reivindicar_transferencia(text), public.poc_criar_transferencia(),
  public.poc_meus_resultados(), public.poc_jogar(date, int), public.poc_quem_sou(), public._poc_anonimo();
drop table if exists public.poc_transferencias, public.poc_resultados;
