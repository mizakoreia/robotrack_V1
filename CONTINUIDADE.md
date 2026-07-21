# Continuidade — estado em 21/07/2026

Ponto de retomada do porte. Para uma sessão nova de agente, o prompt de partida
está em [PROMPT DE RETOMADA](#prompt-de-retomada), no fim.

## Onde está o trabalho

**As branches são empilhadas, não independentes:**

```
main (48497fd)                       ← ondas 1–4, sem nada desta sessão
└── authorization-policies (6b89283)     change COMPLETA
    └── commissioning-hierarchy (b75b072)  change COMPLETA
        └── task-catalog (3d261ac)         5 de 6 grupos (falta só TC-G6, o sync)
            └── robot-tasks (e78d05b)      change COMPLETA — 6 de 6 grupos
```

**`robot-tasks` contém todo o trabalho** (empilhada sobre `task-catalog`). É nela
que se continua. Push é por branch canônica da change (`git push origin
HEAD:robot-tasks`). Os PRs para a `main` podem ser abertos depois, na ordem do
empilhamento.

## Suítes (medidas na branch `robot-tasks`)

| Suíte | Resultado |
|---|---|
| Backend `bundle exec rspec` (como `robotrack_app`) | **801 / 0 falhas / 10 pending** |
| Frontend `vitest run` | **88 / 0** |
| Frontend `tsc --noEmit` | limpo |

Todos os 10 pending nomeiam a capacidade que os desbloqueia — nenhum é dívida
anônima. (Dois pendings de cascade — `tasks→robots` e `task_assignees→tasks` —
destravaram e viraram verdes ao longo de `robot-tasks`.)

> Nota de ambiente: `spec/requests/auth/rate_limit_spec.rb` é levemente FLAKY na
> suíte completa (estado do Rack::Attack sensível à ordem aleatória do RSpec);
> passa isolado. Não é regressão desta sessão. Rodar com `--seed` fixo estabiliza.

## Changes concluídas (8 de 24; task-catalog em 5/6)

`seal-template-baseline`, `workspace-tenancy`, `identity-and-auth`,
`workspace-invitations` (anteriores) e:

- **`authorization-policies`** (G0..G6) — matriz §4.1 como dado, `Authorization::Context`
  (papel resolvido só no servidor), `BasePolicy` singleton + 12 policies, gate fail-closed
  no `before` de `Api::Root` (rota sem `route_setting :policy` nunca responde 200),
  contrato 401/403/404 sem vazamento, allowlist pública em YAML, route-sweep de 100% das
  rotas, 8 invariantes executáveis, varredura cross-tenant gerada, paridade 22/22 com o
  `firestore.rules` legado, guarda estático anti `role ==`, job de CI dedicado.
- **`commissioning-hierarchy`** (G0..G6) — `projects`/`cells`/`robots` com PK uuid gerável
  no cliente, FK composta `(pai_id, workspace_id)`, RLS forçada, `position` DEFERRABLE,
  `progress_cache` desde a origem, CRUD idempotente (201/200/409/404), reordenação em lote
  com advisory lock, e o cliente (hooks React Query, `newId()`, handler de drag & drop).
  Sem telas — `hierarchy-screens` é outra change.
- **`robot-tasks`** (G0..G6, COMPLETA) — a Tarefa como esquema relacional (`tasks` com enum
  `task_status`, CHECK 0–100, FK composta com CASCADE, RLS, índice único
  `(robot_id, lower(btrim(desc)))`), `task_assignees` por `person_id` (FKs compostas, sem
  `resp`, sem `"Não Atribuído"`), CRUD de tarefa (409 por id/versão, PATCH rejeita
  `progress`/`status`), atribuição por PUT de conjunto com diff + evento, e criação de robôs
  em lote §2.5 (normalizer clamp/dedup, transação única com `insert_all`, materialização das
  tarefas-base filtradas pela Aplicação, assistente de 2 passos). Benchmark da leva máxima
  (1550 linhas ~185 ms), fronteira provando que `progress-advances` NÃO foi antecipado, e
  handoff a `legacy-data-migration`. Decisões de execução 1/7/8/9 no EXECUCAO.
- **`task-catalog`** (G0..G5 de 6) — catálogo `task_templates` (CHECK de domínio, unicidade
  por `desc` normalizada, RLS), `ApplicabilityFilter` Ruby+SQL, seed dos 31 padrões na
  transação do bootstrap, CRUD + `GET /meta/robot_applications`, e o cliente TS. **Falta só
  o TC-G6** (sync retroativo §2.6), que estava bloqueado pela tabela `tasks` — agora
  destravado por `robot-tasks`.

Cada change tem seu `openspec/changes/<nome>/EXECUCAO.md` com o mapa de grupos, as
decisões tomadas na execução, as armadilhas encontradas e a CONCLUSÃO com o relatório
final. **Leia o EXECUCAO.md antes de tocar no código de uma change.**

## Onde parou: `robot-tasks` completa; `TC-G6` destravado

`robot-tasks` fechou (6/6 grupos) — ver `openspec/changes/robot-tasks/EXECUCAO.md`
(CONCLUSÃO + decisões 1/7/8/9). Com isso a tabela `tasks` e o índice
`(robot_id, lower(btrim(desc)))` existem.

**Próximo passo — TC-G6** (task-catalog, tarefas 5.1–5.7, sincronização retroativa §2.6),
agora **DESTRAVADO**. Entrega, na branch `robot-tasks` (que já contém `task-catalog`
empilhado):

- `TaskTemplates::SyncToRobotService.call(robot:, actor:)` — `SELECT ... FOR UPDATE` na
  linha do robô, seleção dos templates aplicáveis por `ApplicabilityFilter.scope_for`, diff
  por `lower(btrim(desc))` contra as tarefas do robô, `insert_all` **só das faltantes** com
  `progress: 0`, `status: "Pendente"`, sem responsável, `position` continuando a maior atual
  (NUNCA upsert — zeraria progresso). Retorno `{ added_count: N }` (linhas inseridas, não o
  tamanho do conjunto aplicável).
- Endpoint `POST /api/v1/robots/:id/sync_task_templates` com `TaskTemplatePolicy.sync?` (já
  existe) — entra no route-sweep e no gerador cross-tenant no mesmo grupo.
- Specs: aplicabilidade concreta (Solda MIG não recebe `Calibração de Cola`; Sealing recebe;
  Handling recebe `Check sinais de Gripper`), não-sobrescrita (tarefa em progresso 100 com
  responsável permanece; `"tcp check "` não duplica `"TCP Check"`), e concorrência (duas
  syncs simultâneas do mesmo robô partindo de zero terminam com exatamente as N tarefas, a
  2ª informa `0`) — o índice único `(robot_id, lower(btrim(desc)))` é o backstop.
- O cliente já está pronto (task-catalog G5): `hierarchyApi.syncRobotTaskTemplates` +
  `useSyncTaskTemplates`. Fechar o e2e cross-sistema que o TC-G5 deixou no nível do cliente.

Ao fim, task-catalog vira 6/6 e a CONCLUSÃO do EXECUCAO dela é atualizada.

## Depois de `TC-G6`

`progress-advances` (a máquina de estados progresso↔status §2.2, o modal de avanço §2.4, a
auto-atribuição §2.3 e `task_advances` — que `robot-tasks` deliberadamente deixou de fora) e
`progress-rollup` (o `progress_cache` consolidado). Para ter telas de verdade:
`design-system` + `app-shell-navigation` + `hierarchy-screens` + `robot-task-table` (hoje a
UI é a landing do template + autenticação + painel de equipe + os hooks/lógica sem tela
final).

## Método (não abrir mão)

1. Uma change por vez, cada uma na sua branch, empilhada na anterior.
2. **Antes de qualquer código**, escrever `openspec/changes/<change>/EXECUCAO.md` com o
   mapa de grupos, decisões próprias, armadilhas previstas e seção RETOMADA — commit `G0`.
3. Executar grupo a grupo. Por grupo: aplicar → `bundle exec rspec` (0 falhas) → marcar
   `- [x]` em `tasks.md` → `npx --yes @fission-ai/openspec@1.6.0 validate <change>
   --strict` → **um commit** `G<n>: ...`.
4. Ao fim de cada grupo: resumir e **pedir autorização antes do próximo**.
5. Divergência entre o design e a realidade (ou entre duas changes): decidir, **registrar
   a decisão com o motivo** no EXECUCAO.md e anotar no `tasks.md`. Nunca em silêncio.
6. `pending` sempre nomeia a capacidade bloqueadora; nada de spec pendente fingindo
   cobertura de código que não existe.

## Regras que não podem regredir

- A aplicação conecta ao Postgres como `robotrack_app` — **sem SUPERUSER e sem
  BYPASSRLS** (inclusive nos seeds).
- Isolamento entre workspaces é **Row Level Security forçada**, não convenção de código.
- As invariantes moram no banco (trigger, constraint, índice único), não só no model.
- Vazamento entre tenants responde **404**, nunca 403 — corpo byte-idêntico ao de um id
  inexistente.
- As varreduras (autenticação, tenant, route-sweep de policy, cross-tenant) **só crescem**:
  rota nova nasce declarando policy e entrando no gerador cross-tenant no mesmo grupo.
- O repositório legado `mizakoreia/RoboTrack` é **somente referência de leitura** — nenhum
  arquivo dele entra neste repositório.

## Ambiente de desenvolvimento

Migrations rodam como `robotrack_migrator`; a suíte roda como `robotrack_app`. Detalhes em
[backend/db/PROVISIONING.md](backend/db/PROVISIONING.md):

```bash
cd backend
MIG_DEV="postgres://robotrack_migrator:mig_dev_pw@localhost/robotrack_dev"
MIG_TEST="postgres://robotrack_migrator:mig_dev_pw@localhost/robotrack_test"
RAILS_ENV=development DATABASE_URL=$MIG_DEV  bundle exec rails db:migrate
RAILS_ENV=test        DATABASE_URL=$MIG_TEST bundle exec rails db:migrate
bundle exec rspec

cd ../frontend
./node_modules/.bin/vitest run && ./node_modules/.bin/tsc --noEmit
```

O frontend usa **pnpm** (`pnpm-lock.yaml`); o `package-lock.json` está dessincronizado —
`npm ci` falha. Seed de demonstração da hierarquia:
`RAILS_ENV=development bundle exec rails runner db/seeds/hierarchy_demo.rb`.

## PROMPT DE RETOMADA

> Estou continuando o desenvolvimento do RoboTrack (github.com/mizakoreia/robotrack_V1):
> reimplementação de um sistema legado (PWA + Firestore) sobre um template Rails 8
> API-only + React 18/TS, organizada com OpenSpec — 24 changes em `openspec/changes/`,
> cada uma com proposta, design, deltas de spec e tarefas.
>
> Leia `CONTINUIDADE.md` na raiz do repositório: ele tem o estado atual, o que já foi
> entregue, onde parei e o método de trabalho. Depois leia
> `openspec/changes/robot-tasks/EXECUCAO.md` (change COMPLETA) e
> `openspec/changes/task-catalog/EXECUCAO.md` (falta só o TC-G6, o sync retroativo).
>
> Trabalhe na branch `robot-tasks` (as branches são empilhadas; ela contém tudo, inclusive
> `task-catalog`). O próximo passo é o grupo **TC-G6** (sincronização retroativa §2.6 de
> task-catalog), agora destravado porque `robot-tasks` criou a tabela `tasks` e o índice
> `(robot_id, lower(btrim(desc)))` — descrito no CONTINUIDADE.md e nas tarefas 5.1–5.7 de
> task-catalog. Push por branch canônica (`git push origin HEAD:robot-tasks`).
>
> Siga o método: um grupo por vez, e ao fim de cada grupo me apresente um resumo e peça
> autorização antes de seguir para o próximo. Não regrida nenhuma das regras listadas na
> seção "Regras que não podem regredir".
