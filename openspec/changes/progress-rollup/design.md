## Context

§2.1 define a consolidação bottom-up. Transcrita sem simplificação:

```
Robô:
  válidas = tarefas cujo status ≠ 'N/A'
  sem tarefas                      → 0
  com tarefas, 0 válidas           → 100
  senão → round( Σ(peso × progresso) / Σ(peso × 100) × 100 )   sobre as válidas
Célula:  média aritmética SIMPLES dos progressos dos robôs. Sem robôs → 0.
Projeto: média aritmética SIMPLES dos progressos das células. Sem células → 0.
```

§3.2 define a **outra** métrica: `concluídas ÷ total de tarefas`, mostrada nos hubs
analíticos como "Tarefas concluídas 12/40" e como "progresso físico global".

Três armadilhas concretas herdadas do legado, todas fáceis de "consertar" por engano:

1. **A ponderação para na fronteira do robô.** Uma célula com um robô de 10 tarefas
   a 100% e outro de 1 tarefa a 0% vale **50**, não 91. Cada robô pesa igual. Isso
   é intencional: a unidade de comissionamento é o robô, não a tarefa.
2. **Os casos-limite são assimétricos.** Robô sem tarefas = **0** (não comissionado,
   ninguém sabe o que falta). Robô com 3 tarefas todas `N/A` = **100** (alguém
   olhou e decidiu que nada se aplica). Zero e cem, para dois estados que um
   refatorador colapsaria em "vazio".
3. **`N/A` entra no denominador de uma métrica e não da outra.** É ignorada no
   ponderado (§2.1 é explícito) e contada no total da crua (§3.2 diz "total de
   tarefas", sem ressalva). Um robô com 3 tarefas `N/A` mostra **100% ponderado** e
   **0% na contagem crua** — na mesma tela, em dois widgets vizinhos. É por isso
   que D15 exige rótulo em cada número.

O legado recalculava tudo em JS a cada render, sobre o documento do workspace já
carregado inteiro. O porte relacional não tem esse luxo: a Visão Geral pede o anel
de N projetos, e cada anel depende de toda a subárvore de tarefas daquele projeto.

## Goals / Non-Goals

**Goals**

- Uma única definição executável de cada métrica, em SQL, sem gêmeo em Ruby/TS.
- Cache correto por construção no caminho quente, e **detectável** quando não for.
- Custo de leitura da Visão Geral constante no nº de projetos.
- Impossibilidade prática de renderizar um número sem dizer qual métrica é.

**Non-Goals**

- Unificar as métricas. Reponderar acima do robô. Cachear a contagem crua.
- Série temporal de progresso, previsão, burndown.
- Entregar UI, canal de alerta, ou as migrations da hierarquia (ver `proposal.md`).

## Decisions

### D5.a — O cálculo canônico vive em SQL; não existe implementação Ruby

Duas views por métrica, criadas em migration desta capacidade (a **coluna**
`progress_cache` vem de `commissioning-hierarchy`; as **views** são nossas):

- `robot_weighted_progress(robot_id, workspace_id, value)`
- `cell_weighted_progress(cell_id, workspace_id, value)`
- `project_weighted_progress(project_id, workspace_id, value)`
- `subtree_raw_completion(scope_type, scope_id, workspace_id, completed, total, percent)`

`robot_weighted_progress` implementa os três ramos de §2.1 num `CASE` sobre
agregados condicionais (`COUNT(*)`, `COUNT(*) FILTER (WHERE status <> 'na')`), com
`ROUND(...)` sobre `numeric` — nunca sobre `float`.

**Arredondamento acontece em cada nível.** A célula é a média simples dos valores
**já arredondados** dos robôs, e o projeto a média simples dos valores já
arredondados das células. `ROUND` de `numeric` no Postgres é *half away from zero*,
igual ao `Integer#round` do Ruby — mas isso não importa aqui justamente porque não
há código Ruby fazendo a conta.

*Alternativa descartada:* calcular em Ruby (`Robot#progress`) e usar SQL só na
reconciliação. Isso cria dois algoritmos que precisam concordar **bit a bit** —
e o job de reconciliação passaria a reportar divergência de arredondamento como se
fosse corrupção de cache, tornando o alerta ruído. Um algoritmo, uma fonte.

*Alternativa descartada:* propagar decimais até o topo e arredondar só na
apresentação. Muda os números em relação ao legado (célula 100/0 daria 50 em ambos,
mas 33/33/34 divergiria), e o legado persistia inteiros. Fidelidade ganha.

### D5.b — Cache escrito em cascata, na mesma transação da mutação

`Progress::CascadeRecompute.call(robot_id:)` executa, **nesta ordem fixa**:

```
UPDATE robots   SET progress_cache = (SELECT value FROM robot_weighted_progress   WHERE ...)
UPDATE cells    SET progress_cache = (SELECT value FROM cell_weighted_progress    WHERE ...)
UPDATE projects SET progress_cache = (SELECT value FROM project_weighted_progress WHERE ...)
```

Chamado dentro da transação que grava o avanço (`progress-advances`), o CRUD de
tarefa (`robot-tasks`) e o CRUD/mover de robô, célula e projeto
(`commissioning-hierarchy`). Mover um robô entre células recalcula **as duas** células.

Ordem fixa robô → célula → projeto (e, dentro de cada statement, `ORDER BY id`) é o
que evita deadlock entre dois avanços concorrentes na mesma subárvore. Duas
transações que tocam o mesmo robô serializam no lock da linha do robô; nunca
adquirem locks em ordens opostas.

**Onde mora a invariante:** o *valor legal* mora no banco —
`progress_cache smallint NOT NULL DEFAULT 0 CHECK (progress_cache BETWEEN 0 AND 100)`
(constraint declarada em `commissioning-hierarchy`, exigida por nós). A
*atualidade* do valor **não** é garantida por constraint: é garantida por (a) ponto
de entrada único, (b) sweep spec no CI que falha se qualquer arquivo fora de
`app/services/progress/` escrever em `tasks.progress`, `tasks.status`,
`tasks.weight` ou em `*.progress_cache`, e (c) o job de reconciliação, que é o
detector honesto. Dizemos isso explicitamente porque é a fraqueza real do desenho.

*Alternativa descartada:* **trigger Postgres** em `tasks`. Garantiria a atualidade
até por console, mas: dispara por linha, o que degrada a importação legada e a
criação de robôs em lote (1–50 robôs × 31 tarefas = até 1.550 recálculos em
cascata numa transação); é invisível no código Rails, então ninguém lembra dele ao
depurar; e recalcularia a cascata inteira 31 vezes ao semear um robô. Rejeitado
pelo caminho em massa, não pelo caminho quente.

*Alternativa descartada:* **job assíncrono** disparado após o avanço. O usuário
registra "+10", volta para a célula e vê o anel antigo. §3.5 tem "pulso aos 100%" e
o indicador de gravação de `app-shell-navigation` promete escrita concluída —
consistência eventual quebra as duas promessas. Assíncrono também colide com D7
(offline): a fila de mutations já introduz atraso; somar um segundo atraso torna
"quando o número está certo?" indeterminável.

### D5.c — Caminho em massa separado, set-based

`Progress::BulkRecompute.call(workspace_id:)` recalcula o workspace inteiro em
exatamente 3 `UPDATE ... FROM` (todos os robôs, depois todas as células, depois
todos os projetos). Usado por: importação legada, criação de robôs em lote,
reconciliação, e reset de fábrica.

Quem usa o caminho em massa **suprime** a cascata por linha
(`Progress.without_cascade { ... }`, flag de thread), e a chamada em massa ao final
da transação é obrigatória — o sweep spec verifica que todo bloco `without_cascade`
termina com um `BulkRecompute`.

*Alternativa descartada:* deixar a cascata rodar 1.550 vezes e "otimizar depois".
O custo é quadrático na subárvore e a importação legada (§1.4) é justamente onde o
volume aparece.

### D5.d — Reconciliação corrige e alerta

`Progress::ReconciliationJob`, Sidekiq, diário. Por workspace (sob RLS, com
`app.current_workspace_id` setado):

1. `SELECT` comparando `progress_cache` com as views, nos 3 níveis.
2. Se houver linhas divergentes: **corrige** (aplica o valor calculado) e emite um
   evento estruturado `progress_cache.divergence` com `workspace_id`, nível,
   `scope_id`, `cached`, `computed`, `row_count` e o `job_id`.
3. Incrementa a métrica `progress_cache_divergence_total`.

**O canal de alerta é dependência de `delivery-and-observability`** — consumimos a
interface `Observability::Alert.notify(event:, severity:, payload:)` e nada mais. O
plano anterior pedia "alertar divergência" sem que existisse canal nenhum; aqui a
aresta é explícita e, se `delivery-and-observability` não tiver entregue, o job
falha no boot em produção (checagem de presença da constante), não silenciosamente.

*Alternativa descartada:* só alertar, sem corrigir. Deixa o usuário vendo um número
errado até alguém acordar e rodar um rake task. Corrigimos **e** alertamos, e o
alerta carrega o valor antigo — o valor antigo é a evidência de qual caminho de
escrita esqueceu de chamar a cascata; perdê-la torna o alerta inacionável.

*Alternativa descartada:* corrigir em silêncio (self-healing puro). Transforma um
bug de código em ruído invisível: o cache voltaria a divergir todo dia e ninguém
saberia que existe um caminho de escrita quebrado.

### D5.e — A contagem crua não é cacheada

`subtree_raw_completion` é `COUNT(*)` + `COUNT(*) FILTER (WHERE status = 'done')`
sobre `tasks`, resolvido por índice parcial
`idx_tasks_ws_robot_status (workspace_id, robot_id, status)`. Um agregado por hub,
não por card. Cachear duplicaria a superfície de invalidação (a mesma cascata,
agora com dois valores) para economizar uma agregação indexada.

**Denominador inclui `N/A`.** §3.2 diz "total de tarefas", sem ressalva, e o hub
mostra a fração literal `12/40` — esconder as `N/A` do denominador faria a fração
exibida não bater com a tabela do robô (§3.5), que lista todas.
*Alternativa descartada:* excluir `N/A` do total, "para ficar coerente com §2.1".
Isso é exatamente a unificação silenciosa que D15 proíbe.

**Zero tarefas → 0%** na contagem crua (e não 100, como no ponderado). A assimetria
é intencional e tem cenário próprio.

### D15.a — Métrica é um valor de primeira classe, não um número solto

Um enum compartilhado, `progress_metric ∈ {weighted, raw_count}`:

- **API**: nenhuma entidade Grape expõe um inteiro chamado `progress`. Expõe
  `weighted_progress: { value:, metric: "weighted", label: "Progresso ponderado" }`
  e `raw_completion: { completed:, total:, percent:, metric: "raw_count", label: … }`.
  Um spec de contrato varre todas as entidades e falha se algum campo numérico com
  `progress`/`percent` no nome for exposto fora desses envelopes.
- **Frontend**: `<ProgressRing>` e `<MetricStat>` têm `metric` como prop
  **obrigatória** (sem default) e renderizam o rótulo visível + `aria-label`.
  Vitest sweep: renderiza cada componente que exibe progresso e falha se o nó
  acessível não contiver o rótulo da métrica.
- **Relatório (§3.8)**: o carimbo do documento nomeia a métrica usada.
- **Strings**: `config/locales/pt-BR.progress.yml` e o módulo único do frontend
  (D14, `quality-and-accessibility`). Rótulos são format strings versionadas, não
  literais.

*Alternativa descartada:* convenção de nomes + revisão de código
(`progressWeighted` vs `progressRaw`). É exatamente o que o legado fazia, e foi o
que permitiu que os dois números convivessem por anos sem que ninguém soubesse que
eram dois.

### D15.b — Dataset de divergência obrigatório

`spec/support/progress_divergence_dataset.rb` (e o espelho em TS) monta:

| Robô | Tarefas | Ponderado §2.1 | Crua §3.2 |
|---|---|---|---|
| R1 | peso 3 @100 `Concluído`, peso 1 @0 `Pendente` | **75** | **50%** (1/2) |
| R2 | 3 tarefas todas `N/A` | **100** | **0%** (0/3) |
| R3 | nenhuma tarefa | **0** | — (0/0) |
| Célula C1 = (R1+R2+R3)/3 | | **58** | **20%** (1/5) |

Todo teste que exercita as duas métricas usa este dataset. Um dataset onde elas
coincidem passa com uma implementação unificada — e é assim que a unificação entra.

### Orçamento de query da Visão Geral

Alvo: **2 queries, constantes no nº de projetos**.

1. Lista de projetos com `progress_cache` na própria linha + `cells_count`
   (contador na tabela) → 1 query.
2. Hub analítico global (projetos ativos, robôs analisados, concluídas/total) →
   1 query em `subtree_raw_completion` agregada no workspace.

O anel do card **nunca** dispara query: lê `projects.progress_cache`.

**Dataset de carga** (compartilhado com `quality-and-accessibility`):
20 projetos × 10 células × 15 robôs × 31 tarefas = 3.000 robôs, 93.000 tarefas,
num único workspace.

**Orçamentos** (p95, banco local com o dataset acima, medidos no CI):

| Operação | Queries | p95 |
|---|---|---|
| `GET /api/v1/projects` (Visão Geral, 20 projetos) | ≤ 2 | ≤ 120 ms |
| Hub analítico de projeto (§3.3) | ≤ 2 | ≤ 120 ms |
| `CascadeRecompute` de 1 avanço | 3 | ≤ 25 ms |
| `BulkRecompute` de 1 workspace do dataset | 3 | ≤ 8 s |

**Anti-N+1**: um helper de spec assina `sql.active_record` e conta os `SELECT`
emitidos pela request. O teste declara o teto (`expect { get ... }.to
issue_at_most(2).queries`) e roda com **20 projetos**, não com 1 — com 1 projeto um
N+1 é indistinguível do caso ótimo. Isso é teste de CI, não cláusula de aceite de
passagem.

## Risks / Trade-offs

- **O cache pode ficar velho e a constraint não impede isso.** Só o CHECK de
  domínio (0–100) é garantido pelo banco. Mitigação em três camadas: ponto de
  entrada único, sweep spec no CI, job de reconciliação. **O SLO honesto de
  atualidade é o intervalo do job (24 h)** para qualquer caminho de escrita que
  esqueça a cascata. Aceitamos isso porque a alternativa (trigger) custa a
  importação legada.
- **A dependência da coluna é de mão dupla.** `commissioning-hierarchy` cria a
  coluna, mas quem sabe o que ela significa somos nós. Se aquela capacidade for
  implementada antes de esta spec ser lida, a coluna nasce sem `CHECK` e sem
  `NOT NULL`. Mitigação: a tarefa 1.1 abaixo é uma verificação de esquema que falha
  se a coluna não existir com a forma exigida — falha alto, cedo, e nomeia a
  capacidade dona.
- **Média simples acima do robô distorce em hierarquia desbalanceada.** Uma célula
  com 1 robô trivial e 1 robô de 40 tarefas mostra 50% quando metade do trabalho
  real está por fazer. É fiel ao legado e ao modelo mental do engenheiro
  ("quantos robôs estão prontos"), mas é uma pergunta de produto legítima.
  Registrada em aberto, **não** alterada aqui.
- **Dois números na mesma tela confundem.** O rótulo é a mitigação, e é por isso
  que D15 é executável (sweep) e não convenção.
- **Reconciliação sob RLS é fácil de errar.** O job roda por workspace, setando
  `app.current_workspace_id` a cada iteração; um job que rode como superusuário
  fora de RLS reconciliaria entre tenants. Cenário de negação obrigatório.

## Plano de migração

Não há dado em produção. A ordem é:

1. `commissioning-hierarchy` cria as tabelas **já com** `progress_cache` (D5).
2. Migration desta capacidade cria as 4 views e o índice parcial de status. Views
   são `CREATE OR REPLACE`; a migration é reversível por `DROP VIEW`.
3. `Progress::CascadeRecompute` entra e os chamadores passam a invocá-lo.
4. `BulkRecompute` é rodado uma vez ao final da importação legada
   (`legacy-data-migration`) — é a única forma de o dado importado ter cache certo,
   já que a importação suprime a cascata.

Nenhum passo é destrutivo: as views são derivadas e o `BulkRecompute` só reescreve
uma coluna derivada. Ainda assim, a tarefa de `BulkRecompute` em massa sobre dado
importado é precedida de uma tarefa de dump da coluna (ver `tasks.md` 5.x), porque
um bug nas views transformaria "cache errado" em "cache errado e irrecuperável sem
recomputar".

## Perguntas em aberto

1. A média simples acima do robô deve virar ponderada pelo nº de tarefas? **Não
   nesta mudança** — mudaria todos os números históricos. Se o produto quiser, é
   uma terceira métrica rotulada, não uma alteração da §2.1.
2. Intervalo do job de reconciliação: 24 h é o padrão proposto. Se
   `delivery-and-observability` expuser custo de execução aceitável, cair para 1 h
   estreita o SLO de atualidade sem mudar nenhum código daqui.
3. Robô com tarefas, todas `N/A`, contribui **100** para a média da célula. Uma
   célula inteira de robôs `N/A` marca 100% "pronto". É fiel a §2.1; vale conferir
   com o usuário do chão de fábrica se é o que ele lê no anel verde.
