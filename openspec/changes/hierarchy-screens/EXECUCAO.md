# EXECUCAO — hierarchy-screens

Mapa de execução. Escrito ANTES de qualquer código (commit G0). RETOMADA no fim.
Decisões próprias e armadilhas registradas à medida que aparecem.

## Ponto de partida

Branch empilhada sobre `app-shell-navigation` (que fechou). Onda 7. FULL-STACK
(backend: 3–4 endpoints agregados + entities + services; frontend: 3 telas + busca).
Depende de `progress-rollup` (métricas + orçamento de query), `app-shell-navigation`
(shell, rotas, React Query + factory de keys + guard), `design-system` (Card, Hub,
ProgressRing, Badge), `commissioning-hierarchy` (esquema + CRUD), `authorization-policies`
(policy por endpoint). Baseline: backend 933/0/9pending; frontend 221/0; tsc/build limpos.

## Objetivo central

As três telas de navegação (Visão Geral, Projeto, Célula) + a busca (§3.7), cada uma
com hub analítico + grade de cards + estados vazio/carregando/erro. O CORAÇÃO é D15: as
DUAS métricas coexistem na mesma dobra — anel = **ponderado** (§2.1), hub = **contagem
crua** (§3.2) — nomeadas diferente na API e na UI, com teste sobre dataset que as faz
DIVERGIR (ponderado 40 ≠ crua 25). Custo de consulta constante em N (≤3 queries/tela).

## RECONCILIAÇÃO COM A REALIDADE (crítico — parte do backend já existe)

- **Visão Geral leve JÁ EXISTE**: `progress-rollup` entregou `GET /api/v1/projects/overview`
  (`Progress::OverviewQuery`, 2 queries) devolvendo `{ projects: [{id,name,position,
  weighted_progress}], raw_completion: {completed,total,percent} }`. → 2.1 vira ESTENDER
  esse endpoint (somar `cells_count` por projeto + as contagens globais do hub: Projetos
  ativos / Robôs analisados), mantendo o teto de 3 queries. NÃO crio `/workspaces/:id/overview`.
- **Tenant vem do HEADER `X-Workspace-Id`, não da URL.** Todo o domínio resolve o workspace
  pelo header (RLS, `Api::Root#before`). O proposal escreve `/workspaces/:id/overview` e
  `/ws/:wsId/...` — herança de um desenho pré-header. → Uso rotas SEM `:wsId` no path:
  backend `GET /projects/:id/overview`, `GET /cells/:id/overview`, `GET /search?q=`;
  frontend `/` (overview), `/projeto/:id`, `/celula/:id`. Divergência registrada (decisão 1/2).
- **Rotas do frontend já fixadas por `app-shell-navigation`**: `nav.ts` casa `/`, `/projeto`,
  `/celula`, `/robo`; `/` já é a Visão Geral autenticada (OverviewPage stub). → Preencho os
  stubs `OverviewPage` e crio `/projeto/:id` + `/celula/:id`. O robô (`/robo/:id`) é de
  `robot-task-table`; aqui só navego para lá.
- **Chaves de cache**: a factory `qk.*` de app-shell só tem até `robot`/`tasks`. Adiciono
  `qk.overview(wsId)`, `qk.projectOverview(wsId,id)`, `qk.cellOverview(wsId,id)` (a `qk.search`
  já existe). O guard exige a forma `['ws', wsId, …]` — as novas keys a respeitam.

## Ordem dos grupos

| Grupo | Escopo | Tarefas | Visual? |
|---|---|---|---|
| **G1** | Fixture divergente + contrato das duas métricas (entities sem `progress`, spec que caça a chave) | 1.1–1.3 | não (backend) |
| **G2** | Endpoints agregados: estender overview do workspace, project/cell overview, policies, isolamento 404, contador de queries | 2.1–2.6 | não (backend) |
| **G3** | Busca server-side (`ILIKE` escapado, `path_label` de locale, isolamento por RLS) | 3.1–3.3 | não (backend) |
| **G4** | **Tela Visão Geral**: hook, hub global rotulado, grade de cards de Projeto, vazio/carregando/erro, teste D15 | 4.1–4.6 | **SIM — 1º print** |
| **G5** | **Telas Projeto e Célula**: hubs, grades, ações CRUD ligadas (invalidação), vazios de nível, E2E de navegação | 5.1–5.6 | **SIM** |
| **G6** | **Busca na UI**: form role=search, hook com debounce/flush, substituição por termo, lista com caminho, testes | 6.1–6.5 | **SIM** |
| **G7** | a11y/responsivo/contraste AA/verificação final sobre a fixture divergente | 7.1–7.4 | ajustes |

> Nota ao cliente: G1–G3 são BACKEND (invisíveis, guiados por teste). Os **prints
> começam no G4** (Visão Geral) e continuam em G5/G6. Antes disso, mando um print da
> casca atual (baseline) para mostrar o ponto de partida.

## Decisões de desenho já fixadas (do design.md — não reabrir)

- **D-A** — duas métricas = dois campos com nomes distintos (`weighted_progress` int /
  `raw_completion {completed,total,percent}`). NUNCA um campo `progress`.
- **D-B** — rótulo textual é requisito: hub "de progresso físico global/físico", anel
  `aria-label "Progresso ponderado: N%"`. Teste sobre o texto renderizado, não a prop.
- **D-C** — 1 endpoint por tela, ≤3 queries, constante em N (contador de queries no CI).
- **D-D** — busca server-side, lista plana com `path_label` do servidor, `ILIKE` escapado
  (`%`,`_`,`\`), escopo por RLS (não `WHERE workspace_id`).
- **D-E** — busca substitui a visão por `isSearching = debouncedQuery.trim().length>0`
  (estado derivado, sem flag). Termo NÃO vai para a URL.
- **D-F** — 4 gatilhos, 1 submit: `<form role=search onSubmit>` + `<input type=search
  enterKeyHint=search inputMode=search>`; onSubmit dá preventDefault + flush do debounce.
- **D-G** — 3 estados vazios distintos (workspace sem projeto / nível sem filho / busca sem
  acerto que NOMEIA o termo); para `view` o CTA de criação não é renderizado.
- **D-H** — cards por §5.2: badge em linha própria, altura igual (`items-stretch`), anel 0%
  omite o traço. Componentes de design-system, não reimplementar.
- **D-I** — keys `['ws',wsId,'overview']`, `[...'project',id,'overview']`, `[...'cell',id,
  'overview']`, `[...'search',q]`; busca com `staleTime 30s` + `keepPreviousData`. Quem
  invalida no avanço é `realtime-collaboration`; aqui só declaro o conjunto.

## Decisões que EU tomo aqui (LER)

1. **Overview do workspace = ESTENDER `GET /api/v1/projects/overview`** (progress-rollup),
   não criar `/workspaces/:id/overview`. Somo `cells_count` por projeto e as contagens do hub
   (projetos ativos, robôs analisados) dentro do teto de 3 queries. Tenant pelo header.
2. **Rotas sem `:wsId` no path** (header resolve o tenant): backend `/projects/:id/overview`,
   `/cells/:id/overview`, `/search?q=`; frontend `/`, `/projeto/:id`, `/celula/:id`. Alinha
   ao que `app-shell-navigation` já fixou (`nav.ts`). Divergência do texto do proposal.
3. **Entities `HierarchyCard`/`AnalyticsHub`** como camada de contrato: exponho só
   `weighted_progress` e `raw_completion`; o spec de 1.3 varre as 3/4 respostas por `progress`
   em qualquer profundidade e falha se achar.
4. **Fixture `divergent_progress`** roda como `robotrack_app` (sem BYPASSRLS): cria via os
   services/cascade normais para o `progress_cache` sair correto (peso 5@100 + 3×peso1@0 →
   ponderado 40, crua 25). Se um seed cru deixar o cache 0, chamo `Progress::BulkRecompute`.
5. **`path_label` versionado em `config/locales/pt-BR.hierarchy.yml`** com guarda para o robô
   órfão de célula (nunca `"Robô · em  · "`).
6. **Consumo dos componentes de design-system** (EntityCard/Hub/ProgressRing/Badge). Se algum
   faltar prop necessária (ex.: rodapé "Visão macro / Acessar"), estendo o componente base em
   design-system de forma retrocompatível e registro — não reimplemento na tela.
7. **Overviews de nível ganharam `id`/`name` (e `lock_version` no card de célula) no G5.** As telas
   de Projeto/Célula precisam do NOME no cabeçalho e do `project_id` para o "voltar"; renomear célula
   exige o `lock_version`. Somei esses campos aos hashes dos services (adição retrocompatível, dentro
   do teto de 3 queries — são colunas do mesmo pluck/find). O contrato "sem `progress`" segue válido
   (o scanner não acha `progress`), e os specs de G2 seguiram verdes.
8. **Tipos de view reexportados pela feature.** As telas (em `app/pages/`) importam os DTOs de
   `features/hierarchy/useOverview` (que os reexpõe de `lib/api/endpoints`), NÃO de `lib/api` direto —
   o sweep de convenção reprova componente que importe a camada de API.

## Armadilhas previstas

1. **D15 (risco nº 1)**: alguém faz o anel ler `raw_completion`. Em dataset uniforme passa.
   A fixture divergente + o teste que exige "1/4"+"25%" no hub E "40%" no anel é o que trava.
2. **N+1 disfarçado**: um `map` com `cells.count`/`robots.count` dentro reintroduz N+1 sem
   mudar a resposta. O contador de queries (2.6) é obrigatório. Ler `progress_cache` da coluna.
3. **Escape do `ILIKE`**: sem escapar `%`/`_`/`\`, buscar `%` devolve o workspace inteiro.
   Testado (3.1).
4. **Rota `overview` casando como `:id`**: definir `get 'overview'`/`'search'` ANTES de
   `:id` no Grape (o projeto já faz isso com `overview`/`reorder`).
5. **Isolamento**: cross-tenant responde **404** byte-idêntico (nunca 403/nome vazado). Specs
   2.5 e 3.3. O escopo é a RLS, não o WHERE.
6. **Guard de key**: as novas keys de overview precisam de `wsId` não-vazio; hooks com
   `enabled: Boolean(wsId)` (tenant null = query desabilitada, tolerada pelo guard).

## Protocolo por grupo

Aplicar → backend `bundle exec rspec` (0 falhas, como `robotrack_app`) e/ou frontend
`pnpm exec vitest run` + `pnpm exec tsc --noEmit` (0 falhas) → marcar `- [x]` em tasks.md →
`npx --yes @fission-ai/openspec@1.6.0 validate hierarchy-screens --strict` → **um commit**
`G<n>:`. A partir do G4, **print da tela** a cada grupo. Divergência design×realidade:
decidir, registrar aqui, seguir.

## Progresso

- [x] G0 — este mapa (commit G0)
- [x] G1 — Fixture + contrato das métricas (1.1–1.3)
- [x] G2 — Endpoints agregados (2.1–2.6)
- [x] G3 — Busca server-side (3.1–3.3)
- [x] G4 — Tela Visão Geral (4.1–4.6) — 1º print
- [x] G5 — Telas Projeto e Célula (5.1–5.6)
- [x] G6 — Busca na UI (6.1–6.5)
- [x] G7 — a11y/responsivo/final (7.1–7.4)

## RETOMADA (para o próximo agente)

1. `git log --oneline` na branch (empilhada em `app-shell-navigation`); um commit por grupo.
   `tasks.md` tem o estado fino; este arquivo tem as decisões.
2. Baseline: backend `cd backend && bundle exec rspec` (como `robotrack_app`, `--seed 12345`);
   frontend `cd frontend && pnpm exec vitest run && pnpm exec tsc --noEmit`. pnpm.
3. LEIA a RECONCILIAÇÃO: a Visão Geral leve já existe (progress-rollup), tenant é header,
   rotas são pt-BR sem `:wsId`. Muita tarefa de G2 é ESTENDER/compor, não construir do zero.
4. Invioláveis: duas métricas com nomes distintos (nunca `progress`), ≤3 queries/tela,
   cross-tenant 404, busca por RLS, anel 0% sem traço, CTA de criação oculto para `view`.
5. Consumidores: `robot-task-table` (destino de "Abrir" no card do robô), `my-tasks-view`,
   `commissioning-report`, `quality-and-accessibility` (E2E + a11y), `offline-pwa`.

## Verificação final (7.4) — números medidos

- Frontend: **231 / 0** (vitest), tsc `--noEmit` limpo. Inclui o teste D15 (hub 25% ≠ anel
  40% rotulados na mesma tela), o E2E de navegação (Visão Geral→Projeto→Célula→voltar) e a
  busca ('sol' acha célula+robô, não a tarefa; 'xyz' vazio; limpar restaura).
- Backend (suíte da change): **49 / 0** — contrato das duas métricas (fixture divergente
  ponderado 40 ≠ crua 25 sob a fórmula real; nenhuma chave `progress`), overview (≤3 queries
  com 20×5×8, projeto vazio 200, robô N/A ponderado 100/raw 0), busca (escape do curinga,
  path_label, isolamento), e a varredura cross-tenant (os 3 endpoints geram 404 byte-idêntico).
- a11y/responsivo: grade em coluna única <640px; alvos de toque ≥32px (IconButtons + links
  de card min-h 2rem); busca com fonte ≥16px (sem zoom iOS), `aria-live` no contador e foco
  preservado no campo após buscar; contraste AA coberto pelo teste de tokens (as telas só
  compõem tokens auditados).
