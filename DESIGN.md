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
  navegação.
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

## Layout & Spacing

- **App-shell** permanente: sidebar de 3 destinos (Visão Geral / Minhas Tarefas /
  Relatório) por **preenchimento tintado** (nunca faixa lateral), topbar com contexto
  de workspace + sino + menu da conta, rodapé com card de usuário + indicador de
  gravação. Gaveta abaixo de 768px. Navegar entre destinos NÃO remonta o shell.
- Grades de card responsivas sem breakpoint fixo; `items-stretch` para cards de
  mesma altura.
- **Escala z semântica** (`z-dropdown` / `z-sticky` / `z-sidebar` / `z-modal`…), com
  lint — nunca `9999`.

## Motion

- **Luz ambiente** (`.ambient` / `.glass-sheen`) throttled (32ms), 3 degradações.
- `prefers-reduced-motion: reduce` **zera** animações e transições — a luz ambiente
  fica PARADA na posição de repouso (não some: quem pediu menos movimento não perde
  o sistema visual).
- `successPulse` na transição <100→100 (suprimido por reduced-motion; NÃO move o foco
  — pode disparar por evento remoto de outra pessoa).
- Ease-out; sem bounce/elastic.

## Bans herdados (design-system + regras do impeccable)

Texto em gradiente, borda-faixa lateral (`border-left` colorido), glassmorphism
decorativo, grades de cards idênticos, hero-métrica gigante, eyebrow em maiúsculas
sobre cada seção. Recharts/GSAP/TipTap/Slate fora do chunk de entrada (guarda de
bundle).
