# Validação na WSL — o que só a WSL fecha

Este container remoto NÃO tem Docker daemon nem Playwright, então vários itens
foram entregues como **código + config + spec de integração**, com a execução real
marcada como HANDOFF. A WSL (com Docker Desktop + navegador) é onde esses handoffs
se fecham. Este arquivo é o roteiro.

> Estado de referência: `main` = `1b9be98` (23/07/2026). 22 de 24 changes completas.
> Assinatura de commit é impossível no container (sem chave) — os commits saem
> "Unverified"; é ambiental, não é problema de conteúdo.

---

## 0. Pegar a versão mais atual

```bash
# clone novo
git clone https://github.com/mizakoreia/robotrack_V1.git
cd robotrack_V1

# OU, se já tem o repo:
git fetch origin
git checkout main
git pull --ff-only origin main
git log --oneline -1        # deve mostrar 1b9be98 (ou mais recente)
```

`main` É a versão mais atual (não há mais empilhamento de branches).

---

## 1. Pré-requisitos na WSL

- **Ruby 3.2.3** (rbenv): `rbenv install 3.2.3 && rbenv local 3.2.3`.
- **Node 20+** e **npm** (o frontend usa npm, NÃO pnpm).
- **PostgreSQL 16** rodando.
- **Redis 7** rodando (`sudo service redis-server start`).
- **Docker Desktop com integração WSL2** (para os itens de deploy).

---

## 2. Setup

### Banco (ver `backend/db/PROVISIONING.md` para o detalhe)

```bash
# como superusuário postgres: cria os papéis robotrack_migrator/robotrack_app
# (SEM superuser, SEM bypassrls) e os bancos, depois aplica roles.sql nos dois.
cd backend
psql -U postgres -f db/roles.sql            # cria papéis + grants (idempotente)
# crie robotrack_dev e robotrack_test se ainda não existirem (owner robotrack_migrator)

MIG_DEV="postgres://robotrack_migrator:mig_dev_pw@localhost/robotrack_dev"
MIG_TEST="postgres://robotrack_migrator:mig_dev_pw@localhost/robotrack_test"
bundle install
RAILS_ENV=development DATABASE_URL=$MIG_DEV  bundle exec rails db:migrate
RAILS_ENV=test        DATABASE_URL=$MIG_TEST bundle exec rails db:migrate
# Se recriar papéis depois, REAPLIQUE db/roles.sql (a recriação apaga grants).
```

### Frontend

```bash
cd ../frontend
npm install
```

---

## 3. Paridade — deve passar igual ao container (confirma que a WSL está sã)

```bash
# BACKEND: a suíte INTEIRA num run só. ATUALIZAÇÃO: o container remoto AGORA roda a
# suíte inteira (ruby 3.2.3 + gems prontos) — resultado de referência ATUAL 1443/0,
# 9 pending (era 1382/0 antes da migração legada, que somou +56 specs em spec/legacy),
# com raise_on_missing_translations ligado e Redis no ar. Rode aqui pra confirmar paridade.
cd backend
export PATH="$(rbenv root)/versions/3.2.3/bin:$PATH"   # ou rbenv shims
RAILS_ENV=test bundle exec rspec        # roda como robotrack_app; esperado: verde
# ^ os benchmarks `:slow` (progress/load_dataset = 93k tasks, my_tasks & reports
#   load_perf) NÃO entram nesse run — ficam de fora por padrão. Isso é de propósito:
#   são orçamentos de latência sensíveis a tuning do Postgres, não teste de paridade.
#   Para rodá-los EXPLICITAMENTE (ver §4.6): SLOW=1 bundle exec rspec --tag slow

# FRONTEND
cd ../frontend
npm run lint && npx tsc --noEmit && npx vitest run     # esperado: 527/0, tsc+lint limpos
npm run build                                          # esperado: build limpo (emite sourcemaps)
```

Se algo aqui falhar, é problema de setup da WSL (versão de gem/node, banco), não do
código — me mande o erro.

---

## 4. Os HANDOFFS — o que SÓ a WSL valida

### 4.1 Imagem de produção + smoke de staging (delivery-and-observability 2.x/3.x)

Prova: a imagem prod builda, roda como não-root, tem HEALTHCHECK, o `bin/release`
migra sob lock, os processos web/worker sobem e `/health/ready` responde 200.

```bash
cd robotrack_V1   # raiz (onde estão Dockerfile e docker-compose.staging.yml)

# build só da imagem backend de produção (sem assets:precompile, usuário app):
docker build --target backend-prod -t robotrack-backend-prod .
docker run --rm robotrack-backend-prod whoami        # deve imprimir "app", não root

# smoke completo da stack de staging (Postgres+Redis+release+web+worker):
bash scripts/staging_smoke.sh
# esperado no fim: "[smoke] OK: /health/ready = 200"
# (ele sobe, roda bin/release, espera o web ficar healthy e afirma 200)
```

Se o smoke reprovar, os logs saem no fim (`docker compose logs web release`).

### 4.2 Service worker num navegador REAL (offline-pwa G2)

O SW só registra em produção. Aqui você vê o network-first, a purga de cache e o
aviso de nova versão de verdade.

```bash
cd frontend
npm run build
npx vite preview --port 4173   # serve o dist/ (produção)
```

No Chrome, abra `http://localhost:4173`:
- DevTools → Application → Service Workers: deve haver um SW ativo (`sw.js`).
- DevTools → Network → marque **Offline** → recarregue uma rota (`/robo/...`):
  a navegação deve responder do shell (200), não a tela do dinossauro.
- Application → Cache Storage: deve haver `robotrack-cache-<hash>`.
- Rebuild com uma mudança + preview de novo → deve aparecer o aviso "Nova versão".

### 4.3 Headers de cache do nginx (delivery-and-observability 3.3)

O `frontend/nginx.conf` é a config do bundle no CDN. Rode um nginx local com ela:

```bash
docker run --rm -p 8080:80 \
  -v "$PWD/frontend/nginx.conf:/etc/nginx/nginx.conf:ro" \
  -v "$PWD/frontend/dist:/usr/share/nginx/html:ro" \
  nginx:alpine

curl -sI http://localhost:8080/sw.js        | grep -i cache-control   # no-store
curl -sI http://localhost:8080/index.html   | grep -i cache-control   # no-store
curl -sI http://localhost:8080/assets/<algum-hash>.js | grep -i cache-control  # immutable, 1 ano
```

### 4.4 Isolamento de Redis por função + guarda de topologia (delivery-and-observability 3.x)

Suba 3 instâncias/dbs de Redis e prove que o guarda de boot aborta quando duas
funções colidem:

```bash
# guarda deve ABORTAR o boot em produção quando cache e fila apontam para o mesmo lugar:
cd backend
RAILS_ENV=production \
  DATABASE_URL=$MIG_DEV SECRET_KEY_BASE=x ACTION_CABLE_URL=ws://x CORS_ORIGINS=http://x \
  REDIS_CACHE_URL=redis://localhost:6379/1 \
  REDIS_QUEUE_URL=redis://localhost:6379/1 \
  REDIS_CABLE_URL=redis://localhost:6379/3 \
  METRICS_TOKEN=x \
  bundle exec rails runner 'puts "NÃO deveria chegar aqui"'
# esperado: "[boot abortado] topologia de Redis insegura ... resolvem para o mesmo (host, porta, db)"
```

### 4.5 Broadcast multi-processo do ActionCable (realtime 3.4 / delivery 3.4)

Com Redis de Cable real, dois processos `web` e um cliente conectado em cada:
prova que um broadcast originado no processo B chega ao cliente conectado no A.
(É a versão real do que os specs cobrem em processo único.) Roteiro no
`openspec/changes/delivery-and-observability/EXECUCAO.md` (FECHAMENTO).

### 4.6 Diagnóstico do rollup de progresso (`:slow` — DÚVIDA EM ABERTO)

**Contexto:** o benchmark `spec/progress/load_dataset_spec.rb` (agora fora do run
padrão, roda só com `SLOW=1`) semeia 93k tasks num workspace e afirma que
`Progress::BulkRecompute` fecha em < 20s (alvo de prod p95 ≤ 8s). Na primeira
execução até o fim (na WSL) uma única `UPDATE projects … FROM
project_weighted_progress` rodou **15-17 min**. Preciso saber se é (a) regressão de
plano — RLS `security_invoker` barrando pushdown de predicado nas views agregadas —
ou (b) Postgres da WSL sub-tunado (`work_mem` baixo → a agregação de 3 níveis
derrama pra disco). **Não reescrevi nada às cegas**; o `EXPLAIN` abaixo decide.

```bash
cd backend
export PATH="$(rbenv root)/versions/3.2.3/bin:$PATH"

# 1) Semeia o dataset de 93k tasks UMA vez, COMMITADO (rails runner não abre
#    transação, então as linhas ficam no banco pro EXPLAIN de outra sessão).
#    Usa os mesmos helpers do spec (FactoryBot + make_workspace + Tenant.with).
MIG_TEST="postgres://robotrack_migrator:mig_dev_pw@localhost/robotrack_test"
RAILS_ENV=test DATABASE_URL=$MIG_TEST bundle exec rails runner '
  require "factory_bot"
  FactoryBot.find_definitions
  require "./spec/support/tenancy_helpers"
  require "./spec/support/progress_load_dataset"
  include FactoryBot::Syntax::Methods
  include TenancyHelpers
  include ProgressLoadDataset
  u  = create(:user, name: "Ana Load")
  ws = make_workspace(owner: u)
  in_workspace(ws) { seed_progress_load(ws.id) }   # 20×10×15×31 = 93k tasks
  puts "WORKSPACE_ID=#{ws.id}"
'  # anote o WORKSPACE_ID impresso
#  ^ semeia como robotrack_migrator (dono das linhas); o EXPLAIN abaixo roda como
#    robotrack_app pra pegar a RLS/security_invoker real do runtime.

# 2) EXPLAIN da statement do roll-up de projeto, DENTRO do escopo de tenant
#    (a RLS security_invoker precisa do current_workspace_id setado). Troque
#    <WSID> pelo valor impresso acima. A senha da app é app_dev_pw (db/roles.sql).
psql "postgres://robotrack_app:app_dev_pw@localhost/robotrack_test" <<'SQL'
SET app.current_workspace_id = '<WSID>';
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
UPDATE projects p
SET progress_cache = pwp.value, progress_cached_at = now()
FROM project_weighted_progress pwp
WHERE pwp.project_id = p.id AND p.workspace_id = '<WSID>';
SQL

# 3) Repita o EXPLAIN com work_mem alto pra isolar derrame-pra-disco (causa (b)):
psql "postgres://robotrack_app:app_dev_pw@localhost/robotrack_test" <<'SQL'
SET app.current_workspace_id = '<WSID>';
SET work_mem = '256MB';
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
UPDATE projects p
SET progress_cache = pwp.value, progress_cached_at = now()
FROM project_weighted_progress pwp
WHERE pwp.project_id = p.id AND p.workspace_id = '<WSID>';
SQL
```

O que olhar no plano e me mandar **inteiro**:

- **`Buffers: … temp read/written`** grandes ou `Sort Method: external merge Disk` →
  é derrame por `work_mem` baixo (causa (b), tuning da WSL). Teste rápido:
  `SET work_mem = '256MB';` antes do EXPLAIN e veja se despenca.
- **`Seq Scan on tasks`** re-agregando as 93k linhas por dentro sem o filtro de
  workspace empurrado, ou um nó de agregação processando muito mais linhas do que o
  workspace tem → é (a), pushdown barrado pela view `security_invoker`. Aí o conserto
  é de código (materializar o rollup / forçar o predicado), e eu faço.

Me mande a saída dos dois EXPLAIN (com e sem `work_mem` alto). É o que separa "bug de
query" de "Postgres da WSL apertado" — e eu não consigo rodar isso no container (sem
o dataset e sem daemon).

---

## 5. O que NEM a WSL fecha (precisa de nuvem/serviço real)

- **Sentry real:** ingestão de exceção com scrubbing exige um DSN de projeto Sentry.
  O `before_send`/scrubbing/contexto estão testados em unidade; o envio é do deploy.
- **CDN de produção:** os headers estão no `nginx.conf` (validável no 4.3), mas a
  regressão "por clique no console do provedor" só o smoke pós-deploy pega.
- **Ensaio de rollback em staging** (delivery 8.4): promover→promover→reverter em
  dois deploys reais. O runbook (`backend/docs/runbooks/rollback.md`) e os guards
  (`db:rollback` recusa contract; `bin/release` exige backup) estão prontos.

---

## 6. `quality-and-accessibility` (a wave restante) — NÃO é só rodar

Esta capacidade é o gate de release e o proposal dela declara que NÃO entrega o
pipeline de CI nem o harness Playwright. Os E2E de offline/realtime foram entregues
como INTEGRAÇÃO (RTL/`fake-indexeddb`); a versão Chromium+WebKit precisa do harness
Playwright, que é justamente o que essa wave CONSTRÓI. Ou seja: rodar na WSL não a
completa — ela é trabalho de implementação (com o Playwright que a WSL viabiliza),
não uma validação. `legacy-data-migration` foi construída (36/38) e FECHADA COMO
DORMENTE (o sistema começa do zero, sem dado legado a migrar) — não há corte a rodar
e o `RoboTrack_Database.json` não será fornecido; nada a validar na WSL.

---

## Como me passar os resultados

Rode os blocos e me mande a saída (especialmente 3 e 4). Eu interpreto, e se algo
reprovar por causa do código (não do setup), corrijo aqui e empurro pra `main` —
você dá `git pull` e re-testa.
