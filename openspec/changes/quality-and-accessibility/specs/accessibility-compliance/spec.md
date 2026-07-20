# accessibility-compliance

## ADDED Requirements

### Requirement: Contraste calculado com composição alfa, nos dois temas

O sistema SHALL calcular a razão de contraste WCAG 2.1 de cada par de cores
declarado na matriz, **compondo as camadas alfa** antes do cálculo
(`--bg-panel` sobre `--bg-main`, pílula tingida a 15% sobre o painel,
`--bg-sunken` sobre o painel), e SHALL comparar o valor computado com o valor
esperado literal, falhando se divergir em mais de `0.01` para qualquer lado
(D-QA-3). O mínimo — `4.5:1` para texto de corpo, `3.0:1` para elemento não
textual — SHALL ser codificado **separadamente** da tabela de valores esperados.

#### Scenario: Texto de corpo no tema escuro bate os valores medidos
- **WHEN** o teste calcula `--text-main #f8fafc` sobre `--bg-main #0a0f1d` e sobre
  `--bg-panel` resolvido (`rgba(18,26,47,0.7)` sobre `--bg-main` = `rgb(15,22,39)`)
- **THEN** SHALL obter `18.26:1` e `17.09:1` respectivamente

#### Scenario: Texto secundário no tema escuro bate os valores medidos
- **WHEN** o teste calcula `--text-muted #94a3b8` sobre `--bg-main`, sobre
  `--bg-panel` e sobre `--bg-sunken` composto
- **THEN** SHALL obter `7.45:1`, `6.97:1` e `7.38:1` — os três acima de `4.5:1`

#### Scenario: Texto de corpo no tema claro bate os valores medidos
- **WHEN** o teste calcula `--text-main #0f172a` sobre `--bg-main #f1f5f9` e
  `--text-muted #475569` sobre `--bg-panel` resolvido `rgb(253,254,254)`
- **THEN** SHALL obter `16.30:1` e `7.51:1`

#### Scenario: Tabela desatualizada falha mesmo quando o valor melhora
- **WHEN** alguém altera `--text-muted` no tema claro de `#475569` para `#334155`,
  elevando o contraste sobre o painel de `7.51:1` para além do esperado
- **THEN** o teste SHALL falhar — a divergência força atualizar a tabela
  conscientemente, que é o que impediria o `DESIGN.md` de voltar a afirmar um
  número que ninguém verificou

#### Scenario: Baixar o mínimo não faz o teste passar
- **WHEN** alguém atualiza a tabela de esperados para aceitar `3.9:1` num par de
  texto de corpo
- **THEN** o teste SHALL ainda falhar contra o piso de `4.5:1`, que é constante
  independente da tabela

### Requirement: Correção dos três tokens que reprovam AA

O sistema SHALL corrigir os três pares medidos que reprovam: `--accent-solid` com
texto branco (**3.68:1**), `--danger-solid` com texto branco (**3.76:1**), e a
tinta de `N/A` sobre a própria pílula no tema claro (**2.25:1**).

#### Scenario: Botão primário com texto branco passa AA nos dois temas
- **WHEN** `--accent-solid` é `#2563eb` e o teste calcula branco sobre ele
- **THEN** SHALL obter `5.17:1`, **E** o valor anterior `#3b82f6` (`3.68:1`) SHALL
  fazer o teste falhar se reintroduzido — inclusive em `.btn-primary`,
  `.filter-btn.active` e nos botões de swipe, que são os três consumidores

#### Scenario: Botão de perigo com texto branco passa AA nos dois temas
- **WHEN** `--danger-solid` é `#dc2626` no tema escuro e `#b91c1c` no tema claro
- **THEN** o branco sobre eles SHALL dar `4.83:1` e `6.47:1` respectivamente

#### Scenario: Pílula N/A no tema claro deixa de ser ilegível
- **WHEN** a tinta de `N/A` no tema claro passa de `#a1a1aa` para `#52525b`, sobre a
  pílula `N/A` resolvida `rgb(233,233,234)`
- **THEN** SHALL obter `6.09:1` — o valor anterior era `2.25:1`, abaixo até do
  mínimo de elemento não textual

#### Scenario: A tinta de N/A no escuro permanece e a assimetria é intencional
- **WHEN** o teste calcula `#a1a1aa` sobre a pílula `N/A` do tema escuro
- **THEN** SHALL obter `5.46:1` e passar sem alteração — a assimetria com o tema
  claro é a mesma já documentada para azul e vermelho: a pílula escurece o fundo no
  escuro e o clareia no claro

#### Scenario: A variante `-ink` é provada necessária, não redundante
- **WHEN** o teste calcula a cor **cheia** usada como texto sobre a própria pílula
  no tema claro para success, warning, danger e accent
- **THEN** SHALL obter `2.18:1`, `1.90:1`, `3.07:1` e `3.07:1` — as quatro reprovam,
  **E** as mesmas com a variante `-ink` (`#065f46`, `#92400e`, `#991b1b`, `#1e40af`)
  SHALL dar `6.62:1`, `6.27:1`, `6.77:1` e `7.28:1`

#### Scenario: Anel de progresso contra a trilha passa o mínimo não textual
- **WHEN** o teste calcula `--accent` contra `--track` nos dois temas
- **THEN** SHALL obter `3.80:1` (escuro) e `4.00:1` (claro), acima do mínimo de
  `3.0:1` para elemento gráfico

### Requirement: Foco visível medido em `:focus-visible`

O sistema SHALL expor indicador de foco em todo elemento que recebe teclado,
exclusivamente via `:focus-visible`, com contorno cuja razão de contraste contra a
superfície adjacente SHALL ser ≥ `3.0:1` nos dois temas, e espessura ≥ `2px`.
`outline: none` global SHALL não existir.

#### Scenario: Contorno de foco atinge o mínimo medido no tema escuro
- **WHEN** o contorno de foco usa `#60a5fa` e o teste o calcula contra `--bg-main`
  e contra `--bg-panel`
- **THEN** SHALL obter `7.52:1` e `7.03:1`, ambos acima de `3.0:1`

#### Scenario: Contorno de foco atinge o mínimo medido no tema claro
- **WHEN** o contorno de foco usa `#1d4ed8` e o teste o calcula contra `--bg-main` e
  contra `--bg-panel`
- **THEN** SHALL obter `6.12:1` e `6.64:1`

#### Scenario: Clique com mouse não desenha o anel de foco
- **WHEN** o usuário clica com o mouse em um botão de ícone
- **THEN** o contorno SHALL não aparecer, **E** ao navegar até o mesmo botão com
  `Tab` o contorno SHALL aparecer — é a distinção que `:focus-visible` existe para
  fazer e a razão de o `outline: none` global ter saído

#### Scenario: Nenhuma regra global apaga o contorno
- **WHEN** o sweep de CSS varre `styles/globals.css` e os arquivos de token
- **THEN** SHALL falhar se encontrar `outline: none` ou `outline: 0` em seletor que
  não seja acompanhado, no mesmo bloco ou em bloco irmão `:focus-visible`, de uma
  substituição visível

### Requirement: Navegação por teclado com setas e Esc devolvendo o foco

O sistema SHALL permitir operar menus, filtros segmentados e modais inteiramente
por teclado. Menus SHALL navegar por `ArrowUp`/`ArrowDown` com `Home`/`End`, e
`Escape` SHALL fechar devolvendo o foco **ao elemento gatilho**. Modais SHALL
prender o foco.

#### Scenario: Esc devolve o foco ao gatilho, não ao body
- **WHEN** o usuário abre o menu da conta com `Enter`, desce duas vezes com
  `ArrowDown` e pressiona `Escape`
- **THEN** `document.activeElement` SHALL ser o botão gatilho do menu — perder o
  foco para o `<body>` joga o usuário de teclado para o topo da página a cada menu
  fechado

#### Scenario: Foco preso no modal e devolvido ao fechar
- **WHEN** o modal de avanço está aberto e o usuário pressiona `Tab` até o último
  elemento focável e mais uma vez
- **THEN** o foco SHALL voltar ao primeiro elemento do modal, nunca alcançar o
  conteúdo atrás do overlay, **E** ao fechar com `Escape` o foco SHALL voltar ao
  controle que abriu o modal

#### Scenario: Setas percorrem o menu e não rolam a página
- **WHEN** o menu está aberto e o usuário pressiona `ArrowDown`
- **THEN** o foco SHALL ir para o próximo item, **E** a página atrás SHALL não
  rolar — o `preventDefault` é obrigatório, senão o menu "anda" junto com o
  conteúdo

#### Scenario: O filtro segmentado da tela do robô é operável por teclado
- **WHEN** o usuário tabula até o filtro segmentado (§3.5) e pressiona `ArrowRight`
- **THEN** a segmentação SHALL avançar e aplicar o filtro, **E** o estado ativo
  SHALL ser exposto por `aria-pressed` ou `aria-checked` — cor sozinha não comunica
  seleção a leitor de tela

#### Scenario: Toda tela principal é alcançável sem mouse
- **WHEN** o teste percorre Visão Geral, Projeto, Célula, Robô, Minhas Tarefas e
  Relatório apenas com `Tab`, `Enter`, setas e `Escape`
- **THEN** SHALL conseguir abrir o modal de avanço, alterar um status e voltar à
  Visão Geral sem nenhum evento de mouse

### Requirement: Três regiões `aria-live` no shell, montadas uma única vez

O sistema SHALL expor exatamente três regiões vivas, montadas no shell do app antes
de qualquer conteúdo e nunca renderizadas condicionalmente: `#rt-status`
(`polite`, `aria-atomic="true"`), `#rt-notifications` (`polite`) e `#rt-alerts`
(`assertive`, `role="alert"`) (D-QA-4).

#### Scenario: As regiões existem antes de haver o que anunciar
- **WHEN** o shell é montado sem nenhuma rota carregada
- **THEN** os três elementos SHALL existir no DOM e estar vazios — uma região
  inserida junto com seu texto não é anunciada por leitor de tela nenhum, e esse
  erro passa em qualquer teste de snapshot

#### Scenario: Indicador de gravação anuncia em `polite`
- **WHEN** um avanço é salvo e `_ind('saved')` dispara
- **THEN** o texto de estado salvo SHALL aparecer em `#rt-status`, **E** SHALL não
  aparecer em `#rt-alerts` — anunciar cada gravação em `assertive` interromperia o
  leitor dezenas de vezes por turno

#### Scenario: Falha de persistência anuncia em `assertive`
- **WHEN** o `POST` do avanço falha e `_ind('error')` dispara
- **THEN** a mensagem de erro SHALL ir para `#rt-alerts` — a ação em curso da
  pessoa deixou de ser possível, que é a régua para interromper

#### Scenario: Perda de acesso ao workspace anuncia em `assertive`
- **WHEN** a membership é revogada ao vivo com a tela aberta
- **THEN** a mensagem SHALL ir para `#rt-alerts`, não para `#rt-notifications`

#### Scenario: Nenhum `aria-live` fora do shell
- **WHEN** o sweep varre `frontend/src/` em busca de `aria-live` e `role="alert"`
- **THEN** SHALL falhar se encontrá-los fora do módulo do shell — duas regiões
  vivas visíveis ao mesmo tempo produzem anúncio duplicado ou engolido conforme o
  leitor

### Requirement: Semântica ARIA de progresso, ícones e botões só-ícone

O sistema SHALL expor barras de progresso como `role="progressbar"` com
`aria-valuenow`, `aria-valuemin="0"`, `aria-valuemax="100"` e `aria-valuetext` em
pt-BR; anéis como `role="img"` com `aria-label` completo incluindo o rótulo da
métrica (D15); ícones decorativos com `aria-hidden="true"`; e botões só-ícone com
`aria-label` (D-QA-5).

#### Scenario: Anel expõe rótulo completo com a métrica nomeada
- **WHEN** o anel do robô `R01 - Solda` está em 100% ponderado
- **THEN** o `aria-label` SHALL ser exatamente
  `Progresso do robô R01 - Solda: 100 por cento, ponderado` — sem o nome da métrica
  o usuário de leitor de tela recebe um número que não sabe conciliar com a
  contagem crua do hub ao lado

#### Scenario: Barra do hub expõe valor e texto
- **WHEN** o hub exibe `12/40` tarefas concluídas
- **THEN** o elemento SHALL ter `role="progressbar"`, `aria-valuenow="30"` e
  `aria-valuetext="12 de 40 tarefas concluídas, contagem"`

#### Scenario: Anel a 0% continua anunciando o valor
- **WHEN** o progresso é 0 e o traço do SVG é omitido por decisão visual
- **THEN** o `aria-label` SHALL ainda declarar `0 por cento` — a omissão é do traço,
  não do dado

#### Scenario: Botão só-ícone tem rótulo textual
- **WHEN** o sweep varre os componentes em busca de `<button>` cujo único filho é um
  `<svg class="ic">`
- **THEN** SHALL falhar para todo botão sem `aria-label` ou `aria-labelledby`,
  nomeando arquivo e linha

#### Scenario: Ícone dentro de botão rotulado é escondido
- **WHEN** um botão tem ícone **e** texto
- **THEN** o `<svg>` SHALL ter `aria-hidden="true"` — senão o leitor anuncia o nome
  do símbolo antes do rótulo

#### Scenario: O `status-select` é anunciado como controle, não como rótulo
- **WHEN** o leitor de tela alcança a pílula de status da tabela do robô
- **THEN** SHALL anunciá-la como combobox com valor e rótulo acessível — a regra
  visual do `DESIGN.md` (*badge é rótulo, select é controle*) SHALL valer também na
  árvore de acessibilidade

#### Scenario: O pulso de 100% não rouba o foco
- **WHEN** outra pessoa conclui a última tarefa de um robô e o `successPulse`
  dispara na tela de quem está digitando um comentário
- **THEN** `document.activeElement` SHALL permanecer no campo de comentário, **E** o
  anúncio SHALL ir para `#rt-status` — mover foco por evento remoto é hostil e é
  falha de WCAG 3.2

### Requirement: Movimento reduzido respeitado sem perda de conteúdo

O sistema SHALL zerar animações e transições sob `prefers-reduced-motion: reduce`,
e SHALL manter a luz ambiente **existente e parada** na posição de repouso, sem
nenhuma informação exclusiva de animação.

#### Scenario: Nenhuma animação roda sob movimento reduzido
- **WHEN** a página carrega com `prefers-reduced-motion: reduce` e o teste inspeciona
  `getAnimations()` do documento após a entrada de view
- **THEN** SHALL retornar lista vazia

#### Scenario: A luz ambiente fica, mas não se move
- **WHEN** o cursor percorre a viewport sob movimento reduzido
- **THEN** `--lx` e `--ly` SHALL permanecer no valor de repouso, **E** as camadas
  `.ambient`, `.glass-sheen` e `.glass` SHALL continuar renderizadas — desligar a
  luz junto com o movimento removeria o sistema visual de quem pediu menos animação

#### Scenario: O pulso de 100% continua comunicando sem animar
- **WHEN** uma tarefa chega a 100% sob movimento reduzido
- **THEN** o estado concluído SHALL ser legível pelo badge e pelo anel, **E** o
  anúncio SHALL ir para `#rt-status` — a animação é reforço, nunca requisito para
  ver o conteúdo (`PRODUCT.md §Accessibility & Inclusion`)

### Requirement: Alvo de toque mínimo de 32px por requisito de ambiente

O sistema SHALL garantir área de toque ≥ `32×32 CSS px` em todo controle tocável —
botões de ícone, `.status-select`, chips clicáveis, itens de menu e segmentos de
filtro — via tamanho real ou área estendida por pseudo-elemento. O mínimo excede os
`24px` de WCAG 2.2 AA por requisito de ambiente: uso **de luva**, no escuro do
galpão (`PRODUCT.md §Users`).

#### Scenario: Controle abaixo de 32px reprova nomeando o seletor
- **WHEN** o teste mede o retângulo de todos os controles tocáveis na tela do robô,
  em viewport de 375×812
- **THEN** SHALL falhar para qualquer um com largura ou altura efetiva < 32px,
  nomeando o seletor e as duas dimensões medidas

#### Scenario: Área estendida por pseudo-elemento conta
- **WHEN** um botão de ícone tem 24px visuais mas `::after` estendendo a área
  clicável para 36px
- **THEN** SHALL passar — o critério é a área que responde ao toque, não a caixa
  pintada

#### Scenario: Controles adjacentes não se sobrepõem
- **WHEN** dois botões de ícone vizinhos têm áreas estendidas
- **THEN** as áreas SHALL não se interceptar — sobreposição faz o dedo de luva
  acionar o botão errado, que é pior que o alvo pequeno

#### Scenario: Link de texto em fluxo é isento
- **WHEN** o teste encontra um link dentro de um parágrafo de texto corrido
- **THEN** SHALL não aplicar o mínimo de 32px — a isenção é a mesma de WCAG 2.5.8 e
  está declarada para que ninguém a resolva inflando a altura de linha

### Requirement: Gate `axe-core` em oito telas nos dois temas

O sistema SHALL rodar `axe-core` (regras `wcag2a`, `wcag2aa`, `wcag21aa`,
`wcag22aa`) sobre Visão Geral, Projeto, Célula, Robô, Minhas Tarefas, Relatório,
Configurações e Login, em ambos os temas — 16 varreduras — reprovando o CI com
qualquer violação de impacto `serious` ou `critical`.

#### Scenario: Violação séria reprova o CI com localização
- **WHEN** uma varredura encontra `button-name` com impacto `critical`
- **THEN** o job SHALL falhar reportando a regra, o seletor do nó e a tela+tema em
  que ocorreu

#### Scenario: Ambos os temas são varridos, não só o padrão
- **WHEN** o gate roda
- **THEN** SHALL haver 16 resultados de varredura — o tema claro é o menos usado e
  por isso é onde a regressão mora, como a tinta de `N/A` a `2.25:1` demonstrou

#### Scenario: Resultado `incomplete` de contraste não é tratado como aprovação
- **WHEN** o axe retorna `incomplete` na regra de contraste por causa do
  `backdrop-filter` das superfícies de vidro
- **THEN** o gate SHALL não contar como aprovação, **E** SHALL exigir que o par
  correspondente esteja coberto pela matriz calculada — é a razão de as duas
  abordagens coexistirem

#### Scenario: Modal aberto também é varrido
- **WHEN** a varredura da tela do robô ocorre
- **THEN** SHALL incluir uma passagem com o modal de avanço aberto — o modal é onde
  moram o foco preso e o rótulo de campo, e ele não existe no DOM da tela em repouso
