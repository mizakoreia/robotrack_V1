# Spec — `app-shell-navigation`

## ADDED Requirements

### Requirement: Casca persistente da aplicação

O sistema SHALL renderizar toda rota autenticada dentro de um layout único composto por
sidebar, barra de topo e área de conteúdo com rolagem própria. A sidebar e a barra de
topo MUST permanecer montadas entre navegações; apenas a área de conteúdo é substituída.

#### Scenario: Navegar entre destinos não remonta a casca

- **WHEN** o usuário está em `/` e clica em "Minhas Tarefas", indo para `/minhas-tarefas`
- **THEN** o componente de sidebar e o de topbar NÃO são desmontados nem remontados
- **AND** somente o conteúdo do outlet é substituído
- **AND** a área de conteúdo volta ao topo (`scrollTop = 0`)

#### Scenario: Rota de login fica fora da casca

- **WHEN** o usuário não autenticado acessa `/login`
- **THEN** nem a sidebar nem a topbar são renderizadas

#### Scenario: Área de conteúdo é a única com rolagem

- **WHEN** o conteúdo da Visão Geral tem 3000px de altura numa viewport de 800px
- **THEN** o elemento de conteúdo rola e `document.body` NÃO apresenta barra de rolagem
- **AND** a sidebar e a topbar permanecem visíveis na mesma posição

### Requirement: Sidebar com exatamente três destinos

A sidebar SHALL conter exatamente três destinos de navegação — "Visão Geral" (`/`),
"Minhas Tarefas" (`/minhas-tarefas`) e "Relatório" (`/relatorio`) — nesta ordem. Nenhum
item de configuração, equipe, catálogo, backup ou auditoria MUST aparecer na sidebar.

#### Scenario: A lista de destinos tem tamanho três

- **WHEN** a constante de destinos da sidebar é lida
- **THEN** ela contém exatamente 3 entradas
- **AND** os rótulos são "Visão Geral", "Minhas Tarefas" e "Relatório", nesta ordem

#### Scenario: Configuração não é destino de sidebar

- **WHEN** a sidebar é renderizada para um usuário com papel Dono
- **THEN** nenhum item com rótulo contendo "Configurações", "Equipe", "Backup" ou
  "Histórico" está presente entre os destinos

### Requirement: Estado ativo por preenchimento tintado, nunca faixa lateral

O destino correspondente à rota corrente SHALL ser marcado por fundo tintado com a cor
de accent e ícone em `--accent`. O sistema MUST NOT usar faixa/barra lateral como
indicador de estado ativo.

#### Scenario: Destino corrente recebe preenchimento e ícone em accent

- **WHEN** a rota corrente é `/minhas-tarefas`
- **THEN** o item "Minhas Tarefas" tem fundo tintado de accent e `aria-current="page"`
- **AND** seu ícone usa `--accent` como `currentColor`
- **AND** os itens "Visão Geral" e "Relatório" não têm fundo tintado nem `aria-current`

#### Scenario: Nenhum item ativo desenha faixa lateral

- **WHEN** o item ativo é inspecionado
- **THEN** ele NÃO possui `border-left` nem pseudo-elemento de barra vertical como
  indicador de seleção

#### Scenario: Rota aninhada mantém o destino raiz ativo

- **WHEN** a rota corrente é `/projeto/8f2a/celula/1c9b`
- **THEN** o item "Visão Geral" está ativo

### Requirement: Rodapé da sidebar com indicador de gravação e card de usuário

O rodapé da sidebar SHALL exibir o indicador de gravação e, abaixo dele, um card de
usuário mostrando o **nome sobre o e-mail**. Acionar o card SHALL abrir o menu "Edição e
visualização" com exatamente três itens: tarefas/equipe/filtros, logs & histórico e
backup.

#### Scenario: Card de usuário mostra nome sobre e-mail

- **WHEN** o usuário autenticado é "Ana Ribeiro" com e-mail `ana@fabrica.com.br`
- **THEN** o card exibe "Ana Ribeiro" na primeira linha e `ana@fabrica.com.br` na segunda
- **AND** o e-mail é truncado com reticências se exceder a largura, sem quebrar linha

#### Scenario: Menu "Edição e visualização" tem três itens

- **WHEN** o usuário aciona o card de usuário
- **THEN** um menu é aberto com exatamente 3 itens de comando, nesta ordem: "Tarefas,
  equipe e filtros", "Logs e histórico" e "Backup"

#### Scenario: Usuário sem nome de exibição cai para o e-mail

- **WHEN** o usuário autenticado tem nome vazio e e-mail `joao@fabrica.com.br`
- **THEN** a primeira linha do card exibe `joao@fabrica.com.br`
- **AND** a segunda linha não é renderizada (o e-mail não aparece duplicado)

### Requirement: Barra de topo com contexto à esquerda e conta à direita

A barra de topo SHALL posicionar o contexto do workspace (seletor e badge de papel) à
esquerda e o gatilho da conta à direita. O menu da conta SHALL conter exatamente três
itens: adicionar usuário, alternar tema e sair.

#### Scenario: Menu da conta tem três itens

- **WHEN** o usuário aciona o gatilho da conta
- **THEN** um menu é aberto com 3 itens: "Adicionar usuário", "Alternar tema" e "Sair"

#### Scenario: Alternar tema fecha o menu e persiste a escolha

- **WHEN** o tema corrente é escuro e o usuário escolhe "Alternar tema"
- **THEN** o tema passa a claro, a escolha é persistida localmente e o menu fecha

#### Scenario: Sair limpa sessão e cache

- **WHEN** o usuário escolhe "Sair"
- **THEN** o token é removido do store de auth, `queryClient.clear()` é chamado
- **AND** o usuário é levado a `/login`

#### Scenario: A topbar expõe um slot nomeado para o gatilho de notificações

- **WHEN** a barra de topo é renderizada sem nenhum gatilho de notificações registrado
- **THEN** o slot existe e está vazio, e o layout da barra não se desloca

### Requirement: Gaveta de navegação em viewport estreita

Em viewport com largura inferior a 768px, a sidebar SHALL ser recolhida e acessível como
gaveta sobreposta acionada por um botão na barra de topo. O indicador de gravação MUST
permanecer visível na barra de topo enquanto a gaveta está fechada.

#### Scenario: Sidebar vira gaveta a 375px

- **WHEN** a viewport tem 375px de largura
- **THEN** a sidebar não ocupa espaço no fluxo do layout
- **AND** um botão com `aria-label` "Abrir navegação" está presente na barra de topo

#### Scenario: Indicador de gravação continua alcançável com a gaveta fechada

- **WHEN** a viewport tem 375px, a gaveta está fechada e há 1 mutation em voo
- **THEN** o estado `salvando` é visível na barra de topo

#### Scenario: Escolher um destino fecha a gaveta

- **WHEN** a gaveta está aberta a 375px e o usuário escolhe "Relatório"
- **THEN** a navegação ocorre e a gaveta fecha

### Requirement: Menus suspensos renderizados como filhos da raiz do documento

Todo menu suspenso SHALL ser renderizado por portal em um contêiner de overlays que é
filho direto de `<body>`, com `position: fixed` e coordenadas de viewport derivadas do
retângulo do gatilho. O sistema MUST NOT posicionar menus com `position: absolute`
dentro da área de conteúdo rolável.

#### Scenario: Menu não é descendente do contêiner rolável

- **WHEN** o menu do card de usuário está aberto
- **THEN** o elemento do menu é descendente de `#rt-overlays`, que é filho direto de
  `<body>`
- **AND** o elemento do menu NÃO é descendente do elemento de conteúdo rolável

#### Scenario: Menu do rodapé não é recortado pela área rolável

- **WHEN** a área de conteúdo está rolada 400px e o menu do card de usuário é aberto
- **THEN** a altura visível do menu é igual à sua altura medida (nenhum recorte)

### Requirement: Menus são medidos antes de abrir para escolher a direção

O sistema SHALL medir as dimensões do menu antes de torná-lo visível e SHALL abri-lo para
cima quando não houver espaço abaixo do gatilho. Nenhuma pintura do menu em posição
provisória MUST ser visível ao usuário.

#### Scenario: Menu perto do rodapé abre para cima

- **WHEN** a viewport tem 800px de altura, o gatilho do card de usuário tem
  `bottom = 780` e o menu mede 220px de altura
- **THEN** o menu é posicionado com `bottom` alinhado ao topo do gatilho (abre para cima)
- **AND** o topo do menu está dentro da viewport (`top >= 8`)

#### Scenario: Menu com espaço suficiente abre para baixo

- **WHEN** o gatilho da conta tem `bottom = 56` numa viewport de 800px e o menu mede
  180px
- **THEN** o menu é posicionado abaixo do gatilho, com `top = 64`

#### Scenario: Menu maior que a viewport rola internamente

- **WHEN** o menu mede 900px de altura numa viewport de 700px
- **THEN** a altura do menu é limitada ao espaço disponível menos 16px
- **AND** o menu apresenta rolagem interna, e a viewport não rola

#### Scenario: Menu que estouraria a borda direita é deslocado para dentro

- **WHEN** o gatilho está a 40px da borda direita e o menu mede 260px de largura
- **THEN** o menu é deslocado para a esquerda, com margem mínima de 8px da borda direita

#### Scenario: Nenhum frame com o menu visível fora de posição

- **WHEN** um menu é aberto
- **THEN** durante a fase de medição o menu tem `visibility: hidden`
- **AND** ele nunca é renderizado com `display: none` (que zeraria as dimensões medidas)

### Requirement: Fechamento de menus e devolução do foco

Um menu aberto SHALL fechar em clique fora, `Escape`, rolagem da área de conteúdo,
redimensionamento da janela e escolha de item. Ao fechar por `Escape`, por clique fora ou
por rolagem, o foco MUST retornar ao gatilho que o abriu.

#### Scenario: Escape fecha e devolve o foco ao gatilho

- **WHEN** o menu da conta está aberto com o foco no primeiro item e o usuário pressiona
  `Escape`
- **THEN** o menu fecha
- **AND** `document.activeElement` é o gatilho da conta

#### Scenario: Rolar o conteúdo fecha o menu

- **WHEN** o menu do card de usuário está aberto e a área de conteúdo é rolada em 30px
- **THEN** o menu fecha
- **AND** o foco retorna ao gatilho

#### Scenario: Clique fora fecha sem ativar o alvo do clique

- **WHEN** o menu da conta está aberto e o usuário pressiona o ponteiro sobre um card na
  área de conteúdo
- **THEN** o menu fecha e o card NÃO é acionado nesse mesmo gesto

#### Scenario: Escolher um item fecha o menu

- **WHEN** o menu "Edição e visualização" está aberto e o usuário escolhe "Backup"
- **THEN** o menu fecha e a ação de backup é acionada uma única vez

#### Scenario: Redimensionar a janela fecha o menu

- **WHEN** um menu está aberto e a largura da janela muda de 1280px para 900px
- **THEN** o menu fecha

#### Scenario: Teclado virtual não fecha o menu indevidamente

- **WHEN** um menu está aberto e ocorre `resize` com a mesma largura e redução de altura
  de 80px
- **THEN** o menu permanece aberto

#### Scenario: Escape com menu aberto sobre modal não fecha o modal

- **WHEN** um modal está aberto, um menu foi aberto a partir dele, e `Escape` é
  pressionado uma vez
- **THEN** apenas o menu fecha e o modal permanece aberto

### Requirement: Navegação por teclado nos menus

Um menu aberto SHALL ser navegável por `ArrowDown`, `ArrowUp`, `Home` e `End`, com foco
inicial no primeiro item e ciclo entre extremos. Cada gatilho de menu MUST declarar
`aria-haspopup="menu"` e `aria-expanded`.

#### Scenario: Setas percorrem os itens com ciclo

- **WHEN** o menu da conta (3 itens) está aberto com foco no item 1 e `ArrowUp` é
  pressionado
- **THEN** o foco vai para o item 3

#### Scenario: Atributos ARIA acompanham o estado

- **WHEN** o gatilho da conta está fechado
- **THEN** ele tem `aria-expanded="false"`
- **AND** após ser acionado, ele tem `aria-expanded="true"`

#### Scenario: Botão só de ícone tem rótulo acessível

- **WHEN** o botão de abrir navegação é renderizado
- **THEN** ele possui `aria-label` não vazio e alvo de toque de ao menos 32×32px

### Requirement: Indicador de gravação com três estados honestos

O indicador de gravação SHALL exibir `salvando`, `salvo` ou `erro`, derivados
exclusivamente do store de persistência, com a precedência: `erro` acima de `salvando`,
`salvando` acima de `salvo`. O estado `salvo` MUST NOT expirar por tempo.

#### Scenario: Mutation em voo mostra "salvando"

- **WHEN** `inFlight = 1` e `failed = 0`
- **THEN** o indicador exibe o estado `salvando`

#### Scenario: Erro tem precedência sobre gravação em curso

- **WHEN** `inFlight = 2` e `failed = 1`
- **THEN** o indicador exibe o estado `erro`

#### Scenario: "salvo" permanece visível indefinidamente

- **WHEN** a última mutation foi concluída com sucesso há 10 minutos, `inFlight = 0`,
  `queued = 0` e `failed = 0`
- **THEN** o indicador continua exibindo `salvo`

#### Scenario: Fila offline não vazia é "salvando", nunca "salvo"

- **WHEN** `inFlight = 0`, `queued = 3` e `failed = 0`
- **THEN** o indicador exibe `salvando`

#### Scenario: Antes da primeira mutação nada é exibido

- **WHEN** a sessão acabou de iniciar e `inFlight = 0`, `queued = 0`, `failed = 0`,
  `lastSavedAt = null`
- **THEN** o indicador não renderiza rótulo algum

#### Scenario: Erro não se apaga por tempo

- **WHEN** `failed = 1` e passam 60 segundos sem nova mutation
- **THEN** o indicador continua exibindo `erro`

### Requirement: Contrato de escrita do store de persistência

O store de persistência SHALL expor exatamente as operações `beginMutation(id)`,
`settleMutation(id, resultado)` e `setQueueDepth(n)` como única forma de alterar seu
estado. Nenhum componente de UI MUST escrever os contadores diretamente.

#### Scenario: Par begin/settle equilibra o contador

- **WHEN** `beginMutation('a')` e `beginMutation('b')` são chamados e em seguida
  `settleMutation('a', 'ok')`
- **THEN** `inFlight = 1` e `failed = 0`

#### Scenario: settle com erro incrementa failed e decrementa inFlight

- **WHEN** `inFlight = 1` e `settleMutation('a', 'error')` é chamado
- **THEN** `inFlight = 0` e `failed = 1`

#### Scenario: settle duplicado do mesmo id é ignorado

- **WHEN** `beginMutation('a')` é chamado e `settleMutation('a', 'ok')` é chamado duas
  vezes
- **THEN** `inFlight = 0` e não fica negativo

#### Scenario: Sucesso posterior zera o estado de erro

- **WHEN** `failed = 1` e uma mutation de reenvio conclui com `settleMutation('a', 'ok')`
  levando `failed` a 0
- **THEN** o indicador passa de `erro` para `salvo`
