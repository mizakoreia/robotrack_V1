# performance-budgets

## ADDED Requirements

### Requirement: Dataset de carga semeado com tamanhos declarados

O sistema SHALL prover `bin/rails rt:seed:load`, que semeia dois workspaces com
tamanhos exatos e reprodutíveis, usando `insert_all` em transação única
(D-QA-6):

- `WS-CARGA`: **4** projetos, **24** células (6 por projeto), **240** robôs
  (10 por célula), **7.440** tarefas (31 por robô, os 31 padrões de §1.2),
  **22.320** avanços (3 por tarefa), **12** pessoas, **5** memberships,
  **1.500** notificações, **8.000** logs de auditoria.
- `WS-ISCA`: 1 projeto, 1 célula, 1 robô, 31 tarefas, com todos os nomes
  prefixados por `ISCA-`.

#### Scenario: As contagens semeadas são exatamente as declaradas
- **WHEN** `rt:seed:load` termina
- **THEN** `SELECT count(*)` em `WS-CARGA` SHALL retornar `4`, `24`, `240`, `7440`,
  `22320`, `1500` e `8000` nas respectivas tabelas — um dataset "mais ou menos
  grande" torna os p95 incomparáveis entre execuções

#### Scenario: As duas métricas de progresso divergem no dataset
- **WHEN** o progresso de `WS-CARGA` é calculado pelas duas fórmulas de D15
- **THEN** o ponderado e a contagem crua SHALL diferir em pelo menos 8 pontos
  percentuais em ao menos um projeto — um dataset onde as duas coincidem não
  distingue uma implementação correta de uma que unificou as métricas em silêncio

#### Scenario: A isca tem nome procurável, não só id distinto
- **WHEN** qualquer registro de `WS-ISCA` é serializado
- **THEN** seu nome SHALL conter a substring `ISCA-` — o teste de vazamento procura
  texto literal, porque um assert por id não pega nome antigo exibido por cache

#### Scenario: O seed roda em menos de 30 segundos
- **WHEN** `rt:seed:load` é executada num runner de CI limpo
- **THEN** SHALL concluir em menos de 30 s — acima disso o custo por job faz alguém
  removê-lo do pipeline

### Requirement: Orçamento de query constante em relação ao tamanho do dataset

O sistema SHALL medir o número de queries SQL por endpoint orçado
(`sql.active_record`, descontando `SCHEMA` e `TRANSACTION`) em **dois** tamanhos de
dataset — o mínimo e o de carga — e SHALL falhar se o número **variar** entre eles,
mesmo que ambos fiquem sob o teto absoluto. A medição SHALL limpar o cache de query
do ActiveRecord entre as amostras.

#### Scenario: N+1 na Visão Geral é detectado pela variação, não pelo teto
- **WHEN** `GET /api/v1/projects` executa 6 queries com 3 projetos e 9 com 4
  projetos
- **THEN** o teste SHALL falhar por variação — ambos os números estão abaixo do teto
  de `≤ 6`? não: mas ainda que estivessem, a variação por si SHALL reprovar, porque
  é a assinatura de N+1 e o teto absoluto é justamente o gate que datasets pequenos
  atravessam

#### Scenario: Tetos absolutos por tela
- **WHEN** cada endpoint é medido sobre `WS-CARGA`
- **THEN** SHALL respeitar: Visão Geral `≤ 6`, Projeto (6 células) `≤ 6`, Célula
  (10 robôs) `≤ 6`, Robô (31 tarefas + responsáveis) `≤ 8`, Minhas Tarefas `≤ 6`,
  Notificações (50) `≤ 4`, Relatório (workspace inteiro) `≤ 12`

#### Scenario: O relatório mantém 12 queries com 240 robôs
- **WHEN** `GET /api/v1/report` roda no escopo do workspace inteiro de `WS-CARGA` —
  240 robôs, 7.440 tarefas, 22.320 avanços, com histórico por tarefa (§3.8)
- **THEN** SHALL executar `≤ 12` queries — o número precisa ser independente de
  240, senão o relatório é um timeout esperando o primeiro cliente grande

#### Scenario: Carregar responsáveis não multiplica queries por tarefa
- **WHEN** `GET /api/v1/robots/:id/tasks` retorna 31 tarefas, 18 delas com 2
  responsáveis cada
- **THEN** o nº de queries SHALL ser idêntico ao de um robô cujas 31 tarefas não têm
  responsável nenhum

#### Scenario: Cache de aplicação não mascara a medição
- **WHEN** as duas amostras são coletadas
- **THEN** o cache de query do ActiveRecord SHALL ser limpo entre elas, **E** o
  relatório do teste SHALL declarar isso — senão a segunda amostra tem menos queries
  e a comparação de constância vira ruído

### Requirement: Orçamento de latência p95 por endpoint no dataset de carga

O sistema SHALL medir p95 de latência de servidor sobre 30 amostras por endpoint no
dataset de carga, num runner de CI de configuração declarada, falhando ao estourar.

#### Scenario: Tetos de p95
- **WHEN** os endpoints são medidos sobre `WS-CARGA`
- **THEN** SHALL respeitar: Visão Geral `150 ms`, Projeto `150 ms`, Célula `150 ms`,
  Robô `200 ms`, Minhas Tarefas `200 ms`, Notificações `100 ms`, Relatório
  `1.200 ms`

#### Scenario: O teto do relatório é alto e explicitamente delimitado
- **WHEN** o relatório mede `1.150 ms`
- **THEN** SHALL passar — mas se as queries subirem de 12 para 13 no mesmo commit, o
  orçamento de query SHALL reprovar independentemente da latência, porque o gate
  real ali é a forma da consulta

#### Scenario: Falha de p95 reporta a distribuição, não só o veredito
- **WHEN** um endpoint estoura
- **THEN** a saída SHALL incluir p50, p95, máximo e nº de amostras — um veredito sem
  distribuição não distingue regressão de outlier de runner

### Requirement: Orçamento de bundle por chunk e por composição

O sistema SHALL medir, no build de produção, o tamanho **gzip** de cada chunk e
SHALL inspecionar o grafo de módulos do `stats.json` do Rollup, falhando por
tamanho **ou** por composição.

#### Scenario: Tetos de tamanho gzip
- **WHEN** `npm run build` termina e o teste mede os artefatos
- **THEN** SHALL respeitar: JS do entry inicial `≤ 250 KB`, CSS inicial `≤ 40 KB`,
  chunk do relatório `≤ 120 KB`, chunk de gráficos `≤ 180 KB`, soma de todos os
  chunks `≤ 900 KB`

#### Scenario: Dependência pesada no entry reprova mesmo cabendo no teto
- **WHEN** `recharts` passa a ser importado estaticamente pelo shell e o entry vai a
  `240 KB` gzip, ainda sob o teto
- **THEN** o teste SHALL falhar pela regra de composição, nomeando `recharts` e o
  módulo que o importa — passar por tamanho hoje e quebrar no commit seguinte é
  exatamente o modo de falha que o teto sozinho não pega

#### Scenario: Nenhum de recharts, gsap, tiptap ou slate no chunk inicial
- **WHEN** o grafo do chunk de entry é inspecionado
- **THEN** SHALL não conter módulo cujo caminho case `recharts`, `gsap`,
  `@tiptap/`, ou `slate`

#### Scenario: TipTap e Slate coexistindo reprovam nomeando os dois
- **WHEN** o build ainda contém os dois editores, dívida herdada do template
- **THEN** o teste SHALL falhar nomeando ambos e citando
  `seal-template-baseline` como a capacidade que remove um deles

#### Scenario: O relatório é lazy, não parte do entry
- **WHEN** o usuário carrega a Visão Geral
- **THEN** o chunk do relatório SHALL não ser requisitado — quem nunca gera A4 não
  paga 120 KB por ele

### Requirement: Orçamento de interação com 24 cards em tela

O sistema SHALL medir INP (Interaction to Next Paint) na tela de Célula com
**exatamente 24 `.card` visíveis** em viewport de 1440×900, reproduzindo o cenário
citado em `DESIGN.md §Luz ambiente`, sob throttling de CPU declarado.

#### Scenario: INP sob 4x de throttling de CPU
- **WHEN** 24 cards estão em tela, o CPU está a `4x` de throttling e o usuário abre
  o menu da conta e altera um status
- **THEN** o INP p95 SHALL ser `≤ 200 ms` para as duas interações

#### Scenario: A luz ambiente não excede a cadência declarada
- **WHEN** o cursor percorre a viewport por 3 segundos com 24 cards em tela
- **THEN** o nº de escritas em `--lx`/`--ly` SHALL ser `≤ 100` (≈30 fps, cadência de
  ~32 ms declarada no `DESIGN.md`) — escrever a cada `mousemove` invalidaria toda
  superfície de vidro dezenas de vezes por segundo

#### Scenario: Sob toque, o efeito de luz não roda
- **WHEN** a medição roda em viewport de 375×812 emulando toque
- **THEN** SHALL não haver nenhuma escrita em `--lx`/`--ly` — o efeito é gated por
  `(hover: hover) and (pointer: fine)` e no toque o custo não se paga

#### Scenario: O cenário de 24 cards é derivado do dataset, não montado à mão
- **WHEN** o teste prepara a tela
- **THEN** SHALL usar uma célula de `WS-CARGA` cuja contagem de cards em tela é 24
  — um cenário montado com HTML fixo mede um componente, não a tela

### Requirement: Reprovação do CI e legibilidade da falha

O sistema SHALL reprovar o job de CI quando qualquer orçamento estourar, e a saída
SHALL identificar orçamento, valor medido, teto e o commit anterior conhecido.

#### Scenario: Falha nomeia o delta, não só o estouro
- **WHEN** o entry vai de `238 KB` para `262 KB` gzip
- **THEN** a saída SHALL reportar `+24 KB` contra o valor do commit base e o teto de
  `250 KB` — sem o delta, quem lê não sabe se foi a mudança dele ou uma deriva de
  seis semanas

#### Scenario: Orçamento não pode ser afrouxado sem registro
- **WHEN** um PR altera um teto no arquivo de orçamentos
- **THEN** o CI SHALL exigir que a alteração venha acompanhada de justificativa no
  próprio arquivo, na linha do teto — orçamento silenciosamente elevado é orçamento
  inexistente

#### Scenario: Os orçamentos valem para capacidades já entregues
- **WHEN** uma capacidade já concluída passa a estourar o orçamento por efeito de
  outra que foi mesclada depois
- **THEN** o CI SHALL reprovar o merge da segunda — o gate é do repositório, não do
  PR que introduziu a tela
