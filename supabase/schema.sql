-- =====================================================================
--  MANO MIAU v4 — Banco do ranking (Supabase / PostgreSQL)
--  Como usar: no painel do Supabase, abra "SQL Editor", cole este
--  arquivo inteiro e clique em "Run". Pode rodar de novo sem problema.
--
--  Princípio de segurança: o jogo NUNCA escreve direto nas tabelas.
--  As tabelas ficam trancadas (RLS sem políticas) e todas as escritas
--  passam por funções que conferem as regras no servidor.
-- =====================================================================

-- ---------- Tabelas ----------

-- Um jogador por conta Google. O id é o mesmo do login do Supabase.
create table if not exists public.jogadores (
  id        uuid primary key references auth.users (id) on delete cascade,
  apelido   text not null check (apelido ~ '^[A-Za-z0-9_]{3,16}$'),
  criado_em timestamptz not null default now()
);
-- Apelido único sem diferenciar maiúsculas: "Lucas" e "lucas" são o mesmo.
create unique index if not exists jogadores_apelido_unico on public.jogadores (lower(apelido));

-- Cada partida ganha um "bilhete" quando começa e é fechada uma única vez.
create table if not exists public.partidas (
  id         uuid primary key default gen_random_uuid(),
  jogador_id uuid not null references public.jogadores (id) on delete cascade,
  inicio     timestamptz not null default now(),
  fim        timestamptz,
  pontuacao  integer,
  status     text not null default 'aberta' check (status in ('aberta', 'aceita', 'recusada')),
  motivo     text
);
create index if not exists partidas_jogador_idx on public.partidas (jogador_id, inicio desc);
create index if not exists partidas_aceitas_idx on public.partidas (jogador_id, pontuacao desc) where status = 'aceita';

-- Lista de palavras proibidas em apelidos.
--   modo 'contem'  = bloqueia se a palavra aparecer em qualquer parte do apelido
--   modo 'inteiro' = bloqueia só se for uma "parte inteira" (entre _ ou o apelido todo).
--                    Serve para palavras curtas que aparecem dentro de nomes normais
--                    (ex.: "cu" está dentro de "lucas").
create table if not exists public.palavroes (
  termo text primary key,
  modo  text not null default 'contem' check (modo in ('contem', 'inteiro'))
);

-- ---------- Segurança: tranca tudo ----------
alter table public.jogadores enable row level security;
alter table public.partidas  enable row level security;
alter table public.palavroes enable row level security;
-- Sem nenhuma política criada, ninguém lê nem escreve direto nas tabelas.
revoke all on public.jogadores, public.partidas, public.palavroes from anon, authenticated;

-- ---------- Funções auxiliares (internas) ----------

-- Normaliza para comparar: minúsculas, desfaz disfarces (4→a, 0→o...),
-- remove "_" e junta letras repetidas ("merdaaa" → "merda").
create or replace function public.normalizar_texto(t text) returns text
language sql immutable set search_path = public as $$
  select regexp_replace(translate(lower(t), '4@31057$_', 'aaeiosts'), '(.)\1+', '\1', 'g');
$$;

create or replace function public.contem_palavrao(t text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from palavroes p
    where (p.modo = 'contem'  and position(normalizar_texto(p.termo) in normalizar_texto(t)) > 0)
       or (p.modo = 'inteiro' and normalizar_texto(p.termo) in (
             select normalizar_texto(parte) from regexp_split_to_table(t, '_') as parte
             union select normalizar_texto(t)))
  );
$$;

-- ---------- Funções que o jogo pode chamar ----------

-- Retorna o perfil de quem está logado (ou null se ainda não escolheu apelido).
create or replace function public.meu_perfil() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'apelido', j.apelido,
    'melhor', (select max(pontuacao) from partidas where jogador_id = j.id and status = 'aceita'))
  from jogadores j where j.id = auth.uid();
$$;

-- Cria ou troca o apelido, aplicando todas as regras no servidor.
create or replace function public.definir_apelido(p_apelido text) returns json
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    return json_build_object('ok', false, 'erro', 'sem_login');
  end if;
  p_apelido := btrim(coalesce(p_apelido, ''));
  if p_apelido !~ '^[A-Za-z0-9_]{3,16}$' then
    return json_build_object('ok', false, 'erro', 'formato');
  end if;
  if contem_palavrao(p_apelido) then
    return json_build_object('ok', false, 'erro', 'proibido');
  end if;
  begin
    insert into jogadores (id, apelido) values (uid, p_apelido)
    on conflict (id) do update set apelido = excluded.apelido;
  exception when unique_violation then
    return json_build_object('ok', false, 'erro', 'em_uso');
  end;
  return json_build_object('ok', true, 'apelido', p_apelido);
end;
$$;

-- Abre o "bilhete" de uma partida. O relógio que vale é o do servidor.
create or replace function public.iniciar_partida() returns json
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  recentes int;
  novo uuid;
begin
  if uid is null or not exists (select 1 from jogadores where id = uid) then
    return json_build_object('ok', false, 'erro', 'sem_cadastro');
  end if;
  -- Bilhetes esquecidos há mais de 2 horas são descartados.
  update partidas set status = 'recusada', motivo = 'abandonada'
   where jogador_id = uid and status = 'aberta' and inicio < now() - interval '2 hours';
  -- Limite: no máximo 6 partidas por minuto por jogador.
  select count(*) into recentes from partidas where jogador_id = uid and inicio > now() - interval '1 minute';
  if recentes >= 6 then
    return json_build_object('ok', false, 'erro', 'muitas_partidas');
  end if;
  insert into partidas (jogador_id) values (uid) returning id into novo;
  return json_build_object('ok', true, 'id', novo);
end;
$$;

-- Fecha a partida e decide se a pontuação é aceita.
-- TETO DE PLAUSIBILIDADE: ninguém junta mais que 300 + 30 reais por segundo.
-- (Jogando perfeito, a média real fica bem abaixo de 15 reais por segundo.)
create or replace function public.finalizar_partida(p_id uuid, p_pontuacao integer) returns json
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  p partidas%rowtype;
  dur numeric;
  v_motivo text;
  v_melhor int;
  v_pos int;
  v_total int;
begin
  if uid is null then
    return json_build_object('ok', false, 'erro', 'sem_login');
  end if;
  select * into p from partidas where id = p_id and jogador_id = uid for update;
  if not found then
    return json_build_object('ok', false, 'erro', 'partida_invalida');
  end if;
  if p.status <> 'aberta' then
    return json_build_object('ok', false, 'erro', 'partida_ja_finalizada');
  end if;

  dur := extract(epoch from now() - p.inicio);
  if p_pontuacao is null or p_pontuacao < 0 then v_motivo := 'pontuacao_invalida';
  elsif dur > 7200 then v_motivo := 'partida_expirada';
  elsif p_pontuacao > 300 + 30 * dur then v_motivo := 'pontuacao_impossivel';
  end if;

  update partidas
     set fim = now(), pontuacao = p_pontuacao, motivo = v_motivo,
         status = case when v_motivo is null then 'aceita' else 'recusada' end
   where id = p_id;

  select max(pontuacao) into v_melhor from partidas where jogador_id = uid and status = 'aceita';
  select count(distinct jogador_id) into v_total from partidas where status = 'aceita';
  if v_melhor is not null then
    select 1 + count(*) into v_pos from (
      select jogador_id, max(pontuacao) m from partidas where status = 'aceita' group by jogador_id) r
     where r.m > v_melhor;
  end if;

  return json_build_object('ok', true, 'aceita', v_motivo is null, 'motivo', v_motivo,
                           'melhor', v_melhor, 'posicao', v_pos, 'total', v_total);
end;
$$;

-- O ranking completo: todo mundo que já tem pontuação aceita.
create or replace function public.obter_ranking()
returns table (posicao bigint, apelido text, melhor integer, eu boolean)
language sql stable security definer set search_path = public as $$
  select rank() over (order by max(p.pontuacao) desc) as posicao,
         j.apelido,
         max(p.pontuacao)::int as melhor,
         coalesce(j.id = auth.uid(), false) as eu
    from partidas p join jogadores j on j.id = p.jogador_id
   where p.status = 'aceita'
   group by j.id, j.apelido
   order by melhor desc, lower(j.apelido);
$$;

-- ---------- Quem pode chamar o quê ----------
revoke execute on function public.normalizar_texto(text), public.contem_palavrao(text),
  public.meu_perfil(), public.definir_apelido(text), public.iniciar_partida(),
  public.finalizar_partida(uuid, integer), public.obter_ranking()
  from public, anon, authenticated;

grant execute on function public.obter_ranking() to anon, authenticated;   -- visitantes também veem o ranking
grant execute on function public.meu_perfil(), public.definir_apelido(text),
  public.iniciar_partida(), public.finalizar_partida(uuid, integer) to authenticated;

-- ---------- Lista inicial de palavras proibidas ----------
-- Complete com as criatividades da sua galera:
--   insert into public.palavroes (termo, modo) values ('palavra', 'contem') on conflict do nothing;
insert into public.palavroes (termo, modo) values
  ('merda','contem'), ('porra','contem'), ('caralho','contem'), ('buceta','contem'), ('boceta','contem'),
  ('foder','contem'), ('foda','contem'), ('putaria','contem'), ('puta','inteiro'), ('puto','inteiro'),
  ('fdp','contem'), ('pqp','contem'), ('vsf','inteiro'), ('krl','inteiro'), ('crl','inteiro'),
  ('cacete','contem'), ('arrombado','contem'), ('arrombada','contem'), ('otario','contem'), ('babaca','contem'),
  ('piroca','contem'), ('punheta','contem'), ('xoxota','contem'), ('bosta','contem'), ('corno','contem'),
  ('vagabunda','contem'), ('vagabundo','contem'), ('vadia','contem'), ('cuzao','contem'), ('cu','inteiro'),
  ('pau','inteiro'), ('rola','inteiro'), ('viado','contem'), ('bicha','inteiro'), ('retardado','contem'),
  ('nazi','contem'), ('hitler','contem'), ('estupro','contem'), ('pedofilo','contem'), ('bct','inteiro')
on conflict (termo) do nothing;
