## ADDED Requirements

### Requirement: O código é o único caminho de convite

O sistema SHALL oferecer o **código curto** (`XXXX-XXXX`) como a única representação de
convite exposta ao usuário. Nenhuma superfície de produto — UI, rota SPA ou endpoint de
API — SHALL expor um link de convite por token. A geração interna do `token` (dormente)
MAY continuar, mas NÃO SHALL ser exposta.

#### Scenario: Criar convite não revela link

- **WHEN** o dono cria um convite via `POST /api/v1/invitations`
- **THEN** a resposta SHALL conter `short_code` (formatado `XXXX-XXXX`) e `code_expires_at`
- **AND** a resposta NÃO SHALL conter `invite_url` nem qualquer campo de token

#### Scenario: A tela de criação mostra só o código

- **WHEN** o `InviteDialog` exibe o convite recém-criado
- **THEN** SHALL mostrar o código e o controle "Copiar código"
- **AND** NÃO SHALL renderizar região de link, input de `invite_url` nem "Copiar link"

#### Scenario: A lista de convites pendentes não expõe link

- **WHEN** o `TeamPanel` lista os convites pendentes
- **THEN** cada linha SHALL mostrar e-mail, papel e status (incl. status do código)
- **AND** NÃO SHALL renderizar o input de `invite_url`

### Requirement: A superfície pública de convite se limita ao preview por código

O único endpoint público (não autenticado) de convite SHALL ser `POST
/api/v1/invitations/code/preview`. A allowlist pública (`PUBLIC_ROUTES`,
`config/authorization/public_routes.yml`) NÃO SHALL conter nenhuma rota de token.

#### Scenario: Route-sweep não encontra rota pública de token

- **WHEN** a varredura de rotas públicas roda sobre a allowlist
- **THEN** nenhuma entrada SHALL casar `GET /api/v1/invitations/:token`
- **AND** a única rota pública de convite SHALL ser `POST /api/v1/invitations/code/preview`

## REMOVED Requirements

### Requirement: Preview público do convite por token

**Motivo:** o link deixa de existir no produto (código-só). O preview por token era a porta
pública pré-login do link; sem link, a rota some. Substituído pelo preview por código
(`POST /api/v1/invitations/code/preview`, exige o par código + e-mail), que já existe.

O sistema não expõe mais `GET /api/v1/invitations/:token`.

#### Scenario: Rota de preview por token não existe mais

- **WHEN** um cliente faz `GET /api/v1/invitations/rt_inv_qualquercoisa`
- **THEN** a aplicação SHALL responder 404 (rota inexistente), não um preview
- **AND** nenhum dado do convite (workspace, e-mail mascarado, papel) SHALL vazar

### Requirement: Aceite de convite por token

**Motivo:** removido o link, o aceite por token deixa de ter caminho de entrada. O aceite
por **código** (`POST /api/v1/invitations/code/accept`) é o único, e preserva idêntica a
invariante §4.1 inv. 6 (consumo atômico com e-mail idêntico ao autenticado).

O sistema não expõe mais `POST /api/v1/invitations/:token/accept` nem a rota SPA
`/convite/:token`.

#### Scenario: Aceite por token não existe mais

- **WHEN** um usuário autenticado faz `POST /api/v1/invitations/rt_inv_x/accept`
- **THEN** a aplicação SHALL responder 404 (rota inexistente)
- **AND** nenhuma membership SHALL ser criada por esse caminho

#### Scenario: A rota SPA de convite por link não existe mais

- **WHEN** um usuário abre `/convite/<token>` no navegador
- **THEN** o app NÃO SHALL montar um preview de convite por token
- **AND** o único caminho de aceite no cliente SHALL ser por código (seção "Tenho um
  código" da tela de entrada e o diálogo de entrar por código no app)

## MODIFIED Requirements

### Requirement: Localização da linha de convite no aceite e no preview

O `AcceptService` e o `PreviewService` SHALL localizar a linha de `invitations`
**exclusivamente por código** (`row_by_code` / `invitation_by_code`). O construtor NÃO
SHALL aceitar `token:`. As demais etapas do consumo — `SELECT … FOR UPDATE`, as 6
validações da invariante §4.1 inv. 6, a resolução de `Person`, o one-shot e o
`reject_unexpected_parameters!` — SHALL permanecer inalteradas.

#### Scenario: Aceite por código bem-sucedido cria membership

- **WHEN** o par código + e-mail é válido e o e-mail autenticado é idêntico ao do convite
- **THEN** o serviço SHALL criar a membership com o papel do convite e marcar `used_at`

#### Scenario: E-mail autenticado diferente do convite não consome (negação)

- **WHEN** o código é válido mas o e-mail autenticado difere do e-mail do convite
- **THEN** o serviço SHALL recusar sem criar membership (preserva inv. 6)

#### Scenario: Convite de outro tenant não vaza por código (negação cross-tenant)

- **WHEN** um usuário tenta prever/aceitar um código de convite de outro workspace ao qual
  não pertence e cujo e-mail não é o seu
- **THEN** a resposta SHALL ser indistinguível de código inexistente (nada vaza)
- **AND** nenhuma membership cross-tenant SHALL ser criada

#### Scenario: Nenhum caminho por token permanece no serviço

- **WHEN** o código chama `AcceptService`/`PreviewService`
- **THEN** não SHALL existir ramo `lookup_by_token`/`lookup` por token acionável
- **AND** passar `token:` SHALL ser um erro (parâmetro não aceito)
