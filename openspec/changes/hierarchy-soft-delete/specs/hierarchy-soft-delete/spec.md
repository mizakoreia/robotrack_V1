# hierarchy-soft-delete

## ADDED Requirements

### Requirement: Soft-delete de projeto, célula e robô

O sistema SHALL persistir uma coluna `deleted_at timestamptz NULL` em `projects`, `cells` e
`robots`, e os models `Project`, `Cell` e `Robot` SHALL aplicar
`default_scope { where(deleted_at: nil) }` de modo que toda leitura de domínio por
ActiveRecord ignore linhas arquivadas (espelhando `tasks`). A exclusão de um nó da
hierarquia SHALL ser um soft-delete (marcar `deleted_at`), NUNCA um `DELETE` físico. O
contrato HTTP do endpoint de exclusão SHALL permanecer `204`.

#### Scenario: Excluir robô com avanços responde 204, não 500
- **GIVEN** um robô com tarefas, e ao menos uma tarefa com um avanço registrado em
  `task_advances`
- **WHEN** o endpoint de exclusão do robô é chamado por um papel autorizado
- **THEN** a resposta SHALL ser `204`
- **AND** a linha do robô SHALL continuar existindo com `deleted_at` preenchido
- **AND** as linhas de `task_advances` das suas tarefas SHALL permanecer intactas

#### Scenario: Nó arquivado some da leitura de domínio
- **GIVEN** uma célula com dois robôs, um deles arquivado
- **WHEN** a tela da célula (overview) é lida
- **THEN** apenas o robô vivo SHALL aparecer

#### Scenario: Exclusão de ancestral arquiva a subárvore inteira
- **GIVEN** um projeto com células, robôs e tarefas
- **WHEN** o projeto é excluído
- **THEN** o projeto, suas células, seus robôs e suas tarefas SHALL ter `deleted_at`
  preenchido
- **AND** nenhuma linha de `task_advances` SHALL ser apagada

### Requirement: Progresso ignora nós arquivados

As views de progresso (`robot_weighted_progress`, `cell_weighted_progress`,
`project_weighted_progress`, `subtree_raw_completion`) SHALL excluir `robots`, `cells` e
`projects` com `deleted_at` não-nulo, de forma que um nó arquivado NÃO contribua para
nenhuma das duas métricas (§2.1 ponderada, §3.2 contagem crua).

#### Scenario: Robô arquivado deixa de arrastar a média da célula
- **GIVEN** uma célula com dois robôs, um a 100% e outro a 0%
- **WHEN** o progresso ponderado da célula é lido
- **THEN** o valor SHALL ser `50`
- **WHEN** o robô de 0% é arquivado e o progresso da célula é recalculado
- **THEN** o valor SHALL ser `100`

#### Scenario: Tarefa arquivada continua fora da contagem crua
- **GIVEN** a contagem crua de um escopo já exclui tarefas com `deleted_at`
- **WHEN** um robô inteiro é arquivado
- **THEN** as tarefas dele SHALL sair também da contagem crua do escopo pai

### Requirement: Nome e posição após arquivamento

Os índices de unicidade de nome por escopo (`(workspace_id|project_id|cell_id, lower(name))`)
SHALL considerar apenas linhas com `deleted_at IS NULL`, permitindo reusar o nome de um nó
arquivado. A coluna `position` SHALL ser nullable, e o soft-delete SHALL zerá-la para `NULL`,
de modo que a reordenação dos irmãos vivos não colida com o nó arquivado. A constraint
DEFERRABLE de unicidade de posição SHALL permanecer.

#### Scenario: Nome de nó arquivado fica livre
- **GIVEN** um robô "R-014" arquivado em uma célula
- **WHEN** um novo robô "R-014" é criado na mesma célula
- **THEN** a resposta SHALL ser `201`, não `409 name_taken`

#### Scenario: Reordenar irmãos vivos após arquivar não viola unicidade
- **GIVEN** três robôs nas posições 0, 1, 2 numa célula
- **WHEN** o robô da posição 1 é arquivado e os dois restantes são reordenados
- **THEN** a reordenação SHALL concluir sem violar a constraint de posição

### Requirement: Isolamento de tenant preservado no soft-delete

O soft-delete SHALL respeitar a Row Level Security: excluir um nó de outro workspace SHALL
responder `404` com corpo byte-idêntico ao de um id inexistente, sem revelar a existência da
linha.

#### Scenario: Soft-delete cross-tenant responde 404
- **GIVEN** um robô pertencente ao workspace `B`
- **WHEN** uma sessão do workspace `A` chama a exclusão desse robô
- **THEN** a resposta SHALL ser `404`
- **AND** a linha em `B` SHALL permanecer com `deleted_at` nulo (não arquivada)
