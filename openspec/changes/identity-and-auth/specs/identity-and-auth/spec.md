## ADDED Requirements

### Requirement: Cadastro por e-mail e senha

O sistema SHALL expor `POST /auth/v1/registration` aceitando `name`, `email`,
`password` e `remember_me`, criando um `User` com senha de no mínimo 6 caracteres
(§3.1) e devolvendo 201 com um JWT válido no corpo e no header `Authorization`.

#### Scenario: Cadastro válido

- **WHEN** `POST /auth/v1/registration` recebe `{name: "Ana Souza", email: "ana@fabrica.com", password: "senha123", remember_me: false}`
- **THEN** a resposta é 201, o corpo contém `data.user.name == "Ana Souza"` e `data.access_token`, e `User.count` aumenta em 1

#### Scenario: Senha com 5 caracteres é recusada

- **WHEN** `POST /auth/v1/registration` recebe `password: "abcde"` (5 caracteres)
- **THEN** a resposta é 422 com `errors.password` mencionando o mínimo de 6 caracteres, e nenhum `User` é criado

#### Scenario: E-mail já cadastrado

- **WHEN** `POST /auth/v1/registration` recebe `email: "ana@fabrica.com"` e já existe um `User` com esse e-mail
- **THEN** a resposta é 409, nenhum segundo `User` é criado, e o corpo NÃO revela se a conta existente é local ou Google

#### Scenario: E-mail normalizado para minúsculas

- **WHEN** `POST /auth/v1/registration` recebe `email: "Ana@Fabrica.COM"`
- **THEN** o `User` persistido tem `email == "ana@fabrica.com"`, e um cadastro posterior com `"ana@fabrica.com"` retorna 409

#### Scenario: Nome ausente

- **WHEN** `POST /auth/v1/registration` recebe `name: ""`
- **THEN** a resposta é 422 e nenhum `User` é criado

### Requirement: Nome de exibição sempre presente e normalizado

O sistema SHALL garantir que todo `User` tenha `name` com pelo menos 2 caracteres
não-brancos, normalizado (espaços das pontas removidos, espaços internos
colapsados), impondo isso por CHECK constraint no banco além da validação de
model. Este `name` é a fonte do nome de exibição consumido por `workspace-tenancy`
(D10), pelos snapshots de autor (D8), pelas notificações (§2.7) e pela auditoria
(§2.8).

#### Scenario: Espaços são normalizados na escrita

- **WHEN** um `User` é criado com `name: "  Ana   Souza  "`
- **THEN** o registro persistido tem `name == "Ana Souza"`

#### Scenario: Nome só de espaços é recusado

- **WHEN** um `User` é criado com `name: "   "`
- **THEN** a validação falha com 422

#### Scenario: CHECK constraint resiste ao bypass do model

- **WHEN** `User.find(id).update_column(:name, "A")` é executado pelo console, contornando as validações
- **THEN** o Postgres levanta `ActiveRecord::StatementInvalid` por violação do CHECK e o valor não é gravado

#### Scenario: Nome derivado quando o Google não envia um

- **WHEN** o callback do Google retorna `info.name` em branco e `info.email == "joao.silva@fabrica.com"`
- **THEN** o `User` criado tem `name == "joao.silva"`, nunca string vazia

### Requirement: Login por e-mail e senha

O sistema SHALL expor `POST /auth/v1/session` que autentica por e-mail e senha e
devolve 200 com um JWT, e SHALL responder 401 com a mesma mensagem genérica tanto
para senha incorreta quanto para e-mail inexistente.

#### Scenario: Credenciais corretas

- **WHEN** `POST /auth/v1/session` recebe `{email: "ana@fabrica.com", password: "senha123"}` de um usuário existente
- **THEN** a resposta é 200 com `data.access_token` decodificável e `data.user.id` igual ao id da Ana

#### Scenario: Senha incorreta

- **WHEN** `POST /auth/v1/session` recebe a senha `"senha124"` para `ana@fabrica.com`
- **THEN** a resposta é 401 com mensagem `"E-mail ou senha inválidos."` e nenhum token é emitido

#### Scenario: E-mail inexistente responde igual a senha errada

- **WHEN** `POST /auth/v1/session` recebe `{email: "ninguem@fabrica.com", password: "qualquer"}`
- **THEN** a resposta é 401 com exatamente o mesmo corpo do cenário de senha incorreta, e o cálculo de hash é executado mesmo assim para não vazar a existência da conta pelo tempo de resposta

#### Scenario: Conta criada só por Google não entra por senha

- **WHEN** `POST /auth/v1/session` recebe o e-mail de um `User` com `provider == "google_oauth2"` e `encrypted_password` vazio
- **THEN** a resposta é 401 e nenhum token é emitido

### Requirement: Tempo de vida do JWT amarrado ao "manter conectado"

O sistema SHALL carimbar `exp` no payload do JWT conforme o parâmetro
`remember_me` recebido no login ou cadastro: 30 dias quando verdadeiro, 12 horas
quando falso ou ausente. O payload SHALL conter `sub`, `jti`, `exp` e
`iat_origin`.

#### Scenario: Sessão longa

- **WHEN** o login é feito com `remember_me: true`
- **THEN** o `exp` decodificado do token fica entre 29 e 30 dias no futuro

#### Scenario: Sessão curta

- **WHEN** o login é feito com `remember_me: false`
- **THEN** o `exp` decodificado do token fica entre 11 e 12 horas no futuro

#### Scenario: Token expirado é rejeitado

- **WHEN** uma requisição a `GET /auth/v1/me` apresenta um token cujo `exp` já passou
- **THEN** a resposta é 401 e `current_user` não é populado

### Requirement: Logout revoga o token por denylist

O sistema SHALL usar `Devise::JWT::RevocationStrategies::Denylist` sobre a tabela
`jwt_denylist`, e `DELETE /auth/v1/session` SHALL gravar o `jti` do token
apresentado no denylist, tornando aquele token — e apenas aquele — inválido.

#### Scenario: Logout invalida o token apresentado

- **WHEN** `DELETE /auth/v1/session` é chamado com um token válido e em seguida `GET /auth/v1/me` é chamado com o mesmo token
- **THEN** o logout responde 204, uma linha com o `jti` daquele token existe em `jwt_denylist`, e o `GET` responde 401

#### Scenario: Logout em um dispositivo não derruba o outro

- **WHEN** o mesmo usuário tem os tokens A (celular) e B (desktop) e `DELETE /auth/v1/session` é chamado com A
- **THEN** o token A responde 401 e o token B continua respondendo 200 em `GET /auth/v1/me`

#### Scenario: Logout sem token

- **WHEN** `DELETE /auth/v1/session` é chamado sem header `Authorization`
- **THEN** a resposta é 401 e nenhuma linha é inserida em `jwt_denylist`

#### Scenario: `jti` duplicado é impedido pelo índice

- **WHEN** duas revogações concorrentes tentam inserir o mesmo `jti` em `jwt_denylist`
- **THEN** o índice único em `jwt_denylist.jti` faz a segunda inserção falhar e apenas uma linha existe

### Requirement: Renovação explícita com rotação de `jti` e teto absoluto

O sistema SHALL expor `POST /auth/v1/session/renew`, que exige token válido,
devolve um token novo e grava o `jti` do token antigo no denylist. A renovação
SHALL ser recusada quando `iat_origin` do token for mais antigo que duas vezes o
TTL da sessão.

#### Scenario: Renovação bem-sucedida rotaciona o `jti`

- **WHEN** `POST /auth/v1/session/renew` é chamado com o token A
- **THEN** a resposta é 200 com um token B cujo `jti` difere do de A, o `jti` de A está em `jwt_denylist`, e A passa a responder 401

#### Scenario: Renovação com token já revogado

- **WHEN** `POST /auth/v1/session/renew` é chamado com um token cujo `jti` já está no denylist
- **THEN** a resposta é 401 e nenhum token novo é emitido

#### Scenario: Teto absoluto da sessão

- **WHEN** `POST /auth/v1/session/renew` é chamado com um token de sessão curta (TTL 12h) cujo `iat_origin` tem 25 horas
- **THEN** a resposta é 401 e o usuário precisa autenticar de novo

#### Scenario: `iat_origin` é preservado através das renovações

- **WHEN** o token A (login às 10:00) é renovado gerando B, e B é renovado gerando C
- **THEN** o `iat_origin` de C é 10:00, igual ao de A, e não o instante da renovação

### Requirement: Purga de entradas expiradas do denylist

O sistema SHALL prover um job Sidekiq que apaga de `jwt_denylist` as linhas com
`exp` no passado, SHALL preservar as demais, e a mudança SHALL declarar a
dependência de agendamento em produção (`delivery-and-observability`).

#### Scenario: Linhas expiradas são apagadas

- **WHEN** `jwt_denylist` tem 3 linhas com `exp` de ontem e 2 com `exp` de amanhã, e o job de purga executa
- **THEN** restam exatamente as 2 linhas com `exp` de amanhã

#### Scenario: Purga não afeta revogação recente

- **WHEN** um token é revogado e o job de purga executa imediatamente depois
- **THEN** aquele token continua respondendo 401, porque sua linha ainda não expirou

### Requirement: Login com Google por redirect de página inteira

O sistema SHALL autenticar via `omniauth-google-oauth2` em `/users/auth/google_oauth2`
por redirect (não popup), criando ou vinculando o `User` no callback.

#### Scenario: Primeiro login com Google cria o usuário

- **WHEN** o callback do Google retorna `uid: "10938"`, `info.email: "novo@fabrica.com"`, `info.name: "Novo Operador"`, e-mail verificado, e não existe `User` com esse e-mail
- **THEN** um `User` é criado com `provider == "google_oauth2"`, `provider_uid == "10938"`, `name == "Novo Operador"` e um token é emitido

#### Scenario: Google vincula a conta existente em vez de duplicar

- **WHEN** já existe um `User` local com `email == "ana@fabrica.com"` e senha, e o callback do Google traz esse mesmo e-mail verificado com `uid: "77"`
- **THEN** o `User` existente recebe `provider == "google_oauth2"` e `provider_uid == "77"`, `User.where(email: "ana@fabrica.com").count == 1`, e o id do usuário autenticado é o mesmo de antes

#### Scenario: E-mail não verificado é recusado

- **WHEN** o callback do Google traz `email: "ana@fabrica.com"` com `email_verified` falso, e já existe um `User` com esse e-mail
- **THEN** nenhum vínculo é criado, nenhum token é emitido, e o redirect ao frontend carrega `#error=email_nao_verificado`

#### Scenario: `provider_uid` já pertence a outro usuário

- **WHEN** o callback traz `uid: "77"` já associado ao usuário X, mas com `info.email` do usuário Y
- **THEN** a autenticação resolve para o usuário X (chave é `provider/provider_uid`) e nenhum registro é duplicado

### Requirement: Entrega do token ao cliente por fragmento de URL

Após o callback do OAuth o sistema SHALL redirecionar para
`FRONTEND_AUTH_CALLBACK_URL` com o token no **fragmento** da URL, e SHALL NÃO
colocar o token em query string, corpo de página ou cookie legível.

#### Scenario: Token vai no fragmento

- **WHEN** o callback do Google conclui com sucesso
- **THEN** o `Location` do 302 tem a forma `https://app/auth/callback#access_token=…&expires_at=…` e a porção anterior ao `#` não contém o token

#### Scenario: Falha do OAuth também redireciona

- **WHEN** o usuário cancela o consentimento no Google e o OmniAuth chama a rota de falha
- **THEN** o redirect é para `https://app/auth/callback#error=acesso_negado` e nenhum token é emitido

### Requirement: Superfície pública de autenticação por allowlist ancorada

O sistema SHALL declarar as rotas públicas de autenticação como regex **ancoradas**
no allowlist de `api/root.rb`, e todo endpoint de auth que dependa de identidade
(`renew`, `DELETE session`, `me`) SHALL permanecer protegido.

#### Scenario: Login é público

- **WHEN** `POST /auth/v1/session` é chamado sem header `Authorization`
- **THEN** a requisição chega ao endpoint e responde 200 ou 401 conforme as credenciais, nunca 401 por ausência de header

#### Scenario: Renovação NÃO é pública

- **WHEN** `POST /auth/v1/session/renew` é chamado sem header `Authorization`
- **THEN** a resposta é 401 por falta de autenticação — a regex `^/auth/v1/session/?$` não casa esse caminho

#### Scenario: `GET /auth/v1/me` exige token

- **WHEN** `GET /auth/v1/me` é chamado sem header `Authorization`
- **THEN** a resposta é 401

#### Scenario: `X-Skip-Auth` não fura a autenticação

- **WHEN** `GET /auth/v1/me` é chamado com o header `X-Skip-Auth: 1` e sem token
- **THEN** a resposta é 401 (vedação entregue por `seal-template-baseline`, verificada aqui como regressão)

### Requirement: Limite de tentativas de login

O sistema SHALL limitar tentativas de `POST /auth/v1/session` a 10 por janela de
5 minutos, por par (IP, e-mail normalizado), respondendo 429 além disso.

#### Scenario: Décima primeira tentativa é bloqueada

- **WHEN** o mesmo IP faz 10 tentativas falhas para `ana@fabrica.com` em 1 minuto e faz a 11ª
- **THEN** a resposta é 429 e a senha nem chega a ser verificada

#### Scenario: O bloqueio é por e-mail, não global

- **WHEN** `ana@fabrica.com` está bloqueada por 11 tentativas e o mesmo IP tenta logar como `bruno@fabrica.com` com a senha correta
- **THEN** a resposta é 200 e o login de Bruno funciona

### Requirement: O token identifica, não autoriza

O payload do JWT SHALL conter apenas `sub`, `jti`, `exp`, `iat` e `iat_origin`, e
SHALL NÃO conter `workspace_id`, papel, permissões ou qualquer claim de
autorização. A decisão de acesso pertence a `authorization-policies` (D3) e ao RLS
de `workspace-tenancy` (D2).

#### Scenario: Payload não carrega escopo

- **WHEN** um token emitido no login é decodificado
- **THEN** suas chaves são exatamente `sub`, `jti`, `exp`, `iat`, `iat_origin` — sem `workspace_id`, sem `role`

#### Scenario: Autenticar não é ser membro

- **WHEN** um usuário autenticado que não é membro de nenhum workspace chama um endpoint de domínio
- **THEN** a resposta é 403 (não 200 e não 401): a identidade é válida, a autorização não existe

#### Scenario: Token de outro usuário não empresta identidade

- **WHEN** um token emitido para o usuário B é apresentado em `GET /auth/v1/me`
- **THEN** o corpo devolve os dados de B, jamais os de A, e nenhum parâmetro de requisição consegue trocar o sujeito
