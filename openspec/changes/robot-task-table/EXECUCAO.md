# EXECUCAO — robot-task-table

Mapa de execução. Escrito ANTES de qualquer código (commit G0). RETOMADA no fim.

## Ponto de partida

Branch empilhada sobre `hierarchy-screens`. Onda 8. FULL-STACK (backend: estender a
leitura agregada; frontend: a tela operacional §3.5 — 6 colunas, 2 modais, mobile).
Baseline: backend baseline 933/0 + specs de hierarchy-screens 49/0; frontend 231/0.
Depende de `robot-tasks` (esquema+CRUD+endpoint de lista), `progress-advances` (modal
de avanço + trilha), `progress-rollup` (percentual ponderado), `task-catalog` (§2.6
sync), `design-system` (StatusSelect/Chip/Modal/Badge), `app-shell-navigation` (rota
`/robo/:id`, D9). Consumida por `offline-pwa` e `realtime-collaboration`.

## RECONCILIAÇÃO COM A REALIDADE (crítico — muita coisa já existe)

- **Endpoint `GET /api/v1/robots/:robot_id/tasks` JÁ EXISTE** (robot-tasks), com
  `Api::Entities::Task` (id, cat, desc, weight, progress, status, position,
  lock_version, updated_at, **assignees[{id,name}]**, **advances_count**,
  **last_comment**) e `Tasks::ListService.for_robot` que **pré-carrega
  `task_advances`** (sem N+1). → 1.1/1.2 = ESTENDER a entity/service (somar
  `contributors[]` e `last_advance{comment,recorded_at,author_name_snapshot,legacy}`),
  NÃO criar endpoint/`TaskRow` paralelo. O contrato-spec de 1.1 aplica-se à entity.
- **Índice `(task_id, recorded_at DESC, created_at DESC, id DESC)` JÁ EXISTE**
  (progress-advances). → a migration do "plano de migração" é NO-OP; não crio índice.
- **`<AdvanceControls robotId taskId />` JÁ EXISTE** (progress-advances G5): botões
  ±10, slider, modal de confirmação, role-gated (`view` sem controles), e no sucesso
  invalida `catalogKeys.robotTasks(wsId,robotId)` + a trilha. → Grupo 2 COMPÕE isso,
  não reimplementa o modal/slider. A célula de Status (StatusSelect → abre o modal com
  `to%` derivado de §2.2) é a parte nova a ligar.
- **Cache key = `catalogKeys.robotTasks(wsId, robotId)` = `['ws',wsId,'robot',robotId,
  'tasks']`** (idêntico a `qk.tasks`). A tabela POPULA/lê essa chave; `AdvanceControls`
  lê `progress`/`lock_version` dela. Reuso `catalogKeys` (não duplico com `qk.tasks`).
- **PUT `/tasks/:id/assignees` JÁ EXISTE** (robot-tasks G4) + criação de `Person`
  (workspace-tenancy). → Grupo 5 (modal de atribuição) COMPÕE esses endpoints.
- **`TaskDTO` já existe** (advances_count/last_comment/assignees) — somo `contributors`
  + `last_advance`. As telas em `app/` não importam `lib/api` (reexporto pela feature).
- **Rota `/robo/:id`** é destino do "Abrir" (hierarchy-screens) e hoje é STUB; monto a
  `RobotTaskTablePage` lá, com `key={robotId}` (D-RTT-1).

## Ordem dos grupos (Grupo 1 bloqueante; 2–6 paralelizáveis; 7 integra)

| Grupo | Escopo | Tarefas | Visual? |
|---|---|---|---|
| **G1** | Esqueleto: estender entity (contributors+last_advance) + ≤3 queries; feature `features/robot-tasks/`, `useRobotTasks`, rota `key=robotId`, layout por categoria, estados, `robotTaskFilterStore` + reset | 1.1–1.6 | SIM (tabela base) |
| **G2** | Colunas de mutação: Status (StatusSelect→modal §2.2) + Progresso (compõe `AdvanceControls`), invalidação | 2.1–2.4 | SIM |
| **G3** | Colunas de leitura + avisos: Responsáveis (chips 1º/2º), Trilha (last_advance), avisos "Atribuir…"/"Registre…" | 3.1–3.5 | SIM |
| **G4** | Cabeçalho (nome+Aplicação+% ponderado rotulado), Ações (editar/excluir), Sincronizar §2.6, gating de papel `view` | 4.1–4.5 | SIM |
| **G5** | Modais: histórico (timeline por recorded_at, legacy marcado) + atribuição (checkboxes people + cadastro) | 5.1–5.5 | SIM |
| **G6** | Mobile (cartões <md), alvos ≥40px, `successPulse` 100%, ARIA/foco nos modais | 6.1–6.5 | SIM |
| **G7** | Integração das trilhas, E2E dos cenários, dataset de carga (40 tarefas/200 avanços, 1 request) | 7.1–7.3 | ajustes |

> Prints a cada grupo a partir do G1 (a tabela é visual desde o esqueleto).

## Decisões de desenho fixadas (design.md — não reabrir)

D-RTT-1 filtro efêmero (Zustand sem persist) reset por `key={robotId}` + `useEffect`;
D-RTT-2 filtro derivado de STATUS (Pendentes=Pendente+Em Andamento; Concluídos=Concluído;
N/A só em Todos), no cliente; D-RTT-3 um endpoint agregado, sem N+1 (aqui: via `includes`
existente); D-RTT-4 assignees vs contributors disjuntos (intersecção subtraída do 2º);
D-RTT-5 slider `persisted`(query)/`draft`, ± a partir de `persisted` nunca do DOM (já no
AdvanceControls); D-RTT-6 aviso trilha = `0<progress<100 AND advances_count=0` (sem "nem
nota"); D-RTT-7 avisos não-bloqueantes dentro da célula; D-RTT-8 mobile por cartões reais;
D-RTT-9 `view` REMOVE controles (status vira Badge), servidor é a garantia (403); D-RTT-10
key `['ws',wsId,'robot',robotId,'tasks']` + invalida também `['ws',wsId,'projects']`;
D-RTT-11 decomposição p/ paralelismo. D8 recorded_at; D11 identidade; D15 % rotulado.

## Decisões que EU tomo aqui (LER)

1. **Estender o endpoint/entity existente**, não criar `TaskRow`+endpoint novo. A entity
   ganha `contributors` + `last_advance`; o service segue com `includes(:task_advances)`
   (sem N+1). Contrato-spec (1.1) sobre a entity estendida.
2. **Reusar `<AdvanceControls>`** para a coluna Progresso e o disparo do modal; a coluna
   Status liga o StatusSelect ao mesmo modal com `to%` de §2.2.
3. **Reusar `catalogKeys.robotTasks`** (a chave que AdvanceControls já lê/invalida).
4. **`contributors`** = `DISTINCT by` (person_id não-nulo) dos avanços, nome do
   `author_name_snapshot` (sem query extra — advances já pré-carregados).
5. **Migration de índice = NO-OP** (já existe); registro e sigo.
6. **`view`**: controles REMOVIDOS do DOM (não `disabled`); os 403 já são garantidos pelas
   policies de robot-tasks/progress-advances — adiciono specs de request confirmando.

## Armadilhas previstas

1. **N+1 na trilha** — manter `includes(:task_advances)`; contributors/last_advance em
   memória. Teste conta queries (1.2/7.3), ≤3.
2. **recorded_at vs created_at** — `last_advance`/timeline por `recorded_at DESC,
   created_at DESC`; spec de contrato falha se virar `created_at`.
3. **Bug "+10 duas vezes = +10"** — já resolvido no AdvanceControls (persisted da query);
   não reintroduzir lendo do DOM.
4. **Reset de filtro** — `key={robotId}` + `useEffect([robotId])` (A→B→A mostra Todos).
5. **contributors ⊄ assignees** — subtrair a intersecção só no 2º chip (D-RTT-4).
6. **Aviso trilha** — `advances_count=0` inclui legacy no COUNT (legacy conta como trilha).

## Protocolo por grupo

Aplicar → backend `rspec` dirigido (0 falhas) e/ou frontend `vitest` + `tsc` (0) →
marcar `- [x]` em tasks.md → `npx --yes @fission-ai/openspec@1.6.0 validate
robot-task-table --strict` → **um commit** `G<n>:` → print da tela (G1+). Suíte backend
completa fica para o G7. Provisionar o banco a cada sessão (ver CONTINUIDADE).

## Progresso

- [x] G0 — este mapa (commit G0)
- [x] G1 — Esqueleto + contrato (1.1–1.6)
- [ ] G2 — Status + Progresso (2.1–2.4)
- [ ] G3 — Responsáveis + Trilha + avisos (3.1–3.5)
- [ ] G4 — Cabeçalho + Ações + sync + gating (4.1–4.5)
- [ ] G5 — Modais histórico + atribuição (5.1–5.5)
- [ ] G6 — Mobile + a11y + pulso (6.1–6.5)
- [ ] G7 — Integração + E2E + carga (7.1–7.3)

## RETOMADA (para o próximo agente)

1. `git log --oneline` na branch (empilhada em `hierarchy-screens`); um commit por grupo.
2. LEIA a RECONCILIAÇÃO: endpoint/entity/índice/AdvanceControls/assignees JÁ EXISTEM.
   G1 é ESTENDER + montar a casca da tela; muita coisa é compor, não construir.
3. Invioláveis: 1 endpoint sem N+1, recorded_at (não created_at), filtro reset na nav,
   contributors≠assignees, aviso trilha `0<p<100 AND advances_count=0`, `view` sem
   controles (403 no servidor), key `['ws',wsId,'robot',id,'tasks']` + invalida projects.
4. Banco: provisionar (ver bloco no topo do CONTINUIDADE) + `PATH=/opt/rbenv/shims`.
   Prints: `scratchpad/shot.mjs` (mocka a API).
