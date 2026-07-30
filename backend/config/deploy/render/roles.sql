-- Reconciliação de papéis para o Postgres GERENCIADO do Render.
--
-- Roda no START do backend web (`bin/render-web-start`), DEPOIS do `bin/release`
-- (migrate) — o plano free do Render não suporta preDeployCommand, então o release
-- foldou na inicialização do serviço. Conecta como o usuário PRIMÁRIO do Render —
-- que é o DONO do banco e das tabelas, ou seja, faz o papel do `robotrack_migrator`
-- — via MIGRATION_DATABASE_URL.
--
-- CRIA o papel de runtime `robotrack_app` e define a senha: o Render entrega o
-- Postgres com UM usuário (o dono/primário) e a UI NÃO permite criar um usuário
-- nomeado não-dono. Então o próprio app cria `robotrack_app` no primeiro boot,
-- conectado como o dono via MIGRATION_DATABASE_URL. A senha vem de
-- `APP_DB_PASSWORD` (psql -v app_pw="$APP_DB_PASSWORD"), gerada pelo Render
-- (generateValue) — nunca fixa neste arquivo. O `bin/render-web-start` deriva o
-- DATABASE_URL de runtime dessa mesma senha.
--
-- Modelo (tenant-isolation / design D-11): runtime = robotrack_app, NÃO-dono,
-- sujeito à RLS FORÇADA, SEM UPDATE/DELETE nas tabelas append-only. O usuário do
-- Render é NOSUPERUSER e NOBYPASSRLS (plataforma gerenciada) — logo NÃO pode
-- conferir SUPERUSER nem BYPASSRLS a quem cria: `robotrack_app` nasce NOSUPERUSER
-- NOBYPASSRLS por construção (defaults inforjáveis por um não-superusuário). Tanto
-- o dono quanto o app respeitam a RLS — `FORCE ROW LEVEL SECURITY` vincula até o
-- dono. Por isso o isolamento por workspace vale mesmo sem superusuário.
--
-- Idempotente: pode rodar em todo deploy. Cada deploy roda migrate (pode criar
-- tabelas novas) e ENTÃO este arquivo (re-concede em ALL TABLES, cobrindo as novas).

-- ── Papel de runtime robotrack_app (cria-se se ausente; senha a cada boot) ────
-- CREATE ROLE não tem IF NOT EXISTS: usa-se \gexec para criar só quando falta. O
-- ALTER seguinte (re)define LOGIN e a SENHA idempotentemente. Exige que o usuário
-- primário do Render tenha CREATEROLE (o managed PG concede — a doc do Render
-- descreve criar usuários por `CREATE USER` via SQL). Se NÃO tiver, este passo
-- falha aqui nomeando o privilégio (é a decisão bloqueante — ver DEPLOY_RENDER.md).
-- SUPERUSER/BYPASSRLS são OMITIDOS de propósito: o dono, sendo não-superusuário,
-- não pode conferi-los, e os defaults (NOSUPERUSER NOBYPASSRLS NOCREATEDB
-- NOCREATEROLE) são exatamente o que queremos.
SELECT 'CREATE ROLE robotrack_app LOGIN'
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'robotrack_app')
\gexec
ALTER ROLE robotrack_app WITH LOGIN PASSWORD :'app_pw';

-- Conectar ao banco e enxergar o schema.
DO $$
BEGIN
  EXECUTE format('GRANT CONNECT ON DATABASE %I TO robotrack_app', current_database());
END $$;
GRANT USAGE ON SCHEMA public TO robotrack_app;

-- DML nas tabelas/sequences JÁ existentes (o migrate desta release já rodou).
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA public TO robotrack_app;
GRANT USAGE, SELECT, UPDATE          ON ALL SEQUENCES IN SCHEMA public TO robotrack_app;

-- Objetos FUTUROS criados pelo dono (migrations futuras): o app ganha DML
-- automaticamente. "current role" aqui = o usuário primário do Render (o migrator).
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES    TO robotrack_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT, UPDATE          ON SEQUENCES TO robotrack_app;

-- ── Imutabilidade append-only (camada de privilégio) ─────────────────────────
-- Sem estes REVOKE o app teria UPDATE por atacado (grant acima) e o
-- AuditLog::ImmutabilityGuard ABORTA o boot do web/worker (ele recusa subir se o
-- papel corrente enxerga UPDATE sobre audit_logs). As triggers no banco são a
-- rede final; a negação de privilégio é a primeira camada. Guardado por
-- existência das tabelas; idempotente (REVOKE é no-op se já revogado).
DO $$
BEGIN
  IF to_regclass('public.audit_logs') IS NOT NULL THEN
    REVOKE UPDATE, DELETE ON audit_logs FROM robotrack_app;
  END IF;
  IF to_regclass('public.task_advances') IS NOT NULL THEN
    REVOKE UPDATE, DELETE ON task_advances FROM robotrack_app;
  END IF;
  IF to_regclass('public.membership_revocations') IS NOT NULL THEN
    REVOKE UPDATE, DELETE ON membership_revocations FROM robotrack_app;
  END IF;
  -- workspaces: revoga UPDATE de tabela e reconcede só as colunas mutáveis
  -- (owner_user_id/id ficam protegidos; realtime_seq é escrita pelo publisher).
  IF to_regclass('public.workspaces') IS NOT NULL THEN
    REVOKE UPDATE ON workspaces FROM robotrack_app;
    GRANT  UPDATE (name, updated_at, realtime_seq) ON workspaces TO robotrack_app;
  END IF;
END $$;
