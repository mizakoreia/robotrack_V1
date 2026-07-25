# Tasks — `impeccable-remediation`

Grupos ordenados por **dor do operador** (ver `EXECUCAO.md`). Um grupo por vez, prova
verde, ff para `main`, **aprovação do dono entre grupos**. Nada de `[x]` sem prova verde;
handoff é anotado como handoff.

## G1. Contraste + alvo de toque (o que mais dói para o operador de luva)

- [x] 1.1 `styles/globals.css`: classe `.progress-slider` estilizando `<input type=range>` nos dois motores (`::-webkit-slider-thumb`/`-runnable-track`, `::-moz-range-thumb`/`-track`), com área de toque **≥ 32px** base e **≥ 40px** sob `@media (pointer: coarse)`; trilho `--track`, thumb `--accent-solid` com borda `--bg-panel`, foco `--ring`. (§Princípio 1 — o range nasce 16px; o thumb visível fica menor que a área de toque de propósito)
- [x] 1.2 `features/advances/AdvanceControls.tsx`: aplicar `progress-slider` ao slider. (§Princípio 1 — o único jeito de mudar o avanço passa a ter alvo de luva)
- [x] 1.3 `components/ui/StatusSelect.tsx`: `min-h-[2.5rem] sm:min-h-[2rem]` (40 mobile / 32 desktop), `py-1`, borda `border-current/70` (≥3:1). (§Princípio 1 + §5.2 — controle primário do operador; borda `/30` reprovava não-texto)
- [x] 1.4 `components/ui/Button.tsx`: default → `bg-accent-solid text-white hover:brightness-110`; destructive → `bg-danger-solid text-white hover:brightness-110`. (§DESIGN regra dura — #3b82f6 dá 3,68:1; a sólida dá 6,70:1)
- [x] 1.5 `features/auth/AuthPage.tsx`: 3 submits `bg-primary`→`bg-accent-solid` (+`hover:brightness-110 transition`); todos os `text-red-600`→`text-danger-ink`. (§DESIGN — tira o login de fora do gate de contraste)
- [x] 1.6 `features/notifications/NotificationBell.tsx`: badge `bg-danger`+`text-danger-ink`→`bg-danger-solid`+`text-white`. (§DESIGN — vermelho-sobre-vermelho ~1,30:1 → 5,9:1)
- [x] 1.7 `components/ui/IconButton.tsx`: `focus-visible:ring-accent`→`focus-visible:ring-ring`. (§5.1 a11y — foco AA)
- [x] 1.8 **Gate:** `tests/touch-and-contrast-usage.test.ts` — trava (a) `.progress-slider` no slider e a regra `(pointer: coarse)` no CSS; (b) piso de toque no `StatusSelect`; (c) uso de `--accent-solid`/`--danger-solid`/`--danger-ink` (não `bg-primary`/`bg-destructive`/`text-red-600`) em Button/AuthPage/NotificationBell; (d) `ring-ring` no IconButton. (§Princípio 1 — o gate MORDE: reprova a versão atual)
- [x] 1.9 **Verificação:** `contrast.test.ts` + o novo gate + `convention-sweep` verdes; `vitest` das áreas tocadas; `tsc --noEmit`; `eslint` — todos verdes. Screenshot do slider/select/login/sino em mobile + desktop.

## G2. Harden dos modais e da navegação (bloqueios de a11y) — AGUARDA OK DO DONO

- [ ] 2.1 `components/ui/Modal.tsx`: scroll-lock do `body` ao abrir; `max-h-[90vh] overflow-y-auto` no conteúdo; × via `IconButton icon="close"` (32px).
- [ ] 2.2 `features/advances/AdvanceModal.tsx` (+ `AdvanceControls`): portar para o primitivo `Modal` (portal/fixed/trap/Esc); remover o `<div role=dialog>` inline do `<td>`.
- [ ] 2.3 `features/advances/AdvanceModal.tsx`: sinal honesto de offline/enfileirado (`wasQueued` → "Sem rede — avanço enfileirado"), não fechar como "salvo"; `text-amber-700`→`text-warning-ink`.
- [ ] 2.4 `app/AppShell.tsx`: gaveta mobile com focus-trap, Esc fecha, `inert`/`hidden` quando fechada (não só `-translate-x-full`).
- [ ] 2.5 Classes CSS mortas: `SettingsPage.tsx` `.page-title`→`.title`; `FactoryResetModal.tsx` `.input-base`→campo temático (`bg-bg-main border h-9 rounded-md px-3`); `StorageWarning` `text-text`→`text-text-main` + "Dispensar" `min-h-[32px]`.
- [ ] 2.6 `styles/globals.css`/`index.html`: declarar `color-scheme` (glifos nativos claros sobre o escuro).
- [ ] 2.7 `components/menu/PortalMenu.tsx`: focar a si mesmo ao abrir (setas/Home/End/Enter); itens ≥ 32px; item desabilitado com contraste ≥ 3:1.
- [ ] 2.8 `components/ui/Tooltip.tsx`: acessível por foco + toque, `aria-describedby`, Esc dispensa.
- [ ] 2.9 `features/team/InviteDialog.tsx`: `role="dialog"` falso → `Modal` (ou remover o role).
- [ ] 2.10 **Verificação:** testes de render (Modal trap/scroll-lock, AdvanceModal via portal, PortalMenu setas, Tooltip foco/Esc, gaveta Esc/inert); `tsc`; `lint`; screenshots.

## G3. Relatório responsivo no mobile (gestor no celular) — AGUARDA OK DO DONO

- [ ] 3.1 `features/report/` + `report-print.css`: reflow/overflow do documento print-width (433px) em 375/320px **sem regredir a impressão A4**.
- [ ] 3.2 `features/report/ReportHeader.tsx`: carimbo — nome da métrica em `.label-md`+`text-text-main`, reduzir o domínio do %; `ReportBody.tsx` `text-text-muted/70`→sem `/70`.
- [ ] 3.3 **Verificação:** teste de largura/estrutura; screenshot em 320/375px; prova de que a impressão A4 não mudou.

## G4. Consistência Equipe/Convites (Nielsen 4) — AGUARDA OK DO DONO

- [ ] 4.1 `features/team/TeamPanel.tsx` + `InviteDialog.tsx`: portar tokens/tipografia (`text-muted-foreground`/`text-destructive`/`text-xl`→`text-text-muted`/`text-danger-ink`/`.panel-header`).
- [ ] 4.2 `features/team/TeamPanel.tsx`: remover `window.confirm()` de remover membro/revogar → `Modal`.
- [ ] 4.3 Desambiguar as duas telas "Equipe" (`PeoplePanel`→"Responsáveis" + link cruzado); `PeoplePanel` remover-pessoa via primitivo `Chip` (≥32px, não chip à mão de ~18px).
- [ ] 4.4 Padronizar posição da ação primária entre níveis (Overview vs. Projeto/Célula).
- [ ] 4.5 **Verificação:** testes; screenshots; `convention-sweep` regra G verde.

## G5. Distill dos bans vivos (anti-slop) — AGUARDA OK DO DONO

- [ ] 5.1 `components/ui/Button.tsx`: remover variantes `primary`/`gradient`/`uiverse` do union (tsc trava o uso).
- [ ] 5.2 `styles/globals.css`: remover `.text-goat-gradient*` e bordas rainbow (`.card-highlight`, `icon-hue-cycle`, `.btn`).
- [ ] 5.3 `features/.../HistoryModal.tsx`: `border-l-2 border-accent/40` (ban de borda-faixa) → tratamento sem faixa lateral.
- [ ] 5.4 `BuildPage`/`ProfilePage`/`UsersPage` legado: remover ou reduzir ao mínimo que compila (decidir com o dono; alinhar com `design-system` EXECUCAO decisão 3).
- [ ] 5.5 **Verificação:** `detect.mjs` sobre `frontend/src` = 0 achados; `tsc`; `lint`.

## G6. Polimento final — AGUARDA OK DO DONO

- [ ] 6.1 `UtilitiesPanel`: nested card (uma borda só).
- [ ] 6.2 Badge "Solda Ponto" quebrando em 2 linhas; tratamento uniforme das pílulas de aplicação.
- [ ] 6.3 `label-sm` pequeno para "legível de longe" onde a crítica apontou (busca, colunas).
- [ ] 6.4 Loaders "…" com `aria-busy`; item de notificação lido sinalizado por ponto/fundo (não `opacity-60` no texto); header da central empilha em ≤320px.
- [ ] 6.5 **Verificação:** `/impeccable critique` de novo (meta: nota subir de 27/40); suíte completa verde.
