## Why

A hierarquia **Projeto → Célula → Robô** (§1.1) é o esqueleto do RoboTrack: sem ela não
existe tarefa (§1.1 Tarefa), não existe avanço (§2.4), não existe consolidação de
progresso (§2.1) e não existe nenhuma das telas de §3.2 a §3.6. Ela é o primeiro nó do
caminho crítico depois de `workspace-tenancy` e `authorization-policies`.

No legado essas três entidades não são tabelas: são **arrays aninhados dentro do
documento de projeto** no Firestore. Célula é posição num array de `cells`; robô é
posição num array de `robots`; a ordem de projeto é um inteiro `_ord` que na criação
recebe um **timestamp** (§2.9). Nada disso é requisito — é acidente do modelo de
documento. O porte normaliza os três níveis em tabelas relacionais e unifica os dois
mecanismos de ordenação numa única coluna `position`.

Esta mudança também é onde nascem duas decisões transversais que o porte inteiro herda:

- **D1/D13 — PK `uuid` gerável no cliente em toda tabela de domínio.** Sem isso, criar
  um robô offline é estruturalmente impossível: o cliente não teria id para enfileirar
  o avanço contra as tarefas desse robô, que também não existiriam. Isso contradiz
  frontalmente §4.2 ("escritas resolvem localmente e são reenviadas"). A regra nasce
  aqui e vale para todas as tabelas (`workspaces`, `people`, `memberships`,
  `invitations`, `projects`, `cells`, `robots`, `tasks`, `task_templates`,
  `task_advances`, `notifications`, `audit_logs`).
- **D5 — `progress_cache` nasce nas mesmas migrations** que criam `projects`, `cells` e
  `robots`. A semântica do cache é de `progress-rollup`; a **existência da coluna desde
  a primeira migration** é obrigação desta mudança, para não retrofitar três migrations
  já aplicadas.

## What Changes

- Cria as tabelas `projects`, `cells` e `robots` com PK `uuid` (default
  `gen_random_uuid()`, mas o valor pode vir do cliente), `workspace_id` desnormalizado
  `NOT NULL` (D2), `position` (`integer`), `progress_cache` (`jsonb NOT NULL DEFAULT
  '{}'`), `lock_version`, `updated_by_person_id` / `updated_at` (§1.1 `_updatedBy` /
  `_updatedAt`, agora nos **três** níveis, não só no projeto) e `created_at`.
- Integridade de tenancy no banco, não no model: FK composta
  `(project_id, workspace_id) → projects(id, workspace_id)` e
  `(cell_id, workspace_id) → cells(id, workspace_id)`, mais política RLS por
  `app.current_workspace_id` (D2).
- CRUD completo (criar, renomear, excluir) dos três níveis via Grape sob
  `/api/v1/projects`, `/api/v1/cells`, `/api/v1/robots`, no contrato de service do
  template (`ApiResponseHandler` + `Api::Entities::*`), com policy declarada por
  endpoint (D3).
- **Idempotência de criação**: `POST` aceita `id` do cliente; replay do mesmo `id` com
  a mesma carga devolve o recurso existente em `200` em vez de `409`.
- **Ordenação manual unificada** (§2.9): uma única coluna `position` inteira, contígua e
  0-based por escopo, com endpoint de reordenação em lote transacional e detecção de
  reordenação concorrente.
- **Leitura tolerante** (§1.4, normalização defensiva): projeto sem células, célula sem
  robôs e robô sem tarefas retornam **lista vazia**, nunca `null` e nunca erro.
- `application` do robô (§1.2) persistido como enum fechado com constraint de banco.

### BREAKING

Nenhuma quebra de contrato público — não existe nada construído para quebrar. Mas há
duas quebras **em relação ao legado**, deliberadas:

- **BREAKING (legado):** `_ord` como timestamp na criação é abandonado. `position` é
  índice contíguo 0-based. `legacy-data-migration` renumera na importação.
- **BREAKING (legado):** ordem de célula/robô deixa de ser implícita na posição do array
  e passa a ser coluna explícita.

### Não-objetivos

- **Layout, hubs analíticos, grades de card, estados vazios e busca** das telas §3.3 /
  §3.4 — pertencem a `hierarchy-screens`. Esta mudança entrega apenas as **ações de
  CRUD e reordenação** que essas telas chamam, e o contrato de API que elas consomem.
- **Semântica** do progresso, as duas métricas de D15, consolidação bottom-up e job de
  reconciliação — `progress-rollup`. Aqui só a coluna e seu default.
- **Tabela `tasks`**, criação de robôs em lote (§2.5, 1–50 com dedup) e `task_assignees`
  — `robot-tasks`. Aqui só a FK que `robots` expõe e a garantia de que "robô sem tarefas"
  não quebra o render.
- **Definição dos papéis, matriz §4.1 e o motor de policy** — `authorization-policies`.
  Esta mudança **declara** e consome policies, não as inventa.
- **RLS, `Workspace`, `Person`, `Membership` e o helper que seta
  `app.current_workspace_id`** — `workspace-tenancy`. Aqui se escrevem apenas as
  políticas RLS **destas três tabelas**.
- **Fila de mutations, IndexedDB e resolução de dependência** — `offline-pwa`. Aqui só o
  contrato de id/idempotência que a torna possível.
- **Eventos ActionCable** de criação/reordenação — `realtime-collaboration`. Esta
  mudança emite o hook de publicação; o canal é de lá.
- **Importação do export Firestore** — `legacy-data-migration`.

## Capabilities

### New Capabilities

- `client-generated-ids`: contrato de identidade de domínio — `uuid` PK gerável no
  cliente em toda tabela, formato aceito, tratamento de colisão, idempotência de replay
  e isolamento de id entre workspaces (D1, D13).
- `commissioning-hierarchy`: esquema relacional e CRUD de `projects`, `cells` e
  `robots`, tenancy no banco, cascade de exclusão, `progress_cache` desde a origem e
  leitura tolerante (§1.1, §1.4, §3.3, §3.4).
- `hierarchy-ordering`: `position` como representação única de ordem manual,
  reordenação em lote transacional, concorrência e permissão (§2.9).

### Modified Capabilities

Nenhuma. `openspec/specs/` está vazio.

## Impact

- **Banco:** 3 migrations novas (`projects`, `cells`, `robots`), 3 políticas RLS, 2 FKs
  compostas, índices únicos de `(escopo, position)` e `(escopo, lower(name))`. Nada
  destrutivo — só criação.
- **Backend:** `app/models/{project,cell,robot}.rb`,
  `app/services/{projects,cells,robots}_service.rb`, `app/services/hierarchy/reorder_service.rb`,
  `app/api/entities`, 3 arquivos de endpoint + 3 linhas de `mount` em `api/v1/base.rb`,
  3 policies em `app/policies/`.
- **Frontend:** `lib/api/endpoints.ts` ganha o grupo `hierarchy`; hooks React Query com
  as chaves de D9 (`['ws', wsId, 'projects']`, `['ws', wsId, 'project', pid, 'cells']`,
  `['ws', wsId, 'cell', cid, 'robots']`); helper `newId()` (`crypto.randomUUID`).
- **Dependências:** `authorization-policies` (policies + route-sweep), `workspace-tenancy`
  (workspace, person, RLS, `app.current_workspace_id`).
- **Consome esta mudança:** `task-catalog`, `robot-tasks`, `progress-rollup`,
  `hierarchy-screens`, `offline-pwa`, `legacy-data-migration`.
- **Entrega** (`delivery-and-observability`): a extensão `pgcrypto` (ou `pg_uuidv7`) deve
  estar habilitada no Postgres de todos os ambientes antes da primeira migration, e o
  usuário de aplicação **não pode** ter `BYPASSRLS`.
