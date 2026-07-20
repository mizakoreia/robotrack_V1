# test-harness-baseline

## ADDED Requirements

### Requirement: Factories para os models sobreviventes

O sistema SHALL prover factories `factory_bot` em `backend/spec/factories/` para
todos os models que permanecem após a redução de escopo, e SHALL falhar o CI se
alguma factory ficar inválida.

#### Scenario: Toda factory declarada constrói e persiste

- **WHEN** um spec de sanidade itera `FactoryBot.factories.map(&:name)` e chama
  `create` em cada uma
- **THEN** todas SHALL persistir sem erro, e a falha SHALL nomear a factory e a
  mensagem de validação da primeira que falhar

#### Scenario: Factory de usuário produz e-mails únicos em lote

- **WHEN** `create_list(:user, 50)` é executado
- **THEN** SHALL persistir 50 registros sem violar o índice único de `email`,
  provando que a sequência de e-mail é usada em vez de um literal

#### Scenario: Factories não referenciam models removidos

- **WHEN** `backend/spec/factories/` é listado
- **THEN** NÃO SHALL existir factory para `Lead`, `Operation`, `PolemkInstance`,
  `Permission`, `LoginCode`, `LoginAttempt` nem `ClientApplication`

### Requirement: Helper de autenticação de request compartilhado

O sistema SHALL prover um único helper em `backend/spec/support/request_auth_helper.rb`
que gera cabeçalhos autenticados para specs de request. Nenhum spec SHALL
redefinir `bearer_for` localmente.

#### Scenario: Helper produz um token aceito pelo bloco before de Api::Root

- **WHEN** um spec chama `auth_headers(user)` e emite `GET /api/v1/users` com o
  resultado
- **THEN** a resposta SHALL ser `200` e `env['api.current_user']` SHALL ser o
  `user` informado

#### Scenario: Não há definição duplicada de bearer_for

- **WHEN** `backend/spec/` é varrido por `def bearer_for`
- **THEN** o número de ocorrências SHALL ser `0`, com o helper compartilhado
  incluído via `config.include RequestAuthHelper, type: :request`

#### Scenario: Helper permite construir o caminho negativo

- **WHEN** um spec chama `auth_headers(user, expired: true)`
- **THEN** a requisição correspondente SHALL receber `401`, tornando o teste de
  token expirado escrevível sem manipular JWT à mão em cada spec

### Requirement: Estratégia de limpeza de banco declarada

O sistema SHALL manter `use_transactional_fixtures = true` como padrão e SHALL
usar `database_cleaner-active_record` com estratégia `:truncation` apenas para
exemplos marcados com metadado que rodam fora da transação do RSpec.

#### Scenario: Spec transacional não deixa resíduo

- **WHEN** um spec cria 3 usuários e termina, e o spec seguinte executa
  `User.count`
- **THEN** o resultado SHALL ser `0`

#### Scenario: Spec marcado usa truncation

- **WHEN** um exemplo marcado com `js: true` cria 2 usuários a partir de outra
  conexão e termina
- **THEN** `DatabaseCleaner` SHALL truncar as tabelas afetadas e o exemplo
  seguinte SHALL observar `User.count == 0`

### Requirement: Suíte backend verde e substantiva

O sistema SHALL manter `bundle exec rspec` terminando com 0 falhas e 0 erros, e
a suíte SHALL conter os specs de regressão que provam as vedações desta mudança.

#### Scenario: Execução limpa

- **WHEN** `bundle exec rspec` é executado sobre um banco recém-carregado
- **THEN** SHALL terminar com código `0`, `0 failures` e `0 errors occurred
  outside of examples`

#### Scenario: Specs de módulos removidos não permanecem

- **WHEN** `backend/spec/` é listado
- **THEN** `whats_instances_spec.rb`, `whats_messages_spec.rb`,
  `polemk_instance_service_spec.rb`, `magic_login_service_spec.rb`,
  `checkout_session_service_spec.rb`, `permissions_sync_service_spec.rb`,
  `login_code_spec.rb` e `pre_register_flow_spec.rb` NÃO SHALL estar presentes

#### Scenario: Suíte cobre as vedações, não apenas o smoke test

- **WHEN** a lista de arquivos de spec é inspecionada
- **THEN** SHALL conter specs de request para o bypass de header, para o sweep de
  rotas 401, para o formato do erro 500, e um spec de `ActionCable::Connection`
  para a rejeição anônima

### Requirement: Suíte frontend verde sem testes falsamente pulados

O sistema SHALL manter `npm test` terminando com 0 falhas e 0 arquivos com erro
de importação. Nenhum teste SHALL ser mantido verde por `skip` ou `todo` quando
a funcionalidade que ele testa foi removida.

#### Scenario: Nenhum teste importa página inexistente

- **WHEN** `npx vitest run` é executado
- **THEN** SHALL terminar com código `0`, e nenhum erro
  `Failed to resolve import` SHALL aparecer para `CheckoutPage`,
  `AdminPlansPage`, `AdminFeaturesPage` ou `PaymentsPage`

#### Scenario: Testes de funcionalidade removida foram deletados, não pulados

- **WHEN** `frontend/src/` é varrido por `it.skip`, `describe.skip` e `it.todo`
- **THEN** o número de ocorrências SHALL ser `0`

#### Scenario: A suíte cobre o interceptor de refresh single-flight

- **WHEN** duas requisições concorrentes recebem `401` e o teste observa as
  chamadas de rede de `lib/api/client.ts`
- **THEN** SHALL ocorrer exatamente `1` POST de refresh e `2` retentativas das
  requisições originais, e não `2` POSTs de refresh

### Requirement: Ambas as suítes executáveis por um comando documentado

O sistema SHALL documentar e prover um caminho único de execução das duas suítes
a partir de um checkout limpo, para que `delivery-and-observability` o conecte a
CI sem redescobrir os passos.

#### Scenario: Execução a partir de checkout limpo

- **WHEN** `bundle install`, `rails db:create db:schema:load`, `bundle exec rspec`,
  `npm ci` e `npx vitest run` são executados em sequência num clone novo
- **THEN** todos os cinco comandos SHALL terminar com código `0`

#### Scenario: Env vars obrigatórias estão declaradas

- **WHEN** `.env.example` é comparado com as variáveis lidas por
  `backend/config/` após a remoção
- **THEN** SHALL conter `DATABASE_URL`, `REDIS_URL`, `DEVISE_JWT_SECRET_KEY`,
  `APP_NAME` e as credenciais do Google OAuth, e NÃO SHALL conter variáveis de
  Evolution, Asaas ou SMTP do magic-login
