## ADDED Requirements

### Requirement: Toda exposição de progresso declara sua métrica (D15)

Nenhuma resposta de API SHALL expor um número de progresso como inteiro solto. O
progresso ponderado SHALL ser exposto no envelope
`{ value, metric: "weighted", label }` e a contagem crua no envelope
`{ completed, total, percent, metric: "raw_count", label }`. O campo `metric` SHALL
usar o enum fechado `weighted | raw_count`.

#### Scenario: Card de projeto expõe o anel com métrica declarada

- **WHEN** `GET /api/v1/projects` retorna o projeto `P1` com
  `projects.progress_cache = 58`
- **THEN** o corpo contém
  `"weighted_progress": { "value": 58, "metric": "weighted", "label": "Progresso ponderado" }`
- **AND** não contém nenhuma chave `"progress": 58`

#### Scenario: Hub analítico expõe a contagem crua com métrica declarada

- **WHEN** `GET /api/v1/workspaces/current/overview` responde para um workspace com
  12 de 40 tarefas concluídas
- **THEN** o corpo contém
  `"raw_completion": { "completed": 12, "total": 40, "percent": 30, "metric": "raw_count", "label": "Progresso físico (tarefas concluídas)" }`

#### Scenario: Sweep de entidades falha em campo numérico sem envelope

- **WHEN** uma entidade Grape expõe `expose :progress` ou `expose :percent` fora dos
  envelopes `weighted_progress` / `raw_completion`
- **THEN** o spec `spec/api/progress_metric_envelope_spec.rb` falha nomeando a
  entidade, o campo e D15

#### Scenario: Valor de `metric` fora do enum é rejeitado

- **WHEN** um serializador tenta emitir `metric: "physical"`
- **THEN** a construção do envelope levanta erro antes da resposta ser serializada

### Requirement: A UI rotula visivelmente cada número de progresso (D15)

Todo componente que renderiza um número de progresso SHALL receber `metric` como
propriedade obrigatória, sem valor padrão, e SHALL renderizar o rótulo
correspondente de forma visível e acessível (`aria-label` ou texto associado). O
sistema MUST NOT renderizar dois números de métricas diferentes na mesma tela sem
rótulo distinto em cada um.

#### Scenario: Anel sem `metric` não compila

- **WHEN** `<ProgressRing value={58} />` é escrito sem a prop `metric`
- **THEN** a checagem de tipos do TypeScript falha em tempo de build

#### Scenario: Anel do card anuncia a métrica ponderada

- **WHEN** `<ProgressRing value={58} metric="weighted" />` é renderizado
- **THEN** o nó acessível expõe um nome contendo "Progresso ponderado" e o valor
  "58%"

#### Scenario: Hub e card na mesma tela mostram rótulos diferentes

- **WHEN** a Visão Geral é renderizada com o dataset de divergência (hub `20%`,
  anel do projeto `58%`)
- **THEN** o hub exibe "Progresso físico (tarefas concluídas)" e o card exibe
  "Progresso ponderado"
- **AND** os dois números `20` e `58` aparecem simultaneamente sem que a tela sugira
  que um é erro do outro

#### Scenario: Sweep de componentes falha em número sem rótulo

- **WHEN** o sweep `progress-label.test.tsx` renderiza cada componente registrado
  como exibidor de progresso
- **THEN** falha qualquer um cujo nome acessível não contenha um dos dois rótulos

### Requirement: Rótulos são strings pt-BR centralizadas e versionadas (D14)

Os rótulos das duas métricas SHALL viver em `config/locales/pt-BR.progress.yml` no
backend e no módulo único de strings do frontend, como format strings versionadas.
Literais de rótulo espalhados no código SHALL falhar o CI.

#### Scenario: Rótulo literal fora do módulo de strings falha o CI

- **WHEN** um componente contém o literal `"Progresso ponderado"` em vez de
  `t('progress.metrics.weighted.label')`
- **THEN** o lint de strings falha nomeando o arquivo

#### Scenario: Chave de rótulo ausente falha em teste, não em runtime

- **WHEN** `progress.metrics.raw_count.label` é removida do arquivo de locale
- **THEN** o spec de completude de locale falha
- **AND** nenhuma tela renderiza a chave crua como texto ao usuário

### Requirement: O relatório de comissionamento nomeia a métrica usada (§3.8)

O relatório A4 SHALL declarar, no carimbo do documento, que os percentuais do corpo
hierárquico usam o **progresso ponderado (§2.1)**, e SHALL NOT misturar os dois
números no mesmo bloco sem rotulá-los separadamente.

#### Scenario: Carimbo declara a métrica

- **WHEN** o relatório `RT-20260720-1430` é gerado para um projeto com
  `progress_cache = 58`
- **THEN** o carimbo contém a menção ao progresso ponderado
- **AND** o percentual do projeto no corpo é `58%`

#### Scenario: Distribuição de status não é apresentada como progresso

- **WHEN** o bloco de distribuição de status mostra `1 Concluído, 1 Pendente, 3 N/A`
- **THEN** o bloco é rotulado como distribuição de status, não como progresso
- **AND** o número `20%` (contagem crua) não aparece rotulado como o anel do projeto

### Requirement: Testes que exercitam as duas métricas usam dataset divergente (D15)

Toda suíte, de backend ou de frontend, que exercita as duas métricas SHALL usar o
dataset compartilhado de divergência, no qual ponderado e contagem crua produzem
números diferentes em todos os níveis.

#### Scenario: Dataset compartilhado produz o par 58 / 20

- **WHEN** `progress_divergence_dataset` é carregado
- **THEN** a célula `C1` tem ponderado `58` e contagem crua `20%`
- **AND** o robô `R2` (3 tarefas `N/A`) tem ponderado `100` e contagem crua `0%`

#### Scenario: Implementação unificada quebra o dataset

- **WHEN** o cálculo do anel é trocado por `subtree_raw_completion`
- **THEN** os cenários do dataset de divergência falham em pelo menos 3 asserções,
  nomeando os pares `58/20`, `100/0` e `75/50`
