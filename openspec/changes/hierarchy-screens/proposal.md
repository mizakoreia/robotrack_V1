# hierarchy-screens

## Why

A ESPECIFICACAO.md descreve três telas de navegação hierárquica — **§3.2 Visão Geral**,
**§3.3 Projeto**, **§3.4 Célula** — mais a **§3.7 Busca**, que vive dentro da Visão Geral.
São as telas que o engenheiro atravessa para chegar à tela operacional (§3.5): sem elas
não há caminho até o robô, e o progresso consolidado calculado por `progress-rollup`
não tem onde ser lido.

Estas telas são também o único lugar do produto onde as **duas métricas de progresso
coexistem na mesma dobra**: o anel de cada card usa o **progresso ponderado** (§2.1) e o
hub analítico usa a **contagem crua** de tarefas concluídas ÷ total (§3.2). O aviso da
própria spec (§2.1, nota final) e a decisão transversal **D15** existem por causa desta
tela. Um porte descuidado calcula um número só, preenche os dois lugares com ele, e
ninguém percebe — porque em datasets pequenos e homogêneos os valores coincidem.

O legado resolvia isso lendo documentos aninhados do Firestore inteiros no cliente e
somando em JavaScript. O porte lê o consolidado do servidor (coluna `progress_cache`,
D5) e não recalcula nada no navegador.

## What Changes

- **Tela Visão Geral** (`/ws/:wsId`): hub analítico global (Projetos ativos · Robôs
  analisados · Tarefas concluídas `concluídas/total`) + barra e percentual rotulados
  "de progresso físico global"; grade de cards de Projeto (ícone, nome, badge
  `N célula(s)`, anel de progresso **ponderado**, rodapé "Visão macro / Acessar");
  campo de busca; ação "Novo Projeto"; estado vazio dedicado com CTA.
- **Tela Projeto** (`/ws/:wsId/projects/:projectId`): hub analítico do projeto (Células
  configuradas · Robôs analisados · Tarefas concluídas); grade de cards de Célula (badge
  `N robô(s)`, anel, rodapé "Status global / Acessar"); ações nova célula, renomear e
  excluir célula, voltar.
- **Tela Célula** (`/ws/:wsId/cells/:cellId`): hub analítico da célula (Robôs
  configurados · Tarefas concluídas); grade de cards de Robô (badge = **Aplicação**,
  anel, rodapé `N tarefas`, "Abrir"); ação adicionar robô(s).
- **Busca (§3.7)**: campo na Visão Geral; enquanto há texto os resultados **substituem**
  hub e grade; substring case-insensitive sobre nomes de projeto, célula e robô (**não**
  busca tarefas); lista plana com ícone do tipo, nome e caminho; contador; estado vazio
  nomeando o termo; dispara por digitação ao vivo (com debounce), Enter, botão Buscar e
  pela tecla "buscar" do teclado mobile (`enterKeyHint="search"` dentro de um `<form>`
  com `role="search"`); botão limpar restaura a visão normal.
- **Rotulagem explícita das duas métricas** (D15) em toda superfície onde ambas
  aparecem, com teste sobre dataset em que elas **divergem**.
- **Endpoints de leitura agregada** em Grape (`GET /api/v1/workspaces/:id/overview`,
  `.../projects/:id/overview`, `.../cells/:id/overview`, `GET .../search?q=`), servindo
  contagens e progressos já consolidados — leitura, nunca cálculo no cliente.

### Não-objetivos

- **Cálculo de progresso.** Ponderado e contagem crua são de `progress-rollup` (D5);
  aqui só se consome e se rotula. Nenhuma soma de progresso roda no navegador.
- **CRUD de projeto/célula/robô.** Esquema, criação, renomeação, exclusão, `position` e
  drag&drop são de `commissioning-hierarchy` (§2.9). Estas telas apenas **acionam** os
  fluxos e reagem à invalidação de cache.
- **Assistente de criação de robôs em lote** (§2.5) — `robot-tasks`.
- **Componentes visuais.** Card, Anel de progresso, Barra do hub, Badge, Modal e tokens
  vêm de `design-system` (§5.2). Aqui se compõe, não se desenha.
- **Sidebar, topbar, seletor de workspace, indicador de gravação, convenção de query
  key** — `app-shell-navigation` (D9).
- **Busca em tarefas.** Excluída por spec (§3.7). Não é lacuna, é escopo.
- **Tempo real.** A invalidação por `WorkspaceChannel` é de `realtime-collaboration`
  (D6); estas telas só declaram as query keys que serão invalidadas.
- **Offline.** Comportamento de cache e fila é de `offline-pwa`.

Sem **BREAKING**: nada existe ainda para quebrar.

## Capabilities

### New Capabilities

- `hierarchy-navigation-screens`: as três telas de navegação (Visão Geral, Projeto,
  Célula), seus hubs analíticos, grades de card, estados vazios/carregando/erro, a
  rotulagem obrigatória das duas métricas (D15) e os endpoints agregados que as servem.
- `hierarchy-search`: a busca da Visão Geral (§3.7) — escopo, disparo, substituição da
  visão, resultado com caminho, contador, estado vazio e limpeza.

### Modified Capabilities

(nenhuma — `openspec/specs/` está vazio)

### Impact

- **Depende de** `progress-rollup` (métricas e orçamento de query), `app-shell-navigation`
  (shell, rotas, React Query), `design-system` (componentes), `commissioning-hierarchy`
  (esquema e CRUD), `authorization-policies` (policy por endpoint), `workspace-tenancy`
  (RLS/escopo).
- **É consumida por** `robot-task-table` (destino da navegação), `quality-and-accessibility`
  (E2E e a11y destas telas), `offline-pwa` (telas cacheadas).
- **Backend**: 4 endpoints Grape novos + entities + services agregadores; nenhuma
  migration própria.
- **Frontend**: 3 páginas, 1 componente de busca, hooks React Query com as keys
  `['ws', wsId, 'overview']`, `['ws', wsId, 'project', id, 'overview']`,
  `['ws', wsId, 'cell', id, 'overview']`, `['ws', wsId, 'search', q]`.
- **Entrega**: nenhum asset externo, fila ou env var nova (nada a pedir a
  `delivery-and-observability`), mas o dataset de carga de
  `quality-and-accessibility` precisa cobrir 50 projetos na Visão Geral.
