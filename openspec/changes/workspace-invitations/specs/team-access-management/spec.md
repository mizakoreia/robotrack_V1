## ADDED Requirements

### Requirement: Painel de equipe

O sistema SHALL exibir, na tela de Configurações (§3.10), um painel de equipe com
duas listas: membros atuais (nome, e-mail, papel) e convites pendentes (e-mail,
papel, expiração). Os controles de mutação SHALL ser visíveis apenas para o papel
`owner`; a ocultação é conveniência de UI e SHALL NOT ser a fonte de autorização
(invariante 1).

#### Scenario: Dono vê listas e controles

- **WHEN** o dono de `WS-A` abre o painel de equipe de um workspace com 3 membros e
  2 convites pendentes
- **THEN** o sistema SHALL exibir as duas listas e, em cada linha, os controles de
  mudança de papel e remoção (membros) ou revogação (convites)

#### Scenario: Membro edit vê as listas sem controles

- **WHEN** um membro `edit` de `WS-A` abre o painel de equipe
- **THEN** o sistema SHALL exibir as duas listas em modo leitura e SHALL NOT
  renderizar botões de mudar papel, remover ou revogar

#### Scenario: Membro view chamando a API de mutação diretamente

- **WHEN** um membro `view` chama `PATCH /api/v1/memberships/:id` com
  `{ role: "edit" }` contornando a UI
- **THEN** o sistema SHALL responder `403` com código `forbidden` e o papel SHALL
  permanecer inalterado

#### Scenario: Convite pendente expirado é distinguido na lista

- **WHEN** um convite tem `expires_at` no passado e ainda não foi expurgado
- **THEN** a linha SHALL ser rotulada como "Expirado" e SHALL NOT ser apresentada
  como pendente ativo

### Requirement: Cópia do link de convite

O sistema SHALL, ao criar um convite, exibir o link absoluto
`<APP_URL>/convite/<token>` com um controle de cópia para a área de transferência, e
SHALL confirmar visualmente a cópia.

#### Scenario: Link copiado com confirmação

- **WHEN** o dono cria um convite e aciona "Copiar link"
- **THEN** a área de transferência SHALL conter a URL absoluta iniciada por
  `<APP_URL>/convite/rt_inv_` e o sistema SHALL exibir confirmação de cópia

#### Scenario: Fallback quando a Clipboard API é negada

- **WHEN** o navegador nega acesso à área de transferência
- **THEN** o sistema SHALL exibir o link num campo de texto selecionável e SHALL
  instruir a cópia manual, sem falhar em silêncio

#### Scenario: Link não é reexibido depois de fechado

- **WHEN** o dono fecha o diálogo de criação e reabre a lista de convites pendentes
- **THEN** o sistema SHALL permitir recopiar o link daquele convite a partir da
  lista, já que o token continua sendo o mesmo valor persistido

### Requirement: Mudança de papel de membro

O sistema SHALL permitir que apenas o `owner` altere o papel de um membro, apenas
entre `view` e `edit`, e SHALL NOT permitir atribuir ou remover o papel `owner`
(invariante 5).

#### Scenario: Dono promove membro de view para edit

- **WHEN** o dono de `WS-A` altera o papel de um membro `view` para `edit`
- **THEN** o sistema SHALL responder `200`, a membership SHALL passar a `edit` e o
  cliente SHALL invalidar a chave `['ws', WS-A, 'members']`

#### Scenario: Promoção a owner é negada

- **WHEN** o dono de `WS-A` chama a mudança de papel com `role: "owner"`
- **THEN** o sistema SHALL responder `422` com código `invalid_role` e o papel SHALL
  permanecer inalterado

#### Scenario: Dono tentando rebaixar a si mesmo

- **WHEN** o dono de `WS-A` chama a mudança de papel sobre a própria membership com
  `role: "edit"`
- **THEN** o sistema SHALL responder `422` com código `owner_is_immutable`

#### Scenario: Membro edit tentando mudar papel de outro

- **WHEN** um membro `edit` de `WS-A` chama `PATCH /api/v1/memberships/:id`
- **THEN** o sistema SHALL responder `403` com código `forbidden`

#### Scenario: Membro de outro workspace é invisível

- **WHEN** o dono de `WS-A` chama a mudança de papel sobre uma membership de `WS-B`
- **THEN** o sistema SHALL responder `404` (não `403`), porque a RLS de D2 impede
  que a linha de `WS-B` seja sequer visível na conexão do request

### Requirement: Remoção de membro

O sistema SHALL permitir que apenas o `owner` remova membros, SHALL exigir
confirmação explícita na UI e SHALL NOT permitir a remoção do próprio dono.

#### Scenario: Dono remove membro edit

- **WHEN** o dono de `WS-A` confirma a remoção de um membro `edit`
- **THEN** a membership SHALL ser removida, o convite que a originou SHALL permanecer
  com `used_at` preenchido, e a `Person` SHALL permanecer no workspace com as
  atribuições históricas intactas

#### Scenario: Remoção do dono é negada

- **WHEN** o dono de `WS-A` chama a remoção da própria membership
- **THEN** o sistema SHALL responder `422` com código `cannot_remove_owner`, porque
  um workspace sem dono é irrecuperável

#### Scenario: Remoção não apaga a Person

- **WHEN** um membro com 12 tarefas atribuídas é removido
- **THEN** as 12 tarefas SHALL continuar apontando para a mesma `Person`, e a
  `Person` SHALL ter `user_id` limpo para `NULL`, voltando a ser um responsável sem
  conta

### Requirement: Revogação de convite pendente

O sistema SHALL permitir que apenas o `owner` revogue um convite com
`used_at IS NULL`, apagando a linha (`firestore.rules` L81), e SHALL recusar a
revogação de convite já consumido.

#### Scenario: Dono revoga convite pendente

- **WHEN** o dono de `WS-A` revoga um convite pendente para `ana@fabrica.com`
- **THEN** o sistema SHALL responder `204`, a linha SHALL ser removida e um aceite
  posterior daquele token SHALL responder `404 invitation_not_found`

#### Scenario: Convite consumido não é revogável

- **WHEN** o dono chama a revogação de um convite com `used_at` preenchido
- **THEN** o sistema SHALL responder `422` com código `invitation_already_used` e a
  orientação SHALL ser remover o membro correspondente

#### Scenario: Membro edit tentando revogar

- **WHEN** um membro `edit` de `WS-A` chama `DELETE /api/v1/invitations/:id`
- **THEN** o sistema SHALL responder `403` com código `forbidden` e o convite SHALL
  permanecer pendente

#### Scenario: Convite de outro workspace

- **WHEN** o dono de `WS-A` chama a revogação de um convite de `WS-B`
- **THEN** o sistema SHALL responder `404`, porque a RLS impede a visibilidade da
  linha

### Requirement: Revogação de acesso em tempo real

O sistema SHALL detectar, enquanto o usuário está no workspace, que seu acesso foi
removido; SHALL avisá-lo, remover o workspace do índice local, descartar o cache de
consultas daquele workspace e navegar para o workspace próprio (§3.10).

#### Scenario: Detecção por evento empurrado

- **WHEN** o dono remove a membership de um usuário que está com a tela de um robô
  aberta, e o `WorkspaceChannel` de D6 está conectado
- **THEN** o cliente daquele usuário SHALL executar a rotina de revogação em menos
  de 2 segundos, sem que ele precise interagir com a tela

#### Scenario: Detecção por 403 quando não há Cable

- **WHEN** o `WorkspaceChannel` não está conectado e a próxima requisição do usuário
  ao workspace responde `403` com código `workspace_access_revoked`
- **THEN** o cliente SHALL executar a mesma rotina de revogação, provando que o
  fallback funciona sem `realtime-collaboration`

#### Scenario: Cache do workspace perdido é descartado

- **WHEN** a rotina de revogação executa para `WS-A`
- **THEN** todas as chaves React Query com prefixo `['ws', WS-A]` SHALL ser removidas
  do cache, e nenhum dado de `WS-A` SHALL permanecer renderizado após a navegação

#### Scenario: Aviso é persistente

- **WHEN** a rotina de revogação executa
- **THEN** o aviso SHALL nomear o workspace perdido e SHALL permanecer até dispensa
  explícita do usuário, e SHALL NOT desaparecer automaticamente

#### Scenario: Sessão não é invalidada

- **WHEN** o usuário removido de `WS-A` também é membro de `WS-B`
- **THEN** ele SHALL permanecer autenticado e com acesso íntegro a `WS-B`, e seu JWT
  SHALL NOT ser adicionado à denylist de D4

#### Scenario: Usuário sem outro workspace volta ao próprio

- **WHEN** o usuário removido de `WS-A` não é membro de nenhum outro workspace além
  do próprio
- **THEN** o app SHALL navegar para o workspace próprio criado no bootstrap
  (`workspace-tenancy`), nunca para uma tela vazia ou erro

#### Scenario: Índice local não é fonte de autorização

- **WHEN** o usuário removido de `WS-A` reinsere manualmente `WS-A` no índice local
  persistido e recarrega o app
- **THEN** toda requisição a `WS-A` SHALL responder `403`, confirmando a invariante 2
  (o índice de workspaces é cache de UI)
