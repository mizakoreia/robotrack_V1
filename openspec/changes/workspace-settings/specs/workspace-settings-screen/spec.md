# workspace-settings-screen

## ADDED Requirements

### Requirement: Tela de configurações com gate de papel

O sistema SHALL expor a rota `/ws/:wsId/settings` com os painéis Equipe, Tarefas-base,
Utilitários e Aparência, e SHALL renderizar controles de escrita apenas para os papéis
autorizados por §4.1, com a autorização repetida no servidor por policy (§4.1 inv. 1, D3).

#### Scenario: dono vê os quatro painéis
- **WHEN** um usuário com papel `owner` no workspace `WS-1` abre `/ws/WS-1/settings`
- **THEN** os painéis Equipe, Tarefas-base, Utilitários e Aparência são renderizados
- **AND** o painel Utilitários contém "Exportar backup" e "Reset de fábrica"

#### Scenario: membro edit não vê os utilitários destrutivos
- **WHEN** um usuário com papel `edit` abre `/ws/WS-1/settings`
- **THEN** os painéis Equipe, Tarefas-base e Aparência são renderizados com controles de escrita
- **AND** o painel Utilitários não contém "Exportar backup" nem "Reset de fábrica"

#### Scenario: membro view não vê nenhum controle de edição do catálogo
- **WHEN** um usuário com papel `view` abre `/ws/WS-1/settings`
- **THEN** a tabela de tarefas-base é renderizada em modo somente leitura, sem coluna
  "excluir", sem formulário de adição e sem editor de filtro de aplicação
- **AND** os chips de Equipe são renderizados sem o "x" de remoção e sem campo de adição

#### Scenario: membro view chamando a API de escrita diretamente é negado
- **WHEN** um usuário com papel `view` envia `POST /api/v1/workspace/task_templates`
  com `{"category":"A. Hardware","description":"X"}`
- **THEN** a resposta é `403`
- **AND** nenhuma linha é criada em `task_templates`

### Requirement: Painel de Equipe — listagem de responsáveis como chips

O sistema SHALL listar as `Person` ativas (`archived_at IS NULL`) do workspace corrente
como chips, em ordem alfabética por nome, lendo de `GET /api/v1/workspace/people`
(§3.9, D10).

#### Scenario: chips refletem as pessoas ativas do workspace
- **WHEN** o workspace `WS-1` tem as pessoas `Ana`, `Bruno` e `Carla` ativas e `Diego`
  com `archived_at` preenchido
- **THEN** o painel Equipe exibe exatamente 3 chips, na ordem `Ana`, `Bruno`, `Carla`

#### Scenario: pessoa de outro workspace nunca aparece
- **WHEN** existe a pessoa `Eva` no workspace `WS-2` e o usuário abre `/ws/WS-1/settings`
- **THEN** `Eva` não aparece entre os chips
- **AND** `GET /api/v1/workspace/people` no contexto de `WS-1` não retorna `Eva`

### Requirement: Painel de Equipe — adicionar responsável

O sistema SHALL permitir a `owner` e `edit` criar uma `Person` do workspace informando
apenas o nome, com `user_id` nulo, e SHALL rejeitar nome vazio ou duplicado entre as
pessoas ativas (§3.9, D10).

#### Scenario: adicionar cria pessoa sem conta
- **WHEN** um usuário `edit` submete o nome `Fernanda` no campo de adição de Equipe
- **THEN** uma `Person` com `name = "Fernanda"`, `user_id = NULL` e
  `workspace_id = WS-1` é criada
- **AND** um novo chip `Fernanda` aparece sem recarregar a página

#### Scenario: nome duplicado é rejeitado ignorando caixa
- **WHEN** já existe a pessoa ativa `Ana` e um usuário `edit` submete `ana`
- **THEN** a resposta é `422` com mensagem de nome já existente
- **AND** continua existindo exatamente uma pessoa ativa com esse nome

#### Scenario: nome só com espaços é rejeitado
- **WHEN** um usuário `edit` submete o nome `"   "`
- **THEN** a resposta é `422`
- **AND** nenhuma linha é criada em `people`

### Requirement: Painel de Equipe — remover responsável por arquivamento

O sistema SHALL remover um chip arquivando a `Person` (`archived_at = now()`) e apagando
suas linhas de `task_assignees`, SHALL preservar `task_advances` e `audit_logs` que a
referenciam, e SHALL recusar o arquivamento de pessoa com membership ativa (D-PERSON-DEL).

#### Scenario: remover chip preserva a história
- **WHEN** `Bruno` é responsável por 2 tarefas e autor de 5 registros em `task_advances`,
  e um usuário `edit` remove o chip `Bruno`
- **THEN** `people.archived_at` de `Bruno` é preenchido
- **AND** as 2 linhas de `task_assignees` são apagadas
- **AND** os 5 registros de `task_advances` permanecem, com `author_name_snapshot = "Bruno"`

#### Scenario: pessoa com conta não é removível por esta tela
- **WHEN** um usuário `owner` tenta remover o chip de uma pessoa que tem membership ativa
  no workspace
- **THEN** a resposta é `409` com mensagem apontando o painel de membros
- **AND** `archived_at` continua nulo

#### Scenario: não existe chip não-removível (D11)
- **WHEN** o painel Equipe exibe os chips do workspace `WS-1`
- **THEN** todo chip exibido possui controle de remoção
- **AND** não existe nenhuma linha em `people` com `name = "Não Atribuído"`

#### Scenario: ausência de responsável é rótulo, não pessoa
- **WHEN** uma tarefa tem `task_assignees` vazio
- **THEN** a interface exibe o texto `"Não atribuído"`
- **AND** nenhuma consulta a `people` é feita para produzir esse texto

### Requirement: Tela do catálogo de tarefas-base

O sistema SHALL exibir os `task_templates` do workspace em tabela com as colunas
categoria, descrição, filtro de aplicação e excluir, agrupada por categoria em ordem
lexicográfica pela string da categoria (§1.3, §3.9). O modelo é de `task-catalog`.

#### Scenario: ordenação é lexicográfica pelo prefixo alfabético
- **WHEN** o workspace tem templates nas categorias `A. Hardware`, `C. Segurança` e
  `B. Rede`
- **THEN** os grupos aparecem na ordem `A. Hardware`, `B. Rede`, `C. Segurança`

#### Scenario: filtro vazio é apresentado como "todas"
- **WHEN** um template tem `app_filters = []`
- **THEN** a coluna de filtro de aplicação exibe `Todas as aplicações`

### Requirement: Adicionar template ao catálogo

O sistema SHALL permitir a `owner` e `edit` criar um template informando categoria,
descrição e filtro de aplicação, com `weight` padrão `1` (§1.3, §3.9).

#### Scenario: template criado com peso padrão
- **WHEN** um usuário `edit` submete categoria `D. Processo`, descrição
  `Calibração de Cola` e filtro `Sealing`
- **THEN** um `task_template` é criado com `weight = 1` e `app_filters = ["Sealing"]`
- **AND** ele aparece dentro do grupo `D. Processo` sem recarregar a página

#### Scenario: descrição vazia é rejeitada
- **WHEN** um usuário `edit` submete categoria `D. Processo` e descrição vazia
- **THEN** a resposta é `422`
- **AND** nenhum `task_template` é criado

### Requirement: Editar o filtro de aplicação com `Misto / Geral` limpando o filtro

O sistema SHALL apresentar o filtro de aplicação como multi-seleção sobre o enum de §1.2
e, quando `Misto / Geral` for escolhido, SHALL desmarcar as demais opções e enviar
`app_filters` como lista vazia, significando "vale para todas" (§3.9, D-CATALOG-FILTER).

#### Scenario: escolher Misto / Geral limpa o filtro
- **WHEN** um template tem `app_filters = ["Handling","Solda Ponto"]` e o usuário marca
  `Misto / Geral` no editor
- **THEN** `Handling` e `Solda Ponto` são desmarcados na interface
- **AND** a requisição enviada contém `"app_filters": []`

#### Scenario: escolher uma aplicação específica desmarca Misto / Geral
- **WHEN** o editor está com `Misto / Geral` marcado e o usuário marca `Sealing`
- **THEN** `Misto / Geral` é desmarcado
- **AND** a requisição enviada contém `"app_filters": ["Sealing"]`

#### Scenario: a interface nunca envia o valor sentinela
- **WHEN** qualquer combinação de opções é escolhida no editor de filtro
- **THEN** a requisição enviada nunca contém a string `Misto / Geral` dentro de
  `app_filters`

### Requirement: Excluir template do catálogo

O sistema SHALL permitir a `owner` e `edit` excluir um template do catálogo com
confirmação, e SHALL não alterar tarefas já criadas a partir dele (§3.9).

#### Scenario: excluir template não mexe em tarefas existentes
- **WHEN** existe o template `TCP Check` e 12 tarefas já criadas a partir dele, e um
  usuário `edit` exclui o template
- **THEN** o template deixa de aparecer na tabela
- **AND** as 12 tarefas continuam existindo com sua descrição e progresso inalterados

#### Scenario: membro view recebe 403 ao excluir
- **WHEN** um usuário `view` envia `DELETE /api/v1/workspace/task_templates/:id`
- **THEN** a resposta é `403`
- **AND** o template continua existindo

### Requirement: Alternância de tema persistida localmente

O sistema SHALL oferecer alternância entre tema escuro e claro no painel Aparência,
SHALL persistir a escolha no armazenamento local do dispositivo, SHALL usar escuro como
padrão e SHALL ignorar a preferência do sistema operacional (§3.11, §4.2, §5.1, D-THEME).

#### Scenario: escolha sobrevive ao recarregamento
- **WHEN** o usuário alterna para o tema claro e recarrega a página
- **THEN** a aplicação carrega em tema claro
- **AND** a classe `dark` não está presente no elemento `<html>`

#### Scenario: preferência do sistema é ignorada
- **WHEN** o sistema operacional está em `prefers-color-scheme: light` e não há
  preferência gravada
- **THEN** a aplicação carrega em tema escuro

#### Scenario: armazenamento bloqueado degrada sem quebrar
- **WHEN** o armazenamento local está bloqueado e o usuário alterna para o tema claro
- **THEN** a interface muda para claro imediatamente
- **AND** um aviso de que a preferência não será lembrada é exibido uma única vez
- **AND** o recarregamento seguinte abre em tema escuro sem erro no console

#### Scenario: tema é do dispositivo, não do workspace
- **WHEN** o usuário está em tema claro no workspace `WS-1` e troca para o workspace `WS-2`
- **THEN** a aplicação permanece em tema claro

### Requirement: Modal de auditoria

O sistema SHALL exibir o log de auditoria em modal, ordenado do mais recente para o mais
antigo, limitado a 200 registros, acessível a todos os papéis, sem qualquer controle de
edição ou exclusão (§2.8, §4.1 inv. 3). O modelo é de `audit-log`.

#### Scenario: exibe no máximo 200 registros mais recentes
- **WHEN** o workspace tem 250 registros de auditoria e o usuário abre o modal
- **THEN** 200 registros são exibidos
- **AND** o primeiro da lista é o de `recorded_at` mais recente

#### Scenario: membro view lê a auditoria
- **WHEN** um usuário `view` abre o modal de auditoria
- **THEN** os registros são exibidos
- **AND** nenhum botão de editar ou excluir registro é renderizado

#### Scenario: registro de outro workspace não vaza
- **WHEN** existem 40 registros em `WS-1` e 10 em `WS-2`, e o usuário abre o modal em `WS-1`
- **THEN** exatamente os 40 registros de `WS-1` são exibidos
