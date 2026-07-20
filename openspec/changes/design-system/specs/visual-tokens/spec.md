# Spec — `visual-tokens`

## ADDED Requirements

### Requirement: Fonte única de tokens

O sistema SHALL definir todos os tokens de cor, tipografia, raio, sombra, espaçamento e
empilhamento em exatamente um arquivo, `frontend/src/styles/globals.css`, com o tema
escuro em `:root` e o tema claro em `.light`. Nenhum outro arquivo SHALL redefinir um
token já declarado ali.

#### Scenario: o segundo arquivo de tokens é removido

- **WHEN** o build do frontend é executado após a mudança
- **THEN** `frontend/src/styles/tokens-campfire.css` não existe no repositório
- **AND** nenhum arquivo em `frontend/src/` o importa
- **AND** um `grep -rn "^\s*--\(bg-\|text-\|accent\|success\|warning\|danger\)" frontend/src --include=*.css` retorna ocorrências apenas em `globals.css`

#### Scenario: token redefinido fora do arquivo canônico falha o CI

- **WHEN** um desenvolvedor adiciona `--accent: 0 0% 50%;` em `frontend/src/features/foo/foo.css`
- **THEN** a tarefa de lint de tokens falha o CI nomeando o arquivo e o token duplicado

### Requirement: Papéis de cor dos dois temas

O sistema SHALL declarar os papéis de cor de `DESIGN.md` nos dois temas, como triplas HSL
sem canal alpha, consumidas como `hsl(var(--x))` ou `hsl(var(--x) / <alpha>)`.

Os papéis são: `--bg-main`, `--bg-nav`, `--bg-panel`, `--bg-menu`, `--bg-sunken`,
`--bg-raised`, `--border`, `--border-soft`, `--text-main`, `--text-muted`, `--accent`,
`--track`.

#### Scenario: valores canônicos do tema escuro

- **WHEN** o tema escuro está ativo
- **THEN** `hsl(var(--bg-main))` resolve para `#0a0f1d`
- **AND** `hsl(var(--text-main))` resolve para `#f8fafc`
- **AND** `hsl(var(--text-muted))` resolve para `#94a3b8`
- **AND** `hsl(var(--accent))` resolve para `#3b82f6`

#### Scenario: valores canônicos do tema claro

- **WHEN** o tema claro está ativo
- **THEN** `hsl(var(--bg-main))` resolve para `#f1f5f9`
- **AND** `hsl(var(--text-main))` resolve para `#0f172a`
- **AND** `hsl(var(--text-muted))` resolve para `#475569`
- **AND** `hsl(var(--accent))` resolve para `#2563eb`

#### Scenario: alpha não está embutido no token

- **WHEN** o valor bruto de `--bg-panel` é lido via `getComputedStyle`
- **THEN** ele é a string `222 45% 13%` — três componentes, sem `rgba(`, sem `/`, sem vírgula
- **AND** a translucidez de `0.7` do papel "superfície" aparece na classe `.surface-panel`, não no token

### Requirement: Contraste medido do texto de corpo

O sistema SHALL manter contraste ≥ 4.5:1 para texto de corpo e ≥ 3:1 para elementos
não-textuais (bordas, anel de progresso, ícones portadores de significado), nos dois
temas, verificado por teste automatizado sobre a tabela de pares declarada em
`frontend/src/styles/tokens.json`.

#### Scenario: pares de base medidos no escuro

- **WHEN** o teste de contraste computa `--text-main` `#f8fafc` sobre `--bg-main` `#0a0f1d`
- **THEN** o resultado é **18.26:1**
- **AND** `--text-muted` `#94a3b8` sobre `--bg-main` `#0a0f1d` é **7.45:1**
- **AND** ambos passam do mínimo 4.5:1

#### Scenario: pares de base medidos no claro

- **WHEN** o teste de contraste computa `--text-main` `#0f172a` sobre `--bg-main` `#f1f5f9`
- **THEN** o resultado é **16.30:1**
- **AND** `--text-muted` `#475569` sobre `--bg-main` `#f1f5f9` é **6.92:1**

#### Scenario: regressão de contraste falha o CI

- **WHEN** `--text-muted` do tema claro é alterado de `#475569` para `#94a3b8`, baixando o contraste sobre `#f1f5f9` de 6.92:1 para 2.28:1
- **THEN** o teste de contraste falha
- **AND** a mensagem de falha nomeia o par (`text-muted` / `bg-main`), o tema (`light`), o valor medido (`2.28`) e o mínimo exigido (`4.5`)

#### Scenario: par de cor não declarado é detectado

- **WHEN** uma classe utilitária de texto usa um token de cor que não tem linha correspondente em `tokens.json`
- **THEN** o teste de cobertura de tokens falha nomeando o token não declarado

### Requirement: Três variantes de cor de status

O sistema SHALL expor cada cor de status em três variantes de token com nomes distintos —
**cheia** (`--success`, `--warning`, `--danger`, `--accent`, `--na`), **tinta**
(`--*-ink`) e **sólida** (`--accent-solid`, `--danger-solid`) — e SHALL impedir por
configuração do Tailwind que uma variante seja usada no papel de outra.

#### Scenario: a variante errada não gera classe utilitária

- **WHEN** um desenvolvedor escreve `className="text-success"` (variante cheia usada como texto)
- **THEN** o Tailwind não gera a regra `.text-success` porque `success` está declarado apenas em `backgroundColor`, `borderColor`, `stroke` e `ringColor` na config
- **AND** o texto renderiza herdando a cor do contexto, tornando o erro visível na primeira execução
- **AND** o mesmo vale para `bg-success-ink`: `success-ink` está declarado apenas em `textColor`

#### Scenario: tintas do tema claro sobre pílula composta

- **WHEN** a pílula de status é `--success` a 15% sobre `#ffffff`, compondo `#dbf4ec`, e o texto é `--success-ink` `#065f46`
- **THEN** o contraste medido é **6.65:1**
- **AND** `warning` (`#fef0da` / `#92400e`) é **6.31:1**
- **AND** `danger` (`#fde3e3` / `#991b1b`) é **6.84:1**
- **AND** `accent` (`#e2ecfe` / `#1e40af`) é **7.34:1**
- **AND** `na` (`#f1f1f2` / `#3f3f46`) é **9.25:1**

#### Scenario: tintas do tema escuro clareiam em vez de escurecer

- **WHEN** a pílula é o status a 18% sobre `--bg-panel` `#121a2f` e o texto é `--*-ink`
- **THEN** `success` (`#12373e` / `#34d399`) mede **6.65:1**
- **AND** `warning` (`#3b3229` / `#fbbf24`) mede **7.51:1**
- **AND** `danger` (`#3a2233` / `#f87171`) mede **5.21:1**
- **AND** `accent` (`#192d53` / `#60a5fa`) mede **5.36:1**
- **AND** `na` (`#2c3245` / `#d4d4d8`) mede **8.61:1**

#### Scenario: a variante cheia reprova AA como fundo de texto branco — por isso a sólida existe

- **WHEN** `#ffffff` é medido sobre `--accent` `#3b82f6`
- **THEN** o contraste é **3.68:1**, abaixo do mínimo 4.5:1
- **AND** `#ffffff` sobre `--danger` `#ef4444` é **3.76:1**, também abaixo
- **AND** `#ffffff` sobre `--accent-solid` `#1d4ed8` é **6.70:1**, que passa
- **AND** `#ffffff` sobre `--danger-solid` `#b91c1c` é **6.47:1**, que passa

#### Scenario: botão primário usa a sólida, nunca a cheia

- **WHEN** `<Button variant="primary">` é renderizado com texto branco
- **THEN** o `background-color` computado é `--accent-solid`
- **AND** um teste falha se o computado for `--accent`

### Requirement: Cor de status é semântica, nunca decoração

O sistema SHALL reservar verde para concluído, âmbar para pendente/parcial, azul para em
andamento, vermelho para perigo e cinza para N/A. Nenhum componente SHALL usar cor de
status para diferenciar tipo de entidade, seção ou categoria.

#### Scenario: o selo de ícone do card usa um só tom

- **WHEN** cards de projeto, célula e robô são renderizados lado a lado
- **THEN** os três `.entity-ic` usam `--accent`, o mesmo tom
- **AND** nenhum deles usa `--success`, `--warning` ou `--danger`, porque essas cores significam *status*, não *tipo de entidade*

### Requirement: Tipografia Inter com números tabulares

O sistema SHALL usar Inter (300–700) como família única, com escala fixa em rem, e SHALL
aplicar `font-variant-numeric: tabular-nums` em todo número exibido (progresso,
percentual, contadores).

#### Scenario: escala fixa declarada

- **WHEN** os utilitários de tipografia são resolvidos
- **THEN** `.title` é `1.65rem` / peso 700 / `letter-spacing: -0.02em`
- **AND** `.modal-title` é `1.22rem` / peso 600
- **AND** `.panel-header` é `0.92rem` / peso 600
- **AND** corpo é `14px`
- **AND** rótulos e badges ficam entre `0.68rem` e `0.78rem`

#### Scenario: percentual não muda de largura ao variar

- **WHEN** um anel de progresso passa de `8%` para `88%` e depois para `100%`
- **THEN** a caixa de texto do percentual mantém a mesma largura medida em px nos três valores
- **AND** o `font-variant-numeric` computado do elemento contém `tabular-nums`

#### Scenario: fallback quando o Inter não carrega

- **WHEN** `fonts.googleapis.com` está inacessível
- **THEN** a `font-family` computada continua resolvendo para a stack `Inter, system-ui, -apple-system, "Segoe UI", sans-serif`
- **AND** o app permanece legível, sem texto invisível durante o carregamento (`font-display: swap`)

### Requirement: Ícones vetoriais sem emoji herdando currentColor

O sistema SHALL fornecer os ícones por sprite SVG inline (`<symbol id="i-*">`), consumido
por um componente `Icon`. Nenhum `<symbol>` SHALL fixar cor: traço e preenchimento vêm por
herança de `currentColor`. A interface SHALL NÃO conter emoji.

#### Scenario: o ícone herda a cor do contexto

- **WHEN** `<Icon name="check" />` é renderizado dentro de um elemento com `color: #34d399`
- **THEN** o `stroke` computado do `<svg>` é `#34d399`
- **AND** nenhum atributo `stroke` ou `fill` com valor literal aparece dentro do `<symbol id="i-check">`

#### Scenario: tamanhos canônicos

- **WHEN** `<Icon size="sm" />`, `<Icon />` e `<Icon size="lg" />` são renderizados
- **THEN** as caixas medem 15px, 18px e 22px respectivamente

#### Scenario: emoji no código-fonte falha o CI

- **WHEN** um desenvolvedor escreve `<span>✅ Concluído</span>` em `frontend/src/components/ui/Badge.tsx`
- **THEN** o lint de emoji falha nomeando o arquivo, a linha e o codepoint (`U+2705`)
- **AND** o mesmo lint não acusa os glifos `✓ ◐ ○ —` no módulo allow-listado do relatório A4

#### Scenario: o sprite funciona sem rede

- **WHEN** a aplicação é carregada e a rede é desligada em seguida
- **THEN** todos os ícones continuam renderizando, porque o sprite está inline no documento e não faz requisição

### Requirement: Escala de empilhamento semântica

O sistema SHALL declarar sete níveis nomeados de `z-index` e SHALL proibir valores
literais fora do arquivo de tokens.

#### Scenario: os sete níveis e seus valores

- **WHEN** os tokens de empilhamento são resolvidos
- **THEN** `--z-ambient` é `0`, `--z-content` é `1`, `--z-sticky` é `20`, `--z-sidebar` é `30`, `--z-dropdown` é `60`, `--z-modal` é `90`, `--z-login` é `200`
- **AND** os mesmos nomes estão disponíveis como `theme.extend.zIndex` do Tailwind (`z-modal`, `z-dropdown`, …)

#### Scenario: z-index literal é rejeitado

- **WHEN** um desenvolvedor escreve `z-index: 999` em um arquivo CSS de componente ou `className="z-[9999]"` em um `.tsx`
- **THEN** o lint de empilhamento falha nomeando o arquivo, a linha e o nível semântico mais próximo que deveria ter sido usado

#### Scenario: modal cobre dropdown, dropdown cobre sidebar

- **WHEN** um modal, um dropdown e a sidebar estão simultaneamente na tela
- **THEN** o modal (90) renderiza acima do dropdown (60), que renderiza acima da sidebar (30)

### Requirement: Tema não segue a preferência do sistema

O sistema SHALL iniciar no tema escuro quando não há escolha registrada, SHALL persistir a
escolha da pessoa em `localStorage` sob a chave `rt-theme`, e SHALL NÃO consultar
`prefers-color-scheme` em nenhuma circunstância.

#### Scenario: primeiro acesso com sistema em claro continua escuro

- **WHEN** uma pessoa abre o app pela primeira vez (sem `rt-theme` em `localStorage`) num dispositivo cujo sistema operacional está em modo claro
- **THEN** o app renderiza no tema **escuro**
- **AND** o elemento raiz **não** tem a classe `light`

#### Scenario: escolha explícita persiste entre sessões

- **WHEN** a pessoa alterna para o tema claro e recarrega a página
- **THEN** `localStorage['rt-theme']` é `"light"`
- **AND** o elemento raiz tem a classe `light` já na primeira pintura
- **AND** `<meta name="theme-color">` tem `content="#f1f5f9"`

#### Scenario: leitura de prefers-color-scheme falha o CI

- **WHEN** qualquer arquivo em `frontend/src/` contém `prefers-color-scheme`, seja em `matchMedia(...)` ou em uma `@media` de CSS
- **THEN** a tarefa de guarda de tema falha o CI nomeando o arquivo e a linha

#### Scenario: sem flash de tema errado

- **WHEN** a pessoa com `rt-theme = "light"` recarrega a página
- **THEN** a classe `light` está no elemento raiz antes da primeira pintura, aplicada pelo script síncrono do `<head>`
- **AND** nenhum frame renderiza com o fundo `#0a0f1d`

### Requirement: Raio, sombra e grade de cards

O sistema SHALL declarar a escala de raio (`--r-xs 6`, `--r-sm 8`, `--r-md 12`,
`--r-lg 16`, `--r-xl 20`, `--r-pill`), três degraus de sombra (`--sh-1/2/3`), espaçamento
em múltiplos de 4/8, e a grade de cards responsiva.

#### Scenario: grade de cards por breakpoint

- **WHEN** a grade de cards `repeat(auto-fill, minmax(260px, 1fr))` é renderizada
- **THEN** em viewport de 375px de largura ela mostra 1 coluna
- **AND** em 768px mostra 2 colunas
- **AND** em 1440px mostra entre 3 e 5 colunas

### Requirement: Dívida de duplicação do template resolvida

O sistema SHALL remover as dependências duplicadas do template e SHALL impedir que
retornem.

#### Scenario: dependências removidas

- **WHEN** `frontend/package.json` é inspecionado após a mudança
- **THEN** `recharts` não está listado
- **AND** nenhum pacote com prefixo `@tiptap/` está listado
- **AND** nenhum pacote com prefixo `slate` está listado
- **AND** `tsc --noEmit` passa, provando que nenhum código restante os importa

#### Scenario: reintrodução acidental falha o CI

- **WHEN** um desenvolvedor executa `npm i recharts` e comita o `package.json`
- **THEN** a guarda de dependência falha o CI nomeando `recharts` e citando D-DS-7 (as duas visualizações do produto são feitas à mão)
