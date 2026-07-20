## ADDED Requirements

### Requirement: Esquema da entidade Tarefa

O sistema SHALL persistir tarefas numa tabela `tasks` com chave primária `uuid`
aceitável do cliente (D1/D13), pertencente a um robô, contendo `cat` (categoria),
`desc` (descrição), `weight` (numérico, default `1`), `progress` (inteiro 0–100,
default `0`), `status` (enum `Pendente` | `Em Andamento` | `Concluído` | `N/A`,
default `Pendente`), `position` (ordem dentro do robô) e `lock_version`.
A faixa de `progress` MUST ser garantida por `CHECK` no banco e o domínio de
`status` por tipo enum do Postgres — não apenas por validação de model.

#### Scenario: Cliente fornece o uuid da tarefa

- **WHEN** um cliente envia `POST /api/v1/robots/{robot_id}/tasks` com
  `id: "9f1c2d3e-0000-4000-8000-000000000abc"`, `cat: "D. Processo"`,
  `desc: "Calibração de Cola"`
- **THEN** a tarefa SHALL ser persistida exatamente com esse `id`
- **AND** um segundo `POST` com o mesmo `id` SHALL retornar `409` sem criar
  duplicata

#### Scenario: Defaults de uma tarefa recém-criada

- **WHEN** uma tarefa é criada sem informar `weight`, `progress` nem `status`
- **THEN** o registro persistido SHALL ter `weight = 1`, `progress = 0` e
  `status = "Pendente"`
- **AND** SHALL ter zero linhas em `task_assignees`

#### Scenario: Progresso fora da faixa é rejeitado pelo banco

- **WHEN** um `INSERT` direto no banco tenta gravar `progress = 101`
- **THEN** o banco SHALL abortar a operação com violação de `CHECK`

#### Scenario: Status fora do enum é rejeitado pelo banco

- **WHEN** um `INSERT` direto no banco tenta gravar `status = "Concluido"`
  (sem acento)
- **THEN** o banco SHALL abortar a operação com erro de tipo enum inválido

### Requirement: Tenancy da tarefa é obrigação do banco

Toda tarefa SHALL ter `workspace_id NOT NULL` e a tabela `tasks` MUST ter RLS
habilitado com `FORCE`, filtrando por `app.current_workspace_id` (D2). A leitura
de tarefa de outro workspace SHALL resultar em `404`, não `403`.

#### Scenario: Tarefa de outro workspace não é legível

- **WHEN** um usuário autenticado no workspace `WS-A` requisita
  `GET /api/v1/tasks/{id}` de uma tarefa cujo `workspace_id` é `WS-B`
- **THEN** o sistema SHALL responder `404`
- **AND** o corpo da resposta SHALL NOT conter `desc`, `cat` nem qualquer campo
  da tarefa

#### Scenario: Tarefa de outro workspace não é editável

- **WHEN** um usuário autenticado no workspace `WS-A` envia
  `PATCH /api/v1/tasks/{id}` com `desc: "Invadido"` para uma tarefa de `WS-B`
- **THEN** o sistema SHALL responder `404`
- **AND** o valor de `desc` no banco SHALL permanecer inalterado

#### Scenario: `insert_all` sem `workspace_id` falha ruidosamente

- **WHEN** um `INSERT` em `tasks` omite `workspace_id`
- **THEN** o banco SHALL abortar a operação por violação de `NOT NULL` ou da
  policy de RLS

### Requirement: Responsáveis são endereçados por identidade, nunca por nome

O sistema SHALL registrar responsáveis numa tabela de junção `task_assignees`
referenciando `people.id` (D10). A ausência de responsável SHALL ser representada
como conjunto vazio; o valor `"Não Atribuído"` MUST NOT ser persistível como
responsável (D11). A tabela `tasks` MUST NOT possuir coluna `resp` e o sistema
MUST NOT gravar `resp = assignees[0] || "Não Atribuído"` em nenhum caminho de
escrita — a leitura tolerante de §1.4 item 1 pertence exclusivamente ao
importador de `legacy-data-migration`.

#### Scenario: Esquema não expõe responsável por texto

- **WHEN** o esquema de `tasks` é inspecionado após as migrations
- **THEN** SHALL NOT existir coluna `resp`, `assignees` nem qualquer coluna de
  texto destinada a nome de responsável

#### Scenario: Mesma pessoa não é atribuída duas vezes

- **WHEN** duas requisições concorrentes tentam inserir
  `(task_id: T1, person_id: P1)` em `task_assignees`
- **THEN** o índice único `(task_id, person_id)` SHALL fazer a segunda falhar
- **AND** a tarefa `T1` SHALL ter exatamente uma linha de responsável

#### Scenario: Pessoa de outro workspace não pode ser atribuída pelo banco

- **WHEN** um `INSERT` direto tenta gravar `task_assignees` com uma `task_id` de
  `WS-A` e uma `person_id` de `WS-B`
- **THEN** a FK composta `(person_id, workspace_id)` SHALL abortar a operação

#### Scenario: Tarefa sem responsável

- **WHEN** uma tarefa é lida e não possui linhas em `task_assignees`
- **THEN** a entity SHALL retornar `assignees: []`
- **AND** SHALL NOT retornar nenhum item com nome `"Não Atribuído"`

### Requirement: Substituição do conjunto de responsáveis

O sistema SHALL expor `PUT /api/v1/tasks/{id}/assignees` recebendo
`{person_ids: [...], lock_version: N}`, que substitui integralmente o conjunto de
responsáveis da tarefa e SHALL retornar o diff `{added, removed}` para consumo de
`in-app-notifications` (§2.7). A operação MUST ser idempotente.

#### Scenario: Substituição calcula o diff

- **WHEN** a tarefa tem responsáveis `[P1, P2]` e recebe
  `PUT` com `person_ids: [P2, P3]`
- **THEN** o conjunto persistido SHALL ser exatamente `[P2, P3]`
- **AND** a resposta SHALL conter `added: [P3]` e `removed: [P1]`
- **AND** `P2` SHALL NOT aparecer em `added`

#### Scenario: Reenvio idêntico é inócuo

- **WHEN** o mesmo `PUT` com `person_ids: [P2, P3]` é reenviado (retry da fila
  offline) sobre a tarefa que já tem `[P2, P3]`
- **THEN** a resposta SHALL conter `added: []` e `removed: []`
- **AND** o conjunto persistido SHALL continuar `[P2, P3]`

#### Scenario: Lista vazia remove todos os responsáveis

- **WHEN** a tarefa tem responsáveis `[P1]` e recebe `PUT` com `person_ids: []`
- **THEN** a tarefa SHALL ficar com zero linhas em `task_assignees`
- **AND** o sistema SHALL NOT criar nenhuma `Person` chamada `"Não Atribuído"`

#### Scenario: Pessoa de outro workspace não pode ser atribuída pela API

- **WHEN** um usuário de `WS-A` envia `PUT /api/v1/tasks/{id}/assignees` com
  `person_ids: ["<id de uma Person de WS-B>"]`
- **THEN** o sistema SHALL responder `404`
- **AND** o conjunto de responsáveis da tarefa SHALL permanecer inalterado

#### Scenario: Pessoa nova cadastrada no modal já entra atribuída

- **WHEN** o cliente cria a pessoa `"Marcos Lima"` via `POST /api/v1/people` com
  uuid gerado no cliente e em seguida envia `PUT .../assignees` incluindo esse id
- **THEN** a pessoa SHALL constar em `added` na resposta
- **AND** SHALL permanecer disponível na lista de pessoas do workspace após a
  operação

### Requirement: CRUD de tarefa avulsa

O sistema SHALL permitir adicionar uma tarefa avulsa a um robô existente, editar
sua descrição e excluí-la. O endpoint de edição MUST rejeitar payloads contendo
`progress` ou `status` — essas transições pertencem a `progress-advances` (§2.2).

#### Scenario: Adicionar tarefa avulsa

- **WHEN** um membro `edit` envia `POST /api/v1/robots/{robot_id}/tasks` com
  `cat: "Z. Extra"`, `desc: "Ajuste de gripper"`
- **THEN** a tarefa SHALL ser criada com `progress = 0`, `status = "Pendente"`,
  `weight = 1` e sem responsáveis
- **AND** sua `position` SHALL ser maior que a de todas as tarefas já existentes
  no robô

#### Scenario: Editar descrição

- **WHEN** um membro `edit` envia `PATCH /api/v1/tasks/{id}` com
  `desc: "TCP Check (revisado)"` e o `lock_version` corrente
- **THEN** a descrição SHALL ser atualizada
- **AND** `lock_version` SHALL ser incrementado em 1

#### Scenario: Edição rejeita mudança de progresso

- **WHEN** um membro `edit` envia `PATCH /api/v1/tasks/{id}` com
  `desc: "TCP Check"` e `progress: 50`
- **THEN** o sistema SHALL responder `422`
- **AND** nem `desc` nem `progress` SHALL ser alterados no banco

#### Scenario: Conflito de versão na edição

- **WHEN** dois clientes leem a tarefa com `lock_version: 3` e ambos enviam
  `PATCH` com `lock_version: 3`
- **THEN** o primeiro SHALL receber `200` e o segundo SHALL receber `409`
- **AND** a resposta `409` SHALL conter o estado atual da tarefa

#### Scenario: Excluir tarefa

- **WHEN** um membro `edit` envia `DELETE /api/v1/tasks/{id}` de uma tarefa com
  dois responsáveis
- **THEN** a tarefa SHALL ser removida
- **AND** as duas linhas correspondentes de `task_assignees` SHALL ser removidas
  em cascata

#### Scenario: Membro `view` não pode criar tarefa

- **WHEN** um membro com papel `view` envia
  `POST /api/v1/robots/{robot_id}/tasks` com `desc: "Nova tarefa"`
- **THEN** o sistema SHALL responder `403`
- **AND** nenhuma linha SHALL ser inserida em `tasks`

#### Scenario: Membro `view` não pode excluir nem atribuir

- **WHEN** um membro com papel `view` envia `DELETE /api/v1/tasks/{id}` e, em
  seguida, `PUT /api/v1/tasks/{id}/assignees` com `person_ids: []`
- **THEN** ambas as requisições SHALL responder `403`
- **AND** a tarefa e seu conjunto de responsáveis SHALL permanecer inalterados

### Requirement: Leitura das tarefas de um robô

O sistema SHALL expor as tarefas de um robô ordenadas por `position`, com os
responsáveis representados por `{id, name}` a partir de `people`, e SHALL tratar
robô sem tarefas como lista vazia (§1.4, normalização defensiva).

#### Scenario: Ordem estável por position

- **WHEN** um robô tem tarefas com `position` `0, 1, 2` e o cliente requisita
  `GET /api/v1/robots/{robot_id}/tasks`
- **THEN** as tarefas SHALL retornar na ordem crescente de `position`

#### Scenario: Robô sem tarefas

- **WHEN** um robô recém-criado sem nenhuma tarefa é requisitado
- **THEN** o sistema SHALL responder `200` com `tasks: []`
- **AND** SHALL NOT responder `404` nem erro
