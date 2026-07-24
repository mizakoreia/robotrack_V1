-- Camada 1 da imutabilidade em staging (design D-11 / §4.1 invariantes). Roda
-- DEPOIS do migrate, como o migrator (dono das tabelas), no release wrapper. Em
-- produção real o equivalente é reaplicar db/roles.sql pós-migrate; aqui isolamos
-- só os REVOKE porque as tabelas de tenant nascem do migrate e já são dele.
--
-- Sem isto o app teria UPDATE em audit_logs (via ALTER DEFAULT PRIVILEGES), e o
-- AuditLog::ImmutabilityGuard (corretamente) abortaria o boot de web e worker
-- (BUG 10). Os nomes espelham db/roles.sql; idempotente (REVOKE é no-op se já
-- revogado).
REVOKE UPDATE, DELETE ON audit_logs             FROM robotrack_app;
REVOKE UPDATE, DELETE ON task_advances          FROM robotrack_app;
REVOKE UPDATE, DELETE ON membership_revocations FROM robotrack_app;

-- workspaces: revoga UPDATE de tabela e reconcede só as colunas mutáveis
-- (owner_user_id/id ficam protegidos). realtime_seq é escrita pelo publisher de
-- tempo real (realtime-collaboration 3.1); name/updated_at seguem mutáveis.
REVOKE UPDATE ON workspaces FROM robotrack_app;
GRANT  UPDATE (name, updated_at, realtime_seq) ON workspaces TO robotrack_app;
