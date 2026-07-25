## ADDED Requirements

### Requirement: Action de matriz owner-only para excluir comissionamento

A `PermissionMatrix` SHALL declarar a action `destroy_commissioning` autorizada
**apenas para o papel `owner`**. O spec que reafirma a matriz literalmente
(`permission_matrix_spec.rb`) SHALL ser atualizado para incluir esta linha — mudar a matriz
exige mudar os dois lugares de propósito.

#### Scenario: Só o dono passa em destroy_commissioning

- **WHEN** `PermissionMatrix.allows?(:destroy_commissioning, role)` é consultado
- **THEN** SHALL retornar verdadeiro para `:owner`
- **AND** SHALL retornar falso para `:edit` e para `:view`

## MODIFIED Requirements

### Requirement: Autorização de exclusão de projeto, célula e robô

Excluir (`destroy?`) um projeto, uma célula ou um robô SHALL ser autorizado **apenas ao
dono do workspace** (papel `owner`). `ProjectPolicy`, `CellPolicy` e `RobotPolicy` SHALL
mapear `destroy?` para a action `destroy_commissioning` (owner-only). Criar (`create?`),
editar (`update?`) e reordenar (`reorder?`) SHALL permanecer autorizados a `owner` e `edit`.
O servidor SHALL ser a autoridade: um pedido de exclusão de um membro `edit` SHALL falhar
mesmo que a UI o tivesse exposto.

#### Scenario: Dono exclui projeto/célula/robô

- **WHEN** o dono faz `DELETE /api/v1/{projects,cells,robots}/:id` de um recurso do próprio
  workspace
- **THEN** a exclusão SHALL prosseguir (soft-delete) e responder 204

#### Scenario: Membro edit NÃO exclui (negação)

- **WHEN** um membro com papel `edit` faz `DELETE /api/v1/{projects,cells,robots}/:id`
- **THEN** a aplicação SHALL responder 403 (Forbidden)
- **AND** nenhum `deleted_at` SHALL ser gravado

#### Scenario: Membro view NÃO exclui (negação)

- **WHEN** um membro com papel `view` faz `DELETE /api/v1/{projects,cells,robots}/:id`
- **THEN** a aplicação SHALL responder 403 (Forbidden)

#### Scenario: Membro edit ainda cria, edita e reordena

- **WHEN** um membro `edit` faz `POST`/`PATCH`/reorder de projeto/célula/robô
- **THEN** as operações SHALL continuar autorizadas (owner+edit), inalteradas por esta change

#### Scenario: Exclusão cross-tenant não vaza (negação)

- **WHEN** o dono de um workspace tenta `DELETE` de um recurso de OUTRO workspace ao qual
  não pertence
- **THEN** a aplicação SHALL responder 404 (indistinguível de id inexistente), nunca 403
- **AND** nada do outro tenant SHALL ser exposto

#### Scenario: O reset de fábrica é independente desta mudança

- **WHEN** a autorização do reset de fábrica (`destroy_workspace`) é avaliada
- **THEN** SHALL permanecer owner-only e inalterada por esta change
