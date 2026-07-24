-- Papéis REAIS de staging (fidelidade a delivery-and-observability / design D-11).
-- Roda UMA vez, na init do volume do Postgres (docker-entrypoint-initdb.d), como
-- superusuário, contra robotrack_staging. `docker compose down -v` limpa o volume,
-- então o smoke reexecuta isto a cada rodada.
--
-- Antes o compose subia o Postgres com POSTGRES_USER: robotrack_app, e a imagem
-- oficial cria esse papel como SUPERUSUÁRIO. Resultado: o runtime conectava como
-- dono/superusuário, a camada 1 (REVOKE) ficava inerte e o guard de imutabilidade
-- (corretamente) abortava o worker — e abortaria o web também, se o guard não
-- estivesse quebrado (BUG 10 + BUG 11). Aqui os papéis são os de produção:
--   robotrack_migrator  → DDL/migrations, dono do banco e das tabelas de tenant
--   robotrack_app       → runtime (Puma/Sidekiq), NÃO-superusuário, sujeito à RLS
-- ambos SEM SUPERUSER e SEM BYPASSRLS.

CREATE ROLE robotrack_migrator LOGIN PASSWORD 'mig_staging_pw' NOSUPERUSER NOBYPASSRLS CREATEDB;
CREATE ROLE robotrack_app      LOGIN PASSWORD 'app_staging_pw' NOSUPERUSER NOBYPASSRLS;

-- O migrator é dono do banco e do schema: as migrations rodam como ele e as tabelas
-- de tenant nascem com dono não-superusuário, para `FORCE ROW LEVEL SECURITY` valer.
ALTER DATABASE robotrack_staging OWNER TO robotrack_migrator;
GRANT ALL   ON SCHEMA public TO robotrack_migrator;
GRANT USAGE ON SCHEMA public TO robotrack_app;

-- Extensões exigem superusuário; pré-instaladas para o `enable_extension` das
-- migrations ser no-op idempotente.
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

-- Privilégios DEFAULT: toda tabela/sequence FUTURA criada pelo migrator (durante o
-- migrate) concede DML ao app automaticamente — o app opera sob RLS sem ser dono,
-- sem re-rodar grants a cada migration. Os REVOKE append-only (audit_logs,
-- task_advances, ...) vêm DEPOIS do migrate (append_only_revokes.sql), quando as
-- tabelas já existem; sem eles o app teria UPDATE por atacado e o guard abortaria.
ALTER DEFAULT PRIVILEGES FOR ROLE robotrack_migrator IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON TABLES TO robotrack_app;
ALTER DEFAULT PRIVILEGES FOR ROLE robotrack_migrator IN SCHEMA public
  GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO robotrack_app;
