## ADDED Requirements

### Requirement: Autenticação da conexão do Cable por ticket de vida curta

O sistema SHALL autenticar a conexão do ActionCable por um ticket opaco, de uso único e
validade de 60 segundos, obtido em `POST /api/v1/cable_tickets` com o Bearer JWT normal, e
SHALL rejeitar a conexão (`reject_unauthorized_connection`) quando o ticket estiver ausente,
expirado, já consumido ou desconhecido. O sistema MUST NOT aceitar o JWT de sessão em
parâmetro de query string em produção.

#### Scenario: Ticket válido estabelece conexão

- **WHEN** o cliente chama `POST /api/v1/cable_tickets` com Bearer válido e conecta em
  `/cable?ticket=<valor retornado>` dentro de 60s
- **THEN** a conexão é aceita, `current_user` é o dono do Bearer, e a chave
  `cable_ticket:<jti>` deixa de existir no Redis

#### Scenario: Ticket reutilizado é rejeitado

- **WHEN** o mesmo ticket é usado numa segunda tentativa de conexão, 2 segundos após a
  primeira ter sido aceita
- **THEN** a segunda conexão é rejeitada e nenhum `current_user` é atribuído

#### Scenario: Ticket expirado é rejeitado

- **WHEN** o cliente conecta com um ticket emitido há 61 segundos
- **THEN** a conexão é rejeitada

#### Scenario: Conexão sem credencial é rejeitada, não aceita como anônima

- **WHEN** um cliente conecta em `/cable` sem parâmetro `ticket` e sem `token`
- **THEN** a conexão é rejeitada com `reject_unauthorized_connection`, e NÃO é estabelecida
  com `current_user` nulo

#### Scenario: JWT em query string não é aceito em produção

- **WHEN** um cliente conecta em `/cable?token=<JWT de sessão válido>` com
  `CABLE_ALLOW_TOKEN_PARAM` ausente ou `false`
- **THEN** a conexão é rejeitada

### Requirement: Autorização de assinatura do `WorkspaceChannel` pela membership

O sistema SHALL expor um único canal `WorkspaceChannel` que recebe o parâmetro
`workspace_id` e SHALL fazer `reject` da assinatura salvo se existir `Membership` ativa do
`current_user` naquele workspace, consultada no banco no momento do `subscribed`. A decisão
MUST NOT depender de qualquer índice, lista ou cache enviado pelo cliente.

#### Scenario: Membro assina o canal do próprio workspace

- **WHEN** o usuário A, com membership `edit` ativa no workspace W1, assina
  `WorkspaceChannel` com `workspace_id: W1`
- **THEN** a assinatura é confirmada e o cliente passa a receber envelopes do stream
  `ws:W1:v1`

#### Scenario: Usuário de outro workspace não consegue assinar

- **WHEN** o usuário B, membro apenas do workspace W2, assina `WorkspaceChannel` com
  `workspace_id: W1`
- **THEN** a assinatura é rejeitada, nenhum stream é iniciado, e B não recebe nenhum
  envelope de W1 — nem mesmo um envelope vazio ou de erro contendo ids de W1

#### Scenario: Workspace inexistente não vaza existência

- **WHEN** um usuário autenticado assina `WorkspaceChannel` com um `workspace_id` UUID que
  não existe
- **THEN** a assinatura é rejeitada com a mesma resposta do caso de não-membro,
  indistinguível dela

#### Scenario: Papel `view` assina normalmente

- **WHEN** o usuário C, com membership `view` em W1, assina o canal de W1
- **THEN** a assinatura é aceita — o canal transporta ponteiros, e a leitura subsequente é
  autorizada pelas policies de `authorization-policies` (§4.1)

### Requirement: Publicação pós-commit de eventos de toda mutação de domínio

O sistema SHALL publicar um envelope no stream do workspace em `after_commit` para toda
criação, atualização e exclusão de `projects`, `cells`, `robots`, `tasks`, `task_advances`,
`memberships` e `notifications`. A publicação MUST partir de um ponto único
(`Realtime::PublisherService`, acionado pelo concern `RealtimePublishable`) e MUST NOT
ocorrer dentro da transação.

#### Scenario: Avanço registrado publica evento após commit

- **WHEN** um `TaskAdvance` levando a tarefa T de progresso 40 para 60 é persistido e a
  transação commita
- **THEN** exatamente um envelope `task_advance.created` é publicado em `ws:<W>:v1`,
  contendo `entity: {kind: "task", id: T}` e `scope` com `project_id`, `cell_id` e
  `robot_id` da tarefa

#### Scenario: Transação revertida não publica

- **WHEN** a criação de um robô é revertida por `raise ActiveRecord::Rollback` após o
  `save`
- **THEN** nenhum envelope `robot.created` é publicado

#### Scenario: Criação em lote publica um evento agregado

- **WHEN** 50 robôs são criados numa única operação em lote na célula C (§3.4)
- **THEN** é publicado 1 envelope `robot.batch_created` com `scope.cell_id = C`, e NÃO 50
  envelopes `robot.created`

#### Scenario: Cobertura de models é verificada por teste

- **WHEN** um model de domínio da lista acima não inclui `RealtimePublishable`
- **THEN** o spec de cobertura de publicação falha, nomeando o model ausente

#### Scenario: Falha do Redis não derruba a mutação

- **WHEN** o broadcast levanta erro de conexão com o Redis durante o `after_commit` de um
  avanço já commitado
- **THEN** a requisição HTTP responde 201 normalmente, o erro é registrado em log
  estruturado e o contador de falha de publicação é incrementado

### Requirement: Envelope de evento versionado com sequência monotônica por workspace

O sistema SHALL numerar cada evento com um `seq` obtido por
`UPDATE workspaces SET realtime_seq = realtime_seq + 1 ... RETURNING realtime_seq` dentro
da transação da mutação, e SHALL incluir no envelope os campos `v`, `seq`, `workspace_id`,
`type`, `entity`, `scope`, `actor_person_id`, `origin_id` e `at`. O envelope MUST NOT
conter atributos de conteúdo da entidade (nome, descrição, comentário, texto de
notificação).

#### Scenario: Sequência é estritamente crescente

- **WHEN** três mutações commitam em sequência no workspace W partindo de
  `realtime_seq = 100`
- **THEN** os envelopes carregam `seq` 101, 102 e 103, nesta ordem de emissão

#### Scenario: Sequência não é consumida por transação abortada

- **WHEN** uma mutação em W incrementa `realtime_seq` para 104 e em seguida a transação
  aborta
- **THEN** a próxima mutação bem-sucedida em W publica `seq: 104`

#### Scenario: Envelope não transporta conteúdo

- **WHEN** é publicado o envelope de uma `notification.created` cujo texto tem 480
  caracteres (§2.7)
- **THEN** o envelope não contém o texto da notificação, apenas o ponteiro para o recurso

#### Scenario: Sequências de workspaces distintos são independentes

- **WHEN** W1 está em `seq` 900 e W2 em `seq` 3, e uma mutação ocorre em W2
- **THEN** o envelope de W2 carrega `seq: 4` e nada é publicado em `ws:W1:v1`

### Requirement: Invalidação de query keys do React Query a partir do evento

O cliente SHALL mapear cada `type` de evento para as query keys da convenção D9
(`['ws', wsId, ...]`) e SHALL invalidar essas chaves com `refetchType: 'active'`. O mapa
MUST ser exaustivo sobre a união de tipos de evento; um tipo desconhecido em runtime SHALL
invalidar `['ws', wsId]` e emitir aviso, e MUST NOT ser ignorado silenciosamente.

#### Scenario: Duas sessões no mesmo robô convergem

- **WHEN** a sessão A e a sessão B estão na tela do robô R (§3.5), e A registra avanço na
  tarefa T de 40 para 60
- **THEN** B recebe `task_advance.created`, invalida `['ws',W,'robot',R,'tasks']` e exibe
  60 na linha de T em até 2 segundos, sem recarregar a página

#### Scenario: Avanço invalida a cadeia de rollup inteira

- **WHEN** chega `task_advance.created` com `scope` `{project: P, cell: C, robot: R}`
- **THEN** são invalidadas `['ws',W,'robot',R,'tasks']`, `['ws',W,'task',T,'advances']`,
  `['ws',W,'my-tasks']`, `['ws',W,'robot',R]`, `['ws',W,'cell',C]`, `['ws',W,'project',P]`
  e `['ws',W,'overview']` — de modo que o anel ponderado (§2.1) e a contagem crua (§3.2)
  não fiquem em desacordo na mesma tela

#### Scenario: Query desmontada não refetcha imediatamente

- **WHEN** chega `robot.updated` para o robô R enquanto o usuário está na Visão Geral e a
  query `['ws',W,'robot',R]` está montada mas inativa
- **THEN** a chave é marcada stale sem disparar requisição, e o fetch ocorre quando a tela
  do robô é aberta

#### Scenario: Rajada de eventos vira um refetch

- **WHEN** 8 envelopes `task_advance.created` do mesmo robô R chegam em 900 ms
- **THEN** a fila de invalidação é drenada com deduplicação por chave e
  `['ws',W,'robot',R,'tasks']` gera exatamente 1 refetch

#### Scenario: Tipo de evento desconhecido não é engolido

- **WHEN** chega um envelope com `type: "gizmo.created"`, ausente do mapa
- **THEN** o cliente invalida `['ws', W]` e registra aviso identificando o tipo

### Requirement: Evento não reverte interface com mutação otimista pendente

O cliente SHALL descartar envelopes cujo `origin_id` seja o da própria aba, e SHALL represar
a invalidação de uma chave que intersecte a `mutationKey` de uma mutação em voo ou de um
item pendente na fila offline (D7) para a mesma entidade, drenando-a quando a mutação
assentar. Em nenhuma circunstância o valor otimista exibido SHALL ser substituído pelo valor
anterior do servidor.

#### Scenario: Eco da própria mutação é descartado

- **WHEN** a sessão A registra avanço 40→60 e recebe de volta o envelope
  `task_advance.created` cujo `origin_id` é o da própria aba
- **THEN** o envelope é descartado, nenhuma invalidação é enfileirada, e a tela permanece
  em 60

#### Scenario: Evento de terceiro durante mutação em voo não pisca

- **WHEN** a sessão A aplica otimista 40→60 com o POST ainda em voo, e chega um envelope de
  outra origem para a mesma tarefa T
- **THEN** a invalidação é represada, a UI continua exibindo 60, e o refetch só ocorre
  depois do `onSettled` da mutação de A

#### Scenario: Mutação enfileirada offline também represa

- **WHEN** a sessão A está offline com um avanço da tarefa T na fila IndexedDB, e ao voltar
  a rede chega um envelope de outra origem para T antes do envio da fila
- **THEN** a invalidação fica represada enquanto `hasPendingFor('task', T)` for verdadeiro,
  e o indicador de gravação sinaliza pendência

#### Scenario: Represamento tem teto

- **WHEN** uma invalidação está represada há 30 segundos porque a mutação correspondente
  saiu de "em voo" e permanece enfileirada offline
- **THEN** a invalidação é aplicada e a tela é marcada como não-sincronizada

#### Scenario: Mutação que falha também drena a fila

- **WHEN** o POST de avanço da sessão A retorna 409 de `lock_version` (§2.4) e havia
  invalidação represada para T
- **THEN** a invalidação represada é aplicada no `onSettled`, e a tela converge para o valor
  do servidor

### Requirement: Fallback de polling quando o WebSocket não estabelece

O sistema SHALL manter uma máquina de estados de transporte com os estados `connecting`,
`live`, `degraded` e `offline`. SHALL entrar em `degraded` quando não houver `welcome` em
8 segundos ou após 3 falhas de conexão em 60 segundos, e em `degraded` SHALL aplicar
`refetchInterval` de 20 segundos às queries ativas, com
`refetchIntervalInBackground: false`, reduzindo para 60 segundos após 5 minutos sem
interação. O estado de transporte MUST ser exposto na interface e emitido como métrica.

#### Scenario: Proxy bloqueia WebSocket e a tela continua atualizando

- **WHEN** o proxy da fábrica bloqueia o `Upgrade:` e o handshake não retorna `welcome` em
  8 segundos, com o usuário na tela do robô R
- **THEN** o transporte entra em `degraded`, `['ws',W,'robot',R,'tasks']` passa a refetchar
  a cada 20 segundos, e um avanço registrado por outro membro aparece em até 20 segundos

#### Scenario: Aba oculta não pesquisa

- **WHEN** o transporte está em `degraded` e o documento fica oculto
- **THEN** nenhuma requisição de `refetchInterval` é emitida até o documento voltar a ficar
  visível

#### Scenario: Ociosidade alonga o intervalo

- **WHEN** o transporte está em `degraded` e passam 5 minutos sem interação do usuário
- **THEN** o intervalo passa a 60 segundos, e volta a 20 segundos no primeiro foco ou input

#### Scenario: Retentativa de WebSocket ocorre em paralelo

- **WHEN** o transporte está em `degraded` e o WebSocket volta a ser possível na terceira
  tentativa de backoff
- **THEN** o transporte passa a `live`, o `refetchInterval` é removido de todas as queries,
  e a reconciliação de reconexão é executada

#### Scenario: Sem rede não há polling

- **WHEN** `navigator.onLine` passa a `false`
- **THEN** o transporte entra em `offline`, nenhum polling é emitido, e o indicador de
  conexão informa o estado

#### Scenario: Modo degradado é observável

- **WHEN** uma sessão permanece em `degraded` por mais de 60 segundos
- **THEN** a topbar exibe "atualizando periodicamente" e a métrica de sessões degradadas é
  incrementada para `delivery-and-observability`

### Requirement: Reconciliação após reconexão por lacuna de sequência

O cliente SHALL persistir o último `seq` recebido por workspace e, ao (re)estabelecer o
transporte, SHALL chamar `GET /api/v1/workspaces/:id/sync?since=<seq>`. O sistema SHALL
responder com `current_seq`, `gap` e os tipos de entidade alterados dentro de uma janela de
10 minutos; fora dessa janela SHALL responder `gap: true`. O cliente MUST NOT assumir que
não perdeu eventos durante a desconexão.

#### Scenario: Eventos perdidos em queda curta são reconciliados

- **WHEN** o cliente estava em `seq` 500, perde a conexão por 45 segundos durante os quais
  ocorrem 6 mutações, e reconecta
- **THEN** `/sync?since=500` responde `current_seq: 506` com os tipos de entidade tocados, e
  o cliente invalida apenas as chaves correspondentes a esses tipos

#### Scenario: Queda longa cai para invalidação total

- **WHEN** o cliente reconecta após 40 minutos desconectado
- **THEN** `/sync` responde `gap: true` sem detalhar entidades, e o cliente invalida
  `['ws', W]` inteiro

#### Scenario: Reconexão sem eventos perdidos não gera refetch

- **WHEN** o cliente reconecta com `since` igual ao `current_seq` do servidor
- **THEN** nenhuma query é invalidada

#### Scenario: `/sync` respeita o tenant

- **WHEN** o usuário B, não membro de W1, chama `GET /api/v1/workspaces/W1/sync?since=0`
- **THEN** a resposta é 403 e não revela `current_seq` nem qualquer tipo de entidade de W1

### Requirement: Revogação de acesso ao vivo com retorno ao workspace próprio

O sistema SHALL, ao revogar a membership de um usuário, publicar `membership.revoked` e
encerrar os streams daquela conexão pelo servidor. O cliente SHALL, ao receber esse evento
para si mesmo **ou** ao receber HTTP 403 em rota do workspace corrente, avisar o usuário,
remover o workspace do índice local, limpar a subárvore `['ws', W]` do cache e navegar para
o workspace próprio (§3.10). O procedimento MUST ser idempotente.

#### Scenario: Usuário removido enquanto navega é avisado e redirecionado

- **WHEN** o usuário C está na tela da célula do workspace W1 e o dono remove sua membership
- **THEN** C vê o aviso de acesso removido, W1 desaparece do seletor de workspaces, o cache
  de `['ws',W1]` é descartado, e C é levado ao seu próprio workspace

#### Scenario: Servidor encerra o stream mesmo se o cliente ignorar

- **WHEN** a membership de C em W1 é revogada
- **THEN** os streams da assinatura de C em `ws:W1:v1` são encerrados pelo servidor e nenhum
  envelope posterior de W1 é entregue a C

#### Scenario: Revogação em transporte degradado é detectada pelo 403

- **WHEN** a membership de C é revogada enquanto seu transporte está em `degraded`, e o
  próximo refetch de polling responde 403
- **THEN** o mesmo procedimento de revogação é executado a partir do interceptor HTTP

#### Scenario: Os dois caminhos juntos produzem um único aviso

- **WHEN** o evento `membership.revoked` e um 403 chegam num intervalo de 300 ms
- **THEN** o usuário vê exatamente um aviso e ocorre exatamente uma navegação

#### Scenario: Revogação de outro membro não expulsa ninguém

- **WHEN** chega `membership.revoked` referente ao usuário D, estando C na tela
- **THEN** C permanece no workspace, e apenas `['ws',W,'members']` e `['ws',W,'people']` são
  invalidadas

### Requirement: Isolamento do adapter de Cable em produção

O sistema SHALL usar adapter Redis para o ActionCable em produção com `channel_prefix`
distinto por ambiente e URL de Redis separada da usada pelo Sidekiq, e SHALL falhar o boot
em produção se o adapter resolvido não for `redis`.

#### Scenario: Boot em produção com adapter não-Redis falha

- **WHEN** a aplicação inicia em `production` com `cable.yml` resolvendo `adapter: async`
- **THEN** o boot é abortado com erro explícito, em vez de subir com broadcast que não
  atravessa processos

#### Scenario: Ambientes não cruzam broadcast

- **WHEN** staging e produção apontam para a mesma instância Redis e um evento é publicado
  em `ws:W:v1` por staging
- **THEN** nenhuma conexão de produção recebe o envelope, por força do `channel_prefix`
  distinto

#### Scenario: Broadcast atravessa processos

- **WHEN** a mutação é commitada pelo processo Puma A e o assinante está conectado ao
  processo Puma B
- **THEN** o assinante em B recebe o envelope
