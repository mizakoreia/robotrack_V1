# Spec — `ui-primitives`

Componentes base em `frontend/src/components/ui/`, feitos à mão no padrão já estabelecido
pelo template (objetos de variante + `cn()`), **sem Radix e sem CVA**.

## ADDED Requirements

### Requirement: Card com badge em linha própria e altura uniforme

O sistema SHALL renderizar o badge do card em uma linha própria (`.card-meta`), nunca
inline com o título, e SHALL fazer com que cards da mesma linha da grade tenham altura
igual, com o rodapé alinhado à base.

*Porquê (§5.2): com o badge junto ao título, títulos longos quebram em um card e não em
outro, e os anéis da grade saem desalinhados na horizontal.*

#### Scenario: título longo não empurra o badge nem desalinha o anel

- **WHEN** dois cards são renderizados lado a lado na mesma linha, um com título `"Robô 1"` e outro com título `"Robô de solda ponto lateral direito — estação 07"`
- **THEN** o `offsetTop` do anel de progresso é idêntico nos dois cards
- **AND** o badge de cada card está em um elemento irmão do título, não dentro dele

#### Scenario: cards da mesma linha têm altura igual

- **WHEN** três cards com quantidades diferentes de texto são renderizados na mesma linha
- **THEN** os três têm a mesma `offsetHeight`
- **AND** o rodapé de cada um está alinhado na mesma coordenada vertical (`mt-auto`)

#### Scenario: o selo de ícone não codifica tipo por cor

- **WHEN** um card de projeto e um card de robô são renderizados
- **THEN** o `background-color` computado dos dois `.entity-ic` é o mesmo tom de `--accent`

### Requirement: Anel de progresso omite o traço a 0%

O sistema SHALL renderizar o anel de progresso como um `<path>` SVG e SHALL **não
renderizar** o path de progresso quando o valor é exatamente 0.

*Porquê (§5.2): com `stroke-linecap: round`, um traço de comprimento zero é desenhado como
um ponto, e um ponto num anel a 0% comunica avanço que não existe.*

#### Scenario: a 0% não existe path de progresso no DOM

- **WHEN** `<ProgressRing value={0} />` é renderizado
- **THEN** o SVG contém apenas o path do trilho (`--track`)
- **AND** nenhum elemento com a classe do path de progresso existe no DOM
- **AND** o teste falha explicitamente se o path existir com `stroke-dasharray: 0` — omitir não é o mesmo que zerar

#### Scenario: a 1% o traço aparece

- **WHEN** o valor passa de `0` para `1`
- **THEN** o path de progresso passa a existir no DOM
- **AND** seu `stroke-linecap` computado é `round`

#### Scenario: acessibilidade do anel

- **WHEN** `<ProgressRing value={45} label="Progresso do robô R07" />` é renderizado
- **THEN** o SVG tem `role="img"`
- **AND** seu nome acessível contém `"45"`

#### Scenario: o percentual usa números tabulares

- **WHEN** o anel exibe `9%` e depois `99%`
- **THEN** a largura medida do texto do percentual não muda por dígito, apenas por contagem de caracteres

### Requirement: Barra do hub anima por transform, não por width

O sistema SHALL animar a barra de progresso do hub analítico com
`transform: scaleX()` e `transform-origin: left`, e SHALL NÃO animar a propriedade `width`.

*Porquê (§5.2): animar `width` dispara layout a cada frame; com 24 cards e um hub em tela
isso é jank visível no celular do chão de fábrica. `scaleX` roda no compositor.*

#### Scenario: a barra a 45% usa scaleX, não width

- **WHEN** `<Hub label="Robôs concluídos" value={9} total={20} />` é renderizado
- **THEN** o `transform` computado do preenchimento é `matrix(0.45, 0, 0, 1, 0, 0)`
- **AND** sua `width` computada é `100%`, constante e independente do valor
- **AND** a `transition-property` computada contém `transform` e não contém `width`

#### Scenario: estrutura e acessibilidade do hub

- **WHEN** o hub é renderizado
- **THEN** o rótulo pequeno aparece acima do valor grande
- **AND** a barra tem `role="progressbar"` com `aria-valuenow="45"`, `aria-valuemin="0"` e `aria-valuemax="100"`

### Requirement: Badge é rótulo estático

O sistema SHALL renderizar `Badge` como pílula tingida **estática**, com texto sempre em
`--*-ink`, sem chevron, sem estado de foco e sem manipulador de clique.

#### Scenario: badge não aceita chevron

- **WHEN** o tipo de `Badge` é inspecionado
- **THEN** ele não expõe prop `chevron`
- **AND** passar `onClick` é erro de tipo

#### Scenario: o texto do badge usa a tinta, não a cor cheia

- **WHEN** `<Badge status="success">Concluído</Badge>` é renderizado no tema claro
- **THEN** a `color` computada é `--success-ink` `#065f46`
- **AND** o `background-color` computado é `--success` a 15%, compondo `#dbf4ec`
- **AND** o contraste medido do par é **6.65:1**

#### Scenario: badge não é focável por teclado

- **WHEN** a pessoa navega por Tab pela tela
- **THEN** nenhum `Badge` recebe foco
- **AND** nenhum `Badge` tem `tabindex`

### Requirement: StatusSelect é controle e exige chevron visível

O sistema SHALL renderizar `StatusSelect` como um `<select>` nativo com
`appearance: none`, e SHALL renderizar sempre um chevron visível, com
`pointer-events: none` e `padding-right` reservando o espaço. O chevron SHALL herdar a
tinta do status.

*Porquê (§5.2): sem o chevron, a pílula do select fica pixel-idêntica ao badge estático da
mesma tabela e ninguém descobre que é clicável. **Badge é rótulo, seletor é controle — os
dois nunca podem se parecer.***

#### Scenario: o chevron não é opcional

- **WHEN** o tipo de `StatusSelect` é inspecionado
- **THEN** não existe prop que suprima o chevron (`hideChevron`, `chevron={false}` ou equivalente)
- **AND** um teste de renderização falha se o `<svg>` do chevron não estiver no DOM

#### Scenario: select e badge do mesmo status são visualmente distinguíveis

- **WHEN** um `<Badge status="warning">Pendente</Badge>` e um `<StatusSelect value="warning">` são renderizados na mesma tabela
- **THEN** o `StatusSelect` tem um `<svg>` filho que o `Badge` não tem
- **AND** o `padding-right` computado do `StatusSelect` é maior que o do `Badge` por pelo menos a largura do chevron
- **AND** um teste de diferença estrutural falha se os dois nós renderizarem a mesma árvore de elementos

#### Scenario: o chevron herda a tinta do status

- **WHEN** `<StatusSelect value="danger">` é renderizado no tema escuro
- **THEN** o `stroke` computado do chevron é `--danger-ink` `#f87171`, o mesmo valor da `color` do select

#### Scenario: o chevron não bloqueia o clique

- **WHEN** a pessoa clica exatamente sobre o chevron
- **THEN** o `<select>` abre
- **AND** o `pointer-events` computado do chevron é `none`

#### Scenario: continua sendo um select nativo

- **WHEN** o `StatusSelect` recebe foco e a pessoa pressiona a seta para baixo
- **THEN** o valor avança para a próxima opção, sem nenhum código de teclado próprio
- **AND** o elemento é um `<select>`, não um `<button>` com listbox custom

### Requirement: Chips são pílulas tingidas estáticas

O sistema SHALL renderizar `Chip` (responsável, contribuinte, tag) como pílula tingida
estática com texto em `--*-ink`, e SHALL permitir uma variante removível cujo botão de
remoção tem `aria-label` e alvo de toque ≥ 32px.

#### Scenario: chip removível tem nome acessível

- **WHEN** `<Chip removable onRemove={fn}>Ana Souza</Chip>` é renderizado
- **THEN** o botão de remoção tem `aria-label` contendo `"Ana Souza"`
- **AND** sua caixa medida é de pelo menos 32×32px

#### Scenario: chip não removível não é focável

- **WHEN** `<Chip>Ana Souza</Chip>` é renderizado sem `removable`
- **THEN** nenhum elemento dentro dele recebe foco por Tab

### Requirement: Modal com foco preso e devolução de foco

O sistema SHALL renderizar `Modal` com overlay desfocado (`backdrop-filter`), barra de
título com botão fechar e rodapé de ações, no nível de empilhamento `--z-modal`. O modal
SHALL prender o foco, fechar em Esc **devolvendo o foco ao elemento que o abriu**, e
marcar o resto da árvore como `aria-hidden`.

#### Scenario: Esc devolve o foco ao gatilho

- **WHEN** a pessoa aciona o botão "Registrar avanço", o modal abre, e ela pressiona Esc
- **THEN** o modal fecha
- **AND** `document.activeElement` volta a ser o botão "Registrar avanço"

#### Scenario: Tab não escapa do modal

- **WHEN** o modal está aberto e a pessoa pressiona Tab repetidamente até o último elemento focável
- **THEN** o próximo Tab volta para o primeiro elemento focável do modal
- **AND** nenhum elemento fora do modal recebe foco

#### Scenario: empilhamento acima do dropdown

- **WHEN** o modal é renderizado
- **THEN** seu `z-index` computado é `90` (`--z-modal`)
- **AND** o valor não é literal no componente — vem do token

#### Scenario: overlay desfoca porque há conteúdo por baixo

- **WHEN** o overlay do modal é renderizado
- **THEN** ele tem `backdrop-filter` aplicado
- **AND** `Card` e `Panel` não têm `backdrop-filter` — o fundo ali é liso e o custo não se paga

### Requirement: Save indicator honesto

O sistema SHALL renderizar `SaveIndicator` em exatamente três estados — `saving`, `saved`,
`error` — cada um com ícone do sprite, classe de cor de status e texto, e SHALL anunciar a
mudança de estado por região viva.

#### Scenario: os três estados e suas cores

- **WHEN** `<SaveIndicator state="saving" />`, `"saved"` e `"error"` são renderizados
- **THEN** `saving` usa `--accent-ink`, `saved` usa `--success-ink` e `error` usa `--danger-ink`
- **AND** cada um tem um `<svg>` de sprite distinto
- **AND** nenhum deles usa emoji

#### Scenario: mudança de estado é anunciada

- **WHEN** o estado passa de `saving` para `error`
- **THEN** o texto muda dentro de um contêiner com `aria-live="polite"`
- **AND** o texto de `error` não afirma que houve gravação

### Requirement: Filter bar como controle segmentado

O sistema SHALL renderizar `FilterBar` como controle segmentado em pílula, com o segmento
ativo usando `--accent-solid` como fundo e texto branco, navegável por teclado.

#### Scenario: o segmento ativo usa a variante sólida

- **WHEN** o segmento "Pendentes" está ativo
- **THEN** seu `background-color` computado é `--accent-solid` `#1d4ed8` e sua `color` é `#ffffff`
- **AND** o contraste medido do par é **6.70:1**
- **AND** um teste falha se o fundo for `--accent` `#3b82f6`, que com branco dá 3.68:1 e reprova AA

#### Scenario: estado ativo é exposto à tecnologia assistiva

- **WHEN** o controle segmentado é renderizado
- **THEN** ele tem `role="tablist"` (ou `radiogroup`) e o segmento ativo carrega `aria-selected="true"` (ou `aria-checked="true"`)
- **AND** o estado ativo não é comunicado apenas por cor

#### Scenario: alvo de toque para uso com luva

- **WHEN** os segmentos são medidos
- **THEN** cada um tem altura ≥ 32px

### Requirement: Acessibilidade nasce na assinatura de tipo

O sistema SHALL tornar o nome acessível obrigatório por tipo onde ele é necessário, e
SHALL marcar ícones decorativos como `aria-hidden` por padrão.

#### Scenario: botão só-ícone sem rótulo é erro de tipo

- **WHEN** um desenvolvedor escreve `<Button><Icon name="trash" /></Button>` sem `aria-label`
- **THEN** `tsc --noEmit` falha, porque `Button` exige `aria-label` quando os filhos são apenas um `Icon`

#### Scenario: ícone decorativo é escondido por padrão

- **WHEN** `<Icon name="chevron-down" />` é renderizado sem prop `label`
- **THEN** o `<svg>` tem `aria-hidden="true"`
- **AND** passar `label="Abrir menu"` remove o `aria-hidden` e define o nome acessível

#### Scenario: foco visível em todo controle

- **WHEN** a pessoa navega por Tab por `Button`, `Input`, `StatusSelect`, `FilterBar` e o botão de fechar do `Modal`
- **THEN** cada um exibe anel de foco visível via `:focus-visible`
- **AND** o reset global `button { outline: none }` do template não está mais presente no CSS

### Requirement: Primitivos sem Radix e sem CVA

O sistema SHALL implementar todos os primitivos com composição manual e `cn()`, sem
introduzir Radix UI, CVA ou qualquer runtime de estilo.

#### Scenario: nenhuma dependência de primitivo adicionada

- **WHEN** `frontend/package.json` é inspecionado após a mudança
- **THEN** nenhum pacote com prefixo `@radix-ui/` está listado
- **AND** `class-variance-authority` não está listado
- **AND** os nove primitivos existem em `frontend/src/components/ui/`
