## Context

Estado REAL levantado no planejamento (paths verificados):

- **Matriz §4.1 como dado:** `backend/app/policies/permission_matrix.rb` — `manage_commissioning:
  %i[owner edit]` cobre create/update/**destroy** de projeto/célula/robô. Não há linha de
  destroy própria; a única destroy owner-only é `destroy_workspace: %i[owner]` (reset de
  fábrica).
- **Papel resolvido no servidor:** `Authorization::Context#resolve_role` retorna `:owner` se
  `workspace.owner_user_id == user.id`, senão o papel da membership. `owner` é papel
  **distinto** (nunca vira linha de membership — trigger de banco garante); ganha poder de
  edit porque a matriz o lista junto de `edit`, não por herança. `owner` só é resolvido aqui,
  no servidor.
- **Policies:** `BasePolicy#permits` mapeia cada predicado a UMA action da matriz;
  `ProjectPolicy`/`CellPolicy`/`RobotPolicy` declaram `destroy?: :manage_commissioning`.
- **Soft-delete:** `CrudService#destroy` → `SoftDeleteService.call` (arquiva a subárvore
  bottom-up, `deleted_at`/`position: nil`, remove `task_assignees`) → 204. A autorização
  acontece ANTES, no gate.
- **Frontend gating:** em TODA tela é `canEdit = role === 'owner' || role === 'edit'`
  (`ProjectPage:27`, `CellPage:29`, `OverviewPage:34`, `RobotTaskTablePage:46`, etc.). O dono
  passa em todos. Não há gating por `edit` sozinho.
- **UI de excluir hoje:** só nos cards de **célula** (`ProjectPage.tsx:83–93`, `IconButton`
  trash → `DeleteCellDialog`, um `Modal`). `useDeleteCell` é usado; `useDeleteProject`
  (`useHierarchy.ts:125`) está órfão; `useDeleteRobot` **não existe**. `deleteProject`/
  `deleteRobot` existem no client (`endpoints.ts:344,376`) — `deleteRobot` é código morto.
- **Mobile hoje:** `OverviewPage`/`ProjectPage`/`CellPage` usam grid CSS puro
  (`sm:grid-cols-2 lg:grid-cols-3`, 1 coluna < 640px), sem `useMediaQuery`. Só o
  `RobotTaskTablePage` troca de layout (tabela↔cartões) via `useMediaQuery('(min-width:768px)')`.
  **Não há motor de gesto/pointer reutilizável** — o "drag & drop" de reorder é só
  `moveItem`/`useReorder(onDrop(from,to))` na camada de dados, nunca ligado a alça de arraste;
  os únicos pointer events são o range nativo do slider e o `pointerdown` de outside-click dos
  portais. **Não há swipe-to-delete.**
- **DESIGN.md:** `EntityCard` inteiro clicável (`role=button` + `aria-label="Abrir X"`),
  controles internos não disparam navegação (`fromInnerControl` via `closest(INNER_CONTROL)`);
  `prefers-reduced-motion` **zera** transições (globals.css força ~0ms); ease-out, sem
  bounce/elastic; z-scale semântica (tokens, nunca `9999`); alvo de toque ≥32px
  (`IconButton`), piso mobile de 40px (precedente `AcoesCell`); cor de status semântica
  (`danger`).

## Decisões

### D1 — Owner-only por nova action de matriz, não por `role ==` na policy.

Adicionar `destroy_commissioning: %i[owner]` à `PermissionMatrix` e repontar os três
`destroy?` para ela. `create?`/`update?`/`reorder?` continuam em `manage_commissioning`.

**Por quê:** a matriz é a fonte única (D3.2 de `authorization-policies`), e há um cop que
reprova `role ==` fora de `permission_matrix.rb`. A máquina de owner-only já é provada
(`destroy_workspace`, `manage_membership`). O `Context` já resolve `owner`. Custo: uma linha
na matriz + repontar 3 policies + atualizar o `permission_matrix_spec.rb` (que reafirma a
matriz **literalmente** — "mudar a matriz exige mudar dois lugares de propósito", por design).

**Alternativa descartada:** comparar papel na policy (`context.role == :owner`) — proibido
pelo cop e quebra a fonte-única.

### D2 — Consequência explícita: `edit` perde excluir, mantém o resto.

Depois desta change, um membro `edit` **não** exclui projeto/célula/robô (403 no servidor,
controle ausente na UI) — continua criando, editando e reordenando. `view` segue sem excluir.
Isso é o pedido do dono. **Não afeta:**

- o **reset de fábrica** (já owner-only via `destroy_workspace`);
- o **soft-delete** em si (o serviço e o 204 são iguais; só o gate muda);
- excluir **tarefa** no `robot-task-table` (`AcoesCell`/`useDeleteTask`) — **decisão aberta
  DA-1:** o dono disse "cards" (projeto/célula/robô); tarefa é outra granularidade. Recomendo
  **manter tarefa em owner+edit** (o operador de chão de fábrica mexe em tarefa o tempo todo;
  travar em owner atrapalharia o fluxo diário) e restringir só os cards de hierarquia. Confirmar.

### D3 — Fechar a lacuna de UI nos três níveis, reusando o padrão que já funciona.

`DeleteCellDialog` (confirm `Modal` + `Button` destructive) é o padrão. Replicar para:

- **Projeto** (`OverviewPage`/`ProjectCard`): `IconButton` trash → `DeleteProjectDialog` →
  `useDeleteProject` (já existe). Invalidar `qk.overview`/`projects`.
- **Robô** (`CellPage`): `IconButton` trash → `DeleteRobotDialog` → **novo** `useDeleteRobot`
  (fiar `deleteRobot` do client; invalidar `robots(wsId, cellId)`, espelhando `useCreateRobot`).
- **Célula** (`ProjectPage`): já existe; só re-gated para owner-only.

Excluir é destrutivo → **sempre** passa pelo diálogo de confirmação, nomeando o alvo. O texto
deve avisar que arquiva a subárvore (célula/robô com filhos) — o soft-delete cascateia.

**Alternativa descartada:** um controle de excluir dentro do próprio `EntityCard` (prop
`onDelete`) em vez de via `footer`. Mais encapsulado, mas o `EntityCard` é hoje presentacional
puro e os três grids passam ações pelo `footer`; manter a convenção reduz raio de mudança. O
swipe (D4), esse sim, vive no `EntityCard` porque é comportamento do card.

### D4 — Swipe-to-reveal no `EntityCard`, pointer nativo, dentro dos tokens.

O gesto vive no `EntityCard` (assim os três grids herdam) e é implementado com **pointer
events nativos** + `transform: translateX` (não anima layout), revelando um painel de ação
**Excluir** (`danger`) atrás do card. Regras duras (DESIGN.md):

- **Alvo de toque ≥ 40px** na ação revelada (piso mobile da casa).
- **`prefers-reduced-motion`:** sem animação — o painel aparece/desaparece instantâneo; **não
  há bounce/elastic** em nenhum caso (só ease-out).
- **`touch-pan-y`:** arrastar na vertical **rola a página**; só o gesto predominantemente
  **horizontal** (além de um limiar) move o card — espelha o cuidado do slider de avanço.
- **Não brigar com a navegação:** o card é `role=button` (Abrir X); o swipe precisa distinguir
  "tap para abrir" de "arrasto para revelar" por deslocamento/limiar, e o toque na ação
  revelada não pode disparar a navegação (mesma ideia do `fromInnerControl`).
- **z-index:** o painel revelado usa token semântico (entre `--z-content` e `--z-dropdown`),
  nunca literal.
- **Só aparece no toque/estreito:** em desktop com mouse o `IconButton` basta; o swipe é
  progressive enhancement para dedo. Detecção por `useMediaQuery`/ponteiro grosso, sem trocar
  o layout do grid.

**Alternativa descartada:** biblioteca de swipe (`react-swipeable`/dnd-kit) — traria peso e um
motor externo para um gesto de uma ação; a casa evita deps novas (guarda de bundle). Pointer
nativo é suficiente e auditável.

### D5 — O swipe revela **só excluir**, sempre com confirmação. **RECOMENDADO.**

Excluir é a única ação destrutiva e a que o dono pediu. Revelar renomear/editar no mesmo gesto
multiplicaria a complexidade do gesto e o risco de toque acidental. Renomear/editar continuam
no `IconButton`. E como excluir é destrutivo, o swipe **nunca** exclui direto: ele revela o
botão, e o toque abre o **diálogo de confirmação**. (Confirmar em DA-2.)

### D6 — Acessibilidade: o gesto NUNCA é o único caminho.

O `IconButton` visível de excluir (foco, Enter/Espaço, rótulo para leitor de tela) permanece em
todos os cards para o dono. Swipe é atalho de toque. Assim teclado e leitor de tela têm o mesmo
poder que o dedo — requisito de `PRODUCT.md`/WCAG e do gate `quality-and-accessibility`.

## Decisões em aberto (para o dono)

- **DA-1 — Excluir TAREFA também vira owner-only?** O dono disse "cards" (projeto/célula/robô).
  Tarefa (`AcoesCell`) é outra granularidade, usada no fluxo diário do operador. **Recomendo
  manter tarefa em owner+edit** e restringir só os cards de hierarquia. Confirmar.
- **DA-2 — Swipe revela só excluir, sempre com confirmação?** **Recomendo sim** (mínimo +
  seguro). Se o dono quiser mais ações no swipe, é escopo maior.
- **DA-3 — Cobrir os três níveis (projeto, célula, robô)?** **Recomendo sim** — consistência; é
  onde a lacuna de UI está (projeto e robô não têm botão hoje). Confirmar.

## Riscos / trade-offs

- **`edit` perde excluir** (D2) — mudança de contrato de papel; mitigado por specs de negação
  atualizados (edit→403) e pelo aviso ao dono.
- **Matriz literal** — esquecer de atualizar `permission_matrix_spec.rb` quebra o build (é o
  objetivo do design; a tarefa de verificação cobre).
- **Swipe × navegação do card** — o maior risco de UX; limiar/`touch-pan-y` e testes de gesto
  (RTL/pointer) mitigam. Sem limiar, um scroll viraria delete acidental.
- **Robô sem hook de delete hoje** — `useDeleteRobot` é novo; seguir o padrão de invalidação de
  `useDeleteCell`/`useCreateRobot` para não invalidar o tenant inteiro (regra de convenção).
- **Reduced-motion** — se o swipe animar `translateX` sem o guard, quem pediu menos movimento
  ganha animação; o CSS global já força ~0ms, mas o JS do gesto deve respeitar (sem inércia).
