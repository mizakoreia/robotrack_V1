## G0. Reconciliação e esqueleto da change

- [ ] G0.1 Materializar a change no formato OpenSpec (`proposal.md`, `design.md`,
  `specs/authorization-policies/spec.md`, `specs/owner-only-card-delete/spec.md`, `tasks.md`)
  reconciliando com a REALIDADE (backend pronto, UI faltante nos cards de projeto/robô,
  `useDeleteRobot` inexistente, sem motor de swipe)
- [ ] G0.2 Escrever `EXECUCAO.md` com o mapa de grupos G0..G4, as decisões (D1 matriz, D2
  consequência do edit, D3 UI, D4 swipe nativo, D5 só-excluir, D6 acessível) e as armadilhas
  (matriz literal, swipe × navegação, invalidação do robô)
- [ ] G0.3 **Confirmar com o dono DA-1 (tarefa também owner-only?), DA-2 (swipe só excluir?)
  e DA-3 (os três níveis?)** antes do código — registrar no `EXECUCAO.md`
- [ ] G0.4 Verificação: `npx --yes @fission-ai/openspec@1.6.0 validate owner-only-card-delete
  --strict` verde

## G1. Autorização — excluir vira owner-only

- [ ] G1.1 `PermissionMatrix`: adicionar `destroy_commissioning: %i[owner]`
- [ ] G1.2 `ProjectPolicy`/`CellPolicy`/`RobotPolicy`: `destroy?` → `:destroy_commissioning`
  (create/update/reorder ficam em `manage_commissioning`)
- [ ] G1.3 Atualizar `permission_matrix_spec.rb` (reafirma a matriz literalmente — agora 9
  linhas) e os specs de autorização/policy que afirmavam "edit exclui"
- [ ] G1.4 **Verificação:** specs de policy dos três recursos provando owner→204/204/204 e
  **edit→403** e view→403; cross-tenant→404; route-sweep de 100% das rotas ainda verde
  (nenhuma rota nova; só o gate mudou); reset de fábrica inalterado (regressão de
  `workspace-settings`/`workspace-factory-reset`)

## G2. UI — fechar a lacuna de excluir nos três níveis (owner-only)

- [ ] G2.1 `useDeleteRobot` novo em `useHierarchy.ts` (ligar `hierarchyApi.deleteRobot`,
  invalidar só `robots(wsId, cellId)`, espelhando `useCreateRobot`/`useDeleteCell`)
- [ ] G2.2 `CellPage`/card de robô: `IconButton` lixeira (owner-only) → `DeleteRobotDialog`
  (padrão do `DeleteCellDialog`)
- [ ] G2.3 `OverviewPage`/`ProjectCard`: `IconButton` lixeira (owner-only) → `DeleteProjectDialog`
  → `useDeleteProject` (hoje órfão); invalidar `qk.overview`/`projects`
- [ ] G2.4 `ProjectPage`/card de célula: re-gated de `canEdit` para owner-only (o controle já
  existe); alinhar rótulos e o diálogo (aviso de subárvore arquivada)
- [ ] G2.5 Trocar o gating dos controles de excluir de `canEdit` para `isOwner` (`role ===
  'owner'`) nas três telas; **não** trocar o gating de criar/editar/reordenar
- [ ] G2.6 **Verificação:** `vitest` — dono vê os 3 excluir, edit/view não veem nenhum;
  confirmar/cancelar; invalidação correta; `tsc`/`lint`; sweep de convenção (sem invalidar
  tenant inteiro, sem importar `lib/api` em `app/`)

## G3. Mobile — swipe-to-reveal excluir no EntityCard

- [ ] G3.1 Implementar o gesto no `EntityCard` com pointer events nativos + `transform`
  (limiar horizontal, `touch-pan-y`, distinguir tap-abre de arrasto-revela, não disparar a
  navegação `role=button`); painel Excluir `danger`, alvo ≥40px, z semântico
- [ ] G3.2 `prefers-reduced-motion`: revelação instantânea, sem bounce/elastic; só no
  toque/estreito (progressive enhancement, sem trocar o layout do grid)
- [ ] G3.3 Fiar o toque na ação revelada ao mesmo `DeleteDialog` do nível (nunca excluir direto)
- [ ] G3.4 **Verificação:** teste de gesto (RTL/pointer) — swipe revela, tap na ação confirma,
  scroll vertical não revela, swipe não abre o card; teclado/leitor de tela excluem sem o
  gesto (alternativa acessível); `axe`/contraste do painel `danger`

## G4. Documentação e fechamento

- [ ] G4.1 Atualizar a documentação no MESMO empurrão: `CONTINUIDADE.md` (nova change,
  excluir owner-only, UI dos 3 níveis, swipe), `DESIGN.md` se o swipe virar primitivo/motion
  nomeado, `VALIDACAO_WSL.md` se algum passo de validação mudar; `grep -rn "Excluir\|excluir"
  *.md` para runbook que dependa do gating antigo
- [ ] G4.2 `EXECUCAO.md`: CONCLUSÃO (o que foi fiado, DA-1/2/3 como decididas, estado das
  suítes) + resumo pt-BR client-friendly ao dono
