# Como ligar o ranking online do Mano Miau

Tempo estimado: 30 a 40 minutos, uma única vez.
Os nomes dos menus do Supabase e do Google mudam de vez em quando; se algo não estiver
exatamente onde o guia diz, procure pelo nome parecido.

---

## Parte A · Criar o projeto no Supabase

1. Acesse **supabase.com**, crie uma conta (pode entrar com o GitHub) e clique em **New project**.
2. Preencha:
   - **Name:** `mano-miau`
   - **Database password:** gere uma senha forte e **guarde num lugar seguro**. Você quase nunca vai usá-la, mas não dá para recuperar.
   - **Region:** South America (São Paulo), a mais perto dos seus amigos.
3. Clique em **Create new project** e espere uns 2 minutos até o painel ficar pronto.

## Parte B · Criar o banco do ranking

1. No menu lateral, abra **SQL Editor** e clique em **New query**.
2. Abra o arquivo `supabase/schema.sql`, copie **tudo** e cole no editor.
3. Clique em **Run**. Deve aparecer *Success. No rows returned*.
4. Confira em **Table Editor**: devem existir as tabelas `jogadores`, `partidas` e `palavroes`.

> Pode rodar o script de novo sem medo: ele não apaga nada que já existe.

## Parte C · Login com Google

Aqui são duas telas conversando: o Supabase e o Google Cloud.

**C1. Pegue o endereço de retorno no Supabase**
1. Menu **Authentication** → **Sign In / Providers** (ou **Providers**) → **Google**.
2. Copie o **Callback URL**. Ele tem este formato: `https://SEU-PROJETO.supabase.co/auth/v1/callback`.
   Deixe essa aba aberta.

**C2. Crie a credencial no Google Cloud**
1. Acesse **console.cloud.google.com** e crie um projeto chamado `Mano Miau`.
2. Abra **Google Auth Platform** (em algumas contas aparece como **APIs e serviços → Tela de consentimento OAuth**):
   - **Nome do app:** Mano Miau
   - **E-mail de suporte:** o seu
   - **Público (Audience):** Externo
3. Ainda em Audience, o app começa em modo **Teste**: só entra quem estiver na lista de **usuários de teste**.
   Você tem duas opções:
   - adicionar o e-mail Gmail de cada amigo como usuário de teste; ou
   - clicar em **Publicar app**. Como o jogo só pede nome e e-mail básicos, não é preciso verificação do Google.
4. Vá em **Clientes** (ou **Credenciais → Criar credenciais → ID do cliente OAuth**):
   - **Tipo:** Aplicativo da Web
   - **Origens JavaScript autorizadas:** `https://lucasileckdossantos.github.io`
   - **URIs de redirecionamento autorizados:** cole o **Callback URL** do passo C1
5. Clique em **Criar** e copie o **ID do cliente** e a **Chave secreta do cliente**.

**C3. Volte ao Supabase**
1. Na tela do provedor **Google**, ative a opção, cole o **Client ID** e o **Client Secret** e salve.

## Parte D · Dizer ao Supabase onde o jogo mora

1. **Authentication** → **URL Configuration**.
2. **Site URL:** `https://lucasileckdossantos.github.io/Jogo-Mano-Miau/`
3. Em **Redirect URLs**, adicione o mesmo endereço e salve.

> Sem isso, depois do login o Google não sabe para onde devolver o jogador.

## Parte E · Colocar as chaves no jogo

1. No Supabase, abra **Project Settings** → **API** (ou **API Keys**).
2. Copie:
   - **Project URL**
   - a chave pública: **anon public** (em projetos novos pode aparecer como **publishable key**, começando com `sb_publishable_`; ela serve igual)
3. No `index.html`, procure o bloco `const SUPABASE = {` e preencha:

```js
const SUPABASE = {
  url: "https://SEU-PROJETO.supabase.co",
  chaveAnon: "COLE-A-CHAVE-PUBLICA-AQUI",
};
```

> ⚠️ **Nunca** coloque a chave **service_role** (ou **secret key**) no jogo. Ela ignora todas as
> regras de segurança, e qualquer pessoa que abrir o site consegue lê-la.
> A chave pública pode aparecer no código sem problema: quem protege os dados são as regras do banco.

## Parte F · Publicar e testar

1. Faça o commit e o push (veja o README). Espere o GitHub Pages atualizar.
2. Abra **o link do GitHub Pages** (o login não funciona abrindo o arquivo direto do computador).
3. Clique em **Entrar com Google**, escolha um apelido e jogue uma partida.
4. No Supabase, abra **Table Editor → partidas**: sua partida deve estar lá com status `aceita`.

## Parte G · Manutenção

**Adicionar palavras proibidas** (SQL Editor):

```sql
insert into public.palavroes (termo, modo) values ('palavra', 'contem') on conflict do nothing;
```

Use `'inteiro'` para palavras curtas que aparecem dentro de nomes normais (ex.: `cu` dentro de `lucas`).

**Ajustar o anti-trapaça:** o teto fica na função `finalizar_partida` do `schema.sql`
(`300 + 30 * dur`). Os testes mostraram que um jogador perfeito faz até uns R$ 13 por segundo.

**Ver recusas:** no Table Editor, filtre `partidas` por `status = recusada` e veja a coluna `motivo`.

---

## Se algo der errado

| O que aparece | Causa provável |
|---|---|
| "Ranking online indisponível" no menu | Chaves da Parte E vazias ou erradas |
| Erro `redirect_uri_mismatch` do Google | O URI de redirecionamento no Google não é igual ao Callback URL do Supabase |
| "Acesso bloqueado: o app está em teste" | O e-mail do amigo não está nos usuários de teste, ou o app não foi publicado |
| Depois do login, volta para a página errada | Site URL ou Redirect URLs da Parte D |
| Ranking não carrega, mas o menu mostra a conta | Rode o `schema.sql` de novo e confira se terminou com sucesso |
