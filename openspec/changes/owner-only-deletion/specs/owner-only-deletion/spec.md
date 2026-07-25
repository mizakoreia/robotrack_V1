## ADDED Requirements

### Requirement: Excluir nó da hierarquia é exclusivo do dono do workspace

O sistema SHALL restringir a exclusão de projeto, célula, robô e tarefa ao **dono** do
workspace. Um membro de papel `edit` MUST NOT conseguir excluir qualquer um desses quatro
recursos, e um membro de papel `view` tampouco. A negação por papel insuficiente SHALL
responder **403**, e o recurso SHALL permanecer intacto e visível na hierarquia após a
tentativa.

Personagens usados nos cenários, no mesmo elenco das suítes de autorização existentes:
**Ana** é a dona do workspace `ACME`; **Bruno** é membro `edit`; **Clara** é membro `view`;
**Dinho** é membro `edit` de outro workspace, `RIVAL`.

#### Scenario: Editor não exclui célula

- **GIVEN** o workspace `ACME` com o projeto "Linha 300" contendo a célula "Solda A"
- **WHEN** Bruno (`edit`) envia `DELETE /api/v1/projects/{id_linha_300}/cells/{id_solda_a}`
- **THEN** a resposta SHALL ter status **403**
- **AND** a célula "Solda A" SHALL continuar com `deleted_at` nulo
- **AND** um `GET` das células de "Linha 300" por Bruno SHALL continuar listando "Solda A"

#### Scenario: Editor não exclui projeto

- **WHEN** Bruno (`edit`) envia `DELETE /api/v1/projects/{id_linha_300}`
- **THEN** a resposta SHALL ter status **403**
- **AND** o projeto e toda a sua subárvore SHALL continuar com `deleted_at` nulo

#### Scenario: Editor não exclui robô

- **WHEN** Bruno (`edit`) envia `DELETE /api/v1/cells/{id_solda_a}/robots/{id_robo_r1}`
- **THEN** a resposta SHALL ter status **403**
- **AND** o robô `R1` SHALL continuar com `deleted_at` nulo

#### Scenario: Editor não exclui tarefa

- **WHEN** Bruno (`edit`) envia `DELETE /api/v1/robots/{id_robo_r1}/tasks/{id_tarefa}`
- **THEN** a resposta SHALL ter status **403**
- **AND** a tarefa SHALL continuar com `deleted_at` nulo
- **AND** os `task_assignees` da tarefa SHALL permanecer

#### Scenario: Leitor não exclui nada da hierarquia

- **WHEN** Clara (`view`) envia `DELETE` para o projeto, a célula, o robô ou a tarefa
- **THEN** cada resposta SHALL ter status **403**

#### Scenario: A dona exclui e recebe o mesmo contrato de sempre

- **WHEN** Ana (dona) envia `DELETE /api/v1/projects/{id_linha_300}/cells/{id_solda_a}`
- **THEN** a resposta SHALL ter status **204** e corpo vazio
- **AND** a célula "Solda A" SHALL passar a ter `deleted_at` não nulo e `position` nula
- **AND** os robôs e tarefas sob "Solda A" SHALL ser arquivados na mesma transação
- **AND** o progresso ponderado do projeto "Linha 300" SHALL ser recomputado desconsiderando
  a subárvore arquivada

#### Scenario: Cross-tenant continua respondendo 404, nunca 403

- **WHEN** Dinho, membro `edit` do workspace `RIVAL`, envia
  `DELETE /api/v1/projects/{id_linha_300}/cells/{id_solda_a}` (recursos de `ACME`)
- **THEN** a resposta SHALL ter status **404**
- **AND** NÃO SHALL ter status 403 — a distinção entre "não existe para você" (não-membro,
  outro tenant) e "existe e você não pode" (membro sem papel) é obrigatória

### Requirement: O papel `edit` conserva criar, editar, reordenar, atribuir e registrar avanço

O sistema SHALL preservar integralmente as demais operações do papel `edit` sobre a
hierarquia. Esta capacidade MUST remover do `edit` **apenas** a exclusão; nenhuma outra
operação SHALL passar a exigir o dono.

#### Scenario: Editor cria célula e robô

- **WHEN** Bruno (`edit`) envia `POST` de uma célula "Solda B" em "Linha 300" e, em
  seguida, `POST` de um robô "R7" em "Solda B"
- **THEN** ambas as respostas SHALL ter status **201**

#### Scenario: Editor renomeia nó da hierarquia

- **WHEN** Bruno (`edit`) envia `PATCH` renomeando a célula "Solda A" para "Solda A1"
- **THEN** a resposta SHALL ter status **200**
- **AND** o gatilho de banco NÃO SHALL interferir, pois `deleted_at` não mudou

#### Scenario: Editor reordena e atribui

- **WHEN** Bruno (`edit`) envia o `PATCH` de reordenação das células de "Linha 300" e o
  `PATCH` que atribui um responsável a uma tarefa
- **THEN** ambas as respostas SHALL ter status **200**

#### Scenario: Editor registra avanço

- **WHEN** Bruno (`edit`) registra um avanço de `+10` numa tarefa do robô `R1`
- **THEN** a resposta SHALL indicar sucesso e o avanço SHALL constar da trilha imutável

### Requirement: A matriz de permissões codifica a exclusão como linha própria

A matriz `PermissionMatrix::ACTIONS` SHALL conter a action `destroy_commissioning`
permitida somente ao papel `owner`, distinta de `manage_commissioning` (que permanece
`owner` e `edit`) e distinta de `destroy_workspace`. As quatro policies de hierarquia
SHALL mapear `destroy?` para `destroy_commissioning`. Nenhum arquivo de `app/` fora de
`permission_matrix.rb` SHALL comparar papel diretamente.

#### Scenario: A linha nova permite só o dono

- **WHEN** `PermissionMatrix.allows?(:destroy_commissioning, papel)` é avaliado
- **THEN** SHALL retornar `true` para `:owner`
- **AND** SHALL retornar `false` para `:edit`, para `:view` e para `nil` (não-membro)

#### Scenario: A linha de criar/editar não regride

- **WHEN** `PermissionMatrix.allows?(:manage_commissioning, papel)` é avaliado
- **THEN** SHALL retornar `true` para `:owner` e `:edit`, e `false` para `:view` e `nil`

#### Scenario: As quatro policies apontam para a linha nova

- **WHEN** `ProjectPolicy.destroy?`, `CellPolicy.destroy?`, `RobotPolicy.destroy?` e
  `TaskPolicy.destroy?` são avaliadas com um contexto de papel `edit`
- **THEN** as quatro SHALL retornar `false`
- **AND** com um contexto de papel `owner` as quatro SHALL retornar `true`

#### Scenario: A decisão de papel continua concentrada na matriz

- **WHEN** a varredura que reprova comparação direta de papel percorre `app/`
- **THEN** ela SHALL encontrar comparação de papel apenas em `permission_matrix.rb`
- **AND** a suíte SHALL permanecer verde após esta capacidade

#### Scenario: Action inexistente continua explodindo

- **WHEN** `PermissionMatrix.allows?(:destroy_commissionning, :owner)` (com erro de
  digitação) é avaliado
- **THEN** SHALL levantar `KeyError`, nunca retornar `false` silenciosamente

### Requirement: O banco recusa o arquivamento disparado por quem não é dono

O sistema SHALL impedir, no nível do banco de dados, que a transição de arquivamento
(`deleted_at` de nulo para não nulo) em `projects`, `cells`, `robots` e `tasks` seja
executada por uma sessão cuja identidade corrente não é o `owner_user_id` do workspace. A
regra MUST valer inclusive para código que escreva direto no banco, sem passar pela camada
HTTP. A ausência de identidade na sessão SHALL **negar**, não permitir. Uma válvula
nomeada e explícita SHALL liberar os caminhos de manutenção sem usuário HTTP.

#### Scenario: UPDATE direto com identidade de editor é recusado

- **GIVEN** uma sessão com `app.current_workspace_id` de `ACME` e `app.current_user_id` de
  Bruno (`edit`)
- **WHEN** a sessão executa `UPDATE cells SET deleted_at = now() WHERE id = {id_solda_a}`
- **THEN** o banco SHALL levantar exceção nomeando a regra de exclusão exclusiva do dono
- **AND** a transação SHALL abortar sem alterar a linha

#### Scenario: O gatilho só olha a transição de arquivamento

- **GIVEN** a mesma sessão com identidade de Bruno (`edit`)
- **WHEN** a sessão executa `UPDATE cells SET name = 'Solda A1' WHERE id = {id_solda_a}`
- **THEN** o `UPDATE` SHALL ser bem-sucedido
- **AND** um `UPDATE` que zera `position` sem tocar em `deleted_at` SHALL igualmente ser
  bem-sucedido

#### Scenario: Rearquivar o que já está arquivado não é barrado pelo gatilho

- **GIVEN** a célula "Solda A" já com `deleted_at` não nulo
- **WHEN** uma sessão qualquer executa um `UPDATE` que mantém `deleted_at` não nulo
- **THEN** o gatilho NÃO SHALL levantar, pois não há transição de nulo para não nulo

#### Scenario: Sessão sem identidade é negada

- **GIVEN** uma sessão sem `app.current_user_id` definido e sem a válvula ligada
- **WHEN** a sessão tenta arquivar um robô
- **THEN** o banco SHALL levantar exceção — a ausência de identidade SHALL ser tratada como
  negação, nunca como permissão

#### Scenario: Válvula nomeada libera manutenção

- **GIVEN** uma sessão que executou `SET LOCAL app.hierarchy_archive_bypass = 'on'`
- **WHEN** a sessão arquiva um projeto
- **THEN** o `UPDATE` SHALL ser bem-sucedido
- **AND** a válvula SHALL morrer no fim da transação, não vazando para a sessão seguinte

#### Scenario: A dona arquiva sem obstáculo

- **GIVEN** uma sessão com `app.current_user_id` de Ana, dona de `ACME`
- **WHEN** a sessão arquiva a célula "Solda A"
- **THEN** o `UPDATE` SHALL ser bem-sucedido

#### Scenario: O reset de fábrica continua funcionando

- **GIVEN** Ana (dona) com a frase de confirmação correta e um `backup_id` válido
- **WHEN** Ana dispara o reset de fábrica do workspace
- **THEN** a operação SHALL concluir com sucesso
- **AND** a hierarquia SHALL ficar arquivada
- **AND** o gatilho NÃO SHALL bloquear a operação, pois a identidade corrente é a da dona

### Requirement: A interface não oferece exclusão a quem não pode executá-la

A interface SHALL ocultar os controles de exclusão de nó da hierarquia para usuários que
não são donos do workspace corrente. Os controles MUST NOT ser renderizados em estado
desabilitado. O bloqueio de interface SHALL ser tratado como conveniência: a autoridade
permanece no servidor, e o servidor SHALL negar mesmo quando a interface for contornada.

#### Scenario: Editor não vê o controle de excluir célula

- **WHEN** Bruno (`edit`) abre a tela do projeto "Linha 300"
- **THEN** a lista de células NÃO SHALL conter nenhum controle com nome acessível
  "Excluir Solda A"
- **AND** os controles de criar célula e renomear célula SHALL continuar presentes

#### Scenario: A dona vê o controle de excluir célula

- **WHEN** Ana (dona) abre a mesma tela
- **THEN** a lista de células SHALL conter o controle "Excluir Solda A"

#### Scenario: Editor não vê a ação de excluir tarefa

- **WHEN** Bruno (`edit`) abre a tabela de tarefas do robô `R1`
- **THEN** a coluna de ações NÃO SHALL oferecer "Excluir"
- **AND** SHALL continuar oferecendo a edição da descrição e o registro de avanço

#### Scenario: Leitor não vê nenhum dos dois controles

- **WHEN** Clara (`view`) abre a tela do projeto e a tabela de tarefas
- **THEN** nenhum controle de exclusão SHALL estar presente em qualquer das duas telas

#### Scenario: Contornar a interface não contorna a regra

- **WHEN** Bruno (`edit`) dispara a requisição de exclusão diretamente contra a API,
  ignorando a interface
- **THEN** a resposta SHALL ter status **403**
- **AND** o recurso SHALL permanecer não arquivado — comprovando que a ocultação do controle
  é conveniência e não a autoridade
