# EXECUCAO — commissioning-report

Mapa de execução. Escrito ANTES de qualquer código (commit G0). RETOMADA no fim.

## Ponto de partida

Branch empilhada sobre `my-tasks-view`. Onda 8+. FULL-STACK, **leitura pura** (nenhuma
migration, nenhuma escrita). Preenche o stub `ReportPage` (`/relatorio`, já roteado +
na sidebar). É o ÚNICO artefato FORMAL do sistema — o Protocolo de Comissionamento que
o cliente **assina no aceite**. Logo, todo número tem de ser defensável: um valor que
não bate com a tela, ou um horário que não bate com o ato, derruba o valor jurídico da
assinatura. Duas capabilities: `commissioning-report` (semântica) + `report-print-layout`
(contrato A4). Depende de `progress-rollup` (ponderado, D5/D15 — **leio, não recalculo**),
`progress-advances` (`task_advances`, `recorded_at`, `author_name_snapshot`, D8),
`commissioning-hierarchy` (árvore), `robot-tasks` (status/peso/assignees), `authorization-
policies` (D3), `design-system` (Inter/tabular-nums). Baseline: backend ~1008/0, frontend
296/0.

## RECONCILIAÇÃO COM A REALIDADE (crítico — ler antes de codar)

- **ENDPOINT = `GET /api/v1/commissioning_report?scope=all|project&project_id=`**, tenant
  pelo header `X-Workspace-Id` + RLS — NÃO `/workspaces/:workspace_id/commissioning_report`.
  Mesma divergência de my-tasks/hierarchy/projects (o app inteiro resolve tenant pelo
  header; `workspace_id` não é route param). Os cenários da spec citam o path do design —
  é prosa; o que importa é `scope`/`project_id`.
- **Não-membro → 403 (não 404)**: o gate NEGA a policy `read_workspace` p/ papel nil →
  403 (aprendido no my-tasks G3: 404 é para RECURSO RLS-invisível via `find_by(:id)`;
  coleção sem `:id` é 403). MAS `scope=project&project_id=<de outro ws>` → o projeto é
  RLS-invisível → `find_by` nil → **404** (esse é o 404 que 1.3/1.5 querem, e é real).
- **Carimbo lê `project.progress_cache`** (o ponderado %, smallint 0–100, materializado
  por progress-rollup) via a API pública (`ProgressMetric`/coluna), NUNCA SQL de progresso
  próprio. Stamp = `round(avg(progress_cache))` sobre os projetos do escopo.
- **`workspace.time_zone` NÃO existe** → default `America/Sao_Paulo`; `DocumentId.for(
  instant, time_zone)` recebe o fuso como PARÂMETRO (não vira refatoração quando
  workspace-tenancy expuser o campo). D-R6 já previu.
- **`qk.report` NÃO existe** em keys.ts → adiciono `report: (wsId, scope) => ['ws', wsId,
  'report', scope]` (D9).
- **Rota `/relatorio` + item "Relatório" na sidebar JÁ existem** (app-shell). 8.3 = trocar
  o stub pela tela.
- **`set_pagination_headers`/`ApiResponseHandler`/policies-PORO/base.rb-mount** — padrões
  já usados (my-tasks). Policy `ReportPolicy` com `show?: :read_workspace`.
- **Playwright global existe** (sem dep `@playwright/test`): o teste de impressão A4 (7.5,
  `Page.printToPDF` via CDP) roda no MESMO estilo do harness de screenshot
  (`/opt/node22/.../playwright`), não com `@playwright/test`. Registro.
- **`task_advances(task_id, recorded_at DESC…)` JÁ tem índice** (progress-advances) — o
  `DISTINCT ON`/`ANY(...)` da autoria e do histórico o reusa; nenhuma migration.

## Ordem dos grupos (G1 bloqueante; 2–5 paralelizáveis; 6 depende de 5; 7 fecha)

| Grupo | Escopo | Tarefas |
|---|---|---|
| **G1** | Contrato: `Api::Entities::CommissioningReport` + fixture JSON congelada; `Reports::CommissioningReportService` (escopo all/project, 400 p/ resto); endpoint + `ReportPolicy`; montagem ≤5 queries; specs de autorização (view 200 / não-membro 403 / projeto cross-tenant 404 / X-Skip-Auth 401 / RLS) | 1.1–1.5 |
| **G2** | Cabeçalho + **carimbo** (média do ponderado dos projetos; rótulo por %; dataset divergente D15 90≠50) | 2.1–2.4 |
| **G3** | Metadados + **id do documento** `RT-AAAAMMDD-HHMM` (servidor, fuso, congelado, byte-idêntico) | 3.1–3.3 |
| **G4** | Distribuição de status + os **4 glifos** `✓ ◐ ○ —` (conjunto fechado, 4 linhas sempre) | 4.1–4.3 |
| **G5** | Corpo hierárquico (projeto→célula→robô→tarefa) + histórico por tarefa (`recorded_at`, sem fallback p/ created_at) + **Conclusões** (`CompletionAuthorship`, 3 ramos) | 5.1–5.5, 6.1–6.4 |
| **G6** | Assinaturas + rodapé + **layout A4** (`@page`, thead/tfoot repetidos, `.rpt-task` indivisível, quebras) + teste Playwright printToPDF | 7.1–7.5 |
| **G7** | Volume/truncamento **anunciado** (`Reports::Budget`), i18n versionada (`report.v1.*`) + sweeps (literais/glifos), a **tela** + seletor de escopo, e2e de carga | 8.1–8.4 |

> Prints nos grupos visuais (G2+ têm marcação). Suíte backend completa no fim. §5+§6
> juntos no G5 (6 reusa o resolvedor de tarefa de 5).

## Decisões de desenho fixadas (design.md — não reabrir)

D-R1 payload CONGELADO montado 100% no servidor (o cliente NÃO deriva número: não soma,
não calcula média, não escolhe autor); D-R2 impressão = CSS `@page` no navegador, sem PDF
server-side; D-R3 cabeçalho/rodapé repetidos via `<thead>`/`<tfoot>` da tabela raiz (não
`position:fixed`); D-R4 unidade indivisível de quebra = `tarefa + todo o seu histórico`;
D-R5 carimbo = média simples do PONDERADO dos projetos (nunca contagem crua §3.2); D-R6 id
`RT-AAAAMMDD-HHMM` no servidor, fuso do workspace, não é chave; D-R7 autoria = última
entrada que chegou a 100 (`recorded_at DESC, created_at DESC`), fallback responsáveis →
traço; D-R8 volume com truncamento ANUNCIADO no documento (2000 avisa / 5000 trunca a 10
por tarefa / 8000 recusa 422); D-R9 texto fixo = format string versionada `report.v1.*`
resolvida no SERVIDOR; D-R10 4 glifos = conjunto fechado num mapa único; D-R11 execução
paralela a partir do contrato.

## Decisões que EU tomo aqui (LER)

1. **Endpoint header-tenant** `?scope=…` (ver reconciliação) — divergência do path.
2. **Não-membro 403 / projeto cross-tenant 404** (ver reconciliação); registro no G1.
3. **Carimbo lê `progress_cache`** (ponderado) — o spec 2.4 compara com recálculo do zero
   (`Progress::WeightedProgress`/views) para cache podre virar falha AQUI.
4. **Fuso default `America/Sao_Paulo`** com `time_zone` como parâmetro de `DocumentId.for`.
5. **§5+§6 no mesmo grupo (G5)** — 6 reusa o resolvedor de tarefa.
6. **Teste de impressão via Playwright GLOBAL** (printToPDF/CDP), estilo do harness de
   screenshot; não adiciono dep `@playwright/test` (no-heavy-deps).

## Armadilhas previstas

1. **Métrica errada no carimbo** — ponderado, NUNCA cru. Spec com dataset divergente
   (peso 9@100 + peso 1@0 → 90, não 50) é o guardião (2.4).
2. **Timestamp errado** — `recorded_at` sempre, `created_at` NÃO existe no payload (5.3).
3. **Autoria errada** — última entrada de 100 (não o responsável atual); trocar o
   responsável DEPOIS da conclusão é o caso que só o spec 6.4 pega.
4. **Cliente derivando número** — regra ESLint proíbe `reduce`/`Math.round` em
   `features/report/`; o servidor entrega tudo resolvido (D-R1/D-R9).
5. **N+1** — ≤5 queries constantes; `task_advances` por `ANY(...)` + window LIMIT; spec de
   contagem (1.4).
6. **Truncamento silencioso** — aviso DENTRO do documento impresso, nunca só toast (8.1).
7. **Emoji entrando pela porta do glifo** — sweep falha p/ qualquer char fora de
   `ASCII + {✓ ◐ ○ —}` no payload de textos (8.2).
8. **Quebra de página cortando tarefa/histórico** — `.rpt-task` indivisível; só o teste
   printToPDF (7.5) prova o CSS.

### Decisões tomadas na G1 (registro pós-execução)

- **Não-membro → 403 (não 404, corrigindo o G0)**: NÃO é o gate — é a RESOLUÇÃO DE
  TENANT (X-Workspace-Id) que barra o não-membro com `workspace_access_denied` ANTES
  do endpoint. Leak-free (corpo sem nome/contagens). O 404 da spec 1.5 para não-membro
  não é alcançável neste app; o isolamento (não vazar) está garantido pelo 403. O 404
  REAL é o do `scope=project` com projeto de outro ws (RLS → find_by nil).
- **Bind de array em `= ANY($1)`** não casta via `exec_query` (TypeError) → monto a
  lista de uuids quotada (`ANY(ARRAY[...]::uuid[])`); ids vêm do banco (trusted). Vale
  p/ `fetch_advances` e `CompletionAuthorship`.
- **Árvore = 1 query** (LEFT JOINs projetos→células→robôs), montada em Ruby → 5 queries
  totais (tree, tasks+assignees, advances, status_counts, authorship). Authorship só
  roda se houver tarefa a 100 (senão 4). Constante em N provado (q1==q8).
- **Fixture congelada** (`spec/fixtures/reports/commissioning_report.json`) com o shape
  completo; spec amarra o payload real a ela (mesmas chaves de topo).
- **Isenção D15 da my-tasks-view**: `MyTaskRow#progress` foi adicionado ao
  `PME_EXEMPT` do sweep de envelope (progresso de tarefa atômica, como `Task#progress`
  — não é métrica de rollup). Era a única falha da suíte cheia da my-tasks (1009/1→0).
- **swagger allowlist** ganhou `/api/v1/commissioning_report`.

## Protocolo por grupo

Aplicar → backend `rspec` dirigido (0 falhas) e/ou frontend `vitest`+`tsc` (0) → marcar
`- [x]` em tasks.md → `npx --yes @fission-ai/openspec@1.6.0 validate commissioning-report
--strict` → **um commit** `G<n>:` → print nos grupos visuais. Suíte backend completa no
fim. Banco a cada sessão (ver CONTINUIDADE) + `PATH=/opt/rbenv/shims`. NUNCA rodar duas
suítes ao mesmo tempo (contenção de lock no banco de teste — trava as duas).

## Progresso

- [x] G0 — este mapa (commit G0)
- [x] G1 — contrato + endpoint (1.1–1.5)
- [x] G2 — cabeçalho + carimbo (2.1–2.4)
- [x] G3 — metadados + id (3.1–3.3)
- [ ] G4 — distribuição + glifos (4.1–4.3)
- [ ] G5 — corpo + histórico + conclusões (5.1–5.5, 6.1–6.4)
- [ ] G6 — assinaturas + rodapé + impressão A4 (7.1–7.5)
- [ ] G7 — volume + i18n + tela + fechamento (8.1–8.4)

## RETOMADA (para o próximo agente)

1. `git log --oneline` na branch (empilhada em `my-tasks-view`); um commit por grupo.
2. LEIA a RECONCILIAÇÃO: endpoint header-tenant `?scope`, carimbo lê `progress_cache`
   (ponderado), fuso default, não-membro 403 / projeto cross-tenant 404.
3. Invioláveis: carimbo = média do PONDERADO (nunca cru); `recorded_at` (nunca
   created_at); autoria = última entrada de 100; cliente NÃO deriva número; ≤5 queries;
   truncamento ANUNCIADO; 4 glifos fechados; texto em `report.v1.*` no servidor.
4. Banco: provisionar (ver CONTINUIDADE) + `PATH=/opt/rbenv/shims`. UMA suíte por vez.
   Prints: `scratchpad/shot.mjs` (rota `/relatorio`).
