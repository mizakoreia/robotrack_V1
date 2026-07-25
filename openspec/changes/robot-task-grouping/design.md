# Design — `robot-task-grouping`

## D-TG-1 — Grupos reais por `cat`, ordem por 1ª aparição

Hoje o agrupamento é run-length sobre a ordem por `position` (separador quando `cat`
muda). **Decisão:** montar grupos de verdade no cliente — `groupBy(tasks, cat)`, com a
ordem dos grupos dada pela **menor `position`** de cada categoria e as tarefas dentro do
grupo por `position`. Isso corrige o defeito do título repetido (categorias não
contíguas viram um grupo só) e é pré-requisito do colapsável.

**Descartado:** ordenar no servidor por `cat` (`ORDER BY cat, position`). Mudaria o
contrato de leitura e a ordem visível hoje; o agrupamento é de apresentação e cabe no
cliente. A ordem por 1ª aparição preserva a ordem que o template já semeia.

## D-TG-2 — Prefixo A./B./C. é visual, por índice do grupo

`cat` é texto livre; não há ordenação canônica. **Decisão:** o prefixo é a letra do
índice do grupo na tela (0→A, 1→B, …). É rótulo, não dado — se uma categoria nova surgir
no meio, as letras deslocam (aceitável). Acima de 26 grupos (irreal aqui) cai para número.

## D-TG-3 — Cabeçalho de grupo mostra CONTAGEM, nunca % de categoria

O servidor entrega progresso por robô/célula/projeto, não por categoria. Calcular um %
por categoria no cliente violaria "nada de progresso recalculado no cliente" (D15).
**Decisão:** o cabeçalho mostra só a contagem de tarefas do grupo (`length` do array —
não é métrica de progresso). Se um dia quisermos % por categoria, ele nasce no servidor.

## D-TG-4 — Estado colapsado: todas abertas, lembrado por robô

**Decisão:** default = todas expandidas; o estado por categoria é persistido em
`lib/safeStorage` sob uma chave por robô (`rt.taskgroups.<robotId>`). Guardamos só as
categorias **fechadas** (conjunto) — ausência = aberta, então o default "tudo aberto" não
precisa escrever nada e categorias novas nascem abertas. `safeStorage` degrada em memória
quando o storage é bloqueado (o estado não sobrevive a reload nesse nível — honesto).

## D-TG-5 — Colapsável nos dois layouts, acessível

Tabela `md+`: o cabeçalho do grupo é uma `<tr>` com um `<button aria-expanded aria-controls>`;
colapsar **remove do DOM** as `<tr>` das tarefas daquele grupo (não `display:none`) — DOM
limpo, sem paradas de Tab fantasma. Cartões mobile: uma seção com o mesmo cabeçalho e as
cartas renderizadas condicionalmente. Chevron gira; `prefers-reduced-motion` já é zerado
globalmente. Teclado: o `<button>` nativo cobre Enter/Espaço.

## D-TG-6 — Exclusão em lote: uma transação, um recálculo por robô, RLS ignora invisíveis

**Decisão:** `Tasks::BulkDeleteService.call(ids:)`:
- `Task.find_by(id:)` roda sob RLS como `robotrack_app` → ids de outro tenant/inexistentes
  voltam `nil` e são **ignorados** (não se vaza 404 por item; a resposta é `{ deletedCount }`
  do que de fato existia e era visível).
- Numa transação: `TaskAssignee.where(task_id: ids).delete_all`,
  `Task.where(id: ids).update_all(deleted_at: Time.current)` (sem callbacks → sem cascata
  por linha), e `Progress::CascadeRecompute.call(robot_id:)` **uma vez por robô distinto**.
- **Não** uso `Progress.without_cascade` (aquele contrato exige terminar em `BulkRecompute`,
  que é workspace-wide e pesado): como o `update_all` não dispara cascata, basta eu chamar
  `CascadeRecompute` explicitamente ao fim, por robô. Correto e barato para um punhado de
  tarefas de um robô.

**Descartado:** cliente em laço de `DELETE /tasks/:id`. Seriam N requisições e N recálculos
de rollup, com estados intermediários visíveis. O endpoint de coleção é atômico e recalcula
uma vez.

**Descartado:** hard delete. A FK `task_advances → tasks` é `ON DELETE RESTRICT` e a trilha é
imutável — soft-delete é a única via que preserva a auditoria (é o que a exclusão individual
já faz).

## D-TG-7 — Owner-only, no nível de coleção

O endpoint `DELETE /tasks` declara `TaskPolicy` ação `destroy` (= `destroy_commissioning`,
owner). É permissão de PAPEL (não por-registro) — a visibilidade por-registro é da RLS. `edit`
e `view` recebem 403, igual à exclusão individual. Na UI, os checkboxes e a barra de ação só
aparecem para o dono (espelha o `canDelete` da lixeira).

## Onde cada garantia mora

| Garantia | Mora em | Prova |
|---|---|---|
| Agrupar/ordenar por categoria | cliente (`RobotTaskTablePage`) | Vitest de render |
| Estado colapsado por robô | `lib/safeStorage` | Vitest |
| Rollup correto após lote | views SQL + `CascadeRecompute` (1×/robô) | RSpec |
| Owner-only do lote | `TaskPolicy#destroy?` | RSpec negativo (edit→403) |
| Isolamento de tenant | RLS (ids invisíveis ignorados) | RSpec cross-tenant |
| Auditoria preservada | soft-delete + FK RESTRICT + trigger | RSpec (avanços intactos) |
