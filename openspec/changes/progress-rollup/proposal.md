## Why

A ESPECIFICACAO.md descreve **duas métricas de progresso que coexistem de propósito**:

- **§2.1 — progresso ponderado**, consolidado bottom-up (tarefa → robô → célula →
  projeto). Alimenta os anéis dos cards (§3.2, §3.3, §3.4) e o relatório de
  comissionamento (§3.8).
- **§3.2 — contagem crua**: `tarefas concluídas ÷ total de tarefas`, exibida nos
  hubs analíticos ("Tarefas concluídas `12/40`" + barra e percentual de "progresso
  físico global").

A própria spec avisa em §2.1: *"Os dois coexistem de propósito. Preservar ambos — ou
decidir conscientemente unificá-los."* A decisão transversal **D15** já resolveu:
**preservar ambos, sempre rotulados**. Esta capacidade é a dona de D15 e de **D5**
(cálculo em SQL na leitura **e** cache em `progress_cache`, com job de reconciliação).

O risco desta capacidade não é algoritmo difícil — é **unificação silenciosa**. A
consolidação de §2.1 mistura de propósito dois modos de média: **ponderada por peso
dentro do robô**, **aritmética simples acima do robô**. Um porte "limpo" tende a
propagar a ponderação para cima (célula ponderada pelo nº de tarefas dos robôs), o
que muda todos os números da tela sem quebrar nenhum teste que não tenha sido
escrito para pegar exatamente isso. O mesmo vale para os casos-limite assimétricos:
robô **sem tarefas → 0**, robô **com tarefas mas todas `N/A` → 100**.

No legado (PWA + Firestore) os dois números eram recalculados em JavaScript a cada
render, sobre documentos aninhados já carregados inteiros no cliente. O porte
relacional não pode fazer isso: a Visão Geral precisa do anel de N projetos de uma
vez, e cada anel depende de todas as tarefas da subárvore. É daí que vem o cache.

## What Changes

- **Duas funções de cálculo em SQL, nomeadas distintamente**, sem nenhuma
  reimplementação em Ruby ou TypeScript:
  - `rt_weighted_progress` (§2.1) — views `robot_weighted_progress`,
    `cell_weighted_progress`, `project_weighted_progress`.
  - `rt_raw_completion` (§3.2) — view `subtree_raw_completion` (concluídas, total,
    percentual) agregável em qualquer nível da hierarquia.
- **Coluna `progress_cache`** (`smallint NOT NULL DEFAULT 0`, `CHECK BETWEEN 0 AND 100`)
  em `robots`, `cells` e `projects`, guardando **apenas o ponderado**. A coluna
  **nasce nas migrations de `commissioning-hierarchy`** — não é retrofit. Esta
  capacidade entrega a semântica (quando escreve, quando invalida, quem recalcula);
  a coluna em si é uma dependência declarada, não uma migration nossa.
- **Recálculo em cascata dentro da transação do avanço**: `Progress::CascadeRecompute`
  atualiza robô → célula → projeto em ordem fixa, em 3 `UPDATE ... FROM` set-based.
  Ponto de integração único, chamado por `progress-advances`, `robot-tasks` e
  `commissioning-hierarchy`.
- **Caminho em massa**: `Progress::BulkRecompute` recalcula um workspace inteiro em
  3 statements, para importação legada, criação de robôs em lote e reconciliação.
- **`Progress::ReconciliationJob`**: compara `progress_cache` com o recálculo SQL por
  workspace, **corrige** as linhas divergentes e **alerta** com valor antigo, novo e
  contagem de linhas afetadas. O canal de alerta é entregue por
  `delivery-and-observability` — aqui só produzimos o evento.
- **Rotulagem obrigatória (D15)**: nenhum número de progresso é renderizado sem
  declarar qual das duas métricas é. Contrato de componente + sweep de teste no CI.
- **Orçamento de query** para a Visão Geral: **2 queries constantes**, independentes
  do nº de projetos, com dataset de carga e teste de contagem de queries que falha o
  CI em caso de N+1.

### Não-objetivos

- **Não** unificamos as duas métricas, nem "corrigimos" a média simples acima do
  robô para ponderada. Qualquer PR que faça isso deve falhar nos cenários abaixo.
- **Não** entregamos telas. Anéis, hubs, cards e estados vazios são de
  `hierarchy-screens`; a tabela do robô é de `robot-task-table`. Entregamos o dado,
  o rótulo obrigatório e o contrato do componente que os consome.
- **Não** entregamos a máquina de estados tarefa↔progresso (§2.2), a trilha
  append-only nem o `lock_version` — tudo isso é de `progress-advances`.
- **Não** entregamos o canal de alerta, o agendador de cron, o coletor de métricas
  nem o rastreio de erro — são de `delivery-and-observability`.
- **Não** entregamos as migrations de `projects`/`cells`/`robots`/`tasks` nem a
  coluna `progress_cache` em si — são de `commissioning-hierarchy` (D5).
- **Não** cacheamos a contagem crua. Ela é um agregado indexado barato; cachear
  duplicaria a superfície de invalidação sem ganho medido.
- **Não** há progresso "de pessoa" nem histórico temporal de progresso (série
  temporal / burndown). Fora do escopo do porte.

## Capabilities

### New Capabilities

- `progress-rollup`: as duas métricas em SQL, consolidação bottom-up de §2.1,
  semântica de `progress_cache` (escrita, invalidação, cascata em transação),
  recálculo em massa, job de reconciliação com alerta, e orçamento de query da
  Visão Geral.
- `progress-metric-labeling`: contrato transversal de D15 — toda exibição de um
  número de progresso declara e rotula qual métrica é, na UI, na API e no
  relatório; todo teste que exercita as duas usa um dataset onde elas divergem.

### Modified Capabilities

(nenhuma — `openspec/specs/` está vazio)

### Impact

- **Depende de** `progress-advances` (transação do avanço, `recorded_at`/D8),
  `robot-tasks` (peso, status, enum `N/A`), `commissioning-hierarchy` (hierarquia e
  a coluna `progress_cache` nas migrations), `workspace-tenancy` (RLS/D2 — todo
  recálculo roda sob `app.current_workspace_id`), `authorization-policies` (D3 — o
  endpoint de recálculo manual declara policy), `delivery-and-observability` (canal
  de alerta, agendamento Sidekiq em produção, métrica de divergência),
  `quality-and-accessibility` (D14 — strings dos rótulos em `pt-BR`; dataset de
  carga compartilhado).
- **É dependência de** `hierarchy-screens` (anéis e hubs), `commissioning-report`
  (§3.8 usa o ponderado), `robot-task-table` (§3.5 pulso aos 100%),
  `legacy-data-migration` (recálculo em massa pós-importação).
- **BREAKING**: nenhum — não existe consumidor construído. A quebra potencial é
  semântica e futura: alterar qualquer uma das regras de arredondamento, de média
  ou de caso-limite muda todos os números já exibidos ao usuário.
