---
trigger: always_on
---

# Quality, QA & CI/CD Rules

## 5) Qualidade & Padrões de Código

* **Lint**: `rubocop` (backend) e `eslint + @typescript-eslint` (frontend); `prettier`.
* **Commits**: Conventional Commits + **lint-staged** em pre-commit.
* **Branching**: trunk‑based com feature branches curtas; PR obrigatório.
* **Code Review**: 1+ aprovação; não fazer merge com CI vermelho.
* **Comentários**: todo arquivo/classe/função com comentário explicando finalidade.

---

## 6) Testes & CI/CD

### 6.1 Pipeline (GitHub Actions)

* **Backend**:
  * `bundle install --path vendor/bundle`
  * `rubocop`, `brakeman`, `bundler-audit`
  * `rails db:setup RAILS_ENV=test`
  * `rspec --format documentation --fail-fast`
  * `simplecov` → gate 90%
* **Frontend**:
  * `pnpm i`
  * `eslint --max-warnings=0`
  * `vitest run` (ou `jest`)
  * `tsc --noEmit`
* **Artifacts**: publicar cobertura e relatório de lint.

### 6.2 Deploy

* **Infra**: Docker + Compose; produção em Kubernetes ou VM com Systemd.
* **Rails**: Puma; **Redis** para Sidekiq/Action Cable.
* **Migrations**: rodar antes do boot da nova versão.
* **Rollback**: manter 2 releases prontos.

---

## 10) Definition of Done (DoD)

### 10.1 Backend

* [ ] **Docs**: endpoint documentado no Swagger com **exemplos de request/response**, códigos de erro e `Idempotency-Key` quando aplicável.
* [ ] **Testes**: unitários (models/services), requests (Grape), canais (Action Cable), jobs (Sidekiq). Cobertura **≥ 90%** (SimpleCov) e sem `pending`.
* [ ] **Segurança**: params validados (Grape), autenticação/escopos checados, CORS restrito, verificação de assinatura em webhooks (Evolution/Asaas).
* [ ] **Perf**: sem N+1 (Bullet), índices/migrações reversíveis, latência média do endpoint **< 250ms** em dev/profile.
* [ ] **Erros padronizados**: envelope `errors[]` e mapeamento HTTP correto; logs com `request_id`.
* [ ] **Mensageria**: jobs idempotentes e reentrantes; DLQ/retentativas configuradas.
* [ ] **Qualidade**: `rubocop` sem offenses; `brakeman` e `bundler-audit` limpos.

### 10.2 Frontend

* [ ] **Tipagem**: sem `any` não justificado; `tsc --noEmit` sem erros.
* [ ] **UX/Estados**: loading, empty, error e sucesso cobertos; toasts padronizados.
* [ ] **A11y**: navegação por teclado, labels/ARIA, contraste AA; foco visível.
* [ ] **Temas**: dark/light completos, tokens aplicados e persistência do tema.
* [ ] **Tests**: unit (components/hooks) e integração de páginas (React Testing Library/Vitest) verdes.
* [ ] **Performance**: orçamento de bundle `≤ 250KB` (gzip) por rota inicial; imagens otimizadas.

### 10.3 Realtime

* [ ] Canais protegidos por JWT/roles; reconexão exponencial; unsub em unmount.
* [ ] Eventos versionados, payloads tipados e tratados (retry/backoff) no cliente.

### 10.4 Operação & Release

* [ ] **README** atualizado com uso/variáveis/migrações.
* [ ] **Feature flag**/kill-switch se risco alto.
* [ ] **Plano de migração/rollback** verificado (dry run). Migrations **reversíveis**.
* [ ] **Pipeline CI** verde (lint + testes + segurança) e artefatos publicados.
