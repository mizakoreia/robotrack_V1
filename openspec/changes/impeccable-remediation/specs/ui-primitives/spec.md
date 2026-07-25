# Spec — `ui-primitives` (harden — G2)

Endurecimento dos primitivos que a crítica marcou como bloqueio de a11y. A garantia mora
no PRIMITIVO (para todo consumidor herdar), com teste de render que reprova a versão atual.

## ADDED Requirements

### Requirement: Todo diálogo passa pelo primitivo Modal

O sistema SHALL renderizar o registro de avanço (`AdvanceModal`) através do primitivo
`Modal` — portal em `#rt-overlays`, `position: fixed`, overlay, focus-trap e Esc que
devolve o foco ao gatilho — e SHALL NÃO renderizar diálogo como `<div role="dialog">`
inline no fluxo de uma célula de tabela.

*Porquê: `aria-modal` sem focus-trap deixa o leitor de tela "preso fora" do diálogo; a
superfície MAIS usada era a única fora do primitivo.*

#### Scenario: o AdvanceModal abre como Modal com portal e trap

- **WHEN** o operador termina o arraste do slider e o registro de avanço abre
- **THEN** o diálogo é renderizado via `createPortal` em `#rt-overlays`, não dentro do `<td>`
- **AND** o foco fica preso no diálogo enquanto aberto
- **AND** `Esc` fecha e devolve o foco ao controle de origem

### Requirement: Modal trava a rolagem do body, limita a altura e tem × de toque

O sistema SHALL, enquanto um `Modal` está aberto, travar a rolagem do `body`, limitar o
conteúdo a `max-h-[90vh]` com rolagem interna, e renderizar o botão de fechar com alvo de
toque ≥ 32px (`IconButton`).

*Porquê: hoje a página rola atrás no mobile, um modal alto estoura o viewport sem scroll
interno, e o × é um glifo cru sem área de toque.*

#### Scenario: body não rola e o × é tocável

- **WHEN** um `Modal` está aberto
- **THEN** a rolagem do `body` está travada
- **AND** o container do conteúdo tem `max-h` com `overflow-y: auto`
- **AND** o botão de fechar tem alvo de toque ≥ 32px

### Requirement: Button não exporta as variantes banidas de gradiente

O sistema SHALL NÃO exportar as variantes `primary` e `gradient` do `Button` (bans do
DESIGN: fundo/texto em gradiente). A variante `uiverse` (skin `.btn` de borda animada)
permanece exportada, mas SHALL ser usada apenas pela landing de marketing
(`components/campfire/*`) e páginas de template legado — nenhum callsite do PRODUTO a usa.

*Porquê: `primary`/`gradient` não tinham uso e são bans diretos; `uiverse` só existe para a
landing legada, cuja restilização está fora do escopo desta remediação (design-system
EXECUCAO decisão 4).*

#### Scenario: as variantes de gradiente somem do tipo

- **WHEN** o tipo `ButtonProps` é inspecionado
- **THEN** o union de `variant` não contém `primary` nem `gradient`
- **AND** passar uma delas é erro de `tsc --noEmit`

#### Scenario: o detector estático não acha gradient-text no produto

- **WHEN** `detect.mjs` roda sobre `frontend/src`
- **THEN** não há achado `gradient-text` (o único remanescente é `overused-font: Inter`, a família única deliberada do DESIGN)

### Requirement: PortalMenu é navegável por teclado

O sistema SHALL mover o foco para o `PortalMenu` ao abrir, de modo que setas / Home / End /
Enter operem os itens, espelhando o `PortalPopover`.

#### Scenario: setas operam o menu aberto

- **WHEN** o `PortalMenu` abre
- **THEN** o foco entra no menu
- **AND** a seta para baixo move para o próximo item

### Requirement: Tooltip é acessível por teclado e toque

O sistema SHALL revelar o conteúdo do `Tooltip` também por foco de teclado e por toque
(não só `:hover`), associar o conteúdo ao gatilho via `aria-describedby`, e permitir
dispensá-lo com `Esc`.

*Porquê: o operador de luva/tablet nunca dispara um tooltip só-hover. WCAG 1.4.13.*

#### Scenario: o tooltip abre por foco e fecha com Esc

- **WHEN** o gatilho do `Tooltip` recebe foco por teclado
- **THEN** o conteúdo fica visível e é referenciado por `aria-describedby`
- **AND** `Esc` o dispensa
