# Mano Miau — Foge do Don Larápio

**Jogue agora:** https://lucasileckdossantos.github.io/Jogo-Mano-Miau/

Jogo 2D de corrida infinita, em pixel art, que roda direto no navegador.

O cofre do Cassino Miau explodiu e o dinheiro voou pela cidade inteira. Agora o Mano Miau
precisa recolher tudo antes que o Don Larápio o alcance.
O Mano Miau corre por uma rua antiga juntando dinheiro enquanto foge do Don Larápio.

## Como jogar

Abra o arquivo `index.html` em qualquer navegador.

- **Computador:** setas ← → para andar, ↑ ou espaço para pular, P para pausar, M para som
- **Celular:** botões na tela

## Regras

- A velocidade e a quantidade de obstáculos aumentam com o tempo.
- Moedas e notas valem de R$ 1 a R$ 100. Quanto maior a nota, mais arriscado pegar.
- Cada tropeço tira o dinheiro ganho nos últimos 30 segundos e aproxima o Don Larápio.
- Ficando um tempo sem tropeçar, o Don Larápio fica para trás.
- Com 5 tropeços acumulados, o Don Larápio pega o tigre e a partida acaba.
- A barraca de moedas dá um bônus de R$ 30.
- O recorde fica salvo no navegador.
- Entrando com a conta Google, sua melhor pontuação disputa o **ranking geral** com todos os jogadores.

## Ranking online (Supabase)

O ranking usa o [Supabase](https://supabase.com) como backend. Para configurar o seu, siga o
**[CONFIGURAR_RANKING.md](CONFIGURAR_RANKING.md)**. Sem configuração, o jogo funciona normalmente, só sem ranking.

Como a segurança funciona:
- O jogo **nunca escreve direto nas tabelas**: elas ficam trancadas (Row Level Security sem políticas).
- Toda escrita passa por funções no servidor (`supabase/schema.sql`) que conferem as regras.
- Cada partida recebe um "bilhete" no servidor ao começar e só pode ser fechada uma vez.
- A pontuação precisa ser compatível com o tempo real de jogo (teto de R$ 300 + R$ 30 por segundo).
- Limite de 6 partidas por minuto por jogador.
- Apelidos únicos, de 3 a 16 caracteres, com filtro de palavrões no servidor.

Os testes do banco estão em `supabase/testes/` e rodam em qualquer PostgreSQL.

## Ajustes de dificuldade

Os números de balanceamento ficam no bloco `CONFIG`, no início do script em `index.html`.

## Versões

- **v1** — Primeira versão jogável.
- **v2** — Visual novo: rua antiga com neon, personagens maiores, obstáculos de rua (hidrante, lixeira, caixote de feira, carro antigo), pôster na tela inicial e contagem regressiva.
- **v3** — Intro com a história do Cassino Miau (4 cenas), sons e música estilo arcade, barraca de moedas bônus, rabo animado, óculos pretos, nova contagem e sem carros como obstáculo.
- **v4** — Login com Google, apelidos com filtro, ranking geral completo e proteção contra trapaça no servidor.

Projeto de estudo da disciplina Engenharia 2.0, desenvolvido com agente de IA
seguindo o fluxo: história → respostas → implementação → testes → revisão → commit.
