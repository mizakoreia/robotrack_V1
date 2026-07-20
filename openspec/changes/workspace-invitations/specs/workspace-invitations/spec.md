## ADDED Requirements

### Requirement: Entidade Convite

O sistema SHALL persistir convites numa tabela `invitations` com PK `uuid` gerável
no cliente (D1), `workspace_id uuid NOT NULL` sob RLS (D2), `token text NOT NULL`
único, `email text NOT NULL` armazenado em minúsculas, `role` de enum Postgres
restrito a `view`/`edit`, `created_by_person_id uuid NOT NULL`,
`expires_at timestamptz NOT NULL`, `used_at timestamptz NULL` e
`used_by_user_id uuid NULL`.

#### Scenario: Convite criado com os campos obrigatórios

- **WHEN** o dono do workspace `WS-A` cria um convite para `Joao@Fabrica.COM` com
  papel `edit` em `2026-07-20T10:00:00Z`
- **THEN** a linha persistida SHALL ter `email = "joao@fabrica.com"`,
  `role = "edit"`, `workspace_id = WS-A`, `expires_at = 2026-07-27T10:00:00Z`,
  `used_at IS NULL` e `used_by_user_id IS NULL`

#### Scenario: E-mail em maiúsculas é rejeitado no nível do banco

- **WHEN** um `INSERT` direto por console tenta gravar `email = "Joao@Fabrica.com"`
- **THEN** o banco SHALL rejeitar com violação da constraint
  `CHECK (email = lower(email))`

#### Scenario: Papel owner não é representável

- **WHEN** um `INSERT` direto por console tenta gravar `role = 'owner'`
- **THEN** o banco SHALL rejeitar com erro de valor inválido para o enum
  `invitation_role`

#### Scenario: Estado meio-consumido é impossível

- **WHEN** um `UPDATE` direto tenta gravar `used_at = now()` mantendo
  `used_by_user_id IS NULL`
- **THEN** o banco SHALL rejeitar com violação da constraint
  `chk_invitations_consumption`

#### Scenario: Expiração é obrigatória

- **WHEN** um `INSERT` direto omite `expires_at` e o default não é aplicável
- **THEN** o banco SHALL rejeitar por `NOT NULL`, e o sistema SHALL NOT reproduzir
  a tolerância do legado (`firestore.rules` L33, `!('expiresAt' in ...)`) que
  fazia convites sem expiração nunca expirarem

### Requirement: Token opaco de alta entropia

O sistema SHALL gerar o `token` com no mínimo 256 bits de entropia
criptograficamente segura, em codificação URL-safe, com prefixo `rt_inv_`, e SHALL
garantir sua unicidade por índice único no banco.

#### Scenario: Token gerado é único e URL-safe

- **WHEN** 10.000 convites são criados em sequência
- **THEN** os 10.000 tokens SHALL ser distintos, SHALL casar
  `\Art_inv_[A-Za-z0-9_-]{43}\z` e SHALL NOT exigir escape ao serem inseridos numa URL

#### Scenario: Token nunca aparece em claro nos logs

- **WHEN** uma requisição a `POST /api/v1/invitations/:token/accept` é bloqueada
  por rate limiting
- **THEN** a linha de log estruturado SHALL conter apenas o SHA-256 do token
  truncado em 12 chars, e SHALL NOT conter a string `rt_inv_` seguida do valor

### Requirement: Criação de convite restrita ao dono do próprio workspace

O sistema SHALL permitir a criação de convite apenas por membro com papel `owner`
do workspace de destino, com `role` restrito a `view`/`edit` (invariante 7,
`firestore.rules` L72-77). A restrição SHALL residir simultaneamente em
`InvitationPolicy.create?`, no enum Postgres do papel e na FK composta
`(workspace_id, created_by_person_id) → people (workspace_id, id)`.

#### Scenario: Dono cria convite no próprio workspace

- **WHEN** o dono de `WS-A` chama `POST /api/v1/invitations` com
  `{ email: "joao@fabrica.com", role: "view" }` no contexto de `WS-A`
- **THEN** o sistema SHALL responder `201` com o convite e o link absoluto
  `<APP_URL>/convite/rt_inv_...`

#### Scenario: Membro edit tentando convidar é negado

- **WHEN** um membro com papel `edit` de `WS-A` chama `POST /api/v1/invitations`
  com `{ email: "ana@fabrica.com", role: "view" }`
- **THEN** o sistema SHALL responder `403` com código `forbidden`, SHALL NOT criar
  linha em `invitations`, e o contador de convites de `WS-A` SHALL permanecer
  inalterado

#### Scenario: Membro view tentando convidar é negado

- **WHEN** um membro com papel `view` de `WS-A` chama `POST /api/v1/invitations`
- **THEN** o sistema SHALL responder `403` com código `forbidden`

#### Scenario: Convite apontando para workspace que não é do criador

- **WHEN** o dono de `WS-A` chama `POST /api/v1/invitations` forçando
  `workspace_id = WS-B` (workspace do qual ele não é membro)
- **THEN** o sistema SHALL responder `403` com código `forbidden` e SHALL NOT
  criar a linha; **AND** se a mesma inserção for tentada diretamente no banco, a FK
  composta `fk_invitations_creator_in_workspace` SHALL rejeitá-la porque a `Person`
  criadora não pertence a `WS-B`

#### Scenario: Papel owner rejeitado na API

- **WHEN** o dono de `WS-A` chama `POST /api/v1/invitations` com `role: "owner"`
- **THEN** o sistema SHALL responder `422` com código `invalid_role` (invariante 5:
  o dono é imutável e não é convidável)

#### Scenario: E-mail acima de 254 chars é rejeitado

- **WHEN** o dono cria convite com um `email` de 255 caracteres
- **THEN** o sistema SHALL responder `422` com código `invalid_email`, replicando
  `firestore.rules` L77 (`email.size() <= 254`)

### Requirement: Pré-visualização pública do convite

O sistema SHALL expor `GET /api/v1/invitations/:token` como rota pública (na
allowlist de regex de `api/root.rb`), retornando apenas `workspace_name`, `role`,
`email_masked`, `expires_at` e `status`.

#### Scenario: Convite pendente pré-visualizado sem autenticação

- **WHEN** uma requisição sem header `Authorization` chama
  `GET /api/v1/invitations/rt_inv_ABC` para um convite pendente de `joao@fabrica.com`
  no workspace "Linha 3"
- **THEN** o sistema SHALL responder `200` com
  `{ workspace_name: "Linha 3", role: "view", email_masked: "j***@fabrica.com",
  status: "pending" }` e SHALL NOT retornar `joao@fabrica.com`, `workspace_id`,
  `created_by_person_id` nem lista de membros

#### Scenario: Token inexistente na pré-visualização

- **WHEN** uma requisição chama `GET /api/v1/invitations/rt_inv_INEXISTENTE`
- **THEN** o sistema SHALL responder `404` com código `invitation_not_found`, com o
  mesmo tempo de resposta de um token válido (sem canal lateral de temporização)

### Requirement: Consumo atômico do convite

O sistema SHALL consumir o convite em **uma única transação** que, sob
`SELECT ... FOR UPDATE` da linha do convite, valida as seis condições da invariante
6 e então cria a `Membership` e marca `used_at`/`used_by_user_id`. O endpoint SHALL
ser `POST /api/v1/invitations/:token/accept` e SHALL NOT aceitar `role` no corpo.

#### Scenario: Aceite bem-sucedido cria membership e marca usado

- **WHEN** `joao@fabrica.com`, autenticado, chama
  `POST /api/v1/invitations/rt_inv_ABC/accept` para um convite pendente de papel
  `edit` no workspace `WS-A`
- **THEN** o sistema SHALL responder `200`; **AND** SHALL existir exatamente 1
  `Membership` em `WS-A` com `role = "edit"` e `invitation_id = ABC`; **AND** o
  convite SHALL ter `used_at` preenchido e `used_by_user_id` = id do usuário; **AND**
  ambas as escritas SHALL ter ocorrido no mesmo `xid` de transação

#### Scenario: Corrida entre dois consumos do mesmo token

- **WHEN** duas requisições simultâneas de aceite do token `rt_inv_ABC` chegam do
  mesmo usuário autenticado
- **THEN** exatamente uma SHALL responder `200` e a outra SHALL responder `409` com
  código `invitation_already_used`; **AND** SHALL existir exatamente 1 `Membership`
  com `invitation_id = ABC`; **AND** nenhuma das duas SHALL responder `500`

#### Scenario: Segunda membership do mesmo convite bloqueada pelo banco

- **WHEN** um `INSERT` direto por console tenta criar uma segunda `Membership` com
  `invitation_id` de um convite já consumido
- **THEN** o banco SHALL rejeitar por violação do índice único parcial
  `idx_memberships_one_per_invitation`

#### Scenario: E-mail autenticado diferente do convite

- **WHEN** `ana@fabrica.com`, autenticada, chama o aceite de um convite emitido para
  `joao@fabrica.com`
- **THEN** o sistema SHALL responder `403` com código `invitation_email_mismatch`;
  **AND** o convite SHALL permanecer com `used_at IS NULL`; **AND** nenhuma
  `Membership` SHALL ser criada para `ana@fabrica.com` em `WS-A`

#### Scenario: Token já usado

- **WHEN** um usuário chama o aceite de um convite cujo `used_at` já está preenchido
- **THEN** o sistema SHALL responder `409` com código `invitation_already_used` e
  SHALL NOT alterar `used_at` nem `used_by_user_id`

#### Scenario: Token expirado

- **WHEN** `joao@fabrica.com` chama o aceite em `2026-07-28T10:00:01Z` de um convite
  com `expires_at = 2026-07-27T10:00:00Z`
- **THEN** o sistema SHALL responder `410` com código `invitation_expired` e SHALL
  NOT criar `Membership`

#### Scenario: Papel adulterado no corpo da requisição

- **WHEN** `joao@fabrica.com` chama o aceite de um convite de papel `view` enviando
  o corpo `{ "role": "edit" }`
- **THEN** o sistema SHALL responder `422` com código `unexpected_parameter`, SHALL
  NOT criar `Membership` e SHALL NOT consumir o convite — a rejeição explícita
  (em vez de ignorar o parâmetro) SHALL registrar a tentativa

#### Scenario: Papel da membership vem sempre do convite

- **WHEN** um aceite bem-sucedido ocorre para um convite de papel `view`
- **THEN** a `Membership` criada SHALL ter `role = "view"`, sendo o valor lido da
  linha do convite dentro da transação e nunca de entrada do cliente

#### Scenario: Convite apontando para workspace divergente

- **WHEN** o aceite é processado e `invitation.workspace_id` não corresponde ao
  workspace-alvo resolvido
- **THEN** o sistema SHALL responder `422` com código
  `invitation_workspace_mismatch` e SHALL fazer rollback da transação inteira

#### Scenario: Usuário que já é membro

- **WHEN** `joao@fabrica.com`, já membro `edit` de `WS-A`, chama o aceite de um
  convite pendente para `WS-A`
- **THEN** o sistema SHALL responder `409` com código `already_member`, SHALL NOT
  consumir o convite (ele permanece pendente e revogável pelo dono) e SHALL NOT
  alterar o papel da membership existente

#### Scenario: Falha parcial faz rollback completo

- **WHEN** a criação da `Person` falha por conflito depois de o convite ter sido
  travado com `FOR UPDATE`
- **THEN** a transação SHALL sofrer rollback; **AND** `used_at` SHALL permanecer
  `NULL`; **AND** nenhuma `Membership` SHALL existir; **AND** o mesmo token SHALL
  continuar consumível numa tentativa posterior

### Requirement: Criação ou casamento de Person no aceite

O sistema SHALL, dentro da transação de aceite, resolver a `Person` do convidado
(D10): casando por e-mail com uma `Person` do workspace que tenha `user_id IS NULL`,
ou criando uma `Person` nova com `user_id` preenchido.

#### Scenario: Casamento com Person pré-cadastrada preserva histórico

- **WHEN** existe em `WS-A` a `Person` "João Silva" com `email = "joao@fabrica.com"`,
  `user_id IS NULL` e 12 tarefas atribuídas, e `joao@fabrica.com` aceita o convite
- **THEN** o sistema SHALL preencher `person.user_id` com o id do usuário, SHALL NOT
  criar uma segunda `Person`, e as 12 tarefas SHALL permanecer atribuídas à mesma
  `Person`

#### Scenario: Person nova quando não há correspondência

- **WHEN** não existe `Person` com `email = "ana@fabrica.com"` em `WS-A` e
  `ana@fabrica.com` aceita o convite
- **THEN** o sistema SHALL criar uma `Person` em `WS-A` com aquele e-mail,
  `user_id` preenchido e `name` = nome de exibição do usuário

#### Scenario: Person já vinculada a outro usuário

- **WHEN** existe `Person` com `email = "joao@fabrica.com"` em `WS-A` cujo `user_id`
  já aponta para um usuário diferente, e `joao@fabrica.com` aceita o convite
- **THEN** o sistema SHALL responder `409` com código `person_email_conflict` e
  SHALL NOT sobrescrever `person.user_id`

#### Scenario: Casamento é por e-mail, nunca por nome

- **WHEN** existe em `WS-A` a `Person` "João Silva" sem e-mail e o convite é para
  `joao@fabrica.com` cujo nome de exibição também é "João Silva"
- **THEN** o sistema SHALL criar uma `Person` nova e SHALL NOT casar pelo nome

### Requirement: Token de convite recebido antes do login

O sistema SHALL aceitar o token pela URL antes da autenticação, preservá-lo em
`sessionStorage` (mecanismo de `identity-and-auth`, D4), consumi-lo após a
autenticação e limpá-lo em qualquer desfecho.

#### Scenario: Token sobrevive ao redirect do Google

- **WHEN** um visitante não autenticado abre `/convite/rt_inv_ABC` e conclui login
  via Google (redirect, não popup)
- **THEN** ao retornar autenticado, o app SHALL disparar o aceite de `rt_inv_ABC`
  automaticamente, sem que o usuário precise reabrir o link

#### Scenario: Token removido da URL após ser guardado

- **WHEN** o app grava o token em `sessionStorage`
- **THEN** SHALL substituir a URL via `history.replaceState` para uma sem o token, e
  a entrada do histórico do navegador SHALL NOT conter `rt_inv_ABC`

#### Scenario: Token limpo mesmo quando o aceite falha

- **WHEN** o aceite responde `403 invitation_email_mismatch`
- **THEN** o app SHALL remover o token de `sessionStorage`, SHALL exibir o e-mail
  mascarado do convite com a opção "sair e entrar com outra conta", e uma navegação
  subsequente SHALL NOT reemitir o aceite

#### Scenario: Aceite indisponível offline

- **WHEN** o dispositivo está sem rede e há um token pendente em `sessionStorage`
- **THEN** o app SHALL exibir "conecte-se para aceitar o convite" e SHALL NOT
  enfileirar o aceite na fila de mutations offline (D7)

### Requirement: Rate limiting dos endpoints de convite

O sistema SHALL limitar `POST /api/v1/invitations/:token/accept` a 10 tentativas por
10 minutos por IP e por usuário autenticado, e `GET /api/v1/invitations/:token` a 20
por 10 minutos por IP, respondendo `429` com header `Retry-After`.

#### Scenario: 11ª tentativa de aceite é bloqueada

- **WHEN** o mesmo IP faz 10 chamadas de aceite com tokens inválidos em 3 minutos e
  então uma 11ª
- **THEN** o sistema SHALL responder `429` com `Retry-After` presente, sem consultar
  o banco

#### Scenario: Bloqueio não vaza o token

- **WHEN** uma chamada é bloqueada por rate limiting
- **THEN** o log estruturado SHALL conter o hash truncado do token e SHALL NOT
  conter o token em claro

### Requirement: Expurgo de convites expirados

O sistema SHALL executar diariamente um job que apaga convites com `used_at IS NULL`
e `expires_at < now() - 30 dias`, preservando todos os convites consumidos.

#### Scenario: Convite expirado há 31 dias é apagado

- **WHEN** o job roda em `2026-08-27` e existe convite pendente com
  `expires_at = 2026-07-27`
- **THEN** a linha SHALL ser removida

#### Scenario: Convite expirado há 3 dias é preservado

- **WHEN** o job roda em `2026-07-30` e existe convite pendente com
  `expires_at = 2026-07-27`
- **THEN** a linha SHALL permanecer, para que o clique no link velho produza
  `410 invitation_expired` em vez de `404`

#### Scenario: Convite consumido nunca é apagado pelo job

- **WHEN** o job roda e existe convite com `used_at` preenchido e
  `expires_at` há 2 anos
- **THEN** a linha SHALL permanecer, porque `memberships.invitation_id` a referencia
  com `ON DELETE RESTRICT` e ela é a prova auditável do acesso concedido
