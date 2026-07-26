## ADDED Requirements

### Requirement: O pipeline honra as preferências sem regredir invariantes

O `CreateService` SHALL, depois de montar os candidatos (responsáveis ∪ dono) e resolver o
`ctx`, aplicar o filtro de preferências — adicionando seguidores do galho e removendo
silenciadores pela regra "mais específico vence" (D-P3) — **antes** de subtrair o autor e de
inserir, preservando dedup, "nunca o autor", RLS e o caráter best-effort pós-commit.

#### Scenario: seguidor não-autor é adicionado ao universo

- **WHEN** Bruno avança uma tarefa e Carla (não-responsável) tem `follow` no robô
- **THEN** Carla recebe uma notificação de avanço
- **AND** Bruno (autor) não recebe

#### Scenario: seguidor que é o autor não se auto-notifica

- **WHEN** Bruno tem `follow` no robô e é ele quem registra o avanço
- **THEN** Bruno não recebe (a subtração do autor se aplica ao universo, seguidores incluídos)

#### Scenario: silenciador responsável é removido

- **WHEN** Ana é responsável e tem `mute` no robô, e Bruno avança a tarefa
- **THEN** Ana não recebe
- **AND** o avanço permanece salvo (o filtro roda no job best-effort, fora da transação)

#### Scenario: dedup preservado com seguidor repetido

- **WHEN** uma pessoa é responsável **e** tem `follow` na célula do mesmo galho
- **THEN** exatamente uma notificação é criada para ela

#### Scenario: preferências indisponíveis não derrubam o avanço

- **WHEN** a leitura de `notification_subscriptions` falha durante o job
- **THEN** o job falha e retenta; o `task_advance` permanece persistido e a requisição do
  avanço já retornou sucesso

### Requirement: Notificação de atribuição a terceiros (assign observador)

Quando pessoas são atribuídas a uma tarefa, o sistema SHALL notificar, além do atribuído (2ª
pessoa, como hoje), o **dono e os seguidores** do galho que não sejam o atribuído nem o autor,
com uma mensagem em **3ª pessoa** da chave de locale versionada
`pt-BR.notifications.v1.assign_observer`, mantendo `type = 'assign'` (sem migração de enum).

#### Scenario: dono recebe a atribuição em 3ª pessoa

- **WHEN** Carla atribui Diego à tarefa `"Backup do programa"` (robô `R01 - Solda`) e o dono do
  workspace não é Carla nem Diego
- **THEN** Diego recebe `msg` em 2ª pessoa (`Carla atribuiu você à tarefa "Backup do programa"
  (robô R01 - Solda)`)
- **AND** o dono recebe `msg` em 3ª pessoa (`Carla atribuiu Diego à tarefa "Backup do programa"
  (robô R01 - Solda)`)
- **AND** ambas as linhas têm `type = 'assign'`

#### Scenario: autor da atribuição não recebe a observadora

- **WHEN** o próprio dono é quem faz a atribuição
- **THEN** o dono não recebe a notificação observadora (nunca o autor)

#### Scenario: seguidor silenciado não recebe a observadora

- **WHEN** um seguidor do projeto tem `mute` no robô específico da tarefa
- **THEN** ele não recebe a `assign_observer` (mais específico vence)

#### Scenario: chave observadora existe no locale

- **WHEN** o repositório é varrido pela string `atribuiu %{assignee}`
- **THEN** ela aparece somente em `config/locales/pt-BR.notifications.yml` e em testes

### Requirement: Notificação de eventos estruturais

Criar, editar e excluir projeto/célula/robô/tarefa SHALL instrumentar um evento pós-commit que
gera notificação `type = 'structure'` para o dono e os seguidores do galho afetado (menos o
autor), honrando `mute`, com a mensagem materializada da chave de locale correspondente à ação
e à entidade.

#### Scenario: novo valor de enum aceito, valor arbitrário recusado

- **WHEN** a migration de G6 é aplicada
- **THEN** `INSERT ... type = 'structure'` é aceito
- **AND** `INSERT ... type = 'mention'` continua recusado pelo enum

#### Scenario: exclusão de robô notifica o dono

- **WHEN** um membro `edit` exclui um robô e o dono não é o autor
- **THEN** o dono recebe uma notificação `type = 'structure'` com o texto da exclusão daquele
  robô e o `ctx` do galho

#### Scenario: estrutural honra o silêncio do galho

- **WHEN** o dono tem `mute` no projeto e alguém cria uma célula dentro dele
- **THEN** o dono não recebe a notificação estrutural

#### Scenario: autor da mudança estrutural não se notifica

- **WHEN** o próprio dono cria um projeto
- **THEN** nenhuma notificação estrutural é criada para o dono

#### Scenario: rollback estrutural não enfileira notificação

- **WHEN** a transação de criação de um robô sofre rollback
- **THEN** nenhum evento `structure.changed` é instrumentado e nenhum job é enfileirado
