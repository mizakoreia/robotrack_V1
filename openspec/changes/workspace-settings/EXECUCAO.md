# EXECUCAO — workspace-settings

Mapa de execução. Escrito ANTES de qualquer código (commit G0). RETOMADA no fim.

## Ponto de partida

Branch empilhada sobre `audit-log`. Onda 8. FULL-STACK. É a **única operação
destrutiva em massa do produto** (o reset de fábrica). Três capabilities:
`workspace-settings-screen` (tela: Equipe/Tarefas-base/Utilitários/Aparência),
`workspace-backup-export` (`RoboTrack_Database.json`), `workspace-factory-reset`
(reset atômico, dono, D12). Dona de **D12** (o reset preserva a auditoria e grava
nela que ocorreu — a contradição herdada que `audit-log` já resolveu do outro lado).
Depende de `audit-log` (RECÉM-FECHADA: `RecordService.record!(event:
:workspace_reset)` + `AuditLogModal` prontos), `task-catalog` (modelo/seed/CRUD de
templates), `workspace-invitations` (revogação de convite, memberships),
`authorization-policies`, `workspace-tenancy` (RLS, `Person`), `design-system`
(tema, Chip/Modal), `app-shell-navigation`. Baseline a medir no G1.

## RECONCILIAÇÃO COM A REALIDADE (crítico — ler antes de codar)

- **`audit-log` está PRONTA** (esta sessão): o reset (G5) chama
  `AuditLog::RecordService.record!(workspace:, event: :workspace_reset, by:,
  payload: { projects_count: })` DENTRO da transação; o painel Utilitários (G6)
  monta `AuditLogModal` (frontend, `features/audit/`).
- **CRUD de `task_templates` JÁ EXISTE** (`task-catalog`): `POST/PATCH/DELETE
  /api/v1/task_templates` com `TaskTemplatePolicy` (edit/owner). A tarefa 3.1
  ("endpoints de escrita") está SATISFEITA — G3 entrega a **TELA** que os consome,
  não novos endpoints. O design cita `/api/v1/workspace/task_templates`; é prosa —
  reuso `/api/v1/task_templates`.
- **Seeder dos 31 padrões JÁ EXISTE**: `Workspaces::SeedDefaultTaskTemplatesService`
  (`insert_all!` de `TaskTemplates::DefaultCatalog`). O re-seed do reset (G5) DELETA
  os templates e chama esse seeder.
- **`people.archived_at` e `workspace_backups` NÃO existem** → migrations do G1.
- **`themeStore` real = `useThemeStore`, chave `rt-theme`, escuro padrão, ignora o
  SO** (`design-system` já entregou). O design dizia `theme-storage` — divergência;
  G6 é FIAÇÃO do store existente, não lógica nova.
- **Revogação de convite = `Invitations::RevokeService`** (DELETE real do PENDENTE;
  consumido não é revogável). O design D-RESET dizia `revoked_at = now()`; a
  realidade revoga-por-DELETE. Reconciliação do G5.
- **Rota parcial `/configuracoes/equipe` (TeamPanel) JÁ existe** (workspace-
  invitations). A tela vai em **`/configuracoes`** (header-tenant, SEM `:wsId` no
  path — o app resolve tenant por header/store, nunca por URL). O design cita
  `/ws/:wsId/settings`; é prosa.
- **`WorkspaceChannel` não existe** (realtime-collaboration) — o evento terminal do
  reset (5.9) degrada como **no-op guardado** (padrão já usado em
  `memberships/remove_service` e `task_advances`).
- **`legacy-data-migration` não existe** — esta change PUBLICA o contrato (fixture
  v2 + round-trip); o IMPORTADOR é de lá.
- **`delivery-and-observability`**: diretório/TTL dos arquivos de backup e o alerta
  de reset são deles. Aqui: síncrono até um teto + job acima dele (com storage stub).

## Ordem dos grupos (mapa) — G4 precede G5 (o reset exige um backup_id)

| Grupo | Escopo | Tarefas |
|---|---|---|
| **G1** | Esquema + autorização: migration `people.archived_at` + índice único parcial `(workspace_id, lower(name)) WHERE archived_at IS NULL` + `CHECK(btrim(name)<>'')` + trigger `BEFORE UPDATE OF archived_at` (recusa se membership ativa); migration `workspace_backups` (uuid, workspace_id, status, checksum, counts jsonb) com RLS; policies `WorkspaceSettingsPolicy`/`WorkspaceBackupPolicy`/`WorkspaceFactoryResetPolicy`; spec de autorização da matriz §4.1 | 1.1–1.4 |
| **G2** | Painel de Equipe: `GET/POST /api/v1/workspace/people` (entity, ordem alfabética, `archived_at IS NULL`); `People::ArchiveService` (arquiva + apaga task_assignees + preserva advances/audit + 409 se membership); componente de chips (sem chip fixo, `"Não atribuído"` = rótulo de vazio, D11); specs | 2.1–2.4 |
| **G3** | Tela do catálogo (reusa CRUD de task-catalog): tabela agrupada por categoria em ordem lexicográfica, 4 colunas, modo leitura p/ `view`; form de adição (weight=1); editor de filtro com regra `Misto / Geral` → `app_filters: []`; exclusão com confirmação; vitest | 3.1–3.6 |
| **G4** | Exportar backup: fixture congelada `roboTrack_database_v2.json` (superset legado + `_rt`); `Workspace::BackupExportService` (chaves ordenadas, schemaVersion 2, counts, checksum sha256, coleções de topo); `POST /api/v1/workspace/backups` owner-only + `Content-Disposition` + linha em workspace_backups; job acima de 5.000 tarefas; botão; specs de isolamento + round-trip byte a byte | 4.1–4.6 |
| **G5** | **Reset de fábrica** (destrutivo — autorização à parte): backup obrigatório antes; gate no servidor (frase=nome, backup_id ≤15min consumido); `Workspace::FactoryResetService` (transação SERIALIZABLE: apaga projetos→…→avanços→notificações, revoga convites, re-seed 31, **preserva audit_logs+workspace+people+memberships**, grava o registro do reset via `RecordService`); specs D12 + rollback; modal; evento terminal (no-op); alerta | 5.1–5.10 |
| **G6** | Tema + auditoria + fechamento: painel Aparência (fiação do `useThemeStore`); modal de auditoria montando `AuditLogModal`; i18n `pt-BR.settings.yml` + módulo único; e2e | 6.1–6.4 |

> **G0–G4 autorizados agora.** G5 (reset destrutivo) e G6 pedem autorização
> explícita — atenção redobrada no G5 (conferir cada número/destino antes de codar).
> Prints nos grupos visuais (G2/G3/G6).

## Decisões que EU tomo aqui (LER)

1. **Endpoints `/api/v1/workspace/*` header-tenant** (people/backups/factory_reset);
   REUSO `/api/v1/task_templates` (task-catalog) p/ a tela do catálogo — NÃO crio
   `workspace/task_templates`. 3.1 já satisfeita.
2. **Rota `/configuracoes` header-tenant** (não `/ws/:wsId/settings`) — o app nunca
   põe wsId na URL; expando o parcial `/configuracoes/equipe`.
3. **themeStore = `useThemeStore`/`rt-theme`** (design dizia `theme-storage`) — G6 é
   fiação, o store e o guarda anti-SO já existem (design-system).
4. **Reset revoga convites via `Invitations::RevokeService`** (DELETE do pendente —
   realidade; design dizia `revoked_at`). Registro no G5.
5. **AuditLogModal + `RecordService(:workspace_reset)` reusados** de `audit-log`.
6. **Evento terminal do reset = no-op guardado** até `realtime-collaboration`.
7. **BREAKING declarado (D-RESET):** o reset apaga o CONTEÚDO, NÃO o registro do
   workspace nem people/memberships (apagar o workspace cascatearia p/ audit_logs →
   o bug de D12). Preciso do aval do cliente no G5.

## Armadilhas previstas

1. **`people.archived_at`** — arquivar quem tem membership ativa deve falhar no
   BANCO (trigger `BEFORE UPDATE OF archived_at`), não só na policy; `update_column`
   no console tem de bater na parede. Índice único parcial impede duplicata de chip
   ativo; `"Não Atribuído"` NUNCA vira linha (D11 — é rótulo de vazio).
2. **`workspace_backups`** — RLS como as demais (o `schema_guard` exige workspace_id
   NOT NULL + índice liderado por workspace_id + FORCE RLS + policy `tenant_isolation`).
3. **Round-trip do backup byte a byte** — chaves ordenadas na serialização;
   `_rt.exportedAt`/`checksum` EXCLUÍDOS da comparação; qualquer campo novo em
   qualquer change downstream quebra (é o sensor de "backup defasou"). schemaVersion 2.
4. **Export owner-only** (carrega e-mails de membros/convites) — edit/view 403.
5. **Gate do reset no SERVIDOR** — frase == `workspace.name` (strip, sensível a
   caixa); backup_id do MESMO ws, `completed`, `created_at >= now()-15min`, CONSUMIDO
   (duplo clique não gera dois resets). Divergência/ausência → 422, NADA executa,
   NENHUMA entrada de auditoria (tentativa falha não é evento).
6. **Reset atômico** — transação; o registro de auditoria DENTRO dela (rollback leva
   o log junto); `workspace_backups` PRESERVADO (é a prova do backup).
7. **`Misto / Geral`** — o editor envia `app_filters: []`, NUNCA `["Misto / Geral"]`
   (o CHECK mora em task-catalog); o vitest falha se a requisição contiver a string.

### BLOQUEIO descoberto no G5 (reset) — PAUSA de G5/G6

Ao revisar os destinos do reset ANTES de codar, descobri um conflito cross-change:
o reset apaga a hierarquia, MAS `task_advances` é IMUTÁVEL (progress-advances D-IMUT:
REVOKE DELETE + trigger p/ todos os papéis) E trava as tarefas com FK `ON DELETE
RESTRICT`. Logo **`DELETE FROM projects` é impossível sempre que há avanços** (o caso
normal) — a MESMA classe de contradição que a D12 resolveu p/ audit_logs, agora p/
os avanços. Já estava anotado na CONTINUIDADE como pendência ("hard delete de robô/
projeto com tarefas que têm avanços daria 500; fix = soft-delete de hierarquia").

**Decisão do cliente:** fazer o SOFT-DELETE de hierarquia PRIMEIRO (change dedicada
`hierarchy-soft-delete`), depois voltar ao reset (que passa a ARQUIVAR a hierarquia
e PRESERVAR a trilha imutável). G5 e G6 do workspace-settings ficam PAUSADOS até o
pré-requisito existir. G0–G4 (Equipe, catálogo, backup) já entregues e verdes.

### RETOMADA G5 — o pré-requisito existe; reconciliação design↔realidade (ler antes de codar)

`hierarchy-soft-delete` está COMPLETA (4/4). O reset agora é viável. Reconciliações que
a realidade impõe sobre a tabela **D-RESET** do `design.md`:

1. **Hierarquia: ARQUIVA, não DELETA (a divergência central, já aprovada).** D-RESET manda
   `DELETE` de projects/cells/robots e cascade-DELETE de tasks/assignees/**advances**. Isso
   é IMPOSSÍVEL: `task_advances` é imutável (D-IMUT) e trava as tarefas (FK RESTRICT). O
   reset chama `Hierarchy::SoftDeleteService.call(record: project)` por projeto vivo — que
   arquiva a subárvore (tarefas/robôs/células) e remove `task_assignees`, PRESERVANDO os
   avanços. O usuário vê o workspace vazio; a trilha imutável sobrevive. (D-RESET dizia que
   a trilha "pertence à tarefa e a tarefa deixou de existir" — mas a implementação de
   `progress-advances` tornou a trilha indestrutível para TODOS os papéis, uma escolha mais
   forte que o design previu. Arquivar concilia as duas.)
2. **Mensagem de auditoria já simplificada.** `audit-log` CONGELOU `workspace_reset.v1` como
   `"%{by_name} executou o reset de fábrica do workspace. Projetos removidos: %{projects_count}."`
   — só `projects_count`. Não conto células/robôs/tarefas/avanços/notificações (a string
   longa do D14 não foi publicada). "Removidos" é verdade pro usuário (somem da tela).
3. **`notifications` NÃO existe** (in-app-notifications não foi feita). Nada a apagar; o
   destino "notifications → DELETE" do D-RESET é HANDOFF para aquela capacidade.
4. **`WorkspaceChannel` NÃO existe** (realtime-collaboration não feita) → 5.9 (publicar
   evento terminal + invalidar keys) é HANDOFF. Sem no-op a montar.
5. **Alerta de operação** (5.10) → HANDOFF para delivery-and-observability.
6. **Round-trip via importador legado** (5.1) → o importador de `legacy-data-migration` não
   existe; a "prova de restauração" é HANDOFF. O que garanto aqui: o backup é PRÉ-CONDIÇÃO
   verificada (5.2) e o `workspace_backups` sobrevive ao reset (é a prova do backup).
7. **Consumo do backup (anti-duplo-clique):** `workspace_backups` não tem coluna de consumo.
   Adiciono `consumed_at timestamptz NULL` (migration aditiva; a RLS já dá UPDATE ao app). O
   gate exige `status='completed'`, `created_at >= now()-15min` e `consumed_at IS NULL`; o
   reset carimba `consumed_at` na transação. Duplo clique: o 2º acha consumido → 422.
8. **templates: DELETE + re-seed** (mantido do design) — `task_templates` não tem trilha
   imutável nem FK de avanço (deletável pelo app); reuso `Workspaces::
   SeedDefaultTaskTemplatesService`.
9. **convites pendentes: REVOGADOS** (mantido) via `Invitations::RevokeService` (loop nos
   pendentes, papel owner), `revoked_at`, sem DELETE.
10. **Endpoint:** `POST /api/v1/workspace/factory_reset`, owner-only
    (`WorkspaceFactoryResetPolicy`), atrás de `FEATURE_FACTORY_RESET` (desligada → 404).
11. **G5 entregue em dois passos coerentes:** (a) MOTOR backend (serviço+gate+endpoint+specs
    — o núcleo antes bloqueado), (b) modal de reset no frontend (5.8). 5.9/5.10/5.1 = handoffs
    documentados. G6 (tema + modal de auditoria + fechamento) vem depois, com autorização.
12. **(descoberta na execução) SERIALIZABLE é impossível neste app** — TODO contexto de
    tenant (middleware `TenantTransaction` no request; `Tenant.with` fora dele) JÁ abre a
    transação externa, porque o `SET LOCAL` da RLS morre com ela. `transaction(isolation:)`
    aninhado levanta `TransactionIsolationError`. O reset usa savepoint (`requires_new`,
    o padrão de `TaskAdvances::CreateService`); o anti-replay REAL é o CAS
    `UPDATE ... WHERE consumed_at IS NULL` no backup (vale em READ COMMITTED).

**G5 EXECUTADO** (motor + modal): `POST /api/v1/workspace/factory_reset` (owner-only,
flag `FEATURE_FACTORY_RESET` default off → 404), `Workspace::FactoryResetService`
(gates frase/backup≤15min/consumo CAS; arquiva via `Hierarchy::SoftDeleteService`;
templates DELETE+re-seed 31; convites pendentes DELETE; auditoria na transação),
migration `workspace_backups.consumed_at`, `FactoryResetModal` (frase trava o botão,
export SEMPRE antes, cancel+clear pós-sucesso), `flags.factoryReset`. Specs: 9 backend
(feliz, SQL-capture anti-mutação de audit_logs, gates, duplo-clique, 403/404, rollback)
+ 7 vitest. Suítes: backend dirigido 131/0 (incl. sweeps), frontend 352/0, tsc limpo.

## Protocolo por grupo

Aplicar → backend `rspec` dirigido (0 falhas) e/ou frontend `vitest`+`tsc` (0) →
marcar `- [x]` em tasks.md → `npx --yes @fission-ai/openspec@1.6.0 validate
workspace-settings --strict` → **um commit** `G<n>:` → push `git push origin
HEAD:workspace-settings`. Suíte backend completa no fim. Banco a cada sessão (ver
CONTINUIDADE) + `PATH=/opt/rbenv/shims`. Migrations como `robotrack_migrator`;
regenerar structure.sql. UMA suíte por vez.

## Progresso

- [ ] G0 — este mapa (commit G0)
- [x] G1 — esquema + autorização (1.1–1.4)
- [x] G2 — painel de Equipe (2.1–2.4)
- [x] G3 — tela do catálogo (3.1–3.6)
- [x] G4 — exportar backup (4.1–4.6)
- [ ] G5 — reset de fábrica (5.1–5.10) — AUTORIZAÇÃO À PARTE
- [ ] G6 — tema + auditoria + fechamento (6.1–6.4) — AUTORIZAÇÃO À PARTE

## RETOMADA (para o próximo agente)

1. `git log --oneline` na branch (empilhada em `audit-log`); um commit por grupo.
2. LEIA a RECONCILIAÇÃO: `audit-log` pronta (RecordService/AuditLogModal); CRUD de
   templates já existe (G3 = tela); endpoints `/api/v1/workspace/*` header-tenant;
   rota `/configuracoes`; themeStore = `useThemeStore`/`rt-theme`.
3. Invioláveis: reset apaga CONTEÚDO não a conta; preserva audit_logs+workspace+
   people+memberships; gate no servidor (frase+backup≤15min consumido); atômico com
   o registro DENTRO da transação; export owner-only + round-trip byte a byte; D11
   sem sentinela; `Misto / Geral` → `[]`.
4. Banco: provisionar (ver CONTINUIDADE) + `PATH=/opt/rbenv/shims`. UMA suíte por
   vez. Migrations como `robotrack_migrator`; regenerar structure.sql. G5 é o grupo
   destrutivo — backup/prova antes de qualquer código de exclusão.
