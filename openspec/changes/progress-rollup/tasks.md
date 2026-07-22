## 1. Fundação de esquema e cálculo em SQL

- [x] 1.1 Escrever spec de verificação de esquema que exige `progress_cache` em `projects`, `cells` e `robots` como `smallint NOT NULL DEFAULT 0 CHECK (BETWEEN 0 AND 100)`, falhando com mensagem que nomeia `commissioning-hierarchy` como dona da migration. (§D5 — se a coluna nascer `NULL`-able, o teste falha na inicialização em vez de o anel exibir `nil` como `0` seis ondas depois)
- [x] 1.2 Migration reversível criando a view `robot_weighted_progress` com os três ramos de §2.1 num único `CASE` sobre agregados condicionais, em `numeric` (nunca `float`). (§2.1 — robô com 3 tarefas `N/A` retorna 100 e robô sem tarefas retorna 0; não os dois iguais)
- [x] 1.3 Estender a migration com `cell_weighted_progress` e `project_weighted_progress` como média aritmética **simples** dos valores já arredondados do nível abaixo. (§2.1 — célula com robô de 10 tarefas a 100% e robô de 1 tarefa a 0% retorna 50, não 91)
- [x] 1.4 Migration reversível criando `subtree_raw_completion` (`completed`, `total`, `percent`) com `N/A` **no denominador**, mais o índice parcial `idx_tasks_ws_robot_status`. (§3.2 — projeto com 5 `Concluído` e 5 `N/A` retorna 50%, não 100%)
- [x] 1.5 Escrever `spec/support/progress_divergence_dataset.rb` produzindo `R1=75/50%`, `R2=100/0%`, `R3=0/—` e `C1=58/20%`. (D15 — o dataset é rejeitado se algum nível tiver ponderado igual à contagem crua)
- [x] 1.6 Suíte SQL das views cobrindo os 6 cenários de robô, os 5 de célula/projeto e os 4 de contagem crua do spec, com os números literais. (§2.1/§3.2 — peso 2@100 + peso 1@0 dá exatamente 67, não 66 nem 66.67; peso 0 não divide por zero)

## 2. Cache: cascata em transação

- [x] 2.1 Implementar `Progress::CascadeRecompute.call(robot_id:)` com 3 `UPDATE ... FROM` em ordem fixa robô → célula → projeto, `ORDER BY id` dentro de cada statement. (§D5 — dois avanços concorrentes em tarefas do mesmo robô serializam sem deadlock; teste com duas threads e `advisory` de barreira)
- [x] 2.2 Ligar `CascadeRecompute` à transação do avanço de `progress-advances`, sem transação aninhada própria. (§2.4 — rollback por conflito de `lock_version` (409) deixa os três `progress_cache` nos valores anteriores, não adiantados)
- [x] 2.3 Ligar `CascadeRecompute` ao CRUD de tarefa de `robot-tasks` (criar, excluir, alterar peso, alterar status). (§2.1 — excluir a última tarefa `Concluído` de um robô leva o cache de 100 para 0, não deixa 100)
- [x] 2.4 Ligar `CascadeRecompute` ao CRUD e ao mover de `commissioning-hierarchy`, recalculando **as duas** células ao mover um robô. (§2.9 — mover robô de ponderado 100 de `C1` para `C2` deixa `C1` em 0 e `C2` em 75; a célula de origem não fica com o valor velho)
- [x] 2.5 Implementar `Progress.without_cascade` (flag de thread) e `Progress::BulkRecompute.call(workspace_id:)` em 3 `UPDATE` set-based. (§1.4 — criar 50 robôs × 31 tarefas invoca `CascadeRecompute` 0 vez e `BulkRecompute` 1 vez)
- [x] 2.6 Escrever o sweep spec que falha se qualquer arquivo fora de `app/services/progress/` escrever em `tasks.progress`, `tasks.status`, `tasks.weight` ou `*.progress_cache`, e se algum bloco `without_cascade` não terminar em `BulkRecompute`. (§D5 — um `update_column(:progress, …)` novo num service de importação falha o CI nomeando arquivo e linha)
- [x] 2.7 Teste de integração de ponta a ponta da cascata: avanço 0 → 100 numa tarefa e asserção dos três níveis no mesmo commit, mais leitura concorrente vendo os valores antigos antes do commit. (§2.1 — leitura em outra conexão durante a transação não enxerga o valor novo)

## 3. Leitura, envelopes e orçamento de query

- [x] 3.1 Expor `weighted_progress` como envelope `{ value, metric, label }` nas entidades de projeto, célula e robô, lendo `progress_cache` — nunca as views. (D15 — a resposta não contém nenhuma chave `"progress": 58` solta)
- [x] 3.2 Expor `raw_completion` como envelope `{ completed, total, percent, metric, label }` nos endpoints de hub analítico dos três níveis. (§3.2 — 12 de 40 responde `percent: 30` com `metric: "raw_count"`)
- [x] 3.3 Escrever o spec de sweep de entidades Grape que falha em qualquer campo numérico com `progress`/`percent` no nome fora dos dois envelopes. (D15 — `expose :progress` novo numa entidade falha nomeando entidade, campo e a decisão)
- [x] 3.4 Construir o dataset de carga (20 projetos × 10 células × 15 robôs × 31 tarefas = 93.000 tarefas) como seed de spec compartilhado com `quality-and-accessibility`. (§3.2 — semear em ≤ 60 s; se levar minutos ninguém roda o orçamento e ele apodrece)
- [x] 3.5 Implementar o helper `issue_at_most(n).queries` sobre `sql.active_record` e aplicá-lo a `GET /api/v1/projects` com teto de 2 queries, rodando com 20 projetos. (§3.2 — serializar o anel por projeto reporta 22 queries contra o teto de 2; com 1 projeto o N+1 seria invisível)
- [x] 3.6 Fixar no CI, no mesmo job do 3.5, os orçamentos de latência: Visão Geral p95 ≤ 120 ms, cascata p95 ≤ 25 ms, `BulkRecompute` do dataset ≤ 8 s. (§3.2 — estourar o orçamento falha o build; não vira número num relatório que ninguém lê)

## 4. Reconciliação e observabilidade

- [x] 4.1 Implementar `Progress::ReconciliationJob` iterando workspace a workspace, setando `app.current_workspace_id` a cada iteração e comparando cache vs. views nos três níveis. (§D2 — divergência em `W-A` nunca escreve linha de `W-B`; teste com dois workspaces e divergência plantada só num)
- [x] 4.2 Fazer o job **corrigir** as linhas divergentes e emitir `progress_cache.divergence` com `cached`, `computed`, `level`, `scope_id` e `row_count`. (§D5 — cache forçado a 12 num robô de valor 67 volta a 67 **e** o evento carrega o 12; perder o valor antigo torna o alerta inacionável)
- [x] 4.3 Consumir `Observability::Alert.notify` e a métrica `progress_cache_divergence_total` de `delivery-and-observability`, com checagem de boot que levanta erro em produção se a constante não existir, e declarar lá a necessidade do agendamento diário no Sidekiq. (§D5 — sem canal, o job falha alto nomeando a capacidade dona, em vez de corrigir em silêncio)
- [x] 4.4 Garantir que a correção do job não gera notificação (§2.7) nem entrada de auditoria (§2.8). (§2.8 — 40 linhas corrigidas produzem 0 log de auditoria, porque não houve ação humana)
- [x] 4.5 Endpoint de recálculo manual do workspace, declarando policy que exige papel `edit`/dono. (§4.1 inv. 4 — membro `view` recebe 403 e nenhum `UPDATE` em `progress_cache` é emitido)
- [x] 4.6 Teste do job cobrindo os quatro cenários: divergência corrigida e alertada, execução limpa sem alerta, ausência de canal, isolamento entre workspaces. (§D5 — o teste de "execução limpa" falha se o job emitir alerta com `row_count: 0`)

## 5. Backfill de dado importado

- [ ] 5.1 Rake task de dump de `progress_cache` dos três níveis para arquivo antes de qualquer recálculo em massa sobre dado importado. (§4.4 — dump verificável por contagem de linhas por nível; sem ele, um bug nas views torna o estado anterior irrecuperável)
- [ ] 5.2 Rodar `BulkRecompute` ao final da transação do importador legado, dentro de `without_cascade`. (§1.4 — workspace importado com 93.000 tarefas termina com os três níveis consistentes; sem isso todo cache fica em 0 e a Visão Geral mostra tudo zerado)
- [ ] 5.3 Spec de comparação pós-importação: rodar a reconciliação imediatamente após o importador e exigir **zero** divergência. (§4.4 — qualquer divergência aqui é bug de importador ou de view, não de cache velho)

## 6. Rotulagem obrigatória (D15)

- [ ] 6.1 Criar `config/locales/pt-BR.progress.yml` e a entrada equivalente no módulo único de strings do frontend, com os dois rótulos como format strings versionadas, mais o lint que rejeita literal de rótulo fora desses arquivos. (D14 — `"Progresso ponderado"` escrito à mão num componente falha nomeando o arquivo; remover `progress.metrics.raw_count.label` falha o spec de completude de locale em vez de renderizar a chave crua ao usuário)
- [ ] 6.2 Tornar `metric` prop obrigatória sem default em `<ProgressRing>` e `<MetricStat>` (tipo `'weighted' | 'raw_count'`), renderizando o rótulo visível e o `aria-label` correspondentes. (D15 — `<ProgressRing value={58} />` sem `metric` quebra o build de tipos; o nó acessível expõe "Progresso ponderado" e "58%", não só "58")
- [ ] 6.3 Escrever o sweep `progress-label.test.tsx` que renderiza cada componente registrado como exibidor de progresso e falha se o nome acessível não contiver um dos dois rótulos. (D15 — um componente novo que mostra progresso sem rótulo falha o CI)
- [ ] 6.4 Declarar em `commissioning-report` que o carimbo do documento nomeia a métrica ponderada, e adicionar o cenário ao contrato consumido. (§3.8 — o relatório de um projeto de `progress_cache = 58` mostra 58% no corpo e a métrica no carimbo; o `20%` da contagem crua não aparece rotulado como anel)
- [ ] 6.5 Teste de tela da Visão Geral com o dataset de divergência exibindo simultaneamente hub `20%` e anel `58%`, com rótulos distintos. (D15 — trocar o cálculo do anel por `subtree_raw_completion` faz falhar pelo menos 3 asserções nomeando os pares 58/20, 100/0 e 75/50)
