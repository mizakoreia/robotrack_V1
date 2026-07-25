# Proposta — `impeccable-remediation`

## Why

A crítica `CRITICA_IMPECCABLE.md` (skill `impeccable`, comando `critique all pages`,
2026-07-25, tip `main` @ `705a0c2`) auditou o app autenticado tela a tela — quatro
leituras de código independentes + inspeção **ao vivo** em conta de QA descartável,
com medições reais de alvo de toque, contraste computado e screenshots em desktop e
mobile (375/320px), nos dois temas. Nota Nielsen: **27/40** ("Aceitável" — base sólida
e honesta, dívida concentrada em contraste, alvo de toque e no primitivo do avanço).

O achado central: **as dívidas não são de gosto — são regras duras que o próprio
produto já declara** (`PRODUCT.md` Princípio 1: corpo ≥ 4,5:1, não-texto ≥ 3:1, alvo
≥ 32px de luva) **e que o design-system já tem tokens/gates para cumprir** — a dívida é
de *uso*, não de sistema. O botão mais usado usa `bg-primary` (#3b82f6 = **3,68:1** com
branco) quando `--accent-solid` (#1d4ed8 = 6,7:1) existe e passa; os erros do login usam
`text-red-600` (**3,94:1**, e **fora** do `tokens.json`, então furam o gate do CI) quando
`--danger-ink` existe; o slider de progresso — controle nº1 do operador de luva — mede
**16px** de altura; o badge do sino é vermelho-sobre-vermelho (**~1,30:1**).

São **69 achados**: 14 críticos, 31 importantes, 24 de polimento. Esta change os
formaliza e os ataca **grupo a grupo**, cada grupo com prova verde (contraste, tsc,
lint, vitest) e ff para `main`, seguindo o método da casa.

**Natureza:** correção de qualidade de UI/UX/a11y sobre capacidades **já existentes**.
Não cria capacidade nova de produto — endurece o cumprimento das que existem
(`accessibility-compliance`, `ui-primitives`, `commissioning-report`,
`workspace-invitations`).

## What Changes

Organizado em **grupos ordenados por impacto ao operador real** (operador de luva no
mobile primeiro; gestor no desktop depois). O `tasks.md` traz o mapa completo; o
`EXECUCAO.md` traz a ordem e as decisões. Resumo:

### G1 — Contraste + alvo de toque (o que mais dói para o operador de luva)

- Slider de progresso (`AdvanceControls`) e `StatusSelect` com alvo de toque ≥ 32px
  (≥ 40px em ponteiro grosso / mobile) — hoje 16px e ~22px.
- Botão primário/destrutivo (`Button` default/destructive) e submits do login trocam
  `bg-primary`/`bg-destructive`/`bg-primary` por `--accent-solid`/`--danger-solid` (AA).
- Erros do login: `text-red-600` (fora do gate) → `--danger-ink` (no gate).
- Badge de não-lidas do sino: `bg-danger` + `--danger-ink` (vermelho-sobre-vermelho)
  → `--danger-solid` + branco.
- Foco/borda AA: `IconButton` `ring-accent` → `ring-ring`; `StatusSelect`
  `border-current/30` → visível (≥3:1).
- **Gate:** `contrast.test.ts` (já cobre os tokens AA) + novo gate estático que trava
  o *uso* (o slider e o `StatusSelect` carregam classe de piso de toque; as telas do
  grupo usam os tokens sólidos/ink, não as cores cruas).

### G2 — Harden dos modais e da navegação (bloqueios de a11y)

- `AdvanceModal` (hoje `<div role=dialog>` inline dentro do `<td>`) → primitivo `Modal`
  (portal + `position:fixed` + focus-trap + Esc devolve o foco).
- `Modal` primitivo: scroll-lock do body, `max-h-[90vh] overflow-y-auto`, × com alvo de
  toque (`IconButton`).
- Gaveta mobile do `AppShell`: focus-trap, Esc fecha, `inert`/`hidden` quando fechada
  (hoje só `-translate-x-full`, focável fora de tela).
- Classes CSS mortas: `.page-title` (Configurações sem estilo) → `.title`; `.input-base`
  (input do Factory Reset sem tema/borda/altura) → campo temático; `text-text`
  (`StorageWarning`) → `text-text-main`.
- `color-scheme` declarado (glifos nativos claros sobre o escuro).
- `PortalMenu` foca a si mesmo (setas/Home/End/Enter mortos hoje).
- `Tooltip` acessível (hoje só `:hover`; sem teclado, sem toque, sem `aria-describedby`).
- `InviteDialog` `role="dialog"` falso → `Modal` (ou remover o role).
- Sinal honesto de offline/enfileirado no `AdvanceModal` (hoje fecha como "salvo").

### G3 — Relatório responsivo no mobile (gestor no celular)

- O documento do Protocolo (`rpt-doc`, 433px cravados) é cortado em 375/320px sem
  scroll. Reflow / container com overflow para o gestor ler o carimbo e a distribuição.
- Carimbo hero-métrica: nome da métrica tão legível quanto o número (D15);
  `text-text-muted/70` (< 4,5:1) → sem `/70`.

### G4 — Consistência Equipe/Convites (Nielsen 4)

- Portar `TeamPanel`/`InviteDialog` para os tokens/tipografia do sistema
  (`text-muted-foreground`/`text-destructive`/`text-xl` → `text-text-muted`/
  `text-danger-ink`/`panel-header`).
- Unificar os **4 padrões de confirmação de exclusão** num só (`Modal`), removendo
  `window.confirm()`.
- Desambiguar as duas telas "Equipe" (responsáveis ≠ membros).
- Padronizar a posição da ação primária entre níveis.

### G5 — Distill dos bans vivos (anti-slop)

- Remover variantes `primary`/`gradient`/`uiverse` do `Button` (bans, com gradiente).
- Remover utilitários `text-goat-gradient*` e bordas rainbow do `globals.css`.
- `border-l-2` colorido do `HistoryModal` (ban literal de borda-faixa lateral).
- `BuildPage`/utilitários de template legado fora do bundle do produto.

### G6 — Polimento final

- Nested card em Utilitários; badge "Solda Ponto" quebrando em 2 linhas; `label-sm`
  pequeno para "legível de longe"; loaders "…" sem `aria-busy`; item de notificação
  lido baixando `opacity-60` no texto inteiro; header da central em ≤320px; etc.

### Não-objetivos

- **Redesenho.** Nada de nova identidade, nova navegação ou novas telas. É correção de
  cumprimento das regras que o produto já declara.
- **Backend / Ruby.** Esta change é frontend apenas. Autorização, RLS e invariantes de
  banco não mudam.
- **Reescrever o design-system.** Os tokens e primitivos existem e passam; corrige-se o
  *uso*. Onde um primitivo precisa endurecer (Modal, Button, Tooltip, PortalMenu), a
  mudança é registrada como requisito em `ui-primitives`.
- **Arquivos de túnel/dev.** `frontend/vite.config.ts` e `frontend/src/lib/api/client.ts`
  ficam fora de qualquer commit (config local de demo).

## Capabilities

### Modified Capabilities

- `accessibility-compliance` — o piso de alvo de toque do operador (slider,
  `StatusSelect`) e o cumprimento de contraste AA por *uso de token* (botão primário,
  login, badge do sino) passam a ser requisito testável, não só medição pontual.
- `ui-primitives` — `Modal` (scroll-lock, `max-h`, × de toque), `AdvanceModal` sobre o
  primitivo, `Button` sem as variantes banidas, `PortalMenu` com foco/teclado, `Tooltip`
  acessível.
- `commissioning-report` — o documento do Protocolo é legível em viewport estreita.
- `workspace-invitations` — Equipe/Convites usam o design-system único e um só padrão de
  confirmação.

### New Capabilities

Nenhuma.

## Impact

**Arquivos tocados** (por grupo; frontend apenas):

- **G1:** `components/ui/Button.tsx`, `components/ui/StatusSelect.tsx`,
  `components/ui/IconButton.tsx`, `features/advances/AdvanceControls.tsx`,
  `features/auth/AuthPage.tsx`, `features/notifications/NotificationBell.tsx`,
  `styles/globals.css` (classe do slider), novo gate em `tests/`.
- **G2–G6:** ver `tasks.md`.

**Gates existentes que valem de régua:** `tests/contrast.test.ts` (compõe pílula sobre
superfície e reprova < 4,5:1 corpo / < 3:1 não-texto), `tests/convention-sweep.test.ts`
(regra F — campo nativo com fundo temático; regra G/H), `tests/tokens_coverage.test.ts`,
`tests/no-emoji.test.ts`, `tsc --noEmit`, `eslint`.

**Risco residual:** o slider nativo estilizado depende de pseudo-elementos
`::-webkit-slider-thumb`/`::-moz-range-thumb` — testado nos dois motores na inspeção ao
vivo; o gate estático trava a *classe* e a regra `(pointer: coarse)`, a prova visual é o
screenshot do grupo. O hover dos botões sólidos usa `brightness` (não `/opacity`, que
não compõe sobre token HSL sem canal alfa no Tailwind 3.3).
