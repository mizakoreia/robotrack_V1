# EXECUCAO — my-tasks-view

Mapa de execução. Escrito ANTES de qualquer código (commit G0). RETOMADA no fim.

## Ponto de partida

Branch empilhada sobre `robot-task-table`. Onda 8+. FULL-STACK, mas **leitura pura** — a
tela NÃO muta nada. Preenche o stub `MyTasksPage` (`/minhas-tarefas`, já roteado em
App.tsx). O CORAÇÃO não é UX nem perf: é **não falhar em silêncio** — uma lista vazia é
resultado plausível ("nada atribuído"), então uma quebra de identidade se disfarça de
estado normal. Por isso `Person` ausente = **409**, nunca `200 []` (D-MTV-2).
Depende de `workspace-tenancy` (bootstrap cria `Person` do dono), `workspace-invitations`
(aceite cria/reusa `Person`), `robot-tasks` (`task_assignees` por `person_id`),
`progress-advances` (§2.2, auto-atribuição §2.3), `app-shell-navigation` (shell + qk.*),
`design-system` (Badge, estados). Baseline: backend **978/0/9pending**, frontend **290/0**.

## RECONCILIAÇÃO COM A REALIDADE (crítico — ler antes de codar)

- **STATUS é ENUM Postgres PT-BR** `task_status = ('Pendente','Em Andamento','Concluído',
  'N/A')` (migration CreateTasks). O design.md escreve `pending/in_progress/done/
  not_applicable` como PLACEHOLDER — uso os literais REAIS. Logo:
  - índice parcial (2.2): `WHERE status IN ('Pendente','Em Andamento')`;
  - filtro do service (2.4/D-MTV-4): idem;
  - spec do enum (2.3): consulta `pg_enum` de `task_status` e afirma EXATAMENTE esses 4.
- **ENDPOINT = `GET /api/v1/my_tasks`**, tenant pelo header `X-Workspace-Id` + RLS —
  NÃO `/workspaces/:workspace_id/my_tasks`. Motivo: TODO o app resolve tenant pelo header
  (`env['api.current_workspace_id']`); `workspace_id` NÃO é route param em lugar nenhum
  (projects/search/hierarchy divergiram assim). Registro como divergência (igual a
  hierarchy-screens). Os cenários da spec que citam `/workspaces/W1/my_tasks` são prosa;
  o que importa (3.4/D-MTV-10) — `?person_id=` IGNORADO — é agnóstico ao path.
- **`set_pagination_headers(total, page, per_page)` JÁ EXISTE** (controller_helpers) —
  seta `X-Total-Count`/`X-Page`/`X-Per-Page`. Reuso (2.5/3.3).
- **Pré-condições de identidade VALEM**: `Workspaces::BootstrapService#ensure_owner_person`
  cria a `Person` do dono (`INSERT INTO people … user_id`); `Invitations::AcceptService`
  cria/reusa no aceite; `memberships.person_id NOT NULL` + FK `people(id)`. G1 PROVA isso
  com os services reais (proibido factory de `Person`).
- **Índice `(workspace_id, person_id) INCLUDE (task_id)` NÃO existe** — só há
  `index_task_assignees_on_person_task (person_id, task_id)`. 2.1 ADICIONA o ws-person
  (não é no-op). O parcial `idx_tasks_open_ws` também não existe ainda → 2.2 cria.
- **`qk.myTasks = ['ws', wsId, 'my-tasks']` JÁ EXISTE** (keys.ts). A tela lê/invalida ela.
- **Policies são POROs** (`extends BasePolicy`, `permits index?: :read_workspace`). Crio
  `MyTasksPolicy` com `index?: :read_workspace` (membership em QUALQUER papel, inclusive
  `view` — a tela não muta; D-MTV-10).
- **`ApiResponseHandler`** é o padrão dos services (success_response/error_response). O
  service devolve `409 person_missing` quando a `Person` do viewer não existe (D-MTV-2).

## Ordem dos grupos (mapeia as seções do tasks.md)

| Grupo | Escopo | Tarefas | Visual? |
|---|---|---|---|
| **G1** | Provar a pré-condição de identidade (bootstrap real + aceite real criam `Person`; esquema sem coluna de nome) | 1.1–1.4 | não |
| **G2** | Consulta + índices: migrations (ws-person INCLUDE, parcial PT), spec do enum, `MyTasks::ListService` (driver em task_assignees, joins, ordenação total D-MTV-6, paginação), integração 120 tarefas | 2.1–2.6 | não |
| **G3** | Endpoint/authz/viewer: `MyTaskRow` achatada, `GET /my_tasks` montado, `MyTasksPolicy`, 409 person_missing, `?person_id=` ignorado, specs 401/403/200-view | 3.1–3.5 | não |
| **G4** | Provas de §3.6 + isolamento: 6 campos, avanço 45→100 some, N/A não aparece, dedup multi-responsável, Person sem user_id, e2e sem factory; cross-tenant + RLS-stub + 1 query | 4.1–4.6, 5.1–5.3 | não |
| **G5** | Tela: `MinhasTarefasPage` (qk.myTasks), 6 colunas (Badge estático, sem mutação), linha `<a>` deep-link, 3 estados (vazio/409/erro), mobile em cartões, invalidação por evento | 6.1–6.7 | SIM |
| **G6** | Desempenho: dataset de carga (28.800 tarefas), p95<120ms + EXPLAIN sem Seq Scan on tasks | 7.1–7.2 | ajustes |

> Print no G5 (a tela é o único grupo visual). Suíte backend completa fica p/ o fim.

## Decisões de desenho fixadas (design.md — não reabrir)

D-MTV-1 filtro por `person_id`, nome NUNCA participa; D-MTV-2 viewer = `Person(ws,user_id)`,
ausência = **409**, nunca `200 []`; D-MTV-3 `person.user_id NULL` é legítimo e nunca vê a
tela (a tarefa só dela não aparece p/ ninguém); D-MTV-4 UMA consulta, driver em
task_assignees, payload achatado; D-MTV-5 dois índices + orçamento p95<120ms/0 seqscan/1
query; D-MTV-6 ordenação total projeto→célula→robô→tarefa (position + desempate por id),
offset; D-MTV-7 sem materialização; D-MTV-8 3 estados distintos (vazio/409/erro), strings
D14; D-MTV-9 deep-link `?task=:taskId` (query, não fragmento); D-MTV-10 authz = membership
qualquer papel, viewer só do token (nunca param).

## Decisões que EU tomo aqui (LER)

1. **Status PT-BR REAL** em todo predicado/índice/spec (ver reconciliação).
2. **Endpoint `/api/v1/my_tasks`** header-tenant (ver reconciliação) — divergência do path
   do design, coerente com o app.
3. **Ordenação**: o `ORDER BY` de D-MTV-4 usa `p.position, p.id, c.position, c.id,
   r.position, r.id, t.position, t.id`. Confirmo que projects/cells/robots/tasks têm
   `position` (hierarquia) — se algum não tiver, caio para `name, id` naquele nível e
   registro.
4. **Deep-link**: emito `/robo/:robotId?task=:taskId` (a rota REAL do app é `/robo/:id`,
   não `/ws/:wsId/robots/:robotId` do design — reconcilio para a rota que existe). Realçar
   a tarefa ao chegar é de robot-task-table (fora daqui).
5. **G1 antes do endpoint**: os specs de identidade testam bootstrap/aceite, independem do
   meu código. Rodo com o bootstrap real; 1.4 prova que falham com `Person` stubbada.

## Armadilhas previstas

1. **Falha silenciosa** — `Person` ausente DEVE dar 409, nunca `200 []`. Spec 4.6 (e2e sem
   factory) é o guardião; no cliente, o estado 409 é distinto do vazio (D-MTV-8).
2. **Inversão de seletividade** — o driver é `task_assignees` (parte da pessoa), não
   `tasks`. Spec de contagem de query (5.3) + EXPLAIN (7.2) pegam se inverter.
3. **Duplicação por multi-responsável** — partir da linha do viewer em task_assignees já
   dá 1 linha por tarefa; não fazer JOIN que multiplique. Spec 4.4.
4. **Ordenação instável** — desempate por `id` em CADA nível; sem ele, paginação oscila
   (spec 2.6: união das páginas = 120 distintos, ordem estável em 5 chamadas).
5. **Enum diverge do índice em silêncio** — spec 2.3 trava o conjunto de status.
6. **`person_id` param** — IGNORADO; viewer só do token (3.4/spec 3.5).
7. **Índice parcial com literais errados** — `('Pendente','Em Andamento')`, não os nomes
   de enum inventados do design.

## Protocolo por grupo

Aplicar → backend `rspec` dirigido (0 falhas) e/ou frontend `vitest`+`tsc` (0) → marcar
`- [x]` em tasks.md → `npx --yes @fission-ai/openspec@1.6.0 validate my-tasks-view
--strict` → **um commit** `G<n>:` → print no G5. Suíte backend completa no fim.
Provisionar o banco a cada sessão (ver CONTINUIDADE) + `PATH=/opt/rbenv/shims`.

## Progresso

- [x] G0 — este mapa (commit G0)
- [x] G1 — pré-condição de identidade (1.1–1.4)
- [ ] G2 — consulta + índices (2.1–2.6)
- [ ] G3 — endpoint + authz + viewer (3.1–3.5)
- [ ] G4 — provas de §3.6 + isolamento (4.1–4.6, 5.1–5.3)
- [ ] G5 — tela (6.1–6.7)
- [ ] G6 — desempenho (7.1–7.2)

## RETOMADA (para o próximo agente)

1. `git log --oneline` na branch (empilhada em `robot-task-table`); um commit por grupo.
2. LEIA a RECONCILIAÇÃO: status ENUM PT-BR, endpoint `/api/v1/my_tasks` header-tenant,
   pré-condições de identidade valem, índice ws-person NÃO existe (2.1 cria).
3. Invioláveis: `Person` ausente = 409 (nunca `200 []`); filtro por `person_id` (nunca
   nome); UMA consulta sem N+1; ordenação total com desempate por id; `?person_id=`
   ignorado; RLS garante tenant além do WHERE; enum travado em 4 status PT.
4. Banco: provisionar (ver CONTINUIDADE) + `PATH=/opt/rbenv/shims`. Prints: `scratchpad/
   shot.mjs` (rota `/minhas-tarefas`).
