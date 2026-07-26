## ADDED Requirements

### Requirement: Esquema de preferência de notificação

O sistema SHALL persistir preferências numa tabela `notification_subscriptions` com PK
`uuid`, `workspace_id NOT NULL` sujeito a RLS forçada (D2), `person_id` (FK composta com
`workspace_id` → `people`), alvo por **três colunas FK** (`scope_project_id`, `scope_cell_id`,
`scope_robot_id`, cada uma FK composta com `workspace_id`) das quais **exatamente uma** é
não-nula, e `state` (enum Postgres `follow`|`mute`).

#### Scenario: Exatamente um alvo por linha

- **WHEN** um INSERT tenta gravar `scope_project_id` E `scope_robot_id` simultaneamente
- **THEN** a CHECK `chk_notif_sub_one_scope` (`num_nonnulls(...) = 1`) rejeita
- **AND** um INSERT sem nenhum dos três também é rejeitado

#### Scenario: state fora do enum é recusado pelo banco

- **WHEN** um INSERT em SQL puro tenta gravar `state = 'watch'`
- **THEN** o Postgres levanta erro de valor inválido para `notification_subscription_state`

#### Scenario: alvo de outro workspace é recusado pela FK composta

- **WHEN** uma linha com `workspace_id = A` tenta apontar `scope_robot_id` de um robô do
  workspace `B`
- **THEN** a FK composta `(scope_robot_id, workspace_id) → robots (id, workspace_id)` rejeita

#### Scenario: apagar o robô apaga as preferências dele

- **WHEN** um robô com preferências de várias pessoas é excluído (hard delete da linha em
  `robots`)
- **THEN** as `notification_subscriptions` com aquele `scope_robot_id` são removidas por
  `ON DELETE CASCADE`

#### Scenario: uma preferência por pessoa por alvo

- **WHEN** uma pessoa já tem uma linha para o robô `R` e um segundo INSERT tenta outra linha
  para a mesma pessoa e o mesmo `R`
- **THEN** o índice único parcial `uq_notif_sub_person_robot` rejeita a segunda linha

### Requirement: Isolamento de tenant da preferência (RLS forçada)

O sistema SHALL isolar `notification_subscriptions` por workspace via RLS **forçada**, no
mesmo idioma das demais tabelas de tenant.

#### Scenario: preferência de outro workspace é invisível

- **WHEN** `app.current_workspace_id` é o workspace A e um `SELECT * FROM
  notification_subscriptions` é executado
- **THEN** nenhuma linha do workspace B é retornada, mesmo como o papel da aplicação

### Requirement: Resolução — o mais específico vence, com DEFAULT preservado

Dada uma pessoa e uma notificação no galho `(projeto P, célula C, robô R)`, o sistema SHALL
decidir se a pessoa recebe consultando a preferência dela no nível **mais específico** com
linha explícita (robô, depois célula, depois projeto); na ausência de qualquer linha, SHALL
aplicar o DEFAULT: recebe se for responsável pela tarefa ou o dono do workspace, senão não
recebe.

#### Scenario: seguir um robô dentro de um projeto silenciado

- **WHEN** a pessoa tem `mute` no projeto `P` e `follow` no robô `R` (dentro de `P`), e chega
  um avanço em `R`
- **THEN** a pessoa **recebe** (o robô, mais específico, vence)

#### Scenario: silenciar um robô dentro de um projeto seguido

- **WHEN** a pessoa tem `follow` no projeto `P` e `mute` no robô `R`, e chega um avanço em `R`
- **THEN** a pessoa **não recebe**

#### Scenario: sem nenhuma linha preserva o comportamento atual

- **WHEN** a tabela `notification_subscriptions` está vazia e um responsável avança uma tarefa
- **THEN** os destinatários são exatamente os de hoje (responsáveis − autor, mais o dono nos
  avanços) — nenhuma mudança de comportamento

#### Scenario: não-responsável que segue passa a receber

- **WHEN** uma pessoa que **não** é responsável pela tarefa tem `follow` na célula `C` e chega
  um avanço numa tarefa de um robô dentro de `C`
- **THEN** a pessoa recebe, apesar de não ser responsável

#### Scenario: responsável que silencia deixa de receber

- **WHEN** uma pessoa responsável pela tarefa tem `mute` no robô e chega um avanço
- **THEN** a pessoa não recebe, apesar de ser responsável

### Requirement: API pessoal de preferência

O sistema SHALL expor a listagem das preferências da **própria** pessoa e um endpoint de
upsert/remoção, e SHALL negar qualquer edição da preferência de outra pessoa.

#### Scenario: listagem traz só as próprias preferências

- **WHEN** Ana chama `GET /api/v1/notification_subscriptions` num workspace onde Bruno também
  tem preferências
- **THEN** somente linhas com `person_id = Ana` são retornadas

#### Scenario: upsert de seguir é idempotente

- **WHEN** `PUT /api/v1/notification_subscriptions { scope_type: 'robot', scope_id: R, state:
  'follow' }` é chamado duas vezes
- **THEN** existe exatamente uma linha para (Ana, R) com `state = 'follow'`

#### Scenario: voltar ao padrão apaga a linha

- **WHEN** Ana, com uma linha `mute` no robô `R`, chama `PUT { scope_type: 'robot', scope_id:
  R, state: 'default' }`
- **THEN** a linha de (Ana, R) é removida e a resolução de `R` volta ao DEFAULT

#### Scenario: membro não edita a preferência alheia

- **WHEN** Ana tenta gravar uma preferência com `person_id` de Bruno
- **THEN** a `NotificationSubscriptionPolicy` nega — cada pessoa só edita a própria

#### Scenario: route-sweep encontra a policy declarada

- **WHEN** o route-sweep spec de D3 roda
- **THEN** todos os endpoints de `notification_subscriptions` declaram
  `NotificationSubscriptionPolicy`

### Requirement: Controle seguir/silenciar nas telas de hierarquia

O sistema SHALL exibir, no cabeçalho das telas de robô, célula e projeto, um controle que
mostra o **estado efetivo** de notificação daquela entidade para a pessoa (Padrão, Seguindo ou
Silenciado) e permite alterná-lo entre Padrão, Seguir e Silenciar, respeitando alvo de toque
≥40px, teclado e `prefers-reduced-motion`.

#### Scenario: estado herdado é rotulado com a origem

- **WHEN** a pessoa tem `mute` no projeto e abre a tela de um robô dentro dele, sem linha
  própria no robô
- **THEN** o controle do robô exibe estado "Silenciado" com a origem "pelo projeto"

#### Scenario: alternar para Silenciar reflete sem recarregar

- **WHEN** a pessoa, na tela do robô, escolhe "Silenciar"
- **THEN** o `PUT` é enviado, a chave `['ws', wsId, 'subscriptions']` é invalidada e o ícone
  passa a "Silenciado" sem `window.location.reload()`

#### Scenario: nenhum literal solto e ícone sem emoji

- **WHEN** o repositório do frontend é varrido
- **THEN** os rótulos do controle vivem em `src/lib/i18n/notifications.ts` (não inline) e o
  ícone `bell-off` é um `<symbol>` do sprite (currentColor), nunca emoji
