## ADDED Requirements

### Requirement: Idempotência estrutural do importador

O importador SHALL derivar a chave primária de todo registro importado como UUIDv5 sobre
o caminho legado canônico do registro, e SHALL gravar com `INSERT … ON CONFLICT (id) DO
NOTHING`. Uma segunda execução sobre o mesmo arquivo canônico MUST criar zero registros e
MUST NOT alterar nenhum campo de registro já existente.

#### Scenario: Segunda execução cria zero registros

- **WHEN** `rake legacy:import[canonico.json]` roda uma segunda vez sobre o mesmo arquivo,
  depois de um primeiro run que criou 3 projetos, 7 células, 42 robôs e 1.302 tarefas
- **THEN** o relatório do segundo run reporta `criados: 0` para cada um dos oito tipos de
  entidade, `pulados_por_conflito: 1354` no total, e `SELECT count(*)` em cada tabela de
  domínio devolve exatamente o mesmo número de antes

#### Scenario: Segunda execução não sobrescreve edição feita depois do corte

- **WHEN** depois do primeiro import um usuário renomeia o robô importado de `"R01"` para
  `"R01 - Solda Ponto"`, e o importador roda de novo sobre o mesmo arquivo
- **THEN** o nome do robô permanece `"R01 - Solda Ponto"` e `updated_at` do robô não muda

#### Scenario: Dois robôs homônimos na mesma célula não são fundidos

- **WHEN** o arquivo canônico contém, na mesma célula, dois robôs ambos chamados `"R05"`
  nas posições 2 e 3 do array
- **THEN** o import cria **duas** linhas em `robots`, com ids UUIDv5 distintos derivados
  de `.../cell:1/robot:2` e `.../cell:1/robot:3`

### Requirement: Resolução de responsáveis por cascata de §1.4 item 1

O importador SHALL resolver os responsáveis de cada tarefa na ordem: se `assignees` for um
Array, usá-lo e encerrar a cascata; senão, se `resp` for uma string presente e diferente
do sentinela `"Não Atribuído"`, usar `[resp]`; senão, conjunto vazio. Os nomes resultantes
SHALL ser resolvidos para `people.id` e gravados em `task_assignees`. O importador MUST
NOT gravar nenhum campo `resp` no destino.

#### Scenario: assignees presente vence resp

- **WHEN** a tarefa legada tem `assignees: ["Maria"]` e `resp: "João"`
- **THEN** a tarefa importada tem exatamente um responsável, a `Person` de nome `"Maria"`,
  e nenhuma `Person` chamada `"João"` é criada por essa tarefa

#### Scenario: assignees vazio é resposta, não ausência

- **WHEN** a tarefa legada tem `assignees: []` e `resp: "Maria"`
- **THEN** a tarefa importada tem **zero** responsáveis, e `resp` não é consultado

#### Scenario: resp usado quando assignees não existe

- **WHEN** a tarefa legada não tem a chave `assignees` e tem `resp: "Carlos"`
- **THEN** a tarefa importada tem exatamente um responsável, a `Person` de nome `"Carlos"`

#### Scenario: nenhum dos dois campos

- **WHEN** a tarefa legada não tem `assignees` nem `resp`
- **THEN** a tarefa importada tem zero linhas em `task_assignees` e o import não falha

### Requirement: Filtro do sentinela "Não Atribuído" (D11)

O importador MUST NOT criar nenhuma `Person` cujo nome, após `trim` e `downcase`, seja
`"não atribuído"`. Ausência de responsável SHALL ser representada como conjunto vazio. A
proibição SHALL ser reforçada por uma CHECK constraint em `people`, e não apenas por
código de aplicação.

#### Scenario: tarefa com resp sentinela importa sem responsável e sem Person nova

- **WHEN** a tarefa legada tem `resp: "Não Atribuído"` e não tem `assignees`, e o
  workspace de destino tem 4 pessoas antes do import
- **THEN** a tarefa importada tem zero linhas em `task_assignees`, e
  `SELECT count(*) FROM people WHERE workspace_id = :ws` continua devolvendo `4`

#### Scenario: sentinela no meio de uma lista de assignees é removido, o resto entra

- **WHEN** a tarefa legada tem `assignees: ["Ana", "Não Atribuído", "  não atribuído  "]`
- **THEN** a tarefa importada tem exatamente um responsável, `"Ana"`, e nenhuma `Person`
  com nome equivalente ao sentinela existe no workspace

#### Scenario: sentinela removido da lista de responsáveis do workspace

- **WHEN** `workspace.responsibles` no arquivo legado é
  `["Não Atribuído", "Ana", "Bruno"]`
- **THEN** o import cria exatamente 2 linhas em `people` para esse workspace, `"Ana"` e
  `"Bruno"`

#### Scenario: banco recusa o sentinela mesmo por escrita direta

- **WHEN** `INSERT INTO people (id, workspace_id, name) VALUES (gen_random_uuid(), :ws,
  'Não Atribuído')` é executado por `psql`, fora do importador
- **THEN** o Postgres rejeita o INSERT com violação de CHECK constraint

#### Scenario: pessoas homônimas por caixa colapsam numa só

- **WHEN** o arquivo contém `assignees: ["João Silva"]` numa tarefa e
  `assignees: ["joão silva"]` em outra, no mesmo workspace
- **THEN** exatamente uma linha em `people` é criada, e as duas tarefas apontam para o
  mesmo `person_id`

### Requirement: Conversão da nota livre em entrada de histórico (§1.4 item 2)

Uma tarefa legada com `obs` preenchido e `history` vazio ou ausente SHALL produzir uma
linha em `task_advances` com `by = NULL`,
`author_name_snapshot = "(nota anterior)"`, `from_progress = 0`, `to_progress = 0`,
`comment` igual ao conteúdo de `obs` e `legacy = true`, conforme o contrato declarado por
`progress-advances`. O destino MUST NOT ter coluna `obs`. `recorded_at` SHALL ser derivado
de dado do arquivo e MUST NOT usar o relógio do momento do import.

#### Scenario: obs com histórico vazio vira a primeira entrada legada

- **WHEN** a tarefa legada tem `obs: "Cabo de encoder pendente com o fornecedor"`,
  `history: []` e `_updatedAt: "2024-03-11T14:02:00Z"`
- **THEN** a tarefa importada tem exatamente uma linha em `task_advances`, com
  `legacy = true`, `by IS NULL`, `author_name_snapshot = "(nota anterior)"`,
  `from_progress = 0`, `to_progress = 0`,
  `comment = "Cabo de encoder pendente com o fornecedor"` e
  `recorded_at = 2024-03-11T14:02:00Z`

#### Scenario: obs com histórico já existente vai para quarentena

- **WHEN** a tarefa legada tem `obs: "revisar"` e `history` com 2 entradas
- **THEN** o import cria exatamente 2 linhas em `task_advances` (as do histórico), nenhuma
  com `legacy = true`, e o relatório do run contém uma entrada de quarentena com o
  `legacy_path` da tarefa e o motivo `obs_descartado_historico_presente`

#### Scenario: recorded_at determinístico entre dois runs

- **WHEN** o importador roda sobre o mesmo arquivo em dois bancos limpos distintos, com
  24 horas de diferença entre os runs
- **THEN** o `recorded_at` da entrada legada é idêntico nos dois bancos

#### Scenario: obs vazio não gera entrada

- **WHEN** a tarefa legada tem `obs: ""` e `history: []`
- **THEN** a tarefa importada tem zero linhas em `task_advances`

### Requirement: Compatibilidade `apps` / `appFilters` (§1.4 item 3)

O importador SHALL aceitar tanto `appFilters` quanto o nome antigo `apps` como origem de
`task_templates.app_filters`. Quando ambos estiverem presentes, `appFilters` SHALL
prevalecer e a divergência SHALL ser registrada no relatório do run. O valor `"Todas"`
SHALL ser preservado como está.

#### Scenario: template com o campo antigo importa igual a um com o campo novo

- **WHEN** o arquivo contém dois templates idênticos exceto pelo nome do campo — um com
  `apps: ["Solda MIG"]` e outro com `appFilters: ["Solda MIG"]`
- **THEN** as duas linhas de `task_templates` resultantes têm
  `app_filters = '{Solda MIG}'`, sem diferença de nenhum outro campo

#### Scenario: os dois campos presentes e divergentes

- **WHEN** um template tem `apps: ["Handling"]` e `appFilters: ["Sealing"]`
- **THEN** a linha importada tem `app_filters = '{Sealing}'` e o relatório do run contém
  um aviso `app_filters_divergentes` com o `legacy_path` do template

#### Scenario: "Todas" é preservado, não convertido em lista vazia

- **WHEN** um template tem `apps: ["Todas"]`
- **THEN** a linha importada tem `app_filters = '{Todas}'`

### Requirement: Normalização defensiva de coleções ausentes (§1.4)

O importador SHALL tratar `cells`, `robots`, `tasks` e `history` ausentes, `null` ou não
sendo Array como lista vazia. Nenhuma dessas ausências MUST abortar o run.

#### Scenario: projeto sem a chave cells importa sem erro

- **WHEN** o arquivo contém um projeto `{"id": "p1", "name": "Linha 4"}` sem a chave
  `cells`
- **THEN** o projeto é criado com nome `"Linha 4"`, zero células, o run termina com status
  de sucesso e nenhuma exceção é levantada

#### Scenario: célula sem robots e robô sem tasks

- **WHEN** o arquivo contém uma célula `{"name": "C1"}` sem `robots` e, noutro projeto, um
  robô `{"name": "R09", "application": "Handling"}` sem `tasks`
- **THEN** a célula é criada com zero robôs e o robô é criado com zero tarefas, ambos com
  `progress_cache` calculado como `0` (robô sem tarefas = 0, §2.1)

#### Scenario: cells com valor null

- **WHEN** o arquivo contém `{"id": "p2", "name": "Linha 5", "cells": null}`
- **THEN** o projeto é criado com zero células e o run não registra quarentena para ele

### Requirement: Renumeração de ordem para `position` contígua

O importador SHALL converter o `_ord` legado do projeto (que na criação recebia um
timestamp, §2.9) e a posição implícita nos arrays de células, robôs e tarefas em uma
coluna `position` inteira, contígua e 0-based dentro de cada escopo, conforme
`commissioning-hierarchy`.

#### Scenario: _ord timestamp vira índice contíguo

- **WHEN** três projetos têm `_ord` iguais a `1700000000000`, `1500000000000` e
  `1900000000000`
- **THEN** as linhas importadas têm `position` `1`, `0` e `2` respectivamente, e
  `SELECT DISTINCT position FROM projects WHERE workspace_id = :ws` devolve exatamente
  `{0,1,2}`

#### Scenario: projetos com _ord idêntico têm ordem estável

- **WHEN** dois projetos têm o mesmo `_ord: 1700000000000`
- **THEN** o desempate é pela ordem de aparição no arquivo, `position` `0` e `1`, e um
  segundo run sobre o mesmo arquivo produz a mesma atribuição

### Requirement: Quarentena de registro irreparável (sem relaxar constraint)

Um registro legado cujo valor viole uma constraint do esquema de destino MUST NOT ser
importado, MUST NOT provocar relaxamento da constraint, e SHALL gerar uma linha no
relatório do run com `legacy_path`, campo, valor bruto e motivo. O run SHALL continuar.

#### Scenario: status fora do enum de §1.1

- **WHEN** uma tarefa legada tem `status: "Em Análise"`
- **THEN** a tarefa não é importada, o relatório contém
  `motivo: status_fora_do_enum, valor: "Em Análise"` com o caminho da tarefa, e as demais
  tarefas do mesmo robô são importadas normalmente

#### Scenario: progresso fora da faixa

- **WHEN** uma tarefa legada tem `progress: 150`
- **THEN** a tarefa não é importada e o importador MUST NOT gravar `100` no lugar

#### Scenario: status e progresso incoerentes — progresso vence

- **WHEN** uma tarefa legada tem `status: "Concluído"` e `progress: 80`
- **THEN** a tarefa é importada com `progress = 80` e `status = "Em Andamento"` (derivado
  por §2.2), e o relatório registra `status_derivado_de_progresso`

#### Scenario: aplicação de robô fora do enum de §1.2

- **WHEN** um robô legado tem `application: "Paletização"`
- **THEN** o robô não é importado, suas tarefas também não, e o relatório aponta o robô
  com `motivo: application_fora_do_enum`

### Requirement: Isolamento de tenant durante o import

O importador SHALL setar `app.current_workspace_id` explicitamente por workspace antes de
qualquer escrita (D2) e MUST falhar sem escrever nada se a variável não estiver definida.
Registros de um workspace MUST NOT ser gravados sob o `workspace_id` de outro.

#### Scenario: import sem workspace corrente falha limpo

- **WHEN** o serviço de import é chamado diretamente sem `app.current_workspace_id`
  definido
- **THEN** o serviço levanta erro antes da primeira escrita e `SELECT count(*)` em
  `projects` permanece inalterado

#### Scenario: arquivo com dois workspaces não mistura dados

- **WHEN** o arquivo canônico contém os workspaces `wsA` (2 projetos) e `wsB` (5 projetos)
  e ambos são importados
- **THEN** `SELECT count(*) FROM projects WHERE workspace_id = wsA` devolve `2` e para
  `wsB` devolve `5`, e nenhuma célula de `wsA` referencia projeto de `wsB`

#### Scenario: dono divergente recusa o import

- **WHEN** o arquivo declara `ownerUid: "u-123"` e o workspace de destino tem dono
  correspondente a `"u-999"`
- **THEN** o run é recusado antes de qualquer escrita, com mensagem citando os dois
  identificadores
