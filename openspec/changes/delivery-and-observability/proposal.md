## Why

O WBS anterior tinha um bloco intitulado "Qualidade, acessibilidade e entrega" com
**zero tarefas de entrega e zero de observabilidade**. O resultado é um plano em que
todo o domínio depende de infraestrutura que ninguém provisiona:

- **D6** (`realtime-collaboration`) exige "adapter Redis obrigatório em produção" para o
  `WorkspaceChannel`. Nenhuma tarefa criava o Redis, separava o banco lógico do Cable do
  banco do Sidekiq, nem definia `channel_prefix`. Hoje `backend/config/cable.yml`,
  `backend/config/initializers/sidekiq.rb` e `config.cache_store` em
  `backend/config/environments/production.rb` apontam **todos para `redis://…/1`** — a
  mesma instância e o mesmo banco lógico. Um `maxmemory-policy` de cache evicta jobs
  enfileirados e mensagens de Cable.
- **D5** (`progress-rollup`) especifica um job de reconciliação que compara
  `progress_cache` contra o cálculo em SQL e **"alerta divergência"**. Não existia canal
  de alerta nenhum no plano. Este change entrega o canal.
- `backend/config/database.yml` **não tem seção `production`** e traz usuário e senha de
  desenvolvimento em texto plano no repositório. Um deploy hoje não sobe.
- O template chama `ExceptionNotifier` em todo `rescue_from` sem a gem no Gemfile.
  `seal-template-baseline` remove a chamada quebrada; **o substituto é responsabilidade
  deste change** — sem ele, o resultado líquido do seal é "erros somem em silêncio".
- `audit_logs`, `notifications` e `login_codes` crescem sem limite e nada os expurga.
  `audit-log` (§2.8, §4.1 inv. 3) declara "200 mais recentes na exibição **+ política de
  retenção no armazenamento**" — a exibição é dela, o armazenamento é deste change.
  Complica: **D12** dá `REVOKE UPDATE, DELETE` em `audit_logs`, então a retenção não pode
  ser um `DELETE`.
- `rack-attack` protege só `/api/v1/auth/login` (um path que **D4 elimina**) e usa
  `ActiveSupport::Cache::MemoryStore` — contador por processo Puma, ou seja, o limite
  real é `limite × nº de processos`. Endpoints de domínio não têm limite algum; a
  criação em lote de robôs (1–50, `robot-tasks`) e a fila de mutations offline (**D7**)
  são amplificadores de escrita óbvios.
- Cada capacidade introduz variáveis de ambiente e nenhum lugar as registra. O
  `backend/.env.example` atual ainda descreve Asaas e WhatsApp/Evolution — integrações
  que `seal-template-baseline` remove.

## What Changes

- **Ambientes.** Três ambientes nomeados (`development`, `staging`, `production`) com
  paridade de esquema e de serviços. `database.yml` passa a derivar de `DATABASE_URL`;
  credenciais saem do repositório. `staging` roda a mesma imagem de `production`.
- **Imagem e execução.** Estágio de produção do `Dockerfile` corrigido (hoje roda
  `assets:precompile` numa app API-only, roda como root e não tem healthcheck).
  Processos separados e escaláveis independentemente: `web` (Puma), `worker` (Sidekiq),
  `cable` (opcionalmente in-process no `web`), `release` (migrations).
- **Migrations em produção.** Fase de release separada do boot da app, regra
  **expand/contract** obrigatória para toda migration que toca coluna existente,
  `statement_timeout` e `lock_timeout` na conexão de migration, e backup verificado
  imediatamente antes de qualquer migration destrutiva.
- **Rollback.** Runbook executável: rollback de código (imagem anterior), rollback de
  schema (só o que expand/contract torna reversível) e critério explícito de "ponto sem
  volta".
- **Provisionamento das dependências que outras capacidades assumem**: Redis com três
  bancos lógicos de políticas distintas (cache evictável / Sidekiq durável / Cable),
  `channel_prefix` do ActionCable por ambiente, e hospedagem estática do bundle React com
  CDN e regras de cache compatíveis com o service worker de **D7** (`index.html`
  no-store, assets com hash `immutable`).
- **Observabilidade.** Rastreio de erro (Sentry) no Rails, no Sidekiq e no React;
  logs estruturados JSON (lograge) com `request_id`, `workspace_id`, `person_id` e
  **sem PII no corpo**; métricas de negócio e de infra expostas em `/metrics`;
  endpoints `/health/live` e `/health/ready`.
- **Alertas.** Um serviço único `Ops::AlertService` com severidades e destino
  configurável, usado por qualquer capacidade que precise alertar — inclusive o job de
  reconciliação de **D5**, o poison message da fila offline (**D7**) e falha de entrega
  de e-mail de convite (`workspace-invitations`).
- **Ciclo de vida de dado.** Política de retenção por tabela e o job que a executa.
  `audit_logs` vira **particionada por mês**; a retenção descarta partição inteira
  (`DROP TABLE`), o que respeita `REVOKE UPDATE, DELETE` sem abrir exceção ao job.
  `notifications` e `login_codes` são expurgados por `DELETE` em lotes.
- **Rate limiting de domínio.** `rack-attack` migrado para store Redis compartilhado,
  identidade de throttle por `user_id` (não só IP, que colapsa atrás de NAT de fábrica),
  e limites específicos para escrita de domínio, criação em lote e drenagem de fila
  offline.
- **Orçamento de config.** Registro único e tipado de toda variável de ambiente, com
  **fail-fast no boot** quando uma obrigatória falta, e `.env.example` regenerado a
  partir dele.

### Não-objetivos

- **Não** escolhe provedor de nuvem específico nem escreve Terraform/Kubernetes. Os
  requisitos são expressos em termos de contrato (processos, variáveis, endpoints de
  saúde) para caber em Fly.io, Render, ECS ou VM com Compose.
- **Não** implementa CI de teste, E2E, orçamento de performance ou auditoria a11y — isso
  é `quality-and-accessibility`. Este change só define o *gate de deploy* que consome o
  resultado do CI.
- **Não** implementa o job de reconciliação de D5 nem o formato do log de auditoria —
  entrega o **canal de alerta** e o **substrato de retenção**; o conteúdo é de
  `progress-rollup` e `audit-log`.
- **Não** remove Asaas/WhatsApp/`ExceptionNotifier` do código — isso é
  `seal-template-baseline`. Aqui só o `.env.example` é reescrito.
- **Não** faz APM de traço distribuído nem log de auditoria de infraestrutura (SOC2).
- **Não** define retenção de backup de banco além de "existe, é testado e tem RPO
  declarado".

### Impact

- Novos arquivos de infra: `Dockerfile` (estágio prod), `docker-compose.staging.yml`,
  `Procfile`, `bin/release`, `backend/config/initializers/{sentry,lograge,rack_attack}.rb`,
  `backend/config/env_schema.rb`, `backend/app/services/ops/alert_service.rb`,
  `backend/app/jobs/retention/*`.
- **BREAKING** — `backend/config/database.yml`: credenciais literais substituídas por
  `DATABASE_URL`. Quem roda o repo hoje sem `.env` perde a conexão até rodar
  `create_dev_db.sh` e exportar a URL.
- **BREAKING** — Redis: `REDIS_URL` sozinho deixa de ser suficiente. Passam a existir
  `REDIS_CACHE_URL`, `REDIS_QUEUE_URL`, `REDIS_CABLE_URL`. O boot falha se apontarem para
  o mesmo banco lógico em produção.
- **BREAKING** — boot em `production`/`staging` falha se qualquer variável obrigatória do
  registro estiver ausente. Deploys que hoje subiriam com default silencioso passam a
  parar na fase de release.
- Dependência de todas as capacidades: quem introduzir variável de ambiente **deve**
  registrá-la em `env_schema.rb`; quem precisar alertar **deve** usar `Ops::AlertService`.

## Capabilities

### New Capabilities

- `deployment-environments`: ambientes, imagem de produção, topologia de processos,
  provisionamento de Redis/Cable/CDN, migrations em produção, rollback e registro de
  configuração.
- `observability-and-alerting`: rastreio de erro, log estruturado, métricas, health
  checks e canal único de alerta.
- `data-retention-and-rate-limiting`: retenção e expurgo por tabela (incluindo
  `audit_logs` particionada sob D12) e limitação de taxa dos endpoints de domínio.

### Modified Capabilities

Nenhuma. `openspec/specs/` está vazio: nada foi construído ainda.
