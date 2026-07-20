## ADDED Requirements

### Requirement: Progresso ponderado do robô (§2.1)

O sistema SHALL calcular o progresso ponderado de um robô em SQL, sobre as tarefas
cujo `status` é diferente de `N/A` ("válidas"), pela fórmula
`round( Σ(peso × progresso) / Σ(peso × 100) × 100 )`, com dois casos-limite
assimétricos: robô sem nenhuma tarefa SHALL valer `0`; robô com tarefas mas nenhuma
válida SHALL valer `100`. O resultado SHALL ser um inteiro entre 0 e 100.

#### Scenario: Robô sem nenhuma tarefa vale 0

- **WHEN** o robô `R-vazio` não possui nenhuma tarefa
- **THEN** `robot_weighted_progress` retorna `0` para `R-vazio`
- **AND** `robots.progress_cache` de `R-vazio` é `0`

#### Scenario: Robô com 3 tarefas, todas N/A, vale 100

- **WHEN** o robô `R-na` possui exatamente 3 tarefas, todas com `status = 'N/A'` e
  `progress = 0`
- **THEN** `robot_weighted_progress` retorna `100` para `R-na`

#### Scenario: Média ponderada com pesos diferentes arredonda para 67

- **WHEN** o robô `R-peso` possui a tarefa `T1` com `weight = 2`, `progress = 100`,
  `status = 'Concluído'` e a tarefa `T2` com `weight = 1`, `progress = 0`,
  `status = 'Pendente'`
- **THEN** o cálculo é `(2×100 + 1×0) / (2×100 + 1×100) × 100 = 200/300 × 100 = 66,67`
- **AND** `robot_weighted_progress` retorna `67`

#### Scenario: Tarefas N/A são excluídas do numerador e do denominador

- **WHEN** o robô `R-mix` possui `T1` (`weight = 1`, `progress = 100`,
  `Concluído`), `T2` (`weight = 1`, `progress = 0`, `Pendente`) e `T3`
  (`weight = 9`, `progress = 0`, `N/A`)
- **THEN** `robot_weighted_progress` retorna `50`, porque `T3` não entra em nenhum
  dos dois somatórios
- **AND** o mesmo robô com `T3` removida retorna igualmente `50`

#### Scenario: Peso zero não pode zerar o denominador

- **WHEN** o robô `R-peso0` possui uma única tarefa válida com `weight = 0` e
  `progress = 40`
- **THEN** o cálculo não divide por zero
- **AND** `robot_weighted_progress` retorna `100`, aplicando o ramo "nenhuma tarefa
  com peso a cumprir = nada a fazer"

#### Scenario: Progresso ponderado é sempre inteiro entre 0 e 100

- **WHEN** qualquer robô do dataset de carga é avaliado
- **THEN** o valor retornado por `robot_weighted_progress` satisfaz
  `value = ROUND(value) AND value BETWEEN 0 AND 100`

### Requirement: Consolidação bottom-up por média aritmética simples (§2.1)

O sistema SHALL calcular o progresso da célula como a **média aritmética simples**
dos progressos ponderados já arredondados de seus robôs, e o progresso do projeto
como a média aritmética simples dos progressos já arredondados de suas células.
Cada robô SHALL pesar igual, independentemente do seu número de tarefas. Célula sem
robôs SHALL valer `0`; projeto sem células SHALL valer `0`. O sistema MUST NOT
ponderar acima da fronteira do robô.

#### Scenario: Célula com robô de 10 tarefas a 100% e robô de 1 tarefa a 0% vale 50

- **WHEN** a célula `C1` possui o robô `RA` com 10 tarefas, todas `Concluído` a
  `progress = 100` (ponderado `100`), e o robô `RB` com 1 tarefa `Pendente` a
  `progress = 0` (ponderado `0`)
- **THEN** `cell_weighted_progress` retorna `(100 + 0) / 2 = 50`
- **AND** o valor NÃO é `91` (que seria a média ponderada pelas 11 tarefas)

#### Scenario: Célula sem robôs vale 0

- **WHEN** a célula `C-vazia` não possui robôs
- **THEN** `cell_weighted_progress` retorna `0`
- **AND** `cells.progress_cache` de `C-vazia` é `0`

#### Scenario: Projeto sem células vale 0

- **WHEN** o projeto `P-vazio` não possui células
- **THEN** `project_weighted_progress` retorna `0`

#### Scenario: Arredondamento acontece em cada nível

- **WHEN** a célula `C2` possui três robôs com ponderados `33`, `33` e `34`
- **THEN** `cell_weighted_progress` retorna `round(100/3) = 33`
- **AND** o projeto que contém apenas `C2` e uma célula de valor `100` retorna
  `round((33 + 100)/2) = 67`

#### Scenario: Robô vazio arrasta a média da célula para baixo

- **WHEN** a célula `C3` possui `RA` com ponderado `100` e `RB` sem nenhuma tarefa
  (ponderado `0`)
- **THEN** `cell_weighted_progress` retorna `50`, e não `100`

### Requirement: Contagem crua de conclusão (§3.2)

O sistema SHALL expor, separadamente do ponderado, a métrica de contagem crua:
`tarefas com status 'Concluído' ÷ total de tarefas do escopo`, como `completed`,
`total` e `percent` inteiro arredondado. O denominador SHALL incluir as tarefas
`N/A`. Escopo sem nenhuma tarefa SHALL retornar `completed = 0`, `total = 0` e
`percent = 0`.

#### Scenario: Hub global mostra 12/40 e 30%

- **WHEN** o workspace possui 40 tarefas, das quais 12 têm `status = 'Concluído'`
- **THEN** `subtree_raw_completion` no escopo do workspace retorna
  `completed = 12`, `total = 40`, `percent = 30`

#### Scenario: Tarefas N/A entram no denominador da contagem crua

- **WHEN** um projeto possui 10 tarefas, sendo 5 `Concluído` e 5 `N/A`
- **THEN** `subtree_raw_completion` retorna `completed = 5`, `total = 10`,
  `percent = 50`
- **AND** NÃO retorna `percent = 100` (que seria o resultado de excluir `N/A`)

#### Scenario: Escopo sem tarefas vale 0% na contagem crua, ao contrário do ponderado

- **WHEN** o robô `R-na` possui 3 tarefas, todas `N/A`
- **THEN** `subtree_raw_completion` para `R-na` retorna `completed = 0`,
  `total = 3`, `percent = 0`
- **AND** `robot_weighted_progress` para o mesmo `R-na` retorna `100`

#### Scenario: Tarefa em andamento a 99% não conta como concluída

- **WHEN** um robô possui `T1` com `progress = 99`, `status = 'Em Andamento'`
- **THEN** `subtree_raw_completion` conta `completed = 0`, `total = 1`,
  `percent = 0`
- **AND** `robot_weighted_progress` para o mesmo robô retorna `99`

### Requirement: As duas métricas são funções distintas e nunca se substituem

O sistema SHALL implementar as duas métricas como artefatos SQL com nomes
distintos (`*_weighted_progress` e `subtree_raw_completion`) e MUST NOT derivar uma
da outra. Toda suíte que exercita ambas SHALL usar um dataset em que os dois
números divergem.

#### Scenario: Dataset de divergência produz números diferentes em todos os níveis

- **WHEN** a célula `C1` contém `R1` (peso 3 @100 `Concluído` + peso 1 @0
  `Pendente`), `R2` (3 tarefas `N/A`) e `R3` (nenhuma tarefa)
- **THEN** os ponderados são `R1 = 75`, `R2 = 100`, `R3 = 0` e
  `cell_weighted_progress(C1) = round(175/3) = 58`
- **AND** `subtree_raw_completion(C1)` retorna `completed = 1`, `total = 5`,
  `percent = 20`
- **AND** `58 ≠ 20`

#### Scenario: Suíte falha se algum teste das duas métricas usar dataset coincidente

- **WHEN** o CI executa o sweep `spec/progress/metric_divergence_spec.rb`
- **THEN** todo exemplo marcado com `:both_metrics` que produzir
  `weighted == raw_percent` no seu dataset falha com a mensagem nomeando D15

### Requirement: Cache `progress_cache` escrito na transação da mutação (D5)

O sistema SHALL manter `progress_cache` em `robots`, `cells` e `projects`
atualizado por `Progress::CascadeRecompute`, executado **dentro da mesma transação**
da mutação que o invalida, na ordem fixa robô → célula → projeto. A leitura de
progresso ponderado pela API SHALL usar `progress_cache`, nunca as views. A coluna
SHALL existir com `NOT NULL`, `DEFAULT 0` e
`CHECK (progress_cache BETWEEN 0 AND 100)`, criada pelas migrations de
`commissioning-hierarchy`.

#### Scenario: Avanço de tarefa atualiza os três níveis no mesmo commit

- **WHEN** um avanço leva a única tarefa do robô `RX` de `progress = 0` para `100`
- **THEN** ao final da transação `robots.progress_cache` de `RX` é `100`,
  `cells.progress_cache` da célula de `RX` reflete a nova média e
  `projects.progress_cache` do projeto reflete a nova média
- **AND** uma leitura anterior ao commit, em outra conexão, ainda vê os valores
  antigos nos três níveis

#### Scenario: Rollback da transação não deixa cache adiantado

- **WHEN** o avanço falha por conflito de `lock_version` (409, `progress-advances`)
  e a transação é revertida
- **THEN** `robots.progress_cache`, `cells.progress_cache` e
  `projects.progress_cache` permanecem com os valores anteriores ao avanço

#### Scenario: Excluir a última tarefa de um robô leva o cache de 100 para 0

- **WHEN** o robô `RY` tem `progress_cache = 100` com uma única tarefa `Concluído`
  e essa tarefa é excluída
- **THEN** `robots.progress_cache` de `RY` passa a `0` (robô sem tarefas), não
  permanece `100`

#### Scenario: Mudar o peso de uma tarefa recalcula o cache

- **WHEN** o robô `R-peso` (`progress_cache = 67`) tem o peso de `T2` alterado de
  `1` para `3`
- **THEN** `robots.progress_cache` passa a `round(200/500 × 100) = 40`

#### Scenario: Mover um robô entre células recalcula as duas células

- **WHEN** o robô `RA` (ponderado `100`) é movido da célula `C1` (que fica só com
  `RB`, ponderado `0`) para a célula `C2` (que tinha só `RC`, ponderado `50`)
- **THEN** `C1.progress_cache` passa a `0` e `C2.progress_cache` passa a
  `round((100 + 50)/2) = 75`
- **AND** os `progress_cache` dos dois projetos envolvidos são recalculados

#### Scenario: Valor fora do domínio é rejeitado pelo banco

- **WHEN** um `UPDATE robots SET progress_cache = 101` é executado direto no banco
- **THEN** o Postgres rejeita com violação da `CHECK` constraint

#### Scenario: Esquema exigido ausente falha a inicialização

- **WHEN** a coluna `projects.progress_cache` existe mas é `NULL`-able
- **THEN** a verificação de esquema desta capacidade falha nomeando
  `commissioning-hierarchy` como dona da migration

### Requirement: Recálculo em massa para caminhos de alto volume

O sistema SHALL oferecer `Progress::BulkRecompute.call(workspace_id:)` que recalcula
os três níveis do workspace em exatamente 3 statements set-based. Caminhos de alto
volume (importação legada, criação de robôs em lote, reset, reconciliação) SHALL
suprimir a cascata por linha e SHALL invocar o recálculo em massa antes do commit.

#### Scenario: Criação de 50 robôs em lote não dispara 1.550 cascatas

- **WHEN** 50 robôs são criados em lote, cada um com as 31 tarefas-base do catálogo,
  numa única transação
- **THEN** `Progress::CascadeRecompute` é invocado `0` vez
- **AND** `Progress::BulkRecompute` é invocado exatamente `1` vez
- **AND** ao final o `progress_cache` dos 50 robôs é `0`

#### Scenario: Bloco sem recálculo final falha no CI

- **WHEN** o sweep spec encontra um bloco `Progress.without_cascade { ... }` que
  não é seguido por uma chamada a `BulkRecompute` no mesmo método
- **THEN** o spec falha nomeando o arquivo e a linha

#### Scenario: Recálculo em massa do dataset de carga cabe no orçamento

- **WHEN** `BulkRecompute` roda sobre o dataset de 20 projetos × 10 células ×
  15 robôs × 31 tarefas (93.000 tarefas)
- **THEN** emite exatamente 3 `UPDATE`
- **AND** completa em ≤ 8 s (p95)

### Requirement: Job de reconciliação corrige e alerta divergência (D5)

O sistema SHALL executar `Progress::ReconciliationJob` periodicamente, comparando
`progress_cache` com o valor das views nos três níveis, por workspace. Ao encontrar
divergência, o job SHALL corrigir a linha, SHALL emitir o evento
`progress_cache.divergence` contendo `workspace_id`, nível, `scope_id`, `cached`,
`computed` e `row_count`, e SHALL incrementar a métrica
`progress_cache_divergence_total`. O canal de entrega do alerta é fornecido por
`delivery-and-observability`.

#### Scenario: Divergência introduzida fora da cascata é corrigida e alertada

- **WHEN** `UPDATE robots SET progress_cache = 12` é aplicado direto no banco a um
  robô cujo valor calculado é `67`, e o job roda em seguida
- **THEN** `robots.progress_cache` volta a `67`
- **AND** um evento `progress_cache.divergence` é emitido com `cached = 12`,
  `computed = 67`, `level = "robot"` e o `scope_id` do robô

#### Scenario: Execução sem divergência não emite alerta

- **WHEN** o job roda sobre um workspace cujos três níveis já estão consistentes
- **THEN** nenhum evento `progress_cache.divergence` é emitido
- **AND** `progress_cache_divergence_total` não é incrementada

#### Scenario: Ausência do canal de alerta falha o boot, não silencia

- **WHEN** a interface `Observability::Alert` não está disponível no ambiente de
  produção
- **THEN** `Progress::ReconciliationJob` levanta erro na verificação de boot,
  nomeando `delivery-and-observability` como capacidade dona do canal
- **AND** o job NÃO roda corrigindo em silêncio

#### Scenario: Correção do job não dispara notificação nem log de auditoria

- **WHEN** o job corrige 40 linhas de `progress_cache`
- **THEN** nenhuma notificação in-app (§2.7) é criada
- **AND** nenhuma entrada de log de auditoria (§2.8) é gravada, porque não houve
  ação humana

### Requirement: Orçamento de query da Visão Geral

O sistema SHALL servir a Visão Geral (§3.2) com no máximo **2 queries**,
independentemente do número de projetos, lendo o anel de cada card a partir de
`projects.progress_cache`. O sistema MUST NOT emitir query por card. Os orçamentos
SHALL ser verificados no CI contra o dataset de carga.

#### Scenario: 20 projetos custam o mesmo que 1 projeto

- **WHEN** `GET /api/v1/projects` é chamado num workspace com 20 projetos do
  dataset de carga
- **THEN** o contador de `sql.active_record` registra no máximo 2 `SELECT`
- **AND** o mesmo endpoint com 1 projeto registra o mesmo número de `SELECT`

#### Scenario: N+1 introduzido falha o CI

- **WHEN** a serialização do card passa a chamar `robot_weighted_progress` por
  projeto
- **THEN** o spec de orçamento falha reportando 22 queries contra o teto de 2

#### Scenario: Latência da Visão Geral dentro do orçamento

- **WHEN** `GET /api/v1/projects` roda 50 vezes sobre o dataset de carga
- **THEN** a latência p95 é ≤ 120 ms

#### Scenario: Cascata de um avanço custa 3 statements

- **WHEN** um avanço é registrado numa tarefa do dataset de carga
- **THEN** `Progress::CascadeRecompute` emite exatamente 3 `UPDATE`
- **AND** a p95 do recálculo é ≤ 25 ms

### Requirement: Isolamento de tenant no cálculo e na reconciliação (D2)

Todo cálculo, recálculo e reconciliação de progresso SHALL rodar sob RLS com
`app.current_workspace_id` setado, e SHALL considerar apenas linhas do workspace
corrente. Nenhum robô, célula ou tarefa de outro workspace SHALL influenciar um
valor, e nenhum papel SHALL obter progresso de escopo alheio.

#### Scenario: Robô de outro workspace não entra na média da célula

- **WHEN** o workspace `W-A` tem a célula `C1` com um robô de ponderado `100`, e o
  workspace `W-B` tem um robô de ponderado `0` cujo `cell_id` foi forjado para
  apontar para `C1`
- **THEN** `cell_weighted_progress(C1)` sob `app.current_workspace_id = W-A`
  retorna `100`
- **AND** a linha forjada é rejeitada pela `FOREIGN KEY` composta
  `(workspace_id, cell_id)`

#### Scenario: Leitor de outro workspace recebe 404 no progresso do projeto

- **WHEN** um usuário membro apenas de `W-B` requisita
  `GET /api/v1/projects/<id de W-A>`
- **THEN** a resposta é `404`, não `403` e não o valor do anel

#### Scenario: Job de reconciliação não cruza workspaces

- **WHEN** o job processa `W-A` e `W-B`, e `W-A` tem 1 divergência
- **THEN** o evento emitido carrega `workspace_id = W-A`
- **AND** nenhuma linha de `W-B` é escrita durante a iteração de `W-A`

#### Scenario: Membro `view` não pode disparar recálculo manual

- **WHEN** um membro com papel `view` chama o endpoint de recálculo manual do
  workspace
- **THEN** a policy nega com `403` (§4.1 inv. 4)
- **AND** nenhum `UPDATE` em `progress_cache` é emitido
