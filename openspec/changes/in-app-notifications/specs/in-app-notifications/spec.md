## ADDED Requirements

### Requirement: Esquema da notificação

O sistema SHALL persistir notificações numa tabela `notifications` com PK `uuid`
gerável no cliente (D1/D13) e `workspace_id` `NOT NULL` sujeito a RLS (D2),
contendo os campos de §1.1 traduzidos: `recipient_person_id` (FK → `people`,
substitui `target`, por D10/D11), `actor_person_id`, `type` (enum Postgres
`assign`|`progress`|`done`), `msg`, `author_name_snapshot` (`byName`),
`recorded_at` (`ts`), `created_at`, `ts_local` (`tsLocal`), `read`, `read_at`,
`format_version`, e o `ctx` desnormalizado em `ctx_project_id`, `ctx_cell_id`,
`ctx_robot_id`, `ctx_task_id`.

#### Scenario: A migration cria ts e tsLocal desde a origem

- **WHEN** a migration de `notifications` é aplicada num banco limpo
- **THEN** as colunas `recorded_at` (timestamptz, NOT NULL) e `ts_local` (text,
  NOT NULL) existem, sem nenhuma migration de retrofit posterior
- **AND** `created_at` existe como coluna distinta de `recorded_at` (D8)

#### Scenario: type fora do enum é recusado pelo banco

- **WHEN** um INSERT direto em SQL tenta gravar `type = 'mention'`
- **THEN** o Postgres levanta erro de tipo inválido para `notification_type`
- **AND** nenhuma linha é criada

#### Scenario: ctx aponta para registros reais

- **WHEN** uma notificação é criada com `ctx_robot_id` de um robô que é então
  excluído
- **THEN** a FK resolve o `ctx_robot_id` conforme sua regra de exclusão e o
  centro de notificações nunca exibe link para um robô inexistente

### Requirement: Limite de 500 caracteres como constraint de banco (invariante 8)

O sistema SHALL impor `char_length(msg) <= 500` por CHECK constraint no
Postgres, não apenas por validação de model.

#### Scenario: Mensagem com 501 caracteres falha no banco

- **WHEN** um INSERT em SQL puro, contornando o model, grava `msg` com 501
  caracteres
- **THEN** o Postgres levanta `CheckViolation` na constraint `msg_max_500`
- **AND** nenhuma linha é criada

#### Scenario: Mensagem com exatamente 500 caracteres é aceita

- **WHEN** uma notificação é criada com `msg` de exatamente 500 caracteres
- **THEN** a linha é persistida com sucesso

#### Scenario: Comentário longo é truncado para caber em 500

- **WHEN** um avanço de `45 → 60` tem comentário de 900 caracteres e o formato
  `progress` renderizado somaria 980 caracteres
- **THEN** o comentário SHALL ser truncado com `…` até `char_length(msg) == 500`
- **AND** a descrição da tarefa e o nome do robô permanecem íntegros na `msg`

### Requirement: Criação sempre com read = false (invariante 8)

O sistema SHALL garantir por trigger `BEFORE INSERT` que toda notificação nasce
com `read = false`, e SHALL manter `read` monotônico.

#### Scenario: INSERT com read = true é rejeitado

- **WHEN** um INSERT em SQL puro tenta criar uma notificação com `read = true`
- **THEN** a trigger levanta exceção e o INSERT falha
- **AND** a trigger NÃO corrige o valor silenciosamente

#### Scenario: read não pode voltar para false

- **WHEN** uma notificação já marcada como lida recebe `UPDATE ... SET read = false`
- **THEN** a trigger `BEFORE UPDATE` rejeita a operação

#### Scenario: read_at acompanha read

- **WHEN** uma notificação é marcada como lida
- **THEN** `read = true` E `read_at IS NOT NULL`
- **AND** um UPDATE que ponha `read = true` com `read_at` nulo viola a CHECK de
  coerência

### Requirement: Notificação de atribuição (assign)

Quando pessoas são atribuídas a uma tarefa, o sistema SHALL notificar **apenas
quem entrou naquele momento**, com a mensagem
`<autor> atribuiu você à tarefa "<desc>" (robô <robô>)`, renderizada a partir da
chave de locale versionada `pt-BR.notifications.v1.assign` (D14).

#### Scenario: Atribuir 3 pessoas onde 2 já estavam notifica 1

- **WHEN** a tarefa "Backup do programa" tem `assignees = [Ana, Bruno]` e Carla
  registra a atribuição de `[Ana, Bruno, Diego]`
- **THEN** exatamente 1 notificação `assign` é criada, para Diego
- **AND** Ana e Bruno NÃO recebem notificação

#### Scenario: Formato exato da mensagem assign

- **WHEN** Carla atribui Diego à tarefa `desc = "Backup do programa"` no robô
  `R01 - Solda`
- **THEN** `msg` é exatamente
  `Carla atribuiu você à tarefa "Backup do programa" (robô R01 - Solda)`
- **AND** `format_version = 1`

#### Scenario: Nenhum literal de mensagem fora do locale

- **WHEN** o repositório é varrido por `grep` pelo fragmento
  `atribuiu você à tarefa`
- **THEN** ele aparece somente em `config/locales/pt-BR.notifications.yml` e em
  arquivos de teste

### Requirement: Notificação de avanço (progress)

Quando um avanço resulta em `0 < progresso < 100`, o sistema SHALL notificar
todos os responsáveis da tarefa com
`<autor> registrou <N>% na tarefa "<desc>" (robô <robô>): <comentário>`,
da chave `pt-BR.notifications.v1.progress`.

#### Scenario: Formato exato da mensagem progress

- **WHEN** Bruno registra avanço de `20 → 45` na tarefa `"Ajuste de TCP"` do robô
  `R03 - Handling` com comentário `"Calibrado eixo 6"`, e Ana é responsável
- **THEN** Ana recebe uma notificação `type = 'progress'` com `msg` exatamente
  `Bruno registrou 45% na tarefa "Ajuste de TCP" (robô R03 - Handling): Calibrado eixo 6`
- **AND** `recorded_at` é o `recorded_at` do avanço (D8), não o horário do job

#### Scenario: Avanço para 100 não gera progress

- **WHEN** um avanço leva a tarefa de `60 → 100`
- **THEN** nenhuma notificação `type = 'progress'` é criada
- **AND** uma notificação `type = 'done'` é criada

### Requirement: Notificação de conclusão (done)

Quando uma tarefa chega a 100%, o sistema SHALL notificar todos os responsáveis
com `Tarefa "<desc>" (robô <robô>) foi concluída por <autor>`, da chave
`pt-BR.notifications.v1.done`.

#### Scenario: Formato exato da mensagem done

- **WHEN** Bruno leva a tarefa `"Ajuste de TCP"` do robô `R03 - Handling` de
  `60 → 100`, com Ana como responsável
- **THEN** Ana recebe `msg` exatamente
  `Tarefa "Ajuste de TCP" (robô R03 - Handling) foi concluída por Bruno`
- **AND** a `msg` NÃO contém o comentário, mesmo quando ele foi informado

### Requirement: Nunca notificar o próprio autor

O sistema SHALL remover `actor_person_id` do conjunto de destinatários, depois da
dedup, para os três tipos.

#### Scenario: Autor que também é responsável não recebe a própria notificação

- **WHEN** Ana é responsável pela tarefa `"Ajuste de TCP"` e a própria Ana
  registra avanço de `20 → 45`, sendo ela a única responsável
- **THEN** zero notificações são criadas
- **AND** o avanço é persistido normalmente

#### Scenario: Autoatribuição por §2.3 não gera assign

- **WHEN** Bruno altera o progresso de uma tarefa sem responsáveis e é
  autoatribuído a ela por §2.3
- **THEN** nenhuma notificação `assign` é criada para Bruno

#### Scenario: Autor entre vários responsáveis é excluído só ele

- **WHEN** a tarefa tem responsáveis `[Ana, Bruno, Diego]` e Bruno registra
  avanço `10 → 50`
- **THEN** exatamente 2 notificações `progress` são criadas, para Ana e Diego

### Requirement: Deduplicação de destinatários

O sistema SHALL deduplicar destinatários por `person_id` antes de criar
notificações, e SHALL garantir idempotência sob reexecução do job por índice
único parcial.

#### Scenario: Pessoa listada duas vezes recebe uma notificação

- **WHEN** o conjunto bruto de responsáveis contém o mesmo `person_id` duas vezes
- **THEN** exatamente 1 notificação é criada para essa pessoa

#### Scenario: Reexecução do job não duplica assign

- **WHEN** o job de notificação de uma atribuição é executado duas vezes com o
  mesmo `recorded_at`, `ctx_task_id` e destinatário
- **THEN** o índice único parcial impede a segunda linha
- **AND** o job conclui sem levantar erro

### Requirement: Progresso 0 não gera notificação

O sistema SHALL não criar nenhuma notificação quando um avanço resulta em
progresso `0` (reset para `Pendente` ou `N/A`).

#### Scenario: Reset de 45 para 0 é silencioso

- **WHEN** Bruno registra avanço de `45 → 0` numa tarefa cujos responsáveis são
  Ana e Diego
- **THEN** zero notificações são criadas, de qualquer tipo
- **AND** o avanço e a transição de estado para `Pendente` são persistidos

### Requirement: Entrega best-effort que nunca derruba o save

O sistema SHALL enfileirar a criação de notificações em job Sidekiq disparado por
`after_commit`, fora da transação do avanço/atribuição, de modo que nenhuma
falha de notificação possa reverter o dado de domínio.

#### Scenario: Falha na criação da notificação preserva o avanço

- **WHEN** um avanço de `20 → 45` é salvo e a criação da notificação levanta
  exceção (por exemplo, `CheckViolation`)
- **THEN** o `task_advance` permanece persistido e o progresso da tarefa é 45
- **AND** o erro é reportado ao rastreador estruturado

#### Scenario: Redis indisponível não bloqueia o avanço

- **WHEN** o Redis está fora e um avanço é registrado
- **THEN** a requisição do avanço retorna sucesso
- **AND** nenhuma notificação é criada

#### Scenario: Job só existe após o commit

- **WHEN** a transação do avanço sofre rollback
- **THEN** nenhum job de notificação é enfileirado

### Requirement: Listagem e marcação como lida

O sistema SHALL expor listagem paginada das notificações da própria pessoa,
ordenada por `recorded_at DESC`, contagem de não lidas, e os endpoints
`POST /api/v1/notifications/:id/read` e `POST /api/v1/notifications/read_all`.
Não SHALL existir endpoint genérico de UPDATE sobre `notifications`.

#### Scenario: Listagem traz apenas as próprias notificações

- **WHEN** Ana lista suas notificações num workspace onde Bruno também tem
  notificações
- **THEN** somente notificações com `recipient_person_id = Ana` são retornadas

#### Scenario: Marcar como lida é idempotente

- **WHEN** `POST /notifications/:id/read` é chamado duas vezes para a mesma
  notificação
- **THEN** ambas as chamadas retornam sucesso
- **AND** `read_at` mantém o valor da primeira chamada

#### Scenario: Route-sweep encontra a policy declarada

- **WHEN** o route-sweep spec de D3 roda
- **THEN** todos os endpoints de `notifications` declaram `NotificationPolicy`

### Requirement: Membro view só pode marcar a própria notificação como lida (invariante 4)

O sistema SHALL permitir a um membro de papel `view` exatamente uma mutação em
todo o sistema — `read` da própria notificação — porte de
`affectedKeys().hasOnly(['read'])` de `firestore.rules`. Qualquer outra coluna, e
qualquer notificação de outra pessoa, SHALL ser negada.

#### Scenario: Membro view marca a própria notificação como lida

- **WHEN** um membro de papel `view` chama `POST /notifications/:id/read` para
  uma notificação com `recipient_person_id` igual ao seu
- **THEN** a operação é permitida e `read = true`

#### Scenario: Membro view tentando alterar msg além de read é negado

- **WHEN** um membro `view` tenta um UPDATE que altere `msg` (ou `msg` e `read`
  juntos) na própria notificação
- **THEN** a trigger `BEFORE UPDATE` rejeita, porque colunas fora de
  `{read, read_at}` foram afetadas
- **AND** nenhuma coluna é alterada, inclusive `read`

#### Scenario: Membro view não marca a notificação de outra pessoa

- **WHEN** um membro `view` chama `POST /notifications/:id/read` para uma
  notificação cujo `recipient_person_id` é de outra pessoa
- **THEN** a `NotificationPolicy` nega e a resposta é 403 (ou 404, sem vazar
  existência)

#### Scenario: Owner não marca a notificação alheia como lida

- **WHEN** o dono do workspace chama `POST /notifications/:id/read` para uma
  notificação de Ana
- **THEN** a operação é negada — §4.1 exige "a **própria**" notificação

#### Scenario: Membro view não cria notificação

- **WHEN** um membro `view` tenta qualquer caminho que resulte em criação de
  notificação
- **THEN** a operação é negada (§4.1: "Criar log / notificação" é ❌ para `view`)

#### Scenario: Notificação de outro workspace é invisível

- **WHEN** Ana, membro do workspace A, tenta ler ou marcar uma notificação do
  workspace B na qual ela também figura como destinatária
- **THEN** a RLS (D2) impede o acesso e a linha não é retornada nem alterada

### Requirement: Centro de notificações na UI

O sistema SHALL exibir um centro de notificações com badge de contagem de não
lidas, lista ordenada do mais recente, ação de marcar como lida (individual e
todas) e navegação por `ctx` até o robô da tarefa.

#### Scenario: Badge reflete a contagem de não lidas

- **WHEN** a pessoa tem 3 notificações não lidas e 12 lidas
- **THEN** o badge exibe `3`
- **AND** ao marcar uma como lida o badge exibe `2` sem recarregar a página

#### Scenario: Clique navega para o robô da tarefa

- **WHEN** a pessoa clica numa notificação cujo `ctx` é
  `{pid: P1, cid: C1, rid: R1, tid: T1}`
- **THEN** o app navega para a tela do robô `R1` com a tarefa `T1` destacada

#### Scenario: ctx quebrado não gera tela em branco

- **WHEN** a pessoa clica numa notificação cujo `ctx_robot_id` é nulo
- **THEN** o app permanece no centro de notificações e exibe aviso de contexto
  indisponível

### Requirement: Política de retenção declarada

O sistema SHALL expor um scope `Notification.purgeable` correspondendo a
`read = true AND recorded_at < now() - interval '90 days'`, e SHALL nunca tornar
elegível uma notificação não lida, qualquer que seja sua idade.

#### Scenario: Não lida de 2 anos não é expurgável

- **WHEN** existe notificação com `read = false` e `recorded_at` de 730 dias atrás
- **THEN** ela NÃO consta em `Notification.purgeable`

#### Scenario: Lida de 91 dias é expurgável

- **WHEN** existe notificação com `read = true` e `recorded_at` de 91 dias atrás
- **THEN** ela consta em `Notification.purgeable`
- **AND** o `EXPLAIN` da consulta usa o índice `(workspace_id, read, recorded_at)`
