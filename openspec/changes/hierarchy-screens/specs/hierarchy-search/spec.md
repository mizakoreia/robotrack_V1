# hierarchy-search

## ADDED Requirements

### Requirement: Escopo da busca

O sistema SHALL buscar por **substring case-insensitive** nos nomes de **projeto, célula e
robô** do workspace corrente. A busca MUST NOT considerar nomes de tarefa, comentários de
trilha, nomes de pessoa nem qualquer outro campo (§3.7).

#### Scenario: Termo casa projeto, célula e robô mas não tarefa

- **WHEN** o workspace contém a célula "Solda 01", o robô "R02 - Solda" e uma tarefa
  chamada "Solda MIG", e a pessoa busca `sol`
- **THEN** os resultados SHALL conter "Solda 01" e "R02 - Solda", e MUST NOT conter
  "Solda MIG"

#### Scenario: Busca é case-insensitive e por substring

- **WHEN** o workspace contém o projeto "Linha 300 - Carroceria" e a pessoa busca
  `CARROC`
- **THEN** os resultados SHALL conter "Linha 300 - Carroceria"

#### Scenario: Curinga de SQL é tratado como texto literal

- **WHEN** o workspace tem 12 itens nomeados e a pessoa busca `%`
- **THEN** o sistema SHALL retornar 0 resultados e exibir o estado vazio, e MUST NOT
  retornar os 12 itens

### Requirement: Resultados substituem o hub e a grade

Enquanto o campo de busca contiver texto não vazio, o sistema SHALL substituir o hub
analítico e a grade de cards da Visão Geral pela lista de resultados. Quando o campo
voltar a ficar vazio, o sistema SHALL restaurar hub e grade sem recarregar a página.

#### Scenario: Digitar esconde hub e grade

- **WHEN** a Visão Geral está exibindo o hub "Tarefas concluídas 10/40" e 3 cards de
  projeto, e a pessoa digita `sol`
- **THEN** o hub e os cards de projeto MUST NOT estar visíveis, e a lista de resultados
  SHALL estar visível

#### Scenario: Limpar restaura a visão normal

- **WHEN** a busca `sol` está ativa e a pessoa aciona o botão limpar
- **THEN** o campo SHALL ficar vazio, a lista de resultados MUST NOT estar visível, e o
  hub SHALL voltar a exibir "Tarefas concluídas 10/40" com os 3 cards de projeto

### Requirement: Formato e navegação do resultado

Cada resultado SHALL ser exibido em lista plana com ícone do tipo, nome e caminho — sendo
o caminho `Célula · em <projeto>` para células e `Robô · em <célula> · <projeto>` para
robôs — e acioná-lo SHALL navegar diretamente ao destino correspondente. A ordem SHALL ser
projetos, depois células, depois robôs, cada grupo por nome ascendente.

#### Scenario: Caminho do robô nomeia célula e projeto

- **WHEN** o robô "R02 - Solda" pertence à célula "Solda 01" do projeto "Linha 300" e
  aparece nos resultados
- **THEN** o item SHALL exibir o nome "R02 - Solda" e o caminho "Robô · em Solda 01 ·
  Linha 300"

#### Scenario: Acionar resultado navega ao destino

- **WHEN** a pessoa aciona o resultado da célula "Solda 01" de id `c-7`
- **THEN** o sistema SHALL navegar para a tela da célula `c-7`

#### Scenario: Ordem dos tipos é estável

- **WHEN** a busca `sol` retorna o projeto "Solar", a célula "Solda 01" e o robô
  "R02 - Solda"
- **THEN** a lista SHALL apresentá-los exatamente nesta ordem: "Solar", "Solda 01",
  "R02 - Solda"

### Requirement: Contador de resultados e estado vazio

O sistema SHALL exibir o número de resultados encontrados junto à lista. Quando não houver
nenhum acerto, o sistema SHALL exibir um estado vazio que **nomeia o termo buscado** e
oferece a ação de limpar.

#### Scenario: Contador reflete o total

- **WHEN** a busca `sol` retorna 3 itens
- **THEN** o sistema SHALL exibir "3 resultados"

#### Scenario: Estado vazio nomeia o termo

- **WHEN** a pessoa busca `xyz` e nenhum projeto, célula ou robô casa
- **THEN** o sistema SHALL exibir uma mensagem contendo literalmente `xyz` — por exemplo
  `Nenhum resultado para "xyz"` — junto com o botão limpar

### Requirement: Gatilhos de busca

A busca SHALL ser acionada por quatro caminhos que convergem no mesmo comportamento:
digitação ao vivo (com debounce), tecla Enter, botão "Buscar" e a tecla "buscar" do
teclado virtual mobile. Para isso o campo MUST estar dentro de um formulário com
`role="search"`, ser `type="search"` e declarar `enterKeyHint="search"`, e o botão MUST
ser `type="submit"`.

#### Scenario: Digitação dispara busca sem Enter

- **WHEN** a pessoa digita `sol` e não pressiona nenhuma outra tecla
- **THEN** após o debounce o sistema SHALL exibir os resultados de `sol` sem interação
  adicional

#### Scenario: Submit do formulário busca imediatamente

- **WHEN** a pessoa digita `sol` e o formulário recebe `submit` antes de o debounce expirar
  — seja por Enter, pelo botão "Buscar" ou pela tecla "buscar" do teclado mobile
- **THEN** o sistema SHALL executar a busca imediatamente, MUST NOT recarregar a página, e
  MUST NOT executar uma segunda busca duplicada quando o debounce expirar

### Requirement: Busca restrita ao workspace corrente

Os resultados SHALL conter exclusivamente itens do workspace corrente, com o isolamento
garantido pela RLS de `workspace-tenancy` (D2). Nomes de outro workspace MUST NOT aparecer
nem no resultado nem no contador.

#### Scenario: Item homônimo de outro workspace não vaza

- **WHEN** o workspace `W1` tem a célula "Solda 01", o workspace `W2` tem a célula
  "Solda 99", e uma pessoa autenticada em `W1` busca `solda`
- **THEN** o sistema SHALL exibir "1 resultado" e a lista SHALL conter apenas "Solda 01"

#### Scenario: Membro sem acesso ao workspace não busca nele

- **WHEN** uma pessoa sem associação de membro em `W2` chama
  `GET /api/v1/workspaces/W2/search?q=solda`
- **THEN** o sistema MUST responder 403 ou 404 e MUST NOT retornar resultados
