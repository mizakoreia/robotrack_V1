# Crítica Impeccable — RoboTrack (UI/UX/Acessibilidade, tela a tela)

> **Natureza:** auditoria/revisão. **Nenhum código de produção foi alterado nesta rodada.**
> Toda correção abaixo é *recomendação priorizada*; implementar só com o ok do dono.
>
> **Método (skill `impeccable`, comando `critique all pages`):** `PRODUCT.md` + `DESIGN.md`
> como verdade de base; quatro leituras de código independentes (auth/shell, hierarquia+avanço,
> tarefas/relatório/config, primitivos) + inspeção **ao vivo** no navegador contra os servidores
> de dev (`:5173`/`:3000`), numa **conta de QA isolada e descartável** (`qa-resp-375@…`, RLS) —
> o workspace do dono não foi tocado. Medições reais de alvo de toque, contraste computado, e
> screenshots em **desktop + mobile (375 e 320px)**, **tema escuro (primário) + claro**.
> Detector estático do impeccable rodado sobre `frontend/src`.
>
> **Data:** 2026-07-25 · **Tip inspecionada:** `main` @ responsividade mobile (705a0c2).

---

## Resumo executivo — os itens de maior impacto (priorizados)

Ordem por impacto para os usuários reais (operador de luva no mobile; gestor no desktop).

| # | Severidade | Achado | Onde | Por que dói |
|---|---|---|---|---|
| 1 | 🔴 CRÍTICO | **Os dois controles centrais do operador estão abaixo do piso de luva.** Slider de progresso = **16px** de altura (medido); `StatusSelect` = **~22–25px** (medido). | `AdvanceControls.tsx:60-83`, `StatusSelect.tsx:42` | Registrar avanço/status é a tarefa nº1, feita de luva no celular. Mira num thumb de 16px é o gesto mais difícil da tela. Viola PRODUCT Princípio 1 (≥32px). |
| 2 | 🔴 CRÍTICO | **Contraste AA falha no botão mais usado e no login.** `Button` default = branco sobre `#3b82f6` = **3,68:1**; destructive branco sobre `#ef4444` = **~3,3:1**; submit do login idem; erros do login em `text-red-600` = **3,94:1** (e furam o gate do CI, que só cobre `tokens.json`). | `Button.tsx:15-16`, `AuthPage.tsx:219,296,180-217` | Corpo exige ≥4,5:1 (DESIGN, regra dura). O sistema já tem `accent-solid`/`danger-solid`/`danger-ink` que passam — a dívida é só de uso. |
| 3 | 🔴 CRÍTICO | **Badge de não-lidas do sino é ilegível:** vermelho sobre vermelho (`bg-danger`+`text-danger-ink`) = **~1,30:1**. O número ("3", "9+") é `aria-hidden`, então só o vidente o consome — e não consegue. | `NotificationBell.tsx:32` | É exatamente o erro de status-sobre-status composto que o DESIGN alerta. Fix trivial: `bg-danger-solid` + branco. |
| 4 | 🔴 CRÍTICO | **O modal de registro de avanço não é um modal.** É um `<div role="dialog" aria-modal>` inline **dentro do `<td>` da coluna Progresso** — sem portal, sem overlay, sem `position:fixed`, sem focus-trap; espremido em ~150px. `aria-modal` sem trap deixa o leitor de tela "preso fora" do diálogo que acabou de abrir. Todos os outros modais usam o primitivo `Modal`. | `AdvanceModal.tsx:114-121,37-49` + `AdvanceControls.tsx:97-106` | A superfície MAIS usada é a única que foge do primitivo. Inconsistência + WCAG 2.4.3/4.1.2. |
| 5 | 🔴 CRÍTICO | **Gaveta de navegação mobile sem acessibilidade.** Sem focus-trap, **Esc não fecha** (confirmado ao vivo), e quando "fechada" ela só é empurrada com `-translate-x-full` — continua no DOM e na ordem de Tab (controles invisíveis focáveis). | `AppShell.tsx:98-105,159` | Usuário de teclado/leitor no celular não opera nem sai do menu, e cai em controles fantasma. |
| 6 | 🔴 CRÍTICO | **Classes CSS mortas quebram duas telas.** `.page-title` (indefinida) → **título de "Configurações" renderiza no tamanho cru do navegador**; `.input-base` (indefinida) → **input de confirmação do Factory Reset sem fundo temático, sem borda e sem alvo de toque** na ação mais destrutiva do produto (regra F + risco branco-no-branco). | `SettingsPage.tsx:29`, `FactoryResetModal.tsx:85-92` | Sem `color-scheme` declarado (0 ocorrências no `src/`), campos/checkboxes nativos ainda herdam a UI clara do SO sobre o escuro. |
| 7 | 🔴 CRÍTICO | **Tooltip inacessível:** só `:hover`, sem teclado e **sem toque** — operador de luva/tablet (usuário primário) nunca o dispara; sem `aria-describedby`, sem Esc. | `Tooltip.tsx:22` | Se algo essencial depende de tooltip no chão de fábrica, some. WCAG 1.4.13. |
| 8 | 🟠 IMPORTANTE | **Relatório não é responsivo no mobile.** O documento é uma `<table class="rpt-doc">` de **433px cravados**; em 375/320px ele é **cortado à direita sem scroll horizontal** — o gestor no celular não lê o carimbo "PENDENTE" nem "Pendente 5" (aparece só "○ Per"). | `ReportDocument`/`report-print.css` | O Protocolo é o artefato que se assina; ilegível no celular. |
| 9 | 🟠 IMPORTANTE | **Team/Convites é um design-system paralelo.** Usa tokens legados não testados (`text-destructive` `#ef4444` como texto de erro — caminho de contraste fora do gate), tipografia de template (`text-xl font-semibold`), **`window.confirm()`** para remover membro/revogar (4º padrão de confirmação de exclusão diferente no app), e `role="dialog"` sem trap/Esc/portal. Duas telas distintas ambas tituladas **"Equipe"** (responsáveis ≠ membros). | `TeamPanel.tsx`, `InviteDialog.tsx` | Parece "outro app"; anti-referência "SaaS genérico"; inconsistência Nielsen. |
| 10 | 🟠 IMPORTANTE | **Carimbo do Relatório = hero-métrica banida.** `%` gigante em `.title` sobre o **nome que o desambigua** em 0,68rem `text-text-muted`; barras usam `text-text-muted/70` (abaixo de 4,5:1). No único documento que se assina, o nome da métrica precisa ser tão legível quanto o número (D15). | `ReportHeader.tsx:17-20`, `ReportBody.tsx:31` | Bans DESIGN ("hero-métrica gigante") + regra "sem cinza-claro por elegância". |

**Também de alto valor (importantes):** `PortalMenu` **nunca recebe foco** → a navegação por seta documentada está morta e os itens têm ~25px (`menu/PortalMenu.tsx:39-57,167`); estado **offline** estilizado como cinza-muted (baixa ênfase para quem "às vezes sem rede", `ConnectionIndicator.tsx:25`); **variantes gradiente** ainda exportadas no `Button` e **utilitários `text-goat-gradient`** no `globals.css` (bans DESIGN vivos); vários alvos <32px recorrentes (remover-pessoa **~18px**, catálogo, `BackLink`, "Dispensar", switcher de workspace).

### Contagem por severidade

| Severidade | Qtde |
|---|---:|
| 🔴 CRÍTICO | **14** |
| 🟠 IMPORTANTE | **31** |
| 🟡 POLIMENTO | **24** |
| **Total** | **69** |

### Telas mais problemáticas (onde concentrar)

1. **Registro de avanço** (AdvanceModal + slider + StatusSelect) — a superfície mais usada é a que mais falha (2 críticos + importantes).
2. **Login / Auth** — contraste furando o gate do CI; checkbox e links sub-32px.
3. **Configurações → Catálogo + Factory Reset + título** — classes mortas, alvos, `color-scheme`.
4. **Equipe / Convites** — design-system paralelo, `window.confirm`, `role=dialog` falso.
5. **Sino de notificações** — badge ilegível.
6. **Relatório no mobile** — tabela print cortada.

### Destaques positivos (o que está genuinamente bom)

- **Regra D15 (duas métricas nomeadas) cumprida com rigor** em toda a hierarquia: contagem crua + "Anéis: progresso ponderado" + "% físico global"; `ProgressRing` exige `metric` no tipo (progresso solto **nem compila**).
- **Estado honesto de verdade:** skeletons (não spinners), estados vazios que ensinam, fluxo de conflito 409 exemplar no avanço (preserva comentário, oferece recalcular, nunca reenvia sozinho), `view` só-leitura fora do DOM, owner-only delete com caminho acessível além do swipe.
- **Reflow responsivo real** na hierarquia e na tabela do robô: um layout por vez via `useMediaQuery` (tabela ≥768px / cartões abaixo) — **sem overflow horizontal em 375 nem 320px** (medido).
- **Primitivo `Modal` correto:** focus-trap, **Esc fecha e devolve o foco ao gatilho** (confirmado ao vivo) — o problema é só a gaveta e o AdvanceModal, que não o usam.
- **Contrato de impressão do Relatório** é o melhor trabalho do escopo: `@page` A4, `thead/tfoot` correntes, blocos indivisíveis, tema neutralizado para preto-no-branco, barras com borda+preenchimento que sobrevivem ao monocromático.

---

## Placar de heurísticas (Nielsen, 0–4) — app autenticado como um todo

| # | Heurística | Nota | Achado-chave |
|---|-----------|:---:|-------------|
| 1 | Visibilidade do status | 3 | `SaveIndicator`/live regions honestos; mas offline sub-enfatizado e AdvanceModal fecha como "salvo" mesmo enfileirado. |
| 2 | Sistema ↔ mundo real | 3 | Voz pt-BR direta, métricas nomeadas; "Progresso" solto em Minhas Tarefas e duas telas "Equipe" confundem. |
| 3 | Controle e liberdade | 3 | Voltar/Cancelar/Esc no primitivo Modal; **gaveta mobile sem Esc**, AdvanceModal sem × / fora-para-fechar. |
| 4 | Consistência e padrões | 2 | **4 padrões diferentes de confirmar exclusão**; Team/Invite = DS paralelo; posição da ação primária varia por nível. |
| 5 | Prevenção de erro | 3 | Factory-reset com backup obrigatório + digitar o nome; D14 no comentário do avanço. Bom. |
| 6 | Reconhecer > lembrar | 3 | Ícones rotulados, `aria-label` de ação; controle inline do Catálogo indistinguível de texto estático. |
| 7 | Flexibilidade/eficiência | 2 | Sem atalhos de teclado; `PortalMenu` com navegação por seta **morta**; sem ações em lote no operador. |
| 8 | Estético e minimalista | 3 | "Sem enfeite" bem seguido; manchado por variantes gradiente/`uiverse` e utilitários gradient-text ainda no código. |
| 9 | Recuperação de erro | 3 | Erros de login mapeados ao campo, 409 exemplar; alguns textos usam cor crua fora de token. |
| 10 | Ajuda e documentação | 2 | Tooltips inacessíveis (hover-only, sem toque); sem ajuda contextual no chão de fábrica. |
| | **Total** | **27/40** | Faixa **"Aceitável"** — base sólida e honesta, com dívidas concentradas em contraste, alvo de toque e no primitivo do avanço. |

---

## Anti-slop / bans do DESIGN (detector + revisão)

- **Detector estático** (`detect.mjs` sobre `frontend/src`): **1 achado** — `gradient-text` em `BuildPage.tsx:50`. `BuildPage` é rota de template legado (`/build`), fora do produto real; ainda assim é um ban vivo no repositório.
- **Achados que o detector não pega, mas violam bans DESIGN:** variantes `primary`/`gradient`/`uiverse` ainda exportadas no `Button.tsx:21-23`; utilitários `.text-goat-gradient-dark/light` e bordas rainbow animadas (`.card-highlight`, `icon-hue-cycle`, `.btn`) em `globals.css:319-471`; `border-l-2` colorido na timeline do `HistoryModal.tsx:31` (ban literal "borda-faixa lateral"); carimbo hero-métrica no Relatório.
- **Veredito de "cara de IA":** o núcleo do produto **não** tem cara de template — a linguagem é sóbria e funcional, fiel ao "sem enfeite". As exceções são localizadas: `BuildPage`/utilitários de template ainda no bundle e a superfície Team/Invite com tipografia de SaaS genérico.

---

# Crítica por tela

Legenda de severidade: 🔴 CRÍTICO (bloqueia/quebra a11y) · 🟠 IMPORTANTE (fricção/confusão real) · 🟡 POLIMENTO.

## 1. Entrar (login / criar conta) — `features/auth/AuthPage.tsx`

**Bom:** erros mapeados ao campo (401 limpa só a senha e mantém e-mail `:102-106`; 409 mira o e-mail `:108-111`); validação de cliente evita o round-trip (`:127-130`); slots de erro reservam altura (`min-h-[1.25rem]`) sem "pular" o layout.

- 🔴 **Submit branco sobre `#3b82f6` = 3,68:1** — `:219, :296` (`bg-primary text-white`). Corpo ≥4,5:1. Fix: `bg-accent-solid` (`#1d4ed8`, 6,7:1) ou o `Button` aprovado.
- 🔴 **Erros em `text-red-600` (`#dc2626`) = 3,94:1** e **fora do sistema de tokens** — `:180,195,209,217,291`. Furam o gate do CI (só cobre `tokens.json`). Fix: `text-danger-ink`.
- 🔴 **Checkbox "Manter conectado" nativo, sem tamanho (~14px) e sem fundo temático** — `:213`. Sub-32px (luva) + regra F. Fix: dimensionar ≥32px + aparência temática.
- 🟠 **`aria-invalid` sem `aria-describedby`** — `:176-209`: o leitor ouve "inválido" mas não o porquê. Fix: `id` no `<p>` de erro + `aria-describedby`.
- 🟠 **Sem revelar-senha e sem "esqueci a senha"** — `:200-207`: operador de luva no galpão não confere o que digitou.
- 🟠 **Um `codeError` marca dois campos** — `:263,283`: erro de formato do código também marca o e-mail como inválido.
- 🟡 Botões de troca de modo são texto sublinhado sem padding (sub-32px) `:233,237`; sem identidade "RoboTrack" na única tela pré-auth `:162`; sem alternância de tema acessível antes do login.

## 2. Entrar por código / entrar em outro workspace — `features/auth/JoinByCodeDialog.tsx`

**Bom:** usa `text-danger-ink` (o certo que o AuthPage deveria copiar); tira de contexto só-leitura com o e-mail da sessão (`:67-71`); em erro mantém o código digitado (`:55-57`).

- 🟠 **Foco vai para o "×" e não para o campo de código** — o efeito do `Modal` foca o primeiro focável (o botão fechar do header) e vence o `autoFocus` do input (`Modal.tsx:29` vs `:84`). Fix: `Modal` preferir `[data-autofocus]` ou renderizar o × por último.
- 🟡 Botões `size="sm"` (36px) — no piso, ok para ação de gestor no desktop.

## 3. Aceitar convite (fluxo por código) — `features/team/InviteDialog.tsx` + `OAuthCallbackPage.tsx`

**Bom:** `InviteDialog` usa `type=text`+`inputMode=email` de propósito para manter validação em `aria-live` (`:112-124`); falha de copiar-código degrada para campo selecionável (`:56-69`). `OAuthCallbackPage` limpa o fragmento de token da URL/histórico antes de navegar (`:29-33`).

- 🟠 **`role="dialog"` sem semântica de diálogo** — `InviteDialog.tsx:73,106`: é `<form>`/`<div>` no fluxo da página, sem trap/Esc/retorno de foco/portal. Fix: usar o `Modal`, ou remover o `role`.
- 🟡 Estado de espera do OAuth é uma linha `text-muted-foreground` sem spinner nem timeout (`OAuthCallbackPage.tsx:79-83`): se `me()` travar, o usuário fica preso sem saída.

## 4. Casca do app (sidebar / topbar / gaveta) — `app/AppShell.tsx`, `nav.ts`

**Bom:** destino ativo por **preenchimento tintado** + ícone accent, nunca faixa lateral (`:172-179`); `aria-label="Conta: …"` no botão de conta (`:194`); `aria-current="page"` nos links; scroll só no conteúdo com voltar-ao-topo na navegação; "Convidar pessoa" some na tela de Equipe para não duplicar nome (regra G, `:284`).

- 🔴 **Gaveta mobile sem focus-trap e sem Esc** — `:98-105` (**confirmado ao vivo:** Esc não fecha). Fix: mover foco para dentro, prender Tab, tratar Esc (espelhar `Modal`).
- 🔴 **Gaveta "fechada" continua focável** — só `-translate-x-full` (`:159`); links/conta ficam fora de tela mas na ordem de Tab. Fix: `hidden`/`inert` abaixo de `md`.
- 🟠 **Switcher de workspace `py-1` (~22px)** — `WorkspaceContext.tsx:60`: sub-32px, visível ao operador. Fix: `min-h-[32px]`.
- 🟠 **"Recarregar" (recuperação de índice) é link sem padding** — `WorkspaceContext.tsx:48`: única saída do estado degradado, com alvo minúsculo.
- 🟡 `--topbar-h: 94px` definido mas a topbar é `h-14` (56px) — token obsoleto; "Alternar tema" no menu de conta sem indicar o tema atual.

## 5. Menu da conta / troca de workspace — `AppShell.tsx:210-297`, `WorkspaceContext.tsx`

**Bom:** papel como `Badge` (rótulo), workspace como único controle com chevron/Tab; caso de um só workspace vira texto estático **fora da ordem de Tab** (não select desabilitado).

- Ver 🔴/🟠 do switcher e da gaveta acima. Sem novos achados isolados — a distinção controle-vs-rótulo é bem pensada.

## 6. Sino + central de notificações — `features/notifications/`

**Bom:** sino `h-9 w-9` (36px) com contagem no `aria-label`; central com estados vazio/carregando/contexto-quebrado honestos.

- 🔴 **Badge de não-lidas ilegível (vermelho-sobre-vermelho ~1,30:1)** — `NotificationBell.tsx:32`. Fix: `bg-danger-solid` + branco.
- 🟠 **Header da central estoura em ≤320px** — `h2` + dois botões de texto em `flex justify-between` dentro de `w-80 max-w-[90vw]` (`NotificationCenter.tsx:29-47`). Fix: empilhar as ações.
- 🟠 **Item lido baixa `opacity-60` no texto inteiro** — `:62-64`: joga o corpo abaixo de 4,5:1. Fix: sinalizar lido pelo ponto/fundo, não pela opacidade do texto.
- 🟡 Fundo de não-lido `bg-accent/5` quase imperceptível; texto do badge ~10px.

## 7. Visão Geral — `app/pages/OverviewPage.tsx`

**Bom (confirmado ao vivo, desktop+mobile):** duas métricas nomeadas ("% físico global" + "Anéis: ponderado"); `ProgressRing` omite o traço a 0% (não desenha ponto falso); **grid `grid-cols-1` na base → sem estouro em 375/320px**; card inteiro clicável (`role=button` + `aria-label="Abrir X"`) com controles internos isolados; swipe-to-reveal owner-only contido, com o `IconButton` do rodapé como caminho acessível.

- 🟠 **Inconsistência de posição da ação primária:** "Novo Projeto" em linha própria abaixo da busca (Overview) vs "Nova célula"/"Adicionar robôs" inline com o título (Projeto/Célula). Padronizar.
- 🟡 Busca "Buscar" `py-1` (~27px) sub-32px enquanto o input ao lado é 32px; caption `label-sm` (~11px) pequena para "legível de longe".

## 8. Projeto — `app/pages/ProjectPage.tsx`

**Bom:** mesma disciplina de métricas e cards; breadcrumb "Voltar à Visão Geral".

- 🟠 **`BackLink` sem `min-h` (~20px)** — `LevelChrome.tsx:10-17`: alvo de "Voltar" tocado de luva em toda tela de nível. Fix: `min-h-[2rem]`+padding.
- 🟡 `IconButton size="sm"` (32px exatos) no rodapé, dois com `gap-1` (4px) — no piso, sem folga de luva; considerar `md` (36px).

## 9. Célula — `app/pages/CellPage.tsx`

**Bom:** cards de robô com badge de aplicação, anel e contagem de tarefas.

- 🟠 **Affordance inconsistente entre níveis:** cards de célula têm renomear+excluir; cards de robô só excluir (confirmado ao vivo). Alinhar o conjunto de ações.
- 🟡 Badge "Solda Ponto" quebra em 2 linhas dentro da pílula enquanto "Handling"/"Sealing" ficam em 1 — tratamento desigual.

## 10. Tabela do Robô (registro de avanço) — `app/pages/RobotTaskTablePage.tsx` + `features/advances/`, `robot-tasks/`

A superfície central do operador. **Bom:** dois layouts reais (tabela ≥768px / cartões `<dl>` rotulado abaixo — confirmado ao vivo em 375 e 320px, **sem scroll horizontal**); cabeçalho com % ponderado nomeado; `memo` nas linhas; empty-state que ensina; `touch-pan-y` no slider.

- 🔴 **Slider de progresso = 16px de altura (medido)**, único jeito de mudar o avanço — `AdvanceControls.tsx:60-83`. Piso de luva é 32px. Fix: estilizar o thumb/track para ≥32px de área de toque.
- 🔴 **`StatusSelect` ~22–25px (medido)** — `StatusSelect.tsx:42` (`py-0.5`+`label-md`): controle primário do operador. Fix: `min-h-[32px]`.
- 🔴 **AdvanceModal inline no `<td>`** (ver Resumo #4) — `AdvanceModal.tsx:114-121`.
- 🟠 **AdvanceModal não sinaliza offline/enfileirado** — `useRecordAdvance` devolve `QUEUED` offline, mas o `onSuccess` fecha idêntico ao salvo real (`AdvanceModal.tsx:75`), com botão "Salvando…" (Princípio 2). Fix: detectar `wasQueued` e mostrar "Sem rede — avanço enfileirado".
- 🟠 **`text-amber-700` cru (~3:1) no título do aviso de conflito** — `AdvanceModal.tsx:126`; fora do gate. Fix: `text-warning-ink`.
- 🟠 **`role="tablist"` incompleto** no filtro Todos/Pendentes/Concluídos — sem `tabpanel`/`aria-controls`, sem setas (`:97-111`). Fix: completar o padrão ou rebaixar para botões com `aria-pressed`.
- 🟠 **`aria-label` truncado no meio da palavra** nos botões de editar ("…para tes") — o leitor lê nome cortado (confirmado no a11y tree ao vivo).
- 🟡 Botão de contagem da Trilha e aviso "Registre o avanço" ~18–22px (`TrilhaCell.tsx:45-66`); colunas em `label-sm` (~11px); seta única no slider já commita e abre o modal.

## 11. Minhas Tarefas — `app/pages/MyTasksPage.tsx`

**Bom (confirmado ao vivo):** três estados distintos (vazio / 409 identidade / erro de rede) com cópia própria e `role=alert`; **estado vazio que ensina** ("concluídas e N/A não aparecem aqui" + CTA); um layout por vez (tabela/cards); linha é `<a href>` real com `min-h-[40px]`.

- 🟡 Coluna "Progresso" com `{progress}%` cru — é o percentual da própria tarefa (não fere D15), mas o rótulo "Progresso" é o termo ambíguo que o produto evita; preferir "Avanço da tarefa".
- 🟡 `hover:bg-accent/5` na `<tr>` inteira sugere linha toda clicável, mas só a 1ª célula é o link; skeleton de carregamento não lembra a tabela/cards.

## 12. Relatório de comissionamento — `app/pages/ReportPage.tsx` + `features/report/`

**Bom (confirmado ao vivo):** nada é recalculado no cliente (%/glifos/rótulos/contagens vêm do payload); documento nunca renderiza parcial; offline distinto de erro; **duas métricas nomeadas** (barras ponderadas + distribuição de contagem por **símbolo + rótulo + cor**, não só cor); metadados auditáveis (Id do documento, emitido em, estrutura); **contrato de impressão excelente** (A4, thead/tfoot correntes, monocromático legível). `select` de escopo temático `h-9` com `<label>`.

- 🟠 **Não é responsivo no mobile** (ver Resumo #8) — tabela print-width 433px cortada em 375/320px, sem scroll horizontal. Fix: reflow do documento na tela estreita (ou container `overflow-x:auto` com min-width).
- 🟠 **Carimbo = hero-métrica banida** + nome da métrica 0,68rem `text-text-muted` — `ReportHeader.tsx:17-20`. Fix: rótulo em `.label-md`+`text-text-main`, reduzir o domínio do %.
- 🟠 **Nome da métrica em `text-text-muted/70` (<4,5:1)** — `ReportBody.tsx:31` (só na tela; impressão sobrepõe). Fix: remover `/70`.
- 🟡 `border-warning/50` pode cair abaixo de 3:1; loading `role=status` "leve" ao lado dos painéis com borda; `break-before:page` sempre joga Conclusões para folha nova.

## 13. Configurações — `app/pages/SettingsPage.tsx` (página única com rolagem)

> Nota: **não há abas** — Equipe/Catálogo(Tarefas-base)/Aparência/Fila offline/Log de auditoria/Utilitários são seções empilhadas numa página longa (confirmado ao vivo). Não existe padrão de aba a auditar aqui.

**Bom:** controles de escrita saem do DOM para `view` (não só `disabled`); painéis de settings usam tokens testados; `AppearancePanel` é modelo de estado honesto (`aria-pressed`, `role=group`, aviso `role=status` quando o storage bloqueia a persistência).

- 🔴 **Título "Configurações" sem estilo** — `SettingsPage.tsx:29` (`.page-title` inexistente); todas as outras páginas usam `.title`. Fix: `.title`.
- 🟡 **Card dentro de card em "Utilitários"** — a seção bordada contém a sub-caixa "Backup do workspace" também bordada (confirmado ao vivo); nested card é anti-padrão. Fix: uma borda só.

### 13a. Equipe (responsáveis) — `features/settings/PeoplePanel.tsx`
- 🔴 **Remover pessoa ~18px** (`p-0.5` em ícone 14px) — `PeoplePanel.tsx:62-69`: metade do piso. Pior: **chip feito à mão** em vez do primitivo `Chip` (cujo remover é `h-8 w-8`). Fix: usar `Chip` com `onRemove`.
- 🟠 **Duas telas "Equipe":** este painel (responsáveis atribuíveis) e `/configuracoes/equipe` (membros/papéis/convites) têm ambos o H2 "Equipe" sem pista de diferença. Fix: renomear um (ex.: "Responsáveis") e cruzar link.

### 13b. Catálogo / Tarefas-base — `features/catalog/CatalogPanel.tsx`
- 🟠 **Vários alvos <32px:** lixeira 16px sem padding (`:108`), "Confirmar exclusão"/"Cancelar" texto cru ~20px (`:101-104`), gatilho de editar aplicações texto sem `min-h` (`:86-95`), checkboxes nativos ~14px (`:150`).
- 🟠 **`aria-label` duplicado "Editar aplicações"** em todas as linhas — `:90`: leitor ouve o mesmo rótulo 30x. Fix: `${T.edit}: ${tpl.desc}`.
- 🟠 **Controle inline indistinguível de texto estático** — a célula de aplicações é `<button>` estilizado como texto muted (`:86-95`), sem afordância de clique. Fix: ícone de lápis/sublinhado.
- 🟡 Confirmar-exclusão como texto sem chrome, a um toque de "Cancelar"; categoria só na 1ª linha do grupo (associação só visual para leitor).

### 13c. Aparência — `features/settings/AppearancePanel.tsx`
- **Bom:** toggle Escuro/Claro com `aria-pressed`, aviso honesto quando o storage bloqueia (confirmado ao vivo, os dois temas renderizam corretamente).

### 13d. Utilitários / Factory Reset — `features/settings/UtilitiesPanel.tsx` + `FactoryResetModal.tsx`
- **Bom:** backup-antes-de-resetar inbypassável; confirmar só habilita ao digitar o nome do workspace; não fecha no meio da operação.
- 🔴 **Input de confirmação sem estilo/tema** — `FactoryResetModal.tsx:85-92` (`.input-base` inexistente): sem fundo temático (regra F, risco branco-no-branco), sem borda, sem altura/alvo — na ação **mais destrutiva** do produto. Fix: `bg-bg-main border h-9 rounded-md px-3`.
- 🟡 "Exportar backup" branco sobre `#3b82f6` (mesmo débito de contraste do `Button` default).

## 14. Equipe e convites (tela dedicada) — `features/team/TeamPanel.tsx`

**Bom:** regiões nomeadas ("Membros" vs "Convites pendentes") para distinguir o mesmo e-mail em dois estados; colisão de nome com o atalho "Convidar" do AppShell tratada de propósito.

- 🟠 **DS paralelo:** tokens legados (`text-muted-foreground`, `text-destructive` `#ef4444` como texto de erro — fora do gate), tipografia de template (`text-xl font-semibold`) — `:79-219`. Fix: portar para `text-text-muted`/`text-danger-ink`/`panel-header`.
- 🟠 **`window.confirm()` para remover membro / revogar** — `:111,134`: diálogo do SO não-temático, quebra o contrato do `Modal`, é o 4º padrão de confirmação diferente. Fix: usar `Modal`.
- 🟡 `select` de papel `py-1` (~28px) sub-32px.

## 15. Modais (avanço, atribuição, histórico, adicionar tarefa/robôs, convite)

**Bom:** Atribuição, Histórico, Adicionar tarefa e editar/excluir usam o primitivo `Modal` (portal + trap + Esc-devolve-foco). `AssignmentModal` tem linha de checkbox `min-h-[40px]` clicável inteira, dedup por nome com `role=status`, versão só-leitura para `view`. `HistoryModal` marca "sem comentário" explicitamente. `AcoesCell` com botões 40×40 (medido). "Nova tarefa" centraliza e cabe em 375 **e 320px** (confirmado ao vivo).

- 🔴 **AdvanceModal** — o único fora do primitivo (ver #4/#10).
- 🟠 **Modal primitivo sem scroll-lock de body e sem `max-h`** — `Modal.tsx:65-66,68`: a página rola atrás no mobile; modal alto estoura o viewport sem scroll interno. Fix: travar `overflow` do body + `max-h-[90vh] overflow-y-auto`.
- 🟠 **× do Modal sem tamanho de toque** — `Modal.tsx:78`: glifo cru. Fix: usar `IconButton icon="close"` (32px).
- 🟡 `HistoryModal` usa `border-l-2 border-accent/40` (ban literal de borda-lateral); `AddTaskModal` Enter só submete no campo Descrição; `BatchRobotWizard` sem mensagem de erro se `batch.mutate` falhar.

## 16. Estados vazios / carregando / erro (transversal)

**Bom:** skeletons nos três níveis da hierarquia; empty-states que ensinam (Minhas Tarefas, tabela do robô); Relatório com offline distinto de erro; central de notificações com contexto-quebrado tratado.

- 🟠 **Offline estilizado como cinza-muted** — `ConnectionIndicator.tsx:25` e a leitura de rede: baixa ênfase para "às vezes sem rede" (Princípio 2). Fix: dar ênfase warning/danger ao offline.
- 🟠 **`StorageWarning` com classe morta `text-text`** (`:42,49`) — corpo e hover do "Dispensar" não aplicam a cor pretendida; "Dispensar" `py-0.5` (~20px). Fix: `text-text-main` + `min-h-[32px]`.
- 🟡 Loaders "…" crus em PeoplePanel/CatalogPanel sem `aria-busy`.

## 17. Primitivos do design-system — `components/ui/` + `menu/` + `styles/`

**Bom:** `Badge`/`Chip`/`IconButton`/`FilterBar`/`ProgressRing`/`Hub`/`SaveIndicator` são disciplinados e fiéis ao DESIGN (alpha composto, `tabular-nums`, `label` obrigatório por tipo, `aria` correto). Tokens: fonte única de cor, alpha-como-papel, escala z semântica, `:focus-visible` no `@layer base`, reduced-motion que **congela** a luz ambiente.

- 🔴 **`Button` default/destructive falham AA** (ver #2); **variantes `primary`/`gradient`/`uiverse` (bans) ainda exportadas** — `:6,21-23`. Fix: remover do union para o `tsc` travar.
- 🔴 **`Tooltip` só hover** (ver #7) — `:22`; sem `aria-describedby`, não dismissível.
- 🔴 **`Modal` sem scroll-lock/×-de-toque/max-h** (ver #15).
- 🔴 **`PortalMenu` nunca foca a si mesmo** → setas/Home/End/Enter não disparam — `menu/PortalMenu.tsx:39-57` (o `PortalPopover.tsx:47` faz certo); itens ~25px (`:167`); item desabilitado `opacity-40` sobre texto já muted (<3:1); sem hover de mouse.
- 🟠 **`StatusSelect` borda `border-current/30` (<3:1)** — `:42`; **`IconButton` foco `ring-accent` não-AA** — `:26` (o correto é `ring-ring`); **`Hub` `role=progressbar` sem nome acessível** — `:22-27`; `Button`/`Input` **desabilitado por `opacity-50`** falha ≥3:1.
- 🟠 **Utilitários gradient-text e bordas rainbow no `globals.css`** (`:319-471`) — bans vivos; `color-scheme` nunca declarado (glifos nativos claros no escuro).
- 🟡 `Badge` sem `.tabular` na base; `Input` sem estado de erro/hover; `Card` genérico shadcn com `<h3>` fixo (risco de ordem de heading); `FilterBar` com `role=tab` sem roving/`aria-controls`.

---

## Recomendações priorizadas (mapa achado → comando impeccable)

Sugestões — implementar só com o ok do dono. Em ordem de impacto:

1. **`/impeccable audit` (contraste + alvo de toque)** — resolver os 🔴 de contraste (Button default/destructive, login, badge do sino, `text-red-600`, `text-amber-700`, metric name `/70`) e os alvos <32px do operador (slider, `StatusSelect`, remover-pessoa, catálogo, BackLink). É o maior ganho: são regras duras já testadas no CI, só de uso.
2. **`/impeccable harden`** — AdvanceModal → primitivo `Modal`; `Modal` com scroll-lock + `max-h` + ×-de-toque; gaveta mobile com trap/Esc/`inert`; Factory-reset input; classes CSS mortas (`.page-title`/`.input-base`/`text-text`); `PortalMenu` foco+teclado; `role=dialog` do InviteDialog; sinal offline/enfileirado honesto.
3. **`/impeccable adapt`** — Relatório responsivo no mobile (reflow/overflow do documento print-width).
4. **`/impeccable distill`** — remover variantes gradiente/`uiverse` do `Button` e os utilitários gradient-text/rainbow do `globals.css` (bans vivos) + `BuildPage` legado.
5. **`/impeccable clarify` + `/impeccable layout`** — unificar os 4 padrões de confirmação de exclusão; renomear uma das telas "Equipe"; padronizar posição da ação primária; portar Team/Invite para os tokens/typografia do sistema.
6. **`/impeccable polish`** — passada final (nested card em Utilitários, badge "Solda Ponto", `label-sm` pequeno, loaders "…", etc.).

> Rode `/impeccable critique` de novo após as correções para ver a nota subir de **27/40**.
