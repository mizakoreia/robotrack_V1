## Why

A ESPECIFICACAO.md §4.1 (linha 2 da matriz) diz, literalmente: *"criar/editar/excluir
projeto, célula, robô, tarefa — `owner`, `edit`"*. O porte codificou essa linha como dado
em `PermissionMatrix::ACTIONS[:manage_commissioning] = %i[owner edit]`, e as quatro
policies de hierarquia (`ProjectPolicy`, `CellPolicy`, `RobotPolicy`, `TaskPolicy`)
mapeiam `create?`, `update?` **e `destroy?`** para essa mesma action. Consequência atual,
verificada no código: **um membro `edit` pode arquivar um projeto inteiro** — e com ele a
subárvore de células, robôs, tarefas e o progresso que dependia delas.

O dono do produto decidiu que essa é a granularidade errada para o contexto real de uso.
O usuário-alvo (PRODUCT.md) é o engenheiro de comissionamento no chão de fábrica, celular
na mão, às vezes de luva, sob luz forte de galpão. Nesse ambiente, **criar e editar são
gestos de rotina; excluir é irreversível na percepção do usuário e raro na prática**. Dar
os dois ao mesmo papel significa que um toque errado num alvo de 32px apaga o trabalho
coletivo de uma célula — e o produto hoje **não tem tela de restauração**: um nó arquivado
some da hierarquia, do cálculo de progresso e do relatório, sem caminho de volta pela UI.

A assimetria de dano justifica a assimetria de papel. Editar errado se corrige editando de
novo, e a trilha de avanços é imutável (`progress-advances` D-IMUT) — o histórico sobrevive.
Excluir errado, no estado atual do produto, **exige um agente com acesso ao banco** para
desfazer. Concentrar a exclusão no dono é a resposta mais barata, e é exatamente o desenho
que a própria §4.1 já usa para as outras duas operações de dano alto e frequência baixa:
gestão de membros (L7) e destruição/reset do workspace (L8), ambas `owner`-only.

Esta change é, portanto, uma **divergência deliberada e registrada da §4.1 L2**. Não é
correção de bug: o comportamento atual implementa a spec legada corretamente. É uma decisão
de produto que endurece o legado — na mesma família dos endurecimentos que
`authorization-policies` já registrou em `config/authorization/legacy_parity.yml` (ex.: a
divergência D-A das notificações). A entrada `L42 — projects allow write` daquele arquivo
deixa de ser `covered_by` e passa a carregar um `divergence` explícito.

Traduzindo o legado: no `firestore.rules` a regra era `allow write: if isMember(wsId)`
— um único verbo `write` cobrindo create/update/delete, sem meio de separá-los sem
duplicar a rule. O porte já separou os verbos por construção (policy por predicado); esta
change usa essa separação, que o Firestore não oferecia de graça.

## What Changes

- **Nona linha na matriz**: nova action `destroy_commissioning: %i[owner]` em
  `PermissionMatrix::ACTIONS`. A linha 2 da §4.1 passa a ser representada por **duas**
  actions — `manage_commissioning` (criar/editar, `owner`+`edit`) e `destroy_commissioning`
  (excluir, `owner`) — porque o porte diverge da spec legada exatamente nesse ponto. A
  matriz continua sendo a **única** origem de decisão de papel: nenhuma policy ganha `if`.
- **Quatro policies remapeadas**: `ProjectPolicy#destroy?`, `CellPolicy#destroy?`,
  `RobotPolicy#destroy?` e `TaskPolicy#destroy?` passam a apontar para
  `destroy_commissioning`. `create?`, `update?`, `reorder?` e `assign?` **não mudam** — o
  editor perde só a exclusão.
- **A invariante passa a morar no banco**: novo gatilho `hierarchy_archive_owner_only()`,
  `BEFORE UPDATE` em `projects`, `cells`, `robots` e `tasks`, que dispara **apenas na
  transição de arquivamento** (`OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL`) e
  levanta exceção quando `current_setting('app.current_user_id')` não é o
  `workspaces.owner_user_id` do tenant corrente. Renomear, reordenar e registrar avanço
  continuam intocados pelo gatilho. Uma válvula nomeada
  (`app.hierarchy_archive_bypass = 'on'`, mesmo idioma do `app.invitation_purge` já
  existente) libera os caminhos de manutenção que não têm usuário HTTP (seed, restauração
  de backup, `Legacy::*` dormente).
- **Negação é 403, não 404**: o editor **é** membro do workspace, então a negação é
  `Authorization::Forbidden` (403). O 404 continua reservado ao endereçamento cross-tenant
  e ao não-membro, como manda a regra da casa. `BasePolicy#authorize!` já faz essa
  distinção — esta change apenas a exercita num caso novo e a prova em spec.
- **UI deixa de oferecer o que não pode**: o `IconButton` "Excluir <célula>" da
  `ProjectPage` e a ação "Excluir" do `AcoesCell` (tabela de tarefas do robô) passam a
  renderizar **somente para o dono**. Bloqueio de UI é conveniência (§4.1 inv. 1); o
  servidor continua sendo a autoridade, e há cenário provando isso.
- **Conformidade atualizada no mesmo empurrão**: `permission_matrix_spec.rb` (reafirmação
  literal, agora de 9 linhas), `matrix_conformance_spec.rb` (a grade vira 3 papéis × 9
  actions = 27 células), e a entrada `L42 — projects allow write` de
  `config/authorization/legacy_parity.yml` migra de `covered_by` para `divergence`.

### Não-objetivos

- **Não muda o catálogo.** Excluir pessoa do catálogo (`PersonPolicy#destroy?`) e excluir
  modelo de tarefa (`TaskTemplatePolicy#destroy?`) continuam em `manage_catalog`
  (`owner`+`edit`). Decisão explícita do dono nesta rodada: o escopo é **a hierarquia**.
  Registrado aqui para que um leitor futuro saiba que foi decidido, não esquecido.
- **Não muda o que já é do dono.** Gestão de membros, convites, arquivar workspace,
  destruir workspace e reset de fábrica já eram `owner`-only e não são tocados.
- **Não cria tela de restauração.** O arquivamento continua sem caminho de volta pela UI.
  Esta change **aumenta** o valor de uma restauração futura (o editor agora depende do
  dono), e isso fica anotado como questão em aberto Q1 — mas construí-la é outra change.
- **Não transforma exclusão em pedido de aprovação.** Nenhum fluxo de "editor solicita, dono
  confirma": seria uma capacidade nova (fila, notificação, estado pendente), não uma
  mudança de matriz. Se o atrito no campo se provar alto, é a evolução natural — não o
  ponto de partida.
- **Não altera o contrato HTTP do endpoint de exclusão.** Continua `DELETE` → `204` para
  quem pode. Só o conjunto de quem pode muda.
- **Não mexe em soft vs. hard delete.** A exclusão continua sendo o soft-delete de
  `hierarchy-soft-delete`; esta change só decide **quem** pode disparar o arquivamento.
- **Não afrouxa nada.** Nenhum papel ganha permissão; um papel perde uma.

### Impact

- **Backend — autorização**: `app/policies/permission_matrix.rb` (nona action),
  `project_policy.rb`, `cell_policy.rb`, `robot_policy.rb`, `task_policy.rb` (mapeamento de
  `destroy?`). Nenhuma rota nova, nenhum `route_setting` novo — o `route_sweep_spec`
  continua verde sem tocar na allowlist.
- **Backend — banco**: uma migration **aditiva e reversível** (`CREATE FUNCTION` + quatro
  `CREATE TRIGGER`; o `down` derruba os quatro e a função). Não apaga dado, não altera
  coluna, não reescreve tabela — logo **não exige tarefa de backup antes** (regra de
  `tasks` da casa). `db/structure.sql` regenerado.
- **Backend — suítes de conformidade**: `spec/policies/permission_matrix_spec.rb`,
  `spec/authorization/matrix_conformance_spec.rb`, `spec/policies/resource_policies_spec.rb`,
  `config/authorization/legacy_parity.yml`. O `role_comparison_guard_spec` continua verde
  por construção (nenhum `role ==` novo fora da matriz).
- **Frontend**: `app/pages/ProjectPage.tsx` (controle de excluir célula),
  `features/robot-tasks/AcoesCell.tsx` (ação de excluir tarefa). O rótulo de papel já está
  disponível (`workspaceStore.currentRoleLabel`, hoje consumido em `AppShell.tsx:249` como
  `canManage`); esta change acrescenta um predicado irmão para "pode excluir".
- **Dependências consumidas, não modificadas**: `authorization-policies` (matriz,
  `BasePolicy`, contexto, varreduras), `hierarchy-soft-delete` (`SoftDeleteService`,
  `deleted_at`), `workspace-tenancy` (`app.current_user_id`/`app.current_workspace_id` via
  `SET LOCAL`, RLS forçada), `workspace-settings` (reset de fábrica, que já é do dono e
  precisa continuar passando pelo gatilho — verificação explícita em tarefa).
- **BREAKING para o papel `edit`**: é uma remoção de capacidade, visível em produção. Quem
  hoje é editor e apagava passa a receber 403 e a não ver o botão. É o objetivo da change,
  mas precisa aparecer no resumo ao cliente e na `CONTINUIDADE.md`.
- **Sem impacto em dado existente**: nada é migrado, nada é reclassificado. Nós já
  arquivados continuam arquivados.

## Capabilities

### New Capabilities

- `owner-only-deletion`: exclusão de projeto, célula, robô e tarefa restrita ao dono do
  workspace, expressa como linha própria da matriz de permissões (`destroy_commissioning`),
  aplicada nas quatro policies de hierarquia, **reforçada por gatilho de banco** na
  transição de arquivamento (com válvula nomeada para manutenção), negando com 403 para
  membro sem papel e preservando 404 para cross-tenant; papel `edit` mantém criar, editar,
  reordenar, atribuir e registrar avanço; UI oculta os controles de exclusão para quem não
  é dono, sem que isso vire a autoridade.

### Modified Capabilities

Nenhuma via delta de spec (padrão do repositório: todos os deltas anteriores são `ADDED`).
Duas afirmações de artefatos existentes deixam de ser verdadeiras e são reconciliadas no
`EXECUCAO.md`, não em silêncio:

1. `authorization-policies` afirma "a matriz §4.1 codificada como dado: **8** linhas".
   Passa a ter 9, e a nona é a divergência desta change (decisão DE-G0.1).
2. `config/authorization/legacy_parity.yml`, entrada `L42 — projects allow write`, hoje
   `covered_by: manage_commissioning`. Passa a `divergence` (decisão DE-G0.2).
