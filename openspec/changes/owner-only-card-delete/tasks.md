## G0. Reconciliação e esqueleto da change

- [x] G0.1 Materializar a change no formato OpenSpec (`proposal.md`, `design.md`,
  `specs/authorization-policies/spec.md`, `specs/owner-only-card-delete/spec.md`, `tasks.md`)
  reconciliando com a REALIDADE (backend pronto, UI faltante nos cards de projeto/robô,
  `useDeleteRobot` inexistente, sem motor de swipe)
- [x] G0.2 Escrever `EXECUCAO.md` com o mapa de grupos G0..G4, as decisões (D1 matriz, D2
  consequência do edit, D3 UI, D4 swipe nativo, D5 só-excluir, D6 acessível, D7 tarefa) e as
  armadilhas (matriz literal, swipe × navegação, invalidação do robô)
- [x] G0.3 Decisões FIXADAS pelo dono: **DA-1 = tarefa TAMBÉM owner-only** (ajuste), DA-2 =
  swipe só excluir + confirmação, DA-3 = três níveis + tarefa — registrado no `EXECUCAO.md`
- [x] G0.4 Verificação: `npx --yes @fission-ai/openspec@1.6.0 validate owner-only-card-delete
  --strict` verde

## G1. Autorização — excluir (projeto/célula/robô/TAREFA) vira owner-only

- [x] G1.1 `PermissionMatrix`: adicionada `destroy_commissioning: %i[owner]` (9ª linha,
  logo após `manage_commissioning`)
- [x] G1.2 `ProjectPolicy`/`CellPolicy`/`RobotPolicy`/`TaskPolicy`: `destroy?` →
  `:destroy_commissioning` (create/update/reorder/assign seguem em owner+edit)
- [x] G1.3 `permission_matrix_spec.rb` reafirma a 9ª linha; `resource_policies_spec` e
  `matrix_conformance_spec` reescritos (destroy owner-only nos 4 recursos; edit→403; a
  conformance HTTP de TAREFA, antes `pending` por robot-tasks, foi IMPLEMENTADA); `tasks_spec`
  exclusão agora owner-only (owner→204, edit→403 mas cria/edita)
- [x] G1.4 **Verificação:** `spec/policies spec/authorization spec/requests/tasks_spec
  spec/requests/hierarchy_crud_spec spec/requests/hierarchy_soft_delete_spec` = **257
  exemplos, 0 falhas, 7 pending** (pendings pré-existentes). owner→204, edit/view→403 nos 4
  recursos; edit ainda cria/edita/reordena/atribui; cross-tenant 404 (não-membro falha no
  `member?` antes do papel); reset de fábrica inalterado.

## G2. UI — excluir owner-only: 3 níveis de hierarquia + tarefa

- [ ] G2.1 `useDeleteRobot` novo em `useHierarchy.ts` (ligar `hierarchyApi.deleteRobot`,
  invalidar só `robots(wsId, cellId)`, espelhando `useCreateRobot`/`useDeleteCell`)
- [ ] G2.2 `CellPage`/card de robô: `IconButton` lixeira (owner-only) → `DeleteRobotDialog`
  (padrão do `DeleteCellDialog`)
- [ ] G2.3 `OverviewPage`/`ProjectCard`: `IconButton` lixeira (owner-only) → `DeleteProjectDialog`
  → `useDeleteProject` (hoje órfão); invalidar `qk.overview`/`projects`
- [ ] G2.4 `ProjectPage`/card de célula: re-gated de `canEdit` para owner-only (o controle já
  existe); alinhar rótulos e o diálogo (aviso de subárvore arquivada)
- [ ] G2.5 `AcoesCell` (tarefa): a lixeira vira owner-only via `canDelete={isOwner}`; o lápis
  (editar descrição) segue em owner+edit; excluir tarefa passa por confirmação
- [ ] G2.6 Gating dos controles de EXCLUIR de `canEdit` para `isOwner` nas telas de hierarquia
  e no `AcoesCell`; **não** trocar o gating de criar/editar/reordenar/atribuir
- [ ] G2.7 **Verificação:** `vitest` — dono vê os 4 excluir, edit vê editar mas não excluir,
  view não vê nada; confirmar/cancelar; invalidação correta; `tsc`/`lint`; sweep de convenção
  (sem invalidar tenant inteiro, sem importar `lib/api` em `app/`)

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
