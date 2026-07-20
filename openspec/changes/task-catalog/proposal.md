# Catálogo de tarefas-base do workspace (`task_templates`)

## Why

A ESPECIFICACAO.md descreve, em §1.1 ("Template de tarefa"), §1.2 (enum de Aplicações),
§1.3 (catálogo padrão de 31 itens em 9 categorias), §2.5 (regra de filtro de template),
§2.6 (sincronização retroativa) e §3.9 (CRUD do catálogo nas configurações), um
subsistema que é a **fonte de toda tarefa que existe no sistema**: nenhum robô nasce com
tarefas próprias — ele nasce com uma cópia do catálogo do workspace, filtrada pela sua
Aplicação. Sem catálogo, `robot-tasks` não tem o que copiar, `progress-rollup` não tem
denominador e o relatório de comissionamento não tem corpo.

No legado isso morava num array `defaultTasks` dentro do documento do workspace no
Firestore, sem tipo, sem unicidade, com o nome do campo de filtro tendo mudado no meio da
vida do produto (`apps` → `appFilters`, §1.4 item 3) e com duas strings sentinela
diferentes significando "vale para todas" (`"Misto / Geral"` e `"Todas"`, §2.5). Portar
isso para Postgres exige decidir explicitamente o que é dado, o que é sentinela e o que é
compatibilidade de leitura — em vez de arrastar o array como `jsonb` e replicar a
ambiguidade.

Esta capacidade entrega o **modelo, a API e as regras**. O layout da tela de configurações
(§3.9) pertence a `workspace-settings`, que consome esta API.

## What Changes

- **Nova tabela `task_templates`** (uuid PK gerável no cliente, D1/D13; `workspace_id`
  `NOT NULL` + RLS, D2) com `cat`, `desc`, `weight` (default `1`), `app_filters`
  (`text[]`, vazio = todas).
- **Enum fechado de Aplicações** (§1.2) expresso como tipo Postgres `robot_application`,
  com os seis valores: `Misto / Geral`, `Solda Ponto`, `Solda MIG`, `Handling`,
  `Sealing`, `Outros`. Único ponto de verdade do enum no backend; exportado ao frontend
  por um endpoint de metadados para não haver segunda lista hardcoded em TS.
- **Seed do catálogo padrão** (§1.3): os 31 templates exatos, em 9 categorias, todos com
  `weight: 1`. Apenas três desvios de "todas": `Calibração de Cola` → `[Sealing]`;
  `Check sinais de Gripper` → `[Handling, Solda Ponto]`; e nada mais. O seed roda no
  bootstrap de **todo workspace novo** (hook chamado por `workspace-tenancy`), não numa
  task de `db:seed` global.
- **Ordenação lexicográfica por prefixo** (§1.3, nota): o prefixo `A.`, `B.`, … é
  **preservado dentro da string `cat`** e é o critério de ordenação. Ver `design.md`
  para a alternativa descartada.
- **Serviço de filtro de template** (§2.5), único e compartilhado: um template se aplica a
  um robô se `app_filters` está vazio **OU** contém `"Misto / Geral"` **OU** contém
  `"Todas"` **OU** contém a Aplicação do robô. Consumido tanto por `robot-tasks` (criação
  em lote) quanto pela sincronização retroativa.
- **Compatibilidade legada** (§1.4 item 3): a API aceita `appFilters` **e** o nome antigo
  `apps` no corpo de escrita; sempre responde `appFilters`.
- **Sincronização retroativa por robô** (§2.6): endpoint que aplica os templates
  aplicáveis a um robô já existente, **nunca sobrescrevendo** — pula todo template cuja
  `desc` já exista nas tarefas daquele robô — e retorna a contagem de adicionadas.
- **CRUD de template** (§3.9), incluindo a regra de edição de filtro: escolher
  `Misto / Geral` **limpa** o filtro (grava array vazio).
- Autorização por policy object (D3): leitura para `owner`/`edit`/`view`; escrita e
  sincronização para `owner`/`edit` apenas (§4.1, linha "Editar catálogo de templates").

### Não-objetivos

- **Tela** do catálogo (tabela, formulário de novo template, seletor de aplicação) —
  `workspace-settings` (§3.9).
- **Criação de robôs em lote** e materialização das tarefas copiadas — `robot-tasks`
  (§2.5, primeira metade). Esta capacidade fornece o filtro e a lista resultante; quem
  escreve em `tasks` é `robot-tasks`.
- **Lista de responsáveis do workspace** (§3.9, "Equipe") — `workspace-tenancy` /
  `workspace-invitations`. O catálogo não tem responsável.
- **Peso no cálculo de progresso** — `progress-rollup` (§2.1). Aqui `weight` é só um
  número copiado.
- **Importação do `defaultTasks` legado** de um export Firestore —
  `legacy-data-migration` (§1.4). Esta capacidade só garante que o schema e a API
  toleram `apps`.
- Versionamento/histórico de alterações do catálogo, e propagação automática de edição de
  template para tarefas já criadas. Cópia é snapshot; editar um template **não** altera
  tarefas existentes. Sincronização é sempre explícita e aditiva.

### BREAKING

Nenhuma. Não há spec publicada nem código de produção sobre `task_templates`.

## Capabilities

### New Capabilities

- `task-template-catalog`: modelo `task_templates`, enum de Aplicação, seed dos 31
  padrões, regra de filtro §2.5, compatibilidade `apps`/`appFilters` e CRUD autorizado.
- `task-template-sync`: sincronização retroativa de tarefas-base para um robô existente
  (§2.6), aditiva e idempotente por `desc`.

### Modified Capabilities

(nenhuma)

### Impact

- **Depende de** `commissioning-hierarchy` (existência de `robots.application` e do
  escopo de workspace na hierarquia), que por sua vez depende de `authorization-policies`
  e `workspace-tenancy`.
- **Bloqueia** `robot-tasks` (Onda 4) — a criação em lote consome o serviço de filtro — e
  `workspace-settings` (Onda 8), que renderiza este CRUD.
- `workspace-tenancy` precisa chamar o seed no bootstrap do workspace; a aresta é
  explícita e está em `tasks.md`.
- **Entrega**: nenhuma env var, fila ou asset externo novo. O seed é síncrono no bootstrap
  (31 inserts num único `INSERT ... VALUES`), não precisa de Sidekiq. Nada a pedir a
  `delivery-and-observability`.
