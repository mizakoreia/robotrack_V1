# EXECUCAO — progress-rollup

Mapa de execução desta change. Escrito ANTES de qualquer código (commit G0).
RETOMADA no fim. Decisões próprias e armadilhas registradas à medida que aparecem.

## Ponto de partida

Branch empilhada sobre `progress-advances` (que já fechou). O núcleo da Tarefa e a
trilha de avanço existem de ponta a ponta. Esta change entrega **as duas métricas
de progresso** (§2.1 ponderada e §3.2 contagem crua), o cache `progress_cache`
(escrita em cascata na transação da mutação), o job de reconciliação e a rotulagem
obrigatória D15 — **sem telas** (anéis/hubs são de `hierarchy-screens`).

Baseline medido: backend 877/0/9pending; frontend 95/0; tsc limpo.

## Objetivo central

Uma única definição executável de cada métrica, **em SQL, sem gêmeo Ruby/TS**. Cache
correto por construção no caminho quente e **detectável** quando não for. Custo de
leitura da Visão Geral constante no nº de projetos. Impossível renderizar um número
sem dizer qual métrica é (D15, sweep executável, não convenção).

## Ordem dos grupos

| Grupo | Escopo | Tarefas |
|---|---|---|
| **G1** | Esquema + cálculo em SQL: migration corretiva do `progress_cache`, 4 views, índice parcial, dataset de divergência, suíte SQL dos números literais | 1.1–1.6 |
| **G2** | Cache em cascata: `CascadeRecompute` (3 UPDATE em ordem fixa), ligação à transação do avanço/CRUD de tarefa/CRUD-mover de hierarquia, `without_cascade` + `BulkRecompute`, sweep do ponto de entrada único, e2e da cascata | 2.1–2.7 |
| **G3** | Leitura, envelopes e orçamento: envelopes `weighted_progress`/`raw_completion`, sweep de entidades, dataset de carga (93k tarefas), `issue_at_most(n).queries`, orçamentos de latência | 3.1–3.6 |
| **G4** | Reconciliação e observabilidade: `ReconciliationJob` (corrige+alerta, sob RLS), consumo de `Observability::Alert`/métrica com checagem de boot, endpoint de recálculo manual (policy) | 4.1–4.6 |
| **G5** | Backfill de dado importado: dump prévio, `BulkRecompute` no fim do importador legado, spec de zero-divergência pós-import | 5.1–5.3 |
| **G6** | Rotulagem D15: locales pt-BR + módulo TS + lint, props `metric` obrigatórias, sweeps de rótulo, contrato do relatório, tela da Visão Geral | 6.1–6.5 |

## Decisões de desenho já fixadas (do design.md — não reabrir)

- **D5.a** — cálculo canônico em SQL, sem implementação Ruby. Views: `robot_weighted_progress`,
  `cell_weighted_progress`, `project_weighted_progress`, `subtree_raw_completion`. `ROUND` sobre
  `numeric`, nunca `float`. Arredondamento em CADA nível (célula = média simples dos robôs já
  arredondados; projeto idem sobre células).
- **D5.b** — cache escrito em cascata na MESMA transação da mutação, ordem fixa robô→célula→projeto,
  `ORDER BY id` em cada statement (anti-deadlock). Sem trigger (mata o caminho em massa), sem job
  assíncrono (quebra o pulso aos 100% e o offline).
- **D5.c** — caminho em massa `BulkRecompute` em 3 `UPDATE ... FROM`; quem usa **suprime** a cascata
  (`without_cascade`) e é obrigado a chamar `BulkRecompute` antes do commit (sweep verifica).
- **D5.d** — `ReconciliationJob` **corrige E alerta** (o valor antigo é a evidência de qual caminho
  esqueceu a cascata). Canal via `Observability::Alert` (de `delivery-and-observability`); ausência
  falha o boot em produção, não silencia.
- **D5.e** — a contagem crua **NÃO é cacheada** (agregado indexado barato; cachear duplica a
  invalidação). Denominador inclui `N/A`. Zero tarefas → 0% na crua (vs 100 no ponderado).
- **D15** — métrica é valor de primeira classe. Envelopes `weighted_progress`/`raw_completion`,
  props `metric` obrigatórias, rótulos pt-BR centralizados, dataset de divergência em todo teste
  que exercita as duas.

## Decisões que EU tomo aqui (cross-change — LER)

1. **RESOLUÇÃO DO CONFLITO DE ESQUEMA `progress_cache` (a decisão grande).**
   `commissioning-hierarchy` (COMPLETA, upstream) criou `progress_cache` como
   **`jsonb NOT NULL DEFAULT '{}'`** + `progress_cached_at`, e as 3 entities
   (project/cell/robot) já expõem `{weighted, done, total}` (D-H7). A spec desta
   change (1.1, D5.a/D5.e) exige **`smallint NOT NULL DEFAULT 0 CHECK BETWEEN 0 AND 100`**
   guardando **só o ponderado**, com os envelopes rotulados e a crua calculada ao
   vivo. São desenhos incompatíveis.
   **Decisão: alinhar à `progress-rollup` (Opção 1, autorizada pelo cliente — "o que
   você acha melhor").** Migration corretiva NESTA change converte `progress_cache`
   jsonb→smallint nas 3 tabelas (mantendo `progress_cached_at`, setado nas escritas de
   rollup), e reescrevo as 3 entities para os envelopes D15.
   **Raciocínio:** (a) `commissioning-hierarchy` declara que "progress-rollup é dona do
   que vai dentro" — ela deveria ter criado a coluna, não o formato; (b) o jsonb
   `{weighted, done, total}` é exatamente o número-sem-rótulo que o D15 existe para
   proibir, e adotá-lo neutraliza os sweeps; (c) D5.e proíbe cachear a crua, e o jsonb
   a cacheia; (d) o medo do D-H7 (retrofit) era de PRODUÇÃO — backfill, janela nullable
   — e aqui é branch de dev sem dado, então o custo real é 3 `ALTER TABLE` + reescrever
   3 entities. **Divergência do D-H7 registrada.** Specs upstream que assertam o jsonb
   serão atualizados (ver decisão 4).
2. **Literais do enum `task_status`.** O design.md usa `status = 'na'`/`'done'` como
   ATALHO. O enum real (robot-tasks) é pt-BR: `'Pendente'`, `'Em Andamento'`,
   `'Concluído'`, `'N/A'` — e os cenários das specs já usam esses literais. TODO SQL
   das views usa os literais pt-BR: válida = `status <> 'N/A'`, concluída = `status = 'Concluído'`.
3. **Auditoria/observabilidade ausentes (mesmo padrão da progress-advances decisão 2).**
   `Observability::Alert` e a métrica `progress_cache_divergence_total` são de
   `delivery-and-observability` (ainda não entregue). Consumo a interface com **guarda
   de presença**: em produção sem a constante → erro no boot (4.3 exige isso); em
   test/dev → log estruturado `progress_cache.divergence` (o evento existe, o canal é
   stub). Isso mantém 4.6 (o cenário "ausência do canal falha o boot") testável.
4. **Edições em changes upstream COMPLETAS (integração da cascata + entities).** Ligar
   `CascadeRecompute`/`BulkRecompute` toca services de `progress-advances` (CreateService),
   `robot-tasks` (Create/Update/Delete/BatchCreate) e `commissioning-hierarchy`
   (Cells/Projects/Robots/Reorder). Reescrever entities e o esquema toca specs upstream
   (`hierarchy_schema_spec` linha 62 assertava jsonb; `hierarchy_crud_spec` linha 38
   assertava `{weighted,done,total}`). Atualizo esses specs para a realidade nova, com
   nota. É o padrão do repo (as varreduras crescem; specs de contrato acompanham a
   mudança deliberada). O ponto de escrita único do cache é garantido pelo sweep de G2.
5. **G6 é majoritariamente CONTRATO/PENDENTE.** `<ProgressRing>`/`<MetricStat>` (6.2/6.3),
   a tela da Visão Geral (6.5) e o relatório (6.4) pertencem a `design-system`/
   `hierarchy-screens`/`commissioning-report` — que NÃO existem ainda. Entrego agora o
   que é meu: locales pt-BR + módulo TS de strings + lint (6.1) e os HANDOFFs de contrato
   (6.4). Os componentes e a tela ficam **pendentes nomeando a capacidade bloqueadora**,
   com o contrato escrito para quando ela chegar. (Confirmado: `grep ProgressRing` no
   frontend = vazio.)
6. **`progress_cached_at`.** Mantenho a coluna (o `hierarchy_schema_spec` a assertava).
   Setada para `now()` nas escritas de `CascadeRecompute`/`BulkRecompute` — dá o "quando
   o cache foi calculado" de graça, útil para a reconciliação e sem custo.
7. **Orçamentos de latência (3.6) são sensíveis ao ambiente.** Os tetos de query (3.5,
   `issue_at_most`) são determinísticos e ficam firmes no CI. Os de latência p95 (120ms/
   25ms/8s) dependem do hardware do runner; implemento a medição mas com margem/tag para
   não flakar no container. Registro se precisar afrouxar.

## Armadilhas previstas

1. **Unificação silenciosa** (o risco nº 1 da change). Propagar ponderação acima do
   robô (célula ponderada pelo nº de tarefas) muda todos os números sem quebrar teste
   não-escrito-para-isso. Mitigação: o dataset de divergência (1.5) e os números
   LITERAIS da suíte SQL (1.6) — `2@100 + 1@0 = 67`, não 66; célula `100+0 = 50`, não 91.
2. **Casos-limite assimétricos.** Robô sem tarefas → **0**; robô com tarefas todas
   `N/A` → **100**. Zero e cem para dois estados que um refatorador colapsa em "vazio".
   `N/A` no denominador da crua, fora do ponderado.
3. **Divisão por zero com peso 0.** Tarefa válida única `weight=0` → o ramo "nada a
   cumprir" retorna 100, não `0/0`.
4. **RLS na reconciliação.** O job roda POR workspace com `app.current_workspace_id`
   setado a cada iteração; job como superusuário fora de RLS reconciliaria entre tenants.
   Cenário de negação obrigatório (4.1).
5. **`float` vs `numeric`.** Arredondamento em `float` diverge do Ruby e do legado.
   Todo cálculo em `numeric`, `ROUND` em `numeric`.
6. **Semear 93k tarefas.** Tem de caber em ≤60s (3.4) senão ninguém roda o orçamento.
   `insert_all` em lote, `without_cascade`, `BulkRecompute` no fim.
7. **REVOKE/roles após migration.** Se a migration corretiva mexer em coluna sob RLS,
   re-rodar `db/roles.sql` nos dois bancos (o padrão que já mordeu nas changes anteriores).

## Protocolo por grupo

Aplicar → `bundle exec rspec` (0 falhas) + `vitest`/`tsc` quando tocar frontend →
marcar `- [x]` em tasks.md → `npx --yes @fission-ai/openspec@1.6.0 validate progress-rollup
--strict` → **um commit** `G<n>: ...`. Ao fim do grupo: resumo client-friendly (≤50%
palavras) e **pedir autorização antes do próximo**. Divergência design×realidade:
decidir, registrar aqui com raciocínio, seguir.

## Progresso

- [x] G0 — este mapa (commit G0)
- [ ] G1 — Esquema + SQL (1.1–1.6)
- [ ] G2 — Cascata em transação (2.1–2.7)
- [ ] G3 — Leitura, envelopes, orçamento (3.1–3.6)
- [ ] G4 — Reconciliação e observabilidade (4.1–4.6)
- [ ] G5 — Backfill de dado importado (5.1–5.3)
- [ ] G6 — Rotulagem D15 (6.1–6.5, boa parte contrato/pendente — ver decisão 5)

## RETOMADA (para o próximo agente)

1. `git log --oneline -12` na branch `progress-rollup` (empilhada em `progress-advances`);
   um commit por grupo. `tasks.md` tem o estado fino; este arquivo tem as decisões.
2. Baseline: pg no ar, migrations como `robotrack_migrator`, `rspec` como `robotrack_app`,
   `vitest`. Se a migration corretiva mexer em coluna RLS, re-rodar `db/roles.sql` nos dois bancos.
3. **A decisão grande é a nº 1**: `progress_cache` vira `smallint` (só o ponderado) — migration
   corretiva desta change, entities reescritas para os envelopes D15, specs upstream de esquema/CRUD
   atualizados. Se algo assumir jsonb `{weighted,done,total}`, está velho.
4. Invioláveis: runtime sem SUPERUSER/BYPASSRLS, RLS forçada, cross-tenant = 404, cálculo só em SQL
   (sem gêmeo Ruby/TS), ponto de escrita único do cache (sweep de G2), as duas métricas NUNCA se
   derivam uma da outra (dataset de divergência).
5. Contratos que esta change DEVOLVE (HANDOFFs em G4/G5/G6): `delivery-and-observability` (canal de
   alerta + métrica + cron diário do Sidekiq), `legacy-data-migration` (BulkRecompute pós-import +
   dump prévio), `hierarchy-screens`/`robot-task-table` (envelopes + `<ProgressRing>`/`<MetricStat>`
   com `metric` obrigatória), `commissioning-report` (carimbo nomeia o ponderado).
