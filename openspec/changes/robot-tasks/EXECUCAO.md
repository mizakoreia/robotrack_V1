# EXECUCAO — robot-tasks

Mapa de execução das ~30 tarefas de `tasks.md`, em grupos coerentes, um commit
por grupo. Mesmo método das changes anteriores.

Escrito ANTES de qualquer código. Sessão caiu → **RETOMADA** no fim.

## Ponto de partida

- Branch: `robot-tasks`, empilhada sobre `task-catalog` (`3d261ac`, G5). **Sem
  push até o fim do G0.**
- Baseline: **backend 712 / 0 (12 pending)**, **frontend 80 / 0**, `tsc` limpo.
- Ambiente deste container: Postgres 16 provisionado do zero (papéis
  `robotrack_migrator`/`robotrack_app`, sem SUPERUSER/BYPASSRLS), Ruby 3.2.3 via
  rbenv, `backend/config/database.yml` (gitignored) apontando o app. Migrations
  como `robotrack_migrator`, suíte como `robotrack_app`.
- **Precondições da FK composta JÁ valem** (verificado no `structure.sql`):
  `robots` tem `uq_robots_id_workspace UNIQUE (id, workspace_id)` e `people` tem
  `index_people_on_workspace_id_and_id` (único). A tarefa 1.1 vira verificação
  positiva, não issue bloqueante.
- **`people_name_not_sentinel` CHECK já existe** (workspace-tenancy): nome de
  pessoa não pode ser "Não Atribuído"/"Nao Atribuido". D11 já tem dente no banco.
- **`TaskTemplates::ApplicabilityFilter` (task-catalog) é a regra §2.5** — Ruby
  (`applicable?`) e SQL (`scope_for`). A materialização do lote (5.3) a CONSOME,
  não a redefine.
- **`TaskPolicy` JÁ EXISTE** (singleton, do G1 de `authorization-policies`,
  mapeando §4.1). A tarefa 3.6 vira verificação + declaração nos endpoints.

## O objetivo central desta change

A Tarefa é a unidade atômica: tudo que o produto mede/exibe/relata sobe dela.
Esta change entrega o esquema relacional (`tasks` + `task_assignees`), o CRUD, a
atribuição por `people.id` (não por nome) e a criação de robôs em lote com cópia
das tarefas-base filtradas pela Aplicação. É o caminho crítico: destrava
`progress-advances`, `progress-rollup`, `robot-task-table`, `my-tasks-view` e o
grupo de sincronização retroativa de `task-catalog` (TC-G6).

## Ordem dos grupos

| Grupo | Área | Tarefas | Depende |
|---|---|---|---|
| **G0** | Este mapa | — | baseline |
| **G1** | Esquema `tasks`: enum status, tabela, CHECK, RLS, model, factory, spec por SQL cru | 1.1–1.6 | baseline |
| **G2** | `task_assignees`: tabela, FKs compostas, RLS, models, prova de ausência de `resp` | 2.1–2.4 | G1 |
| **G3** | API de leitura e CRUD de tarefa: entity, services, 4 endpoints, policy, 422/409, specs negativos | 3.1–3.7 | G2 |
| **G4** | Atribuição: `AssigneesService.replace` (diff), PUT idempotente, evento, hook do modal, specs | 4.1–4.5 | G3 |
| **G5** | Criação em lote §2.5: normalizer, service transacional, materialização, endpoint, assistente, spec | 5.1–5.7 | G3 + task-catalog |
| **G6** | Carga, fronteira de capacidade, handoff `legacy-data-migration` | 6.1–6.3 | G5 |

Total: ~30 tarefas em 6 grupos de código.

## Decisões de desenho já fixadas (não reabrir)

- **D-RT-1** `task_assignees` por `person_id`, FKs compostas `(task_id,
  workspace_id)`/`(person_id, workspace_id)`, único `(task_id, person_id)`,
  CASCADE de `tasks`, RESTRICT de `people`, RLS.
- **D-RT-2** o esquema NÃO tem `resp`; a leitura tolerante do legado é SÓ do
  importador (`legacy-data-migration`). Nenhum service daqui grava
  `resp = assignees[0] || "Não Atribuído"`.
- **D-RT-3** `progress`/`status` são colunas com constraint (CHECK 0–100 + enum),
  mas READ-ONLY aqui: `PATCH /tasks/:id` rejeita com 422 payload com esses
  campos. A máquina de estados §2.2 é de `progress-advances`.
- **D-RT-4** lote é UMA requisição transacional; clamp 1–50 e dedup por nome
  normalizado NO SERVIDOR; lista normalizada vazia → 422.
- **D-RT-5** materialização é cópia POR VALOR (`cat`/`desc`/`weight`), `progress
  0`, `status Pendente`, sem responsável; `position` pela ordem lexicográfica de
  `(cat, desc)`; sem `template_id`; `insert_all` com `workspace_id` explícito.
- **D-RT-6** atribuição é PUT idempotente do CONJUNTO, diff `{added, removed}` no
  servidor; `person_ids: []` válido; `person_id` alheio → 404; cadastro de pessoa
  nova é DUAS chamadas (POST /people + PUT), não `new_person_names` no PUT.
- **D-RT-7** `lock_version` na tarefa; conflito → 409 com estado atual no corpo.
- **D-RT-8** policy declarada por endpoint; `view` → 403; recurso alheio → 404
  por RLS antes da policy.

## Decisões que EU tomo aqui

1. **O índice único `(robot_id, lower(btrim(desc)))` em `tasks` ENTRA no G1**,
   apesar de o `tasks.md` de robot-tasks não o listar. Motivo: task-catalog
   §5.1/D-TC-6 declara esse índice como requisito EXPLÍCITO sobre a tabela
   `tasks`, e robot-tasks é a DONA da tabela — o índice tem de morar onde a
   tabela mora. Sem ele, o sync retroativo (TC-G6) não tem a garantia contra
   dupla-inserção concorrente que D-TC-6 promete (o lock viraria só otimização).
   Consequência assumida: criar duas tarefas com a mesma `desc` normalizada no
   MESMO robô passa a responder 409 (via `RecordNotUnique`) — coerente com o
   domínio (a `desc` é o que o sync e o catálogo usam como chave natural). Vou
   adicionar um cenário de CRUD para isso no G3. Registrado como aresta
   cross-change; se `robot-task-table` ou `progress-advances` precisarem de
   descrições repetidas por robô, reabrir com o dono daquela change.
2. **`tasks` mora no idioma dos services da hierarquia** (`Hierarchy::CrudService`
   já resolve id do cliente com `IdValidator`/`IdempotentCreate`, 201/200/409,
   404 uniforme, snapshot no corpo). Os `Tasks::*Service` seguem o MESMO contrato
   de resposta (`ApiResponseHandler`), mas em services próprios — `tasks` não é
   nível da hierarquia projeto→célula→robô e tem regras próprias (rejeição de
   `progress`/`status`, assignees).
3. **`progress_cache` do robô (D5) NÃO é criado aqui.** `commissioning-hierarchy`
   já entregou `robots.progress_cache` (visto no `RobotDTO`/entity). A nota do
   proposal ("garante que nasça na mesma migration quando a hierarquia a criar")
   fica sem efeito: já nasceu. `progress-rollup` é quem a preenche.
4. **A materialização (5.3) usa `ApplicabilityFilter.scope_for`** (SQL) para não
   carregar o catálogo inteiro em memória, e a ordem de `position` vem de
   `ORDER BY cat COLLATE "C", "desc" COLLATE "C"` — a MESMA collation binária do
   `TaskTemplate.ordered` (task-catalog 3.5), para o congelamento da ordem na
   criação bater com a ordem de exibição do catálogo entre ambientes.
5. **O evento de mudança de responsáveis (4.3)** é
   `ActiveSupport::Notifications.instrument('task.assignees_changed', ...)` com o
   diff no payload — mesmo padrão de `workspace.bootstrapped`. `in-app-notifications`
   e `realtime-collaboration` são os consumidores; aqui só publicamos. Sem
   subscriber ainda: NADA de spec pending fingindo cobertura do consumidor.
6. **Frontend (4.4, 5.6):** 4.4 é a LÓGICA do modal (hook + seleção + cadastro de
   pessoa nova em duas chamadas), não o visual final (que é de `robot-task-table`
   / `workspace-settings`). 5.6 é o assistente de dois passos como componente
   real (clamp visual, um campo por robô, uma requisição). Ambos com teste de
   componente; sem tela de rota nova se a change não pedir.

## Armadilhas previstas

1. **`desc` é palavra reservada do SQL** — aspas em SQL cru (`"desc"`), igual a
   `task_templates`. Vale para `tasks` também.
2. **`insert_all` pula callbacks E `default_scope`** (D-RT-5): `workspace_id`
   explícito em CADA hash de robô e de tarefa, senão a RLS rejeita o INSERT. É o
   mesmo modo de falha do seed de task-catalog; teste negativo cobre.
3. **FK composta exige o `workspace_id` certo nas DUAS pontas**: uma tarefa de
   WS-A com pessoa de WS-B é barrada pela FK `(person_id, workspace_id)`, não por
   código. O teste insere cru para provar que o banco recusa.
4. **`status` enum em pt-BR com acento** (`Concluído`): `'Concluido'` sem acento
   tem de estourar erro de TIPO, não passar. O enum Postgres é o dono.
5. **RESTRICT em `people`**: apagar pessoa com atribuição falha — intencional
   (D-RT-1). O CASCADE é só de `tasks`.
6. **Rejeição de `progress`/`status` no PATCH (D-RT-3)**: a requisição INTEIRA
   falha 422, não grava "só a `desc` permitida". Testar que a `desc` NÃO muda.
7. **route-sweep, cross-tenant e superfície do swagger crescem no MESMO grupo**
   que cria a rota (regra das changes anteriores): cada endpoint novo declara
   policy, entra no gerador cross-tenant (as rotas com `:id`) e na allowlist do
   swagger, tudo no grupo que o cria.
8. **Transação longa do lote máximo** (~1550 inserts): `insert_all`, não
   `create!` em loop; o benchmark (6.1) mede antes de virar timeout em produção.

## Protocolo por grupo

1. Aplicar tarefas (migrations como `robotrack_migrator`, dev E test).
2. `bundle exec rspec`; grupos com frontend também `vitest run` + `tsc --noEmit`.
3. Marcar `- [x]` em `tasks.md`.
4. `npx --yes @fission-ai/openspec@1.6.0 validate robot-tasks --strict`.
5. **Um** commit `G<n>:`. Sem push a cada grupo além do fim; sem `.env`/coverage.
6. Ao fim de cada grupo: resumir e **pedir autorização antes do próximo**.

## Decisões tomadas na execução (pós-G0)

7. **O "factory" de §1.5 é o helper `create_task(robot)` (tenancy_helpers.rb),
   não uma FactoryBot factory.** A `factories_spec` linta TODA factory rodando
   `create(name)` SEM contexto de tenant; uma factory de `Task` (linha de tenant)
   estouraria na RLS. O repo já não tem factory nenhuma de model de tenant por
   isso — cria via `make_workspace`/inline. O helper resolve `workspace_id` do
   robô, que é o intent literal de §1.5. Também: `tasks` ganhou
   `index_tasks_on_workspace_id` porque a `schema_guard_spec` exige um índice
   liderado por `workspace_id` em toda tabela de domínio.

## Progresso

- [x] G1 — Esquema `tasks` (1.1–1.6) — backend 712 → 723 (12→11 pending: a
  contract spec de cascade `tasks→robots` destravou ao existir a tabela)
- [ ] G2 — `task_assignees` (2.1–2.4)
- [ ] G3 — API de leitura e CRUD (3.1–3.7)
- [ ] G4 — Atribuição de responsáveis (4.1–4.5)
- [ ] G5 — Criação de robôs em lote (5.1–5.7)
- [ ] G6 — Carga, fronteira e handoff (6.1–6.3)

## RETOMADA

1. `git log --oneline -8` na branch `robot-tasks`; um commit por grupo.
2. `tasks.md` tem o estado fino; este arquivo, as decisões e armadilhas.
3. Baseline antes de codar: Postgres no ar (`service postgresql start`),
   migrations como `robotrack_migrator`, `rspec` como `robotrack_app`,
   `vitest run`. Ver EXECUCAO de task-catalog para o provisionamento do container.
4. Reler **Decisões que EU tomo** (em especial 1: o índice `(robot_id,
   lower(btrim(desc)))` no G1) e **Armadilhas** (2: `workspace_id` no `insert_all`;
   6: PATCH rejeita `progress`/`status` inteiro).
5. Invioláveis: sem push fora do combinado, runtime sem SUPERUSER/BYPASSRLS, RLS
   forçada nas tabelas novas, varreduras só crescem, cross-tenant = 404.
6. Empilhamento: `robot-tasks` sai de `task-catalog`. Ao fechar, TC-G6 (sync)
   pode enfim rodar sobre `tasks`.
