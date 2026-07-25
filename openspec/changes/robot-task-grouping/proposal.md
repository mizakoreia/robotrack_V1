# Proposta — `robot-task-grouping`

## Why

Pedido do dono, sobre a tela operacional do robô (`RobotTaskTablePage`):

1. **Categorias colapsáveis.** Hoje as categorias (`tasks.cat`, texto livre — ex.:
   "Hardware", "Rede") só existem como um SEPARADOR VISUAL: `RobotTaskTablePage.tsx`
   desenha um título toda vez que `cat` muda entre linhas consecutivas (run-length
   sobre a ordem por `position`). Não são grupos de verdade, não colapsam, e se duas
   tarefas da mesma categoria não estiverem contíguas o título repete (a própria
   crítica registrou isso). O operador de robô com 31 tarefas em 9 categorias rola
   uma lista longa sem conseguir recolher o que já resolveu.
2. **Apagar tarefas sem quebrar os cálculos.** Isto **já funciona** para UMA tarefa
   (soft-delete owner-only + as views de progresso filtram `deleted_at IS NULL` →
   o ponderado e a contagem crua recalculam ignorando-a, e a trilha de avanços é
   preservada por FK `RESTRICT` + trilha imutável). O que falta é **exclusão em
   lote por seleção múltipla**: marcar várias tarefas e apagá-las de uma vez, sem N
   requisições e N recálculos.

## What Changes

### G1 — Categorias colapsáveis (frontend, sem backend)

- `RobotTaskTablePage` passa a montar **grupos reais** por `cat` (ordem dos grupos
  pela 1ª aparição por `position`; tarefas por `position` dentro do grupo) — o que
  também corrige o bug do título repetido para categorias não contíguas.
- Cada categoria ganha um **cabeçalho colapsável** (`<button aria-expanded>` +
  região `aria-labelledby`): **prefixo sequencial A. / B. / C.** (por índice do
  grupo, visual), o nome da categoria e a **contagem de tarefas** do grupo (nunca um
  % de categoria — não se recalcula métrica no cliente).
- Colapsa/expande nos **dois layouts** (tabela `md+` e cartões abaixo de `md`), com
  teclado (Enter/Espaço), leitor de tela e `prefers-reduced-motion`.
- **Todas abertas** por padrão; o estado (por categoria) é **lembrado por robô** via
  `lib/safeStorage`.

### G2 — Exclusão em lote (backend)

- `Tasks::BulkDeleteService.call(ids:)`: numa **única transação**, soft-delete de
  todas as tarefas visíveis dentre `ids` (via `update_all(deleted_at:)`, sem
  callbacks), remove os `TaskAssignee` correspondentes, e chama
  `Progress::CascadeRecompute` **uma vez por robô distinto** (não por tarefa) — o
  rollup recalcula certo com um recálculo por robô, não N.
- Endpoint `DELETE /api/v1/tasks` (coleção) com `ids: [String]`, `TaskPolicy` ação
  `destroy` (**owner-only** — `edit`/`view` recebem 403). Ids invisíveis (outro
  tenant / inexistentes) são **ignorados** pela RLS (não vazam 404 por item);
  resposta `{ deletedCount }`.
- A trilha de avanços continua **preservada** (soft-delete + FK `RESTRICT` +
  trigger de imutabilidade — nada muda no contrato de auditoria).

### G3 — Seleção múltipla (frontend)

- Modo de seleção **owner-only** na tabela do robô (checkbox por linha, espelhando
  quem já vê a lixeira), barra de ação "Excluir N tarefas" quando ≥1 marcada, e
  **modal de confirmação** (primitivo `Modal`) → chama o endpoint do G2. Invalida o
  trio de chaves do robô (`robotTasks` + `qk.robot` exato + `qk.projects`).

### G4 — Verificação e polimento

- Suíte (Vitest + RSpec) das áreas tocadas, `tsc`, `lint`, e prova de que o rollup
  fica correto após a exclusão em lote. Screenshots do colapsável (desktop + mobile).

### Não-objetivos

- **Relatório.** O Protocolo agrupa por hierarquia (projeto/célula/robô), não por
  categoria — fica intocado.
- **Modelo de categorias.** `cat` continua texto livre por tarefa; não vira tabela
  nem enum, e não se introduz ordenação canônica das 9 categorias (o prefixo A./B.
  é só visual, pela ordem na tela).
- **Cálculo de progresso.** As fórmulas (views SQL) não mudam; a exclusão em lote
  reusa o mesmo `CascadeRecompute`.
- **Backend para o colapsável.** É apresentação; nenhuma rota nova para o G1.

## Capabilities

### Modified Capabilities

- `robot-task-table` — as categorias na tela do robô passam a ser grupos colapsáveis
  (com prefixo A./B./C., contagem, estado lembrado por robô) e a tela ganha seleção
  múltipla de tarefas para exclusão em lote (owner-only).
- `robot-tasks` — além da exclusão individual (que já existe), o sistema passa a
  excluir tarefas em lote numa transação, com um recálculo de rollup por robô.

### New Capabilities

Nenhuma.

## Impact

- **Frontend:** `app/pages/RobotTaskTablePage.tsx` (grupos colapsáveis + seleção),
  `features/robot-tasks/useTaskCrud.ts` (hook de exclusão em lote),
  `lib/api/endpoints.ts` (`robotTasksApi.bulkRemove`), i18n, testes Vitest.
- **Backend:** `app/services/tasks/bulk_delete_service.rb` (novo),
  `app/controllers/api/v1/tasks.rb` (rota de coleção `DELETE /tasks`), RSpec.
- **Marcador de segurança:** `git tag pre-task-grouping` no commit anterior.
- **Risco residual:** a colapsabilidade da TABELA desktop esconde as `<tr>` do grupo
  (semântica `aria-expanded`/região no cabeçalho de grupo); testar teclado/leitor.
  A exclusão em lote é owner-only e atômica; ids invisíveis são ignorados (não 404
  por item) — decisão registrada no `design.md`.
