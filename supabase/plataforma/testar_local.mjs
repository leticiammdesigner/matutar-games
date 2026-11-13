// Uso: npm i @electric-sql/pglite@0.2.17 && node supabase/plataforma/testar_local.mjs supabase/plataforma 010_base.sql,011_base_testes.sql
// O PGlite não traz o pgcrypto: abaixo há substitutos com a mesma assinatura, só para este teste local.
// Roda o SQL da prova de conceito num Postgres local (PGlite) com um "auth" mínimo parecido com o do Supabase.
import { PGlite } from '@electric-sql/pglite';
import fs from 'fs';
const dir = process.argv[2];
const db = new PGlite();
await db.exec(`
create role anon nologin; create role authenticated nologin;
create schema auth; create schema extensions;
grant usage on schema auth, extensions, public to anon, authenticated;
create table auth.users (id uuid primary key, instance_id uuid, aud text, role text, email text, is_anonymous boolean not null default false);
create function auth.jwt() returns jsonb language sql stable as $$ select nullif(current_setting('request.jwt.claims', true), '')::jsonb $$;
create function auth.uid() returns uuid language sql stable as $$ select (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')::uuid $$;
grant execute on function auth.jwt(), auth.uid() to anon, authenticated;
-- substitutos do pgcrypto (o PGlite não traz): mesma assinatura usada no SQL
create function extensions.gen_random_bytes(n int) returns bytea language sql volatile as $$ select substring(decode(replace(gen_random_uuid()::text||gen_random_uuid()::text,'-',''),'hex') from 1 for n) $$;
create function extensions.digest(t text, alg text) returns bytea language sql immutable as $$ select sha256(convert_to(t,'UTF8')) $$;
`);
const [esq, tes] = (process.argv[3] || '001_poc_conta.sql,002_poc_testes.sql').split(',');
await db.exec(fs.readFileSync(dir + '/' + esq, 'utf8').replace(/create extension[^;]*;/, ''));
const r = await db.exec(fs.readFileSync(dir + '/' + tes, 'utf8'));
const rows = r.at(-1).rows;
for (const x of rows) console.log((x.ok ? 'OK    ' : 'FALHA ') + x.caso + (x.ok ? '' : '  · ' + x.detalhe));
console.log(rows.filter(x => x.ok).length + ' de ' + rows.length + ' OK');
const sobra = await db.query('select count(*) u from auth.users');
console.log('usuários sobrando:', sobra.rows[0].u);
