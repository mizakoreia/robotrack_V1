# Spec — `robot-tasks` (exclusão em lote)

## ADDED Requirements

### Requirement: Exclusão de tarefas em lote numa transação

O sistema SHALL expor `DELETE /api/v1/tasks` recebendo `ids: [String]` que, numa única
transação, faz soft-delete (`deleted_at`) de todas as tarefas visíveis dentre `ids`, remove
os responsáveis dessas tarefas, e recalcula o progresso **uma vez por robô distinto**
afetado. A resposta SHALL informar `deletedCount`.

*Porquê: seleção múltipla no cliente não pode virar N requisições com N recálculos de
rollup e estados intermediários; uma transação com um recálculo por robô é atômica e
barata.*

#### Scenario: soft-delete em lote recalcula o rollup uma vez

- **WHEN** o dono exclui em lote 3 tarefas de um robô
- **THEN** as 3 ganham `deleted_at` e somem das leituras e das views de progresso
- **AND** o progresso ponderado e a contagem crua do robô refletem a remoção
- **AND** o rollup do robô é recalculado uma vez (não três)

#### Scenario: a trilha de avanços é preservada

- **WHEN** uma das tarefas excluídas em lote tinha avanços registrados
- **THEN** os `task_advances` daquela tarefa continuam existindo (FK `RESTRICT`, trilha imutável)

### Requirement: Exclusão em lote é owner-only e isolada por tenant

O sistema SHALL exigir papel `owner` (`destroy_commissioning`) para a exclusão em lote, e
SHALL ignorar ids invisíveis (de outro workspace ou inexistentes) sem vazar a existência —
contando em `deletedCount` apenas o que existia e era visível.

#### Scenario: edit não pode excluir em lote

- **WHEN** um membro `edit` chama `DELETE /api/v1/tasks`
- **THEN** a resposta é 403 e nada é excluído

#### Scenario: id de outro tenant é ignorado

- **WHEN** o dono envia `ids` contendo o id de uma tarefa de outro workspace
- **THEN** essa tarefa NÃO é excluída (invisível pela RLS)
- **AND** `deletedCount` conta apenas as tarefas visíveis do próprio workspace
