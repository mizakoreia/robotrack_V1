# Soft-delete da hierarquia (projeto/célula/robô)

## Why

A ESPECIFICACAO.md descreve a exclusão de itens da hierarquia (§2.9 — "excluir um
projeto/célula/robô") e o reset de fábrica (§3.11) como operações do produto. O porte,
porém, criou uma **contradição estrutural** entre duas decisões já implementadas:

- **`progress-advances` (D-IMUT)**: a trilha de avanços é imutável no banco. `task_advances`
  tem `REVOKE UPDATE, DELETE ... FROM robotrack_app` + trigger que barra mutação para
  **todos os papéis**, e a FK `task_advances → tasks` é `ON DELETE RESTRICT`. As tarefas já
  são **soft-deletadas** (`tasks.deleted_at` + `default_scope`), exatamente para que apagar
  uma tarefa não colidisse com a trilha imutável que aponta para ela.
- **`commissioning-hierarchy` (D-H6)**: excluir projeto/célula/robô é um DELETE físico que
  **cascateia por FK do banco** (`ON DELETE CASCADE` de célula→projeto, robô→célula; e
  robô→tarefa). `Hierarchy::CrudService#destroy` chama `record.destroy!`.

As duas nunca foram reconciliadas. Na prática, **`destroy!` de um robô (ou de qualquer
ancestral) com tarefas que têm avanços resulta em 500**: o cascade tenta apagar as tarefas,
a FK `ON DELETE RESTRICT` dos avanços aborta a transação. É o caso NORMAL — todo robô com
progresso registrado tem avanços. A pendência está anotada na CONTINUIDADE como
"D-H6×D-IMUT" e reaparece como **bloqueio duro** do reset de fábrica (`workspace-settings`
G5), que precisa apagar a hierarquia inteira mas não pode tocar na trilha imutável.

A resolução é a MESMA que `tasks` já adotou e que a D12 aplicou a `audit_logs`: **não
apagar — arquivar**. Esta capacidade estende o soft-delete que hoje só existe em `tasks`
para os três níveis da hierarquia (`projects`, `cells`, `robots`), converte a exclusão em
soft-delete **em cascata na aplicação** (o cascade de FK física deixa de disparar porque
não há mais DELETE), e **blinda todo caminho de leitura** — models, views SQL e SQL cru —
para que um nó arquivado suma da tela e do cálculo de progresso sem violar a imutabilidade.

O contrato externo do endpoint de exclusão **não muda**: continua respondendo `204`. O
cliente não distingue soft de hard — a diferença é inteiramente de servidor/banco.

## What Changes

- **Esquema**: `deleted_at timestamptz NULL` em `projects`, `cells`, `robots`. Os índices
  únicos de nome (`(escopo, lower(name))`) viram **parciais** `WHERE deleted_at IS NULL`
  (nome pode ser reusado depois de arquivar). `position` passa a **nullable** e é zerada
  para `NULL` no soft-delete — assim o nó arquivado sai do domínio da constraint DEFERRABLE
  de posição sem colidir com a renumeração dos irmãos vivos.
- **Views de progresso**: as quatro views (`robot_weighted_progress`,
  `cell_weighted_progress`, `project_weighted_progress`, `subtree_raw_completion`) ganham
  `deleted_at IS NULL` nos lados de `robots`/`cells`/`projects` (hoje só filtram `tasks`).
  Sem isso, um robô arquivado continuaria arrastando a média da célula.
- **Models**: `default_scope { where(deleted_at: nil) }` em `Project`/`Cell`/`Robot`,
  espelhando `Task`.
- **Exclusão**: `Hierarchy::SoftDeleteService` arquiva a subárvore (nó + descendentes +
  tarefas) numa transação e recalcula o progresso do pai. `Hierarchy::CrudService#destroy`
  passa a chamá-lo em vez de `record.destroy!`.
- **Leitura em SQL cru**: `deleted_at IS NULL` nos leitores que tocam a hierarquia por SQL
  (cascata/reconciliação/dump de progresso, relatório de comissionamento, minhas-tarefas) e
  nos agregadores que fazem JOIN de associação (o `default_scope` do model juntado NÃO entra
  na condição do JOIN automaticamente).

## Não-objetivos

- **Não** implementa o reset de fábrica (`workspace-settings` G5) — apenas o desbloqueia. O
  reset passa a ser um caso de "arquivar todos os projetos do workspace" reusando esta
  capacidade, em change própria.
- **Não** adiciona UI de "lixeira"/restauração. Soft-delete aqui é mecanismo de
  integridade (preservar a trilha imutável), não uma feature de recuperação exposta ao
  usuário. Restaurar um nó arquivado é caminho interno, sem tela nesta change.
- **Não** remove o `ON DELETE CASCADE` das FKs físicas nem o `REVOKE`/trigger de
  `task_advances`. Eles permanecem como rede de segurança para a exclusão real do workspace
  (fim de conta), fora deste escopo.
- **Não** mexe no frontend: o endpoint de exclusão mantém o contrato `204`.

## Traduções do legado

No Firestore o "delete" apagava o documento e todos os aninhados de fato; a trilha de logs
era coleção separada e sobrevivia. O porte relacional não tem esse luxo — as FKs amarram os
avanços às tarefas. Trocamos o "apagar de fato" por "marcar arquivado", que é o que preserva
a semântica observável (o item some) sem quebrar a imutabilidade que o modelo relacional
tornou explícita.
