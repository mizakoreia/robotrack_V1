## ADDED Requirements

### Requirement: Página A4 retrato com margens definidas

O documento SHALL ser impresso em A4 retrato, com margens declaradas em
`@page { size: A4 portrait; margin: 18mm 14mm 20mm 14mm; }`. Nenhum conteúdo do
documento SHALL exceder a largura útil da folha, e o documento NÃO SHALL produzir
rolagem horizontal na visualização de impressão.

#### Scenario: Impressão em A4 não corta conteúdo na lateral

- **WHEN** o documento é impresso a partir de um escopo com nomes longos (robô com 60 caracteres e comentário de histórico com 400 caracteres)
- **THEN** todo o texto SHALL quebrar dentro da largura útil da folha
- **AND** nenhuma coluna da tabela de tarefas SHALL ser cortada na margem direita

#### Scenario: Cores e sombras da tela não vazam para o papel

- **WHEN** o documento é impresso com o tema escuro ativo na aplicação
- **THEN** o documento impresso SHALL usar fundo branco e texto escuro
- **AND** as barras de progresso SHALL permanecer legíveis em impressão monocromática (contorno + preenchimento, não apenas matiz)

### Requirement: Cabeçalho e rodapé repetidos em todas as páginas

O sistema SHALL repetir o cabeçalho (título e id do documento) e o rodapé (id, data
de geração e nota de rastreabilidade) em **todas** as páginas impressas, usando
`<thead>`/`<tfoot>` da tabela raiz de impressão. O conteúdo do corpo NÃO SHALL
sobrepor cabeçalho nem rodapé em nenhuma página.

#### Scenario: Documento de várias páginas repete cabeçalho e rodapé

- **WHEN** um escopo gera um documento de 12 páginas impressas
- **THEN** cada uma das 12 páginas SHALL conter o cabeçalho com o id `RT-AAAAMMDD-HHMM` e o rodapé
- **AND** o teste Playwright de impressão SHALL falhar se qualquer página não contiver ambos

#### Scenario: Corpo não passa por baixo do cabeçalho na segunda página

- **WHEN** o documento tem mais de uma página
- **THEN** a primeira linha de conteúdo da página 2 SHALL iniciar abaixo do cabeçalho repetido
- **AND** NÃO SHALL haver sobreposição de texto

### Requirement: Tarefa e seu histórico são indivisíveis na quebra de página

O bloco formado por uma tarefa e todas as suas entradas de histórico SHALL ser
tratado como unidade indivisível (`break-inside: avoid`). Cabeçalhos de projeto,
célula e robô NÃO SHALL ficar órfãos no pé da página (`break-after: avoid`). Os
blocos de assinatura SHALL ser indivisíveis. A seção Conclusões SHALL iniciar em
nova página.

#### Scenario: Tarefa com 6 entradas não é partida pela quebra

- **WHEN** uma tarefa com 6 entradas de histórico começaria a 3 linhas do fim da página
- **THEN** a tarefa inteira SHALL ser empurrada para a página seguinte
- **AND** nenhuma de suas entradas SHALL ficar em página diferente da linha da tarefa

#### Scenario: Cabeçalho de robô não fica sozinho no pé da página

- **WHEN** o cabeçalho do robô "R07 - Handling" cairia como último elemento de uma página
- **THEN** o cabeçalho SHALL ser movido para a página seguinte, junto de ao menos a primeira tarefa

#### Scenario: Tarefa maior que uma folha degrada com aviso de continuação

- **WHEN** uma tarefa tem 24 entradas de histórico (acima do limiar de 18) e não cabe em uma folha
- **THEN** o bloco SHALL poder quebrar entre páginas
- **AND** a quebra SHALL exibir a faixa `— histórico continua na próxima página —`

#### Scenario: Bloco de assinatura não é partido

- **WHEN** o bloco `Cliente / Aceite` começaria perto do fim da última página
- **THEN** o bloco inteiro SHALL ser movido para a página seguinte

#### Scenario: Conclusões começam em página nova

- **WHEN** o corpo hierárquico termina no meio de uma página
- **THEN** a seção Conclusões SHALL iniciar na página seguinte

### Requirement: Orçamento de volume com truncamento anunciado

O sistema SHALL aplicar tetos de volume por documento. Acima de 2.000 tarefas no
escopo, SHALL exibir aviso de escopo grande. Acima de 5.000 entradas de histórico no
escopo, SHALL truncar o histórico às 10 entradas mais recentes por tarefa e SHALL
declarar o truncamento no cabeçalho, no rodapé e em cada tarefa truncada. Acima de
8.000 tarefas, SHALL recusar a emissão com `422`. O truncamento NUNCA SHALL ser
silencioso.

#### Scenario: Escopo com 5.400 entradas trunca e anuncia

- **WHEN** o escopo `all` reúne 5.400 entradas de histórico e uma tarefa específica tem 31 entradas
- **THEN** essa tarefa SHALL exibir apenas as 10 entradas mais recentes por `recorded_at`
- **AND** SHALL exibir `(+21 entradas anteriores omitidas)` logo abaixo
- **AND** o cabeçalho e o rodapé SHALL declarar que o documento está com histórico truncado

#### Scenario: Escopo com 2.300 tarefas avisa mas não trunca

- **WHEN** o escopo tem 2.300 tarefas e 3.100 entradas de histórico
- **THEN** o documento SHALL exibir o aviso de escopo grande sugerindo emitir por projeto
- **AND** SHALL exibir todas as 3.100 entradas, sem truncamento

#### Scenario: Escopo acima do teto absoluto é recusado

- **WHEN** o escopo `all` reúne 8.400 tarefas
- **THEN** o sistema SHALL responder `422` com mensagem instruindo a emitir com `scope=project`
- **AND** NÃO SHALL montar payload nem iniciar a renderização

#### Scenario: Escopo típico não dispara aviso algum

- **WHEN** o escopo de um projeto reúne 210 tarefas e 480 entradas de histórico
- **THEN** o documento NÃO SHALL exibir aviso de escopo grande nem de truncamento

### Requirement: Conjunto fechado de glifos e ausência de emoji

O documento SHALL usar exclusivamente os quatro glifos tipográficos `✓`, `◐`, `○` e
`—` como símbolos de status. Nenhum emoji SHALL aparecer no documento nem em
qualquer outra parte da UI (§5.1). Os glifos SHALL vir de um mapa único no servidor.

#### Scenario: Sweep rejeita caractere fora do conjunto permitido

- **WHEN** um caractere emoji é introduzido em qualquer string do payload do relatório ou do componente
- **THEN** o teste de sweep de glifos SHALL falhar o CI nomeando o caractere e sua origem

#### Scenario: Glifos herdam a fonte do documento

- **WHEN** o documento é impresso num ambiente sem nenhuma fonte de emoji instalada
- **THEN** os quatro glifos SHALL ser renderizados pela fonte Inter, com o mesmo peso e alinhamento do texto ao redor
- **AND** NÃO SHALL aparecer caractere de substituição (tofu)

### Requirement: Estados de tela do relatório antes da impressão

A tela do relatório SHALL apresentar o seletor de escopo, um estado de carregamento
durante a montagem do payload, um estado de erro acionável, e um estado explícito
quando não houver conexão. O sistema NÃO SHALL montar o documento a partir de cache
parcial.

#### Scenario: Sem conexão informa em vez de emitir documento incompleto

- **WHEN** o usuário aciona a emissão sem conectividade
- **THEN** a tela SHALL informar que a emissão exige conexão e oferecer nova tentativa
- **AND** NÃO SHALL renderizar um documento a partir de dados em cache

#### Scenario: Falha do servidor não deixa documento pela metade na tela

- **WHEN** o endpoint responde `500` durante a montagem
- **THEN** a tela SHALL exibir estado de erro com ação de nova tentativa
- **AND** NÃO SHALL exibir cabeçalho, carimbo ou qualquer seção parcial do documento
