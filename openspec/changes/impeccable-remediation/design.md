# Design — `impeccable-remediation`

Registro das decisões de desenho. Cada decisão nomeia a alternativa descartada e o
porquê, e — quando toca invariante de a11y — onde a garantia mora (token, primitivo,
gate de CI).

## Princípio-guia

A crítica não pediu redesenho. Pediu **cumprir o que o produto já promete**. Toda
decisão aqui prefere: (1) usar o token/primitivo que já existe e já passa o gate;
(2) endurecer o primitivo, nunca a tela isolada, quando a falha é de sistema;
(3) travar a regressão com um gate de CI, não com vigilância humana.

## D-IR-1 — Contraste é dívida de USO; a garantia mora no `tokens.json` + `contrast.test.ts`

`--accent-solid` (#1d4ed8, 6,70:1 com branco) e `--danger-solid` (#b91c1c) e as tintas
`--*-ink` já existem em `tokens.json` e já passam `contrast.test.ts`. O botão primário
reprova AA só porque usa `bg-primary` (#3b82f6, 3,68:1) em vez da sólida. **Decisão:**
trocar o *uso* pela variante correta; não criar token novo. O `contrast.test.ts` continua
sendo a régua dos tokens; um **gate estático novo** trava o uso das cores cruas
(`bg-primary`/`bg-destructive`/`text-red-600`) nas telas do grupo.

**Descartado:** rebaixar o mínimo de contraste ou "clarear o azul só um pouco". Reprova o
Princípio 1 e some sob luz de galpão — é exatamente o modo de falha que os tokens sólidos
existem para evitar.

## D-IR-2 — Erro do login vai para `--danger-ink`, não `text-red-600`

`text-red-600` (#dc2626 = 3,94:1) é cor **crua do Tailwind**, fora do `tokens.json` —
então o gate do CI nunca a mede e ela reprova AA em silêncio. `--danger-ink` está no gate.
**Decisão:** todos os `text-red-600` do `AuthPage` viram `text-danger-ink`. O
`JoinByCodeDialog` já usa `text-danger-ink` — é o padrão que o `AuthPage` deveria copiar.

## D-IR-3 — Alvo de toque do slider: pseudo-elementos nativos, piso por `(pointer: coarse)`

O slider é `<input type="range">` nativo. O gate `regra F` do `convention-sweep` já isenta
`type="range"` (não é caixa de texto). O range nasce ~16px. **Decisão:** classe
`.progress-slider` em `globals.css` estilizando trilho + thumb nos dois motores
(`::-webkit-slider-thumb` / `::-moz-range-thumb`), com **área de toque ≥ 32px** (mouse) e
**≥ 40px em `(pointer: coarse)`** (luva/tablet). O thumb visível fica menor que a área de
toque de propósito (Fitts: o alvo é a área, não o desenho).

**Descartado:** trocar o range por um slider de biblioteca (custo de bundle, foge do "sem
lib" do design-system) ou por dois botões ±. O dono pediu explicitamente o slider sem
botões ±.

**Descartado:** hover dos botões sólidos com `/opacity` (`bg-accent-solid/90`). No
Tailwind 3.3 o modificador de opacidade não compõe sobre `hsl(var(--x))` sem canal alfa
declarado — o design-system define os sólidos sem `<alpha-value>`. **Decisão:**
`hover:brightness-110` (clareia o azul/vermelho escuro, afordância visível, sem depender
do canal alfa).

## D-IR-4 — `StatusSelect`: piso de toque 40px no mobile / 32px no desktop; borda visível

O `StatusSelect` aparece inline na tabela do robô (≥768px) e nos cartões no mobile.
**Decisão:** `min-h-[2.5rem]` na base (40px, mobile de luva) e `sm:min-h-[2rem]` (32px,
desktop denso). Borda `border-current/30` (< 3:1) → `border-current/70` (a tinta do status
já passa 4,5:1 como texto; a 70% a borda passa 3:1 não-texto).

## D-IR-5 — Badge do sino: `--danger-solid` + branco, e o número deixa de ser só visual

Hoje `bg-danger` (cheia, tingida) + `text-danger-ink` = vermelho-sobre-vermelho (~1,30:1),
e o número é `aria-hidden` — só o vidente o consome, e não consegue. **Decisão:**
`bg-danger-solid` + `text-white` (o par sólido do `tokens.json`, 5,9:1). O `aria-label` do
botão já carrega a contagem para o leitor de tela; o badge passa a ser legível para o
vidente também.

## D-IR-6 — Modais e navegação endurecem no PRIMITIVO, não na tela (G2)

`AdvanceModal` é a única superfície de diálogo fora do primitivo `Modal` — um
`<div role=dialog aria-modal>` inline no `<td>`, sem portal/overlay/fixed/trap. `aria-modal`
sem trap deixa o leitor "preso fora". **Decisão (G2):** portar para `Modal`; e endurecer o
próprio `Modal` (scroll-lock, `max-h`, × de toque) para que TODO consumidor herde. A gaveta
mobile espelha o comportamento do `Modal` (trap/Esc/`inert`). Registrado como requisito em
`ui-primitives` — a garantia mora no primitivo + teste de render, não na tela.

## D-IR-7 — Ordem dos grupos = ordem de dor do operador

O operador de luva no mobile é o usuário mais exposto e o que a crítica mais penaliza.
Por isso G1 (contraste + toque, os controles centrais dele) vem primeiro, G2 (modais/gaveta,
bloqueio de a11y de teclado/leitor) segundo, G3 (relatório, dor do gestor no celular)
terceiro. Consistência (G4), bans (G5) e polimento (G6) não bloqueiam tarefa — vêm depois.
Cada grupo fecha com prova verde e ff para `main`; o dono aprova entre grupos.

## Onde cada invariante de a11y mora

| Invariante | Mora em | Gate |
|---|---|---|
| Contraste dos tokens ≥ AA | `styles/tokens.json` | `contrast.test.ts` |
| Uso do token certo (não cor crua) | a tela | gate estático novo (G1) |
| Piso de toque do slider/select | `globals.css` + className | gate estático novo (G1) |
| Campo nativo com fundo temático | className | `convention-sweep` regra F |
| Foco visível AA | `@layer base :focus-visible` + `ring-ring` | render/axe |
| Modal (trap/Esc/portal) | `components/ui/Modal.tsx` | teste de render (G2) |

## Perguntas em aberto (para os grupos seguintes, não bloqueiam G1)

- G3: reflow do documento print-width vs. container `overflow-x:auto` com `min-width` — a
  decidir com o screenshot em 320px (o contrato de impressão A4 **não** pode regredir).
- G4: qual das duas telas "Equipe" renomear — "Responsáveis" (o `PeoplePanel`) parece o
  menos custoso, mas cruza link com a tela de membros.
- G5: `BuildPage`/`ProfilePage`/`UsersPage` são template legado — remover ou reduzir ao
  mínimo que compila? (mesma decisão registrada no `design-system` EXECUCAO decisão 3).
