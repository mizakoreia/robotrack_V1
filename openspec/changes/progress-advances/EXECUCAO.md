# EXECUCAO — progress-advances

Mapa de execução das ~30 tarefas de `tasks.md`, um commit por grupo. Mesmo método
das changes anteriores. Escrito ANTES de qualquer código; RETOMADA no fim.

## Ponto de partida

- Branch: `robot-tasks` (empilhada; contém task-catalog + robot-tasks completas).
  Push por branch canônica desta change: `git push origin HEAD:progress-advances`
  (nova branch, a partir do tip atual `05720b5`).
- Baseline: **backend 820 / 0 (10 pending)**, **frontend 88 / 0**, `tsc` limpo.
- Ambiente do container: Postgres 16 (papéis `robotrack_migrator`/`robotrack_app`,
  sem SUPERUSER/BYPASSRLS), Ruby 3.2.3 (rbenv), `backend/config/database.yml`
  gitignored. Migrations como migrator, suíte como app. `service postgresql start`
  se o pg cair. Ao criar tabela com REVOKE, re-rodar `db/roles.sql` nos dois bancos
  (o `pg_dump -x` do structure.sql OMITE GRANT/REVOKE — ver Armadilha 1).
- **Dependências satisfeitas:** `tasks`, `task_assignees`, `lock_version` (robot-tasks);
  `people`/RLS (workspace-tenancy); `TaskPolicy`/gate (authorization-policies).
- **`ApplyTransitionService` NÃO existe ainda** — é desta change.

## Objetivo central

O produto é um REGISTRO DE COMISSIONAMENTO: todo número de progresso num relatório
assinado tem atrás dele uma entrada nominal, datada e IMUTÁVEL. Esta change entrega
a trilha `task_advances` (append-only), a máquina de estados status↔progresso, a
auto-atribuição do autor, e a concorrência otimista/idempotência. `task_advances`
vira a ÚNICA porta de escrita de `tasks.progress`.

## Ordem dos grupos

| Grupo | Área | Tarefas |
|---|---|---|
| **G0** | Este mapa | — |
| **G1** | Esquema: soft-delete em `tasks`, `task_advances` (CHECKs, RLS, REVOKE+trigger de imutabilidade), CHECK `done⇒100`, spec por SQL cru | 1.1–1.7 + 6.3 |
| **G2** | Máquina de estados: `ApplyTransitionService` (tabela-verdade 8 linhas) + spec unitário | 2.1–2.3 |
| **G3** | Registro de avanço: `CreateService` (transação, clamp, auto-atribuição, idempotência/409, evento) | 3.1–3.6 |
| **G4** | API e autorização: policy, `POST`/`GET`, limpeza do `PATCH`, specs negativos | 4.1–4.5 |
| **G5** | Modal de avanço (frontend): draft/slider, ±10, comentário condicional, 409, view read-only | 5.1–5.7 |
| **G6** | Integração e fechamento: contratos, env var, e2e | 6.1, 6.2, 6.4 |

## Decisões de desenho já fixadas (do design.md — não reabrir)

D-TS (dois timestamps; `recorded_at` do cliente é a verdade exibida, com clamp),
D-ORD (ordem `recorded_at DESC, created_at DESC, id DESC`), D-SM (máquina de estados
é serviço, NÃO `aasm`), D-CHK (só `status='Concluído' ⇒ progress=100` vira CHECK; a
inversa NÃO, para permitir reabrir; `(Em Andamento,0)` e `(Em Andamento,100)` são
legítimos), D-CMT (comentário obrigatório < 100 é CHECK), D-IMUT (imutabilidade em 3
camadas: RLS sem UPDATE/DELETE + REVOKE + trigger), D-ID (idempotência por uuid ANTES
do lock_version), D-409 (conflito devolve estado atual, UI não reenvia), D-AUTO
(auto-atribuição na mesma transação só se `task_assignees` vazio), D-LEG (`obs` legado
vira entrada `legacy` no importador; `tasks` NÃO tem `obs`), D-UI (valor do modal lido
do estado atual, não de cache), D-AUTHZ (create owner/edit; view 403; tenant alheio 404).

## Decisões que EU tomo aqui (cross-change — LER)

1. **SOFT-DELETE em `tasks` (fecha Q1 / D-IMUT).** robot-tasks entregou HARD delete
   (`DeleteService#call` faz `task.destroy!`), mas a trilha imutável PROÍBE cascade/delete
   de `task_advances`. Resolução exigida pelo design (tarefa 6.3): `tasks` ganha
   `deleted_at timestamptz NULL`; `DeleteService` passa a SETAR `deleted_at` (soft), não
   `destroy!`; a leitura passa a excluir soft-deleted (scope). A FK `task_advances → tasks`
   é `ON DELETE RESTRICT` (defensiva — na prática nunca há hard delete). Isto MODIFICA
   robot-tasks (change na mesma branch): a migration do soft-delete e o ajuste do
   `DeleteService` + do spec `spec/requests/tasks_spec.rb` (o teste "exclui a tarefa e suas
   atribuições" passa a afirmar soft-delete: a tarefa some da leitura, e as atribuições são
   removidas explicitamente no soft-delete para não deixar chip órfão). Vai no G1.
2. **Auditoria de 100% = log estruturado, não tabela (`audit_logs` NÃO existe).** `audit-log`
   é change futura. Como `Hierarchy::CrudService#audit_destroy!` já faz (log estruturado com
   nota "audit-log troca por escrita em audit_logs"), a conclusão a 100% emite um log
   estruturado DENTRO da transação. A semântica "falha na auditoria reverte a entrada"
   (tarefa 3.1) só ganha dente quando `audit-log` criar a tabela; até lá, um log não falha.
   Registrado — nada de spec pending fingindo cobertura de uma tabela inexistente.
3. **Coerência de workspace por FK COMPOSTA, não trigger** (tarefa 1.2 pede "trigger de
   coerência"). A FK composta `(task_id, workspace_id) → tasks(id, workspace_id)` já GARANTE
   que `task_advances.workspace_id == tasks.workspace_id` (é o padrão do repo — robot-tasks
   fez igual). `by` também por FK composta `(by, workspace_id) → people(workspace_id, id)`
   (nula quando `by` é NULL, MATCH SIMPLE — entradas legadas passam). Mais forte e mais
   simples que um trigger; o trigger de coerência fica subsumido.
4. **Evento pós-commit best-effort** (D6, tarefa 3.5): `ActiveSupport::Notifications`
   `'task.advanced'` num `after_commit`/bloco pós-commit, best-effort (falha vai ao rastreio,
   não à resposta). `realtime-collaboration`/`in-app-notifications` são os consumidores. Se
   `WorkspaceChannel` já existir, também faz broadcast; senão, só a notificação. Sem
   subscriber ainda: sem spec de consumidor.
5. **`PATCH /tasks/:id` JÁ rejeita `progress`/`status`** (robot-tasks G3 devolve 422
   `read_only_field`). A tarefa 4.4 vira refinamento: apontar o endpoint de avanço na
   resposta. Baixo risco.
6. **TENSÃO D-H6 × D-IMUT (descoberta no G1 — precisa de decisão de produto).**
   `commissioning-hierarchy` (D-H6) fez `tasks → robots` `ON DELETE CASCADE` (excluir um
   projeto cascateia até as tarefas, para não dar 500 de FK). `progress-advances` (D-IMUT)
   fez `task_advances → tasks` `ON DELETE RESTRICT` + trigger de imutabilidade — a trilha
   NUNCA é apagada. Consequência: HARD-deletar um robô/célula/projeto que tenha tarefas
   COM avanços FALHARIA (o cascade tentaria apagar `tasks`, e a RESTRICT/trigger aborta →
   500). O soft-delete de `tasks` (decisão 1) resolve o DELETE de tarefa AVULSA, mas NÃO o
   cascade de HARD delete da hierarquia. Resolução completa = a hierarquia
   (projects/cells/robots) também virar soft-delete — FOLLOW-UP de
   `commissioning-hierarchy`/`robot-tasks`, FORA do escopo de progress-advances. A suíte
   fica verde (nenhum spec de exclusão da hierarquia cria avanços antes de excluir); o
   `hierarchy_fk_contract_spec` foi ajustado (task_advances = RESTRICT, com a tensão
   documentada no próprio spec). SINALIZADO ao usuário.

## Armadilhas previstas

1. **REVOKE some no rebuild** (`db:schema:load`): o `REVOKE UPDATE, DELETE ON task_advances`
   da migration C some porque `structure.sql` (pg_dump -x) omite GRANT/REVOKE. Replicar em
   `db/roles.sql` guardado por existência (mesmo padrão de `membership_revocations`), e
   re-rodar roles.sql nos dois bancos após migrar.
2. **Ordem das migrations** (D-IMUT plano): tabela+CHECKs (A) → RLS SELECT/INSERT (B) →
   REVOKE+trigger de imutabilidade (C) → CHECK `done⇒100` em tasks (D). O trigger por
   ÚLTIMO, senão migrations seguintes esbarram nele. `down` de C derruba o trigger primeiro.
3. **`recorded_at` clamp vs CHECK**: o CHECK `recorded_at <= created_at + interval '10 min'`
   é rede de segurança; o clamp real (futuro>skew ou passado>90d → created_at) é no service.
   O service tem de clampar ANTES do insert, senão o CHECK derruba um avanço legítimo de
   relógio errado.
4. **Idempotência ANTES de lock_version** (D-ID): a ordem inverte um 409 falso num retry de
   sucesso. Testar as duas ordens no spec de concorrência.
5. **Soft-delete scoping**: `DeleteService` soft + leitura filtrando `deleted_at IS NULL`.
   Não quebrar as leituras de robot-tasks/batch/sync que consultam `Task`.
6. **Varreduras crescem no grupo**: `POST`/`GET /tasks/:task_id/advances` declaram policy,
   entram no gerador cross-tenant (id no meio → o fake troca o UUID no caminho) e a
   superfície do swagger (`/api/v1/tasks` já coberto).

## Protocolo por grupo

Aplicar (migrations dev+test como migrator; re-rodar roles.sql quando houver REVOKE) →
`rspec` (0 falhas); G5 também `vitest`+`tsc` → marcar `- [x]` → `validate progress-advances
--strict` → UM commit `G<n>:` → resumir e pedir autorização.

7. **`TaskAdvances::CreateService` usa `transaction(requires_new: true)` (savepoint).**
   O request já roda dentro de UMA transação (o middleware de tenant abre uma; nos testes
   `Tenant.with` também). Uma `ActiveRecord::Base.transaction` aninhada SEM `requires_new`
   não cria savepoint: um `StaleObjectError` do `task.update!` marcaria só a interna, o
   `advance.create!` seguiria pendente na EXTERNA, e ela commitaria — o 409 persistiria o
   avanço. Com savepoint, o rollback desfaz a entrada. Bug real, pego pelo teste de
   concorrência (dava 2 avanços). Vale para qualquer service que rode dentro do request e
   precise reverter parcialmente.

## Progresso

- [x] G1 — Esquema + soft-delete (1.1–1.7, 6.3) — task_advances imutável, CHECKs, RLS,
  done⇒100, soft-delete em tasks; 2 specs herdados ajustados (boundary; FK RESTRICT)
- [x] G2 — Máquina de estados (2.1–2.3) — ApplyTransitionService + model TaskAdvance
- [x] G3 — Registro de avanço (3.1–3.6) — CreateService (idempotência, 409, clamp, auto-atribuição, requires_new)
- [x] G4 — API e autorização (4.1–4.5) — TaskAdvancePolicy, POST/GET `/tasks/:task_id/advances`,
  entity TaskAdvance + advances_count/last_comment em Task, hint no 422 do PATCH, request spec das 3 negações.
  **Decisão 8 (nova):** no `CreateService` movi o check de `person.nil?` (422 `sem_pessoa_do_ator`) para
  DEPOIS do `Task.find_by → 404`. Motivo: o ator dono do workspace pode não ter `Person` (make_workspace não
  semeia a do dono); com o check antes, uma tarefa invisível (cross-tenant) respondia 422, não 404, quebrando
  a varredura byte-idêntica. A ordem agora é: idempotência → 404 → pessoa → 409 → transação. Nenhum spec de G3
  quebrou (lá o ator sempre tem Person). Também **adicionei `has_many :task_advances` em `Task`** (faltava; a
  entity o exige) com `dependent: :restrict_with_exception` — a FK no banco já é RESTRICT e a tarefa é
  soft-deletada, nunca destruída. O corpo do 409 sai com `task`/`latest_advance` no TOPO (D-409), não em
  `details` — o endpoint faz `error!({ error: ... }.merge(details), 409)`.
- [x] G5 — Modal de avanço (5.1–5.7) — `features/advances/`: useAdvanceDraft (slider draft??server,
  step lê cache vivo, sem useEffect de sync), useRecordAdvance (uuid vem de fora = idempotência;
  invalida robotTasks + trilha), AdvanceModal (rótulo condicional, confirm bloqueado <100 sem comentário,
  409 preserva comentário + recalcular com uuid novo), AdvanceControls (±10/slider role-gated, view read-only).
  i18n `advances.ts`, `advanceKeys.ts`. **Decisão 9 (nova):** defini `TaskDTO`/`TaskAdvanceDTO` no
  `endpoints.ts` AGORA (a leitura da lista `GET /robots/:id/tasks` é de `robot-task-table`, futura, mas o
  TIPO e o `taskAdvancesApi` são necessários já; o modal lê `progress`/`lock_version` do cache
  `catalogKeys.robotTasks`). **Decisão 10:** o modal abre ao mexer no slider/±10 (o rascunho vira não-nulo);
  o modal É o passo de confirmação — não há um segundo botão "abrir". 95 testes vitest (era 88), tsc limpo.
  Pendência para `robot-task-table`: quem POPULA o cache `catalogKeys.robotTasks(wsId, robotId)` com `TaskDTO[]`
  é aquela change; sem ela o modal lê progress 0 (fallback). O contrato do tipo está aqui.
- [ ] G6 — Integração e fechamento (6.1, 6.2, 6.4)

## RETOMADA (para o próximo agente)

1. `git log --oneline -12` na branch `progress-advances`; um commit por grupo. `tasks.md`
   tem o estado fino; este arquivo tem as decisões.
2. Baseline: pg no ar, migrations como `robotrack_migrator`, `rspec` como `robotrack_app`,
   `vitest`. Se criar tabela com REVOKE, re-rodar `db/roles.sql` nos dois bancos.
3. Reler **Decisões que EU tomo** (1: soft-delete modifica robot-tasks; 2: auditoria é log;
   3: FK composta no lugar de trigger) e **Armadilhas** (1: REVOKE no roles.sql; 2: ordem
   das migrations; 4: idempotência antes do lock).
4. Invioláveis: runtime sem SUPERUSER/BYPASSRLS, RLS forçada, trilha IMUTÁVEL (nem o dono
   edita), cross-tenant = 404, varreduras só crescem.
5. Contratos que esta change DEVOLVE (documentar em 6.1): entrada `legacy` para
   `legacy-data-migration`; aviso "trilha faltando" = `0<progress<100 AND advances_count=0`
   para `robot-task-table`; soft-delete de `tasks` (fechado no G1); env var
   `ADVANCE_RECORDED_AT_SKEW_MINUTES=10` + métrica de 409 para `delivery-and-observability`.
