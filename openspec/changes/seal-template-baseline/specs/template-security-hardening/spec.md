# template-security-hardening

## ADDED Requirements

### Requirement: Eliminação do bypass por header

O sistema SHALL ignorar completamente os headers `X-Skip-Auth` e
`HTTP_X_SKIP_AUTH`. Nenhum valor desses headers MUST alterar o resultado da
autenticação de qualquer requisição.

#### Scenario: Header de bypass em rota protegida sem token

- **WHEN** um cliente envia `GET /api/v1/users` com o header `X-Skip-Auth: 1` e
  sem header `Authorization`
- **THEN** a resposta SHALL ser `401` com corpo
  `{"error":"unauthorized","message":"Authorization header ausente"}`

#### Scenario: Header de bypass com token inválido

- **WHEN** um cliente envia `GET /api/v1/users` com `X-Skip-Auth: 1` e
  `Authorization: Bearer nao-e-um-jwt`
- **THEN** a resposta SHALL ser `401` e o corpo NÃO SHALL conter nenhum dado de
  usuário

#### Scenario: Header de bypass não altera resposta de requisição válida

- **WHEN** a mesma requisição `GET /api/v1/users` com `Authorization: Bearer <jwt válido>`
  é enviada duas vezes, uma com `X-Skip-Auth: 1` e outra sem
- **THEN** ambas SHALL retornar `200` com corpos idênticos, provando que o header
  não é lido

#### Scenario: O literal do header não existe mais no código-fonte

- **WHEN** o código de `backend/app/` é varrido por `X-Skip-Auth` ou `X_SKIP_AUTH`
- **THEN** o número de ocorrências SHALL ser `0`

### Requirement: Allowlist de rotas públicas explícita e fechada

O sistema SHALL declarar as rotas que dispensam autenticação em uma única
constante congelada `Api::Root::PUBLIC_ROUTES`. Toda rota montada em `Api::Root`
que não case com nenhum padrão dessa constante SHALL exigir `Authorization:
Bearer` válido.

#### Scenario: Toda rota não-pública responde 401 sem token

- **WHEN** um teste enumera `Api::Root.routes`, remove as que casam com
  `PUBLIC_ROUTES`, e emite cada rota restante sem header `Authorization`
- **THEN** cada uma SHALL responder `401`, e o teste SHALL falhar nomeando o
  método e o caminho da primeira rota que responder qualquer outro status

#### Scenario: Rotas públicas remanescentes são exatamente três padrões

- **WHEN** `Api::Root::PUBLIC_ROUTES` é inspecionada
- **THEN** ela SHALL conter exatamente os padrões para `/swagger_doc`,
  `/api/v1/countries` e `/auth/v1/oauth/(google_url|callback)`, e NÃO SHALL
  conter nenhum padrão de `magic_login`, `code_validation`, `pre_register`,
  `verify_code`, `complete_registration`, `checkout` ou `whats/v1/webhooks`

#### Scenario: Rota pública continua acessível sem token

- **WHEN** `GET /api/v1/countries` é emitida sem header `Authorization`
- **THEN** a resposta SHALL ser `200`

### Requirement: Remoção do fallback de autenticação por ClientApplication

O sistema SHALL remover o caminho de autenticação que aceita um token opaco de
`ClientApplication`. Um token que não decodifica para um `User` existente SHALL
resultar em `401`, sem consulta alternativa a nenhuma outra tabela.

#### Scenario: Token opaco de aplicação é rejeitado

- **WHEN** um cliente envia `GET /api/v1/users` com
  `Authorization: Bearer <token que existia em client_applications>`
- **THEN** a resposta SHALL ser `401` com `{"error":"unauthorized","message":"Token inválido"}`

#### Scenario: A constante ClientApplication não é mais referenciada

- **WHEN** `backend/app/` é varrido por `ClientApplication` e
  `api.current_client`
- **THEN** o número de ocorrências SHALL ser `0`, e o helper `current_client`
  SHALL ter sido removido de `Api::Root`

### Requirement: ActionCable rejeita conexão não autenticada

O sistema SHALL rejeitar toda conexão WebSocket em `/cable` cujo parâmetro
`token` esteja ausente, seja inválido, esteja expirado ou não resolva um `User`
existente. `ApplicationCable::Connection#current_user` NUNCA SHALL ser `nil`
numa conexão estabelecida.

#### Scenario: Conexão sem token é rejeitada

- **WHEN** um cliente abre `ws://host/cable` sem parâmetro `token`
- **THEN** a conexão SHALL ser rejeitada com
  `ActionCable::Connection::Authorization::UnauthorizedError` e nenhum canal
  SHALL ser subscrito

#### Scenario: Conexão com token cujo sub não existe é rejeitada

- **WHEN** um cliente abre `/cable?token=<jwt assinado corretamente com sub de um usuário já deletado>`
- **THEN** a conexão SHALL ser rejeitada, e não SHALL ser estabelecida com
  `current_user = nil`

#### Scenario: Conexão com token válido é aceita e identificada

- **WHEN** um cliente abre `/cable?token=<jwt válido do usuário U>`
- **THEN** a conexão SHALL ser estabelecida e `connection.current_user.id` SHALL
  ser igual a `U.id`

#### Scenario: Canais legados não existem mais

- **WHEN** `backend/app/channels/` é listado
- **THEN** ele SHALL conter apenas `application_cable/connection.rb` e
  `application_cable/channel.rb`, e NÃO SHALL conter `dashboard_channel.rb`,
  `lead_chat_channel.rb`, `permissions_channel.rb` nem
  `whatsapp_instance_channel.rb`

### Requirement: Resposta de erro sem vazamento de backtrace

O sistema SHALL responder a exceções não tratadas com um corpo JSON contendo
apenas `error`, `message` e `request_id`. O backtrace e a mensagem original da
exceção SHALL ser gravados apenas no log do servidor.

#### Scenario: Exceção interna não expõe caminho de arquivo

- **WHEN** um endpoint levanta `RuntimeError.new("conexão com o banco X falhou em /app/services/foo.rb")`
- **THEN** o corpo da resposta SHALL ser `500` com as chaves exatamente
  `error`, `message` e `request_id`, e o corpo NÃO SHALL casar com a expressão
  `/BACKTRACE|\.rb:\d+|app\/(services|controllers|models)/`

#### Scenario: O mesmo erro é rastreável pelo log

- **WHEN** a resposta acima retorna `request_id: "abc-123"`
- **THEN** o log do servidor SHALL conter uma linha com `abc-123`, a mensagem
  original da exceção e o backtrace completo

#### Scenario: Erro de validação continua informativo

- **WHEN** um endpoint recebe parâmetros que falham a validação do Grape
- **THEN** a resposta SHALL ser `400` com `{"error":"validation_error"}` e a
  lista de campos inválidos, e NÃO SHALL ser mascarada como `internal_error`

### Requirement: Notificação de exceção sem gem ausente

O sistema SHALL encaminhar exceções não tratadas a um módulo
`ErrorReporter` que delega para `Rails.error.report`. Nenhuma referência à
constante `ExceptionNotifier` SHALL permanecer no código.

#### Scenario: Rescue não levanta NameError

- **WHEN** uma exceção é levantada dentro de um endpoint Grape em ambiente de
  teste
- **THEN** o cliente SHALL receber `500` com corpo JSON válido, e NENHUM
  `NameError: uninitialized constant ExceptionNotifier` SHALL aparecer no log

#### Scenario: Contexto do erro chega ao reporter

- **WHEN** `ErrorReporter.report` é interceptado durante uma exceção em
  `GET /api/v1/users` de um usuário autenticado `U`
- **THEN** ele SHALL ser chamado exatamente uma vez com a exceção e um contexto
  contendo `request_id`, `path` igual a `/api/v1/users` e `user_id` igual a `U.id`

#### Scenario: Não há rescue_from duplicado

- **WHEN** `backend/app/controllers/api/` é varrido por `rescue_from :all`
- **THEN** SHALL haver exatamente `1` ocorrência, em `api/root.rb`
