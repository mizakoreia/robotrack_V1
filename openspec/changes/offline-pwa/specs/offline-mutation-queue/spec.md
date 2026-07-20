## ADDED Requirements

### Requirement: Fila persistida em IndexedDB com ordem e esquema versionado

O sistema SHALL persistir mutations pendentes em um object store `mutations` do banco
IndexedDB `robotrack`, com número de versão de esquema explícito. Cada item SHALL
conter `id`, `seq` (inteiro monotônico), `kind`, `resource_uuid`, `workspace_id`,
`method`, `url`, `body`, `depends_on`, `recorded_at`, `state`, `attempts`,
`next_attempt_at` e `last_error`. `state` SHALL ser um de
`pending | inflight | blocked | failed | done` (§4.2).

#### Scenario: Fila sobrevive ao fechamento do navegador

- **WHEN** três mutations são enfileiradas offline, a aba é fechada e o app é reaberto ainda offline
- **THEN** as três mutations continuam em `pending` com os mesmos `seq` 1, 2 e 3

#### Scenario: Item de esquema desconhecido é quarentenado, nunca descartado

- **WHEN** o app abre a versão 3 do esquema e encontra itens gravados pela versão 2 que não podem ser migrados
- **THEN** os itens vão para `failed` com `last_error` de classe `"incompatível"` e MUST NOT ser apagados

#### Scenario: Ordem de drenagem segue `seq`

- **WHEN** as mutations independentes A (`seq` 1), B (`seq` 2) e C (`seq` 3) estão pendentes e a rede volta
- **THEN** as requisições partem na ordem A, B, C

### Requirement: Toda mutation declara suas dependências e só é enviada quando resolvidas

O sistema SHALL exigir que quem enfileira declare `depends_on` como lista de uuids. Um
item SHALL ser elegível para envio somente quando todos os uuids de `depends_on`
estiverem no conjunto persistido `resolved_uuids`. Um uuid SHALL entrar em
`resolved_uuids` quando o servidor responder 2xx à mutation que o cria, ou quando o
recurso for lido do servidor. Itens não elegíveis SHALL ser pulados, e o sistema MUST
NOT bloquear itens posteriores independentes (D7-4, D1).

#### Scenario: Criar robô offline e registrar avanço numa tarefa dele

- **WHEN** offline, o usuário cria o robô `R`, cria a tarefa `T` em `R` e registra um avanço `A` de 0 → 30 em `T`, e então a rede volta
- **THEN** o servidor recebe `POST` de `R`, depois `POST` de `T` com `robot_id = R`, depois `POST` de `A` em `/tasks/T/advances`, exatamente nessa ordem, e as três respondem 2xx

#### Scenario: Mutation independente não espera pela dependente bloqueada

- **WHEN** `task.create T` (`seq` 2, `depends_on: [R]`) está esperando `R` e `project.rename P` (`seq` 4, `depends_on: []`) está pendente
- **THEN** `project.rename P` é enviado sem esperar por `R`

#### Scenario: Envio fora de ordem não acontece nem quando o `seq` permitiria

- **WHEN** `robot.create R` está em `inflight` e `task.create T` com `depends_on: [R]` se torna o próximo por `seq`
- **THEN** `T` não é enviado até `R` responder 2xx e entrar em `resolved_uuids`

#### Scenario: Dependência já satisfeita pelo servidor não bloqueia

- **WHEN** o robô `R` já existe no servidor e foi lido pelo cliente, e uma nova `task.create T` com `depends_on: [R]` é enfileirada offline
- **THEN** `T` é elegível assim que a rede voltar, sem depender de nenhuma mutation de criação de `R`

#### Scenario: Dependência declarada errada é contida pelo banco

- **WHEN** um item `task.create T` é enviado com `robot_id = R` sem que `R` exista no servidor
- **THEN** a chave estrangeira `tasks.robot_id → robots.id` faz o servidor responder 422 ou 404, e o item vai para `failed` permanente em vez de criar uma tarefa órfã

### Requirement: Reenvio da mesma mutation é idempotente por uuid

O sistema SHALL usar o uuid do recurso gerado no cliente (D1) como chave de
idempotência, e MUST NOT enviar header `Idempotency-Key` nem depender de tabela de
chaves com expiração. O servidor SHALL responder 200 ao replay, sem criar segundo
registro e sem reaplicar efeitos colaterais (D7-6, D-H2).

#### Scenario: A mesma mutation reenviada duas vezes cria um registro só

- **WHEN** `POST /api/v1/tasks/T/advances` com `id = A` é entregue duas vezes (a primeira resposta se perdeu na rede e a fila reenviou)
- **THEN** existe exatamente uma linha em `task_advances` com `id = A`, a segunda resposta é 200, e `tasks.progress` de `T` é 30 e não 60

#### Scenario: Replay tardio de uma semana continua idempotente

- **WHEN** um dispositivo fica 7 dias offline e reenvia `robot.create R` que já havia chegado ao servidor antes de perder a conectividade
- **THEN** a resposta é 200 com o robô existente e nenhum robô duplicado é criado

#### Scenario: Dois `+10` offline produzem dois avanços distintos

- **WHEN** offline, o usuário registra `+10` (0 → 10, uuid `A1`) e depois `+10` (10 → 20, uuid `A2`) na mesma tarefa, e a rede volta
- **THEN** existem duas linhas em `task_advances` (`A1` e `A2`), o progresso final é 20, e a idempotência por uuid MUST NOT coalescê-las em uma

#### Scenario: `DELETE` de recurso já removido conta como sucesso da fila

- **WHEN** `DELETE /api/v1/tasks/T` é reenviado e o servidor responde 404 porque `T` já foi removida
- **THEN** o item vai para `done` e MUST NOT entrar na quarentena

### Requirement: Falha permanente bloqueia os dependentes sem travar a fila

O sistema SHALL classificar cada resposta em retryable, permanente, conflito ou
autenticação. Ao classificar uma mutation como falha permanente, o sistema SHALL marcar
o item como `failed`, marcar o fechamento transitivo de seus dependentes como `blocked`,
e SHALL continuar drenando todo item cujo fechamento de dependências não contenha o
item falho. O sistema MUST NOT descartar itens automaticamente (D7-5).

#### Scenario: Criação do robô falha em definitivo e não deixa 5 mutations órfãs travando a fila

- **WHEN** `robot.create R` responde 422 (nome duplicado) e há 5 mutations dependentes de `R` atrás dela, mais 2 mutations independentes
- **THEN** `R` fica `failed`, as 5 dependentes ficam `blocked`, as 2 independentes são enviadas normalmente e chegam a `done`, e o indicador de gravação entra em `bloqueado`

#### Scenario: Corrigir e reenviar destrava a cascata

- **WHEN** o usuário renomeia o robô `R` na UI de reconciliação e escolhe "Corrigir e reenviar"
- **THEN** `R` volta a `pending` com o body corrigido, é enviado com sucesso, e as 5 mutations dependentes voltam de `blocked` para `pending` e são drenadas

#### Scenario: Descartar remove o fechamento transitivo inteiro e reverte a UI

- **WHEN** o usuário escolhe "Descartar 6 alterações" no item `failed` `R`
- **THEN** `R` e as 5 dependentes saem da fila, a sobreposição otimista correspondente desaparece, e a tela volta a exibir a verdade do servidor sem o robô `R`

#### Scenario: Erro de rede é retryable com backoff exponencial

- **WHEN** `POST /api/v1/robots` falha com erro de rede quatro vezes seguidas
- **THEN** os intervalos entre tentativas crescem de 1s para aproximadamente 2s, 4s e 8s com jitter, e `attempts` para erro de rede não conta contra o teto

#### Scenario: Teto de tentativas leva à quarentena

- **WHEN** `POST /api/v1/robots` responde 500 oito vezes
- **THEN** o item vai para `failed` com classe `"esgotado"`, o reenvio cessa, e a UI oferece reenvio manual

#### Scenario: 403 por revogação de papel é permanente

- **WHEN** o papel do usuário no workspace muda de `edit` para `view` enquanto há uma mutation na fila, e o servidor responde 403
- **THEN** o item vai para `failed` permanente sem retry, e a mensagem exibida informa que o acesso foi alterado

#### Scenario: 401 pausa a fila inteira em vez de queimar tentativas

- **WHEN** o servidor responde 401 para o item em voo porque o token expirou
- **THEN** a drenagem é pausada, o refresh de token é disparado, `attempts` do item MUST NOT ser incrementado, e a drenagem retoma após o refresh bem-sucedido

#### Scenario: 409 de `lock_version` vira reconciliação, não retry

- **WHEN** um avanço enfileirado offline responde 409 porque outra pessoa avançou a mesma tarefa
- **THEN** o item vai para `failed` com o estado atual do servidor em `last_error`, nenhum reenvio automático ocorre, e a UI de reconciliação de §2.4 é oferecida

### Requirement: `recorded_at` é carimbado no momento da ação, não do envio

O sistema SHALL gravar `recorded_at` no item da fila com o horário local do cliente no
instante em que o usuário confirma a ação, e SHALL enviá-lo no corpo da requisição
(D8).

#### Scenario: Avanço registrado às 14h e sincronizado às 17h aparece como 14h

- **WHEN** um avanço é confirmado offline às 14:03 e a fila o entrega ao servidor às 17:41
- **THEN** `task_advances.recorded_at` é 14:03, `task_advances.created_at` é 17:41, e a trilha da tarefa e o relatório assinado exibem 14:03

#### Scenario: Ordem da trilha segue o horário da ação

- **WHEN** o avanço `A1` é registrado offline às 14:03 e `A2` é registrado online às 15:10, e a fila entrega `A1` às 17:41
- **THEN** a trilha ordenada por `recorded_at` exibe `A1` antes de `A2`

### Requirement: Fila tem teto de tamanho com rejeição na entrada

O sistema SHALL limitar a fila a 500 itens ou 5 MB serializados. Ao atingir o teto, o
sistema SHALL rejeitar a nova mutation com erro visível e MUST NOT descartar itens já
enfileirados. Itens em `done` SHALL ser podados imediatamente; itens em `failed`
SHALL contar para o teto até decisão do usuário (D7-12).

#### Scenario: Fila cheia rejeita a nova mutation e preserva as antigas

- **WHEN** a fila tem 500 itens pendentes e o usuário confirma mais um avanço
- **THEN** a mutation é rejeitada com a mensagem "Fila offline cheia — conecte-se para sincronizar", os 500 itens continuam intactos, e o avanço mais antigo MUST NOT ser descartado

#### Scenario: Itens concluídos liberam espaço

- **WHEN** a fila está com 500 itens e a rede volta drenando 200 deles com sucesso
- **THEN** os 200 itens em `done` são podados e novas mutations voltam a ser aceitas

### Requirement: Uma única aba drena a fila e todas compartilham o estado

O sistema SHALL eleger exatamente uma aba drenadora usando um lock exclusivo nomeado
`robotrack-queue-drain` via Web Locks API, e SHALL propagar toda transição de estado de
item às demais abas por `BroadcastChannel('robotrack-queue')`. Sem Web Locks, o sistema
SHALL usar um registro `leader` em IndexedDB com expiração renovada a cada 5 segundos
(§4.2 "múltiplas abas compartilham o estado", D7-10).

#### Scenario: Três abas abertas produzem um único envio por mutation

- **WHEN** três abas do RoboTrack estão abertas com a mesma mutation pendente e a rede volta
- **THEN** o servidor recebe exatamente uma requisição para aquela mutation

#### Scenario: Estado da fila é visível em todas as abas

- **WHEN** a aba A enfileira um avanço offline
- **THEN** as abas B e C exibem o indicador de gravação em `pendente` com profundidade de fila 1, sem recarregar

#### Scenario: Fechar a aba líder transfere a liderança

- **WHEN** a aba líder é fechada com itens ainda pendentes
- **THEN** o lock é liberado pelo navegador, outra aba o adquire, e a drenagem continua sem intervenção

#### Scenario: Contagem de tentativas não é corrompida por concorrência

- **WHEN** o fallback sem Web Locks está ativo e duas abas disputam a liderança durante uma janela de expiração
- **THEN** toda escrita de `attempts` ocorre em transação `readwrite` do IndexedDB e o valor final reflete o número real de tentativas, nunca um valor menor

### Requirement: A drenagem é disparada por sinais do aplicativo e verifica conectividade real

O sistema SHALL disparar a drenagem nos eventos `online`, `visibilitychange` para
visível, foco da janela, sucesso de qualquer requisição, e por timer de 30 segundos
enquanto houver item `pending`. O sistema MUST NOT tratar `navigator.onLine` como
prova de conectividade (D7-9).

#### Scenario: Wi-Fi sem rota de saída não dispara envio em massa

- **WHEN** o dispositivo se conecta a um Wi-Fi de galpão sem saída para a internet, `navigator.onLine` vira `true` e há 40 itens pendentes
- **THEN** uma única sonda `HEAD /api/v1/health` é disparada, falha, e as 40 requisições MUST NOT ser enviadas

#### Scenario: Voltar à aba dispara a drenagem

- **WHEN** o usuário volta para a aba do RoboTrack após reconectar e há itens pendentes
- **THEN** a drenagem inicia sem esperar o timer de 30 segundos

### Requirement: A fila é escopada ao workspace corrente

O sistema SHALL gravar `workspace_id` em cada item e MUST NOT enviar itens de um
workspace enquanto outro estiver ativo, nem exibir a sobreposição otimista de um
workspace em outro (D2, invariante §4.1 nº 2).

#### Scenario: Trocar de workspace não envia mutations do anterior como se fossem do novo

- **WHEN** há 3 itens pendentes do workspace `W1` e o usuário troca para o workspace `W2`
- **THEN** os 3 itens continuam com `workspace_id = W1`, nenhuma requisição carrega `W2`, e a UI de `W2` não exibe sobreposição otimista alguma

#### Scenario: Usuário sem permissão de escrita não enfileira

- **WHEN** um membro com papel `view` tenta registrar um avanço estando offline
- **THEN** nenhuma mutation é enfileirada e a UI informa a ausência de permissão, independentemente do servidor negar de qualquer forma (invariante §4.1 nº 1)

#### Scenario: Logout preserva a fila do usuário e não a envia com outra identidade

- **WHEN** o usuário A faz logout com 2 itens pendentes e o usuário B entra no mesmo dispositivo
- **THEN** os itens de A não são enviados durante a sessão de B, e a sobreposição otimista de A não aparece na UI de B
