# Continuidade — estado em 22/07/2026

Ponto de retomada do porte. Para uma sessão nova de agente, o prompt de partida
está em [PROMPT DE RETOMADA](#prompt-de-retomada), no fim.

## Onde está o trabalho

**As branches são empilhadas, não independentes:**

```
main (48497fd)                       ← ondas 1–4, sem nada desta sessão
└── authorization-policies (6b89283)     change COMPLETA
    └── commissioning-hierarchy (b75b072)  change COMPLETA
        └── task-catalog                   change COMPLETA — 6 de 6 (TC-G6 fechou)
            └── robot-tasks                 change COMPLETA — 6 de 6 grupos
                └── progress-advances        change COMPLETA — 6 de 6 grupos
                    └── progress-rollup          change COMPLETA — 6 de 6 grupos
                        └── design-system                  change COMPLETA — 8 de 8 grupos
                            └── app-shell-navigation       change COMPLETA — 6 de 6 grupos
                                └── hierarchy-screens          change COMPLETA — 7 de 7 grupos
                                    └── robot-task-table       change COMPLETA — 7 de 7 grupos
                                        └── my-tasks-view          change COMPLETA — 7 de 7 grupos
                                            └── commissioning-report   change COMPLETA — 8 de 8 grupos
                                                └── audit-log          change COMPLETA — 8 de 8 grupos
                                                    └── workspace-settings   PARCIAL — G0..G4 verdes, G5/G6 PAUSADOS
                                                        └── hierarchy-soft-delete (atual)  pré-requisito do reset
```

**A branch atual contém todo o trabalho** (empilhamento full-stack). É nela que se
continua. Push por branch canônica (`git push origin HEAD:<change>`). Os PRs para a
`main` podem ser abertos depois, na ordem do empilhamento.

> **Ordem invertida por dependência:** `workspace-settings` começou (G0..G4: Equipe,
> catálogo, backup — todos verdes), mas o G5 (reset de fábrica) esbarrou num bloqueio
> estrutural: `task_advances` é IMUTÁVEL (REVOKE DELETE + trigger) e trava as tarefas
> com FK `ON DELETE RESTRICT`, então `DELETE FROM projects` é impossível quando há
> avanços (o caso normal). O reset precisa ARQUIVAR, não apagar. Isso exige primeiro o
> **soft-delete de hierarquia** — a change `hierarchy-soft-delete` (atual), que também
> quita a pendência D-H6×D-IMUT. Depois volta-se ao G5/G6 de `workspace-settings`.

## Suítes (medidas na branch `audit-log`)

| Suíte | Resultado |
|---|---|
| Backend `bundle exec rspec` (como `robotrack_app`, `--seed 12345`) | **~1090+ / 2** (audit-log somou ~55 specs a `spec/audit`, todos verdes isolados) — as 2 falhas conhecidas são os BENCHMARKS de tempo do `spec/progress/load_dataset_spec.rb` (93k tarefas, runner lento), NÃO regressão. Total exato confirmado ao fim da suíte completa desta sessão. |
| Frontend `vitest run` | **329 / 0** (57 arquivos) |
| Frontend `tsc --noEmit` | limpo |
| Frontend `pnpm build` | limpo |

> **Provisionamento do banco (container efêmero — refazer a cada sessão):**
> `service postgresql start`; como `postgres` superuser criar `robotrack_user`
> (SUPERUSER) + os bancos `robotrack_dev`/`robotrack_test` + aplicar `db/roles.sql`
> nos dois; `PATH=/opt/rbenv/shims:$PATH` para ruby 3.2.3 (o `/usr/local/bin/ruby`
> 3.3 sombreia). O schema já vem carregado (session-start hook). Detalhes em
> `backend/db/PROVISIONING.md`.
>
> **Screenshots das telas** (sem backend): `pnpm dev` + Playwright global
> (`/opt/node22/lib/node_modules/playwright`) interceptando a API — o harness está em
> `scratchpad/shot.mjs` (semeia sessão+workspace no localStorage, mocka os overviews).

> Lição desta change: constantes definidas dentro de `RSpec.describe do … end`
> VAZAM para o topo (Object). Dois specs com `ALLOWLIST`/`ENVELOPES`/`APP` colidem
> e a última carga vence, quebrando um ou outro conforme a seed. Prefixe (ex.:
> `PME_`, `PWB_`). Foi o que mordeu no G6.

Todos os 10 pending nomeiam a capacidade que os desbloqueia — nenhum é dívida
anônima. (Dois pendings de cascade — `tasks→robots` e `task_assignees→tasks` —
destravaram e viraram verdes ao longo de `robot-tasks`.)

> Nota de ambiente: `spec/requests/auth/rate_limit_spec.rb` é levemente FLAKY na
> suíte completa (estado do Rack::Attack sensível à ordem aleatória do RSpec);
> passa isolado. Não é regressão desta sessão. Rodar com `--seed` fixo estabiliza.

## Changes concluídas (17 de 24)

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
- **`task-catalog`** (G0..G6, COMPLETA) — catálogo `task_templates` (CHECK de domínio,
  unicidade por `desc` normalizada, RLS), `ApplicabilityFilter` Ruby+SQL, seed dos 31
  padrões na transação do bootstrap, CRUD + `GET /meta/robot_applications`, cliente TS, e a
  **sincronização retroativa** (`SyncToRobotService` + `POST /robots/:id/sync_task_templates`)
  que aplica os templates faltantes a robôs existentes sem sobrescrever, com backstop de
  concorrência pelo índice único de `tasks`. O TC-G6 fechou depois de `robot-tasks`.
- **`progress-advances`** (G0..G6, COMPLETA) — a máquina de estados progresso↔status §2.2 e
  a trilha de avanço **imutável**. `task_advances` (RLS forçada só com SELECT+INSERT, REVOKE
  UPDATE/DELETE + trigger, FK composta `ON DELETE RESTRICT`, CHECKs da regra dura do
  comentário/autor-nulo-só-legacy/skew de `recorded_at`), `tasks` ganhou soft-delete e a
  CHECK `done ⇒ 100`. `ApplyTransitionService` (tabela-verdade pura, sem aasm),
  `TaskAdvances::CreateService` (idempotência por uuid ANTES do `lock_version`, 409 com
  estado atual, clamp de `recorded_at`, auto-atribuição do autor, evento pós-commit — tudo
  numa transação com `requires_new: true`, um savepoint que um bug de concorrência real
  exigiu). API `POST`/`GET /tasks/:task_id/advances` (`TaskAdvancePolicy`, 409 no formato
  D-409), entity com `advances_count`/`last_comment`. Frontend `features/advances/` (slider
  `draft ?? server`, ±10 lendo cache vivo, modal com rótulo condicional e resolução de 409
  sem perder o comentário, read-only para `view`). Três handoffs de contrato
  (`legacy-data-migration`, `robot-task-table`, `delivery-and-observability`) e e2e dos 5
  efeitos. Decisões de execução 1–10 no EXECUCAO.
- **`progress-rollup`** (G0..G6, COMPLETA) — as DUAS métricas de progresso que coexistem de
  propósito (D15): **ponderada** §2.1 (por peso no robô, média simples acima) e **contagem
  crua** §3.2 (`concluídas ÷ total`, `N/A` no denominador). Ambas SÓ em SQL (4 views
  `security_invoker`, sem gêmeo Ruby/TS). `progress_cache` convertido de jsonb→**smallint**
  (EXECUCAO decisão 1 — a grande: alinhou a coluna provisória da hierarquia à spec desta
  change, autorizado pelo cliente). Cache escrito em **cascata na transação** da mutação
  (`Progress::CascadeRecompute`, 3 UPDATE ordem fixa), caminho em massa (`BulkRecompute` +
  `without_cascade`), sweep do ponto de escrita único, job de **reconciliação** que corrige e
  alerta sob RLS, endpoint de recálculo manual, Visão Geral leve (`GET /api/v1/projects/
  overview`, 2 queries constantes) com envelopes rotulados `weighted_progress`/`raw_completion`,
  dataset de carga 93k, e a rotulagem D15 (locales, `<ProgressRing>`/`<MetricStat>` com `metric`
  obrigatória, sweeps). Handoffs para `delivery-and-observability`, `legacy-data-migration`,
  `commissioning-report`, `robot-task-table`. Decisões 1–7 no EXECUCAO.

- **`design-system`** (G0..G8, COMPLETA, frontend-only, Onda 0) — a base visual que TODAS as
  telas consomem. Token set único (dois temas, escuro primário) com triplas HSL sem alpha
  (D-DS-1); as 3 variantes de status com **contraste medido no CI** (`tests/contrast.test.ts`,
  16 pares, reprova < 4.5:1 corpo / 3:1 não-texto — a "armadilha nº 1" travada); namespaces de
  cor restritos por propriedade (`text-success` não compila — D-DS-2); Inter + escala rem +
  tabular-nums; sprite de ícones (`currentColor`, lint de emoji); z-index semântico + lint;
  tema não segue o SO (guarda de CI) com dark default/.light/anti-FOUC; 9+ primitivos em
  `components/ui/` (EntityCard, ProgressRing base que OMITE o path a 0%, Hub, Badge,
  StatusSelect, Chip, Modal com focus-trap/Esc, SaveIndicator, FilterBar, IconButton com
  a11y na assinatura de tipo — D-DS-9); luz ambiente (`lib/ambient.ts`, throttle 32ms, 3
  degradações); Recharts/TipTap/Slate DESINSTALADOS (bundle -208kB) com guarda de retorno.
  **Divergência:** `tokens-campfire.css` + aliases shadcn mantidos (só vars da landing,
  ortogonais aos papéis; remoção real quando as telas substituírem as páginas do template —
  EXECUCAO decisão 3/4). HANDOFF de CSP para `delivery-and-observability`. Backup em
  `git tag pre-design-system-cleanup` (local — o proxy rejeita push de tag).
- **`app-shell-navigation`** (G0..G6, COMPLETA, frontend-only, Onda 2) — a moldura permanente
  e as convenções que DESBLOQUEIAM as seis telas. Fundação D9: defaults do QueryClient
  (staleTime 30s, mutation retry 0), factory tipada de chaves `qk.*` (`['ws', wsId, …]` exige
  wsId), e o **guard de forma de key** ligado no `main.tsx` (DEV lança, prod reporta; tolera
  tenant null da query desabilitada). Menu em portal (`#rt-overlays`, fixed, medição prévia, 5
  gatilhos de fechamento, teclado virtual, a11y). `AppShell` envolve toda a área autenticada
  (sidebar de 3 destinos por preenchimento tintado — nunca faixa lateral; rodapé com card de
  usuário + indicador de gravação; topbar com contexto de workspace e menu da conta; gaveta
  <768px). Contexto de workspace: seletor só com >1 (senão texto estático fora do Tab), papel
  como **badge** (não select), e `switchWorkspace` = a **barreira CLIENTE contra vazamento**
  (`cancelQueries` → `clear()` cache inteiro → reset → grava wsId; testes 5.5/5.6 provam que
  cache quente de um tenant não reaparece após a troca). `persistenceStore` (contrato para
  `offline-pwa`, dedup por id) + indicador como projeção pura (erro > salvando > salvo). Sweep
  de convenção no CI (componentes não importam a API, createPortal só em menu/, stores não
  buscam dado, sem invalidação do tenant inteiro). **Divergências:** `/` virou a Visão Geral
  autenticada (landing do template → `/apresentacao`); telas de destino são STUBS
  (`hierarchy-screens`/`my-tasks-view`/`commissioning-report` as preenchem); sem página do
  template em React Query para migrar (6.3 = verificar + ligar o guard).
- **`hierarchy-screens`** (G0..G7, COMPLETA, full-stack, Onda 7) — as três telas de navegação
  (Visão Geral, Projeto, Célula) + a busca. O CORAÇÃO é D15: as DUAS métricas na mesma dobra —
  hub = contagem crua §3.2, anel = ponderado §2.1 — com nomes SEPARADOS na API (`raw_completion`
  vs `weighted_progress`, nunca `progress`) e teste sobre a fixture DIVERGENTE (ponderado 40 ≠
  crua 25, provado sob a fórmula SQL real). Backend: 3 services agregadores (`Hierarchy::
  *OverviewService`, ≤3 queries constantes em N, lendo `progress_cache`), a Visão Geral estende o
  `/projects/overview` de progress-rollup (aditivo), busca server-side (`ILIKE` escapado,
  `path_label` de locale, escopo por RLS), entities-contrato + scanner anti-`progress`, isolamento
  cross-tenant 404 nos 3 endpoints. Frontend: OverviewPage/ProjectPage/CellPage (hub + grade +
  vazio/carregando/erro), CRUD de célula ligado ao overview, "adicionar robôs" (assistente de
  robot-tasks), busca com debounce/flush/keepPreviousData substituindo a visão pelo termo, E2E de
  navegação. **Divergências:** rotas pt-BR sem `:wsId` (tenant pelo header); overviews ganharam
  `id`/`name`/`lock_version` (cabeçalho + renomear); peso da fixture 2:1 (o texto dizia 5, que dá
  63 na fórmula real — usei o que bate o alvo 40 que a tarefa 4.6 asserta). Robô (`/robo/:id`) é de
  `robot-task-table` — aqui só navego para lá.
- **`robot-task-table`** (G0..G7, COMPLETA, full-stack, Onda 8) — a TELA OPERACIONAL do robô
  (rota `/robo/:id`, `key={robotId}`). Backend: estendeu a entity `Task` (contributors +
  last_advance por `recorded_at`, NÃO created_at — D8), `GET /robots/:id` (cabeçalho), tudo em
  ≤3 queries constantes em N (teste de orçamento com 40 tarefas/200 avanços). Frontend, 6 colunas:
  Status (StatusSelect→modal de avanço em MODO STATUS, envia `status` não progress — §2.2 no
  servidor), Progresso (compõe `<AdvanceControls>`, slider passo 5, ± do persistido), Responsáveis
  (chips 1º=assignees / 2º=contributors menos intersecção, D-RTT-4), Trilha (last_advance + contagem),
  Ações (editar/excluir), + os dois avisos não-bloqueantes ("Atribuir…" progress>0 sem responsável;
  "Registre o avanço…" 0<p<100 e advances_count=0, SEM a nota legada — D-RTT-6). Filtro efêmero
  reset na navegação (D-RTT-1). Modais: histórico (timeline por `recorded_at`, legacy marcado,
  "sem comentário" sem herdar do vizinho) e atribuição (checkboxes de people + cadastro com dedup
  por nome, D10/D11). Cabeçalho com % ponderado rotulado + Sincronizar tarefas-base (§2.6, reseta
  filtro) + Adicionar tarefa. Gating de `view`: controles FORA do DOM (não disabled), servidor
  garante (403). Mobile: cartões <md via `useMediaQuery` (um layout por vez), alvos ≥40px, slider
  `touch-pan-y`, `successPulse` na transição <100→100 (suprimido por reduced-motion). Render única
  por mutação (structuralSharing + `memo`). Invalidação: robotTasks + qk.robot exato + qk.projects.
  **Divergências:** Chip 1º/2º por `className` (o Chip não tem `variant`); Em Andamento→accent;
  E2E = integração RTL (sem dep de Playwright); swagger allowlist ganhou `/api/v1/search` (lacuna de
  hierarchy-screens que só apareceu na suíte cheia). Decisões G2..G7 no EXECUCAO.
- **`my-tasks-view`** (G0..G6, COMPLETA, full-stack, Onda 8+) — a lista pessoal do viewer (preenche
  o stub `MyTasksPage`, rota `/minhas-tarefas`). O CORAÇÃO é NÃO FALHAR EM SILÊNCIO: `Person` do
  viewer ausente = **409 person_missing**, NUNCA `200 []` (uma lista vazia enganosa; D-MTV-2). §1
  PROVA a pré-condição de identidade com os services REAIS (bootstrap + aceite criam a `Person`),
  proibido factory. Backend: `GET /api/v1/my_tasks` (tenant pelo header, viewer = `authorization_
  context.person`, `?person_id=` IGNORADO — D-MTV-10), `MyTasks::ListService` UMA consulta com driver
  em `task_assignees` + joins até o projeto + `COUNT(*) OVER()` (1 query), ordenação total
  projeto→célula→robô→tarefa com desempate por id (D-MTV-6), filtro por STATUS pt-BR
  (`Pendente`/`Em Andamento`) no servidor. Dois índices aditivos CONCURRENTLY (ws-person INCLUDE +
  parcial de abertas). Provas §3.6: avanço 45→100 some da lista, N/A não aparece, multi-responsável
  1x, Person sem user_id não vaza; isolamento cross-tenant + RLS-stub. Frontend: 6 colunas, Badge
  estático (LEITURA PURA), linha `<a>` deep-link `/robo/:id?task=` (D-MTV-9), TRÊS estados distintos
  (vazio/409/erro — o 409 nunca vira vazio), mobile em cartões, `useMyTasksLive` (WorkspaceChannel).
  **Divergências:** status ENUM pt-BR (design usava placeholders `pending/...`); endpoint header-tenant
  (não `/workspaces/:id/my_tasks`); não-membro→403 (coleção, não 404); **`SET LOCAL enable_nestloop
  = off`** no service (a RLS `current_setting` faz o estimador dar `rows=1` e um nested loop de 28s no
  dataset de carga — hash join resolve). swagger allowlist +/api/v1/my_tasks. Decisões G1..G6 no EXECUCAO.
- **`commissioning-report`** (G0..G7, COMPLETA, full-stack, Onda 8+) — o Protocolo de
  Comissionamento (§3.8), o ÚNICO artefato formal (o cliente assina no aceite). Payload
  CONGELADO 100% no servidor (D-R1 — o cliente não soma, não escolhe autor, não gera id):
  `GET /api/v1/commissioning_report?scope=all|project` em **≤5 queries constantes**;
  carimbo = média do PONDERADO dos projetos (D15, nunca contagem crua); id
  `RT-AAAAMMDD-HHMM` no fuso (default America/Sao_Paulo), byte-idêntico em
  metadados/rodapé; 4 glifos fechados `✓ ◐ ○ —` num mapa único; histórico por
  `recorded_at` (created_at NÃO existe no payload); Conclusões com autoria = última
  entrada a 100 (`CompletionAuthorship`, DISTINCT ON) + 2 fallbacks; assinaturas SEMPRE
  vazias; TODOS os textos em `report.v1.*` resolvidos no servidor e entregues em
  `labels` (D-R9). Impressão = CSS `@page` A4 (D-R2), thead/tfoot repetidos (D-R3),
  tarefa+histórico indivisível como `<tbody .rpt-task>` (D-R4, limiar 18 → fatias com
  faixa anunciada), tema escuro neutralizado, shell des-clampado via `body:has(.rpt-doc)`.
  Volume `Reports::Budget` (2000 avisa / 5000 trunca a 10 por tarefa ANUNCIADO no
  documento / 8000 → 422 antes do payload). Tela: seletor de escopo, estados
  loading/erro/OFFLINE (listener — query pausada sem rede), imprimir. Testes: 43 specs
  backend (incl. carga 2.325/3.100 na fronteira avisa≠trunca) + sweeps i18n/glifos dos
  dois lados + **printToPDF real** (`frontend/scripts/print-report.mjs`, Playwright
  global + pypdf — páginas, cabeçalho/rodapé em todas, nenhuma tarefa partida).
  **Divergências:** endpoint header-tenant; não-membro→403 (middleware de tenant);
  sweep de literais em vitest (não há config ESLint no repo). Decisões G1..G7 no EXECUCAO.
- **`audit-log`** (G0..G8, COMPLETA, full-stack, Onda 8) — a trilha de auditoria
  **append-only, imutável no BANCO para todos inclusive o dono** (§4.1 inv. 3, a única
  invariante cujo adversário é o dono do dado). Desbloqueia o reset de fábrica D12 de
  `workspace-settings`. `audit_logs` PARTICIONADA por `RANGE(ts)` (PK `(ts,id)`), FK
  `workspaces ON DELETE RESTRICT`, SEM FK p/ hierarquia (sobrevive ao reset). Imutabilidade
  em 3 camadas: REVOKE UPDATE/DELETE do app (migration + roles.sql, caveat `pg_dump -x`) +
  trigger `BEFORE UPDATE/DELETE` (backstop do superuser) + RLS SEM policy de UPDATE/DELETE
  (filtra o dono p/ 0 linhas). **RLS NÃO cascateia às partições** → `secure_audit_partition()`
  por partição (fecha SELECT-direto-na-partição; reusada pelo job de retenção). Gatilho ÚNICO:
  conclusão a 100% grava na MESMA transação do avanço (`RecordService.record!` no seam de
  `CreateService`; log falho → rollback). `msg`/`ts_local` RENDERIZADOS e CONGELADOS no
  INSERT (Decisão 4); format strings versionadas `audit.*.vN` com snapshot-guard (editar vN
  publicada quebra o build). Leitura `GET /api/v1/audit_logs` (clamp 200, ts DESC, sem rota
  de escrita — fail-closed 500). Modal frontend (`AuditLogModal`, verbatim, teto 200) — monta
  na tela em `workspace-settings`. Retenção por DDL (`DETACH`+`DROP`, NUNCA `DELETE`):
  manutenção de partição + arquivamento verificado (JSONL.gz+manifesto count+checksum) +
  poda gated por verify E flag de 24m. **Divergências:** endpoint header-tenant; verbos de
  escrita fail-closam 500 (não 404); a trigger é backstop do superuser (RLS cobre o dono).
  **Dependências de entrega (delivery-and-observability):** bucket de storage frio, papel
  BYPASSRLS read-only p/ arquivamento cross-tenant, agendamento Sidekiq, alerta de queda de
  contagem. `paper_trail` recomendado p/ remoção (registrado em seal-template-baseline).
  Decisões G1..G8 no EXECUCAO. Suíte de contorno (9.2) reúne todos os vetores de burla.

Cada change tem seu `openspec/changes/<nome>/EXECUCAO.md` com o mapa de grupos, as
decisões tomadas na execução, as armadilhas encontradas e a CONCLUSÃO com o relatório
final. **Leia o EXECUCAO.md antes de tocar no código de uma change.**

## Onde parou: `workspace-settings` PARCIAL (G0..G4) → desvio para `hierarchy-soft-delete`

`workspace-settings` entregou G0..G4 (todos verdes): painel de **Equipe** (pessoas do
workspace como chips, arquivamento com guarda de membro ativo), tela do **catálogo** de
tarefas-base, e **exportar backup** (`RoboTrack_Database.json`, envelope `_rt`
schemaVersion 2 + checksum, síncrono/202). Esquema: `people.archived_at` (índice único
parcial), `workspace_backups` (RLS sem DELETE), 3 policies. Ver
`openspec/changes/workspace-settings/EXECUCAO.md`.

**G5/G6 PAUSADOS.** Ao mapear o reset de fábrica ANTES de codar, descobri que ele é
impossível como projetado: `task_advances` é imutável (progress-advances D-IMUT: REVOKE
DELETE + trigger para todos os papéis) e trava as tarefas com FK `ON DELETE RESTRICT`,
então `DELETE FROM projects` falha sempre que há avanços — a mesma classe de contradição
que a D12 resolveu para `audit_logs`. O reset tem de ARQUIVAR a hierarquia e preservar a
trilha imutável, o que exige o **soft-delete de hierarquia** primeiro. Decisão do cliente:
fazer `hierarchy-soft-delete` como change dedicada, depois voltar ao G5/G6.

**`audit-log` fechou antes** (8/8) — `audit_logs` append-only, imutável no BANCO para
todos inclusive o dono (§4.1 inv. 3), particionada por mês, 3 camadas (REVOKE + trigger +
RLS sem policy de mutação). Grava sozinho na conclusão a 100%; leitura clamp 200; modal
frontend pronto (monta em `workspace-settings`); retenção por DDL (nunca DELETE). Testado
(frontend **329/0**; backend `spec/audit` 51/0 isolado).

**Antes:** `commissioning-report` (COMPLETA, 8/8) — o Protocolo A4 assinável
(`/relatorio`; payload congelado, ≤5 queries, printToPDF real). E `my-tasks-view` (7/7)
— a lista pessoal (`/minhas-tarefas`; 409 identidade nunca vira vazio). E
`robot-task-table` (7/7) — a tela operacional do robô. E `hierarchy-screens` (7/7) —
as três telas de navegação + busca (D15). E `app-shell-navigation` (6/6) — a moldura
permanente + as convenções D9 (factory `qk.*`, guard, barreira de vazamento na troca de
workspace, sweep de convenção).

**Pendências conhecidas (documentadas, não atribuídas):**
- **design-system:** `tokens-campfire.css` + aliases shadcn seguem no repo (só vars
  da landing, ortogonais aos papéis). A remoção real (e a migração das classes
  shadcn → papéis) acontece quando `app-shell-navigation`/`hierarchy-screens`
  substituírem as páginas do template. `git tag pre-design-system-cleanup` (local)
  é o ponto de rollback do G8.
- **design-system:** p50 de frame da luz ambiente é medição de hardware (o CI trava
  só o determinístico) — job de perf de `delivery-and-observability` (HANDOFF lá).
- Tensão D-H6×D-IMUT (de progress-advances): hard delete de robô/projeto com
  tarefas que têm avanços daria 500 no trigger de imutabilidade. **EM CURSO:** a
  change `hierarchy-soft-delete` (atual) converte o delete físico da hierarquia em
  soft-delete, quitando esta pendência E destravando o reset de `workspace-settings`.
- Os p95 de latência de `progress-rollup` (120ms/25ms/8s) são alvo de hardware; o
  CI trava o NÚMERO de statements (determinístico) e mede latência com teto
  tolerante (EXECUCAO decisão 7). O job de perf real é de `delivery-and-observability`.
- `<ProgressRing>`/`<MetricStat>` existem (progress-rollup 6.2) mas a TELA que os
  monta (Visão Geral, hubs, cards) é de `hierarchy-screens`.

**Próximo passo — `hierarchy-soft-delete`** (pré-requisito destravado acima). Adiciona
`deleted_at` a `projects`/`cells`/`robots` com `default_scope` (espelhando `tasks`),
converte o delete físico da hierarquia (`Hierarchy::CrudService`) em soft-delete em
cascata, e blinda os leitores em SQL cru com `deleted_at IS NULL`. Depois volta-se ao
**`workspace-settings` G5/G6**: o reset passa a ARQUIVAR (não apagar), reusando
`AuditLog::RecordService.record!(event: :workspace_reset, …)` na transação e montando o
`AuditLogModal` em Utilitários. Alternativa geral: `realtime-collaboration` (D6).

## Depois de `workspace-settings` — o que resta

Próximas:
`realtime-collaboration`
(D6 — invalida as keys `['ws',wsId,'overview'|'project'|'cell'|…]` que hierarchy-screens já
declara), `offline-pwa`.

Ao montar telas, **use as convenções já vigentes**: leituras via hooks em `features/<dominio>/`
com a factory `qk.*` (o guard reprova key fora de `['ws', wsId, …]`); as telas (em `app/`) NÃO
importam `lib/api` direto — os DTOs vêm reexportados pela feature; mutations invalidam a chave
ESPECÍFICA (incl. o overview do nível), nunca o tenant inteiro; `createPortal` só em
`components/menu/`. Escreva o `EXECUCAO.md` (G0) antes de qualquer código. **Nota:** ao montar
telas, MIGRE as classes shadcn (`bg-primary`…) para os papéis (`bg-accent`…) e então remova os
aliases + `tokens-campfire.css` (parte adiada do G8 do design-system). `/` é a Visão Geral
autenticada; a landing do template ficou em `/apresentacao` (dívida do `seal-template-baseline`).

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
> entregue, onde parei e o método de trabalho. `robot-tasks`, `task-catalog`,
> `progress-advances`, `progress-rollup`, `design-system`, `app-shell-navigation`,
> `hierarchy-screens`, `robot-task-table`, `my-tasks-view`, `commissioning-report` e
> `audit-log` estão COMPLETAS (leia os EXECUCAO.md delas). Todo o BACKEND do núcleo, a BASE
> VISUAL, a MOLDURA + CONVENÇÕES, as TRÊS TELAS DE NAVEGAÇÃO (Visão Geral, Projeto, Célula) +
> busca, a TELA OPERACIONAL DO ROBÔ (`/robo/:id`), a LISTA PESSOAL (`/minhas-tarefas`), o
> PROTOCOLO DE COMISSIONAMENTO (`/relatorio`, A4 assinável) e a TRILHA DE AUDITORIA imutável
> (`audit_logs` + `AuditLogModal`, monta em Configurações) estão fechados de ponta a ponta.
> `/` já é a Visão Geral.
>
> Trabalhe na branch `audit-log` (as branches são empilhadas; ela contém tudo; full-stack). O
> próximo passo é **`workspace-settings`** (DESBLOQUEADA por `audit-log` — o reset de fábrica
> D12 reusa `AuditLog::RecordService.record!(event: :workspace_reset)` na transação do reset,
> e monta o `AuditLogModal` em Utilitários). Alternativa: `realtime-collaboration` (D6,
> invalida as keys `['ws', wsId, …]` que as telas já declaram). Depois
> `offline-pwa`. Comece pelo `EXECUCAO.md` da change (commit G0) — antes de qualquer código —
> e faça push por branch canônica (`git push origin HEAD:<change>`). Convenções vigentes:
> hooks em `features/<dominio>/` com a factory `qk.*` (o guard reprova key fora de
> `['ws', wsId, …]`), telas em `app/` NÃO importam `lib/api` (DTOs reexportados pela feature),
> invalidar a chave específica (nunca o tenant inteiro), `createPortal` só em `components/menu/`.
> Para RODAR/testar: provisione o banco (ver bloco no topo) e use `scratchpad/shot.mjs` p/ prints.
> Migrations rodam como `robotrack_migrator` (dono); a suíte como `robotrack_app`. NUNCA rodar
> duas suítes ao mesmo tempo (contenção de lock). DDL em teste (partições) NÃO é revertido pela
> truncation — limpe em `ensure`.
> Ao montar telas, migre as classes shadcn para os papéis e remova os aliases +
> `tokens-campfire.css` (a parte adiada do G8 do design-system).
>
> Siga o método: um grupo por vez, e ao fim de cada grupo me apresente um resumo e peça
> autorização antes de seguir para o próximo. Não regrida nenhuma das regras listadas na
> seção "Regras que não podem regredir".
