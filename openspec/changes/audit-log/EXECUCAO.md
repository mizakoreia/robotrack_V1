# EXECUCAO — audit-log

Mapa de execução. Escrito ANTES de qualquer código (commit G0). RETOMADA no fim.

## Ponto de partida

Branch empilhada sobre `commissioning-report`. Onda 8. FULL-STACK. Entrega a trilha
de auditoria **append-only, imutável no nível do banco para TODOS inclusive o dono**
(§4.1 inv. 3 — a única invariante cujo adversário declarado é o próprio dono do dado).
Desbloqueia `workspace-settings` (o reset de fábrica D12 precisa que o log SOBREVIVA a
ele e de um caminho de escrita para registrar o evento). Depende de `progress-advances`
(a transação do avanço + o único gatilho automático: conclusão a 100%), `workspace-
tenancy` (RLS, `Person`, papéis Postgres), `authorization-policies` (policy + route-
sweep). Baseline a medir no G0.

## RECONCILIAÇÃO COM A REALIDADE (crítico — ler antes de codar)

- **Os dois papéis Postgres JÁ EXISTEM** (`db/roles.sql` cria `robotrack_migrator`
  dono + `robotrack_app` runtime, ambos NOSUPERUSER/NOBYPASSRLS). A tarefa 1.1
  ("criar os papéis") já está satisfeita pelo `roles.sql`; o que resta de novo é o
  **REVOKE UPDATE, DELETE de `audit_logs`** — na migration E no `roles.sql` (guardado
  por `to_regclass`), porque `pg_dump -x` (structure.sql) OMITE GRANT/REVOKE e um
  rebuild via `db:schema:load` nasceria com o app podendo mutar o log. Esse caveat já
  está documentado no `roles.sql` (blocos de `workspaces` e `membership_revocations`).
- **O padrão de imutabilidade está pronto para copiar**: `20260721160004_lock_task_
  advances_immutable.rb` (REVOKE + função `RAISE EXCEPTION` incondicional + trigger
  `BEFORE UPDATE OR DELETE FOR EACH ROW`) e a RLS de `task_advances` (`tenant_isolation`
  FOR SELECT + `tenant_isolation_insert` FOR INSERT, SEM política UPDATE/DELETE). Copio
  o mesmo para `audit_logs`.
- **O seam da escrita JÁ ESTÁ PLANTADO**: `TaskAdvances::CreateService#audit_completion!`
  (dentro da transação `requires_new: true`, após a conclusão a 100) hoje só emite log
  estruturado — o comentário no código diz "audit_logs (audit-log) ainda não existe".
  O G3 troca esse corpo pelo `AuditLog::RecordService.record!`, MESMA transação.
- **ENDPOINT = `GET /api/v1/audit_logs?limit=`**, tenant pelo header `X-Workspace-Id` +
  RLS — NÃO `/workspaces/:workspace_id/audit_logs`. Mesma divergência de todo o app
  (my-tasks/hierarchy/report). Os cenários da spec citam o path do design; o que importa
  é o recurso e o clamp de 200.
- **`ts_local` no fuso default `America/Sao_Paulo`** (Pergunta-em-aberto 1 do design;
  `workspace.time_zone` não existe). Reuso `Reports::DocumentId::DEFAULT_TIME_ZONE`.
- **`qk.auditLogs` NÃO existe** em keys.ts → adiciono `auditLogs: (wsId) => ['ws', wsId,
  'auditLogs']` (D9), invalidável por `realtime-collaboration` depois.
- **`WorkspaceChannel` não existe** (realtime-collaboration) — o modal NÃO atualiza ao
  vivo nesta change (design Non-Goal). Sem no-op a montar aqui.
- **Particionamento é PG 16** (disponível). RLS, trigger de linha e índices moram no
  PARENT particionado e cascateiam às partições (PG 13+). `TRUNCATE` (DatabaseCleaner)
  NÃO dispara trigger de linha → a suíte roda.

## Ordem dos grupos (mapa)

| Grupo | Escopo | Tarefas |
|---|---|---|
| **G1** | Esquema + imutabilidade + papéis: `audit_logs` particionada por `RANGE(ts)`, PK `(ts,id)`, colunas (msg/ts/ts_local/by_person_id/by_name/event_type/format_version/payload/workspace_id), FK `workspaces ON DELETE RESTRICT`, SEM FK p/ hierarquia; partições dos 3 meses + `DEFAULT` + índice `(workspace_id, ts DESC)`; RLS SELECT+INSERT (sem UPDATE/DELETE); função+trigger de imutabilidade; REVOKE (migration + roles.sql); boot-check; specs de privilégio + trigger + INSERT legítimo | 1.1–1.3, 2.1–2.5 |
| **G2** | Model + locale + service: `AuditLog` (readonly, PK `id`, sem reverso de hierarquia) + factory; `pt-BR.audit.yml` (`task_completed.v1`, `workspace_reset.v1`); `AuditLog::RecordService.record!` (renderiza `msg`+`ts_local` congelados no INSERT + `format_version`); snapshots (`by_person_id`+`by_name`, junção de responsáveis); guard de versão de format string; specs (autor irresolúvel `by_person_id NULL`, `by_name` vazio rejeitado) | 3.1–3.6 |
| **G3** | Gatilho de conclusão a 100%: liga `RecordService.record!` à transição p/ 100 no `CreateService`, MESMA transação; `<100`/`N/A`/reabertura NÃO gravam; spec de idempotência (mesmo uuid → 1 registro) | 4.1–4.3 |
| **G4** | Leitura + policy + endpoint: `AuditLogPolicy` (só `index?`, os 3 papéis); `Api::Entities::AuditLog` (id/msg/ts/ts_local/by_name/event_type — SEM payload/by_person_id); `GET /api/v1/audit_logs` (`ORDER BY ts DESC`, clamp 200); route-sweep (POST/PUT/PATCH/DELETE → 404) | 5.1–5.3 |
| **G5** | Modal frontend: `auditLogs.list` + `qk.auditLogs`; `AuditLogModal` (`msg`/`ts_local` verbatim, sem reformatar data, estados vazio/erro); teste 250→200 mais-recente-primeiro | 6.1–6.3 |
| **G6** | Fronteira com o reset (D12): contrato `workspace_reset` (já em RecordService); specs do LADO audit-log — o log SOBREVIVE a cascade delete de projetos, e `DELETE FROM audit_logs` dentro de txn dá rollback/erro | 7.1–7.3 |
| **G7** | Retenção: job de manutenção de partição (cria 3 meses à frente, alerta `DEFAULT` com linhas); export de partição→JSONL+manifesto (checksum+contagem) com storage LOCAL stub; verificação que aborta em divergência; `DETACH`+`DROP` gated por flag (default off); spec "SQL tem DETACH/DROP, não tem DELETE FROM audit_logs" | 8.1–8.6 |
| **G8** | Encerramento: nota `paper_trail` em `seal-template-baseline`; suíte de CONTORNO (update_column/update_all/delete_all/UPDATE cru app/UPDATE cru dono → todos falham no banco); suíte backend completa; CONTINUIDADE | 9.1–9.2 |

> Prints: sem tela própria nesta change (o modal monta em `workspace-settings`); print
> do modal isolado no G5 se pertinente. Suíte backend completa no fim (G8).

## Decisões que EU tomo aqui (LER)

1. **Endpoint header-tenant** `/api/v1/audit_logs` (não path `:workspace_id`) — divergência
   do path do design, alinhada ao app inteiro.
2. **Papéis já existem** (roles.sql) → 1.1 satisfeita; adiciono só o REVOKE audit-específico
   na migration E no roles.sql (caveat `pg_dump -x`).
3. **Fronteira do reset (G6)**: `FactoryResetService` NÃO existe (é de `workspace-settings`)
   → testo o LADO audit-log da D12 SIMULANDO a transação do reset (cascade delete de
   projetos + INSERT do log; e `DELETE FROM audit_logs` → rollback). A integração real
   (12→13 registros pelo reset de verdade) fica p/ `workspace-settings` G5 (registro cruzado).
4. **Modal sem tela onde montar** (Utilitários = `workspace-settings`) → entrego componente
   + hook + teste ISOLADO; a montagem na tela fica p/ `workspace-settings` (mesmo padrão do
   `ReportDocument` no commissioning-report).
5. **Retenção (G7)**: bucket de storage frio + Sidekiq scheduling + métricas/alertas reais
   são de `delivery-and-observability` → entrego a MECÂNICA DDL (partition maintenance,
   export→JSONL+manifesto, verificação, DETACH/DROP gated) com storage LOCAL stub. A
   invariante-crítica (8.6: retenção NUNCA por `DELETE FROM audit_logs`) fica REAL.
6. **Guard de format-version (3.5)**: em vez de comparar com git `main` (frágil no
   container efêmero), comparo as chaves `vN` publicadas com um **snapshot congelado
   versionado** (`spec/fixtures/audit/published_format_strings.yml`); editar uma `vN` já
   publicada quebra o spec. Decido a forma final no G2.
7. **`ts_local` fuso default `America/Sao_Paulo`** (Pergunta-em-aberto 1), reuso do
   `Reports::DocumentId`.

## Armadilhas previstas

1. **Particionamento** — RLS, trigger e índices no PARENT (cascateiam), não à mão por
   partição. `TRUNCATE` (DatabaseCleaner) não dispara trigger de linha → suíte roda. A
   factory tem de inserir na partição certa (por `ts`); `DEFAULT` como rede.
2. **structure.sql omite GRANT/REVOKE** (`pg_dump -x`) → REVOKE no `roles.sql` também
   (guardado por `to_regclass`), senão rebuild nasce mutável. Já é o padrão de `workspaces`.
3. **boot-check** — checa `has_table_privilege(current_user, 'audit_logs', 'UPDATE')` e só
   aborta se `true`. Como o app tem REVOKE → `false` → boot ok na suíte. Guardar por
   `to_regclass` (não quebrar antes da tabela existir).
4. **FK `workspaces ON DELETE RESTRICT`** — o teardown por truncation e o cascade do reset
   não podem levar o log junto; é DELIBERADO (D12). Conferir a truncation da suíte.
5. **Migrations como `robotrack_migrator`** (DATABASE_URL migrator dev/test); regenerar
   `db/structure.sql`. Reaplicar `roles.sql` se recriar banco.
6. **Idempotência do log** vem da PK do AVANÇO (D1), não do log — o spec de reenvio (4.3)
   é o detector; o service NÃO faz dedup próprio.
7. **`msg`/`ts_local` congelados no INSERT** (Decisão 4) — a leitura usa verbatim, nunca
   re-renderiza; publicar `v2` não pode reescrever registro gravado (o guard do G2 prova).

### Decisões tomadas na G1 (registro pós-execução)

- **RLS NÃO cascateia às partições** (corrige a armadilha 1): trigger de linha e
  índices herdam do PARENT, mas `relrowsecurity`/`relforcerowsecurity` e as policies
  NÃO — as partições nascem sem RLS. Como o papel de app tem SELECT/INSERT nelas
  (grant de ALL TABLES), um `SELECT FROM audit_logs_2026_07` DIRETO vazaria
  cross-tenant. Fix: função `secure_audit_partition(regclass)` aplica ENABLE+FORCE
  RLS + as duas policies a CADA partição; a migration a chama p/ as existentes, e o
  **job de manutenção do G7 tem de chamá-la para toda partição nova**. Prova: teste de
  SELECT direto na partição (só vê o próprio tenant) + `schema_guard` verde (as
  partições entram na varredura de tabelas de domínio).
- **A trigger é pré-filtrada pela RLS para o DONO**: sem policy de UPDATE/DELETE, o
  migrator (dono) enxerga 0 linhas no UPDATE/DELETE (afeta 0, sem erro) ANTES da
  trigger. Logo a trigger é o backstop EXCLUSIVO do SUPERUSER (que ignora RLS) —
  testado via `su - postgres` (skippable fora do ambiente local). As duas camadas
  provadas: migrator→0 linhas; superuser→RAISE `append-only`.
- **`by_person_id` = FK SIMPLES `people(id) ON DELETE SET NULL`** (não composta —
  compor nularia `workspace_id NOT NULL`), espelhando `cells.updated_by_person_id`.
- **boot-check** guardado a processos de servidor/worker (`Rails::Server`/`Sidekiq.
  server?`): migração/console/rake/suite conectam como o DONO (UPDATE=true legítimo)
  e NÃO devem abortar; a prova determinística do papel de app é o spec de privilégio.

### Decisões tomadas na G4 (registro pós-execução)

- **Verbos de escrita fail-closam com 500, não 404** (5.3): o design pedia 404 em
  POST/PUT/PATCH/DELETE, mas o gate do app inteiro (`authorize_route!` em
  `Api::Root`) fail-closa QUALQUER rota sem policy declarada com 500 —
  `undeclared_route` (rota policy-less) ou `internal_error` (método sem endpoint,
  API_ENDPOINT nil). Confirmado em `authorization_gate_spec`. A garantia é a mesma
  do 404 pretendido: escrita de auditoria NUNCA responde 2xx. Provo (a) só o GET é
  rota montada, com policy `AuditLogPolicy/index` (via `Api::Root.routes`), e (b)
  os 4 verbos fail-closam. O `route_sweep_spec` (D3) já cataloga o GET.
- **`AuditLogPolicy` mantida como está** (index?/show?/create?): já existia e
  `inv_3` depende de `create?` responder; o design 5.1 pede "só index? e nenhum
  update?/destroy?" — satisfeito. O endpoint só usa `index`.
- **Endpoint header-tenant `/api/v1/audit_logs`** + `MAX_LIMIT=200` clampeado;
  leitura por `AuditLog.order(ts: :desc).limit` (RLS + default_scope isolam).
  Entity sem payload/by_person_id. swagger allowlist +`/api/v1/audit_logs`.

## Protocolo por grupo

Aplicar → backend `rspec` dirigido (0 falhas) e/ou frontend `vitest`+`tsc` (0) → marcar
`- [x]` em tasks.md → `npx --yes @fission-ai/openspec@1.6.0 validate audit-log --strict`
→ **um commit** `G<n>: ...` → push `git push origin HEAD:audit-log`. Suíte backend
completa no fim. Banco a cada sessão (ver CONTINUIDADE) + `PATH=/opt/rbenv/shims`. NUNCA
rodar duas suítes ao mesmo tempo (contenção de lock no banco de teste).

## Progresso

- [ ] G0 — este mapa (commit G0)
- [x] G1 — esquema + imutabilidade + papéis (1.1–1.3, 2.1–2.5)
- [x] G2 — model + locale + service (3.1–3.6)
- [x] G3 — gatilho de conclusão a 100% (4.1–4.3)
- [x] G4 — leitura + policy + endpoint (5.1–5.3)
- [x] G5 — modal frontend (6.1–6.3)
- [x] G6 — fronteira com o reset D12 (7.1–7.3)
- [ ] G7 — retenção (8.1–8.6)
- [ ] G8 — encerramento (9.1–9.2)

## RETOMADA (para o próximo agente)

1. `git log --oneline` na branch (empilhada em `commissioning-report`); um commit por grupo.
2. LEIA a RECONCILIAÇÃO: papéis já existem (só o REVOKE de audit_logs é novo — migration +
   roles.sql); imutabilidade copia `lock_task_advances_immutable`; endpoint header-tenant
   `/api/v1/audit_logs`; seam plantado em `CreateService#audit_completion!`.
3. Invioláveis: imutabilidade em 3 camadas de BANCO (REVOKE + trigger + RLS sem UPDATE/
   DELETE), nunca no model; log de conclusão TRANSACIONAL (avanço sem log não commita);
   `msg`/`ts_local` congelados no INSERT; SEM FK p/ hierarquia + `workspaces ON DELETE
   RESTRICT` (sobrevive ao reset); leitura clamp 200; NENHUMA rota de escrita/update/delete;
   retenção por DDL (DETACH/DROP), NUNCA `DELETE FROM audit_logs`.
4. Banco: provisionar (ver CONTINUIDADE) + `PATH=/opt/rbenv/shims`. UMA suíte por vez.
   Migrations como `robotrack_migrator`; regenerar structure.sql.
