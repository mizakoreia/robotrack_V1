---
trigger: always_on
---

# Project Rules — Monorepo (Rails 8 API + React .tsx)

> **Objetivo**: Documento‑guia para iniciar e manter o novo projeto com backend **Rails 8 (API‑first)** + **Grape + Swagger** (visualização com **Stoplight Elements**) e frontend **React (.tsx)** consumindo **100% via API**. Inclui Action Cable, Turbo/Hotwire (tempo real/admin), PostgreSQL, Evolution API (WhatsApp), Asaas (pagamentos), temas **dark/light**, testes obrigatórios e automações de CI/CD.

---

## 1) Arquitetura & Padrões

* **Monorepo** com duas pastas raiz:
  * `backend/` → Rails 8 API‑only
  * `frontend/` → React + TypeScript (.tsx)
* **API‑first**: todo fluxo de dados, autenticação e autorização via API.
* **Versionamento de API**: por módulo com **Grape** dentro de `controllers/api`:
  * Autenticação: `/auth/v1/*`
  * WhatsApp: `/whats/v1/*`
  * Asaas: `/asaas/v1/*`
* **Documentação**: gerar OpenAPI (Swagger) automaticamente com **grape-swagger**; servir **/swagger_doc** (JSON) e visualizar com **Stoplight Elements** em `/docs`.
* **Tempo real**: **Action Cable** para eventos do servidor → cliente (notificações, estados de pagamento, mensagens), canalizando por **Redis**. **Turbo Streams**/Hotwire opcionais para painel/admin interno.
* **Banco**: **PostgreSQL 14+**, chaves **UUID** por padrão, migrações idempotentes, índices compostos.
* **Mensageria/Jobs**: **ActiveJob** com **Sidekiq** (Redis) para webhooks, filas e integrações externas.
* **Config por ambiente**: `dotenv-rails`/Credenciais Rails; no frontend, `.env` + Vite/Next.
* **Observabilidade**: logs estruturados (JSON), **Rack::Attack** (rate limit), **Skylight/New Relic** (perf).

---

## 13) Roadmap Inicial (sugestão)

1. Bootstrap Monorepo + CI básico (lint + testes em branco).
2. Autenticação JWT end‑to‑end (login/refresh/logout) + guard no React.
3. Módulo Pagamentos (Asaas): criar cobrança, webhook, realtime status.
4. Módulo WhatsApp (Evolution): envio texto, recepção webhook, canal realtime.
5. Tematização dark/light completa.
6. Observabilidade (Sentry) + limites (Rack::Attack).
7. Harden: idempotência, paginação, erros padronizados, docs ricas.

---

## 14) Áreas do Sistema

* **Site Público**: acessível a todos, consumindo APIs públicas (ex.: landing pages, planos, documentação, política de privacidade, status page).
* **Console Administrativo**: somente para usuários autenticados (JWT) e autorizados por role/scope. Todo o backend é via API e o frontend React controla acesso com guards e refresh token.

### Notas finais

* Qualquer divergência dessas regras requer **issue** + **aprovação em PR**.
* Para preview rodar ./bin/dev ele ja abre os dois servidores (backend e frontend)
* Backend (API) roda na porta 3000
* Frontend (React) roda na porta 5173