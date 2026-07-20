# Tela do robô — tabela de tarefas

## Why

A `§3.5` da ESPECIFICACAO.md é a tela operacional principal do RoboTrack: é onde o
engenheiro de comissionamento passa a maior parte do turno, no celular, de luva, sob
luz de galpão. Todas as capacidades a montante (`commissioning-hierarchy`,
`robot-tasks`, `progress-advances`, `progress-rollup`) existem para alimentar esta
superfície; nenhuma delas é observável pelo usuário sem ela. Ela está no caminho
crítico e é pré-requisito direto de `offline-pwa` (Onda 9), que precisa de uma tela
real para exercitar atualização otimista e indicador honesto de gravação.

A tela também é a mais densa do produto: 6 colunas (`§3.5`), agrupamento por
categoria, dois avisos de estado incompleto, dois modais e um refluxo mobile
completo. O legado resolvia isso com uma função de render monolítica que reescrevia
a tabela inteira a cada mudança e mantinha o filtro em variável global — motivo pelo
qual o filtro **não** resetava de forma confiável entre navegações. O porte
reimplementa o comportamento descrito, não a implementação.

Cobertura: `§3.5` integralmente. Consome `§2.2` (máquina de estados), `§2.4` (modal
de avanço), `§2.3` (auto-atribuição), `§2.1` (progresso ponderado), `§2.6`
(sincronizar tarefas-base), `§4.1` (matriz de papéis), `§5.1`/DESIGN.md (componentes
e `successPulse`).

## What Changes

- **Cabeçalho do robô**: nome, badge de Aplicação, percentual consolidado
  **ponderado e rotulado como tal** (D15), e as ações "Adicionar tarefa" e
  "Sincronizar tarefas-base" (esta última dispara `§2.6`, cuja regra pertence a
  `task-catalog`; a tela apenas invoca e exibe o resultado "N tarefas adicionadas").
- **Filtro segmentado** Todos (padrão) · Pendentes · Concluídos, mantido em estado de
  cliente (Zustand, D9) e **resetado para "Todos" a cada navegação** — inclusive ao
  voltar para o mesmo robô. O filtro é derivado de `status`: Pendentes = `Pendente` +
  `Em Andamento`; Concluídos = `Concluído`. `N/A` aparece só em "Todos".
- **Tabela agrupada por Categoria** com linha separadora na troca de categoria,
  preservando a ordem persistida das tarefas dentro de cada grupo.
- **As 6 colunas** de `§3.5`: Tarefa, Status (StatusSelect com chevron obrigatório),
  Progresso (`−` / slider passo 5 / `+`, qualquer mudança abre o modal de avanço),
  Responsáveis (chips primários = responsáveis, chips secundários = contribuidores),
  Trilha (último comentário + contagem), Ações (editar descrição · excluir tarefa).
- **Dois avisos de estado incompleto**, não bloqueantes: "Atribuir…" quando
  `progress > 0` e zero responsáveis; "Registre o avanço…" quando
  `0 < progress < 100` e zero entradas de trilha.
- **Pulso de confirmação (`successPulse`)** na linha ao atingir 100%, respeitando
  `prefers-reduced-motion`.
- **Modal de histórico**: contribuidores + timeline mais-recente-primeiro com autor,
  `de% → para%`, data/hora (**`recorded_at`**, D8) e comentário; entradas legadas
  marcadas.
- **Modal de atribuição**: checkboxes com todas as `people` do workspace + campo de
  cadastro de pessoa nova, que entra já marcada e é persistida no workspace.
- **Refluxo mobile**: abaixo do breakpoint a tabela vira cartões empilhados, com
  todos os alvos de toque ≥ 32px.
- **Endpoints de leitura da tela**: `GET /api/v1/robots/:id/tasks` devolvendo, por
  tarefa, `assignees`, `contributors`, `advances_count` e `last_advance` já
  agregados — a tela nunca faz N+1 de trilha.

### Ajuste declarado à spec (BREAKING vs. `§3.5` literal)

`§3.5` condiciona o aviso de trilha faltando a "nenhum histórico **nem nota**",
onde "nota" é o campo legado `obs` (`§1.1`, `§1.4`). Por decisão de
`progress-advances`, o esquema novo **não tem `obs`**: a nota legada é convertida em
uma entrada de `task_advances` marcada `legacy: true` pelo importador
(`legacy-data-migration`). Portanto a condição do aviso passa a ser exclusivamente
`0 < progress < 100 AND advances_count = 0`. O comportamento observável para dado
migrado é idêntico (a nota vira entrada e suprime o aviso); o que muda é onde a
conversão acontece. Isto está registrado em `design.md` como decisão D-RTT-6.

### Não-objetivos

- **O modal de avanço em si** — gatilhos, `de → para`, comentário obrigatório
  `< 100`, máquina de estados `§2.2`, auto-atribuição `§2.3`, `lock_version`/409 —
  pertence a `progress-advances`. Esta capacidade **abre** o modal e **reage** ao seu
  resultado.
- **Cálculo de progresso** (ponderado e contagem crua) e `progress_cache`:
  `progress-rollup`. A tela exibe e rotula.
- **Componentes base** (StatusSelect com chevron, Chip, Modal, Badge, tokens de cor
  de status): `design-system`. Nada de componente ad-hoc nesta tela.
- **Esquema de `tasks` / `task_assignees`, CRUD de tarefa e criação em lote**:
  `robot-tasks`. Esta capacidade consome os endpoints e adiciona apenas o endpoint
  de leitura agregada da tela.
- **Regra de sincronização de tarefas-base** (`§2.6`): `task-catalog`.
- **Sidebar, topbar, seletor de workspace, indicador de gravação**:
  `app-shell-navigation`.
- **Fila offline e atualização otimista persistente**: `offline-pwa` (que depende
  desta capacidade).
- **Tempo real**: `realtime-collaboration` invalida as query keys que esta tela
  declara; a tela não abre canal próprio.
- **Busca, Minhas Tarefas, relatório**: capacidades próprias.

## Capabilities

### New Capabilities

- `robot-task-table`: cabeçalho do robô, filtro segmentado com reset na navegação,
  agrupamento por categoria, as 6 colunas, os 2 avisos de estado incompleto, pulso
  aos 100%, refluxo mobile e as negações por papel na tela.
- `task-collaboration-modals`: modal de histórico da tarefa (contribuidores +
  timeline por `recorded_at`, entradas legadas marcadas) e modal de atribuição
  (checkboxes de `people` do workspace + cadastro de pessoa nova).

### Modified Capabilities

Nenhuma.

### Impact

- **Backend**: um endpoint de leitura agregada (`Api::V1::RobotTasks#index`) +
  entity com `contributors`, `advances_count`, `last_advance`; um endpoint de
  criação de `Person` a partir do modal de atribuição (delegando a regra a
  `workspace-tenancy`); policies declaradas para ambos (D3).
- **Frontend**: nova feature-folder `frontend/src/features/robot-tasks/` com a
  tela, as colunas como componentes independentes, os dois modais e o store de
  filtro. Query keys `['ws', wsId, 'robot', robotId, 'tasks']` (D9).
- **Entrega**: nenhuma env var nova, nenhum serviço novo. Depende do adapter Redis
  do ActionCable em produção via `realtime-collaboration` — citado em
  `delivery-and-observability`, não introduzido aqui.
- **Risco de regressão**: esta é a superfície onde qualquer erro de `progress-rollup`
  ou `progress-advances` fica visível primeiro; os cenários negativos aqui servem
  como detector a jusante.
