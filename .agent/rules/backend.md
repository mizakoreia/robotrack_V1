---
trigger: always_on
---

# Backend Rules (Rails 8 API‑only)

## 2) Backend (Rails 8 API‑only)

### 2.1 Estrutura de pastas (essencial)

```
backend/
  app/
    controllers/
      api/
        v1/
          base.rb           # monta endpoints Grape
          auth.rb           # login/refresh/logout
          users.rb          # CRUD usuários
          payments.rb       # Asaas webhooks e consultas
          whatsapp.rb       # Evolution webhooks/envio
    channels/               # Action Cable channels
    models/                 # modelos ActiveRecord (uuid)
    serializers/            # (opcional) representação JSON
    services/
      asaas/
      evolution/
      auth/
    jobs/
    workers/                # (se usar Sidekiq diretamente)
  config/
    initializers/
      grape.rb
      grape_swagger.rb
      cors.rb
      sidekiq.rb
      action_cable.rb
    cable.yml
    database.yml
  spec/                     # RSpec + FactoryBot + VCR/WebMock
```

### 2.2 Gems base

* **API**: `grape`, `grape-entity`, `grape-swagger`, `grape-swagger-rails` (ou servir JSON puro + Stoplight Elements no frontend `/docs`).
* **Auth**: `devise`, `devise-jwt` (JWT stateless), `doorkeeper` (opcional se OAuth2).
* **Perf/Sec**: `rack-cors`, `rack-attack`, `brakeman`, `bundler-audit`.
* **Jobs/Realtime**: `sidekiq`, `redis`, `actioncable`.
* **Pagamentos**: cliente HTTP para Asaas (`faraday`/`httpx`) + serviços dedicados.
* **WhatsApp**: cliente HTTP Evolution API (`faraday`/`httpx`) + webhooks.
* **Testes**: `rspec-rails`, `factory_bot_rails`, `database_cleaner-active_record`, `faker`, `vcr`, `webmock`, `simplecov`.
* **Qualidade**: `rubocop`, `standardrb` (opcional), `solargraph` (LSP), `yard` (docs).

### 2.3 Convenções de código

* **Comentários obrigatórios** em classes, módulos e métodos públicos (YARD).
* **Nomes explícitos** de serviços (ex.: `Asaas::CreatePayment`, `Evolution::SendTextMessage`).
* **Entities** do Grape para **contratos de resposta**. Nunca retornar modelos crus.
* **Erros** padronizados: envelope `{ error: { code, message, details } }` + HTTP correto.
* **Paginação** padrão: `page` + `per_page`, cabeçalhos `X-Total-Count`, `Link`.
* **Idempotência** em endpoints sensíveis (ex.: criação de cobrança). Use `Idempotency-Key`.
* **CORS** liberando apenas origens conhecidas (env var).

### 2.4 Autenticação & Autorização

* **JWT** (Bearer) emitido no login; refresh token separado.
* **Scopes**/Roles em `Ability` (Pundit ou CanCanCan). Autorização em cada endpoint.
* Expirar tokens curtos (ex.: 15min) e renovar com refresh (ex.: 7d). Revogação em blacklist Redis.

### 2.5 Action Cable

* Canais por recurso: `NotificationsChannel`, `PaymentsChannel`, `ChatChannel`.
* Identificar usuário pelo JWT (cookie httpOnly opcional para admin).
* Escalar com Redis (config em `cable.yml`).

### 2.6 Integração Evolution API (WhatsApp)

* **Env vars**: `EVOLUTION_BASE_URL`, `EVOLUTION_API_KEY`, `EVOLUTION_INSTANCE`, callbacks.
* **Serviços**: `Evolution::SendTextMessage`, `Evolution::SendMedia`, `Evolution::ListContacts`.
* **Webhooks**: endpoint `POST /whats/v1/webhooks` (Grape), validar assinatura/UA quando aplicável.
* Persistir eventos relevantes (mensagens recebidas, status de entrega) e publicar em `ChatChannel`.

### 2.7 Integração Asaas (Pagamentos)

* **Env vars**: `ASAAS_BASE_URL`, `ASAAS_API_KEY`, `ASAAS_WEBHOOK_SECRET`.
* **Serviços**: `Asaas::CreateCustomer`, `Asaas::CreateCharge`, `Asaas::GetQRCode`, `Asaas::Refund`.
* **Webhooks**: `POST /asaas/v1/webhooks/*` com verificação de assinatura.
* Estados de pagamento em FSM (`aasm` opcional) e broadcasts via Action Cable.

### 2.8 Modelagem & Banco (PostgreSQL)

* **UUID** como PK: `enable_extension 'pgcrypto'` e `default: -> { "gen_random_uuid()" }`.
* **Timestamps UTC**; conversão de fuso no frontend.
* **Índices** para buscas (compostos para chaves usuais) e restrições de unicidade.
* **Auditoria** (opcional): `paper_trail`.

### 2.9 Documentação OpenAPI

* Gerar em `/swagger_doc` via `grape-swagger`.
* **Stoplight Elements** servido em `/docs` consumindo o JSON.
* Manter exemplos de request/response e códigos de erro.

### 2.10 Testes (obrigatório)

* **RSpect** unitário, request e canais (Action Cable).
* **Cobertura mínima** 90% (falha de CI se < 90%).
* **VCR** + **WebMock** para Evolution/Asaas.
* **Factories** consistentes; `lint` em CI.
* Rodar `brakeman` e `bundler-audit` no pipeline.

---

## 7) Convenções de API

* **Prefix**: por módulo (`/auth/v1`, `/whats/v1`, `/asaas/v1`).
* **Content‑Type**: `application/json; charset=utf-8`.
* **Autorização**: `Authorization: Bearer <jwt>`.
* **Padrão de resposta** (ex.):
* **Descobir endpoints da api:** `http://localhost:3000/swagger_doc`
```json
{
  "data": {"id": "...", "attributes": {...}},
  "meta": {"request_id": "..."},
  "errors": null
}
```

* **Erros**:

```json
{
  "errors": [{"code": "validation_error", "message": "...", "details": {...}}]
}
```

* **Paginação**: `?page=1&per_page=20` + headers `X-Total-Count` e `Link`.
* **Idempotência**: cabeçalho `Idempotency-Key` em POST críticos.

------------------------------------------------------------------------

### 7.1 **Padrão Oficial para API + Services + Entities (OBRIGATÓRIO)**

Esta subseção adiciona diretrizes **formais** que todo endpoint e todo
service devem seguir, baseadas exatamente no padrão adotado em
`UsersService`.

#### ✔️ 1. Toda lógica de negócio deve ficar em Services

Controllers Grape **não podem** conter: - consultas ao banco - blocos
`if/else` de regras - cálculos - parse ou limpeza de dados -
criação/atualização de modelos

#### ✔️ 2. Services DEVEM retornar Entities do Grape para qualquer modelo interno

Sempre que o service retorna dados de modelos, deve retornar:

``` ruby
success_response(Api::Entities::User.represent(user), 200)
```

Ou para coleções:

``` ruby
success_response(
  { users: Api::Entities::User.represent(users), total: total },
  200
)
```

#### ✔️ 3. Controllers NÃO chamam `present`

Eles apenas fazem:

``` ruby
process_service_response(UsersService.index(params))
```

#### ✔️ 4. Estrutura padrão de um service

Todos os services devem conter:

``` ruby
include ApiResponseHandler
```

E sempre retornar usando:

``` ruby
success_response(data, http_status)
error_response(data, http_status)
validation_error_response(message)
not_found_response(model_name)
internal_error_response(error_message)
```

#### ✔️ 5. Entities obrigatórios para qualquer retorno que envolva ActiveRecord

**Proibido** retornar AR diretamente:

❌ Errado:

``` ruby
success_response(user)
```

✔️ Certo:

``` ruby
success_response(Api::Entities::User.represent(user))
```

#### ✔️ 6. Controllers finos ("thin controllers")

Controllers devem conter apenas:

1.  descrição (`desc`)
2.  validação de parâmetros (`params do ... end`)
3.  chamada de serviço
4.  headers de paginação quando aplicável
5.  `process_service_response`

Exemplo obrigatório:

``` ruby
get '' do
  result = UsersService.index(params)
  set_pagination_headers(result[:data][:total], params[:page], params[:per_page])
  process_service_response(result)
end
```

#### ✔️ 7. Padrão único para erros

Todos os serviços devem retornar:

``` json
{
  "errors": [
    { "code": "validation_error", "message": "Mensagem" }
  ]
}
```

Grape NUNCA deve retornar erros crus ou mensagens inconsistentes.

#### ✔️ 8. Documentação Grape obrigatória

Cada endpoint precisa ter:

-   `summary`
-   `detail`
-   códigos HTTP
-   entidade de resposta (quando existir)
-   parâmetros validados

---

## 11) Scripts & Comandos Rápidos (Backend)

```bash
bin/setup            # instala gems, prepara DB
bin/rspec            # roda testes com SimpleCov
rubocop -A           # corrige estilo
brakeman -q -w2      # segurança
bundle audit check   # dependências vulneráveis
sidekiq -C config/sidekiq.yml
```
