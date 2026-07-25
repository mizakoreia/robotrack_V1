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

- [ ] G1.1 Componente de diálogo de entrada por código (sob `features/auth/` ou
  `features/invitations/`, reusando `ui/Modal`): e-mail da sessão somente-leitura + único
  campo Código (máscara `formatInviteCode`/normalização `normalizeInviteCode` de
  `lib/auth/code.ts`), estado de carregando, erro por `aria-live`, fundo temático (regra F)
  e alvo ≥ 32px; no submit chama `consumeInviteByCode(codigo, emailDaSessao)` e no sucesso
  fecha + `navigate('/')`
- [ ] G1.2 Item "Entrar em outro workspace com código" no menu da conta em `AppShell.tsx`
  (entre "Equipe e convites" e "Alternar tema"), seguindo o padrão `MenuItem`/`PortalMenu`;
  fiação de abertura por `?codigo=1` (espelhando `?convidar=1`), fechar remove o param
- [ ] G1.3 `lib/i18n/invitations.ts`: rótulo do item de menu + textos do diálogo (título,
  contexto "Entrando como…", rótulo/placeholder do código, botão de submit, e a mensagem
  específica de "convite emitido para outro e-mail estando logado" se ainda não existir);
  nenhum literal de convite fora deste módulo
- [ ] G1.4 (Opcional/decisão do dono — Q2) Item secundário "Entrar com código…" ao fim do
  menu do seletor em `WorkspaceContext.tsx`, visível só com >1 workspace. **Deferido por
  padrão**; só implementar se o dono aprovar. Marcar como decisão no EXECUCAO
- [ ] G1.5 Verificação do grupo G1 (vitest/RTL): porta visível com 1 workspace; acionar
  abre o diálogo e fecha o menu; máscara/normalização do código; submit usa o e-mail da
  sessão e chama `consumeInviteByCode`; sucesso troca de workspace + `navigate('/')` +
  fecha; cada estado de erro (par inválido, travado, expirado, e-mail divergente, offline)
  renderiza a mensagem certa; contraste/regra F/alvo de toque conferidos; `tsc` e `lint`
  limpos nos arquivos tocados. Conferir que nenhum teste do shell asserta contagem exata de
  itens do menu da conta (e reconciliar se houver) → `validate --strict` verde

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
