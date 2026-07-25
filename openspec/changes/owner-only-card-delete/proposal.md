## Why

O dono relatou que "não consegue apagar os cards" (projetos/células/robôs). A investigação
mostrou que **não é um problema de permissão** — é **UI faltante**:

- **Backend (pronto para os três):** `DELETE /api/v1/{projects,cells,robots}/:id` existem,
  cada um faz **soft-delete** (`Hierarchy::SoftDeleteService`, 204), gated por `destroy? →
  manage_commissioning = %i[owner edit]`. O **dono é autorizado** hoje.
- **Frontend:** o controle de excluir só está fiado nos **cards de célula** (`ProjectPage`,
  `IconButton` lixeira → `DeleteCellDialog`). Os **cards de projeto** (`OverviewPage`) e os
  **cards de robô** (`CellPage`) **não têm botão de excluir para ninguém**. `useDeleteProject`
  existe mas está órfão (nenhum componente o usa); `useDeleteRobot` **não existe** (o endpoint
  `deleteRobot` é código morto). Por isso o dono só consegue excluir célula.

Além de fechar essa lacuna, o dono pediu duas mudanças de regra e de UX:

1. **Apenas o DONO pode deletar** (owner-only). Hoje o `edit` também pode
   (`manage_commissioning`). O dono quer tirar o poder de excluir do `edit`.
2. **No celular, arrastar o card para o lado revela o botão de excluir** (swipe-to-reveal),
   respeitando `DESIGN.md` (alvo de toque, `prefers-reduced-motion`, alternativa acessível).

Cobre a ESPECIFICACAO §3.2/§3.3 (telas de hierarquia) e §4.1 (matriz de autorização). Sem
tradução de Firebase nova.

## What Changes

- **Autorização — excluir vira owner-only (§4.1):**
  - Nova linha na matriz `PermissionMatrix`: `destroy_commissioning: %i[owner]`.
  - `ProjectPolicy`/`CellPolicy`/`RobotPolicy`: `destroy?` passa de `:manage_commissioning`
    para `:destroy_commissioning`. `create?`/`update?`/`reorder?` **ficam** em owner+edit.
  - **Consequência:** um membro `edit` deixa de poder excluir projeto/célula/robô — continua
    criando, editando e reordenando. `view` segue sem excluir (inalterado).
  - Atualizar `permission_matrix_spec.rb` (reafirma a matriz literalmente) e os specs de
    autorização que hoje afirmam "edit exclui" → "edit **não** exclui (403), owner exclui".
- **UI de excluir nos três níveis (fechar a lacuna):**
  - `OverviewPage`/`ProjectCard`: adicionar `IconButton` lixeira → diálogo de confirmação →
    `useDeleteProject` (já existe, hoje órfão).
  - `CellPage`/card de robô: adicionar `IconButton` lixeira → diálogo → **novo**
    `useDeleteRobot` (fiar o endpoint `deleteRobot` que já existe no client).
  - `ProjectPage`/card de célula: já existe; só re-gated para owner-only (ver abaixo) e
    alinhado ao mesmo padrão de swipe.
  - **Gating de UI:** os controles de excluir passam de `canEdit` (owner+edit) para
    **owner-only** (`role === 'owner'`), espelhando a matriz. O servidor continua sendo a
    autoridade (403 para edit).
- **Mobile — swipe-to-reveal excluir:**
  - No `EntityCard` (afeta os três grids), no viewport de toque/estreito, arrastar o card
    para a esquerda revela uma ação **Excluir** (destrutiva, cor `danger`).
  - Sempre abre o **diálogo de confirmação** (nunca exclui direto no gesto).
  - O gesto **não** é o único caminho: o `IconButton` visível (foco/teclado/leitor de tela)
    permanece. Swipe é atalho de conveniência no toque.
  - Respeita `prefers-reduced-motion` (sem animação/instantâneo), `touch-pan-y` (rolar a
    página na vertical não dispara o swipe) e não briga com a navegação do card inteiro
    (`role=button`).

## Não-objetivos

- **Não** mudar o soft-delete no banco (`Hierarchy::SoftDeleteService`) nem o 204 — só o
  **gate** (owner-only) e a **UI** mudam. A cascata (tarefas→robôs→células→nó), a auditoria e
  o recompute ficam iguais.
- **Não** tocar no **reset de fábrica** (`workspace-settings` D12) — ele já é owner-only
  (`destroy_workspace`); esta change não o altera.
- **Não** revelar outras ações no swipe (renomear/editar) — só **excluir**, mínimo e sempre
  com confirmação (ver design D5). Renomear/editar seguem pelo `IconButton`.
- **Não** introduzir biblioteca de drag/dnd — o gesto é implementado com pointer events
  nativos + `transform`, dentro dos tokens de `DESIGN.md` (D4).
- **Não** permitir excluir por `edit` em lugar nenhum (nem UI nem API) depois desta change.

## Capabilities

- `authorization-policies` (MODIFIED): excluir projeto/célula/robô passa a ser **owner-only**
  (nova action de matriz `destroy_commissioning`).
- `owner-only-card-delete` (ADDED): controle de excluir nos cards dos três níveis, visível só
  ao dono, sempre com confirmação, e o gesto de **swipe-to-reveal** no mobile com alternativa
  acessível.
