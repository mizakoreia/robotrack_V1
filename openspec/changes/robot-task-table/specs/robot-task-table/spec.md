# robot-task-table

## ADDED Requirements

### Requirement: Cabeçalho do robô

O sistema SHALL exibir, no topo da tela do robô, o nome do robô, a Aplicação como
badge, o percentual consolidado **ponderado** (§2.1) rotulado como tal, e as ações
"Adicionar tarefa" e "Sincronizar tarefas-base" (§3.5).

#### Scenario: Cabeçalho exibe nome, aplicação e percentual ponderado rotulado

- **WHEN** o robô `R01 - Solda`, aplicação `Solda a Ponto`, tem 4 tarefas de peso 1
  com progressos `100, 50, 0, 0`
- **THEN** o cabeçalho SHALL exibir o texto `R01 - Solda`, um badge `Solda a Ponto` e
  o valor `38%` acompanhado do rótulo `Progresso ponderado`

#### Scenario: Robô cujas tarefas são todas N/A exibe 100%

- **WHEN** o robô tem 3 tarefas, todas com status `N/A`
- **THEN** o cabeçalho SHALL exibir `100%` e o rótulo `Progresso ponderado`

#### Scenario: Sincronizar tarefas-base informa a contagem adicionada

- **WHEN** o usuário com papel `edit` aciona "Sincronizar tarefas-base" e o servidor
  responde que 7 tarefas foram adicionadas
- **THEN** a tela SHALL exibir a mensagem `7 tarefas adicionadas`, SHALL recarregar a
  lista de tarefas e SHALL redefinir o filtro segmentado para `Todos`

### Requirement: Filtro segmentado com reset na navegação

O sistema SHALL oferecer um controle segmentado com as opções `Todos` (padrão),
`Pendentes` e `Concluídos`, e SHALL redefinir a seleção para `Todos` a cada navegação
para a tela do robô (§3.5).

#### Scenario: Filtro inicia em Todos

- **WHEN** o usuário abre a tela de um robô pela primeira vez na sessão
- **THEN** o segmento `Todos` SHALL estar selecionado e todas as tarefas do robô
  SHALL estar visíveis

#### Scenario: Navegar para outro robô e voltar reseta o filtro

- **WHEN** o usuário está no robô `A`, seleciona `Concluídos`, navega para o robô `B`
  e em seguida volta para o robô `A`
- **THEN** o segmento selecionado no robô `A` SHALL ser `Todos`, e não `Concluídos`

#### Scenario: Pendentes inclui Em Andamento e exclui N/A

- **WHEN** o robô tem 4 tarefas com status `Pendente`, `Em Andamento`, `Concluído` e
  `N/A`, e o usuário seleciona `Pendentes`
- **THEN** a tabela SHALL exibir exatamente as tarefas `Pendente` e `Em Andamento`, e
  SHALL ocultar as tarefas `Concluído` e `N/A`

#### Scenario: Concluídos exclui N/A

- **WHEN** o robô tem 1 tarefa `Concluído` e 2 tarefas `N/A`, e o usuário seleciona
  `Concluídos`
- **THEN** a tabela SHALL exibir exatamente 1 linha, correspondente à tarefa
  `Concluído`

### Requirement: Agrupamento por categoria

O sistema SHALL agrupar as tarefas por Categoria e SHALL inserir uma linha separadora
identificando a categoria sempre que a categoria mudar em relação à linha anterior
(§3.5).

#### Scenario: Separador aparece uma vez por categoria

- **WHEN** o robô tem 5 tarefas nas categorias `Mecânica`, `Mecânica`, `Elétrica`,
  `Elétrica`, `Segurança`, nessa ordem persistida
- **THEN** a tabela SHALL renderizar exatamente 3 linhas separadoras, com os textos
  `Mecânica`, `Elétrica` e `Segurança`, cada uma imediatamente antes da primeira
  tarefa de sua categoria

#### Scenario: Filtro que esvazia uma categoria remove seu separador

- **WHEN** a categoria `Segurança` tem uma única tarefa, de status `Concluído`, e o
  usuário seleciona `Pendentes`
- **THEN** a tabela NÃO SHALL renderizar a linha separadora `Segurança`

### Requirement: Coluna Status

O sistema SHALL exibir, na coluna Status, um seletor em forma de pílula tingida pela
cor do status, com as 4 opções `Pendente`, `Em Andamento`, `Concluído` e `N/A`
(§3.5, §5.1).

#### Scenario: Seletor é visualmente distinguível de um badge

- **WHEN** a coluna Status é renderizada para um usuário com papel `edit`
- **THEN** o controle SHALL renderizar um chevron visível junto à pílula e SHALL
  expor `role` de seletor acessível — nunca sendo indistinguível do badge estático da
  mesma tela

#### Scenario: Mudança de status abre o modal de avanço

- **WHEN** o usuário seleciona `Concluído` numa tarefa cujo status persistido é
  `Em Andamento` com progresso 60
- **THEN** o modal de registro de avanço SHALL abrir com `de 60% → para 100%`, e a
  pílula SHALL permanecer exibindo `Em Andamento` até a confirmação

#### Scenario: Cancelar a mudança de status devolve a pílula ao valor persistido

- **WHEN** o usuário seleciona `N/A` numa tarefa `Pendente` e cancela o modal
- **THEN** a pílula SHALL voltar a exibir `Pendente`

### Requirement: Coluna Progresso

O sistema SHALL exibir, na coluna Progresso, a leitura em `%`, um botão `−`, um
slider de passo 5 e um botão `+`; qualquer alteração SHALL abrir o modal de registro
de avanço (§3.5, §2.4).

#### Scenario: Slider tem passo 5

- **WHEN** o usuário arrasta o slider de uma tarefa com progresso 30 uma posição para
  a direita e solta
- **THEN** o modal de avanço SHALL abrir com `de 30% → para 35%`

#### Scenario: Cancelar o modal devolve o slider ao valor persistido

- **WHEN** o usuário arrasta o slider de 30 para 70 e cancela o modal de avanço
- **THEN** o slider e a leitura em `%` SHALL voltar a exibir `30%`, e nenhuma
  requisição de mutação SHALL ter sido enviada

#### Scenario: Dois incrementos consecutivos somam a partir do valor persistido

- **WHEN** o usuário, sem recarregar a página, aciona `+` numa tarefa de progresso 20
  e confirma o modal, e em seguida aciona `+` novamente e confirma
- **THEN** o progresso persistido final SHALL ser 40, e o segundo modal SHALL ter
  aberto com `de 30% → para 40%`

#### Scenario: A leitura de % reflete o valor devolvido pelo servidor, não o rascunho

- **WHEN** o usuário confirma um avanço para 100 e o servidor devolve
  `progress: 100, status: "Concluído"`
- **THEN** a leitura SHALL exibir `100%` e a pílula de status SHALL exibir
  `Concluído`

### Requirement: Coluna Responsáveis

O sistema SHALL exibir chips com os nomes dos responsáveis da tarefa e, como chips
secundários, os nomes dos contribuidores — pessoas que já registraram avanço — sem
duplicar quem pertence aos dois conjuntos. Clicar na célula SHALL abrir o modal de
atribuição (§3.5).

#### Scenario: Contribuidor que não é responsável aparece como chip secundário

- **WHEN** a tarefa tem `assignees = [Ana]` e existe um avanço registrado por `Bruno`,
  que não é responsável
- **THEN** a célula SHALL exibir `Ana` como chip primário e `Bruno` como chip
  secundário

#### Scenario: Pessoa que é responsável e contribuidor aparece uma única vez

- **WHEN** a tarefa tem `assignees = [Ana]` e o único avanço registrado é de `Ana`
- **THEN** a célula SHALL exibir exatamente um chip com o texto `Ana`, na forma
  primária

#### Scenario: Clique na célula abre o modal de atribuição

- **WHEN** um usuário com papel `edit` clica em qualquer chip ou na área vazia da
  célula Responsáveis
- **THEN** o modal de atribuição SHALL abrir com os responsáveis atuais já marcados

### Requirement: Coluna Trilha

O sistema SHALL exibir, na coluna Trilha, o comentário do último avanço registrado e
um botão com a contagem de entradas que abre o modal de histórico da tarefa (§3.5).

#### Scenario: Último comentário e contagem

- **WHEN** a tarefa tem 3 avanços e o mais recente por `recorded_at` tem o comentário
  `Cabeamento concluído, falta teste`
- **THEN** a célula SHALL exibir `Cabeamento concluído, falta teste` e um botão cujo
  rótulo acessível informa 3 entradas

#### Scenario: Botão de histórico abre o modal

- **WHEN** o usuário aciona o botão de contagem de uma tarefa com 3 avanços
- **THEN** o modal de histórico SHALL abrir exibindo as 3 entradas

### Requirement: Coluna Ações

O sistema SHALL oferecer, na coluna Ações, editar a descrição da tarefa e excluir a
tarefa, exclusivamente para papéis `owner` e `edit` (§3.5, §4.1).

#### Scenario: Editar descrição atualiza a linha

- **WHEN** um usuário `edit` altera a descrição de `Fixar base` para
  `Fixar base do robô` e confirma
- **THEN** a coluna Tarefa SHALL exibir `Fixar base do robô` sem recarregar a página

#### Scenario: Excluir tarefa exige confirmação e remove a linha

- **WHEN** um usuário `edit` aciona excluir numa tarefa e confirma o diálogo
- **THEN** a linha SHALL desaparecer da tabela e o percentual ponderado do cabeçalho
  SHALL ser recalculado

### Requirement: Aviso de responsável faltando

O sistema SHALL exibir, na célula Responsáveis, o adorno "Atribuir…" com ícone de
alerta quando `progress > 0` e a tarefa não tiver nenhum responsável. O aviso NÃO
SHALL bloquear nenhuma ação (§3.5).

#### Scenario: Progresso 30 sem responsável exibe o aviso

- **WHEN** a tarefa tem `progress = 30` e `assignees = []`
- **THEN** a célula Responsáveis SHALL exibir `Atribuir…` com ícone de alerta

#### Scenario: Progresso 0 sem responsável não exibe o aviso

- **WHEN** a tarefa tem `progress = 0` e `assignees = []`
- **THEN** a célula Responsáveis NÃO SHALL exibir `Atribuir…`

#### Scenario: Aviso persiste quando há contribuidor mas nenhum responsável

- **WHEN** a tarefa tem `progress = 45`, `assignees = []` e um avanço registrado por
  `Bruno`
- **THEN** a célula SHALL exibir `Atribuir…` com ícone de alerta **e** o chip
  secundário `Bruno`

### Requirement: Aviso de trilha faltando

O sistema SHALL exibir, na célula Trilha, o adorno "Registre o avanço…" com ícone de
alerta quando `0 < progress < 100` e a tarefa não tiver nenhuma entrada de avanço. A
condição NÃO SHALL considerar o campo legado `obs`, que não existe no esquema novo
(§3.5, §1.4, D8).

#### Scenario: Progresso 50 sem avanços exibe o aviso

- **WHEN** a tarefa tem `progress = 50` e `advances_count = 0`
- **THEN** a célula Trilha SHALL exibir `Registre o avanço…` com ícone de alerta

#### Scenario: Progresso 100 sem avanços não exibe o aviso

- **WHEN** a tarefa tem `progress = 100` e `advances_count = 0`
- **THEN** a célula Trilha NÃO SHALL exibir `Registre o avanço…`

#### Scenario: Tarefa migrada com nota legada convertida não exibe o aviso

- **WHEN** a tarefa importada tinha `obs` preenchida e nenhum `history`, e o
  importador criou 1 entrada de avanço marcada `legacy`, resultando em
  `progress = 40` e `advances_count = 1`
- **THEN** a célula Trilha NÃO SHALL exibir `Registre o avanço…` e SHALL exibir o
  comentário da entrada legada

### Requirement: Pulso de confirmação aos 100%

O sistema SHALL aplicar a animação `successPulse` à linha da tarefa quando seu
progresso transitar de valor menor que 100 para 100, e SHALL suprimir a animação
quando `prefers-reduced-motion: reduce` estiver ativo (§3.5, DESIGN.md §Motion).

#### Scenario: Transição de 90 para 100 dispara o pulso

- **WHEN** o usuário confirma um avanço de `90 → 100` numa tarefa
- **THEN** a linha correspondente SHALL receber a classe de animação `successPulse`
  uma única vez

#### Scenario: Movimento reduzido suprime o pulso

- **WHEN** `prefers-reduced-motion: reduce` está ativo e um avanço de `90 → 100` é
  confirmado
- **THEN** a linha NÃO SHALL animar, e o status SHALL ser atualizado para `Concluído`
  normalmente

### Requirement: Refluxo mobile em cartões

O sistema SHALL substituir a tabela por cartões empilhados abaixo do breakpoint
`md`, preservando as seis informações de coluna, com alvos de toque de no mínimo
32px e no mínimo 40px nos controles de progresso e ações (§3.5, DESIGN.md, PRODUCT.md).

#### Scenario: Viewport de 375px renderiza cartões e não rolagem horizontal

- **WHEN** a tela do robô é renderizada num viewport de 375px de largura com 12
  tarefas
- **THEN** o conteúdo SHALL ser uma lista de 12 cartões, e o documento NÃO SHALL
  apresentar rolagem horizontal

#### Scenario: Alvos de toque atendem ao piso de tamanho

- **WHEN** a tela é renderizada num viewport de 375px
- **THEN** os botões `−`, `+`, editar e excluir SHALL ter caixa de toque de no mínimo
  40x40 CSS px, e nenhum controle interativo da tela SHALL ter dimensão menor que
  32x32 CSS px

#### Scenario: Separadores de categoria sobrevivem ao refluxo

- **WHEN** o robô tem tarefas em 3 categorias e a tela é renderizada em 375px
- **THEN** SHALL existir 3 cabeçalhos de seção, um por categoria, entre os cartões

### Requirement: Restrições por papel na tela do robô

O sistema SHALL ocultar da tela do robô todos os controles de mutação para membros
com papel `view`, e o servidor SHALL rejeitar essas mutações independentemente da
interface (§4.1, §4.1 inv. 1 e 4).

#### Scenario: Membro view não vê as ações de edição

- **WHEN** um membro com papel `view` abre a tela do robô
- **THEN** a tela NÃO SHALL renderizar "Adicionar tarefa", "Sincronizar tarefas-base",
  a coluna Ações, os botões `−`/`+` nem o slider

#### Scenario: Membro view vê o status como rótulo, não como controle

- **WHEN** um membro com papel `view` abre a tela do robô
- **THEN** o status de cada tarefa SHALL ser renderizado como badge estático, sem
  chevron, e NÃO SHALL ser renderizado como seletor desabilitado

#### Scenario: Servidor rejeita mutação de membro view mesmo sem interface

- **WHEN** um membro com papel `view` envia diretamente
  `PATCH /api/v1/tasks/<id>` alterando a descrição
- **THEN** a API SHALL responder `403` e a descrição persistida NÃO SHALL mudar

#### Scenario: Robô de outro workspace não é legível

- **WHEN** um usuário autenticado no workspace `W1` requisita
  `GET /api/v1/robots/<id de robô do workspace W2>/tasks`
- **THEN** a API SHALL responder `404` e NÃO SHALL vazar nome de robô, tarefa ou
  pessoa do workspace `W2`

### Requirement: Estados de carregamento, vazio e erro da tabela

O sistema SHALL apresentar estados explícitos de carregamento, lista vazia e falha de
leitura na tela do robô, sem exibir tabela parcialmente montada (§2.9, §3.5).

#### Scenario: Robô sem tarefas exibe estado vazio nomeado

- **WHEN** o robô existe e tem 0 tarefas
- **THEN** a tela SHALL exibir um estado vazio mencionando o nome do robô e a ação
  "Adicionar tarefa", e o cabeçalho SHALL exibir `0%`

#### Scenario: Falha de leitura oferece nova tentativa

- **WHEN** `GET /api/v1/robots/:id/tasks` responde `500`
- **THEN** a tela SHALL exibir mensagem de erro em pt-BR com um botão de nova
  tentativa, e NÃO SHALL exibir uma tabela vazia como se o robô não tivesse tarefas
