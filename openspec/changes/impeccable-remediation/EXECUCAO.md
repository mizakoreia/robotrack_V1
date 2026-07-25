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
  - Commit `G1:` + ff `main` + push. **PARADO aqui — aguarda OK do dono para G2.**
