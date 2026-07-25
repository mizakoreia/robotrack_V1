## Context

A maquinaria toda já existe. O trabalho de design **não é** "como autorizar" — é **onde a
linha nova mora** e **como o banco a segura**. Peças reais verificadas no repositório antes
de decidir qualquer coisa:

| Peça (caminho real) | O que é hoje | Como esta change a usa |
|---|---|---|
| `app/policies/permission_matrix.rb` | 8 actions congeladas, uma por linha da §4.1; `allows?` levanta `KeyError` em action desconhecida | Ganha a **9ª** action `destroy_commissioning` |
| `app/policies/base_policy.rb` | `permits` mapeia predicado → action; `authorize!` levanta `NotFound` para não-membro (404) e `Forbidden` para membro sem papel (403); predicado não declarado = `NoMethodError` | Consumido como está — só muda o alvo de `destroy?` |
| `project/cell/robot/task_policy.rb` | `destroy?: :manage_commissioning` | Passam a `destroy?: :destroy_commissioning` |
| `app/services/hierarchy/crud_service.rb#destroy` | Audita, captura o pai, chama `SoftDeleteService`, recomputa, devolve 204 | **Não muda.** O gate já é anterior a ele (`before` do Grape) |
| `app/services/hierarchy/soft_delete_service.rb` | Arquiva a subárvore de baixo para cima com um `UPDATE` por nível (`deleted_at`, `position=NULL`, sem bump de `lock_version`) | É exatamente o `UPDATE` que o gatilho novo intercepta |
| `app/lib/tenant.rb` | `SET LOCAL` de `app.current_workspace_id` **e `app.current_user_id`** dentro da transação do request | É a fonte que o gatilho lê para saber quem está agindo |
| `db/structure.sql` — `memberships_owner_is_not_member()` | Gatilho que faz `SELECT owner_user_id FROM workspaces WHERE id = NEW.workspace_id` e levanta | **Precedente direto** do gatilho novo: mesma consulta, mesma forma |
| `db/structure.sql` — `POLICY purge_expired ON invitations` | Usa `current_setting('app.invitation_purge', true) = 'on'` como válvula nomeada | **Precedente direto** da válvula de manutenção |
| `spec/authorization/role_comparison_guard_spec.rb` | Reprova `role ==` em qualquer arquivo de `app/` fora da matriz | Motivo pelo qual a solução **não pode** ser um `if` na policy |
| `spec/authorization/legacy_parity_spec.rb` + `config/authorization/legacy_parity.yml` | 22 entradas, cada uma com `covered_by` OU `divergence` | O lugar canônico onde esta divergência fica registrada |
| `app/AppShell.tsx:249` — `const canManage = role === 'owner' \|\| role === 'edit'` | Rótulo de papel no cliente | Ganha um irmão para "pode excluir"; segue sendo rótulo, não autoridade |

Decisão de produto herdada e não reaberta nesta change: **escopo é a hierarquia**
(projeto/célula/robô/tarefa). Catálogo fica fora — escolha explícita do dono nesta rodada.

## Decisões

### D1 — Uma nona action na matriz, não um `if` na policy

**Decisão.** Criar `destroy_commissioning: %i[owner]` como linha própria de
`PermissionMatrix::ACTIONS`, e remapear os quatro `destroy?` para ela.

**Alternativa descartada — `if context.role == :owner` dentro de `ProjectPolicy#destroy?`.**
Reprovada mecanicamente: `role_comparison_guard_spec.rb` falha o CI em qualquer `role ==`
fora de `permission_matrix.rb`. E a guarda está certa — a matriz existe para que a
resposta a "quem pode o quê" seja legível num arquivo só. Espalhar a decisão por quatro
policies reconstrói exatamente o problema que `authorization-policies` foi escrita para
matar.

**Alternativa descartada — reusar `destroy_workspace` (que já é `%i[owner]`).** Daria o
comportamento certo pelo motivo errado. `destroy_workspace` é a L8 da §4.1 ("excluir
workspace / reset de fábrica"); pendurar a exclusão de uma tarefa nela faria a matriz
mentir, e uma mudança futura na política de destruição de workspace alteraria em silêncio
quem pode apagar uma célula. Duas regras diferentes não compartilham uma linha.

**Alternativa descartada — `manage_commissioning: %i[owner]`, tirando o `edit` da linha
inteira.** Tiraria também criar e editar do editor, que é o oposto do pedido.

**Onde a invariante mora:** `PermissionMatrix::ACTIONS` (dado congelado) + `BasePolicy`
(decisão) + gatilho de banco (D2). O `KeyError` em action desconhecida garante que um typo
no remapeamento explode no primeiro teste, nunca vira negação silenciosa.

### D2 — A invariante mora também no banco: gatilho na transição de arquivamento

**Decisão.** `CREATE FUNCTION hierarchy_archive_owner_only()`, ligada como `BEFORE UPDATE`
em `projects`, `cells`, `robots` e `tasks`. Corpo, em prosa:

1. Se **não** é a transição de arquivamento (`OLD.deleted_at IS NOT NULL` ou
   `NEW.deleted_at IS NULL`), retorna `NEW` sem olhar mais nada.
2. Se a válvula `current_setting('app.hierarchy_archive_bypass', true) = 'on'` está ligada,
   retorna `NEW`.
3. Caso contrário, compara `NULLIF(current_setting('app.current_user_id', true), '')::uuid`
   com o `owner_user_id` do workspace da linha. Diferente ou nulo → `RAISE EXCEPTION`
   nomeando a regra.

**Por quê.** É a regra da casa, escrita em `CLAUDE.md`: *"invariantes moram no banco
(trigger/CHECK/índice)"* e *"um model pode ser contornado por um console; uma constraint
não."* A policy protege a porta HTTP; o gatilho protege tudo o mais — um service novo que
chame `update_all` direto, um job, um `rails console`. Sem ele, esta change seria uma
convenção que a próxima capacidade esquece.

**Alternativa descartada — política RLS com `WITH CHECK`.** RLS avalia a linha resultante,
não a *transição*: expressar "só o dono pode passar `deleted_at` de nulo para não-nulo"
exigiria uma `USING` que também restringiria updates legítimos de nome e posição feitos por
editores, ou uma expressão contorcida difícil de auditar. Além disso a violação vira uma
mensagem genérica de RLS, enquanto o gatilho levanta com o texto da regra — que é o que
aparece no teste que falha daqui a um ano. Precedente da casa: `workspaces_owner_immutable`
é gatilho, não RLS, pela mesma razão (é uma regra de transição).

**Alternativa descartada — `REVOKE UPDATE` na coluna.** `deleted_at` não pode ser revogada
para `robotrack_app` porque é justamente a app que arquiva; e Postgres não tem "revoke
condicional por identidade".

**Onde a invariante mora:** gatilho `hierarchy_archive_owner_only` nas quatro tabelas.
Migration aditiva e reversível.

### D3 — A válvula é nomeada e explícita, e a ausência de usuário NEGA

**Decisão.** Sem `app.current_user_id` e sem a válvula, o gatilho **levanta**. Caminhos
legítimos sem usuário HTTP ligam `SET LOCAL app.hierarchy_archive_bypass = 'on'`
deliberadamente.

**Por quê.** O modo de falha barato seria "contexto vazio → deixa passar", e ele destrói a
proteção: todo script, job e console cai nesse ramo. Fail-closed é a postura já adotada em
todo lugar nesta base (`BasePolicy` sem predicado default, `allows?` com `KeyError`, rota
sem `route_setting` que levanta). A válvula ser um nome literal — e não a mera ausência de
contexto — significa que quem a usa **escreveu que a estava usando**, e o `grep` encontra
todos os pontos.

**Quem precisa da válvula, verificado:** `db/seeds` (constrói e reconstrói cenários),
restauração de `workspace_backups`, e o `Legacy::*` (dormente — `legacy_rollback`). O
**reset de fábrica NÃO precisa**: é endpoint HTTP com
`WorkspaceFactoryResetPolicy → destroy_workspace` (dono), rodando dentro da transação de
tenant que já emitiu o `SET LOCAL app.current_user_id` do dono — passa pelo ramo 3
naturalmente. Isso é afirmação de comportamento, não suposição, e vira **tarefa de
verificação explícita** (G2.4).

**Onde a invariante mora:** no próprio corpo do gatilho (ramo 2), com o nome
`app.hierarchy_archive_bypass` espelhando o `app.invitation_purge` já existente.

### D4 — 403 para o editor, 404 continua sendo só cross-tenant

**Decisão.** Editor que tenta excluir recebe **403**. O 404 permanece reservado a
não-membro e a endereçamento de recurso de outro tenant.

**Por quê.** A regra da casa diz *"vazamento cross-tenant responde 404, nunca 403"* — e o
valor dela vem de o 403 **significar** alguma coisa: "existe, você é membro, seu papel não
alcança". Se a negação por papel também virasse 404, o cliente perderia a distinção entre
"não existe para você" e "você não pode", e a UI não teria como dizer ao editor por que o
botão sumiu. `BasePolicy#authorize!` já implementa exatamente isso (`NotFound` quando
`!context.member?`, `Forbidden` depois) — a change não altera a mecânica, só a exercita num
caso novo e a prende com cenários.

**Alternativa descartada — 404 para tudo que é negado.** Mais opaco sem ganho: o editor já
sabe que o recurso existe (ele o está vendo na tela).

### D5 — A UI esconde o controle; não o mostra desabilitado

**Decisão.** Os controles de exclusão (`IconButton` "Excluir <célula>" na `ProjectPage`;
ação "Excluir" no `AcoesCell` da tabela de tarefas) **não renderizam** para quem não é dono.

**Alternativa descartada — renderizar desabilitado com tooltip.** Três razões concretas:
(a) botão desabilitado não recebe foco e não é anunciado por leitor de tela, então o
"porquê" não chega a quem depende de teclado — piora a a11y que `quality-and-accessibility`
mediu; (b) num alvo de 32px usado de luva, um controle que existe e não funciona é ruído
puro no gesto; (c) DESIGN.md é explícito que o produto não decora — um controle que nunca
executa é decoração.

**Alternativa descartada — deixar o botão e tratar o 403 com toast.** Ensina o usuário
errado: ele descobre o limite falhando, repetidamente, num fluxo destrutivo.

**Onde a invariante mora:** em lugar nenhum — e isso é o ponto. A UI é conveniência (§4.1
inv. 1). O rótulo de papel do cliente (`workspaceStore.currentRoleLabel`) está anotado no
próprio código como *"rótulo, não autoridade"*. Há cenário de spec provando que o servidor
nega mesmo quando o cliente é contornado.

### D6 — Tentativa negada não escreve em `audit_logs`

**Decisão.** Uma exclusão negada não gera linha em `audit_logs`. Ela aparece no log
estruturado da aplicação (o mesmo caminho de qualquer 403).

**Por quê.** `audit_logs` é append-only e narra **mutações que aconteceram** (§4.1 inv. 3);
poluí-lo com tentativas frustradas mudaria a natureza do artefato — o relatório e a tela de
histórico passariam a mostrar eventos que não alteraram nada. Registrado como decisão para
que a ausência não pareça esquecimento.

**Alternativa descartada — auditar a negação.** Legítima como capacidade de segurança, mas
é outra coisa (trilha de acesso, não trilha de mudança), e teria de resolver retenção e
volume. Fora de escopo.

### D7 — Escopo: hierarquia sim, catálogo não

**Decisão do dono, nesta rodada:** `destroy_commissioning` cobre projeto, célula, robô e
tarefa. `PersonPolicy#destroy?` e `TaskTemplatePolicy#destroy?` continuam em
`manage_catalog` (`owner`+`edit`).

**Por quê registrar.** Sem esta anotação, o próximo leitor encontra um catálogo onde o
editor ainda apaga e conclui que a change ficou incompleta. Ficou **decidida**. A assimetria
tem lógica: excluir um modelo de tarefa ou uma pessoa do catálogo não derruba uma subárvore
de progresso; o dano é local e o desfazer é recriar o registro.

### D8 — A matriz deixa de ser cópia literal da §4.1, e o spec de reafirmação diz isso

**Decisão.** `permission_matrix_spec.rb` passa a reafirmar **9** linhas, e o comentário da
linha nova nomeia a divergência ("§4.1 L2 dividida: criar/editar `owner`+`edit`; excluir
`owner` — divergência `owner-only-deletion`"). `matrix_conformance_spec.rb` vai de 24 para
**27** células. A entrada `L42 — projects allow write` de `legacy_parity.yml` migra de
`covered_by` para `divergence`.

**Por quê.** O `legacy_parity_spec` exige que **toda** entrada tenha `covered_by` **ou**
`divergence` — o repositório já tem o mecanismo para tornar um endurecimento visível em vez
de deixá-lo sumir na tradução. Usar o mecanismo existente é mais barato e mais honesto do
que abrir exceção para ele.

## Questões em aberto

- **Q1 — Restauração.** Sem tela de restauração, o editor que precisa desfazer um
  arquivamento passa a depender do dono, e o dono depende de um agente com acesso ao banco.
  Esta change **aumenta** o valor de uma capacidade `hierarchy-restore` (lixeira com
  restauração, escopo do dono). Recomendação: próxima change, se o atrito aparecer.
  **Fora de escopo aqui.**
- **Q2 — Cópia de confirmação desatualizada.** Os diálogos dizem *"Esta ação não pode ser
  desfeita"* (`lib/i18n/hierarchy.ts`, `lib/i18n/robotTasks.ts`), mas desde
  `hierarchy-soft-delete` a exclusão é arquivamento — o dado permanece. A frase é
  defensável como verdade **do ponto de vista do usuário** (não há caminho de volta pela
  UI) e vira falsa no dia em que Q1 existir. Anotada, **não alterada** nesta change.
- **Q3 — Atrito de campo.** Se na prática o dono virar gargalo (uma pessoa só, no
  escritório, enquanto a equipe está no galpão), a evolução natural é exclusão solicitada
  pelo editor e confirmada pelo dono — capacidade nova, não ajuste de matriz. Medir antes
  de construir.
