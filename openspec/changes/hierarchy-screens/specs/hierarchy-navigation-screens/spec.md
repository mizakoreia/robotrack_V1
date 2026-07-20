# hierarchy-navigation-screens

## ADDED Requirements

### Requirement: Hub analítico global da Visão Geral

O sistema SHALL exibir, no topo da Visão Geral, um hub analítico com três indicadores —
Projetos ativos, Robôs analisados e Tarefas concluídas no formato `concluídas/total` —
mais uma barra e um percentual calculados como `concluídas ÷ total` (contagem crua,
§3.2), acompanhados do rótulo textual "de progresso físico global". O percentual do hub
MUST vir do campo `raw_completion` da resposta e MUST NOT vir de `weighted_progress`.

#### Scenario: Hub exibe contagem crua com rótulo

- **WHEN** o workspace tem 3 projetos, 12 robôs e 40 tarefas das quais 10 estão em
  `Concluído`
- **THEN** o hub SHALL exibir "Projetos ativos 3", "Robôs analisados 12", "Tarefas
  concluídas 10/40" e a barra com "25% de progresso físico global"

#### Scenario: Workspace sem nenhuma tarefa não divide por zero

- **WHEN** o workspace tem 2 projetos, 0 robôs e 0 tarefas
- **THEN** o hub SHALL exibir "Tarefas concluídas 0/0" e "0% de progresso físico global",
  sem erro e sem exibir `NaN`

### Requirement: Grade de cards de Projeto na Visão Geral

O sistema SHALL exibir, abaixo do hub, uma grade de cards de Projeto. Cada card MUST
conter ícone do tipo, nome do projeto, badge `N célula(s)` em linha própria, anel de
progresso alimentado pelo **progresso ponderado** (§2.1) e rodapé com "Visão macro" e
"Acessar". Clicar no card SHALL navegar para a tela do projeto correspondente. Cards da
mesma linha MUST ter altura igual, e o anel a 0% MUST omitir o traço.

#### Scenario: Card de projeto usa progresso ponderado

- **WHEN** o projeto "Linha 300" tem 2 células e progresso ponderado consolidado de 67%
- **THEN** o card SHALL exibir badge "2 células" e anel em 67%, com
  `aria-label` "Progresso ponderado: 67%"

#### Scenario: Anel a 0% omite o traço

- **WHEN** o projeto "Linha 400" tem progresso ponderado 0%
- **THEN** o anel SHALL renderizar apenas a trilha de fundo, sem nenhum segmento de
  traço desenhado

#### Scenario: Clique no card navega ao projeto

- **WHEN** a pessoa aciona "Acessar" no card do projeto de id `p-1`
- **THEN** o sistema SHALL navegar para a tela do projeto `p-1`

### Requirement: As duas métricas de progresso são exibidas rotuladas e nunca unificadas

O sistema SHALL exibir na mesma tela o progresso ponderado (§2.1, nos anéis) e a contagem
crua (§3.2, nos hubs), cada um com rótulo próprio (D15). As respostas dos endpoints
agregados MUST expor os campos `weighted_progress` e `raw_completion` separadamente e
MUST NOT expor um campo genérico chamado `progress`.

#### Scenario: Dataset divergente exibe os dois números distintos e rotulados

- **WHEN** o workspace contém um único projeto com um robô de 4 tarefas — uma de peso 5
  em `Concluído` (100%) e três de peso 1 em `Pendente` (0%) — resultando em progresso
  ponderado 40% e contagem crua 25% (1 de 4 concluídas)
- **THEN** o hub SHALL exibir "Tarefas concluídas 1/4" e "25% de progresso físico global",
  **e** o anel do card do projeto SHALL exibir 40% com `aria-label` "Progresso ponderado:
  40%"

#### Scenario: Payload não expõe campo de progresso ambíguo

- **WHEN** um cliente chama `GET /api/v1/workspaces/:id/overview` no dataset divergente
- **THEN** o corpo da resposta MUST conter `weighted_progress: 40` e
  `raw_completion: {completed: 1, total: 4, percent: 25}`, e MUST NOT conter nenhuma chave
  de nome `progress` em qualquer nível

### Requirement: Estado vazio da Visão Geral

Quando o workspace não possui nenhum projeto, o sistema SHALL substituir a grade por um
estado vazio dedicado, com texto explicativo e CTA "Novo Projeto". Para papel `view` o CTA
MUST NOT ser renderizado e o texto MUST usar a variante sem ação.

#### Scenario: Workspace recém-criado mostra CTA

- **WHEN** uma pessoa com papel `owner` abre a Visão Geral de um workspace com 0 projetos
- **THEN** o sistema SHALL exibir o estado vazio com o botão "Novo Projeto" e MUST NOT
  renderizar a grade de cards

#### Scenario: Leitor não recebe CTA de criação

- **WHEN** uma pessoa com papel `view` abre a Visão Geral de um workspace com 0 projetos
- **THEN** o estado vazio SHALL ser exibido sem nenhum botão "Novo Projeto"

### Requirement: Tela de Projeto

O sistema SHALL exibir, na tela de um projeto, um hub analítico com Células configuradas,
Robôs analisados e Tarefas concluídas (`concluídas/total`, contagem crua), e uma grade de
cards de Célula contendo nome, badge `N robô(s)`, anel de progresso ponderado e rodapé
"Status global / Acessar". A tela SHALL oferecer as ações nova célula, renomear célula,
excluir célula e voltar, delegando a execução ao CRUD de `commissioning-hierarchy`.

#### Scenario: Hub e grade do projeto

- **WHEN** o projeto "Linha 300" tem 2 células, 7 robôs, 30 tarefas com 9 concluídas, e a
  célula "Solda 01" tem 4 robôs com progresso ponderado 55%
- **THEN** o hub SHALL exibir "Células configuradas 2", "Robôs analisados 7" e "Tarefas
  concluídas 9/30", e o card de "Solda 01" SHALL exibir badge "4 robôs" e anel em 55%

#### Scenario: Projeto sem células mostra estado vazio do nível

- **WHEN** o projeto "Linha 400" tem 0 células
- **THEN** o sistema SHALL exibir o estado vazio com CTA "Nova célula", e o hub SHALL
  exibir "Células configuradas 0" e "Tarefas concluídas 0/0"

#### Scenario: Excluir célula atualiza hub e grade

- **WHEN** a pessoa exclui a célula "Solda 02" de um projeto que tinha 2 células
- **THEN** após a confirmação a grade SHALL exibir 1 card e o hub SHALL exibir "Células
  configuradas 1", sem recarregar a página

### Requirement: Tela de Célula

O sistema SHALL exibir, na tela de uma célula, um hub analítico com Robôs configurados e
Tarefas concluídas (`concluídas/total`), e uma grade de cards de Robô contendo nome, badge
com a **Aplicação** do robô, anel de progresso ponderado, rodapé `N tarefas` e ação
"Abrir". A tela SHALL oferecer a ação adicionar robô(s), delegando ao assistente de
`robot-tasks` (§2.5).

#### Scenario: Card de robô mostra Aplicação como badge

- **WHEN** a célula "Solda 01" contém o robô "R02 - Solda" com Aplicação "Solda a ponto",
  12 tarefas e progresso ponderado 80%
- **THEN** o card SHALL exibir badge "Solda a ponto", anel em 80% e rodapé "12 tarefas"

#### Scenario: Robô só com tarefas N/A exibe 100% no anel e 0 concluídas no hub

- **WHEN** a célula contém um único robô com 3 tarefas, todas em `N/A`
- **THEN** o anel do card SHALL exibir 100% (§2.1) e o hub da célula SHALL exibir "Tarefas
  concluídas 0/3"

#### Scenario: Abrir robô navega para a tabela de tarefas

- **WHEN** a pessoa aciona "Abrir" no card do robô `r-9`
- **THEN** o sistema SHALL navegar para a tela de tarefas do robô `r-9`

### Requirement: Orçamento de consulta das telas agregadas

Cada tela SHALL ser servida por uma única chamada HTTP a um endpoint agregado, e cada
endpoint MUST executar no máximo 3 consultas SQL, com número de consultas **constante em
relação à quantidade de itens retornados**. O progresso ponderado MUST ser lido da coluna
`progress_cache` mantida por `progress-rollup` (D5) e MUST NOT ser recalculado por item na
requisição.

#### Scenario: Visão Geral com 20 projetos não faz N+1

- **WHEN** `GET /api/v1/workspaces/:id/overview` é chamado num workspace com 20 projetos,
  100 células e 800 robôs
- **THEN** o número de consultas `sql.active_record` da requisição MUST ser ≤ 3, o mesmo
  valor observado num workspace com 1 projeto

### Requirement: Isolamento de workspace nas telas de hierarquia

Os endpoints agregados SHALL retornar exclusivamente dados do workspace corrente, com o
isolamento garantido pela RLS de `workspace-tenancy` (D2) e a autorização pela policy
declarada em `authorization-policies` (D3). Acesso a um recurso de outro workspace MUST
falhar no servidor, independentemente de o cliente conhecer o identificador.

#### Scenario: Projeto de outro workspace não é acessível por id

- **WHEN** uma pessoa autenticada no workspace `W1` chama
  `GET /api/v1/projects/<id de projeto do workspace W2>/overview`
- **THEN** o sistema MUST responder 404 e MUST NOT revelar nome, contagens ou progresso do
  projeto

#### Scenario: Contagens globais não somam outro tenant

- **WHEN** o workspace `W1` tem 3 projetos e o workspace `W2` tem 5, e a Visão Geral de
  `W1` é carregada
- **THEN** o hub SHALL exibir "Projetos ativos 3"

### Requirement: Estados de carregamento e erro

Enquanto a chamada agregada estiver pendente, o sistema SHALL exibir esqueletos com o
mesmo gabarito do hub e da grade, sem deslocamento de layout na chegada dos dados. Em caso
de falha da chamada, o sistema SHALL exibir mensagem de erro em pt-BR com ação "Tentar
novamente" que refaz a consulta, e MUST NOT exibir hub com valores zerados como se fossem
dados reais.

#### Scenario: Falha de rede não é confundida com workspace vazio

- **WHEN** `GET /api/v1/workspaces/:id/overview` responde 500
- **THEN** o sistema SHALL exibir o estado de erro com "Tentar novamente" e MUST NOT
  exibir o estado vazio "Novo Projeto" nem "0% de progresso físico global"
