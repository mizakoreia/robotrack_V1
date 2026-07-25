# EXECUCAO — owner-only-card-delete

> **Status: G0 PLANEJAMENTO.** Change materializada (proposal/design/specs/tasks) e
> validada `--strict`. **Nenhum código de produção escrito.** Aguarda o dono confirmar
> DA-1 (tarefa também owner-only?), DA-2 (swipe só excluir?) e DA-3 (os três níveis?)
> antes do G1.

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
| G1 | Autorização owner-only (matriz + 3 policies + specs) | policy specs owner→204, edit/view→403; cross-tenant 404; reset intacto |
| G2 | UI de excluir nos 3 níveis, owner-only (novo `useDeleteRobot`) | `vitest`/`tsc`/`lint`; sweep de convenção |
| G3 | Swipe-to-reveal no `EntityCard` (mobile) com alternativa acessível | teste de gesto + axe/contraste |
| G4 | Documentação + fechamento + resumo | — |

## Decisões (recomendadas — G0)

- **D1** owner-only por nova action `destroy_commissioning: %i[owner]` na matriz (não `role
  ==` na policy); repontar os 3 `destroy?`.
- **D2** consequência: `edit` perde excluir, mantém criar/editar/reordenar; **não** afeta
  reset de fábrica (já owner-only) nem o soft-delete (só o gate muda).
- **D3** fechar a UI dos 3 níveis reusando o padrão `DeleteCellDialog`; novo `useDeleteRobot`.
- **D4** swipe no `EntityCard` com pointer nativo + `transform`, dentro dos tokens (≥40px,
  `touch-pan-y`, reduced-motion instantâneo, z semântico, não briga com `role=button`).
- **D5** swipe revela **só excluir**, sempre com confirmação.
- **D6** o gesto nunca é o único caminho — `IconButton` de teclado/leitor de tela permanece.

## Decisões em aberto (bloqueiam G1)

- **DA-1** — Excluir **tarefa** (`AcoesCell`/`useDeleteTask`) também vira owner-only? O dono
  disse "cards" (projeto/célula/robô). **Recomendo manter tarefa em owner+edit** (fluxo diário
  do operador). Confirmar.
- **DA-2** — Swipe revela só excluir, sempre com confirmação? **Recomendo sim.**
- **DA-3** — Cobrir os três níveis? **Recomendo sim** (é onde a lacuna está).

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
