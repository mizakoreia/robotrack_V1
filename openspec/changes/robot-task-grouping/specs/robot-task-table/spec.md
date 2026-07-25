# Spec — `robot-task-table` (categorias colapsáveis + seleção múltipla)

## ADDED Requirements

### Requirement: Categorias são grupos colapsáveis

O sistema SHALL renderizar as tarefas do robô em grupos por categoria (`cat`), cada grupo
com um cabeçalho que expande/recolhe as tarefas daquele grupo, nos layouts de tabela
(`≥768px`) e de cartões (`<768px`). A ordem dos grupos SHALL seguir a primeira aparição da
categoria (menor `position`); dentro do grupo, as tarefas seguem `position`.

*Porquê: hoje a categoria é só um separador visual por run-length; um robô com muitas
tarefas em várias categorias não tem como recolher o que já foi resolvido, e categorias
não contíguas produzem títulos repetidos.*

#### Scenario: cada categoria aparece uma vez, mesmo não contígua

- **WHEN** um robô tem tarefas nas categorias `A`, `B`, `A` (nesta ordem de `position`)
- **THEN** a tela mostra exatamente dois grupos (`A` e `B`), não três cabeçalhos
- **AND** o grupo `A` contém as duas tarefas de `A`

#### Scenario: recolher esconde as tarefas do grupo

- **WHEN** o operador aciona o cabeçalho de uma categoria expandida
- **THEN** as tarefas daquele grupo saem do DOM (não apenas ocultas por CSS)
- **AND** o cabeçalho reflete o estado com `aria-expanded="false"`

#### Scenario: prefixo sequencial e contagem no cabeçalho

- **WHEN** os grupos são renderizados
- **THEN** o primeiro cabeçalho tem o prefixo `A.`, o segundo `B.`, e assim por diante
- **AND** o cabeçalho mostra a contagem de tarefas do grupo
- **AND** o cabeçalho NÃO mostra um percentual de progresso da categoria

### Requirement: Estado de expansão lembrado por robô, aberto por padrão

O sistema SHALL iniciar com todas as categorias expandidas e SHALL persistir o estado de
recolhimento por categoria, por robô, em `lib/safeStorage`, de modo que reabrir a tela do
mesmo robô reflita o que o operador deixou.

#### Scenario: o estado sobrevive à reabertura

- **WHEN** o operador recolhe a categoria `B` no robô R e volta para a tela de R
- **THEN** a categoria `B` aparece recolhida e as demais expandidas

#### Scenario: categoria nova nasce aberta

- **WHEN** uma categoria ainda não vista aparece no robô
- **THEN** ela é renderizada expandida (só o conjunto de recolhidas é persistido)

### Requirement: Seleção múltipla e exclusão em lote (owner-only)

O sistema SHALL permitir ao dono selecionar várias tarefas e excluí-las de uma vez, com
confirmação em `Modal`, e SHALL NÃO exibir a seleção nem a exclusão para `edit`/`view`.

#### Scenario: dono exclui várias de uma vez

- **WHEN** o dono marca 3 tarefas e confirma a exclusão em lote
- **THEN** uma única chamada de exclusão em lote é feita com os 3 ids
- **AND** as chaves do robô (`robotTasks`, `qk.robot` exato, `qk.projects`) são invalidadas

#### Scenario: não-dono não vê a seleção

- **WHEN** um membro `edit` ou `view` abre a tabela
- **THEN** não há checkboxes de seleção nem ação de exclusão em lote
