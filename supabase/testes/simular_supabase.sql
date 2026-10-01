-- Só para testes locais: imita as peças que já existem no Supabase.
create role anon nologin; create role authenticated nologin;
create schema auth;
create table auth.users (id uuid primary key);
create function auth.uid() returns uuid language sql stable as
  $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth to anon, authenticated;
grant usage on schema public to anon, authenticated;
grant all on all tables in schema public to anon, authenticated;   -- o Supabase dá acesso amplo por padrão; nosso script precisa trancar
alter default privileges in schema public grant all on tables to anon, authenticated;
alter default privileges in schema public grant execute on functions to anon, authenticated;
insert into auth.users values ('11111111-1111-1111-1111-111111111111'), ('22222222-2222-2222-2222-222222222222'), ('33333333-3333-3333-3333-333333333333');
