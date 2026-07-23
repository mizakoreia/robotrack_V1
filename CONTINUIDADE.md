# Continuidade — estado em 23/07/2026

Ponto de retomada do porte. Para uma sessão nova de agente, o prompt de partida
está em [PROMPT DE RETOMADA](#prompt-de-retomada), no fim.

## Onde está o trabalho (modelo de git ATUAL)

**Mudou desde as ondas iniciais: não é mais empilhamento de branches.** Agora:

- Todo o trabalho vive em `main` — **`main` é a versão mais atual** (tip `208b332`).
- O desenvolvimento acontece na branch de feature
  `claude/robotrack-task-catalog-tc-g3-6os4vm`, que é **fast-forwarded para `main`
  a cada grupo** e empurrada. No momento a feature e `main` apontam para o MESMO
  commit — nada pendente para mergear.
- Protocolo de push por grupo: commit `G<n>:` na feature → `git checkout main &&
  git merge --ff-only <feature>` → `git push -u origin main` → `git checkout
  <feature>`.
- **Branches remotas antigas** (as ~19 de capacidades já mergeadas) podem ser
  apagadas, MAS o `git push origin --delete` está bloqueado pelo classificador de
  permissão do ambiente — apagar pela UI do GitHub ou liberar a permissão Bash.

> **22 de 24 changes COMPLETAS.** Faltam só: `quality-and-accessibility` (gate de
> release — depende de um harness de CI/Playwright que NÃO existe no repo; seria
> entrega de config + specs + handoff) e `legacy-data-migration` (**BLOQUEADA** —
> falta o insumo `RoboTrack_Database.json`, o export de dados legado).

## Suítes (estado atual, na `main`)

| Suíte | Resultado |
|---|---|
| Frontend `vitest run` | **527 / 0** |
| Frontend `tsc --noEmit` / `npm run lint` | limpos |
| Backend `rspec` (por capacidade; suíte dirigida por grupo) | verde em cada grupo entregue (ex.: notifications+ops+advances+sweeps 155/0; governança/health 277/0) |

> **Ambiente (container efêmero — refazer a cada sessão):**
> - **Postgres CAI com frequência** ("Connection refused" na 5432): reinicie com
>   `pg_ctlcluster 16 main start`. Migrations como `robotrack_migrator`
>   (`DATABASE_URL="postgres://robotrack_migrator:mig_dev_pw@localhost/robotrack_<dev|test>"`);
>   a suíte roda como `robotrack_app` (default do `database.yml`).
> - **Redis:** instalado; subir com `redis-server --daemonize yes` quando um spec
>   precisar (dedup de alerta, rack-attack, topologia). Já foi subido nesta sessão.
> - **Ruby:** `export PATH="/opt/rbenv/versions/3.2.3/bin:$PATH"` (o 3.3 sombreia).
> - **Frontend:** usa **npm** (`npm run lint`, `npx vitest run`, `npx tsc`). Há
>   `.eslintrc.cjs` mínimo (guarda de storage + `new Notification`).
> - **Sem daemon Docker** (smokes de deploy = handoff). **Sem Playwright local**
>   (E2E são integração RTL/`fake-indexeddb`; screenshots via Chromium headless em
>   `/opt/pw-browsers/chromium_headless_shell-*/chrome-linux/headless_shell
>   --screenshot`).
> - **Assinatura de commit IMPOSSÍVEL** (sem chave em `/home/claude/.ssh/` e sem
>   `ssh-keygen`): todos os commits saem "Unverified". O e-mail JÁ é
>   `noreply@anthropic.com` — é limitação de ambiente, não erro. O stop-hook avisa
>   toda vez; não há ação a tomar.

## Changes concluídas (22 de 24)

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
  (vazio/409/erro — o 409 nunca vira vazio), mobile em cartões. Ao vivo NÃO por um hook próprio
  (`useMyTasksLive` nunca existiu): a lista é invalidada pelo cliente de tempo real (`useRealtime` →
  `WorkspaceChannel`), cujo `eventMap` invalida `['ws',w,'my-tasks']` em `task.*`/`task_advance.created`.
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
- **`hierarchy-soft-delete`** (G0..G4, COMPLETA, backend-only) — estende o soft-delete que só
  existia em `tasks` para `projects`/`cells`/`robots`, fechando a tensão **D-H6×D-IMUT**
  (excluir robô/projeto com avanços dava 500: a FK `task_advances→tasks` é `ON DELETE
  RESTRICT` e a trilha é imutável) e DESBLOQUEANDO o reset de fábrica de `workspace-settings`.
  `deleted_at` nas 3 tabelas + `default_scope` (espelha `Task`); `position` NULLABLE zerada no
  soft-delete (D1 — sai do domínio da constraint DEFERRABLE de posição, sem tocá-la); índices
  únicos de nome viram PARCIAIS `WHERE deleted_at IS NULL` (nome reusável, D2); as 4 views de
  progresso recriadas excluindo a hierarquia arquivada (D5 — senão o arquivado arrasta a
  média). `Hierarchy::SoftDeleteService` arquiva a subárvore (tarefas→robôs→células→nó) num
  UPDATE por nível + remove `task_assignees`; `CrudService#destroy` chama-o no lugar de
  `destroy!`, preservando auditoria+recompute na transação e o **204**. Blindagem dos leitores
  em SQL cru (D6): relatório/minhas-tarefas/cache_dump/reconciliação filtram `deleted_at`;
  agregadores por JOIN de associação (overview/project-overview) filtram no **ON do LEFT JOIN**
  (para o pai sem filho vivo ainda aparecer com contagem 0); busca filtra o lado juntado no
  WHERE; `cascade_recompute` NÃO filtra (navega ao pai a recalcular). **Reconciliações:**
  corrigido falso positivo do sweep de escrita de progresso (`WorkspaceBackup.status`, latente
  desde workspace-settings G4) e falha pré-existente do relatório (listava tarefa excluída
  individualmente — `t.deleted_at` agora filtrado). Decisões D1–D7 no EXECUCAO.

- **`workspace-settings`** (G0..G6, COMPLETA) — Equipe/catálogo/backup + reset de fábrica
  (D12) que ARQUIVA via `Hierarchy::SoftDeleteService` (não apaga), gates
  frase/backup≤15min/consumo CAS, auditoria `workspace_reset.v1` na transação, endpoint
  owner-only atrás de `FEATURE_FACTORY_RESET`. Tela `/configuracoes` (PeoplePanel/
  CatalogPanel/AppearancePanel/Utilitários + AuditLogModal). Pendings 5.9 (broadcast) e
  5.10 (alerta) quitados pelas ondas seguintes.
- **`realtime-collaboration`** (G0..G9, COMPLETA, full-stack, Onda D6) — tempo real por
  ActionCable. Backend: tickets de Cable opacos de uso único (Redis SETEX/GETDEL 60s),
  `WorkspaceChannel` por workspace com auth por membership + reverificação por entrega,
  envelopes de PONTEIRO (`{v,seq,workspace_id,type,entity,scope,actor_person_id,origin_id,
  at}` — sem conteúdo), `workspaces.realtime_seq` monotônico (UPDATE...RETURNING) p/ gap,
  `RealtimePublishable` (after_*_commit), `/sync` (janela 10min). Frontend: máquina de
  transporte (connecting|live|degraded|offline, backoff com ticket FRESCO), factory de
  keys D9, fila de invalidação com GATE de represamento (defere invalidações que
  intersectam mutationKeys em voo), poller do modo degradado, indicador de conexão,
  revogação viva (self-revocation). Handoffs: header do `/sw.js`, métricas de transporte.
- **`offline-pwa`** (G0..G8, COMPLETA, full-stack, Onda D7) — o que o Firestore dava de
  graça, agora de primeira classe. `safeStorage` com NÍVEIS (persistent/session-only/
  memory-only) + sonda de boot + aviso D7-11; service worker (`public/sw.js` network-first,
  guarda de não-interceptação, CACHE_NAME por plugin do Vite, aviso de nova versão); FILA
  de mutations em IndexedDB (`idb`; log de comandos, `depends_on`, `recorded_at` no
  enfileiramento, teto 500/5MB); grafo de dependência + drenagem sequencial (1 em voo,
  sonda `HEAD /api/v1/health`); classificação D7-5 (retry/permanente/conflito/auth, DELETE
  404=sucesso) + backoff + cascata de bloqueio + reconciliação; líder por `navigator.locks`
  + fallback IndexedDB + `BroadcastChannel`; **overlay** otimista DERIVADO DA FILA (vence
  evento ao vivo, sobrevive a remount) + indicador honesto (pendente/bloqueado) + probe
  `hasPendingFor` ligado ao gate de D6; export/migração versionada. **SEAM aberto:** os
  hooks de mutação (`useRecordAdvance`/`useHierarchy`) ainda NÃO enfileiram offline nem
  saiu o `setQueryData` — a máquina está pronta e provada (E2E de honestidade temporal),
  falta flipar os hooks. Backend: só `HEAD /api/v1/health`.
- **`delivery-and-observability`** (G0..G8, COMPLETA, backend+config, Onda D11) — a infra
  que todo o domínio assume. Registro único de env (`config/env_schema.rb`) + guarda de
  boot; Dockerfile prod (não-root, HEALTHCHECK, sem assets), Procfile/bin/release (migrate
  sob lock), `/health/live`+`/ready`; isolamento de Redis por função + guarda de topologia;
  contrato de cache do PWA (`frontend/nginx.conf`); Sentry (scrubbing/PII) + lograge JSON +
  `/metrics` por token; `Ops::AlertService` (dedup atômico, roteamento, blindagem) +
  condições; partição de `audit_logs` + retenção/expurgo (`Ops::RetentionPurge`,
  `AuditPartitionMaintenance`); rate limit por classe/identidade (rack-attack Redis);
  runbook de rollback + guarda de migration `contract` + backup verificado. **HANDOFFS de
  deploy** (docker-compose staging smoke, CDN, ingestão Sentry, ensaio de rollback) — code+
  config+spec entregues, execução real é do deploy. Registrados no EXECUCAO (FECHAMENTO).
- **`in-app-notifications`** (G0..G8, COMPLETA, full-stack, Onda D-N) — notificações
  assign/progress/done. Banco: enum + tabela `notifications` (D-N2), invariantes 4 e 8 em
  TRIGGER/CHECK (read=true no INSERT falha; UPDATE só read/read_at; sem read:true→false),
  RLS, índice único de idempotência de assign. `MessageBuilder` (locale v1, trunca só
  `%{comment}`), `RecipientResolver` (delta/todos − autor), `EventClassifier`,
  `CreateService` (idempotente sob unique), `NotifyTaskEventJob` (fila :notifications) ligado
  por subscriber aos eventos PÓS-commit (best-effort — Redis fora não derruba o save). API
  (listagem escopada por destinatário + header de não-lidas, POST :id/read + read_all, SEM
  PATCH genérico), `NotificationPolicy` (a PRÓPRIA). Frontend: `useNotifications` (D9),
  `NotificationCenter`, `ctxToPath`, e **alerta do SO com marca d'água EM MEMÓRIA** (reload
  com pendências antigas → 0 alertas — o modo de falha desta capacidade) + regra de lint
  proibindo `new Notification(` fora do hook único. Retenção `Notification.purgeable` (o
  cron mora em D11).

Cada change tem seu `openspec/changes/<nome>/EXECUCAO.md` com o mapa de grupos, as
decisões tomadas na execução, as armadilhas encontradas e a CONCLUSÃO com o relatório
final. **Leia o EXECUCAO.md antes de tocar no código de uma change.**

## Onde parou: 5 waves fechadas nesta sessão; 2 restam

Nesta sessão fecharam, em ordem: **`workspace-settings`** (reset de fábrica que
arquiva), **`realtime-collaboration`** (D6, ActionCable), **`offline-pwa`** (D7,
fila offline + SW + overlay), **`delivery-and-observability`** (D11, infra/observab.)
e **`in-app-notifications`** (D-N). Cada uma seguiu o protocolo por grupo (G0
reconciliação → grupo a grupo → commit `G<n>:` → ff `main` → push) e tem seu
`EXECUCAO.md`. Tudo na `main` (`208b332`).

## O que resta (2 de 24)

- **`quality-and-accessibility`** (Onda 10, gate de release) — depende de TODAS as
  telas (prontas) mas o PROPRIO proposal diz que NÃO entrega o pipeline de CI, os
  runners nem o harness Playwright. Neste ambiente não há Docker daemon nem
  Playwright local. Entregável realista: orçamento de query por tela, sweeps de
  a11y, specs de integração + a config, com o harness Playwright/WebKit e o
  pipeline de CI como **handoff** (mesmo padrão dos handoffs de deploy do D11 e do
  Playwright do realtime/offline). Vários handoffs de outras ondas apontam para
  cá (E2E offline Chromium+WebKit, etc.).
- **`legacy-data-migration`** — **BLOQUEADA por insumo ausente**: o proposal declara
  que o arquivo `RoboTrack_Database.json` (o export do Firestore legado) **não foi
  fornecido**. Sem ele, a migração real não roda. Dá para entregar o esquema do
  importador + os validadores + specs contra fixtures sintéticas, mas a execução
  fim-a-fim precisa do arquivo. **Peça o arquivo ao cliente antes de começar.**

**SEAMS/handoffs abertos que valem lembrar:**
- **offline-pwa:** flipar `useRecordAdvance`/`useHierarchy` para ENFILEIRAR quando
  offline + retirar o `setQueryData` (a máquina — fila/drenagem/overlay/indicador —
  está pronta e provada; falta a última fiação dos hooks de mutação). É uma mudança
  de fluxo central; merece sua própria rodada com testes.
- **delivery-and-observability:** smokes de deploy (docker-compose staging, CDN,
  Sentry real, ensaio de rollback em staging) — artefatos entregues, execução é do
  primeiro deploy real. Ver FECHAMENTO no EXECUCAO da change.
- **Branches remotas antigas** (~19) prontas para apagar; o `git push --delete` está
  bloqueado pela política de permissão (apagar pela UI do GitHub ou liberar a
  permissão).

**Convenções vigentes (não regredir ao montar mais telas):** leituras via hooks em
`features/<dominio>/` com a factory `qk.*` (o guard reprova key fora de
`['ws', wsId, …]`); telas em `app/` NÃO importam `lib/api` direto (DTOs reexportados
pela feature); mutations invalidam a chave ESPECÍFICA, nunca o tenant inteiro;
`createPortal` só em `components/menu/`; `new Notification(` só no hook de alerta do
SO (regra de lint); storage só por `lib/safeStorage` (regra de lint).

## Método (não abrir mão)

1. Uma change por vez, na branch de trabalho, **fast-forwarded para `main` a cada
   grupo** (`main` é a versão mais atual — não há mais empilhamento de branches).
2. **Antes de qualquer código**, escrever `openspec/changes/<change>/EXECUCAO.md`
   RECONCILIANDO o design com a REALIDADE do repo (o que já existe/evoluiu, o que é
   handoff), com o mapa de grupos, decisões e armadilhas previstas — commit `G0`.
3. Executar grupo a grupo. Por grupo: aplicar → specs dirigidos (0 falhas) → marcar
   `- [x]` em `tasks.md` → `npx --yes @fission-ai/openspec@1.6.0 validate <change>
   --strict` → **um commit** `G<n>: ...` → ff `main` + push.
4. Ao fim de cada grupo: resumo pt-BR client-friendly (cliente não-expert). Em lotes
   autorizados ("vai até G4"), seguir sem pausar; senão, pedir autorização.
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

Migrations rodam como `robotrack_migrator`; a suíte roda como `robotrack_app` (default do
`database.yml`, que já usa `DATABASE_URL` em todos os ambientes). Detalhes em
[backend/db/PROVISIONING.md](backend/db/PROVISIONING.md):

```bash
# Postgres cai com frequência — reinicie quando "Connection refused":
pg_ctlcluster 16 main start

export PATH="/opt/rbenv/versions/3.2.3/bin:$PATH"   # ruby 3.2.3 (o 3.3 sombreia)
cd backend
MIG_DEV="postgres://robotrack_migrator:mig_dev_pw@localhost/robotrack_dev"
MIG_TEST="postgres://robotrack_migrator:mig_dev_pw@localhost/robotrack_test"
RAILS_ENV=development DATABASE_URL=$MIG_DEV  bundle exec rails db:migrate
RAILS_ENV=test        DATABASE_URL=$MIG_TEST bundle exec rails db:migrate
redis-server --daemonize yes    # quando um spec precisar de Redis
RAILS_ENV=test bundle exec rspec spec/<capacidade>/   # rode DIRIGIDO por capacidade

cd ../frontend
npm run lint && npx tsc --noEmit && npx vitest run    # frontend usa NPM (há .eslintrc.cjs)
```

Screenshots de algo gráfico: Chromium headless em
`/opt/pw-browsers/chromium_headless_shell-*/chrome-linux/headless_shell --screenshot`
sobre um HTML no scratchpad (não há Playwright local). Validação de spec OpenSpec:
`npx --yes @fission-ai/openspec@1.6.0 validate <change> --strict`.

## PROMPT DE RETOMADA

> Estou continuando o desenvolvimento do RoboTrack (github.com/mizakoreia/robotrack_V1):
> reimplementação de um sistema legado (PWA + Firestore) sobre um template Rails 8
> API-only + React 18/TS, organizada com OpenSpec — 24 changes em `openspec/changes/`.
>
> Leia `CONTINUIDADE.md` na raiz: tem o estado atual, o modelo de git, o que já foi
> entregue e o método. **22 das 24 changes estão COMPLETAS** — todo o backend do núcleo,
> a base visual, a moldura, as telas (Visão Geral/Projeto/Célula, `/robo/:id`,
> `/minhas-tarefas`, `/relatorio`, `/configuracoes`), a auditoria imutável, o **tempo
> real** (ActionCable), a **fila offline** (PWA), a **infra/observabilidade** e as
> **notificações**. Tudo na `main` (`208b332`); a branch de trabalho
> `claude/robotrack-task-catalog-tc-g3-6os4vm` aponta para o mesmo commit da `main`.
>
> **Restam 2 changes:** `quality-and-accessibility` (gate de release — o harness de
> CI/Playwright NÃO existe no repo e não há Docker/Playwright neste ambiente; entrega
> realista = specs de integração + config + handoff do harness) e `legacy-data-migration`
> (**BLOQUEADA** — falta o insumo `RoboTrack_Database.json`; peça o arquivo ao cliente
> antes de começar).
>
> **Método (mantido):** uma change por vez; ANTES de qualquer código escreva
> `openspec/changes/<change>/EXECUCAO.md` reconciliando o design com a REALIDADE do repo
> (muita coisa já evoluiu além do que o design assume) — commit `G0`. Depois grupo a
> grupo: aplicar → specs dirigidos 0 falhas (suba Postgres/Redis quando preciso, NUNCA
> duas suítes ao mesmo tempo) → marcar `- [x]` em `tasks.md` → `validate --strict` → UM
> commit `G<n>:` → `git checkout main && git merge --ff-only <feature> && git push -u
> origin main && git checkout <feature>` → resumo pt-BR client-friendly ao cliente
> (não-expert) → seguir. Verificações que exigem deploy real/harness ausente viram
> HANDOFF documentado (padrão da casa). Commits terminam com o rodapé
> `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` + a linha de sessão; NÃO
> inclua o id do modelo. Assinatura de commit é impossível neste ambiente (sem chave) —
> os "Unverified" do stop-hook são esperados, sem ação.
>
> Convenções (não regredir): hooks em `features/<dominio>/` com a factory `qk.*` (guard
> reprova key fora de `['ws', wsId, …]`); telas em `app/` não importam `lib/api`;
> invalidar a chave específica; `createPortal` só em `components/menu/`; `new
> Notification(` só no hook de alerta do SO; storage só por `lib/safeStorage`. As regras
> de banco (RLS forçada como `robotrack_app` sem BYPASSRLS, invariantes em trigger/CHECK,
> vazamento cross-tenant = 404) estão na seção "Regras que não podem regredir".
