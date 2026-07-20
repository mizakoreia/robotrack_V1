## ADDED Requirements

### Requirement: Trilha de avanços append-only

O sistema SHALL manter uma tabela `task_advances` com PK `uuid` gerável no cliente (D1),
`workspace_id` NOT NULL sob RLS (D2), `task_id`, `by` (referência a `people.id`, nullable),
`author_name_snapshot` (texto NOT NULL), `from_progress` e `to_progress` (inteiros 0–100),
`comment` (texto), `legacy` (booleano NOT NULL default `false`), `recorded_at` e
`created_at`.

A trilha SHALL ser append-only: nenhuma linha de `task_advances` pode ser alterada ou
excluída por nenhum papel, incluindo `owner`. A garantia MUST residir em três camadas —
ausência de policy RLS de `UPDATE`/`DELETE`, `REVOKE UPDATE, DELETE` para o role da
aplicação, e trigger `BEFORE UPDATE OR DELETE` que faz `RAISE EXCEPTION`.

`author_name_snapshot` SHALL ser gravado com o nome da pessoa **no momento do registro** e
nunca recalculado a partir de `people.name` na leitura.

#### Scenario: Avanço registrado grava snapshot imutável do nome do autor

- **WHEN** a pessoa `Ana Souza` registra um avanço `45 → 60` e, depois, seu nome no
  workspace é alterado para `Ana Souza Lima`
- **THEN** a entrada da trilha continua exibindo `author_name_snapshot = "Ana Souza"`
- **AND** a listagem de responsáveis da tarefa exibe `Ana Souza Lima`

#### Scenario: UPDATE em entrada da trilha é rejeitado pelo banco

- **WHEN** um `UPDATE task_advances SET comment = 'outro' WHERE id = '<uuid>'` é executado
  pelo role da aplicação, mesmo autenticado como `owner` do workspace
- **THEN** a operação falha com exceção do Postgres
- **AND** o `comment` original permanece inalterado

#### Scenario: DELETE em entrada da trilha é rejeitado inclusive fora da aplicação

- **WHEN** um `DELETE FROM task_advances WHERE id = '<uuid>'` é executado por uma conexão
  com o role owner da tabela (ex.: migration ou psql administrativo)
- **THEN** o trigger de imutabilidade aborta a transação com `RAISE EXCEPTION`
- **AND** a contagem de entradas da tarefa permanece a mesma

#### Scenario: Não existe endpoint de edição ou exclusão de avanço

- **WHEN** um cliente emite `PATCH /api/v1/advances/<uuid>` ou
  `DELETE /api/v1/advances/<uuid>`
- **THEN** a API responde `404` (rota inexistente)

### Requirement: Dois timestamps por avanço (D8)

Todo avanço SHALL ter `recorded_at` (quando a pessoa agiu, enviado pelo cliente) e
`created_at` (quando o servidor persistiu). O servidor MUST NOT sobrescrever `recorded_at`
válido. Trilha, modal de histórico e relatório de comissionamento SHALL exibir
`recorded_at`.

Se `recorded_at` for omitido, o sistema SHALL usar `now()`. Se `recorded_at` for maior que
`now() + ADVANCE_RECORDED_AT_SKEW_MINUTES` (padrão `10`) ou menor que `now() - 90 dias`, o
sistema SHALL fazer clamp para o instante de persistência e marcar
`recorded_at_adjusted = true`, sem rejeitar o avanço.

O contrato de leitura SHALL expor `synced_late = true` quando
`created_at - recorded_at > 1 hora`.

#### Scenario: Avanço registrado offline às 14h e sincronizado às 17h

- **WHEN** o cliente envia um avanço com `recorded_at = 2026-03-10T14:00:00-03:00` e o
  servidor persiste às `17:05` do mesmo dia
- **THEN** a trilha e o relatório exibem `14:00`
- **AND** `created_at` armazena `17:05`
- **AND** o contrato de leitura retorna `synced_late: true`

#### Scenario: Relógio do tablet adiantado em 3 dias sofre clamp

- **WHEN** o cliente envia `recorded_at = now() + 3 dias`
- **THEN** o avanço é criado com `recorded_at = created_at`
- **AND** o contrato de leitura retorna `recorded_at_adjusted: true`
- **AND** a entrada não aparece no topo permanente da timeline

#### Scenario: Ordenação da trilha é determinística

- **WHEN** dois avanços da mesma tarefa têm `recorded_at` e `created_at` idênticos
- **THEN** a listagem os ordena por `id DESC` como terceiro critério
- **AND** duas requisições consecutivas retornam a mesma ordem

### Requirement: Comentário obrigatório abaixo de 100

O sistema SHALL exigir comentário não vazio sempre que `to_progress < 100`, e SHALL
aceitar comentário ausente quando `to_progress = 100`. A garantia MUST residir em CHECK
constraint (`to_progress = 100 OR legacy OR (comment IS NOT NULL AND btrim(comment) <> '')`),
com validação de model apenas para produzir mensagem pt-BR de `422`. O comentário SHALL ser
limitado a 1000 caracteres por CHECK; o truncamento para a mensagem de notificação é
responsabilidade de `in-app-notifications`.

#### Scenario: 45 → 100 sem comentário é aceito

- **WHEN** um membro `edit` envia um avanço `from_progress = 45`, `to_progress = 100`, sem
  `comment`
- **THEN** a API responde `201`
- **AND** a entrada é criada com `comment = NULL`
- **AND** a tarefa fica `status = "Concluído"`, `progress = 100`

#### Scenario: 45 → 60 sem comentário é rejeitado

- **WHEN** um membro `edit` envia um avanço `from_progress = 45`, `to_progress = 60`, sem
  `comment`
- **THEN** a API responde `422` com mensagem pt-BR referente ao campo `comment`
- **AND** nenhuma linha é criada em `task_advances`
- **AND** `tasks.progress` continua `45`

#### Scenario: Comentário só com espaços é rejeitado pelo banco

- **WHEN** um `INSERT` direto grava `to_progress = 60` e `comment = '   '` contornando o
  model
- **THEN** o Postgres rejeita com violação da CHECK
- **AND** nenhuma linha é criada

#### Scenario: Comentário com 1001 caracteres é rejeitado

- **WHEN** um avanço `20 → 30` é enviado com `comment` de 1001 caracteres
- **THEN** a API responde `422`
- **AND** a mensagem cita o limite de 1000 caracteres

### Requirement: Máquina de estados — mudança de status ajusta o progresso

Ao alterar o `status` de uma tarefa, o sistema SHALL ajustar `progress` conforme §2.2:
`Concluído` → `100`; `N/A` → `0`; `Pendente` → `0`; `Em Andamento` → `progress` inalterado.
O ajuste MUST ocorrer no mesmo serviço transacional
(`Tasks::ApplyTransitionService`), sem caminho paralelo de escrita.

#### Scenario: Status para Concluído leva progresso a 100

- **WHEN** uma tarefa em `progress = 30`, `status = "Em Andamento"` recebe
  `status = "Concluído"`
- **THEN** `progress` passa a `100`
- **AND** um registro de auditoria de conclusão é gravado na mesma transação

#### Scenario: Status para N/A zera o progresso

- **WHEN** uma tarefa em `progress = 70` recebe `status = "N/A"`
- **THEN** `progress` passa a `0` e `status` fica `"N/A"`
- **AND** nenhuma notificação é gerada (progresso `0` não notifica, §2.7)

#### Scenario: Status para Em Andamento preserva o progresso

- **WHEN** uma tarefa em `progress = 35`, `status = "Pendente"` recebe
  `status = "Em Andamento"`
- **THEN** `progress` permanece `35`

#### Scenario: Reabrir tarefa concluída mantém progresso 100

- **WHEN** uma tarefa em `progress = 100`, `status = "Concluído"` recebe
  `status = "Em Andamento"`
- **THEN** `progress` permanece `100` e `status` fica `"Em Andamento"`
- **AND** a CHECK `tasks_done_implies_full` não é violada

### Requirement: Máquina de estados — mudança de progresso ajusta o status

Ao alterar o `progress`, o sistema SHALL derivar o `status` conforme §2.2: `100` →
`Concluído` e grava log de auditoria; `> 0` e `< 100` → `Em Andamento`; `0` → `Pendente`,
**exceto** quando o status atual for `N/A`, que MUST ser preservado. A coerência
`status = 'Concluído' ⇒ progress = 100` MUST residir em CHECK constraint em `tasks`.

#### Scenario: Progresso 100 conclui e audita

- **WHEN** um avanço leva a tarefa de `45` para `100`
- **THEN** `status` passa a `"Concluído"`
- **AND** um registro de auditoria de conclusão a 100% é gravado na mesma transação do
  avanço

#### Scenario: Progresso 60 coloca em andamento

- **WHEN** um avanço leva a tarefa de `0` para `60` com comentário
- **THEN** `status` passa a `"Em Andamento"`

#### Scenario: Tarefa em N/A levada a progresso 0 continua N/A

- **WHEN** uma tarefa com `status = "N/A"`, `progress = 0` recebe um avanço com
  `to_progress = 0` e comentário
- **THEN** `status` permanece `"N/A"` e **não** vira `"Pendente"`
- **AND** a entrada é acrescentada normalmente à trilha

#### Scenario: Tarefa em Em Andamento levada a progresso 0 vira Pendente

- **WHEN** uma tarefa com `status = "Em Andamento"`, `progress = 40` recebe um avanço com
  `to_progress = 0` e comentário
- **THEN** `status` passa a `"Pendente"`

#### Scenario: Progresso não é escrito por nenhuma outra rota

- **WHEN** um cliente envia `PATCH /api/v1/tasks/<id>` com `{"progress": 80}`
- **THEN** a API responde `422` indicando que progresso só muda por registro de avanço
- **AND** `tasks.progress` permanece inalterado

### Requirement: Registro de avanço aplica a transação completa

Ao confirmar um avanço, o sistema SHALL, numa única transação: acrescentar a entrada em
`task_advances`, aplicar a transição de estado (§2.2), executar a auto-atribuição (§2.3),
incrementar `lock_version` da tarefa e gravar auditoria quando `to_progress = 100`. A
publicação de notificações (§2.7) e do evento do `WorkspaceChannel` (D6) MUST ocorrer
**após o commit** e ser best-effort: falha nelas MUST NOT reverter o avanço.

#### Scenario: Falha ao enfileirar notificação não derruba o avanço

- **WHEN** o avanço `45 → 60` é persistido com sucesso e o Redis está indisponível no
  momento de enfileirar a notificação
- **THEN** a API responde `201`
- **AND** a entrada permanece na trilha e `tasks.progress = 60`
- **AND** o erro de enfileiramento é reportado ao rastreio de erro sem alterar a resposta

#### Scenario: Falha ao gravar auditoria reverte o avanço

- **WHEN** o avanço `45 → 100` é registrado e a gravação do log de auditoria falha
- **THEN** a transação inteira é revertida
- **AND** nenhuma entrada é criada na trilha e `tasks.progress` permanece `45`

### Requirement: Auto-atribuição do autor

Alterar `progress` ou `status` de uma tarefa **sem nenhum responsável** SHALL atribuir
automaticamente a `Person` do autor à tarefa, na mesma transação. Se a tarefa já tiver ao
menos um responsável — mesmo que não seja o autor — o sistema MUST NOT alterar a lista. O
sistema SHALL garantir que a `Person` do autor conste do roster de pessoas do workspace,
de forma idempotente. A ausência de duplicata MUST residir em índice único
`(task_id, person_id)` em `task_assignees`.

#### Scenario: Tarefa sem responsável recebe o autor

- **WHEN** `Ana` registra um avanço `0 → 20` numa tarefa com `task_assignees` vazia
- **THEN** `Ana` passa a constar como responsável da tarefa
- **AND** a lista de responsáveis da tarefa tem exatamente 1 item

#### Scenario: Tarefa com outro responsável não é reatribuída

- **WHEN** `Ana` registra um avanço `20 → 40` numa tarefa cujo único responsável é `Bruno`
- **THEN** `Bruno` continua sendo o único responsável
- **AND** `Ana` aparece apenas como contribuidora, derivada da trilha

#### Scenario: Dois avanços simultâneos não duplicam a atribuição

- **WHEN** dois avanços do mesmo autor, na mesma tarefa sem responsáveis, são processados
  concorrentemente
- **THEN** o índice único impede a segunda inserção em `task_assignees`
- **AND** a lista de responsáveis tem exatamente 1 item

#### Scenario: Roster do workspace não ganha nome solto

- **WHEN** a auto-atribuição ocorre para um autor que já é `Person` do workspace
- **THEN** nenhuma `Person` nova é criada
- **AND** nenhum registro identificado por nome de texto é criado (D10/D11)

### Requirement: Concorrência otimista e idempotência

O cliente SHALL enviar o `lock_version` da tarefa e o `uuid` do avanço. O servidor MUST
resolver nesta ordem: (1) se o `uuid` já existe no workspace, responder `200` com o avanço
existente sem criar segunda entrada, sem reaplicar transição e sem re-notificar; (2) senão,
se `lock_version` divergir do atual, responder `409` com o estado atual da tarefa e o
último avanço; (3) senão, criar.

#### Scenario: Reenvio do mesmo uuid é idempotente

- **WHEN** o mesmo `POST` de avanço com `uuid = U1` é reenviado após a resposta ter se
  perdido na rede
- **THEN** a API responde `200` com o avanço `U1` já existente
- **AND** `task_advances` continua com exatamente 1 entrada `U1`
- **AND** nenhuma notificação adicional é enfileirada

#### Scenario: Conflito de versão retorna 409 com o estado atual

- **WHEN** a sessão A abre o modal com `lock_version = 7`, a sessão B registra `45 → 70`
  (elevando para `8`), e A confirma `45 → 60` com `lock_version = 7`
- **THEN** a API responde `409` com `task.progress = 70`, `task.lock_version = 8` e o
  último avanço de B
- **AND** nenhuma entrada de A é criada
- **AND** `tasks.progress` permanece `70`

#### Scenario: Idempotência precede a checagem de versão

- **WHEN** um avanço `U1` já foi aplicado (elevando `lock_version` de `7` para `8`) e o
  cliente reenvia `U1` com `lock_version = 7`
- **THEN** a API responde `200` com `U1`, **não** `409`

### Requirement: Autorização do registro de avanço

O registro de avanço SHALL exigir membership no workspace da tarefa com papel `owner` ou
`edit` (§4.1). Membro `view` MUST receber `403`. Requisição para tarefa de outro workspace
MUST receber `404`, e não `403`, para não vazar a existência do id — a linha é invisível
por RLS (D2). O endpoint MUST declarar sua policy explicitamente, sob pena de falhar o
route-sweep de D3.

#### Scenario: Membro view não registra avanço

- **WHEN** um membro com papel `view` envia `POST /api/v1/tasks/<id>/advances` com
  `45 → 60` e comentário
- **THEN** a API responde `403`
- **AND** nenhuma linha é criada em `task_advances`
- **AND** `tasks.progress` permanece `45`

#### Scenario: Membro view não altera status pela porta de status

- **WHEN** um membro `view` tenta mudar o `status` de uma tarefa para `"Concluído"`
- **THEN** a API responde `403`
- **AND** `status` e `progress` permanecem inalterados

#### Scenario: Tarefa de outro workspace responde 404

- **WHEN** um `owner` do workspace `W1` envia um avanço para uma tarefa do workspace `W2`
- **THEN** a API responde `404`
- **AND** nenhuma linha é criada, nem em `W1` nem em `W2`

#### Scenario: Leitura da trilha respeita o tenant

- **WHEN** uma sessão do workspace `W1` lê `task_advances` diretamente via SQL
- **THEN** a RLS retorna zero linhas pertencentes a `W2`

### Requirement: Entrada legada de nota livre

O sistema SHALL representar a nota livre legada (`obs`, §1.4 item 2) como uma entrada
comum de `task_advances` com `legacy = true`, `by = NULL`,
`author_name_snapshot = "(nota anterior)"`, `from_progress = 0`, `to_progress = 0` e
`comment` contendo o texto da nota. A conversão SHALL ocorrer no importador em lote
(`legacy-data-migration`); `tasks` MUST NOT ter coluna `obs`. Autor nulo MUST ser permitido
somente para entradas `legacy`, garantido pela CHECK `by IS NOT NULL OR legacy`.

#### Scenario: Nota legada aparece na trilha desde o import

- **WHEN** o importador processa uma tarefa com `obs = "Verificar folga do gripper"` e
  `history` vazio
- **THEN** a tarefa passa a ter 1 entrada de trilha com `legacy = true` e
  `author_name_snapshot = "(nota anterior)"`
- **AND** a nota é visível sem que nenhum avanço novo tenha sido registrado

#### Scenario: Entrada não legada com autor nulo é rejeitada

- **WHEN** um `INSERT` grava `legacy = false` e `by = NULL`
- **THEN** o Postgres rejeita com violação da CHECK `by IS NOT NULL OR legacy`

#### Scenario: Nenhum caminho de runtime converte nota em avanço

- **WHEN** o primeiro avanço de uma tarefa importada é registrado
- **THEN** exatamente 1 entrada nova é criada
- **AND** nenhuma entrada `legacy` adicional é gerada nesse momento

#### Scenario: Aviso de trilha faltando conta entradas legadas

- **WHEN** uma tarefa está em `progress = 40` e possui somente 1 entrada `legacy`
- **THEN** o contrato de leitura retorna `advances_count = 1`
- **AND** a condição do aviso "trilha faltando" (`advances_count = 0`) não é satisfeita
