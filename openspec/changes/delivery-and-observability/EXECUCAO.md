# EXECUCAO — delivery-and-observability (Onda D11)

Mapa de execução. Escrito ANTES de qualquer código (commit G0). RETOMADA no fim.

## Ponto de partida

A infraestrutura que TODO o domínio assume mas ninguém provisiona: split de
processos (web/worker/release), isolamento de Redis (cache×fila×cable),
observabilidade (Sentry, log estruturado, métricas), canal de alerta, ciclo de
vida de dado (partição + retenção), rate limit compartilhado e o runbook de
rollback. É o keystone que destrava os handoffs acumulados (`realtime` 3.4
multi-processo, `offline-pwa` 2.4 header do `/sw.js`, `workspace-settings` 5.10) e
o gate declarado do primeiro deploy de produção.

## RECONCILIAÇÃO COM A REALIDADE (crítico — ler antes de codar)

O repo já EVOLUIU além do que várias tarefas assumem. Registrar o que está feito
evita refazer e evita marcar como "novo" o que já existe.

- **`database.yml` JÁ ESTÁ convertido (1.3 quase pronta):** `default`+`development`+
  `test`+`production` usam `url:` via `DATABASE_URL`; produção com fallback `nil`
  (levanta em vez de assumir). SEM `password:` literal, SEM `robotrack_user`/
  `silas777`. FALTA: ajustar `create_dev_db.sh` para ler a URL e o spec-guarda que
  falha em qualquer `password:` literal.
- **`cable.yml` já tem `channel_prefix`** (`robotrack_development`/`_production`) —
  parte de 3.2 pronta. FALTA o isolamento de URL (hoje cai em `REDIS_URL`) e o
  guarda de topologia.
- **`rack-attack` já usa Redis quando disponível** (store cross-processo, cai para
  memória sem serviço) — 7.1 parcialmente pronta. FALTA apontar para
  `REDIS_CACHE_URL` nominal, a chave por identidade (7.2) e os limites por classe
  (7.3).
- **`filter_parameter_logging`** filtra `passw/secret/token/_key/crypt/salt/otp/
  ssn`. `token` (substring) já cobre `invitation_token`/`refresh_token`; FALTA
  `authorization` explícito (não contém "token") — 4.3.
- **`Dockerfile` backend-prod tem `assets:precompile`** (app é API-only → remover),
  roda como root (sem `USER`), sem `HEALTHCHECK` — 2.1 é conserto, não criação.
- **`docker-compose.yml` existe** (dev: postgres+redis+backend+frontend). FALTA o
  `docker-compose.staging.yml` sobre a imagem de produção (2.4).
- **`/api/v1/health` existe** (offline-pwa 4.3) — é a sonda leve de fila. Os
  `/health/live` e `/health/ready` de 2.3 são OUTRA coisa (liveness/readiness de
  orquestrador, com checagem de PG/Redis/migrations). Adicionar SEM colidir.
- **Redis: instalado, NÃO rodando.** `redis-server` disponível; subir para os
  specs que precisam (dedup do AlertService, store do rack-attack, topologia).
- **NÃO EXISTEM:** `Procfile`, `bin/release`, `lograge.rb`, `env_schema.rb`,
  Sentry (gem ausente), `/metrics`, `Ops::AlertService`, partição de `audit_logs`,
  jobs de retenção/expurgo, guarda de migration `contract`.

## O que roda AQUI vs o que é HANDOFF de deploy

Padrão da casa (igual a Playwright do realtime): entregar código+config+spec
testável; verificações que exigem deploy real viram HANDOFF documentado.

- **Roda aqui (contra PG+Redis local):** guarda de `env_schema`, spec de
  `database.yml` sem senha, `/health/live`+`/ready`, guarda de topologia de Redis,
  spec de lograge JSON, `/metrics` com token, dedup do AlertService (relógio
  congelado + Redis), permissão de retenção (REVOKE), scan de migration
  `contract`, 429 por classe, conformidade do DDL de partição.
- **HANDOFF de deploy (sem alvo real no container):** smoke do
  `docker-compose.staging` (2.4), headers de CDN + broadcast multi-processo
  (3.3/3.4 smoke), ingestão real do Sentry (instalo gem+config+scrubbing testável;
  o envio real é do deploy), ensaio de rollback em staging (8.4), restore do
  backup verificado num banco descartável (8.3 — dá para exercitar local com um
  2º banco; o RPO datado é do deploy).

## Ordem dos grupos (mapa)

| Grupo | Escopo | Tarefas |
|---|---|---|
| **G1** | Config e banco: `env_schema.rb` + guarda de boot; rake `.env.example` dos 3 arquivos; `create_dev_db.sh` por URL + spec sem-senha | 1.1–1.4 |
| **G2** | Imagem/processos/saúde: `Dockerfile` backend-prod (sem assets, não-root, HEALTHCHECK); `Procfile`+`bin/release` (migrate sob lock); `/health/live`+`/ready`; `docker-compose.staging` + smoke (HANDOFF do smoke) | 2.1–2.4 |
| **G3** | Redis/Cable/CDN: isolamento `CACHE`/`QUEUE`/`CABLE` + guarda de topologia; contrato de cache do bundle (`no-store`/`immutable`); smoke de header + broadcast multi-processo (HANDOFF) | 3.1–3.4 |
| **G4** | Observabilidade: Sentry server (scrubbing/PII/contexto) + client (release/sourcemaps); lograge JSON; `/metrics` por `METRICS_TOKEN`; scan sem `ExceptionNotifier` | 4.1–4.5 |
| **G5** | Canal de alerta: `Ops::AlertService` (dedup `SET NX EX`, roteamento por severidade, blindagem de destino), condições operacionais, contrato de `key` (D5/D7/convites) | 5.1–5.4 |
| **G6** | Ciclo de vida de dado: partição de `audit_logs` (DDL de referência + conformidade), job de folga de partição, export+DETACH/DROP com retenção 24m, expurgos em lote, spec de permissão de retenção | 6.1–6.6 |
| **G7** | Rate limit de domínio: store Redis nominal, chave por `user_id` do JWT, limites por classe via ENV, 429 com `Retry-After`+corpo pt-BR e não-poison na fila offline | 7.1–7.4 |
| **G8** | Rollback e prova: runbook (3 degraus), scan de migration `contract`, backup verificado (restore+contagem), ensaio de rollback (HANDOFF staging) | 8.1–8.4 |

## Armadilhas previstas

- **`/health/*` × `/api/v1/health`:** são coisas distintas. `/health/live` e
  `/ready` são de orquestrador (fora do Grape? rota Rails direta), públicas, sem
  `X-Skip-Auth`. Não colidir com a sonda de fila offline nem com a allowlist.
- **Redis não roda por padrão:** specs que dependem dele sobem `redis-server`
  antes; os que caem para memória (rack-attack) testam o fallback também.
- **`env_schema` guard × ambiente de teste:** o boot-abort é só em `staging`/
  `production`. Ligar em `test` derrubaria toda a suíte — o guarda checa `Rails.env`.
- **Migration `contract` scan:** roda sobre `db/migrate` inteiro; as migrations
  legadas do template sem marcador não podem reprovar retroativamente — o scan
  cobre `remove_column`/`drop_table`/`change_column`/`rename_column` e ancora a
  exigência do marcador a partir de agora (documentar a linha de corte).
- **Partição de `audit_logs`:** `audit-log` (Onda 6) ainda pode não ter a tabela
  particionada; 6.1 entrega a migration de REFERÊNCIA + spec de conformidade do
  DDL que aquela onda precisa satisfazer, não a reescrita da tabela viva.

## Baseline

Backend verde (health/governança 277/0 no fecho de offline-pwa). `database.yml`
já em `DATABASE_URL`; `cable.yml` com `channel_prefix`; `rack-attack` já
Redis-quando-disponível. Sem Procfile/bin/release/lograge/Sentry/metrics/alerta/
partição/retenção.

## FECHAMENTO — handoffs de deploy (o que precisa de um alvo real)

Toda a LÓGICA + CONFIG + SPEC estão entregues e testadas contra PG+Redis local. O
que exige um alvo de deploy real fica registrado aqui (padrão da casa — como o
Playwright do realtime):

- **Smoke do `docker-compose.staging`** (2.4) e **broadcast multi-processo**
  (3.4): daemon Docker + 2 web. Artefatos entregues (`docker-compose.staging.yml`,
  `scripts/staging_smoke.sh`).
- **Headers de cache contra o CDN publicado** (3.3): conformidade do `nginx.conf`
  testada aqui; o header no CDN é do provedor.
- **Ingestão real do Sentry** (DSN) e **upload de source maps no CI** (4.1/4.2):
  scrubbing/config/release testados; o envio é do deploy.
- **Coleta de métricas + janelas sustentadas** do alerta (5.3): a lógica das
  condições é testada sobre um snapshot; o coletor é monitoramento de deploy.
- **Object storage do export de partição** (6.3) e **DDL de partição sob papel de
  manutenção** (6.2/6.4): SQL/lógica entregues; a execução privilegiada é de deploy.
- **Ensaio de rollback em staging** (8.4): o runbook (`docs/runbooks/rollback.md`)
  e os guards (`db:rollback` recusa contract; `bin/release` exige backup verificado)
  estão entregues; o ensaio datado é pré-requisito do primeiro deploy de produção.

## RETOMADA

Ler este arquivo + design.md. Estado por grupo em tasks.md (`- [x]`). Protocolo
por grupo: aplicar → specs dirigidos 0 falhas (subir `redis-server` quando
preciso) → marcar tasks → `npx --yes @fission-ai/openspec@1.6.0 validate
delivery-and-observability --strict` → UM commit `G<n>:` → fast-forward `main` +
push → resumo pt-BR client-friendly → seguir. Verificações de deploy real viram
HANDOFF documentado no fim (como Playwright do realtime).
