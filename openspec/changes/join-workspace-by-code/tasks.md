## G0. Reconciliação e esqueleto da change

- [x] G0.1 Materializar a change no formato OpenSpec (`proposal.md`, `design.md`,
  `specs/join-workspace-by-code/spec.md`, `tasks.md`) coerente com a change
  `invite-by-code` (motor reusado) e com as decisões de produto herdadas (e-mail idêntico
  ao autenticado, coexistência com o link)
- [x] G0.2 Escrever `EXECUCAO.md` reconciliando o design com a REALIDADE do repo (o que já
  existe e é reusado — `consumeInviteByCode`, `acceptByCode`, `lib/auth/code.ts`, menu da
  conta em `AppShell`, padrão `?convidar=1`; a divergência da spec `app-shell-navigation`
  sobre o nº de itens do menu da conta), com mapa de grupos G0..G2 e decisões
- [x] G0.3 Verificação do grupo: `npx --yes @fission-ai/openspec@1.6.0 validate
  join-workspace-by-code --strict` verde

## G1. Frontend: diálogo + porta no menu da conta + i18n

- [x] G1.1 Componente de diálogo de entrada por código (`features/auth/JoinByCodeDialog.tsx`,
  reusando `ui/Modal`): e-mail da sessão somente-leitura + único campo Código (máscara
  `formatInviteCode`/normalização `normalizeInviteCode` de `lib/auth/code.ts`), estado de
  carregando, erro por `aria-live`, fundo temático (regra F, `bg-bg-main`/`border-input`) e
  alvo ≥ 32px (`py-2`); no submit chama `consumeInviteByCode(codigo, emailDaSessao)` e SÓ no
  sucesso fecha + `navigate('/')`. `consumeInviteByCode` passou a retornar `boolean` (DE-G1.1)
- [x] G1.2 Item "Entrar em outro workspace com código" no menu da conta em `AppShell.tsx`
  (entre "Equipe e convites" e "Alternar tema"), seguindo o padrão `MenuItem`/`PortalMenu`;
  fiação de abertura por `?codigo=1` (`useSearchParams`, espelhando `?convidar=1`), fechar
  remove o param; diálogo montado na casca persistente
- [x] G1.3 `lib/i18n/invitations.ts`: rótulo do item de menu + textos do diálogo
  (`joinByCodeMenu`, `joinByCodeTitle`, `joinByCodeHint`, `joinByCodeAs`, `joinByCodeSubmit`);
  a mensagem de "convite para outro e-mail" REUSA `emailMismatch` (com ação de trocar de
  conta) já existente; nenhum literal de convite fora deste módulo (sweep verde)
- [~] G1.4 (Opcional — Q2) Item secundário no menu do seletor (`WorkspaceContext.tsx`),
  visível só com >1 workspace. **DEFERIDO** (recomendação Q2 adotada pelo dono: manter a
  change mínima). Registrado como decisão DE-G1.2 no EXECUCAO
- [x] G1.5 Verificação do grupo G1: vitest 35/35 nos dirigidos (diálogo 6 + AppShell 11 +
  AuthPageCode 5 + session 13), sweeps de convenção/contraste/i18n verdes (66 + 3), `tsc` e
  `lint` limpos. Confirmado que o teste do shell NÃO assertava contagem exata de itens do
  menu (itera por rótulo) — atualizado para incluir o novo item. `validate --strict` verde

## G2. E2E, docs e fechamento

- [ ] G2.1 E2E do usuário logado entrando por código de ponta a ponta
  (`frontend/e2e/tests/...`, locators ancorados por região/diálogo + `{ exact: true }`,
  seed determinístico `rt:seed:e2e*`): abre o menu da conta → item → diálogo → digita o
  código → aceite → contexto passa ao novo workspace → Visão Geral. Execução em Chromium
  aqui; WebKit/CI é HANDOFF (padrão da casa — `VALIDACAO_WSL.md`)
- [ ] G2.2 Docs no MESMO empurrão: `CONTINUIDADE.md` (seção da 27ª change, estado/suítes/git
  local) e `VALIDACAO_WSL.md` (handoff do E2E in-app, se aplicável). `DESIGN.md` NÃO tocado
  (reuso puro — nenhum token/primitivo/motion/ban novo, registrado no design G1.1/D7).
  Conferir que nenhum runbook/`.md` afirma algo falso após a mudança
  (`grep -rn "código de convite" *.md` e afins)
- [ ] G2.3 Verificação final: `validate --strict` verde; docs sem afirmação falsa; commit
  `G<n>:` LOCAL (sem push, sem `merge --ff-only main` — instrução vigente do dono);
  resumo pt-BR client-friendly entregue (o que ficou pronto, o que é handoff, o que
  aguarda decisão do dono)
