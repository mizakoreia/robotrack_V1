# Spec — `ambient-light`

## ADDED Requirements

### Requirement: Fonte única de luz em coordenadas de viewport

O sistema SHALL manter **uma** posição de luz, publicada nas custom properties `--lx` e
`--ly` no elemento raiz, registradas com `@property` como `<length>`, e SHALL fazer todas
as superfícies de vidro resolverem seu gradiente em espaço de viewport via
`background-attachment: fixed`.

*Porquê: é o `background-attachment: fixed` que faz a luz atravessar o app como um corpo
só. Sem ele, cada card ganha seu próprio brilho local, que é o efeito barato e errado.*

#### Scenario: duas superfícies distantes leem a mesma posição

- **WHEN** o ponteiro está em `(1200, 300)` e existem duas superfícies de vidro, uma no topo esquerdo e outra no rodapé direito da página
- **THEN** as duas resolvem o gradiente a partir de `(1200, 300)` em coordenadas de viewport
- **AND** o `background-attachment` computado das duas é `fixed`
- **AND** o brilho é mais intenso na superfície mais próxima do ponteiro, não centralizado em cada uma

#### Scenario: a posição vive num único lugar

- **WHEN** o DOM é inspecionado durante o movimento do ponteiro
- **THEN** `--lx` e `--ly` estão definidas apenas no elemento raiz
- **AND** nenhum card, painel ou menu define sua própria variável de posição de luz

#### Scenario: as três camadas consumidoras

- **WHEN** a luz está ativa
- **THEN** `.ambient` renderiza o halo fixo atrás de todo o conteúdo, no nível `--z-ambient` (0)
- **AND** `.glass-sheen::before` aparece apenas em sidebar, topbar, hub, painéis e menus
- **AND** `.glass::after` renderiza a borda de 1px que acende do lado voltado ao ponteiro, e aparece em todas as superfícies, cards inclusive

### Requirement: Orçamento de escrita da posição de luz

O sistema SHALL limitar a escrita de `--lx`/`--ly` a no máximo uma vez a cada ~32ms
(≈30fps).

*Porquê: escrever essas propriedades invalida todas as superfícies de vidro de uma vez. A
inércia visual da luz esconde a diferença para 60fps.*

#### Scenario: o throttle segura a taxa de escrita

- **WHEN** 60 eventos de `pointermove` são disparados em 1000ms
- **THEN** `--lx` é escrita no máximo 32 vezes
- **AND** nenhuma escrita ocorre a menos de 32ms da anterior

#### Scenario: custo medido com a tela cheia

- **WHEN** 24 cards estão em tela, com throttle de CPU 1x, e o ponteiro atravessa a viewport
- **THEN** o p50 de duração de frame é igual à linha de base medida com `data-glow="off"`
- **AND** o resultado da medição é registrado no repositório como número, não como afirmação

### Requirement: A luz é desativada no toque

O sistema SHALL condicionar todo o efeito de rastreamento a
`@media (hover: hover) and (pointer: fine)`, e SHALL não registrar o listener de ponteiro
quando a condição é falsa.

*Porquê: no toque não existe cursor e o custo não se paga.*

#### Scenario: em dispositivo de toque não há listener nem rastreamento

- **WHEN** o app é carregado num dispositivo com `(pointer: coarse)`
- **THEN** nenhum listener de `pointermove` que escreva `--lx`/`--ly` está registrado
- **AND** `.glass-sheen::before` e `.glass::after` não são pintados
- **AND** o halo de fundo `.ambient` continua presente, estático

#### Scenario: em desktop com mouse a luz rastreia

- **WHEN** o app é carregado num dispositivo com `(hover: hover) and (pointer: fine)`
- **THEN** mover o ponteiro de `(100, 100)` para `(900, 500)` altera os valores computados de `--lx` e `--ly`

### Requirement: Movimento reduzido congela a luz sem removê-la

O sistema SHALL, sob `prefers-reduced-motion: reduce`, manter a luz **presente e parada**
na posição de repouso, e SHALL zerar animações e transições globalmente.

*Porquê: `PRODUCT.md` diz que animação é reforço, nunca requisito para ver conteúdo.
Remover a luz inteira mudaria a leitura das superfícies, não só o movimento.*

#### Scenario: a luz existe mas não se move

- **WHEN** `prefers-reduced-motion: reduce` está ativo e o ponteiro se move de `(100, 100)` para `(900, 500)`
- **THEN** `--lx` e `--ly` permanecem nos valores de repouso, inalterados
- **AND** `.ambient`, `.glass-sheen::before` e `.glass::after` continuam pintados e visíveis
- **AND** um teste falha se as três camadas ficarem com `opacity: 0` ou `display: none`

#### Scenario: animações zeradas

- **WHEN** `prefers-reduced-motion: reduce` está ativo
- **THEN** a `animation-duration` e a `transition-duration` computadas de `viewEnter`, `menuIn`, `modalPop`, `successPulse` e do hover de card são `0s`
- **AND** o conteúdo permanece totalmente legível e alcançável

### Requirement: A luz é desligável por completo

O sistema SHALL desligar todas as camadas de luz, incluindo o halo de fundo, quando
`data-glow="off"` está no `<body>`, e SHALL persistir essa escolha.

#### Scenario: desligar remove tudo

- **WHEN** `data-glow="off"` é aplicado ao `<body>`
- **THEN** `.ambient`, `.glass-sheen::before` e `.glass::after` não são pintados
- **AND** nenhum listener de `pointermove` de luz permanece registrado
- **AND** o layout, o contraste do texto e a legibilidade de todas as superfícies permanecem inalterados

#### Scenario: contraste não depende da luz

- **WHEN** a mesma tela é medida com a luz ligada e com `data-glow="off"`
- **THEN** os contrastes de `--text-main` sobre `--bg-panel` e de todos os pares de tinta de status são os mesmos nas duas medições
- **AND** nenhum texto fica abaixo de 4.5:1 em nenhuma das duas condições

### Requirement: backdrop-filter só onde há conteúdo por baixo

O sistema SHALL aplicar `backdrop-filter` apenas em sidebar, topbar, menus e overlay de
modal, e SHALL NÃO aplicá-lo em card ou painel.

*Porquê: em card e painel ele custava caro e não borrava nada — o fundo ali é liso.*

#### Scenario: card e painel não desfocam

- **WHEN** o CSS computado de `.card` e do painel é inspecionado
- **THEN** `backdrop-filter` é `none` em ambos
- **AND** o mesmo teste confirma que sidebar, topbar, menu e overlay de modal têm `backdrop-filter` aplicado

### Requirement: Motion de entrada, menu, modal e conclusão

O sistema SHALL fornecer as animações `viewEnter` (fade + 8px), `menuIn`, `modalPop`,
`successPulse` (ao concluir tarefa) e hover de card elevando 3px, com curvas de saída
exponencial, duração entre 150ms e 320ms, e sem bounce.

#### Scenario: durações e curvas dentro do envelope

- **WHEN** as cinco animações são inspecionadas na config do Tailwind
- **THEN** cada `animation-duration` está entre `150ms` e `320ms`
- **AND** nenhuma `timing-function` produz overshoot (nenhum `cubic-bezier` com componente y fora de `[0, 1]`, nenhum `spring`)

#### Scenario: o pulso de conclusão é reforço, não informação

- **WHEN** uma tarefa chega a 100% e `successPulse` dispara
- **THEN** o novo estado já está legível no texto e na cor antes da animação começar
- **AND** com `prefers-reduced-motion: reduce` o pulso não roda e o estado continua completamente legível

#### Scenario: hover de card não desloca vizinhos

- **WHEN** o ponteiro entra num card da grade
- **THEN** o card sobe 3px por `transform: translateY(-3px)`
- **AND** a `offsetHeight` e o `offsetTop` dos cards vizinhos não mudam
