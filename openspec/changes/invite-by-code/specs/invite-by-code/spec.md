## ADDED Requirements

### Requirement: Código curto como representação adicional do convite

O sistema SHALL permitir que um convite (`invitations`) tenha, além do `token`, um
**código curto por-convite** representado no banco por `code_hash text` (HMAC-SHA256 do
código com pepper de servidor), `code_expires_at timestamptz NULL` (expiração própria,
mais curta que a do link), `code_attempts smallint NOT NULL DEFAULT 0` e
`code_locked_at timestamptz NULL`. O sistema SHALL garantir a unicidade do código por
índice único parcial `WHERE code_hash IS NOT NULL` e SHALL NOT persistir o código em
claro em coluna alguma.

#### Scenario: Convite criado com código guarda apenas o hash

- **WHEN** o dono de `WS-A` cria um convite com código para `joao@fabrica.com`
- **THEN** a linha persistida SHALL ter `code_hash` não nulo, `code_expires_at`
  preenchido, `code_attempts = 0`, `code_locked_at IS NULL`, e SHALL NOT existir nenhuma
  coluna contendo o código em claro

#### Scenario: Dois convites não podem compartilhar o mesmo code_hash

- **WHEN** um `INSERT`/`UPDATE` direto por console tenta gravar um `code_hash` já usado
  por outro convite
- **THEN** o banco SHALL rejeitar por violação do índice único parcial
  `index_invitations_on_code_hash`

#### Scenario: Convite via link puro não tem código

- **WHEN** um convite é criado sem código (só link)
- **THEN** a linha SHALL ter `code_hash IS NULL` e `code_expires_at IS NULL`, e o índice
  único parcial SHALL NOT contá-la (múltiplos convites sem código coexistem)

#### Scenario: Expiração do código é mais curta que a do link

- **WHEN** um convite com código é criado em `2026-07-24T10:00:00Z`
- **THEN** `expires_at` (link) SHALL ser `2026-07-31T10:00:00Z` (7 dias) e
  `code_expires_at` SHALL ser `2026-07-26T10:00:00Z` (48h), com `code_expires_at <
  expires_at`

### Requirement: Geração criptográfica do código no alfabeto sem ambíguos

O sistema SHALL gerar o código com 8 caracteres do alfabeto Crockford Base32
(`0123456789ABCDEFGHJKMNPQRSTVWXYZ`, que exclui I, L, O e U), usando fonte
criptograficamente segura e sem viés de módulo, exibindo-o como `XXXX-XXXX`. O sistema
SHALL normalizar a entrada do usuário (maiúsculas, remoção de hífen/espaço, mapeamento
de ambíguos `I→1`, `L→1`, `O→0`) antes de computar o hash.

#### Scenario: 10.000 códigos gerados são distintos e sem ambíguos

- **WHEN** 10.000 códigos são gerados em sequência
- **THEN** os 10.000 códigos SHALL ser distintos, SHALL ter exatamente 8 caracteres cada
  e SHALL NOT conter nenhum dos caracteres I, L, O, U

#### Scenario: Normalização tolerante casa a entrada do galpão

- **WHEN** o convite tem código canônico `4K7P9QMX` e o usuário digita `4k7p-9qmx`
- **THEN** a normalização SHALL produzir `4K7P9QMX` e o hash computado SHALL casar o
  `code_hash` da linha

#### Scenario: Colisão de código gerado é resolvida por retry

- **WHEN** a geração produz um código cujo `code_hash` já existe e o `INSERT` levanta
  `RecordNotUnique`
- **THEN** o sistema SHALL gerar um novo código e tentar de novo, e SHALL NOT propagar um
  `500` ao chamador

### Requirement: Lookup por código sem contexto de workspace

O sistema SHALL localizar a linha do convite por código através de uma função
`invitation_by_code(text)` `SECURITY DEFINER` que recebe o HASH já computado no
aplicativo (o pepper nunca entra no banco) e de um terceiro ramo no `USING` da policy
`tenant_isolation` de `invitations` (`OR code_hash = NULLIF(current_setting(
'app.invitation_code_hash', true), '')`). O `WITH CHECK` SHALL permanecer restrito ao
workspace corrente, e o sistema SHALL NOT usar `BYPASSRLS`.

#### Scenario: Função acha a linha por hash exato, sem workspace corrente

- **WHEN** `invitation_by_code($hash)` é chamada com o hash de um convite de `WS-A`,
  sem `app.current_workspace_id` setado
- **THEN** a função SHALL retornar exatamente aquela linha

#### Scenario: Lookup por código não permite listagem

- **WHEN** um `SELECT * FROM invitations` é executado com `app.invitation_code_hash`
  setado ao hash de um convite de `WS-A` e sem workspace corrente
- **THEN** o resultado SHALL conter no máximo a linha daquele hash e SHALL NOT retornar
  qualquer outra linha de `invitations`

#### Scenario: Sem código conhecido, RLS nega tudo (fail-closed)

- **WHEN** um `SELECT * FROM invitations` é executado sem `app.current_workspace_id` e
  sem `app.invitation_code_hash`
- **THEN** o resultado SHALL ser vazio (a comparação com `NULL` não é `TRUE`)

#### Scenario: Convite de outro tenant não vaza por código

- **WHEN** o dono de `WS-B`, no contexto de `WS-B`, faz `SELECT` esperando ver o convite
  de `WS-A` sem conhecer o código dele
- **THEN** o resultado SHALL NOT conter a linha de `WS-A`

### Requirement: Aceite por código atômico com e-mail autenticado idêntico

O sistema SHALL consumir o convite por código na MESMA transação atômica do aceite por
token: sob `SELECT ... FOR UPDATE` da linha, validando as seis condições da invariante 6
(§4.1) e criando a `Membership` com o papel LIDO da linha. O endpoint SHALL ser
`POST /api/v1/invitations/code/accept` com corpo `{ code, email }`, SHALL exigir
autenticação, SHALL exigir que o e-mail do convite seja idêntico ao e-mail autenticado
e SHALL NOT aceitar `role` no corpo.

#### Scenario: Aceite por código bem-sucedido cria membership e marca usado

- **WHEN** `joao@fabrica.com`, autenticado, chama `POST /api/v1/invitations/code/accept`
  com o código válido de um convite `edit` pendente de `WS-A`
- **THEN** o sistema SHALL responder `200`; **AND** SHALL existir exatamente 1
  `Membership` em `WS-A` com `role = "edit"`; **AND** o convite SHALL ter `used_at` e
  `used_by_user_id` preenchidos

#### Scenario: Corrida entre dois consumos pelo mesmo código

- **WHEN** duas requisições simultâneas de aceite pelo mesmo código chegam do mesmo
  usuário autenticado
- **THEN** exatamente uma SHALL responder `200` e a outra `409 invitation_already_used`;
  **AND** SHALL existir exatamente 1 `Membership` para aquele convite; **AND** nenhuma
  SHALL responder `500`

#### Scenario: E-mail autenticado diferente do convite não consome

- **WHEN** `ana@fabrica.com`, autenticada, chama o aceite por código de um convite
  emitido para `joao@fabrica.com` (ainda que ela conheça o código)
- **THEN** o sistema SHALL NOT criar `Membership` para `ana@fabrica.com`, SHALL NOT
  marcar `used_at`, e SHALL responder de forma que não conceda acesso (a comparação de
  e-mail é a condição 5 da invariante 6, inalterada)

#### Scenario: Papel adulterado no corpo do aceite por código

- **WHEN** `joao@fabrica.com` chama o aceite por código de um convite `view` enviando
  `{ code, email, role: "edit" }`
- **THEN** o sistema SHALL responder `422 unexpected_parameter`, SHALL NOT criar
  `Membership` e SHALL NOT consumir o convite

#### Scenario: Papel da membership vem sempre do convite

- **WHEN** um aceite por código bem-sucedido ocorre para um convite `view`
- **THEN** a `Membership` SHALL ter `role = "view"`, lido da linha dentro da transação

#### Scenario: Código expirado é recusado sem consumir

- **WHEN** `joao@fabrica.com` chama o aceite por código em `2026-07-27T00:00:00Z` de um
  convite com `code_expires_at = 2026-07-26T10:00:00Z` (mas com o LINK ainda válido)
- **THEN** o sistema SHALL responder com erro de código expirado, SHALL NOT criar
  `Membership`, e o convite SHALL permanecer consumível pelo LINK

#### Scenario: Aceite por token continua funcionando inalterado

- **WHEN** um convite com código também é aceito por `POST /api/v1/invitations/:token/
  accept` pelo destinatário autenticado
- **THEN** o fluxo do token SHALL responder `200` exatamente como antes deste change

### Requirement: Preview por código exige o par código + e-mail

O sistema SHALL expor `POST /api/v1/invitations/code/preview` com corpo `{ code, email }`
como rota pública (pré-login), retornando `workspace_name`, `role`, `email_masked` e
`status` SOMENTE quando o e-mail submetido for idêntico ao e-mail do convite localizado
pelo código. Sem o par correto, a resposta SHALL ser genérica e idêntica (mesmo corpo,
mesmo tempo) à de um código inexistente.

#### Scenario: Par correto revela a pré-visualização

- **WHEN** uma requisição sem autenticação chama o preview por código com o código e o
  e-mail corretos de um convite pendente de `joao@fabrica.com` no workspace "Linha 3"
- **THEN** o sistema SHALL responder `200` com `workspace_name: "Linha 3"`,
  `email_masked: "j***@fabrica.com"` e `status: "pending"`, e SHALL NOT retornar
  `joao@fabrica.com` completo nem `workspace_id`

#### Scenario: Código certo com e-mail errado não vaza nada

- **WHEN** o preview por código é chamado com o código correto mas um e-mail diferente
  do convite
- **THEN** o sistema SHALL responder de forma genérica idêntica à de um código
  inexistente e SHALL NOT retornar `workspace_name`, `role` nem `email_masked`

#### Scenario: Código inexistente responde igual a par inválido

- **WHEN** o preview por código é chamado com um código que não existe
- **THEN** o sistema SHALL responder com o MESMO corpo e o MESMO status do cenário de
  código certo com e-mail errado (sem canal lateral que distinga "existe" de "não
  existe")

### Requirement: Lockout do código após tentativas falhas

O sistema SHALL contar as tentativas de aceite/preview em que o CÓDIGO existe mas o
e-mail do par não casa, incrementando `code_attempts` da linha; ao atingir 5 falhas,
SHALL setar `code_locked_at` e passar a responder `423 invitation_code_locked` ao par
código+e-mail correspondente. O LINK do mesmo convite SHALL permanecer válido, e o
lockout SHALL ser removível apenas pela reemissão de um novo código pelo dono.

#### Scenario: Sexta falha do par trava o código

- **WHEN** um atacante submete o código correto com e-mail errado 5 vezes e então uma 6ª
- **THEN** a partir do lockout o sistema SHALL responder `423 invitation_code_locked`,
  `code_locked_at` SHALL estar preenchido, e mesmo o e-mail CORRETO SHALL receber `423`
  até a reemissão

#### Scenario: Link segue válido com o código travado

- **WHEN** o código de um convite está travado (`code_locked_at` preenchido) e o
  destinatário autenticado aceita pelo LINK (`/:token/accept`)
- **THEN** o aceite por token SHALL responder `200` e consumir o convite normalmente

#### Scenario: Adivinhação cega não trava linha alguma

- **WHEN** um atacante submete códigos que NÃO existem
- **THEN** nenhuma linha SHALL ter `code_attempts` incrementado (não há linha a travar),
  e a defesa contra o volume SHALL recair sobre o rate-limit por IP/e-mail/global

### Requirement: Rate limiting dos endpoints por código

O sistema SHALL limitar `POST /api/v1/invitations/code/accept` a 5 tentativas por 10
minutos por IP e a 5 por 10 minutos por e-mail submetido, `POST /api/v1/invitations/
code/preview` a 10 por 10 minutos por IP, e SHALL aplicar um teto GLOBAL de falhas de
código por minuto, respondendo `429` com header `Retry-After`. Os tetos por código SHALL
ser mais apertados que os do token.

#### Scenario: 6ª tentativa de aceite por código do mesmo IP é bloqueada

- **WHEN** o mesmo IP faz 5 chamadas de aceite por código em 3 minutos e então uma 6ª
- **THEN** o sistema SHALL responder `429` com `Retry-After` presente, sem consultar o
  banco

#### Scenario: Teto por e-mail submetido morde outro IP

- **WHEN** 5 tentativas de aceite por código para o mesmo e-mail chegam de IPs diferentes
  e então uma 6ª
- **THEN** a 6ª SHALL responder `429` (o eixo do e-mail cobre o que o IP não cobre)

#### Scenario: Bloqueio não vaza o código em claro

- **WHEN** uma chamada por código é bloqueada por rate limiting
- **THEN** o log estruturado SHALL conter apenas `code_sha256` truncado em 12 chars e
  SHALL NOT conter o código em claro

### Requirement: Código nunca aparece em claro em log ou resposta

O sistema SHALL expor o código em claro EXCLUSIVAMENTE na resposta da criação do convite
(campo `short_code` da entity, uma única vez), e SHALL NOT reexpô-lo em nenhuma listagem,
preview ou log. A listagem de pendentes SHALL expor apenas `code_status` e
`code_expires_at`, nunca `code_hash` nem o claro.

#### Scenario: Criação retorna o código uma vez

- **WHEN** o dono cria um convite com código
- **THEN** a resposta `201` SHALL conter `short_code` no formato `XXXX-XXXX` e SHALL NOT
  conter `code_hash`

#### Scenario: Listagem de pendentes não reexpõe o código

- **WHEN** o dono lista os convites pendentes de `WS-A` depois de fechar o diálogo de
  criação
- **THEN** cada convite com código SHALL trazer `code_status` e `code_expires_at`, e
  SHALL NOT trazer `short_code` nem `code_hash`

#### Scenario: Código não aparece em log de aceite

- **WHEN** requisições a `POST /api/v1/invitations/code/accept` são processadas e logadas
- **THEN** nenhuma linha de log SHALL conter o código em claro; apenas o hash truncado
  quando houver bloqueio

### Requirement: Entrada por código na tela de login

O sistema SHALL oferecer, na tela de entrada (`/entrar`), uma seção "Tenho um código de
convite" com campos de E-mail e Código; SHALL preservar o par em `sessionStorage`
(mecanismo de `identity-and-auth`) para sobreviver ao redirect do Google OAuth; SHALL
consumir o convite após a autenticação; e SHALL limpar o par em qualquer desfecho. Os
campos SHALL ter fundo temático (regra F) e alvo de toque ≥ 32px.

#### Scenario: Código sobrevive ao redirect do Google

- **WHEN** um visitante não autenticado digita e-mail e código válidos na seção "Tenho um
  código de convite" e conclui login via Google (redirect)
- **THEN** ao retornar autenticado, o app SHALL disparar o aceite por código
  automaticamente, sem que o usuário redigite o código

#### Scenario: Par limpo mesmo quando o aceite falha

- **WHEN** o aceite por código responde com e-mail divergente do autenticado
- **THEN** o app SHALL remover o par de `sessionStorage`, SHALL exibir a orientação
  específica (sair e entrar com a conta correta) e uma navegação subsequente SHALL NOT
  reemitir o aceite

#### Scenario: Código travado mostra mensagem específica

- **WHEN** o aceite por código responde `423 invitation_code_locked`
- **THEN** o app SHALL exibir uma mensagem própria orientando pedir um novo código ao
  responsável, e SHALL NOT exibir o erro genérico "não foi possível aceitar"

#### Scenario: Campo de código tem fundo temático e é tolerante

- **WHEN** a seção de código é renderizada no tema escuro
- **THEN** os campos SHALL usar fundo temático (não branco-sobre-branco) e SHALL aceitar
  a digitação em minúsculas, com hífen e espaços, normalizando antes de enviar
