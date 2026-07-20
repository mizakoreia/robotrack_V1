# task-template-sync

## ADDED Requirements

### Requirement: Sincronizar tarefas-base para um robô existente

O sistema SHALL oferecer uma ação por robô que percorre o catálogo do workspace, aplica a
regra de aplicabilidade de §2.5 usando explicitamente a Aplicação daquele robô, e cria as
tarefas faltantes com `progress: 0`, `status: "Pendente"` e sem responsável (§2.6).

#### Scenario: Robô Handling recebe Check sinais de Gripper e pula TCP Check

- **WHEN** o robô `R07 - Handling` (`application: "Handling"`), que já possui apenas a
  tarefa `TCP Check` com progresso `60`, é sincronizado contra o catálogo padrão de 31
  templates
- **THEN** 29 tarefas são criadas, entre elas `Check sinais de Gripper`
- **AND** `TCP Check` não é recriada e mantém progresso `60`
- **AND** `Calibração de Cola` não é criada, porque seu filtro é `["Sealing"]`
- **AND** o robô passa a ter 30 tarefas

#### Scenario: Robô Solda MIG nunca recebe Calibração de Cola

- **WHEN** o robô `R02 - MIG` (`application: "Solda MIG"`), sem nenhuma tarefa, é
  sincronizado contra o catálogo padrão
- **THEN** 29 tarefas são criadas
- **AND** nem `Calibração de Cola` nem `Check sinais de Gripper` estão entre elas

#### Scenario: Tarefas criadas nascem zeradas e sem responsável

- **WHEN** o robô `R02 - MIG` é sincronizado
- **THEN** toda tarefa criada tem `progress == 0`, `status == "Pendente"` e conjunto de
  responsáveis vazio
- **AND** o `weight` de cada tarefa é o `weight` do template de origem no momento da
  sincronização

#### Scenario: Tarefas novas entram ao fim da ordem do robô

- **WHEN** o robô `R07 - Handling` tem `TCP Check` na `position` `0` e é sincronizado
- **THEN** `TCP Check` permanece na `position` `0`
- **AND** as 29 tarefas criadas ocupam `position` de `1` a `29`, sem lacuna e sem
  duplicata

### Requirement: A sincronização nunca sobrescreve tarefa existente

A sincronização SHALL pular todo template cuja `desc` já exista entre as tarefas do robô,
comparando de forma insensível a caixa e a espaços nas bordas, e SHALL preservar
integralmente progresso, status, responsáveis, peso e histórico das tarefas existentes
(§2.6).

#### Scenario: Progresso e responsáveis de tarefa existente são preservados

- **WHEN** o robô `R07 - Handling` tem `Power On` com progresso `100`, status `Concluído`,
  responsável `Ana` e 3 entradas de histórico, e é sincronizado
- **THEN** `Power On` continua com progresso `100`, status `Concluído`, responsável `Ana` e
  as mesmas 3 entradas de histórico
- **AND** nenhuma segunda tarefa `Power On` é criada

#### Scenario: Comparação de descrição ignora caixa e espaços nas bordas

- **WHEN** o robô possui a tarefa `"tcp check "` (minúscula, com espaço à direita, vinda de
  dado legado) e o catálogo tem o template `"TCP Check"`
- **THEN** o template é pulado
- **AND** o robô continua com uma única tarefa de TCP check

#### Scenario: Tarefa criada à mão no robô também bloqueia a criação pelo template

- **WHEN** um editor criou manualmente no robô a tarefa `Speed up`, sem origem em template,
  e depois sincroniza
- **THEN** o template `Speed up` é pulado
- **AND** a tarefa manual permanece com seus dados

#### Scenario: Sincronizar duas vezes seguidas não cria nada na segunda

- **WHEN** o robô `R02 - MIG` é sincronizado e imediatamente sincronizado de novo, sem
  outra alteração
- **THEN** a segunda sincronização informa `0` tarefas adicionadas
- **AND** o robô continua com 29 tarefas

#### Scenario: Duas sincronizações concorrentes não duplicam tarefas

- **WHEN** duas requisições de sincronização do mesmo robô `R02 - MIG` chegam ao mesmo
  tempo, partindo de zero tarefas
- **THEN** ao final o robô tem exatamente 29 tarefas
- **AND** a segunda transação falha ou informa `0` adicionadas, pelo índice único
  `(robot_id, lower(btrim(desc)))`, nunca produzindo 58 tarefas

### Requirement: A sincronização informa quantas tarefas foram adicionadas

A ação SHALL retornar a contagem de tarefas efetivamente criadas (§2.6), refletindo o
número real de linhas inseridas, não o tamanho do conjunto aplicável.

#### Scenario: Contagem reflete apenas o que foi inserido

- **WHEN** o robô `R07 - Handling`, que já tem `TCP Check` e `Power On`, é sincronizado
  contra o catálogo padrão
- **THEN** a resposta contém `addedCount: 28`
- **AND** o robô passa de 2 para 30 tarefas

#### Scenario: Catálogo sem template aplicável informa zero

- **WHEN** um robô `Outros` é sincronizado num workspace cujo catálogo foi reduzido a um
  único template com `appFilters: ["Sealing"]`
- **THEN** a resposta contém `addedCount: 0`
- **AND** nenhuma tarefa é criada

#### Scenario: Falha parcial não deixa contagem mentirosa

- **WHEN** a inserção falha no meio da sincronização de 29 tarefas
- **THEN** a transação é revertida por inteiro
- **AND** a resposta é um erro, não um `addedCount` parcial
- **AND** o robô mantém o número de tarefas que tinha antes

### Requirement: Autorização e isolamento da sincronização

A sincronização SHALL declarar policy (D3), sendo permitida a `owner` e `edit` e negada a
`view` (§4.1, "Criar/editar/excluir ... tarefas"), e SHALL operar exclusivamente sobre
robôs e catálogo do workspace corrente (D2).

#### Scenario: Membro view não pode sincronizar

- **WHEN** um membro com papel `view` envia `POST /api/v1/robots/<id de R07 -
  Handling>/sync_task_templates`
- **THEN** a resposta é `403`
- **AND** o número de tarefas do robô permanece o mesmo — nenhuma linha foi inserida

#### Scenario: Sincronizar robô de outro workspace é invisível

- **WHEN** um usuário com papel `edit` no workspace A envia `POST
  /api/v1/robots/<id de um robô do workspace B>/sync_task_templates`
- **THEN** a resposta é `404`
- **AND** nenhuma tarefa é criada no robô do workspace B

#### Scenario: A sincronização usa o catálogo do workspace do robô, não outro

- **WHEN** o workspace A tem o template `Check de aterramento` e o workspace B não tem, e
  um robô do workspace B é sincronizado
- **THEN** `Check de aterramento` não é criado no robô do workspace B
