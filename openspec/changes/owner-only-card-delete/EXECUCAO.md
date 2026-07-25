# EXECUCAO — owner-only-card-delete

> **Status: EM EXECUÇÃO.** Decisões FIXADAS pelo dono (não mais pendentes):
> **DA-1 = SIM, tarefa TAMBÉM owner-only** (ajuste explícito do dono: "excluir cards
> de tarefas também") — o `destroy` de tarefa sai do `edit`, junto com os três níveis
> de hierarquia. **DA-2 = swipe revela SÓ excluir, sempre com confirmação.**
> **DA-3 = cobrir os três níveis (projeto/célula/robô) + tarefa.**
>
> **Escopo do `destroy_commissioning` (owner-only):** `ProjectPolicy`, `CellPolicy`,
> `RobotPolicy` **e `TaskPolicy`** (`destroy?`). `create?`/`update?`/`reorder?`/`assign?`
> ficam em owner+edit — um membro `edit` continua criando/editando/reordenando/atribuindo,
> só perde o EXCLUIR (dos quatro).

## O estado REAL do delete hoje (a descoberta central)

**Não é permissão — é UI faltante.**

- Backend: `DELETE /api/v1/{projects,cells,robots}/:id` existem, fazem soft-delete
  (`SoftDeleteService`, 204), gated `destroy? → manage_commissioning = %i[owner edit]`. **O
  dono é autorizado hoje.**
- Frontend: controle de excluir só nos **cards de célula** (`ProjectPage.tsx:83–93` →
  `DeleteCellDialog`). **Cards de projeto (`OverviewPage`) e de robô (`CellPage`) não têm
  botão de excluir para ninguém.** `useDeleteProject` (`useHierarchy.ts:125`) está órfão;
  `useDeleteRobot` **não existe**; `deleteRobot` (`endpoints.ts:376`) é código morto.
- Gating: em toda tela `canEdit = role === 'owner' || role === 'edit'` — o dono passa. Não
  há bug de papel. O dono "não consegue apagar" projeto/robô porque **o botão não existe**;
  célula ele consegue.

## Mapa de grupos

| Grupo | Entrega | Verificação |
|---|---|---|
| G0 | Reconciliação + esqueleto OpenSpec + este EXECUCAO | `validate --strict` verde |
| G1 | Autorização owner-only (matriz + **4 policies**: Project/Cell/Robot/Task + specs) | policy specs owner→204, edit/view→403; cross-tenant 404; reset intacto |
| G2 | UI de excluir: 3 níveis de hierarquia (novo `useDeleteRobot`) + tarefa re-gated (AcoesCell) — tudo owner-only | `vitest`/`tsc`/`lint`; sweep de convenção |
| G3 | Swipe-to-reveal no `EntityCard` (cards de hierarquia) com alternativa acessível | teste de gesto + axe/contraste |
| G4 | Documentação + fechamento + resumo | — |

## Decisões FIXADAS

- **D1** owner-only por nova action `destroy_commissioning: %i[owner]` na matriz (não `role
  ==` na policy); repontar `destroy?` de **Project/Cell/Robot/Task**.
- **D2** consequência: `edit` perde excluir (dos 4), mantém criar/editar/reordenar/atribuir;
  **não** afeta reset de fábrica (já owner-only) nem o soft-delete (só o gate muda).
- **D3** fechar a UI de excluir dos 3 níveis de hierarquia reusando o padrão
  `DeleteCellDialog`; novo `useDeleteRobot`. Tarefa já tem UI de excluir (`AcoesCell`) — só
  re-gated para owner-only (o botão editar da tarefa fica em owner+edit).
- **D4** swipe no `EntityCard` (cards de hierarquia) com pointer nativo + `transform`, dentro
  dos tokens (≥40px, `touch-pan-y`, reduced-motion instantâneo, z semântico, não briga com
  `role=button`). **Escopo do gesto:** só os cards de hierarquia (EntityCard); a tarefa vive
  numa tabela/`MobileTaskCard` — seu excluir continua pelo botão (owner-only), sem swipe.
- **D5** swipe revela **só excluir**, sempre com confirmação.
- **D6** o gesto nunca é o único caminho — `IconButton` de teclado/leitor de tela permanece.
- **D7 (ajuste do dono):** `TaskPolicy#destroy?` **também** vira owner-only; no `AcoesCell`,
  o botão lixeira é gated por owner enquanto o botão editar segue em owner+edit (o
  `RobotTaskTablePage` monta o `AcoesCell` quando `canEdit`, e passa `canDelete={isOwner}`).

## G1 — resultado (backend, VERDE)

- **Produção:** `PermissionMatrix` +`destroy_commissioning: %i[owner]` (9ª linha);
  `ProjectPolicy`/`CellPolicy`/`RobotPolicy`/`TaskPolicy` `destroy?` → `destroy_commissioning`.
- **Specs:** `permission_matrix_spec` (9ª linha + `.allows?`); `resource_policies_spec`
  (destroy owner-only nos 4; `authorize!(edit,:destroy)`→Forbidden); `matrix_conformance_spec`
  (ESPERADO +linha; teste HTTP: edit cria/edita mas NÃO exclui; **implementada** a conformance
  HTTP de TAREFA que estava `pending` por robot-tasks); `tasks_spec` exclusão owner-only.
- **Gate:** `policies + authorization + tasks + hierarchy_crud + hierarchy_soft_delete` =
  **257/0/7pend**. Cross-tenant inalterado (não-membro → 404 no `member?`, antes do papel);
  reset de fábrica intacto (já `destroy_workspace`).

## Armadilhas previstas

- **Matriz literal:** `permission_matrix_spec.rb` reafirma a matriz linha a linha — adicionar
  `destroy_commissioning` obriga atualizar o spec (por design). Esquecer = build vermelho.
- **Specs que afirmam "edit exclui":** precisam virar "edit→403, owner→204" nos três recursos.
- **Swipe × navegação do card:** maior risco de UX. Sem limiar/`touch-pan-y`, um scroll vira
  delete acidental, ou o tap-para-abrir compete com o arrasto. Testar gesto explicitamente.
- **Invalidação do robô:** `useDeleteRobot` deve invalidar só `robots(wsId, cellId)` (regra de
  convenção: nunca o tenant inteiro), espelhando `useCreateRobot`.
- **Reduced-motion:** o JS do gesto deve respeitar (sem inércia/bounce), não só o CSS global.
- **`edit` no servidor:** garantir 403 real (não só sumir o botão) — a UI é conveniência, a
  autoridade é a policy.
