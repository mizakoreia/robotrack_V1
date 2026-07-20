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
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES    IN SCHEMA public TO robotrack_migrator;
GRANT USAGE, SELECT, UPDATE                     ON ALL SEQUENCES IN SCHEMA public TO robotrack_migrator;

-- Objetos FUTUROS criados pelo migrator: a app recebe DML automaticamente, sem
-- precisar re-rodar grants a cada migration. (O REVOKE de owner_user_id é feito
-- na migration 2.5, depois que `workspaces` existe.)
ALTER DEFAULT PRIVILEGES FOR ROLE robotrack_migrator IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON TABLES TO robotrack_app;
ALTER DEFAULT PRIVILEGES FOR ROLE robotrack_migrator IN SCHEMA public
  GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO robotrack_app;

-- O DatabaseCleaner emite `TRUNCATE ... RESTART IDENTITY` (hardcoded na
-- truncation 2.2.2). Reiniciar a sequence de uma coluna serial exige ser dono
-- dela, e o dono da sequence acompanha o dono da TABELA (a sequence é "linked").
-- A truncation é obrigatória sob RLS (um `DELETE` sem contexto de tenant apaga
-- zero linhas). Tabelas de tenant usam uuid (sem sequence) e ficam com o
-- migrator (FORCE RLS + REVOKE de coluna dependem disso). As não-tenant com
-- coluna serial passam para o app, para que a truncation de teste as reinicie.
-- Hoje só jwt_denylist se qualifica; o filtro é genérico para pegar qualquer
-- serial futura, sempre excluindo as tabelas de tenant.
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
