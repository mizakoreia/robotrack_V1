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

- [x] G2.1 `useDeleteRobot(cellId, projectId)` novo em `useHierarchy.ts` (liga
  `hierarchyApi.deleteRobot`, invalida `robots(wsId, cellId)` + `cellOverview` +
  `projectOverview` + `overview`, nunca o tenant inteiro). `useDeleteProject` ganhou a
  invalidação de `qk.overview` que faltava (era órfão)
- [x] G2.2 `CellPage`/card de robô: `IconButton` lixeira (owner-only) → `DeleteRobotDialog`
- [x] G2.3 `OverviewPage`/`ProjectCard`: `IconButton` lixeira (owner-only) → `DeleteProjectDialog`
  → `useDeleteProject` (deixou de ser órfão)
- [x] G2.4 `ProjectPage`/card de célula: renomear fica em `canEdit`, excluir vira `isOwner`;
  diálogos com aviso de subárvore arquivada (i18n `hierarchy.*.remove`)
- [x] G2.5 `AcoesCell` (tarefa): lixeira gated por `canDelete={isOwner}`; lápis segue
  `canEdit`; excluir tarefa já passava por confirmação (mantido)
- [x] G2.6 Gating de EXCLUIR = `isOwner` nas telas de hierarquia e no `AcoesCell`; criar/
  editar/reordenar/atribuir inalterados (`canEdit`)
- [x] G2.7 **Verificação:** `tsc`/`lint` limpos; `vitest` hierarquia+robot-tasks **77/77**
  (dono vê os 4 excluir; edit vê editar mas NÃO excluir tarefa nem card; view nada; confirmar/
  remover); suíte 578/579 (a única falha é o flaky pré-existente de fila offline, alheio);
  sweep de convenção verde (invalidação específica, sem `lib/api` em `app/`)

## G3. Mobile — swipe-to-reveal excluir no EntityCard

- [x] G3.1 Gesto no `EntityCard` com pointer events nativos + `transform` (limiar `SLOP`,
  trava direção h/v, `touch-action: pan-y`, distingue tap de arrasto e não navega no arrasto);
  painel Excluir `bg-danger-solid`, alvo ≥40px, sem z literal (pintura por ordem/posição).
  Prop opcional `onSwipeDelete` (owner-only) fiada nos 3 níveis (Overview/Project/Cell)
- [x] G3.2 `prefers-reduced-motion`: snap instantâneo (transition none), sem bounce/elastic;
  só com `(pointer: coarse)` (progressive enhancement, grid intocado)
- [x] G3.3 O painel é `aria-hidden`/não-focável (não duplica nome acessível — o caminho de
  teclado/leitor é o `IconButton` do rodapé, regra G); tocá-lo abre o mesmo `DeleteDialog` do
  nível (`onSwipeDelete` → `setRemoving`), nunca exclui direto
- [x] G3.4 **Verificação:** `EntityCard.swipe.test.tsx` **5/5** — swipe revela + tap chama
  `onSwipeDelete` sem navegar; arrasto vertical não move nem revela; tap navega;
  reduced-motion sem transição; desktop (ponteiro fino) não monta o gesto. `tsc`/`lint`
  limpos; suíte 583/584 (flaky offline alheio). `DESIGN.md` atualizado. Axe em navegador é
  HANDOFF (demo viva; padrão da casa)

## G4. Documentação e fechamento

- [ ] G4.1 Atualizar a documentação no MESMO empurrão: `CONTINUIDADE.md` (nova change,
  excluir owner-only, UI dos 3 níveis, swipe), `DESIGN.md` se o swipe virar primitivo/motion
  nomeado, `VALIDACAO_WSL.md` se algum passo de validação mudar; `grep -rn "Excluir\|excluir"
  *.md` para runbook que dependa do gating antigo
- [ ] G4.2 `EXECUCAO.md`: CONCLUSÃO (o que foi fiado, DA-1/2/3 como decididas, estado das
  suítes) + resumo pt-BR client-friendly ao dono
