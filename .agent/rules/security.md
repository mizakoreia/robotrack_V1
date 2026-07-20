---
trigger: always_on
---

# Security Rules

## 4) Segurança

* **HTTPS only**; HSTS.
* **JWT** seguro: expiração curta + refresh; armazenamento: memory/httponly (admin) + CSRF para painéis.
* **Rate limit** (Rack::Attack) por IP/rota; chaves em headers.
* **Validação de payload** (Grape params + esquemas TS no frontend).
* **Headers**: `X-Content-Type-Options`, `X-Frame-Options`, `Content-Security-Policy`.
* **Secrets** exclusivamente em variáveis de ambiente/credenciais.

---

## 12) Checklist de Segurança em Produção

### 12.1 Contas & Acesso

* [ ] Admin/console atrás de **login JWT** + **roles**; MFA obrigatório para contas administrativas.
* [ ] Painéis (Sidekiq/Any admin) com proteção extra (basic auth/IP allowlist).

### 12.2 Segredos & Config

* [ ] Segredos apenas em **Rails.credentials**/variáveis protegidas do CI; nunca em git.
* [ ] Rotação periódica de chaves (Asaas/Evolution/JWT). Algoritmo JWT `RS256` ou `HS256` com chave forte.

### 12.3 Transporte & Headers

* [ ] **HTTPS** obrigatório + **HSTS**.
* [ ] **CSP** restritiva (default-src 'self';) com allowlists mínimas.
* [ ] `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: strict-origin-when-cross-origin`.

### 12.4 API & Rate Limiting

* [ ] **Rack::Attack** por IP/rota/chaves.
* [ ] Validação de payload (Grape params) e limites de tamanho (`max_content_length`).
* [ ] Webhooks (Asaas/Evolution) com verificação de assinatura/timestamp e **rejeição** de duplicatas.

### 12.5 Dados & Banco

* [ ] Postgres com SSL, usuários mínimos por ambiente, **least privilege**.
* [ ] **Criptografia** at-rest (armazenamento) quando aplicável; hashing de senhas com **bcrypt** (custo adequado).
* [ ] Backups automáticos testados (restore drill) e retenção definida.
* [ ] Índices/constraints para integridade; remoção/anonimização de PII quando desnecessária.

### 12.6 Uploads & Conteúdo

* [ ] Sanitização de uploads (MIME/Extensão), varredura anti‑malware se aplicável.
* [ ] Desabilitar execução em buckets (S3/Cloud) e tornar privados por padrão.

### 12.7 Observabilidade & Resposta a Incidentes

* [ ] Logs estruturados, sem PII sensível; retenção/rotação configuradas.
* [ ] Runbooks para incidentes (webhook fora do ar, fila congestionada, picos de tráfego).

### 12.8 Dependências & Build

* [ ] `brakeman`/`bundler-audit`/`npm audit` limpos; pins em versões seguras.
* [ ] Supply chain: lockfiles com integridade, verificação de assinaturas se disponível.

### 12.9 Realtime

* [ ] Action Cable com Redis autenticado, canais namespaced, checagem de escopos.
* [ ] Limites de broadcast, proteção contra flood, desconexão de clientes ociosos.

### 12.10 Política de CORS & Origem

* [ ] Origens explicitamente **whitelistadas** por ambiente; bloquear wildcard em produção.
