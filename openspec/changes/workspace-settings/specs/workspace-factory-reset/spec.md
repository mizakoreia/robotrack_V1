# workspace-factory-reset

## ADDED Requirements

### Requirement: Reset de fábrica exclusivo do dono

O sistema SHALL permitir o reset de fábrica apenas ao papel `owner` do workspace
corrente, validado por policy no servidor, independentemente do que a interface exibe
(§3.11, §4.1 matriz e inv. 1, D3).

#### Scenario: membro edit tentando reset é negado
- **WHEN** um usuário com papel `edit` no workspace `WS-1` envia
  `POST /api/v1/workspace/factory_reset` com frase de confirmação e `backup_id` corretos
- **THEN** a resposta é `403`
- **AND** nenhum projeto, célula, robô ou tarefa de `WS-1` é apagado
- **AND** nenhum registro de auditoria é criado

#### Scenario: membro view tentando reset é negado
- **WHEN** um usuário com papel `view` envia `POST /api/v1/workspace/factory_reset`
- **THEN** a resposta é `403`
- **AND** a contagem de projetos de `WS-1` permanece inalterada

#### Scenario: dono de outro workspace não reseta este
- **WHEN** o dono do workspace `WS-2`, sem membership em `WS-1`, envia o reset apontando
  para `WS-1`
- **THEN** a resposta é `403` ou `404`
- **AND** os dados de `WS-1` permanecem intactos

### Requirement: Confirmação explícita por frase digitada

O sistema SHALL exigir no corpo da requisição o campo `confirmation_phrase` exatamente
igual ao `name` do workspace, comparado **no servidor** após remoção de espaços das
bordas, com sensibilidade a maiúsculas e minúsculas (§3.11, D-RESET-GATE).

#### Scenario: confirmação digitada errada não executa nada
- **WHEN** o workspace se chama `Workspace de Mizael` e o dono envia
  `confirmation_phrase = "Workspace de mizael"`
- **THEN** a resposta é `422` com código `confirmation_mismatch`
- **AND** nenhuma linha é apagada em `projects`, `cells`, `robots`, `tasks`,
  `task_advances` ou `notifications`
- **AND** nenhum registro é acrescentado a `audit_logs`

#### Scenario: confirmação ausente não executa nada
- **WHEN** o dono envia a requisição sem o campo `confirmation_phrase`
- **THEN** a resposta é `422`
- **AND** o estado do workspace é idêntico ao anterior

#### Scenario: confirmação correta com espaços nas bordas é aceita
- **WHEN** o workspace se chama `Linha 300` e o dono envia
  `confirmation_phrase = "  Linha 300  "`
- **THEN** a comparação passa e o reset prossegue para a verificação de backup

### Requirement: Backup recente obrigatório como pré-condição

O sistema SHALL exigir no corpo da requisição um `backup_id` que referencie um
`workspace_backups` do mesmo workspace, com `status = "completed"` e `created_at` dentro
dos últimos 15 minutos, e SHALL recusar a operação caso contrário (D-RESET-GATE; regra de
tarefa destrutiva com backup imediatamente antes).

#### Scenario: reset sem backup é recusado
- **WHEN** o dono envia a requisição com a frase correta e sem `backup_id`
- **THEN** a resposta é `422` com código `backup_required`
- **AND** nenhum dado é apagado

#### Scenario: backup velho é recusado
- **WHEN** o `backup_id` informado aponta para um backup criado há 40 minutos
- **THEN** a resposta é `422` com código `backup_stale`
- **AND** nenhum dado é apagado

#### Scenario: backup de outro workspace é recusado
- **WHEN** o dono de `WS-1` informa um `backup_id` cujo `workspace_id` é `WS-2`
- **THEN** a resposta é `422` com código `backup_mismatch`
- **AND** nenhum dado de `WS-1` nem de `WS-2` é apagado

### Requirement: Destino declarado de cada entidade do workspace

O sistema SHALL executar o reset em uma única transação e SHALL aplicar exatamente o
destino declarado a cada entidade: apagar projetos, células, robôs, tarefas, atribuições,
avanços e notificações; restaurar o catálogo de templates ao seed de fábrica de §1.3;
revogar convites pendentes; preservar `people`, `memberships`, a linha do workspace,
`workspace_backups` e `audit_logs` (§3.11, D-RESET).

#### Scenario: conteúdo hierárquico é apagado
- **WHEN** o dono reseta `WS-1`, que tem 3 projetos, 8 células, 24 robôs, 500 tarefas e
  1.200 avanços
- **THEN** `projects`, `cells`, `robots`, `tasks`, `task_assignees` e `task_advances` de
  `WS-1` ficam com 0 linhas
- **AND** `notifications` de `WS-1` fica com 0 linhas

#### Scenario: catálogo volta ao padrão de fábrica, não a vazio
- **WHEN** o workspace tinha 45 templates (31 padrão editados e 14 criados à mão) e o
  reset é executado
- **THEN** `task_templates` de `WS-1` contém exatamente os 31 templates padrão de §1.3,
  em 9 categorias, todos com `weight = 1`

#### Scenario: pessoas, membros e workspace sobrevivem
- **WHEN** `WS-1` tem 5 pessoas, 3 memberships ativas e o reset é executado
- **THEN** a linha de `workspaces` de `WS-1` continua existindo com o mesmo `id` e o
  mesmo `name`
- **AND** as 5 linhas de `people` e as 3 memberships continuam existindo
- **AND** a `Person` do dono continua existindo e é a autora do registro do reset

#### Scenario: convites pendentes são revogados, não apagados
- **WHEN** `WS-1` tem 2 convites pendentes e 1 já usado, e o reset é executado
- **THEN** os 2 convites pendentes ficam com `revoked_at` preenchido
- **AND** as 3 linhas de `invitations` continuam existindo
- **AND** abrir o link de um convite revogado resulta em erro de convite inválido

### Requirement: Reset preserva a auditoria e registra a si mesmo (D12)

O sistema SHALL não apagar nenhum registro de `audit_logs` durante o reset e SHALL
acrescentar, na mesma transação, um registro descrevendo o reset com as contagens do que
foi removido e o `backup_id` usado (D12, §2.8, §4.1 inv. 3).

#### Scenario: registros anteriores sobrevivem e um novo é acrescentado
- **WHEN** `WS-1` tem 47 registros de auditoria e o dono executa o reset
- **THEN** `audit_logs` de `WS-1` passa a ter 48 registros
- **AND** os 47 registros anteriores permanecem com `id`, `msg` e `recorded_at` inalterados
- **AND** o registro mais recente descreve o reset, nomeando o dono, as contagens
  removidas e o `backup_id`

#### Scenario: nenhuma instrução de exclusão toca a tabela imutável
- **WHEN** o reset é executado com o log de consultas ativo
- **THEN** nenhuma instrução `DELETE` ou `UPDATE` sobre `audit_logs` é emitida
- **AND** nenhuma exceção `PG::InsufficientPrivilege` é levantada

#### Scenario: o modal de auditoria mostra o reset logo depois
- **WHEN** o dono abre o modal de auditoria imediatamente após o reset
- **THEN** o primeiro item da lista é o registro do reset
- **AND** os registros de conclusão de tarefa anteriores ao reset continuam listados

### Requirement: Atomicidade e rollback

O sistema SHALL executar todas as etapas do reset em uma única transação e, diante de
qualquer falha, SHALL reverter integralmente, deixando o workspace no estado exatamente
anterior, sem registro de auditoria do reset (D-RESET-ROLLBACK).

#### Scenario: falha no meio não deixa estado parcial
- **WHEN** a revogação dos convites falha depois de os projetos já terem sido apagados
- **THEN** a transação é revertida
- **AND** os 3 projetos, as 500 tarefas e os 1.200 avanços continuam existindo
- **AND** `audit_logs` continua com 47 registros

#### Scenario: registro do backup sobrevive ao rollback
- **WHEN** o reset falha e é revertido
- **THEN** a linha de `workspace_backups` usada como pré-condição continua existindo com
  `status = "completed"`

#### Scenario: reset não é repetido por reenvio da mesma requisição
- **WHEN** a mesma requisição de reset, com o mesmo `backup_id`, é enviada duas vezes
- **THEN** a segunda resposta é `422` com código `backup_stale` ou `backup_consumed`
- **AND** nenhum segundo registro de reset é acrescentado a `audit_logs`

### Requirement: Sessões abertas reagem ao reset

O sistema SHALL publicar um evento no `WorkspaceChannel` do workspace ao concluir o
reset, e os clientes conectados SHALL descartar o estado em cache do workspace e
recarregar, caindo nos estados vazios (§3.10, D6, D9).

#### Scenario: cliente de outro membro recarrega sem dado obsoleto
- **WHEN** um membro `edit` está com a tela de um robô aberta e o dono executa o reset
- **THEN** o cliente dele recebe o evento de reset
- **AND** as query keys sob `['ws', 'WS-1']` são invalidadas
- **AND** a tela passa a mostrar o estado vazio de "nenhum projeto", sem exibir dados do
  robô apagado

#### Scenario: membro não perde acesso ao workspace
- **WHEN** o reset termina
- **THEN** o membro `edit` continua autenticado e com papel `edit` em `WS-1`
- **AND** não é redirecionado para outro workspace
