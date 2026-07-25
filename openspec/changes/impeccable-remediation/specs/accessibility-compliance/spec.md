# Spec — `accessibility-compliance`

Cumprimento das regras duras de `PRODUCT.md` Princípio 1 (corpo ≥ 4,5:1, não-texto ≥ 3:1,
alvo de toque ≥ 32px de luva) por **uso**, não só por token isolado. Os tokens já passam
`contrast.test.ts`; aqui a garantia é que as telas os usam e que os controles centrais do
operador têm o piso de toque.

## ADDED Requirements

### Requirement: Controles centrais do operador têm alvo de toque de luva

O sistema SHALL renderizar o slider de progresso (`AdvanceControls`) e o `StatusSelect`
com área de toque **≥ 32px** e, em ponteiro grosso (`(pointer: coarse)` / mobile),
**≥ 40px** — o piso de luva de `PRODUCT.md` Princípio 1, que excede os 24px de WCAG 2.5.8.

*Porquê: registrar avanço e status é a tarefa nº1, feita de luva no celular. Um thumb de
16px (medido) é o gesto mais difícil da tela.*

#### Scenario: o slider carrega a classe de piso de toque

- **WHEN** `AdvanceControls` renderiza o `<input type="range">`
- **THEN** o input tem a classe `progress-slider`
- **AND** `styles/globals.css` define `.progress-slider` com altura base ≥ 32px
- **AND** define, sob `@media (pointer: coarse)`, altura ≥ 40px

#### Scenario: o StatusSelect tem piso de toque

- **WHEN** o `<select>` do `StatusSelect` renderiza
- **THEN** sua className contém um piso de altura (`min-h-[2.5rem]` no base, `sm:min-h-[2rem]` no desktop)
- **AND** não usa mais `py-0.5` como única definição de altura

### Requirement: Ação primária e destrutiva usam a variante de contraste AA

O sistema SHALL usar `--accent-solid` (branco sobre #1d4ed8 = 6,70:1) para a ação primária
e `--danger-solid` (branco sobre #b91c1c) para a ação destrutiva, e SHALL NÃO usar
`bg-primary` (#3b82f6 = 3,68:1 com branco) nem `bg-destructive` para texto branco nessas
superfícies.

*Porquê: corpo exige ≥ 4,5:1. O sistema já tem a variante sólida; a dívida é só de uso.*

#### Scenario: o Button default/destructive usa a sólida

- **WHEN** `Button` renderiza a variante `default`
- **THEN** o `background-color` vem de `--accent-solid`, com texto branco
- **WHEN** renderiza a variante `destructive`
- **THEN** o `background-color` vem de `--danger-solid`, com texto branco

#### Scenario: os submits do login usam a sólida

- **WHEN** o `AuthPage` renderiza os botões de submit (login, cadastro e entrada por código)
- **THEN** o `background-color` vem de `--accent-solid`
- **AND** nenhuma classe `bg-primary` permanece no `AuthPage`

### Requirement: Mensagens de erro usam token de contraste medido

O sistema SHALL exibir texto de erro com `--danger-ink` (que está no `tokens.json` e passa
o gate) e SHALL NÃO usar `text-red-600` (#dc2626 = 3,94:1, fora do gate).

*Porquê: `text-red-600` é cor crua do Tailwind — o gate do CI nunca a mede, e ela reprova
AA em silêncio.*

#### Scenario: erros do login usam a tinta de perigo

- **WHEN** o `AuthPage` exibe um erro de campo ou de formulário
- **THEN** o texto usa `text-danger-ink`
- **AND** nenhuma ocorrência de `text-red-600` permanece no `AuthPage`

### Requirement: Badge de não-lidas do sino é legível

O sistema SHALL renderizar o badge de contagem de não-lidas do sino com `--danger-solid` +
branco, e SHALL NÃO compor `bg-danger` (cheia tingida) com `--danger-ink` (vermelho sobre
vermelho ~1,30:1).

*Porquê: o número é `aria-hidden` — só o vidente o consome, e a ~1,30:1 não consegue.*

#### Scenario: o badge usa a sólida sobre branco

- **WHEN** há não-lidas e o `NotificationBell` renderiza o badge
- **THEN** o `background-color` vem de `--danger-solid`
- **AND** o texto do número é branco

### Requirement: Foco e borda de controle passam o mínimo de não-texto

O sistema SHALL usar `--ring` (não `--accent`) para o anel de foco do `IconButton`, e SHALL
dar ao `StatusSelect` uma borda com contraste ≥ 3:1.

*Porquê: `ring-accent` (#3b82f6 sobre a superfície) e `border-current/30` caem abaixo de
3:1; `--ring` está no bloco `focus` do `tokens.json` e passa.*

#### Scenario: o IconButton foca com o anel AA

- **WHEN** o `IconButton` recebe foco por teclado
- **THEN** o anel de foco usa `ring-ring` (`--ring`)
- **AND** nenhuma classe `ring-accent` permanece no `IconButton`
