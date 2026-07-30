# Design

Sistema visual do RoboTrack, gerado a partir do código (capacidade `design-system`,
`frontend/src/styles/`). Escuro é o tema PRIMÁRIO; claro é a exceção. O tema NÃO
segue o SO. Todo par de contraste é medido no CI (`tests/contrast.test.ts`, entrada
em `src/styles/tokens.json`).

## Theme

- **Modo:** escuro por padrão (`:root`), claro em `.light` (D-DS-3). Guarda de CI
  proíbe `prefers-color-scheme` decidir o tema — a escolha é do produto, não do SO.
  Anti-FOUC no boot.
- **Mood:** ferramenta de chão de fábrica. Superfícies profundas (navy quase-preto),
  tinta clara de alto contraste, acento azul funcional. Nada de gradiente decorativo,
  nada de vidro por enfeite (bans do design-system).

## Colors

HSL via CSS vars (`hsl(var(--token))`), consumidas por classes utilitárias
(`bg-bg-main`, `text-text-main`, `border-input`). Namespaces restritos por
propriedade (`text-success` não compila — D-DS-2).

| Papel | Escuro (primário) | Claro |
|---|---|---|
| `bg-main` (fundo) | `#0a0f1d` navy quase-preto | `#f1f5f9` slate-50 |
| `bg-panel` (superfície) | `#121a2f` | `#ffffff` |
| `text-main` (tinta) | `#f8fafc` | `#0f172a` |
| `text-muted` | `#94a3b8` | `#475569` |
| **accent** (azul funcional) | pílula `#3b82f6` / tinta `#60a5fa` | sólido `#1d4ed8` |
| **danger** | `#ef4444` / sólido `#b91c1c` | idem |
| **success** | `#10b981` (tinta `#34d399`) | tinta `#065f46` |
| **warning** | `#f59e0b` (tinta `#fbbf24`) | tinta `#92400e` |
| **na** (neutro/status vazio) | `#71717a` (tinta `#d4d4d8`) | tinta `#3f3f46` |
| **ring** (foco) | `#60a5fa` | `#1d4ed8` |

**Regras de cor duras:**
- Corpo ≥ 4.5:1, não-texto ≥ 3:1, foco ≥ 3:1 — medido com **composição alfa** das
  camadas (pílula = status a 15% claro / 18% escuro sobre a superfície), não sobre
  cor sólida imaginária. É como a tinta de `N/A` a 2.25:1 tinha passado batido.
- Sem cinza-claro "por elegância": tinta muda tem piso de contraste como o corpo.
- Estratégia: **restrained** — neutros com leve tinte + UM acento (azul). O status
  (success/warning/danger/na) é semântico, não decorativo.

## Typography

- **Família única: Inter** (`Inter, system-ui, -apple-system, 'Segoe UI', sans-serif`).
  Sem pareamento de fontes.
- Escala fixa em **rem**; `letter-spacing: -0.02em` nos títulos.
- **`tabular-nums` em todo número** (progresso, %, contadores) — a largura não dança
  quando o valor muda (`.tabular`).
- `.title` / `.panel-header` / `.label-md` / `.label-sm` como degraus nomeados.

## Components (primitivos em `components/ui/`)

- **EntityCard** — card de projeto/célula/robô: badge é IRMÃO do título (não
  descendente, para alinhar os anéis), título `truncate`, anel/rodapé com `mt-auto`
  em `h-full`. **Card inteiro clicável** (`role=button` + `aria-label="Abrir X"`)
  quando recebe `onClick`; controles internos (editar/excluir) não disparam a
  navegação. **Swipe-to-reveal excluir** (owner-only-card-delete): com `onSwipeDelete`
  e ponteiro grosso (`(pointer: coarse)`), arrastar o card para a esquerda revela um
  painel "Excluir" (`bg-danger-solid`, alvo ≥40px). É ATALHO de toque — o painel é
  `aria-hidden`/não-focável (não duplica nome acessível; o caminho de teclado/leitor é
  o `IconButton` do rodapé — regra G). `touch-action: pan-y` (rolagem vertical não
  dispara); só arrasto horizontal além do limiar move o card; tocá-lo abre a
  confirmação (nunca exclui direto); o arrasto não navega. `prefers-reduced-motion`
  zera a transição do snap (instantâneo, sem bounce). Sem `z-index` literal — o painel
  fica atrás por ordem de pintura (posicionado + card opaco por cima).
- **Button** — variantes `default`/`outline`/`ghost`/`destructive` etc. (o `primary`
  gradiente existe mas é legado do template — evitar).
- **Badge** — pílula de status (success/warning/danger/na/accent), tingida sobre a
  superfície com o alpha do papel.
- **ProgressRing** — anel ponderado; OMITE o traço a 0% (não desenha um ponto);
  `role=img` + `aria-label` com a métrica nomeada (D15).
- **Hub / barra** — anima por `transform`, não `width`; `role=progressbar`.
- **Modal** — foco preso em ciclo, `Esc` devolve ao gatilho. **PortalMenu** /
  **PortalPopover** (menu/conteúdo rico em portal `#rt-overlays`, `position: fixed`,
  mede antes de pintar) — o único lugar com `createPortal` (regra B).
- **StatusSelect**, **Chip**, **IconButton** (a11y na assinatura de tipo — `label`
  obrigatório), **SaveIndicator**, **FilterBar**, **LiveRegions** (`#rt-status`
  polite / `#rt-alerts` assertive), **NotificationBell** (sino + badge de não-lidas).
  - **NotificationPreferenceControl** (notification-preferences) — sino de **seguir/
    silenciar** por entidade (projeto/célula/robô) no cabeçalho de cada tela. `IconButton`
    (sino `bell` cheio/accent quando **Seguindo**, `bell-off` quando **Silenciado**, contorno
    mudo no **Padrão**) → `PortalMenu` com três alvos explícitos (Padrão/Seguir/Silenciar,
    ≥40px) — **não** um toggle que cicla no toque (ambíguo sob luva). Exibe o **estado efetivo
    com origem** (`aria-label` "Silenciado pela célula" quando herdado de um ancestral — estado
    honesto, Princípio 2). Novo glifo `bell-off` no sprite (currentColor, sem emoji). Rótulos em
    `lib/i18n/notifications.ts` (sem literal solto).
  - **SaveIndicator** só desenha quando há algo a saber/agir: `error`, `pendente`,
    `bloqueado` (`saveStateNeedsAttention`). Os estados de repouso/feliz (`saved`,
    `saving`) **não renderizam nada** — um "Salvo" parado no canto é decoração, não
    informação (§Princípios 5). Esconder o SUCESSO não fere o estado honesto
    (Princípio 2): ausência nunca afirma "salvo"; a exigência é que FALHA/pendência
    apareçam, e essas seguem visíveis, com `aria-live="polite"`.

## Layout & Spacing

- **App-shell** permanente: sidebar de 3 destinos (Visão Geral / Minhas Tarefas /
  Relatório) por **preenchimento tintado** (nunca faixa lateral), topbar com contexto
  de workspace + **"?" de Ajuda** + sino + menu da conta, rodapé com card de usuário
  (o indicador de gravação só aparece acima dele quando há erro/pendência — no repouso
  o canto fica limpo). Gaveta abaixo de 768px. Navegar entre destinos NÃO remonta o shell.
- **Tela de Ajuda** (`ajuda-screen`, rota `/ajuda`, frontend-only): explicação geral
  de como o RoboTrack funciona, para operador + dono. Acesso pelo `IconButton` **"?"**
  da topbar (glifo `help` novo no sprite, currentColor/sem emoji) — **ponto único** de
  acesso, sempre visível, sem duplicar o nome acessível "Ajuda" (regra G). Layout:
  índice navegável (âncoras `#id`) fixo no desktop (`grid-cols-1 lg:grid-cols-[13rem_1fr]`,
  regra H) e como lista de atalhos no mobile; seções e TOC saem da MESMA lista de dados
  (não divergem). Prosa em medida contida (~68ch) e `text-text-main` (sem cinza-claro).
  As duas métricas nomeadas vêm de `lib/i18n/progress.ts`, a porta por código de
  `lib/i18n/invitations.ts` (chaves, não literais — respeita os sweeps D14).
- Grades de card responsivas; `items-stretch` para cards de mesma altura. Todo grid
  que salta de coluna em `sm:`/`lg:` **começa em `grid-cols-1`** no base — sem a
  coluna base `minmax(0,1fr)`, a trilha implícita `auto` estica no `min-content` do
  título `truncate` (que é `nowrap`) e o card estoura a viewport do celular (o antigo
  bug do zoom-out). Travado pela regra H do `convention-sweep`.
- **Escala z semântica** (`z-dropdown` / `z-sticky` / `z-sidebar` / `z-modal`…), com
  lint — nunca `9999`.

## Motion

- **Luz ambiente REMOVIDA.** O efeito de luz que seguia o cursor no desktop (a fonte
  única em `--lx`/`--ly` throttled + as camadas `.ambient` / `.glass-sheen` / `.glass`,
  a antiga D-DS-6) foi retirada por completo — sem listener de `pointermove`, sem
  brilho estático residual, custo de runtime zero. As superfícies, cards, contraste e
  temas seguem intactos (a luz nunca carregou informação; era decoração). Registro da
  decisão em `openspec/changes/design-system/EXECUCAO.md`.
- `prefers-reduced-motion: reduce` **zera** animações e transições.
- `successPulse` na transição <100→100 (suprimido por reduced-motion; NÃO move o foco
  — pode disparar por evento remoto de outra pessoa).
- Ease-out; sem bounce/elastic.

## Bans herdados (design-system + regras do impeccable)

Texto em gradiente, borda-faixa lateral (`border-left` colorido), glassmorphism
decorativo, grades de cards idênticos, hero-métrica gigante, eyebrow em maiúsculas
sobre cada seção. Recharts/GSAP/TipTap/Slate fora do chunk de entrada (guarda de
bundle).
