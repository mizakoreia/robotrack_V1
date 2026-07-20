## ADDED Requirements

### Requirement: Passo 1 — quantidade com clamp e Aplicação da leva

O assistente de criação de robôs em lote (§2.5) SHALL aceitar uma quantidade
entre 1 e 50 aplicando **clamp** ao limite superior, e uma Aplicação (§1.2) que
SHALL ser aplicada a todos os robôs da leva. O clamp MUST ser aplicado no
servidor, independentemente do que a interface envie.

#### Scenario: Quantidade 99 é limitada a 50

- **WHEN** o usuário digita `99` no campo de quantidade do passo 1
- **THEN** o passo 2 SHALL apresentar exatamente 50 campos de nome
- **AND** uma requisição de lote com 99 robôs válidos SHALL criar exatamente 50
  robôs, descartando os 49 excedentes sem erro

#### Scenario: Quantidade 0 é elevada a 1

- **WHEN** o usuário digita `0` no campo de quantidade
- **THEN** o passo 2 SHALL apresentar exatamente 1 campo de nome

#### Scenario: Aplicação vale para toda a leva

- **WHEN** a leva é criada com Aplicação `Sealing` e 3 nomes válidos
- **THEN** os 3 robôs criados SHALL ter `application = "Sealing"`

#### Scenario: Aplicação fora do enum é rejeitada

- **WHEN** a requisição de lote informa `application: "Pintura"`
- **THEN** o sistema SHALL responder `422`
- **AND** nenhum robô SHALL ser criado

### Requirement: Passo 2 — nomes por robô, vazios ignorados e dedup na leva

O passo 2 SHALL oferecer um campo de nome por robô com placeholder sugerido no
formato `R01 - Solda`. Nomes vazios (ou só com espaços) MUST ser ignorados e
nomes duplicados **dentro da mesma leva** MUST ser deduplicados, preservando a
primeira ocorrência. O placeholder MUST NOT ser usado como valor quando o campo
ficar vazio.

#### Scenario: Dois nomes iguais na mesma leva geram um robô

- **WHEN** a leva contém os nomes `["R01 - Solda", "R01 - Solda"]`
- **THEN** exatamente 1 robô SHALL ser criado
- **AND** seu nome SHALL ser `"R01 - Solda"`

#### Scenario: Dedup ignora espaços e caixa

- **WHEN** a leva contém `["R02 - Handling", "  r02 -  handling  "]`
- **THEN** exatamente 1 robô SHALL ser criado com o nome `"R02 - Handling"`
  (a primeira ocorrência, preservada como digitada)

#### Scenario: Nomes vazios são ignorados

- **WHEN** a leva de 5 campos contém `["R01", "", "   ", "R02", ""]`
- **THEN** exatamente 2 robôs SHALL ser criados, com nomes `"R01"` e `"R02"`
- **AND** nenhum robô SHALL receber o texto do placeholder como nome

#### Scenario: Leva inteiramente vazia é erro

- **WHEN** todos os campos de nome da leva estão vazios
- **THEN** o sistema SHALL responder `422`
- **AND** SHALL NOT responder `200` com zero robôs criados

#### Scenario: Nome repetido em leva anterior é permitido

- **WHEN** a célula já contém um robô `"R01 - Solda"` e uma nova leva envia
  `["R01 - Solda"]`
- **THEN** um segundo robô com o mesmo nome SHALL ser criado — a dedup vale
  apenas dentro da mesma leva

### Requirement: Materialização das tarefas-base filtradas pela Aplicação

Cada robô criado em lote SHALL receber uma cópia por valor (`cat`, `desc`,
`weight`) dos `task_templates` do workspace que passam no filtro de §2.5, com
`progress: 0`, `status: "Pendente"` e **sem responsável**. A cópia MUST NOT
guardar referência ao template de origem.

#### Scenario: Robô `Sealing` recebe "Calibração de Cola"

- **WHEN** um robô chamado `"R05 - Sealing"` com Aplicação `Sealing` é criado em
  lote sobre o catálogo padrão dos 31 templates (§1.3)
- **THEN** o robô SHALL possuir uma tarefa com `desc = "Calibração de Cola"` e
  `cat = "D. Processo"`

#### Scenario: Robô `Solda MIG` não recebe "Calibração de Cola"

- **WHEN** um robô chamado `"R06 - Solda MIG"` com Aplicação `Solda MIG` é criado
  em lote sobre o mesmo catálogo padrão
- **THEN** o robô SHALL NOT possuir nenhuma tarefa com
  `desc = "Calibração de Cola"`
- **AND** SHALL NOT possuir tarefa com `desc = "Check sinais de Gripper"`
  (cujo `appFilters` é `Handling, Solda Ponto`)
- **AND** SHALL possuir a tarefa `"TCP Check"` (filtro vazio = todas)

#### Scenario: Tarefas materializadas nascem zeradas e sem responsável

- **WHEN** um robô é criado em lote
- **THEN** todas as suas tarefas SHALL ter `progress = 0` e
  `status = "Pendente"`
- **AND** SHALL ter zero linhas em `task_assignees`

#### Scenario: Ordem das tarefas materializadas

- **WHEN** um robô `Handling` é criado a partir do catálogo padrão
- **THEN** as tarefas SHALL receber `position` seguindo a ordem lexicográfica de
  `(cat, desc)`, de modo que `"A. Hardware"` precede `"B. Rede"` que precede
  `"I. Aceitação"`

#### Scenario: Editar o template depois não altera o robô já criado

- **WHEN** um robô é criado em lote com a tarefa `"TCP Check"` e, em seguida, o
  template correspondente tem sua `desc` alterada para `"TCP Check v2"`
- **THEN** a tarefa do robô SHALL continuar com `desc = "TCP Check"`

#### Scenario: Catálogo vazio produz robôs sem tarefas

- **WHEN** o workspace não tem nenhum `task_template` e uma leva de 2 robôs é
  criada
- **THEN** os 2 robôs SHALL ser criados com `tasks: []`
- **AND** a requisição SHALL responder `201`, não erro

### Requirement: Atomicidade e identidade da criação em lote

A criação em lote SHALL ocorrer numa única transação: ou todos os robôs
normalizados e todas as suas tarefas são persistidos, ou nada é. Os `uuid` dos
robôs SHALL ser aceitos do cliente (D1), tornando o reenvio da mesma leva
idempotente por chave primária.

#### Scenario: Falha parcial não deixa leva incompleta

- **WHEN** a criação de uma leva de 10 robôs falha ao inserir as tarefas do 7º
  robô
- **THEN** nenhum dos 10 robôs SHALL existir no banco após a operação
- **AND** nenhuma tarefa da leva SHALL existir

#### Scenario: Reenvio da mesma leva não duplica

- **WHEN** a mesma requisição de lote, com os mesmos `uuid` de robô, é reenviada
  pela fila offline após ter sido aplicada
- **THEN** o sistema SHALL NOT criar robôs duplicados
- **AND** o número total de robôs na célula SHALL permanecer o mesmo

### Requirement: Autorização da criação em lote

A criação de robôs em lote SHALL exigir papel `owner` ou `edit` no workspace da
célula de destino (§4.1), validada no servidor por policy declarada (D3), e
SHALL ser negada para célula de outro workspace.

#### Scenario: Membro `view` não pode criar robôs em lote

- **WHEN** um membro com papel `view` envia
  `POST /api/v1/cells/{cell_id}/robots/batch` com 3 nomes válidos
- **THEN** o sistema SHALL responder `403`
- **AND** nenhum robô e nenhuma tarefa SHALL ser criado

#### Scenario: Célula de outro workspace

- **WHEN** um usuário autenticado em `WS-A` envia uma criação em lote apontando
  para uma célula de `WS-B`
- **THEN** o sistema SHALL responder `404`
- **AND** o corpo SHALL NOT revelar o nome da célula

#### Scenario: Tarefas materializadas herdam o workspace da célula

- **WHEN** uma leva é criada com sucesso na célula do workspace `WS-A`
- **THEN** todas as tarefas criadas SHALL ter `workspace_id = WS-A`
- **AND** SHALL ser invisíveis a uma sessão com
  `app.current_workspace_id = WS-B`
