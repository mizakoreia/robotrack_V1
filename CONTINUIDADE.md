# Continuidade — estado em 21/07/2026

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
                        └── design-system                     change COMPLETA — 8 de 8 grupos
                            └── app-shell-navigation (atual)  change COMPLETA — 6 de 6 grupos
```

**A branch atual contém todo o trabalho** (`app-shell-navigation` empilhada sobre
`design-system`; é frontend-only). É nela que se continua. Push por branch canônica
(`git push origin HEAD:app-shell-navigation`). Os PRs para a `main` podem ser abertos
depois, na ordem do empilhamento.

## Suítes (medidas na branch `app-shell-navigation`)

| Suíte | Resultado |
|---|---|
| Backend `bundle exec rspec` (como `robotrack_app`, `--seed 12345`) | **933 / 0 falhas / 9 pending** |
| Frontend `vitest run` | **221 / 0** |
| Frontend `tsc --noEmit` | limpo |
| Frontend `pnpm build` | limpo — bundle principal 388kB |

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

## Changes concluídas (12 de 24)

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

Cada change tem seu `openspec/changes/<nome>/EXECUCAO.md` com o mapa de grupos, as
decisões tomadas na execução, as armadilhas encontradas e a CONCLUSÃO com o relatório
final. **Leia o EXECUCAO.md antes de tocar no código de uma change.**

## Onde parou: `app-shell-navigation` COMPLETA; a moldura e as convenções fechadas

Fechou (6/6 grupos) — ver `openspec/changes/app-shell-navigation/EXECUCAO.md`. A
moldura permanente existe (AppShell: sidebar/topbar/gaveta, contexto de workspace,
menus em portal) E as convenções que desbloqueiam as telas: D9 (React Query padrão,
factory `qk.*`, guard ligado no `main.tsx`), a barreira CLIENTE de vazamento
(`switchWorkspace` = `clear()` na troca), o contrato do indicador de gravação
(`persistenceStore`), e o sweep de convenção no CI. Tudo testado (221 testes frontend).

**Antes:** `design-system` (COMPLETA, 8/8) — a base visual: token set único (dois
temas), contraste medido no CI, tipografia, ícones, empilhamento, tema (dark default),
9+ primitivos em `components/ui/`, luz ambiente, dívida do template removida.

**Pendências conhecidas (documentadas, não atribuídas):**
- **design-system:** `tokens-campfire.css` + aliases shadcn seguem no repo (só vars
  da landing, ortogonais aos papéis). A remoção real (e a migração das classes
  shadcn → papéis) acontece quando `app-shell-navigation`/`hierarchy-screens`
  substituírem as páginas do template. `git tag pre-design-system-cleanup` (local)
  é o ponto de rollback do G8.
- **design-system:** p50 de frame da luz ambiente é medição de hardware (o CI trava
  só o determinístico) — job de perf de `delivery-and-observability` (HANDOFF lá).
- Tensão D-H6×D-IMUT (de progress-advances): hard delete de robô/projeto com
  tarefas que têm avanços daria 500 no trigger de imutabilidade. Fix = soft-delete
  de hierarquia (follow-up em `commissioning-hierarchy`).
- Os p95 de latência de `progress-rollup` (120ms/25ms/8s) são alvo de hardware; o
  CI trava o NÚMERO de statements (determinístico) e mede latência com teto
  tolerante (EXECUCAO decisão 7). O job de perf real é de `delivery-and-observability`.
- `<ProgressRing>`/`<MetricStat>` existem (progress-rollup 6.2) mas a TELA que os
  monta (Visão Geral, hubs, cards) é de `hierarchy-screens`.

**Próximo passo — as telas de conteúdo.** O backend do núcleo (hierarquia + tarefas +
avanços + rollup), a base visual (`design-system`) e agora a moldura + convenções
(`app-shell-navigation`) estão fechados. Falta preencher os STUBS de destino. Ver abaixo.

## Depois de `app-shell-navigation` — as telas de conteúdo

A moldura e os contratos estão prontos. O caminho: **`hierarchy-screens`** (árvore de
projetos/células/robôs, Visão Geral com os anéis/hubs de `progress-rollup` — consome os
envelopes rotulados e os primitivos `EntityCard`/`Hub`/`ProgressRing`; preenche o stub
`OverviewPage`) → **`robot-task-table`** (a tabela do robô: CONSOME `progress-advances` —
reusa `<AdvanceControls>`, aviso "trilha faltando" com `advances_count` — e
`progress-rollup` — os envelopes). Também `my-tasks-view` (preenche `MyTasksPage`),
`workspace-settings`, `commissioning-report` (preenche `ReportPage`).

Ao montar telas, **use as convenções de `app-shell-navigation`**: leituras via hooks em
`features/<dominio>/api/` com a factory `qk.*` (o guard reprova key fora de `['ws', wsId, …]`);
mutations invalidam a chave ESPECÍFICA, nunca o tenant inteiro; nada de `createPortal` fora de
`components/menu/`; o indicador de gravação lê `persistenceStore`. Comece por
**`hierarchy-screens`** (maior valor, contratos prontos via HANDOFFs). Leia o
`proposal.md`/`design.md` e escreva o `EXECUCAO.md` (G0) antes de qualquer código.
**Nota:** ao montar telas, MIGRE as classes shadcn (`bg-primary`, `text-muted-foreground`…)
para os papéis (`bg-accent`, `text-text-muted`) e então remova os aliases +
`tokens-campfire.css` (a parte adiada do G8 do design-system). E `/` agora é a Visão Geral
autenticada — a landing do template ficou em `/apresentacao` (dívida do `seal-template-baseline`).

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
> `progress-advances`, `progress-rollup`, `design-system` e `app-shell-navigation` estão
> COMPLETAS (leia os EXECUCAO.md delas). Todo o BACKEND do núcleo (hierarquia, tarefas,
> catálogo, avanços, progresso consolidado), a BASE VISUAL (design-system) e a MOLDURA +
> CONVENÇÕES (app-shell-navigation: AppShell, D9/factory de keys + guard, barreira de
> vazamento na troca de workspace) estão fechados de ponta a ponta.
>
> Trabalhe na branch `app-shell-navigation` (as branches são empilhadas; ela contém tudo;
> é frontend-only). O próximo passo é PREENCHER OS STUBS DE TELA sobre a moldura:
> `hierarchy-screens` (Visão Geral, stub `OverviewPage`) → `robot-task-table` (+
> `my-tasks-view` no stub `MyTasksPage`, `workspace-settings`, `commissioning-report` no
> stub `ReportPage`). Escolha a próxima change, comece pelo `EXECUCAO.md` dela (commit G0)
> — antes de qualquer código — e faça push por branch canônica (`git push origin
> HEAD:<change>`). Use as convenções de `app-shell-navigation`: hooks em `features/*/api/`
> com a factory `qk.*` (o guard reprova key fora de `['ws', wsId, …]`), invalidar chave
> específica (nunca o tenant inteiro), `createPortal` só em `components/menu/`. Os contratos
> de dados estão nos `HANDOFF-*.md`; os primitivos de UI em `frontend/src/components/ui/`. Ao
> montar telas, migre as classes shadcn para os papéis e remova os aliases +
> `tokens-campfire.css` (a parte adiada do G8 do design-system).
>
> Siga o método: um grupo por vez, e ao fim de cada grupo me apresente um resumo e peça
> autorização antes de seguir para o próximo. Não regrida nenhuma das regras listadas na
> seção "Regras que não podem regredir".
