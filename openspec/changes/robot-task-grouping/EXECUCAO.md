# EXECUCAO — robot-task-grouping

Mapa de execução. Escrito ANTES do código (commit G0). RETOMADA no fim.

## Ponto de partida

- Branch: `main` @ `0f84014` (= origin/main, com toda a `impeccable-remediation`).
- Marcador de segurança: `git tag pre-task-grouping` @ `0f84014` (voltar:
  `git reset --hard pre-task-grouping`).
- **NÃO** comitar `frontend/vite.config.ts` nem `frontend/src/lib/api/client.ts` (túnel).
- **NÃO** reiniciar servidores de dev (:5173/:3000)/túneis; o Vite recarrega sozinho.

## Reconciliação (mapeado no código, G0)

- Categoria = `tasks.cat` texto livre (1–120), semeada de 9 categorias de template; servidor
  ordena por `position` (sem `ORDER BY cat`). Agrupamento hoje é run-length visual em
  `RobotTaskTablePage.tsx:149-197`.
- Progresso: views SQL no servidor (ponderado ignora N/A; crua conta N/A no total); rollup por
  `Progress::CascadeRecompute`. Cliente só consome.
- Exclusão INDIVIDUAL já existe: soft-delete owner-only (`Tasks::DeleteService`), views filtram
  `deleted_at IS NULL`, avanços preservados (FK RESTRICT + trilha imutável). **"apagar sem
  quebrar cálculo" já está resolvido** — o novo é só o LOTE.

## Ordem dos grupos

| Grupo | Escopo | Camada |
|---|---|---|
| **G1** | Categorias colapsáveis (grupos reais, prefixo A./B., contagem, estado por robô) | frontend |
| **G2** | `Tasks::BulkDeleteService` + `DELETE /tasks` (owner-only, 1 recálculo/robô) | backend |
| **G3** | Seleção múltipla + barra + confirmação → bulkRemove | frontend |
| **G4** | Suíte + validate --strict + docs + ff/push | ambos |

## Decisões fixadas (design.md — não reabrir)

- **D-TG-1** grupos reais por `cat`, ordem por 1ª aparição (corrige título repetido).
- **D-TG-2** prefixo A./B. visual, por índice do grupo.
- **D-TG-3** cabeçalho mostra contagem, nunca % de categoria (não recalcular no cliente).
- **D-TG-4** default tudo aberto; persiste só as recolhidas, por robô, em safeStorage.
- **D-TG-5** colapsar remove `<tr>`/cartões do DOM; `<button aria-expanded>`; a11y.
- **D-TG-6** lote: 1 transação, `update_all(deleted_at:)` (sem callbacks) + `CascadeRecompute`
  1×/robô; SEM `without_cascade`; ids invisíveis ignorados pela RLS.
- **D-TG-7** owner-only no nível de coleção (`TaskPolicy#destroy?`).

## RETOMADA

- **G0** planejamento (proposal/design/tasks/EXECUCAO + 2 spec deltas), validate --strict
  verde, `git tag pre-task-grouping`. Commit `G0`.
- **G1 (colapsável) — FECHADO:** `taskGroups.ts` (groupByCategory por 1ª aparição —
  corrige título repetido; groupLetter A./B.; useCollapsedCategories em safeStorage por
  robô, guarda só recolhidas, default aberto); `RobotTaskTablePage` com CategoryToggle
  (`<button aria-expanded aria-controls>` + prefixo + contagem; recolher REMOVE do DOM)
  nos dois layouts. Prova: taskGroups.test.tsx (4) + robotTaskTable/e2eLoad verdes; tsc 0;
  eslint 0. Commit `G1`.
- **G2 (lote backend) — FECHADO:** `Tasks::BulkDeleteService` (transação, `update_all(deleted_at:)`
  sem callbacks, CascadeRecompute 1×/robô, RLS ignora invisíveis, deleted_count);
  `DELETE /tasks { ids[] }` owner-only. Prova (RSpec): dono exclui N (cache→100, avanços
  intactos, soft não hard), edit→403, tenant alheio ignorado; tasks_spec + matrix 57 ex 0
  falhas. Commit `G2`.
- **G3 (seleção múltipla frontend) — FECHADO:** `robotTasksApi.bulkRemove`, `useBulkDeleteTasks`;
  checkbox owner-only nos dois layouts (props estáveis preservam o memo §7.1), barra de ação +
  modal de confirmação → bulkRemove. Prova: taskBulkDelete.test.tsx (2) + robot-tasks 68
  verdes; tsc 0; eslint 0. Commit `G3`.
- **G4 (fechamento):** validate --strict verde; suíte frontend completa + specs backend das
  áreas verdes; docs (CONTINUIDADE/EXECUCAO); ff `main` + push. Divergência: nenhuma —
  "apagar sem quebrar cálculo" individual já existia; entregue o LOTE.
