# workspace-membership

## ADDED Requirements

### Requirement: Person como identidade de domínio independente de User

O sistema SHALL persistir `people(id uuid PK, workspace_id uuid NOT NULL, name
text NOT NULL, email citext NULL, user_id uuid NULL REFERENCES users(id))`, com
`user_id` deliberadamente nullable, para que uma pessoa sem conta possa ser
responsável por tarefas (D10). Toda referência de domínio a responsável SHALL
apontar para `people.id` e SHALL NOT usar nome de pessoa como chave.

#### Scenario: Pessoa sem conta é criada e pode ser referenciada
- **WHEN** um editor cadastra o responsável `"Cláudio Terceirizado"` sem e-mail
- **THEN** SHALL existir uma linha em `people` com `user_id = NULL`,
  `email = NULL`, `name = "Cláudio Terceirizado"`, **E** essa `Person` SHALL ser
  referenciável por `id` como responsável de tarefa

#### Scenario: Nomes não são chave estrangeira
- **WHEN** a suíte inspeciona as colunas das tabelas de domínio
- **THEN** SHALL NOT existir coluna de responsável de tipo textual — toda
  referência SHALL ser `uuid` para `people.id`

#### Scenario: Pessoas do mesmo nome em workspaces diferentes coexistem
- **WHEN** `WS-A` e `WS-B` criam, cada um, uma `Person` chamada `"João Souza"`
- **THEN** ambas SHALL ser persistidas como linhas distintas com `workspace_id`
  distintos, sem violação de unicidade

#### Scenario: Nome duplicado no mesmo workspace é rejeitado
- **WHEN** `WS-A` já tem `Person` com `name = "João Souza"` e um `INSERT` tenta
  criar `name = " joão souza "` no mesmo workspace
- **THEN** o Postgres SHALL levantar violação do índice único sobre
  `(workspace_id, lower(btrim(name)))` — sem isso, `§3.6 Minhas Tarefas`
  mostraria metade das tarefas da pessoa

### Requirement: Resolução de Person no aceite de convite

O sistema SHALL expor `People::ResolveService` que, dado um workspace e um
e-mail, casa com a `Person` existente daquele e-mail no workspace ou cria uma
nova, e SHALL preencher `user_id` na linha resultante quando o convidado tem
conta (D10). O serviço SHALL preservar a `Person` já existente em vez de criar
duplicata, para não partir o histórico de atribuições.

#### Scenario: Convidado casa com Person pré-existente sem conta
- **WHEN** existe `Person(name: "Ana Lima", email: "ana@fabrica.com",
  user_id: NULL)` em `WS-A`, já responsável por 7 tarefas, e Ana aceita um
  convite para `WS-A` com a conta `ana@fabrica.com`
- **THEN** o sistema SHALL preencher `user_id` **na linha existente**, **E** a
  contagem de `people` em `WS-A` SHALL permanecer inalterada, **E** as 7 tarefas
  SHALL continuar atribuídas a ela

#### Scenario: Convidado sem Person correspondente gera nova
- **WHEN** `carlos@fabrica.com` aceita convite para `WS-A`, onde não há `Person`
  com esse e-mail
- **THEN** SHALL ser criada uma `Person` em `WS-A` com esse e-mail, o nome de
  exibição da conta e `user_id` preenchido

#### Scenario: Casamento de e-mail é case-insensitive
- **WHEN** a `Person` existente tem `email = "Ana@Fabrica.com"` e o convidado
  autentica como `ana@fabrica.com`
- **THEN** SHALL ocorrer casamento com a linha existente e SHALL NOT ser criada
  segunda `Person`

#### Scenario: Resolução nunca cruza workspace
- **WHEN** existe `Person(email: "ana@fabrica.com")` em `WS-B` e Ana aceita
  convite para `WS-A`
- **THEN** o serviço SHALL criar uma nova `Person` em `WS-A` e SHALL NOT
  reutilizar nem alterar a linha de `WS-B`

### Requirement: Papéis owner, edit e view resolvidos no servidor

O sistema SHALL definir o enum Postgres `membership_role` com exatamente os
valores `edit` e `view`. `owner` SHALL ser derivado de
`workspaces.owner_user_id` e SHALL NOT ser representável como valor de
membership — o dono não é membro (`§1.1`, `§4.1 inv. 2` e `inv. 5`).

#### Scenario: Papel do dono é derivado, não armazenado
- **WHEN** o bootstrap cria o workspace `WS-A` para o usuário `U1`
- **THEN** SHALL NOT existir linha em `memberships` para `U1` em `WS-A`, **E**
  a resolução de papel de `U1` em `WS-A` SHALL retornar `:owner`

#### Scenario: Promover membro a dono é inexprimível
- **WHEN** um `UPDATE memberships SET role = 'owner' WHERE id = '<m>'` é
  executado por qualquer papel de banco
- **THEN** o Postgres SHALL levantar `invalid input value for enum
  membership_role: "owner"`, e a linha SHALL permanecer com o papel anterior

#### Scenario: Dono não pode virar linha de membership
- **WHEN** um `INSERT INTO memberships (workspace_id, user_id, role)` usa o
  `user_id` igual ao `owner_user_id` daquele workspace
- **THEN** o trigger `memberships_owner_is_not_member` SHALL levantar exceção, e
  nenhuma linha SHALL ser criada

#### Scenario: Usuário sem relação não tem papel
- **WHEN** a resolução de papel roda para um usuário sem membership e que não é
  dono de `WS-A`
- **THEN** o resultado SHALL ser `nil` e a request SHALL ser negada com `403`

#### Scenario: Papel é único por usuário e workspace
- **WHEN** um `INSERT` tenta criar segunda membership para o mesmo
  `(workspace_id, user_id)`
- **THEN** o Postgres SHALL levantar violação do índice único
  `index_memberships_on_workspace_id_and_user_id`

### Requirement: Membership vinculada a Person do mesmo workspace

O sistema SHALL persistir `memberships(id uuid PK, workspace_id uuid NOT NULL,
user_id uuid NOT NULL, person_id uuid NOT NULL, role membership_role NOT NULL,
invitation_id uuid NULL)` e SHALL garantir por chave estrangeira composta
`(workspace_id, person_id) REFERENCES people (workspace_id, id)` que a `Person`
vinculada pertence ao mesmo workspace.

#### Scenario: Vincular Person de outro workspace é rejeitado
- **WHEN** um `INSERT INTO memberships` em `WS-A` referencia uma `person_id` que
  existe apenas em `WS-B`
- **THEN** o Postgres SHALL levantar violação de chave estrangeira, **E** a linha
  SHALL NOT ser criada — a RLS sozinha tornaria esse dado corrompido invisível,
  não impossível

#### Scenario: Remover membro preserva a Person e o histórico
- **WHEN** o dono remove a membership de Ana em `WS-A`, onde ela é responsável
  por 7 tarefas
- **THEN** a linha de `memberships` SHALL ser removida, **E** a `Person` de Ana
  SHALL permanecer em `people`, **E** as 7 tarefas SHALL continuar atribuídas a
  ela para efeito de relatório (`§3.8`)

### Requirement: Ausência de responsável é conjunto vazio

O sistema SHALL rejeitar no banco a criação de qualquer `Person` cujo nome seja o
sentinela legado `"Não Atribuído"`, em qualquer grafia com ou sem acento e
independente de caixa e espaços (D11). Ausência de responsável SHALL ser
representada por conjunto vazio de atribuições, nunca por uma pessoa sentinela.
A string `"Não atribuído"` SHALL existir apenas como literal de interface.

#### Scenario: Person sentinela é rejeitada pelo CHECK
- **WHEN** um `INSERT INTO people (name) VALUES ('Não Atribuído')` é executado
- **THEN** o Postgres SHALL levantar violação da constraint
  `people_name_not_sentinel`

#### Scenario: Variantes de grafia também são rejeitadas
- **WHEN** os valores `"nao atribuido"`, `"NÃO ATRIBUÍDO"` e `"  Não Atribuído "`
  são tentados como `name`
- **THEN** os três `INSERT` SHALL falhar com a mesma constraint

#### Scenario: Importação legada suja falha alto em vez de criar fantasma
- **WHEN** `legacy-data-migration` processa uma tarefa exportada com
  `resp: "Não Atribuído"` sem aplicar o filtro de `§1.4 item 1`
- **THEN** a importação SHALL abortar com erro de constraint, **E** SHALL NOT
  criar uma `Person` chamada `"Não Atribuído"` que apareceria no seletor de
  responsáveis

#### Scenario: Bootstrap não cria o sentinela
- **WHEN** um workspace novo é criado
- **THEN** a lista de responsáveis do workspace SHALL conter exatamente uma
  entrada — a `Person` do dono — e SHALL NOT conter `"Não Atribuído"`, ao
  contrário do que `§1.1 Workspace.responsibles` descrevia no legado

#### Scenario: Nome válido que contém a palavra não é bloqueado
- **WHEN** uma `Person` chamada `"Ana Atribuído"` é criada
- **THEN** o `INSERT` SHALL ter sucesso — a constraint compara o nome inteiro
  normalizado, não uma substring
