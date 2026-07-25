# Tasks — `robot-task-grouping`

Um grupo por vez, prova verde. Marcador de segurança: `git tag pre-task-grouping`.

## G1. Categorias colapsáveis (frontend, sem backend)

- [x] 1.1 `RobotTaskTablePage.tsx`: substituir o run-length por grupos reais — `groupBy(cat)`, ordem por menor `position`, tarefas por `position`. (corrige o título repetido)
- [x] 1.2 Cabeçalho de grupo colapsável nos dois layouts: `<button aria-expanded aria-controls>` + região, prefixo `A./B./C.` (índice), nome, contagem; recolher REMOVE do DOM as tarefas do grupo; chevron.
- [x] 1.3 Estado por robô em `lib/safeStorage` (chave `rt.taskgroups.<robotId>`, guarda só as recolhidas; default tudo aberto; categoria nova nasce aberta).
- [x] 1.4 **Verificação:** Vitest — dois grupos p/ `A,B,A`; recolher tira do DOM; prefixo+contagem; estado lembrado. `tsc`/`lint`. Screenshots desktop+mobile.

## G2. Exclusão em lote (backend)

- [x] 2.1 `Tasks::BulkDeleteService.call(ids:)`: transação — `TaskAssignee.delete_all` das ids, `Task.where(id:).update_all(deleted_at:)`, `Progress::CascadeRecompute` 1×/robô distinto; ignora ids invisíveis (RLS); retorna `{ deleted_count }`.
- [x] 2.2 `api/v1/tasks.rb`: rota de coleção `DELETE /tasks` com `ids: [String]`, `TaskPolicy` ação `destroy` (owner-only); resposta `{ deletedCount }`.
- [x] 2.3 **Verificação (RSpec):** dono exclui N (rollup recalcula 1×/robô, avanços intactos); `edit`→403; id de outro tenant ignorado (`deletedCount` só conta visível).

## G3. Seleção múltipla (frontend)

- [x] 3.1 `endpoints.ts`: `robotTasksApi.bulkRemove(ids)`; `useTaskCrud.ts`: `useBulkDeleteTasks(robotId)` (invalida o trio).
- [x] 3.2 `RobotTaskTablePage.tsx`: modo de seleção owner-only (checkbox por linha nos dois layouts), barra "Excluir N", modal de confirmação → `bulkRemove`; limpa a seleção no sucesso.
- [x] 3.3 **Verificação (Vitest):** dono seleciona 3 e confirma → 1 chamada com 3 ids; `edit`/`view` sem checkboxes. `tsc`/`lint`.

## G4. Verificação e polimento

- [x] 4.1 Suíte completa (Vitest + RSpec das áreas), `tsc`, `lint`; prova do rollup pós-lote; screenshots do colapsável e da seleção.
- [x] 4.2 `openspec validate robot-task-grouping --strict`; docs (CONTINUIDADE/EXECUCAO); ff `main` + push.
