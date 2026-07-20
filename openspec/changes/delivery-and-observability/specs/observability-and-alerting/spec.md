## ADDED Requirements

### Requirement: Rastreio de exceção nos três processos

O sistema SHALL capturar toda exceção não tratada dos processos `web`, `worker` e do
cliente React num serviço de rastreio de erro, substituindo integralmente as chamadas a
`ExceptionNotifier` removidas por `seal-template-baseline`.

#### Scenario: exceção em endpoint Grape é registrada com contexto

- **WHEN** um `GET /api/v1/workspaces/W1/projects` levanta `ActiveRecord::StatementInvalid`
- **THEN** um evento SHALL ser enviado ao rastreio contendo `request_id`, `user_id`,
  `workspace_id` e o nome da rota
- **AND** a resposta HTTP ao cliente SHALL ser 500 sem stacktrace no corpo

#### Scenario: job Sidekiq que esgota retries é registrado

- **WHEN** um job de reconciliação falha nas 25 tentativas e vai para a dead set
- **THEN** um evento de severidade `error` SHALL ser registrado nomeando a classe do job e
  seus argumentos serializados

#### Scenario: nenhuma referência a ExceptionNotifier permanece

- **WHEN** o repositório é varrido por `ExceptionNotifier`
- **THEN** nenhuma ocorrência SHALL existir em `backend/app/` ou `backend/config/`

#### Scenario: PII não é enviada ao rastreio

- **WHEN** uma exceção ocorre numa requisição cujo corpo contém
  `{"password":"segredo123","email":"a@b.com"}`
- **THEN** o evento enviado SHALL NOT conter a string `segredo123`
- **AND** SHALL NOT conter o corpo da requisição

### Requirement: Log estruturado em JSON com identificadores de tenant

O sistema SHALL emitir uma linha JSON por requisição em `staging` e `production`,
contendo `request_id`, `method`, `path`, `status`, `duration`, `db_runtime`, `user_id`,
`workspace_id`, `person_id` e `policy`.

#### Scenario: linha de log é JSON parseável

- **WHEN** `GET /api/v1/workspaces/W1/projects` responde 200 em 43 ms
- **THEN** a linha emitida SHALL ser um objeto JSON válido numa única linha
- **AND** SHALL conter `"status":200` e `"workspace_id":"W1"`

#### Scenario: requisição não autenticada não quebra o log

- **WHEN** uma requisição a uma rota pública responde 200 sem usuário
- **THEN** a linha SHALL conter `"user_id":null` e `"workspace_id":null`
- **AND** SHALL NOT levantar exceção durante a formatação

#### Scenario: parâmetros sensíveis são filtrados

- **WHEN** uma requisição inclui `invitation_token=abc` e header
  `Authorization: Bearer xyz`
- **THEN** a linha de log SHALL conter `[FILTERED]` no lugar dos dois valores

### Requirement: Endpoints de saúde distintos para liveness e readiness

O sistema SHALL expor `GET /health/live` e `GET /health/ready`, ambos públicos e sem
autenticação, e `/health/ready` SHALL verificar Postgres, Redis de fila e migrations
pendentes.

#### Scenario: readiness falha com migration pendente

- **WHEN** existe migration em `db/migrate` não presente em `schema_migrations`
- **THEN** `GET /health/ready` SHALL responder 503
- **AND** o corpo SHALL nomear `pending_migrations`

#### Scenario: liveness não depende de dependência externa

- **WHEN** o Postgres está inacessível
- **THEN** `GET /health/live` SHALL responder 200
- **AND** `GET /health/ready` SHALL responder 503

#### Scenario: health check não exige autenticação

- **WHEN** `GET /health/live` é chamado sem header `Authorization`
- **THEN** a resposta SHALL ser 200
- **AND** o path SHALL constar da allowlist de rotas públicas sem depender do header
  `X-Skip-Auth`, que `seal-template-baseline` elimina

### Requirement: Métricas de infraestrutura e de negócio

O sistema SHALL expor métricas em `GET /metrics`, protegido por token, incluindo latência
de requisição por rota, taxa de erro 5xx, profundidade e latência da fila Sidekiq,
conexões ActionCable ativas e contadores de negócio (avanços registrados, mutations
offline drenadas, divergências de `progress_cache`).

#### Scenario: profundidade de fila é observável

- **WHEN** 1.200 jobs estão enfileirados na fila `default`
- **THEN** `GET /metrics` SHALL reportar `sidekiq_queue_depth{queue="default"} 1200`

#### Scenario: endpoint de métricas não é público

- **WHEN** `GET /metrics` é chamado sem o token de `METRICS_TOKEN`
- **THEN** a resposta SHALL ser 401
- **AND** nenhum valor de métrica SHALL constar no corpo

#### Scenario: métricas não expõem identificadores de tenant como label

- **WHEN** métricas são coletadas num sistema com 300 workspaces
- **THEN** nenhuma série SHALL ter `workspace_id` como label
- **AND** contadores de negócio SHALL ser agregados globalmente

### Requirement: Canal único de alerta com severidade e deduplicação

O sistema SHALL prover `Ops::AlertService.raise_alert(key:, severity:, message:,
context:)` como único caminho de alerta, com `severity ∈ {info, warning, critical}` e
deduplicação atômica por `key` numa janela de 1 hora.

#### Scenario: alerta repetido na janela é suprimido

- **WHEN** `raise_alert(key: "progress_cache_divergence:W1", severity: :warning, …)` é
  chamado às 10h00 e novamente às 10h30
- **THEN** apenas uma notificação SHALL ser enviada ao destino externo
- **AND** a segunda chamada SHALL incrementar um contador de supressão sem notificar

#### Scenario: alerta reaparece após a janela

- **WHEN** a mesma `key` é levantada às 10h00 e às 11h05
- **THEN** duas notificações SHALL ser enviadas

#### Scenario: severidade decide o destino

- **WHEN** `severity: :info` é usada
- **THEN** o alerta SHALL ir apenas para o log estruturado
- **AND** SHALL NOT gerar chamada ao webhook de chat nem ao pager

#### Scenario: destino indisponível não derruba o chamador

- **WHEN** o webhook de chat responde 500 durante um `raise_alert` chamado de dentro de um
  job
- **THEN** `raise_alert` SHALL NOT levantar exceção para o chamador
- **AND** a falha de entrega SHALL ser registrada no log estruturado

#### Scenario: alerta de divergência de progresso encontra canal pronto

- **WHEN** o job de reconciliação de `progress-rollup` (D5) detecta `progress_cache = 45`
  contra cálculo `= 100` no projeto `P1`
- **THEN** ele SHALL chamar `raise_alert` com `severity: :warning` e
  `key: "progress_cache_divergence:P1"`
- **AND** o contexto SHALL conter os dois valores divergentes

### Requirement: Condições de alerta operacionais definidas

O sistema SHALL disparar alerta automático para: taxa de 5xx acima de 1% em janela de 5
minutos, profundidade de fila Sidekiq acima de 1.000 por mais de 10 minutos, job na dead
set, falha de conexão ao Redis de Cable e falha da fase de release.

#### Scenario: taxa de erro cruza o limiar

- **WHEN** 15 de 1.000 requisições numa janela de 5 minutos respondem 5xx
- **THEN** um alerta `critical` com `key: "error_rate_5xx"` SHALL ser levantado

#### Scenario: fila abaixo do limiar não alerta

- **WHEN** a fila atinge 1.200 jobs e drena para 200 em 4 minutos
- **THEN** nenhum alerta de profundidade de fila SHALL ser levantado

#### Scenario: perda do Redis de Cable é alertada

- **WHEN** o adapter de ActionCable falha ao publicar por 3 tentativas consecutivas
- **THEN** um alerta `critical` SHALL ser levantado
- **AND** o `message` SHALL nomear `REDIS_CABLE_URL` sem incluir a senha da URL
