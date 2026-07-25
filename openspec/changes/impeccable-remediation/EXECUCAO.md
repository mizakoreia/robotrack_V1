# EXECUCAO — impeccable-remediation

Mapa de execução. Escrito ANTES de qualquer código (commit **G0**). Reconcilia a crítica
(`CRITICA_IMPECCABLE.md`) × realidade do código. Decisões próprias e armadilhas
registradas à medida que aparecem. RETOMADA no fim.

## Ponto de partida

- Branch: `main` @ `c2532a8` (= `origin/main`). Marcador de segurança criado:
  **`git tag pre-impeccable-remediation`** em `c2532a8` (como voltar: `git reset --hard
  pre-impeccable-remediation` ou `git checkout c2532a8`).
- Método da casa: um grupo por vez, prova verde, ff para `main` a cada grupo,
  **aprovação do dono entre grupos**.
- **NÃO comitar** `frontend/vite.config.ts` nem `frontend/src/lib/api/client.ts` (config
  local de túnel/demo — seguem sem commit).
- **NÃO** reiniciar/derrubar os servidores de dev (:5173/:3000) nem túneis/caffeinate; o
  Vite recarrega sozinho (dono com a demo aberta).

## Decisão de estrutura: UMA change, muitos grupos (não N changes)

**Decisão:** materializar os 69 achados como **uma** change (`impeccable-remediation`) com
6 grupos, não como 5 changes por tema. **Porquê:**

1. Os achados são **dívida de cumprimento** sobre capacidades já existentes, não
   capacidades novas — todos consomem os MESMOS tokens/primitivos do `design-system`.
   Uma change com spec deltas por capacidade (`accessibility-compliance`, `ui-primitives`,
   `commissioning-report`, `workspace-invitations`) modela isso sem fragmentar.
2. O método da casa **já** trabalha grupo-a-grupo DENTRO de uma change (ff a cada grupo).
   Cinco changes duplicariam o mapa de grupos, o EXECUCAO e o ff, sem ganho.
3. O dono quer **aprovar entre grupos e revisar reversibilidade** — um `tasks.md` único
   com o mapa ordenado é o artefato certo para isso; cada grupo é um commit `G<n>:` + ff.

**Descartado:** uma change por comando impeccable (audit/harden/adapt/distill/clarify).
Ficaria bonito no papel, mas espalha a mesma dívida de token por 5 EXECUCAO e obriga o
dono a aprovar 5 planejamentos em vez de 1 plano com 6 grupos.

## Objetivo central

Levar a nota Nielsen de **27/40** para cima corrigindo, por USO, as regras duras que o
produto já declara e o design-system já tem gate para medir. Nenhuma regressão de contrato
(impressão A4, RLS, invariantes de banco). Cada grupo fecha com prova verde.

## Ordem dos grupos (por dor do operador)

| Grupo | Escopo | Impacto | Tarefas |
|---|---|---|---|
| **G1** | Contraste + alvo de toque: slider ≥40px, StatusSelect ≥40/32px, Button/login sólidos AA, erros→danger-ink, badge do sino, ring AA, gate novo | 🔴 operador de luva, tarefa nº1 | 1.1–1.9 |
| **G2** | Harden: AdvanceModal→Modal, Modal (scroll-lock/max-h/×), gaveta (trap/Esc/inert), classes mortas, color-scheme, PortalMenu, Tooltip, InviteDialog, sinal offline | 🔴 bloqueio de teclado/leitor | 2.1–2.10 |
| **G3** | Relatório responsivo no mobile + carimbo/nome de métrica | 🟠 gestor no celular | 3.1–3.3 |
| **G4** | Consistência Equipe/Convites: tokens, 1 padrão de confirmação, desambiguar "Equipe" | 🟠 Nielsen 4 (2/4) | 4.1–4.5 |
| **G5** | Distill dos bans vivos: variantes gradiente, gradient-text, borda-faixa, template legado | 🟠 anti-slop | 5.1–5.5 |
| **G6** | Polimento: nested card, badge quebrado, label-sm, loaders, item lido, header ≤320px | 🟡 | 6.1–6.5 |

## Decisões de desenho fixadas (do design.md — não reabrir)

- **D-IR-1** — contraste é dívida de USO; troca-se o uso pela variante sólida/ink que já
  passa `contrast.test.ts`; gate estático novo trava a cor crua. Não criar token novo.
- **D-IR-2** — erro do login → `--danger-ink` (no gate), nunca `text-red-600` (fora do gate).
- **D-IR-3** — alvo de toque do slider por pseudo-elemento nativo, piso por `(pointer:
  coarse)`; hover dos sólidos por `brightness` (o `/opacity` não compõe sobre HSL sem alfa
  no Tailwind 3.3).
- **D-IR-4** — StatusSelect 40 mobile / 32 desktop; borda `/70` (≥3:1).
- **D-IR-5** — badge do sino `--danger-solid` + branco.
- **D-IR-6** — modais/gaveta endurecem no PRIMITIVO, não na tela (G2).
- **D-IR-7** — ordem dos grupos = ordem de dor do operador.

## Decisões que EU tomo aqui (LER)

1. **Gate do G1 é estático e MORDE arquivos específicos**, não um sweep global. As telas de
   template (`DashboardPage`/`BuildPage`/`ProfilePage`/`UsersPage`/`SetupPage`) usam
   `text-muted-foreground`/`bg-primary` e **não estão no escopo do G1** (são do G5/legado).
   O gate afirma os fixes POSITIVOS em `Button`/`AuthPage`/`NotificationBell`/`StatusSelect`/
   `AdvanceControls`/`IconButton` + a regra CSS do slider — não varre o repositório inteiro,
   para não reprovar o que é escopo de outro grupo.
2. **`AdvanceModal` migra no G2, não no G1.** No G1 o slider já ganha alvo de toque; o
   modal inline vira dívida explícita do G2 (é harden, não contraste).
3. **Hover dos botões sólidos = `hover:brightness-110`.** Verificado: nenhum uso atual de
   `accent-solid`/`danger-solid` no repo usa `/opacity`; o Tailwind 3.3 não compõe alfa
   sobre `hsl(var(--x))` sem `<alpha-value>`. `brightness` clareia o tom escuro (afordância)
   sem depender do canal alfa.
4. **StatusSelect `bg-transparent` permanece** — passa a regra F (contém `bg-`) e a pílula é
   tingida por cima da superfície; o problema era só a borda e a altura.

## Reconciliação crítica × realidade (checada no código, G0)

- ✅ `--accent-solid` (#1d4ed8), `--danger-solid` (#b91c1c), `--danger-ink`, `--ring` existem
  em `tokens.json` e passam `contrast.test.ts` — o fix do G1 é só de uso. Confirmado.
- ✅ `Button.tsx` default = `bg-primary text-primary-foreground`; destructive =
  `bg-destructive ...`. Confirmado (`Button.tsx:15-16`).
- ✅ `AuthPage.tsx`: `text-red-600` em `:180,195,209,217,291`; `bg-primary` em `:219,296`.
  Confirmado.
- ✅ `NotificationBell.tsx:32`: badge `bg-danger ... text-danger-ink`. Confirmado.
- ✅ Slider `AdvanceControls.tsx` sem estilo de altura (range nativo). Confirmado — não há
  regra de range em `globals.css` (grep vazio).
- ✅ `StatusSelect.tsx:42`: `border-current/30 ... py-0.5`. Confirmado.
- ✅ `IconButton.tsx:26`: `focus-visible:ring-accent`. Confirmado.
- ✅ `regra F` do `convention-sweep` isenta `type="range"` (SKIP_TYPE) — o slider não cai na
  regra de fundo temático. Confirmado.

## RETOMADA

*(preenchido ao fim de cada grupo)*

- **G0 (planejamento):** proposal/design/4 spec deltas/tasks/EXECUCAO escritos; `validate
  --strict` verde; marcador `pre-impeccable-remediation` criado (@ `c2532a8`). Commit `G0:`
  `017e8b0`.
- **G1 (contraste + alvo de toque) — FECHADO:**
  - `.progress-slider` em `globals.css` (≥32px / ≥40px em `(pointer: coarse)`) + aplicado no
    `AdvanceControls`; `StatusSelect` `min-h-[2.5rem] sm:min-h-[2rem]` + borda `/70`.
  - `Button` default→`bg-accent-solid`, destructive→`bg-danger-solid` (hover `brightness-110`);
    `AuthPage` submits→`bg-accent-solid`, erros→`text-danger-ink` (0 `bg-primary`, 0 `text-red-600`);
    `NotificationBell` badge→`bg-danger-solid`+branco; `IconButton` foco→`ring-ring`.
  - Gate novo `tests/touch-and-contrast-usage.test.ts` (7 testes, MORDE).
  - **Prova:** `contrast.test.ts` 20 ✓, gate 7 ✓, `convention-sweep` 13 ✓, `tokens_coverage` 3 ✓,
    render (AdvanceControls/NotificationBell/primitives) 23 ✓, `no-heavy-deps` 1 ✓; `tsc --noEmit`
    exit 0; `eslint` dos 6 arquivos exit 0. Medição ao vivo (login): submit `rgb(29,79,215)`
    (#1d4ed8) sobre branco = **6,70:1** (antes #3b82f6 = 3,68:1). Screenshot em `/entrar`.
  - **Divergência:** nenhuma. Escopo exatamente o mínimo do dono + os fixes AA adjacentes
    (IconButton ring, StatusSelect borda). `AdvanceModal` inline segue como dívida do G2.
  - Commit `G1:` `34ed526` + push. Tag `pre-impeccable-remediation` também no remoto.
- **G2 (harden dos modais e navegação) — FECHADO:**
  - `Modal`: scroll-lock do body (guarda/restaura `overflow`), `max-h-[90vh]` + coluna
    flex com corpo em `overflow-y-auto`, × via `IconButton icon="close"` (32px).
  - `AdvanceModal`: portado para o primitivo `Modal` (portal/fixed/trap/Esc) — era o
    único diálogo fora do primitivo (inline no `<td>`); sinal honesto de offline
    (`wasQueued` → "Sem rede — avanço enfileirado", não fecha como salvo); cores cruas
    (`amber-700`/`muted-foreground`/`destructive`) → tokens (`warning-ink`/`text-muted`/
    `danger-ink`).
  - Gaveta mobile (`AppShell`/`Sidebar`): `role=dialog`+trap+Esc quando aberta abaixo de
    768px, `inert` quando fechada (sai da ordem de Tab); acima de 768px é permanente.
  - Classes mortas: `SettingsPage` `.page-title`→`.title`; `FactoryResetModal`
    `.input-base`→campo temático (`h-9 border bg-bg-main`); `StorageWarning`
    `text-text`→`text-text-main` + "Dispensar" ≥32px.
  - `color-scheme: dark`/`light` em `:root`/`.light` (glifos nativos herdam o tema).
  - `PortalMenu`: foca a si mesmo ao abrir (setas/Home/End/Enter estavam mortos) + itens
    ≥32px. `Tooltip`: foco+toque+`aria-describedby`+Esc (era só hover). `InviteDialog`:
    removido o `role="dialog"` falso (é form inline).
  - Testes novos: `src/components/ui/__tests__/harden-g2.test.tsx` (Modal scroll-lock/×,
    Tooltip foco/Esc, PortalMenu foco) 5 ✓; `TeamPanel.test` atualizado (form, não dialog).
  - **Prova:** suíte completa 585/595 na 1ª passada — as 10 "falhas" foram TODAS
    `Test timed out` sob carga paralela (máquina saturada: demo+túneis+dev servers); os 8
    arquivos rodados isolados (`--no-file-parallelism`) passam 100% (statusProgressColumns,
    robotTaskTable, settingsPage.e2e, integrationRender, navigation, e2eLoad, queue,
    auditLogModal). `tsc --noEmit` 0; `eslint` 0.
  - **Divergência:** `InviteDialog` — em vez de portar para `Modal` (overlap com G4),
    removi o `role="dialog"` falso (é painel inline; a spec permite "ou remover o role").
    O port completo de Team/Invite fica no G4.
  - Commit `G2:` `220355f` + push.
- **G3 (relatório legível no mobile) — FECHADO:** `.rpt-doc` com `min-width: 30rem` só em
  `@media screen` (abaixo disso o `.overflow-x-auto` do ReportPage rola em vez de espremer;
  impressão A4 intacta); carimbo deixa de ser hero-métrica (% `.title`→`.modal-title`, nome
  `label-sm text-text-muted`→`label-md text-text-main`, D15); ReportBody sem `/70`. Prova:
  report/reportPage/literalSweep 28 ✓; tsc 0. Commit `G3:`.
- **G4 (consistência Equipe/Convites) — FECHADO:** TeamPanel/InviteDialog portados para o DS
  (`text-muted-foreground`→`text-text-muted`, `text-destructive`→`text-danger-ink`,
  `text-xl`→`panel-header`); `window.confirm()`→`Modal` (remover/revogar); PeoplePanel vira
  "Responsáveis" com link cruzado + chip via primitivo `Chip` (32px); Overview com ação
  primária inline no título. Testes atualizados ao novo fluxo. Prova: team/settings/hierarchy
  /convention-sweep verdes; tsc 0; eslint 0. Commit `G4:`.
  - **Divergência:** o nome composto do `Chip` ("Ana · membro") mudou 2 asserts do peoplePanel
    (regex em vez de match exato) — atualizados.
- **G5 (distill dos bans) — FECHADO:** `Button` sem `primary`/`gradient` (dead bans);
  `uiverse` fica (landing legada — divergência no spec ui-primitives); globals.css sem
  `.card-highlight`/`icon-hue-cycle`/`.text-goat-gradient-*` (todos sem uso); BuildPage h1
  gradient-text→sólido; HistoryModal+AuditLogModal `border-l-2`→tinte de fundo. Prova:
  `detect.mjs` gradient-text **0** (só resta `overused-font: Inter`, decisão de DESIGN); tsc 0;
  eslint 0. Commit `G5:`.
- **G6 (polimento) — FECHADO:** Badge `whitespace-nowrap`; NotificationCenter lido sem
  `opacity-60` (contraste) + header `flex-wrap` (≤320px); PeoplePanel loader honesto
  (role=status); busca "Buscar" ≥32px; nested card em Utilitários VERIFICADO como irmãos (sem
  aninhamento). Prova: notifications/settings/hierarchy/primitives 34 ✓; tsc 0; eslint 0.
  Commit `G6:`.
- **Fechamento:** suíte completa (`--no-file-parallelism`) verde; `validate --strict` verde.
  Todos os 6 grupos no `main` e empurrados. Túnel (`vite.config.ts`, `lib/api/client.ts`)
  nunca commitado.
