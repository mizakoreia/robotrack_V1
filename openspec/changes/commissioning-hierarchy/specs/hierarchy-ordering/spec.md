## ADDED Requirements

### Requirement: `position` é a representação única de ordem manual

O sistema SHALL representar a ordem manual de projetos, células e robôs numa única coluna
`position integer NOT NULL`, contígua e 0-based dentro do escopo — `workspace_id` para
projetos, `project_id` para células, `cell_id` para robôs (§2.9). O `_ord` inicializado
com timestamp e a ordem implícita por posição de array, ambos do legado, SHALL NOT ser
reproduzidos.

#### Scenario: os três níveis usam a mesma coluna

- **WHEN** um spec de esquema inspeciona `projects`, `cells` e `robots`
- **THEN** as três têm `position integer NOT NULL`
- **AND** nenhuma tem coluna `_ord`, `ord` ou `sort_order`

#### Scenario: item novo entra no fim do escopo

- **WHEN** um projeto tem células nas posições `0, 1, 2` e o cliente cria a célula `Solda 04`
- **THEN** a nova célula recebe `position = 3`
- **AND** as posições das três anteriores não mudam

#### Scenario: primeiro item de um escopo recebe posição 0

- **WHEN** o cliente cria a primeira célula de um projeto vazio
- **THEN** ela recebe `position = 0`, não um timestamp e não `1`

#### Scenario: posições duplicadas no mesmo escopo são impossíveis

- **WHEN** um `UPDATE` de console tenta setar `position = 1` numa segunda célula do mesmo
  projeto que já tem uma célula em `position = 1`, e a transação é confirmada
- **THEN** o Postgres rejeita no `COMMIT` por violação do índice único
  `(project_id, position) DEFERRABLE INITIALLY DEFERRED`

#### Scenario: mesma posição em escopos diferentes é permitida

- **WHEN** o projeto `P1` tem célula em `position = 0` e o projeto `P2` também
- **THEN** ambas coexistem — o índice único é por escopo, não global

### Requirement: reordenação em lote atômica

O sistema SHALL expor um endpoint de reordenação por escopo que recebe o conjunto
completo e ordenado de ids irmãos e renumera `0..n-1` numa única transação, com
`SELECT ... FOR UPDATE` na linha pai. O sistema SHALL NOT expor atualização de
`position` item a item.

#### Scenario: reordenação renumera contiguamente

- **WHEN** o cliente envia `PATCH /api/v1/cells/reorder` com
  `{"scope_id": "<project_id>", "ordered_ids": ["C3", "C1", "C2"]}` para células hoje em
  `C1=0, C2=1, C3=2`
- **THEN** a resposta é `200` e as posições finais são `C3=0, C1=1, C2=2`
- **AND** não existe buraco nem valor negativo em nenhuma linha do escopo

#### Scenario: falha no meio da renumeração não deixa lista inconsistente

- **WHEN** a transação de reordenação de 8 células falha na 5ª linha
- **THEN** todas as 8 mantêm as posições originais
- **AND** a lista não fica com `position` duplicada nem com buraco — o que impediria a
  próxima reordenação legítima do usuário de gravar

#### Scenario: `PATCH` de item não aceita `position`

- **WHEN** o cliente envia `PATCH /api/v1/cells/<id>` com `{"position": 0, "lock_version": 2}`
- **THEN** o parâmetro `position` é rejeitado ou ignorado pela declaração de params
- **AND** a posição da célula não muda

#### Scenario: reordenação não incrementa `lock_version`

- **WHEN** um projeto com `lock_version = 4` é reordenado com sucesso
- **THEN** `lock_version` continua `4`
- **AND** um `PATCH` de renome pendente com `lock_version: 4` ainda é aceito — reordenar
  e renomear são operações independentes (§2.9 vs. §3.3)

### Requirement: reordenação concorrente é detectada pelo conjunto de ids

Quando o conjunto de ids recebido divergir do conjunto de irmãos atualmente no escopo, o
sistema SHALL responder `409` com o conjunto atual e SHALL NOT escrever nenhuma posição.

#### Scenario: irmão criado por outra pessoa invalida o arrasto

- **WHEN** o cliente carrega `["C1", "C2", "C3"]`, outra pessoa cria `C4` no mesmo projeto,
  e então o cliente envia `ordered_ids: ["C3", "C1", "C2"]`
- **THEN** o servidor responde `409` com o conjunto atual `["C1", "C2", "C3", "C4"]`
- **AND** as posições de `C1`, `C2` e `C3` permanecem inalteradas

#### Scenario: irmão excluído por outra pessoa invalida o arrasto

- **WHEN** o cliente envia `ordered_ids: ["C1", "C2", "C3"]` mas `C2` foi excluída
- **THEN** o servidor responde `409` e nenhuma posição é escrita

#### Scenario: id de outro escopo na lista é rejeitado

- **WHEN** o cliente envia `ordered_ids: ["C1", "C2", "<id de célula do projeto P2>"]`
  para o escopo `P1`
- **THEN** o servidor responde `409` (ou `422`), a célula de `P2` não é movida para `P1`
  e nenhuma posição de `P1` muda

#### Scenario: duas reordenações simultâneas serializam

- **WHEN** dois clientes enviam reordenações do mesmo projeto ao mesmo tempo, ambos com o
  conjunto correto `["C1", "C2", "C3"]`
- **THEN** ambas respondem `200`, uma após a outra pelo `FOR UPDATE` no projeto
- **AND** o estado final é exatamente a ordem da segunda transação a confirmar, sem
  posições duplicadas nem deadlock

### Requirement: reordenar exige permissão de edição

Reordenar SHALL exigir papel `owner` ou `edit` no workspace corrente (§2.9, §4.1) e o
endpoint SHALL declarar sua policy (D3).

#### Scenario: membro `view` não reordena

- **WHEN** um membro `view` envia `PATCH /api/v1/projects/reorder` com
  `{"ordered_ids": ["P2", "P1"]}`
- **THEN** o servidor responde `403`
- **AND** as posições de `P1` e `P2` permanecem `0` e `1`

#### Scenario: usuário de outro workspace não reordena

- **WHEN** um usuário autenticado no workspace `W2` envia
  `PATCH /api/v1/cells/reorder` com `scope_id` de um projeto de `W1`
- **THEN** o servidor responde `404` (o escopo não é visível sob RLS), nunca `403` nem `200`
- **AND** as posições das células de `W1` permanecem inalteradas

### Requirement: ordem de leitura segue `position`

Toda listagem de projetos, células e robôs SHALL ordenar por `position` ascendente, com
desempate determinístico por `created_at` e depois por `id`.

#### Scenario: listagem respeita a ordem manual

- **WHEN** as células estão em `C3=0, C1=1, C2=2` e o cliente faz
  `GET /api/v1/projects/<id>` ou `GET /api/v1/cells?project_id=<id>`
- **THEN** a coleção vem na ordem `C3, C1, C2` em ambas as respostas

#### Scenario: ordem é estável entre requisições

- **WHEN** a mesma listagem de 3 robôs é pedida 10 vezes sem nenhuma escrita entre elas
- **THEN** as 10 respostas trazem exatamente a mesma sequência de ids
