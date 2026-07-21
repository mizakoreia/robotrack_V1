-- Papéis de banco do RoboTrack — tenant-isolation §"Papel de banco" / design D-11.
--
-- Dois papéis, ambos SEM SUPERUSER e SEM BYPASSRLS:
--   robotrack_migrator  → DDL, `db:migrate`, dono das tabelas de tenant
--   robotrack_app       → runtime (Puma, Sidekiq, Cable e a suíte rspec)
--
-- A app conecta como robotrack_app justamente para que a RLS seja avaliada: um
-- papel dono ou com BYPASSRLS tornaria a política decorativa e todo teste
-- negativo de tenancy seria teatro.
--
-- Idempotente. As senhas aqui são DEV-LOCAIS (mesmo precedente do `silas777`
-- já versionado em config/database.yml) — NÃO são um .env e NÃO valem para
-- staging/prod, onde as credenciais vêm de `delivery-and-observability`.
--
-- Uso (como superusuário, uma vez por banco):
--   psql -U robotrack_user -d robotrack_dev  -f db/roles.sql
--   psql -U robotrack_user -d robotrack_test -f db/roles.sql

-- === Papéis (globais ao cluster; a parte de LOGIN/senha só cria se faltar) ===
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'robotrack_migrator') THEN
    CREATE ROLE robotrack_migrator LOGIN PASSWORD 'mig_dev_pw';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'robotrack_app') THEN
    CREATE ROLE robotrack_app LOGIN PASSWORD 'app_dev_pw';
  END IF;
END
$$;

-- Garantia explícita e reafirmada a cada execução: nenhum contorno de RLS.
-- O migrator recebe CREATEDB para o rebuild limpo (`db:drop/create/schema:load`,
-- tarefa 6.5); o app NÃO — runtime nunca administra o ciclo de vida do banco.
ALTER ROLE robotrack_migrator NOSUPERUSER NOBYPASSRLS CREATEDB;
ALTER ROLE robotrack_app       NOSUPERUSER NOBYPASSRLS NOCREATEDB;

-- O migrator é dono dos bancos (dono do schema e das tabelas de tenant, para que
-- `FORCE ROW LEVEL SECURITY` também o vincule) e pode recriá-los. O app conecta
-- como não-dono, sujeito à RLS. Requer superusuário; idempotente.
ALTER DATABASE robotrack_dev  OWNER TO robotrack_migrator;
ALTER DATABASE robotrack_test OWNER TO robotrack_migrator;

-- === Extensões (exigem superusuário; pré-instaladas para as migrations do
--     migrator serem no-op idempotente em `enable_extension`) ===
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

-- === Privilégios no banco corrente ===
GRANT CREATE, USAGE ON SCHEMA public TO robotrack_migrator;
GRANT USAGE ON SCHEMA public TO robotrack_app;

-- Objetos JÁ existentes (tabelas do template + metadados do Rails).
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES    IN SCHEMA public TO robotrack_app;
GRANT USAGE, SELECT, UPDATE                     ON ALL SEQUENCES IN SCHEMA public TO robotrack_app;
-- REFERENCES: o migrator cria FKs de workspaces/people/memberships para `users`
-- (tabela do template, dona = robotrack_user no dev); criar a FK exige REFERENCES.
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES ON ALL TABLES    IN SCHEMA public TO robotrack_migrator;
GRANT USAGE, SELECT, UPDATE                                ON ALL SEQUENCES IN SCHEMA public TO robotrack_migrator;

-- Objetos FUTUROS criados pelo migrator: a app recebe DML automaticamente, sem
-- precisar re-rodar grants a cada migration. (O REVOKE de owner_user_id é feito
-- na migration 2.5, depois que `workspaces` existe.)
ALTER DEFAULT PRIVILEGES FOR ROLE robotrack_migrator IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON TABLES TO robotrack_app;
ALTER DEFAULT PRIVILEGES FOR ROLE robotrack_migrator IN SCHEMA public
  GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO robotrack_app;

-- === Posse de `users` (identity-and-auth): DDL do migrator exige ownership ===
-- `users` é do template (nasce do robotrack_user no dev). A partir desta onda o
-- migrator faz DDL nela (encrypted_password, CHECKs, índice de e-mail — 1.2/1.3),
-- e `ALTER TABLE` exige ser dono. `users` NÃO tem RLS, então o migrator ser dono
-- é inócuo para isolamento; `users` não tem sequence serial, então isso NÃO
-- afeta a truncation. Idempotente. Após a troca de dono, o app é RE-grantado
-- abaixo (o privilégio de dono era implícito e some com a posse).
DO $$
BEGIN
  IF to_regclass('public.users') IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.users OWNER TO robotrack_migrator';
  END IF;
END
$$;

GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES    IN SCHEMA public TO robotrack_app;
GRANT USAGE, SELECT, UPDATE                     ON ALL SEQUENCES IN SCHEMA public TO robotrack_app;

-- === Migrator faz DDL em tabela do app COMO MEMBRO do app (identity-and-auth) ===
-- `jwt_denylist` continua sendo do `robotrack_app` (a truncation de teste emite
-- `TRUNCATE ... RESTART IDENTITY`, hardcoded na 2.2.2, que exige posse da
-- sequence — e a sequence é "linked" à tabela, logo segue o dono). Mas o migrator
-- precisa trocar o índice de `jti` para único (1.2). Em Postgres, a checagem de
-- ownership passa se o papel corrente for MEMBRO do dono. Tornando o migrator
-- membro do app, o DDL sobre tabelas do app funciona sem transferir posse — e a
-- RLS não é tocada: o runtime continua sendo o `robotrack_app` (sem BYPASSRLS), e
-- a membership é migrator→app, não o contrário (app não ganha nada). Idempotente.
GRANT robotrack_app TO robotrack_migrator;

-- As tabelas não-tenant com coluna serial passam para o app, para que a
-- truncation de teste (TRUNCATE ... RESTART IDENTITY) reinicie a sequence. O
-- migrator, agora membro do app, ainda faz DDL nelas quando preciso (ex.: o
-- índice único de jti em jwt_denylist, 1.2). Tabelas de tenant usam uuid (sem
-- sequence) e ficam com o migrator (FORCE RLS + REVOKE de coluna dependem
-- disso). O filtro é genérico para pegar qualquer serial futura, sempre
-- excluindo as de tenant. Hoje só jwt_denylist se qualifica.
DO $$
DECLARE tbl text;
BEGIN
  FOR tbl IN
    SELECT DISTINCT t.relname
    FROM pg_class s
    JOIN pg_depend d    ON d.objid = s.oid AND d.deptype IN ('a', 'i')
    JOIN pg_class t     ON t.oid = d.refobjid AND t.relkind = 'r'
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE s.relkind = 'S'
      AND n.nspname = 'public'
      AND t.relname NOT IN ('workspaces', 'people', 'memberships')
  LOOP
    EXECUTE format('ALTER TABLE public.%I OWNER TO robotrack_app', tbl);
  END LOOP;
END
$$;

-- Imutabilidade do dono, camada de privilégio de coluna (§4.1 inv. 5). Precisa
-- morar AQUI, não só na migration: `pg_dump -x` (structure.sql) OMITE GRANT/
-- REVOKE, então um rebuild via `db:schema:load` (tarefa 6.5) nasceria com o app
-- podendo trocar o dono. Como o app teria UPDATE de TABELA (default privileges
-- acima), e privilégio de tabela + coluna é UNIÃO, revogamos o UPDATE de tabela
-- e reconcedemos só as colunas mutáveis. Guardado por existência: no G1 a tabela
-- ainda não existe. A trigger workspaces_owner_immutable (na migration, capturada
-- no structure.sql) cobre o path migrator/admin.
DO $$
BEGIN
  IF to_regclass('public.workspaces') IS NOT NULL THEN
    REVOKE UPDATE ON workspaces FROM robotrack_app;
    GRANT  UPDATE (name, updated_at) ON workspaces TO robotrack_app;
  END IF;
END
$$;

-- Snapshot de membership removida é APPEND-ONLY (workspace-invitations 4.2).
-- Mesmo argumento do bloco acima: `pg_dump -x` omite GRANT/REVOKE, então sem
-- isto um rebuild por `db:schema:load` nasceria com o runtime podendo reescrever
-- o próprio log que torna a remoção reversível. Guardado por existência.
DO $$
BEGIN
  IF to_regclass('public.membership_revocations') IS NOT NULL THEN
    REVOKE UPDATE, DELETE ON membership_revocations FROM robotrack_app;
  END IF;
END
$$;
