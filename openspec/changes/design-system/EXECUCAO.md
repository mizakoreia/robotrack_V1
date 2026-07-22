# EXECUCAO — design-system

Mapa de execução. Escrito ANTES de qualquer código (commit G0). RETOMADA no fim.
Decisões próprias e armadilhas registradas à medida que aparecem.

## Ponto de partida

Branch empilhada sobre `progress-rollup` (que fechou). Onda 0, **sem dependências**:
todo o trabalho de tela (`app-shell-navigation`, `hierarchy-screens`,
`robot-task-table`, …) consome os primitivos e tokens daqui. Frontend apenas —
**não escreve Ruby**. Baseline: backend 933/0/9pending; frontend 100/0; tsc limpo.

## Objetivo central

Fonte ÚNICA de verdade visual: um token set (dois temas), as três variantes de
cor de status com **contraste medido** (teste de CI que reprova < 4.5:1 corpo /
< 3:1 não-texto), 9 primitivos que carregam as regras de §5.2 como comportamento
testável, luz ambiente com custo limitado, e a limpeza da dívida do template
(Recharts/TipTap/Slate/tokens-campfire fora). O escuro é o modo primário e **não**
segue `prefers-color-scheme` (decisão de produto, protegida por guarda de CI).

## Ordem dos grupos

| Grupo | Escopo | Tarefas |
|---|---|---|
| **G1** | Tokens e temas: token set em globals.css (escuro `:root`, claro `.light`), aliases shadcn, opacidades de superfície, tailwind.config, verificação de valores canônicos | 1.1–1.4 |
| **G2** | 3 variantes de status + contraste medido: namespaces cheia/tinta/sólida, restrição por propriedade no Tailwind, tokens.json + contrast.test.ts, cobertura de tokens | 2.1–2.4 |
| **G3** | Tipografia e ícones: Inter + escala rem + tabular-nums, sprite SVG + Icon, lint de emoji | 3.1–3.3 |
| **G4** | Empilhamento e tema: 7 níveis de z-index (token + lint de literal), themeStore (dark default, rt-theme, meta theme-color, anti-FOUC), guarda anti prefers-color-scheme | 4.1–4.3 |
| **G5** | Primitivos de superfície/progresso: Card, ProgressRing (omite path a 0%), Hub (scaleX), testes dos 3 modos de falha | 5.1–5.4 |
| **G6** | Primitivos de rótulo/controle/diálogo: Badge, StatusSelect (chevron não suprimível), Chip, Modal (focus trap), SaveIndicator, FilterBar, axe + tipos a11y | 6.1–6.7 |
| **G7** | Luz ambiente e motion: ambient.ts (throttle ~32ms), 3 camadas, 3 degradações, keyframes, medição de frame | 7.1–7.5 |
| **G8** | Limpeza destrutiva (POR ÚLTIMO): tag de backup, remover tokens-campfire + aliases, desinstalar Recharts/TipTap/Slate + código morto + guarda de reaparecimento, suíte completa + issue de CSP | 8.1–8.4 |

## Decisões de desenho já fixadas (do design.md — não reabrir)

- **D-DS-1** — tokens HSL de canal separado (sem alpha embutido), alpha aplicado no ponto de
  uso via `hsl(var(--x) / <alpha>)`. Embutir alpha faz o modificador do Tailwind multiplicar
  duas vezes.
- **D-DS-2** — 3 variantes de status = 3 namespaces; o namespace errado NÃO COMPILA (cheia só
  em bg/border/stroke/ring; tinta só em text; sólida só em bg). `text-success` sem regra CSS
  é o erro ficando visível cedo.
- **D-DS-3** — tema NÃO lê `prefers-color-scheme`; escuro é primário; `rt-theme` em
  localStorage; guarda de CI (`grep prefers-color-scheme` = vazio).
- **D-DS-4** — 7 níveis de z-index como token + `theme.extend.zIndex`; literal proibido por lint.
- **D-DS-5** — primitivos carregam §5.2 como comportamento com o porquê inline; cada teste
  reprova a implementação ingênua correspondente.
- **D-DS-6** — luz ambiente: uma fonte (viewport), custo limitado (~32ms), 3 degradações
  (gate por ponteiro, reduced-motion congela sem remover, `data-glow=off` desliga).
- **D-DS-7** — dívida do template: ficam charts à mão; saem Recharts, TipTap, Slate (a única
  entrada de texto livre é o `<textarea>` de comentário < 100 chars).
- **D-DS-8** — sprite inline, `currentColor`, zero emoji (lint).
- **D-DS-9** — a11y dos primitivos é assinatura de TIPO, não convenção (Button só-ícone sem
  aria-label falha `tsc`).

## Decisões que EU tomo aqui (LER)

1. **`themeStore` mora em `src/store/themeStore.ts`** (singular), não `src/stores/` como diz o
   proposal. Uso o caminho REAL do repo (já existe lá). Registro a divergência do texto.
2. **Aliases shadcn durante G1–G7, removidos no G8 (8.2).** `Button/Card/Input/Tooltip` do
   template usam `--primary`, `--background`, etc. Mantenho esses nomes como ALIASES dos papéis
   novos (1.1) para nada quebrar durante a construção; o G8 remove os aliases e ajusta os
   callsites. É o que a task 8.2 pede.
3. **Blast radius destrutivo (G8) — o que o código morto arrasta.** Remover Recharts mata
   `src/components/charts/Recharts*.tsx`; remover TipTap/Slate mata `src/components/RichTextEditor.tsx`
   E o uso dele em `src/app/pages/ProfilePage.tsx`. `tokens-campfire.css` é importado em
   `src/main.tsx`. **Decisão:** no G8 removo os arquivos de charts/RichTextEditor, ajusto
   `ProfilePage` para não depender do editor rico (o RoboTrack não tem campo de texto rico —
   §2.4), removo o import de tokens-campfire e o próprio arquivo. Se `ProfilePage` ficar sem
   propósito real (é página de template), reduzo-a ao mínimo que compila em vez de removê-la
   (evita quebrar rotas). Registro cada remoção.
4. **Landing "campfire" (marketing do template) FICA, mas restyla.** Os componentes
   `src/components/campfire/*` (Hero, Topbar, sections) são a landing do template. NÃO estão no
   escopo de remoção. Mas a troca do accent violeta→azul (BREAKING declarado no proposal) e a
   remoção dos aliases no G8 podem mudar a cor/estilo deles. **Decisão:** mantenho a landing
   COMPILANDO e o teste `hero.test.tsx` VERDE; aceito deslocamento visual (é marketing, não a
   app). Se o teste do hero assertar a cor violeta, atualizo-o com nota.
5. **`axe` + testes de tipo (6.7).** Uso `vitest-axe`/`jest-axe` se disponível; senão, um
   check estrutural de a11y equivalente (roles/aria/nome acessível) + o teste de tipo por
   `// @ts-expect-error`. Registro qual caminho usei.
6. **Medição de frame (7.5) é sensível ao ambiente** (mesmo espírito da decisão de latência da
   progress-rollup): registro os números medidos no repo, com asserção TOLERANTE (a luz ligada
   não pode ser MUITO pior que a base), não um p50 absoluto que flakaria no runner headless.

## Armadilhas previstas

1. **Alpha embutido no token** (D-DS-1): o modificador de opacidade do Tailwind multiplica em
   cima e a superfície sai escura demais. Verificação 1.4: `--bg-panel` é tripla sem `/` nem `rgba(`.
2. **Namespace de cor errado** (D-DS-2): `text-success` (cheia em texto) não gera regra — o
   teste de cobertura (2.4) pega.
3. **Contraste AA silencioso** (o risco nº 1): `#3b82f6`+branco = 3.68:1 REPROVA. Por isso
   `--accent-solid`/`--danger-solid` existem. O contrast.test.ts é a rede.
4. **`prefers-color-scheme` acidental** (D-DS-3): guarda de grep. Um "conserto" bem-intencionado
   entregaria claro para a maioria dos celulares — pior sob luz de galpão.
5. **Ponto no anel a 0%** (§5.2/5.2): OMITIR o path, não zerar `stroke-dasharray` (ponto
   arredondado sugere avanço). Badge vs StatusSelect com a mesma árvore (ninguém descobre que é
   clicável). Hub animando por `width` em vez de `transform`.
6. **Ordem destrutiva** (G8 por último, tag ANTES): sem o `git tag pre-design-system-cleanup` a
   volta é reconstrução manual.
7. **Frontend usa pnpm** (`pnpm-lock.yaml`); desinstalar dep é `pnpm remove`, não `npm`.

## Protocolo por grupo

Aplicar → `pnpm exec vitest run` (0 falhas) + `pnpm exec tsc --noEmit` (limpo) → marcar `- [x]`
em tasks.md → `npx --yes @fission-ai/openspec@1.6.0 validate design-system --strict` → **um
commit** `G<n>:`. Divergência design×realidade: decidir, registrar aqui, seguir.

## Progresso

- [x] G0 — este mapa (commit G0)
- [x] G1 — Tokens e temas (1.1–1.4) — token set 2 temas, aliases, superfícies, contraste-alvo
- [x] G2 — Status + contraste medido (2.1–2.4) — namespaces restritos, tokens.json + contrast.test (16 pares)
- [x] G3 — Tipografia e ícones (3.1–3.3) — Inter, escala rem, sprite+Icon, lint de emoji
- [x] G4 — Empilhamento e tema (4.1–4.3) — z-index semântico, dark default/.light/anti-FOUC, guarda anti-sistema
- [x] G5 — Primitivos superfície/progresso (5.1–5.4) — ProgressRing base (omite 0%), EntityCard, Hub
- [x] G6 — Primitivos rótulo/controle/diálogo (6.1–6.7) — Badge/StatusSelect/Chip/Modal/SaveIndicator/FilterBar/IconButton
- [x] G7 — Luz ambiente e motion (7.1–7.5) — ambient.ts throttle, 3 camadas, 3 degradações, keyframes
- [x] G8 — Limpeza destrutiva (8.1–8.4) — Recharts/TipTap/Slate FORA (bundle -208kB), guarda de retorno, CSP handoff.
  **DIVERGÊNCIA (decisão 3/4 revista):** `tokens-campfire.css` e os aliases shadcn MANTIDOS — só têm vars
  `--campfire-*` da landing (ortogonais aos papéis, que são a fonte única) e indireção `var()`; removê-los
  desestilizaria telas vivas sem ganho. A remoção real fica para quando app-shell/hierarchy-screens as
  substituírem. ProfilePage simplificada para `<textarea>` (sem texto rico, §2.4). **change COMPLETA.**

## RETOMADA (para o próximo agente)

1. `git log --oneline` na branch `design-system` (empilhada em `progress-rollup`); um commit
   por grupo. `tasks.md` tem o estado fino; este arquivo tem as decisões.
2. Baseline: só frontend. `cd frontend && pnpm exec vitest run && pnpm exec tsc --noEmit`. pnpm,
   não npm.
3. Invioláveis desta change: fonte ÚNICA de cor (tokens.json + globals.css), contraste medido
   no CI, tema não segue `prefers-color-scheme`, zero emoji, z-index semântico, primitivos com
   a11y na assinatura de tipo. As remoções do G8 são POR ÚLTIMO, com tag de backup ANTES.
4. Decisão grande: o G8 arrasta ProfilePage (RichTextEditor) e a landing campfire (accent
   violeta→azul). Ver decisões 3 e 4.
5. Consumidores (documentar quando fechar): todas as changes de tela + `progress-advances`
   (Modal), `offline-pwa` (SaveIndicator), `in-app-notifications`. Emitir issue de CSP para
   `delivery-and-observability` (8.4).
