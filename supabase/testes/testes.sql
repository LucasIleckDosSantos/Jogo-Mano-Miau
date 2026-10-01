\set ON_ERROR_STOP off
\pset format unaligned
\pset tuples_only on
create or replace function pg_temp.ok(nome text, cond boolean) returns text language sql as
  $$ select case when cond then '✅ ' else '❌ ' end || nome $$;

-- ===== Jogador 1 (Lucas) =====
set role authenticated; set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select pg_temp.ok('apelido válido aceito', (definir_apelido('Lucas_01')->>'ok')::bool);
select pg_temp.ok('formato inválido (2 letras)', definir_apelido('ab')->>'erro' = 'formato');
select pg_temp.ok('formato inválido (acento)', definir_apelido('João')->>'erro' = 'formato');
select pg_temp.ok('palavrão disfarçado c4r4lh0 bloqueado', definir_apelido('c4r4lh0')->>'erro' = 'proibido');
select pg_temp.ok('palavrão com letras repetidas bloqueado', definir_apelido('Merdaaa')->>'erro' = 'proibido');
select pg_temp.ok('"cu" como parte inteira bloqueado', definir_apelido('o_cu')->>'erro' = 'proibido');
reset role;
select pg_temp.ok('"lucas" não é falso positivo de "cu"', not contem_palavrao('lucas'));
select pg_temp.ok('"computador" não é falso positivo de "puta"', not contem_palavrao('computador'));
select pg_temp.ok('"Paulo" não é falso positivo de "pau"', not contem_palavrao('Paulo'));
set role authenticated;
do $$ begin
  begin perform contem_palavrao('x'); raise notice '❌ jogador não deveria chamar função interna';
  exception when insufficient_privilege then raise notice '✅ função interna de palavrões não é exposta ao jogo'; end;
end $$;
select pg_temp.ok('Lucas mantém o apelido Lucas_01', meu_perfil()->>'apelido' = 'Lucas_01');

-- ===== Jogador 2 =====
set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select pg_temp.ok('apelido repetido (maiúsc./minúsc.) recusado', definir_apelido('LUCAS_01')->>'erro' = 'em_uso');
select pg_temp.ok('jogador 2 pega outro apelido', (definir_apelido('Fominha')->>'ok')::bool);

-- ===== Acesso direto às tabelas (tentativa de trapaça) =====
do $$ begin
  begin perform 1 from partidas; raise notice '❌ jogador leu a tabela de partidas';
  exception when insufficient_privilege then raise notice '✅ ler a tabela de partidas direto é bloqueado'; end;
end $$;
do $$ begin
  begin insert into partidas (jogador_id, status, pontuacao) values ('22222222-2222-2222-2222-222222222222', 'aceita', 999999);
        raise notice '❌ inserção direta deveria falhar';
  exception when others then raise notice '✅ inserir pontuação direto na tabela é bloqueado (%)', sqlstate; end;
end $$;

-- ===== Partida normal do jogador 2 =====
select (iniciar_partida()->>'id') as p2a \gset
reset role; update partidas set inicio = now() - interval '60 seconds' where id = :'p2a'; set role authenticated;
select pg_temp.ok('partida plausível aceita (R$ 800 em 60 s)', (finalizar_partida(:'p2a', 800)->>'aceita')::bool);
select pg_temp.ok('fechar a mesma partida de novo é recusado', finalizar_partida(:'p2a', 5000)->>'erro' = 'partida_ja_finalizada');

-- ===== Pontuação impossível =====
select (iniciar_partida()->>'id') as p2b \gset
reset role; update partidas set inicio = now() - interval '20 seconds' where id = :'p2b'; set role authenticated;
select pg_temp.ok('R$ 5.000 em 20 s é recusado como impossível', finalizar_partida(:'p2b', 5000)->>'motivo' = 'pontuacao_impossivel');

-- ===== Jogador 1 tenta fechar a partida do jogador 2 =====
select (iniciar_partida()->>'id') as p2c \gset
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select pg_temp.ok('não dá para fechar a partida de outro jogador', finalizar_partida(:'p2c', 10)->>'erro' = 'partida_invalida');
select (iniciar_partida()->>'id') as p1a \gset
reset role; update partidas set inicio = now() - interval '120 seconds' where id = :'p1a'; set role authenticated;
select finalizar_partida(:'p1a', 1500) as r1 \gset
select pg_temp.ok('Lucas faz R$ 1.500 em 120 s', (:'r1'::json->>'aceita')::bool);
select pg_temp.ok('resposta traz posição 1 de 2', :'r1'::json->>'posicao' = '1' and :'r1'::json->>'total' = '2');

-- ===== Limite de partidas por minuto =====
set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select pg_temp.ok('7ª partida no mesmo minuto é bloqueada',
  (select bool_or(iniciar_partida()->>'erro' = 'muitas_partidas') from generate_series(1, 6)));

-- ===== Ranking =====
select pg_temp.ok('ranking em ordem: Lucas_01 1º, Fominha 2º',
  (select string_agg(posicao || ':' || apelido, ',' order by posicao) from obter_ranking()) = '1:Lucas_01,2:Fominha');
select pg_temp.ok('ranking marca "eu" no jogador logado', (select eu from obter_ranking() where apelido = 'Fominha'));
select pg_temp.ok('a partida recusada (R$ 5.000) não entrou no ranking', (select max(melhor) from obter_ranking()) = 1500);

-- ===== Jogador 3 logado, sem apelido =====
set request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select pg_temp.ok('sem apelido não consegue iniciar partida', iniciar_partida()->>'erro' = 'sem_cadastro');

-- ===== Visitante (sem login) =====
reset role; set role anon; reset request.jwt.claim.sub;
select pg_temp.ok('visitante vê o ranking', (select count(*) from obter_ranking()) = 2);
do $$ begin
  begin perform iniciar_partida(); raise notice '❌ visitante não deveria iniciar partida';
  exception when insufficient_privilege then raise notice '✅ visitante não pode iniciar partida (sem permissão)'; end;
end $$;
do $$ begin
  begin perform 1 from jogadores; raise notice '❌ visitante leu a tabela de jogadores';
  exception when insufficient_privilege then raise notice '✅ visitante não lê a tabela de jogadores'; end;
end $$;
