## G0. Reconciliação e esqueleto da change

- [ ] G0.1 Materializar a change no formato OpenSpec (`proposal.md`, `design.md`,
  `specs/code-only-invites/spec.md`, `tasks.md`) reconciliando com a REALIDADE do repo (o
  que `workspace-invitations`/`invite-by-code` construíram e o que sai)
- [ ] G0.2 Escrever `EXECUCAO.md` com o mapa de grupos G0..G4, as decisões (D1 profundidade,
  D2 coluna dormente, D4 allowlist encolhe) e as armadilhas previstas (testes que cobrem
  token, ordem `code/*` vs `:token`, model `validates :token`)
- [ ] G0.3 **Confirmar com o dono as decisões abertas DA-1 (convites já criados) e DA-2
  (profundidade)** antes de qualquer código — registrar a resposta no `EXECUCAO.md`
- [ ] G0.4 Verificação do grupo: `npx --yes @fission-ai/openspec@1.6.0 validate
  code-only-invites --strict` verde

## G1. Backend — remover os endpoints e a superfície pública por token

- [ ] G1.1 Remover `GET ':token'` (preview) e `POST ':token/accept'` (aceite) de
  `invitation_tokens.rb`, mantendo o `namespace :code` intacto
- [ ] G1.2 `AcceptService`/`PreviewService`: remover os ramos de token (`lookup_by_token`/
  `lookup`); construtor deixa de aceitar `token:`; o código vira o único localizador
- [ ] G1.3 Entity: parar de expor `invite_url`; remover o uso de `AppUrl.invite_url`
- [ ] G1.4 Remover as entradas de token de `root.rb` (`PUBLIC_ROUTES`,
  `TENANT_EXEMPT_ROUTES`) e de `config/authorization/public_routes.yml` (D4 — allowlist
  encolhe, registrado)
- [ ] G1.5 **Verificação:** request specs de code/preview + code/accept verdes; specs de
  preview/accept por token **removidos** (não deixar spec cobrindo rota inexistente);
  route-sweep e cross-tenant verdes (rota e allowlist saíram juntas); regressão de
  `invitations`/`tenancy`/`authorization` sem falha

## G2. Frontend — remover toda a superfície de LINK

- [ ] G2.1 `InviteDialog.tsx`: remover a região do link (input `invite_url`, `copiar()`,
  "Copiar link"); manter a região do código + "Copiar código"
- [ ] G2.2 `TeamPanel.tsx`/`LinhaConvite`: remover o input `invite_url` da lista de pendentes
- [ ] G2.3 Remover a rota `/convite/:token` (`App.tsx`) e o componente `InviteRoute.tsx`; se
  algum redirect apontava para lá, repontar para a entrada por código
- [ ] G2.4 `session.ts`/`invite.ts`: remover `consumeInvite` (token), o ramo de token de
  `handleInviteAfterAuth` e a chave `INVITE_KEY`; DTO deixa de ter `invite_url`
- [ ] G2.5 **Verificação:** `vitest` dos diálogos/AuthPage/AppShell verde (o caminho de
  código intacto); `tsc --noEmit` e `lint` limpos; testes que exercitavam link removidos/
  reescritos

## G3. E2E e documentação

- [ ] G3.1 `frontend/e2e/tests/invite-code.spec.ts`: retirar/ajustar qualquer trecho que
  dependa do link; garantir que o fluxo de convite E2E é **só por código**; `e2e:lint` verde
  (execução em navegador é HANDOFF, padrão da casa)
- [ ] G3.2 Atualizar a documentação no MESMO empurrão: `CONTINUIDADE.md` (nova change,
  código-só), `VALIDACAO_WSL.md` se algum passo de validação citava o link,
  `openspec/changes/invite-by-code/*` (anotar que §F.1 "coexiste" foi superado por esta
  change — não reescrever histórico, anotar); `grep -rn "convite/\|invite_url\|Copiar link"
  *.md` para caçar runbook que mande usar o link
- [ ] G3.3 **Verificação:** `openspec validate code-only-invites --strict` verde; suíte
  backend do raio (invitations/tenancy/authorization) + frontend (`vitest run`) verdes

## G4. Fechamento

- [ ] G4.1 `EXECUCAO.md`: CONCLUSÃO com o que foi removido, as decisões finais (DA-1/DA-2
  como o dono decidiu) e o estado das suítes
- [ ] G4.2 Resumo pt-BR client-friendly ao dono
