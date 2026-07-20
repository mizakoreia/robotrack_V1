## Context

O legado é Firebase Auth: sessão gerida pelo SDK, `signInWithPopup` para Google,
persistência escolhida por `setPersistence(LOCAL|SESSION)` conforme o checkbox
"manter conectado", e revogação implícita porque o SDK renova ID tokens sozinho.
Nada disso existe do outro lado. O alvo é Devise + devise-jwt + OmniAuth sobre
Grape, onde:

- não há renovação automática — quem decide TTL e rotação somos nós;
- não há `setPersistence` — a escolha do meio de armazenamento é código nosso;
- Google não é popup, é **redirect de página inteira**, o que apaga toda a
  memória volátil da página no meio do fluxo;
- revogar um JWT exige estado no servidor, e a tabela para isso já existe morta.

O template ai9 nos entrega uma base parcialmente errada: `users.jti` com índice
único (assinatura da estratégia `JTIMatcher`), `jwt_denylist` sem estratégia
ligada, `jwt.dispatch_requests = []` e `jwt.revocation_requests = []` vazios,
`users.user_type_id` NOT NULL herdado de um domínio de cobrança que o RoboTrack
não tem, e um `before` em `api/root.rb` cuja allowlist é um array de regex.

## Goals / Non-Goals

**Goals**

1. Uma identidade por e-mail, com nome de exibição sempre presente e utilizável
   como fonte de `person.display_name` e de snapshots históricos.
2. Logout que realmente invalida o token apresentado, sem derrubar as outras
   sessões do mesmo usuário.
3. Um fluxo Google que atravessa duas navegações de página inteira sem perder o
   token de convite nem vazá-lo em query string.
4. Login que **nunca trava**, mesmo com `localStorage`/`sessionStorage` lançando
   exceção (Safari privado, bloqueadores, iframe com storage particionado).
5. Uma superfície de auth pública por allowlist ancorada, à prova de
   over-matching de regex.

**Non-Goals**

- Refresh tokens opacos com rotação de família e detecção de reuso. Fora do
  porte; ver "Perguntas em aberto".
- SSO corporativo, SCIM, provisionamento.
- Recuperação de senha por e-mail. A §3.1 não a descreve, e sem ela o e-mail
  transacional fica exclusivamente com `workspace-invitations`.

## Decisions

### D4.1 — Estratégia de revogação: `Denylist`, não `JTIMatcher`

Ligamos `Devise::JWT::RevocationStrategies::Denylist` ao model `JwtDenylist`
(`self.table_name = 'jwt_denylist'`), e `revocation_requests` passa a listar
`['DELETE', %r{^/auth/v1/session$}]`.

**Alternativa descartada — `JTIMatcher`** (que é o que `users.jti` com índice
único sugere): guarda um único `jti` por usuário, então emitir um token novo
invalida todos os anteriores. Um engenheiro de comissionamento usa celular no
chão de fábrica e desktop para revisar — `JTIMatcher` derruba um ao logar no
outro. Inaceitável para o perfil descrito em PRODUCT.md.

**Alternativa descartada — `Allowlist`**: exigiria uma linha por sessão viva e
uma leitura no banco a **cada** request autenticado. Denylist só é consultado
contra um conjunto pequeno (tokens revogados e ainda não expirados).

**Onde a invariante mora:** não no model. `jwt_denylist.jti` ganha **índice
único** (hoje é índice comum) — sem isso, uma revogação concorrente insere duas
linhas e o purge fica ambíguo. A verificação em si é o middleware do Warden, não
código nosso; nosso teste é de request, não de unidade.

**Consequência:** `users.jti` e `index_users_on_jti` são removidos. Deixar a
coluna é pior que removê-la: ela sinaliza uma estratégia que não está em uso e
alguém vai tentar preenchê-la.

### D4.2 — Tempo de vida do token amarrado ao "manter conectado"

`remember_me = true` → `exp` em **30 dias**. `remember_me = false` → **12 horas**.
Configurável por `JWT_TTL_REMEMBER_DAYS` / `JWT_TTL_SESSION_HOURS`. O TTL é
gravado no payload no momento do dispatch, a partir do parâmetro recebido; não é
o `jwt.expiration_time` global do devise-jwt (que é único). Implementamos
sobrescrevendo `jwt_payload` em `User` para carimbar `exp`.

O checkbox age em **duas camadas independentes e ambas necessárias**:
`exp` no servidor (um token roubado de sessão curta morre em 12h) e o meio de
armazenamento no cliente (§4.2: `sessionStorage` morre ao fechar a aba). Só a
camada do cliente não é segurança nenhuma; só a do servidor não cumpre "só até
fechar".

**Alternativa descartada — TTL único longo + revogação no logout**: quem fecha o
navegador sem clicar em "sair" (o caso comum no chão de fábrica, celular
compartilhado) deixaria um token de 30 dias vivo no disco.

**Alternativa descartada — par access/refresh token**: devise-jwt não modela
refresh token; seria um segundo sistema de sessão escrito à mão. O interceptor de
refresh single-flight que existe em `lib/api/client.ts` é do magic-link e sai com
ele; o interceptor 401 permanece, mas passa a **encerrar** a sessão em vez de
tentar renovar (ver D4.3).

### D4.3 — Renovação é explícita e rotaciona o `jti`

`POST /auth/v1/session/renew` aceita um token válido e devolve um novo, gravando
o `jti` antigo no denylist. É a única forma de estender uma sessão. Não há
renovação transparente em interceptor: um 401 significa "sessão acabou", limpa e
volta para `/entrar`. Isso mata a classe de bug em que o interceptor entra em
laço de refresh contra um token permanentemente inválido — comportamento que o
template hoje tem.

O cliente chama `renew` proativamente quando faltam menos de 25% do TTL, no
foco da janela. A renovação **não** pode ultrapassar o teto absoluto: o payload
carrega `iat_origin` (instante do login original) e o servidor recusa renovar
depois de `iat_origin + 2 × TTL`. Sem esse teto, uma sessão de 12h vira eterna.

**Onde a invariante mora:** endpoint + payload assinado. `iat_origin` está dentro
do JWT assinado, então o cliente não consegue esticá-lo.

### D4.4 — Google é redirect, e o convite vive em `sessionStorage`

Fluxo: `/convite/:token` (SPA) grava `robotrack.invite_token` em `sessionStorage`
e redireciona para `/entrar` → o usuário clica "Entrar com Google" → navegação de
página inteira para `/users/auth/google_oauth2` → Google → callback no backend →
redirect 302 para `FRONTEND_AUTH_CALLBACK_URL#access_token=…&expires_at=…` → o
SPA lê o **fragmento**, chama `history.replaceState` para apagá-lo da barra, lê o
convite do `sessionStorage` e o consome.

`sessionStorage` sobrevive a isso porque é por aba **e por origem**, e as duas
navegações de página inteira retornam à mesma aba e à mesma origem do SPA. A ida
até `accounts.google.com` não é a mesma origem, mas também não apaga a entrada.

**Alternativa descartada — carregar o token de convite no parâmetro `state` do
OAuth**: `state` pertence ao `omniauth-rails_csrf_protection`; sequestrá-lo
enfraquece a proteção CSRF do fluxo. Além disso o token do convite apareceria na
URL de redirect e, portanto, nos logs do Google e no `Referer`.

**Alternativa descartada — cookie**: o SPA e a API podem estar em origens
distintas em produção; cookie cross-site com `SameSite=None` é mais superfície
que benefício para guardar uma string por 20 segundos.

**Token entregue por fragmento, não por query string:** o fragmento não é enviado
ao servidor, não entra em log de acesso nem em `Referer`. É a mesma regra que
proíbe dado sensível em query string.

**Degradação:** se `sessionStorage` estiver bloqueado, o token vai para uma
variável de módulo em memória — que **não** sobrevive ao redirect do Google. Esse
caso é detectado no retorno (autenticou, mas não há convite guardado e a rota de
entrada foi `/convite/:token`) e resolvido pela UI mandando o usuário reabrir o
link do convite, já autenticado. O link é de uso único e ainda não foi consumido,
então reabri-lo funciona. Silenciosamente perder o convite seria o pior desfecho.

### D4.5 — E-mail é a chave de identidade; Google vincula, não duplica

Callback do Google: procura `User` por `provider/provider_uid`; se não achar,
procura por `email` (minúsculo) e **vincula** `provider`/`provider_uid` ao
usuário existente; se não achar, cria.

O vínculo por e-mail só ocorre se o Google declarar o e-mail **verificado**
(`auth.info.email_verified` ou `auth.extra.raw_info.email_verified` verdadeiro).
Sem essa condição, qualquer um que crie uma conta Google com o e-mail de outra
pessoa num domínio mal configurado assume a conta RoboTrack dela.

**Alternativa descartada — criar um segundo usuário**: D10 casa `Person` por
e-mail no aceite do convite; dois `User` com o mesmo e-mail produziriam
`Person` ambíguo, responsáveis duplicados em "Minhas Tarefas" e notificações
enviadas a metade das sessões.

**Onde a invariante mora:** `index_users_on_email` já é único (parcial, onde
`email IS NOT NULL`); tornamos `users.email` **NOT NULL** e o índice total, já que
o RoboTrack não tem login por telefone. `index_users_on_provider_and_provider_uid`
único já existe e impede dois usuários com o mesmo sujeito Google.

### D4.6 — Nome de exibição é obrigatório e normalizado na escrita

`users.name` já é NOT NULL. Acrescentamos **CHECK constraint**
`char_length(btrim(name)) >= 2` e normalização (`strip` + colapso de espaços
internos) em `before_validation`, para que o nome não seja `"   "`. No cadastro
por Google, `name` vem de `auth.info.name`; se vier em branco, cai para a parte
local do e-mail (`joao.silva@x.com` → `joao.silva`), nunca para string vazia.

**Onde a invariante mora:** CHECK no banco, não só validação. É o único jeito de
garantir que `author_name_snapshot` (D8) e as format strings de notificação e
auditoria (D14) nunca renderizem um vazio no meio de uma frase em pt-BR.

O RoboTrack não tem nome separado de exibição: um campo só, editável depois em
`workspace-settings`/perfil (fora deste escopo). Alterar o nome **não** reescreve
snapshots históricos já gravados — isso é intencional e é dito aqui porque é a
pergunta que sempre aparece depois.

### D4.7 — Senha: mínimo 6, e a ausência dela é expressa no banco

`config.password_length = 6..128` (§3.1). Não há como impor comprimento de senha
por constraint — o que chega ao banco é um hash bcrypt. O que **é** expresso no
banco: `encrypted_password` NOT NULL DEFAULT `''` (convenção Devise) mais um
CHECK — um usuário sem `provider` deve ter `encrypted_password <> ''`. Isso
impede criar por console um usuário local sem credencial nenhuma, que passaria a
existir mas nunca conseguiria entrar.

O mínimo de 6 é fraco. Compensamos com **rack-attack**: 10 tentativas de
`POST /auth/v1/session` por (IP, e-mail normalizado) em 5 minutos, 429 depois
disso, e resposta genérica idêntica para senha errada e e-mail inexistente, com
`User.new.valid_password?` chamado no caminho negativo para não vazar a
existência da conta pela diferença de tempo.

### D4.8 — Superfície pública é allowlist **ancorada**

As rotas novas entram no array de regex do `before` de `api/root.rb` como
`%r{^/auth/v1/session/?$}`, `%r{^/auth/v1/registration/?$}`,
`%r{^/users/auth/google_oauth2}`, `%r{^/users/auth/google_oauth2/callback}`.

O risco concreto: `%r{^/auth/v1/session}` **sem** âncora final casaria também
`/auth/v1/session/renew`, tornando pública a renovação — qualquer um estenderia
sessão sem token. Há um teste dedicado a isso.

`DELETE /auth/v1/session` **não** é público: precisa do token para saber qual
`jti` revogar.

### D4.9 — Uma fonte de verdade para o token no cliente

O template guarda o token em `localStorage['token']` **e** em
`localStorage['auth-storage']` (zustand `persist`), sincronizados manualmente.
Passa a existir um único dono: `authStore`, com `storage` **injetado em tempo de
criação** conforme o "manter conectado" (`localStorage` ou `sessionStorage`), e
um `safeStorage` que envolve toda operação em `try/catch` e cai para um `Map` em
memória. `lib/api/client.ts` lê o token de `useAuthStore.getState()`, nunca do
`localStorage`.

**Timeout de segurança (§3.1):** o handshake com o storage roda numa `Promise`
que corre contra um timer de **1500 ms**. Se o timer vencer, o login segue com
storage em memória e dispara um toast `sonner`: "Sua sessão não vai persistir
neste navegador." O login **não** aguarda o storage para navegar.

## Risks / Trade-offs

- **Denylist cresce sem limite.** Mitigação: `Auth::PurgeJwtDenylistJob` diário
  apaga `exp < now()`. Se o Sidekiq agendado não existir em produção, a tabela
  cresce silenciosamente e o `SELECT` por `jti` degrada. Dependência explícita de
  `delivery-and-observability`.
- **30 dias é longo para um token não revogável por dispositivo.** Um dispositivo
  perdido só é cortado se alguém souber revogar. Não há tela de "sessões ativas"
  neste escopo. Mitigação parcial: `authorization-policies` remove acesso ao
  workspace na hora (o token continua válido, mas não autoriza nada) e
  `realtime-collaboration` faz a revogação chegar à sessão aberta.
- **Redirect quebra o app instalado.** Num PWA em modo standalone, o redirect
  para o Google pode abrir o navegador do sistema e voltar fora do app. Precisa
  ser exercitado em Android/iOS instalados; anotado como dependência de teste
  para `offline-pwa` e `quality-and-accessibility`.
- **`user_type_id` NOT NULL bloqueia o cadastro.** Removemos o NOT NULL e a FK
  aqui porque nosso `POST /auth/v1/registration` não funciona sem isso. A remoção
  da tabela `user_types` e do restante do domínio de cobrança é de
  `seal-template-baseline`; se as duas mudanças colidirem na mesma migration de
  `users`, a nossa é a que roda primeiro (Onda 1 depende da Onda 0 já aplicada).
- **Migration destrutiva** (`remove_column :users, :jti`, `change_column_null`).
  Precedida obrigatoriamente de dump lógico de `users` e escrita como `up`/`down`
  reversível.
- **Trocar Firebase Auth por senha própria transfere risco para nós**: hash,
  rate limit e vazamento de existência de conta passam a ser responsabilidade do
  projeto. As três estão endereçadas em D4.7, mas a superfície é nova.

## Plano de migração

1. Dump lógico de `users` (`pg_dump -t users --data-only`) antes de qualquer DDL.
2. Migration aditiva: `encrypted_password`, CHECKs de `name` e de credencial,
   `email` NOT NULL + índice único total, índice único em `jwt_denylist.jti`.
3. Migration destrutiva, separada: `remove_column :users, :jti`,
   `change_column_null :users, :user_type_id, true`, remoção da FK.
4. Não há backfill de senha. O RoboTrack não tem base instalada; qualquer usuário
   pré-existente do template fica em estado "só Google" até definir senha, e é o
   CHECK de D4.7 que garante que ninguém fique sem nenhum dos dois caminhos.

## Perguntas em aberto

- **Recuperação de senha.** A §3.1 não menciona. Sem ela, quem esquece a senha e
  não usa Google fica travado e depende de intervenção manual. Recomendação:
  escopar `recoverable` numa mudança própria antes do primeiro uso em produção.
- **Teto de renovação (D4.3) em 2 × TTL** é uma escolha nossa; a spec é omissa.
  60 dias de sessão contínua para um usuário que marcou "manter conectado" pode
  ser demais para o cliente automotivo. Parametrizável, valor a confirmar.
- **Um usuário só-Google que depois quer senha** não tem caminho neste escopo
  (definir senha exigiria `recoverable` ou uma tela de perfil). Aceito por ora.
