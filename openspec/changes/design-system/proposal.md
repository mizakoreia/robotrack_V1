# Proposta — `design-system`

## Why

A ESPECIFICACAO.md §5.1 e §5.2 e o `DESIGN.md` descrevem um sistema visual que já foi
construído, medido e corrigido no legado (PWA vanilla + CSS custom properties). Ele não
é gosto: cada regra de §5.2 existe porque a versão ingênua falhou em produção — o badge
junto ao título desalinhava os anéis da grade; o anel a 0% desenhava um ponto que
sugeria avanço inexistente; o `<select>` de status sem chevron era indistinguível do
badge estático e ninguém descobria que era clicável.

O alvo (`frontend/`) tem outra tecnologia — Tailwind 3 com `darkMode: ['class']`, tokens
HSL estilo shadcn em `styles/globals.css`, primitivos feitos à mão em `components/ui/`
sem Radix e sem CVA — e hoje tem **quatro** peças que impedem o porte:

1. **Dois arquivos de tokens** (`styles/globals.css` e `styles/tokens-campfire.css`) sem
   dono declarado. Duas fontes de verdade para cor é como se perde contraste medido.
2. **Primary violeta** do template, que não é a paleta do RoboTrack (neutros tintados de
   azul + accent azul).
3. **Duas bibliotecas de gráfico** (charts à mão *e* Recharts) e **dois editores de texto
   rico** (TipTap *e* Slate) carregando peso morto no bundle da aplicação visual.
4. **Nenhum dos primitivos que o produto precisa**: `components/ui/` tem só `Button`,
   `Card`, `Input`, `Tooltip`. Faltam anel de progresso, hub analítico, badge, status
   select, chip, modal, save indicator e filter bar.

Esta capacidade está na **Onda 0** e não tem dependências. Todo trabalho de tela
(`app-shell-navigation`, `hierarchy-screens`, `robot-task-table`, `my-tasks-view`,
`commissioning-report`, `workspace-settings`) consome os primitivos daqui. Começa
imediatamente, em paralelo com todo o backend.

O risco a evitar é a **armadilha nº 1 do porte**: a cor de status tem três variantes
(cheia / tinta `--*-ink` / sólida `--*-solid`) e trocar uma pela outra quebra contraste
AA de forma silenciosa — o texto continua legível na tela do desenvolvedor e reprova
para quem está no chão de fábrica sob luz de galpão. `#3b82f6` com branco em cima dá
**3.68:1** e `#ef4444` dá **3.76:1**; ambos reprovam em AA para corpo (≥ 4.5:1). É
exatamente por isso que `--accent-solid` e `--danger-solid` existem como tokens
separados.

## What Changes

### Tokens e temas

- Token set único em `frontend/src/styles/globals.css`, com os dois temas: escuro
  (padrão, em `:root`) e claro (em `.light`, aplicado via classe na raiz).
- **BREAKING** — `frontend/src/styles/tokens-campfire.css` é **removido**. Fonte única de
  verdade para cor.
- **BREAKING** — o primary violeta do template é substituído pelo accent azul do
  RoboTrack (`#3b82f6` escuro / `#2563eb` claro). Qualquer tela do template que
  dependesse do violeta muda de cor.
- Tema **deliberadamente NÃO segue `prefers-color-scheme`**. O escuro é o modo primário
  (§5.1). O claro só entra quando a pessoa pede. Persistência em `localStorage`
  (`rt-theme`), `<meta name="theme-color">` acompanha.
- Superfícies com alpha (`--bg-nav`, `--bg-panel`, `--bg-menu`, `--bg-sunken`,
  `--bg-raised`, `--border`, `--track`) são tokens HSL **sem** o canal alpha embutido,
  consumidos como `hsl(var(--x) / <alpha>)` — ver `design.md`.

### As três variantes de cor de status

- `--success` / `--warning` / `--danger` / `--accent` / `--na` — **cheia**: `background`,
  `border-color`, `stroke`, anéis de progresso.
- `--success-ink` / `--warning-ink` / `--danger-ink` / `--accent-ink` / `--na-ink` —
  **tinta**: a cor quando vira texto sobre a própria pílula tingida.
- `--accent-solid` / `--danger-solid` — **sólida**: a cor quando vira fundo de texto
  branco (`.btn-primary`, filtro ativo, botões de swipe).
- Um **teste automatizado de contraste** roda sobre a tabela de tokens, nos dois temas, e
  falha o CI abaixo de 4.5:1 para corpo e 3:1 para não-texto. Isso é o que impede a
  regressão silenciosa.

### Tipografia, ícones, empilhamento

- Inter 300–700, família única, escala fixa em rem. `font-variant-numeric: tabular-nums`
  em todo número (progresso, %, contadores).
- Sprite SVG inline, ícones herdando `currentColor` via `stroke`/`fill`. **Zero emoji na
  interface** — verificado por lint que falha o CI.
- Escala de z-index **semântica** exposta como token e como `theme.extend.zIndex` do
  Tailwind: `ambient 0 → content 1 → sticky 20 → sidebar 30 → dropdown 60 → modal 90 →
  login 200`. `z-index: 999` literal é proibido por lint.

### Primitivos em `components/ui/`

Card, ProgressRing, Hub, Badge, StatusSelect, Chip, Modal, SaveIndicator, FilterBar —
feitos à mão, variantes como objetos + `cn()`, **sem Radix e sem CVA** (segue o padrão já
estabelecido em `Button.tsx`/`Card.tsx`).

### Luz ambiente

Fonte única de luz em coordenadas de viewport (`--lx`/`--ly` via `@property`), três
camadas consumidoras, `background-attachment: fixed` como o mecanismo que faz todas as
superfícies lerem a mesma posição. Orçamento de escrita ~32ms (30fps), gated por
`@media (hover: hover) and (pointer: fine)`, congelada mas presente com
`prefers-reduced-motion`, desligável por completo (`data-glow="off"`).

### Dívida do template — o que fica

| Duplicação | Fica | Sai |
|---|---|---|
| Tokens de cor | `styles/globals.css` | `styles/tokens-campfire.css` |
| Gráficos | **charts à mão** (SVG do anel e da barra do hub já são feitos à mão e não pedem lib) | **Recharts** — desinstalado |
| Editor rico | **nenhum dos dois** — o RoboTrack não tem campo de texto rico; comentário de avanço é `<textarea>` de < 100 chars (§2.4) | **TipTap e Slate** — ambos desinstalados |

Racional em `design.md`. As remoções de dependência são executadas com tarefa de backup
(`git tag`) imediatamente antes.

### Não-objetivos

- **Composição de tela.** Sidebar, topbar, menus posicionados por JS, seletor de
  workspace e roteamento são de `app-shell-navigation`. Aqui entrega-se o *token de
  z-index* e o *primitivo de menu/modal*, não o shell.
- **Telas.** Visão Geral, Projeto, Célula, Robô, Minhas Tarefas, Relatório — cada uma tem
  sua capacidade. Aqui não se monta nenhuma rota.
- **Auditoria WCAG de tela montada.** `quality-and-accessibility` mede as telas com axe
  nos dois temas. Aqui mede-se a **tabela de tokens** e o **primitivo isolado**.
- **Layout do relatório A4 impresso.** É de `commissioning-report`; os quatro glifos
  tipográficos (`✓ ◐ ○ —`) são exceção declarada ali, não aqui.
- **Ícones específicos de domínio.** O sprite nasce com o conjunto que os primitivos
  precisam; cada capacidade de tela adiciona os seus.
- **Fonte auto-hospedada.** Inter via Google Fonts, como no legado. Auto-hospedar é
  requisito de `offline-pwa` (cache de asset) e de `delivery-and-observability`.

## Capabilities

### New Capabilities

- `visual-tokens`: tokens de cor dos dois temas, as três variantes de status com
  contraste medido, tipografia Inter + tabular-nums, raio/sombra/espaçamento, escala de
  z-index semântica, sprite de ícones sem emoji e a política de alternância de tema que
  não segue `prefers-color-scheme`.
- `ui-primitives`: os nove componentes base em `components/ui/` e as regras de
  comportamento de §5.2 que precisam sobreviver como requisito testável.
- `ambient-light`: a luz ambiente unificada — fonte única em coordenadas de viewport,
  orçamento de frame, gating por ponteiro, `prefers-reduced-motion`, desligamento
  completo — e as animações de entrada/hover/pulso.

### Modified Capabilities

Nenhuma. `openspec/specs/` está vazio.

## Impact

**Arquivos tocados** (frontend apenas — esta capacidade não escreve Ruby):

- `frontend/src/styles/globals.css` — reescrito (token set completo, dois temas).
- `frontend/src/styles/tokens-campfire.css` — **removido**.
- `frontend/tailwind.config.js` — `colors` remapeado para os papéis do RoboTrack,
  `zIndex`, `fontFamily`, `borderRadius`, `boxShadow`, `keyframes` de `viewEnter`/
  `menuIn`/`modalPop`/`successPulse`.
- `frontend/src/components/ui/` — 9 primitivos novos; `Button.tsx` e `Card.tsx`
  reescritos sobre os novos tokens.
- `frontend/src/components/icons/sprite.tsx` + `Icon.tsx` — novos.
- `frontend/src/lib/ambient.ts` — novo.
- `frontend/src/stores/themeStore.ts` — já existe; passa a gravar `rt-theme` e a
  sincronizar `<meta name="theme-color">`; **não** lê `prefers-color-scheme`.
- `frontend/package.json` — remove `recharts`, TipTap e Slate.
- `frontend/index.html` — `<link>` do Inter, `<meta name="theme-color">`, classe de tema
  aplicada antes da hidratação (script inline anti-FOUC).
- Testes novos: contraste de tokens, lint de emoji, lint de z-index literal, e um teste
  por regra de §5.2.

**Consumidores** (Onda 2+): `app-shell-navigation`, `hierarchy-screens`,
`robot-task-table`, `my-tasks-view`, `commissioning-report`, `workspace-settings`,
`in-app-notifications`, `offline-pwa` (SaveIndicator), `progress-advances` (Modal).

**Entrega** (cita `delivery-and-observability`): o `<link>` do Google Fonts precisa estar
na CSP de produção (`fonts.googleapis.com` em `style-src`, `fonts.gstatic.com` em
`font-src`); sem isso o Inter cai para a fallback stack e a métrica de contraste medida
continua válida mas a escala tipográfica quebra.

**Risco residual**: o `<textarea>` de comentário (§2.4) e o backup JSON (§3.11) são as
duas únicas superfícies de texto longo do produto — se alguma capacidade futura pedir
texto rico, a remoção de TipTap/Slate terá que ser revisitada. Está registrado como
pergunta em aberto no `design.md`.
