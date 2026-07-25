# PLANO — invite-by-code (convite por CÓDIGO)

> **Status: DOCUMENTO DE PLANEJAMENTO.** Não é uma change OpenSpec ainda — não há
> `proposal.md`/`design.md`/`specs/`/`tasks.md` e o gerador NÃO foi rodado. Este
> arquivo existe para o dono decidir as questões em aberto (§F) antes de a change
> nascer. Quando aprovado, o método da casa começa pelo `G0`/`EXECUCAO.md`
> reconciliando este plano com a realidade do repo.
>
> **DECISÃO DO DONO JÁ TOMADA (§F.4):** o código é **por-convite / por-e-mail** — cada
> convite (um e-mail, um papel) gera o próprio código, ligado àquele e-mail, uso único.
> **NÃO** é um código único/reutilizável de workspace. Restam abertas **§F.1** (coexistir
> com o link), **§F.2** (formato/comprimento) e **§F.3** (quem pode convidar).

## Resumo em uma frase

Além do link `/convite/:token` que já existe, o mesmo convite passa a ter um **código
curto e legível** (ex.: `4K7P-9QMX`) que a pessoa **digita** (com o e-mail) numa seção
"Tenho um convite" da tela de entrada — pensado para o operador de chão de fábrica no
próprio celular, para quem digitar é mais prático que abrir um link.

## Recomendação principal (leia isto primeiro)

O código deve ser uma **representação adicional do MESMO convite**, não um segundo
registro. É uma nova coluna na linha `invitations` existente (guardada **hasheada**,
nunca em claro), com sua própria unicidade e sua própria janela de expiração curta. O
caminho de aceite **reusa** o `AcceptService` inteiro que já existe — o mesmo `SELECT
... FOR UPDATE`, as mesmas 6 validações, a mesma resolução de `Person`, o mesmo
one-shot. A única diferença é **como a linha é encontrada**: por `invitation_by_code`
em vez de `invitation_by_token`.

Isto mantém intacta a invariante que é o coração da segurança do convite: **o e-mail do
convite tem de ser idêntico ao e-mail autenticado**. Com ela, "adivinhar o código" não
concede acesso — o atacante ainda precisaria controlar a conta de e-mail do convidado.
O código curto, sozinho, **não é credencial suficiente**; é um localizador de uma linha
cuja consumação continua exigindo autenticação como o destinatário.

E o mais importante do documento, **agora decidido pelo dono (§F.4): o código é
por-convite / por-e-mail** — a representação adicional do MESMO registro `invitations`,
já ligado a um e-mail específico. **NÃO** se constrói a variante "código de workspace
reutilizável que qualquer um usa para pedir entrada": ela quebraria a invariante de
e-mail e seria um modelo de ameaça inteiramente diferente — na prática o "convite por
link aberto" que o `design.md` da `workspace-invitations` **rejeitou de propósito** como
não-objetivo. Fica fora desta change e de qualquer change futura sem uma decisão nova e
explícita.

---

## Reconciliação com o que já existe (a base madura)

Levantado lendo `workspace-invitations` (proposal/design/specs/EXECUCAO),
`authorization-policies`, o `structure.sql`, o `rack_attack.rb`, a `AuthPage` e o fluxo
de aceite. O que já está construído e que este plano REUSA:

**Banco** (`backend/db/structure.sql`, migrations `20260721120001..05`):
- `invitations`: `id uuid`, `workspace_id NOT NULL`, `token text` único, `email`
  (`CHECK email = lower(email)`, `CHECK ≤254`), `role invitation_role` (enum só
  `view`/`edit`), `created_by_person_id`, `expires_at` (`DEFAULT now()+7d`), `used_at`,
  `used_by_user_id`, `chk_invitations_consumption` (os dois campos de consumo juntos ou
  ambos nulos). `FORCE ROW LEVEL SECURITY`.
- RLS `tenant_isolation`: `USING (workspace_id = app.current_workspace_id OR token =
  app.invitation_token)`, `WITH CHECK` só de workspace. **É este segundo ramo do
  `USING` que permite ler a linha por token exato sem contexto de workspace, sem
  `BYPASSRLS`** — o padrão que o código vai espelhar.
- `invitation_by_token(text)` `SECURITY DEFINER`: faz `set_config('app.invitation_token',
  …, true)` e retorna a linha do token. É o único jeito de a rota pública achar o convite
  pré-login.
- Unicidades: `index_invitations_on_token` (único), `index_invitations_pending_unique_per_email`
  (`(workspace_id, email) WHERE used_at IS NULL` — 1 pendente por e-mail/workspace),
  `idx_memberships_one_per_invitation` (segunda camada anti-duplo-consumo).
- `purge_expired_invitations()` `SECURITY DEFINER` (só pendentes expirados há >30d).

**Model** `backend/app/models/invitation.rb`: `TOKEN_PREFIX='rt_inv_'`,
`generate_token` = `"rt_inv_#{SecureRandom.urlsafe_base64(32)}"`, callbacks
`assign_token`/`assign_expiry` só `on: :create`, `scope :pending`, `status`
(`used`>`expired`>`pending`), `email_masked`. **É o gancho natural para um
`assign_short_code on: :create` ao lado do `assign_token`.**

**Services** `backend/app/services/invitations/`:
- `accept_service.rb`: `lookup_by_token` → `SELECT * FROM invitation_by_token($token)`;
  `consume` abre `Tenant.with(workspace_id, user_id)`, `SET LOCAL statement_timeout`,
  `Invitation.lock('FOR UPDATE').find_by(id:)`, `validate!` (6 validações, cada uma com
  seu código HTTP), `resolve_person`, `Membership.create!`, `update!(used_at,
  used_by_user_id)`. Rejeições são exceções (não `return`) por causa do commit-on-return.
  `reject_unexpected_parameters!` bloqueia `role` no corpo.
- `create_service.rb`: guard `InvitationPolicy.create?`, `ALLOWED_ROLES`, savepoint
  `requires_new: true`, `RecordNotUnique → invitation_already_pending` (409), resolve a
  `Person` do criador (exigida pela FK composta).
- `preview_service.rb`: `lookup` via `invitation_by_token`, monta um `Invitation.new` só
  para derivar `role`/`email_masked`/`status`, `workspace_name` dentro de `Tenant.with`.
- `revoke_service.rb`: `destroy!` real (204), 422 se já consumido.

**Endpoints Grape**:
- `api/v1/invitations.rb` (DOMÍNIO, exige `X-Workspace-Id`): `GET`/`POST`/`DELETE :id`,
  cada rota com `route_setting :policy, policy: 'InvitationPolicy', action: …`.
- `api/v1/invitation_tokens.rb` (POR TOKEN, isento de tenant): `before` seta
  `Referrer-Policy: no-referrer`; `GET :token` (público, `PreviewService`); `POST
  :token/accept` (`route_setting :policy, access: :authenticated`).
- `api/root.rb`: `PUBLIC_ROUTES` (regex, ciente de método) inclui `['GET,
  %r{^/api/v1/invitations/[^/]+/?$}]`; `TENANT_EXEMPT_ROUTES` inclui o `GET` de preview e
  o `POST …/accept`; o `DELETE …/:id` fica de fora de propósito (rota de domínio).
- Entities `api/entities/invitation.rb` (expõe `invite_url` via `AppUrl.invite_url`,
  **nunca o token cru**) e `invitation_preview.rb`.

**Autorização** `backend/app/policies/`: `InvitationPolicy` mapeia `create?/index?/
destroy?` → `:manage_membership`. `PermissionMatrix.ACTIONS[:manage_membership] =
[:owner]` — **só o dono convida hoje**. Mudar isto é a questão §F.3.

**Rate limiting** `backend/config/initializers/rack_attack.rb`: store Redis com fallback
memória; safelist localhost; `invitations/accept-ip` 10/10min, `invitations/accept-session`
10/10min (hash do bearer), `invitations/preview-ip` 20/10min; `throttled_responder` loga
só `token_sha256[0,12]`, nunca o token em claro; 429 com `Retry-After`.

**Frontend**:
- `features/auth/InviteRoute.tsx` (rota `/convite/:token`): captura o token, marca
  entrada por convite (`oauthState.markInviteEntry`), `inviteStore.capture`, troca a URL
  (`replaceUrl`), e — se já autenticado — `consumeInvite(token)`; senão faz o preview e
  manda para `/entrar`.
- `features/auth/AuthPage.tsx` (rota `/entrar`): form único login/cadastro; no sucesso
  `await handleInviteAfterAuth()` → `navigate('/')`. **O `email` já é estado local aqui.**
- `lib/auth/session.ts`: `consumeInvite(token)` (limpa o token ANTES do await; mapa de
  erros por CÓDIGO do servidor → `inviteText.*`; seleciona o workspace aceito);
  `handleInviteAfterAuth()` (dispara uma vez). Chamado em `AuthPage` e `OAuthCallbackPage`.
- `lib/auth/invite.ts`: `inviteStore.capture/read/clear` em `sessionStorage`
  (`robotrack.invite_token`, via `safeStorage`).
- `lib/api/endpoints.ts`: `invitationsApi.{list,create,revoke,preview,accept}`;
  `InvitationDTO` (`…, invite_url`), `InvitationPreviewDTO`
  (`workspace_name, role, email_masked, expires_at, status`).
- `lib/i18n/invitations.ts` (`inviteText`): TODOS os literais de convite; o CI proíbe
  strings de convite fora daqui.
- `features/team/{TeamPanel,InviteDialog}.tsx`: o dono cria o convite e copia o link;
  a lista de pendentes mostra `invite_url` + status. Keys literais `['ws', wsId,
  'members'|'invitations']`.

**Regras da casa que este plano respeita** (CONTINUIDADE "regras que não regridem" +
DESIGN + PRODUCT):
- App conecta como `robotrack_app` **sem BYPASSRLS**; isolamento é **RLS forçada**;
  invariantes moram no banco; vazamento cross-tenant = **404**.
- Varreduras só crescem: rota nova nasce declarando policy e entrando no gerador
  cross-tenant no mesmo grupo.
- Campo nativo precisa de **fundo temático** (regra F); alvo de toque **≥32px** (luva);
  contraste AA medido no CI; tema não segue o SO.
- Locators E2E ancorados por região/diálogo + `{ exact: true }`.

---

## A) MODELO DE DADOS — o código convive com o token

### A.1 Uma coluna na mesma linha, não um segundo registro

Migration **puramente aditiva** sobre `invitations`:

| Coluna | Tipo | Papel |
|---|---|---|
| `code_hash` | `text` | **HMAC-SHA256(code)** com pepper de servidor. Nunca o código em claro. Único (índice parcial). |
| `code_expires_at` | `timestamptz NULL` | Expiração PRÓPRIA do código, mais curta que a do link (ver B). NULL = convite sem código. |
| `code_attempts` | `smallint NOT NULL DEFAULT 0` | Contador de tentativas falhas contra ESTA linha (lockout, ver B). |
| `code_locked_at` | `timestamptz NULL` | Trava do código após N falhas. |

Por que o `code_hash` e não o código em claro: o token de 256 bits **é** um segredo (é
guardado em claro porque adivinhá-lo é inviável por entropia). O código curto é de baixa
entropia — se o banco vazar, um código em claro é acesso pronto; um código hasheado com
**pepper** (HMAC com segredo de servidor fora do banco) não é reconstruível offline sem
o pepper. HMAC (e não bcrypt) porque o lookup precisa ser **determinístico** para
indexar e achar a linha por igualdade — bcrypt salga por linha e exigiria varredura.
O pepper vem de `Rails.application.credentials`/ENV (registrar no `env_schema.rb` de
`delivery-and-observability`), nunca versionado.

Índices e integridade:
- `CREATE UNIQUE INDEX index_invitations_on_code_hash ON invitations (code_hash) WHERE
  code_hash IS NOT NULL` — parcial, porque a maioria dos convites (via link) não terá
  código.
- Reusar a unicidade de pendente por e-mail que já existe — o código herda a mesma linha,
  então não há convite pendente duplicado a criar.

RLS e lookup pré-login (espelha exatamente `invitation_by_token`):
- Estender a policy `tenant_isolation` de `invitations` com um terceiro ramo no `USING`:
  `OR code_hash = NULLIF(current_setting('app.invitation_code_hash', true), '')`. O
  `WITH CHECK` continua só de workspace (ler por código não autoriza escrever).
- Nova função `invitation_by_code(text)` `SECURITY DEFINER`: recebe o código em claro,
  computa o HMAC **dentro da função** (ou recebe já o hash do app — decidir no G1; recebê-lo
  já hasheado evita o pepper morar no banco), faz `set_config('app.invitation_code_hash',
  <hash>, true)` e `RETURN QUERY SELECT * FROM invitations WHERE code_hash = <hash>`.
  Recomendação: **o app computa o HMAC** (pepper só na app) e passa o hash à função; a
  função só seta a variável de sessão e seleciona. Assim o pepper nunca entra no banco.

### A.2 Formato: comprimento, alfabeto, entropia

- **Alfabeto:** Crockford Base32 — `0123456789ABCDEFGHJKMNPQRSTVWXYZ` (32 símbolos,
  **exclui I, L, O, U**), resolvendo o pedido de "evitar ambíguos O/0/I/1". Sempre
  MAIÚSCULAS; a entrada do usuário é normalizada (upper, remover hífen/espaço, mapear
  `I→1`, `O→0`, `L→1` na leitura por tolerância).
- **Comprimento:** **8 caracteres**, exibidos como `XXXX-XXXX` (o hífen é cosmético,
  removido na normalização). Entropia = 32⁸ = **2⁴⁰ ≈ 1,1 × 10¹²**.
- Geração criptográfica: `SecureRandom` sobre o alfabeto (rejeitar viés de módulo).
  Colisão tratada por retry no `RecordNotUnique` do índice único.

**Por que 8 e não mais/menos:** 8 é o teto confortável de digitação no celular com luva;
2⁴⁰ é grande o bastante para que, **combinado com** rate-limit + lockout + expiração
curta + a exigência de e-mail (§B), o custo de adivinhação online seja proibitivo. Não é
grande o bastante para dispensar essas defesas — e é exatamente essa a diferença com o
token (§B). Se o dono priorizar segurança sobre ergonomia, 10 chars (2⁵⁰) é o degrau
seguinte; registrado como knob na questão §F.2.

---

## B) SEGURANÇA — o ponto central (um código curto é credencial fraca e ENUMERÁVEL)

### B.1 Modelo de ameaça: código vs. link, lado a lado

| Vetor | Link (token 256 bits) | Código (8 chars, 2⁴⁰) |
|---|---|---|
| Adivinhação por entropia | **Inviável** (2²⁵⁶). O rate-limit existe só porque o accept é caro. | **Concebível em escala.** Exige defesa ATIVA, não só entropia. |
| Reconhecível/estruturado | Não (prefixo `rt_inv_` + aleatório) | Sim — espaço pequeno e enumerável em ordem. |
| Vazamento por referrer/histórico | Sim (mitigado: `replaceState`, `no-referrer`) | Menor (o código não vai na URL; é digitado). |
| Se o banco vaza | Token em claro = acesso | `code_hash` com pepper ≠ reconstruível offline |
| **Proteção comum decisiva** | **e-mail idêntico ao autenticado** | **e-mail idêntico ao autenticado** |

O ponto que não pode ser subestimado, mas também não pode ser exagerado: **enumerar o
código não basta**. Para consumir, o atacante precisa (1) acertar um código pendente,
(2) e estar **autenticado como o e-mail do convite**. Como a consumação roda logada e a
condição 5 do `validate!` compara `invitation.email == current_user.email`, adivinhar o
código de um convite para `joao@fabrica.com` é inútil para quem não controla a conta do
João. **O vínculo com o e-mail autenticado é a proteção que transforma "adivinhe o
código" em "adivinhe o código E controle a conta-alvo".**

O risco REAL da enumeração, então, não é o aceite — é o **preview**. Se um preview por
código devolvesse `workspace_name`/`email_masked`/`role` para qualquer código adivinhado,
um atacante colheria uma lista de alvos de phishing. Defesa (B.4): o preview por código
**exige o par (código + e-mail)** e só responde quando os dois casam.

### B.2 Defesas exigidas (que o token de 256 bits não exigia)

1. **Hashing com pepper** (A.1) — código nunca em claro, nem no banco nem em log.
2. **Expiração curta e própria** — `code_expires_at` **default 48h** (recomendado; knob),
   contra os 7 dias do link. A janela curta é a alavanca mais barata contra enumeração de
   segredo de baixa entropia: encolhe o tempo em que qualquer código adivinhado vale algo.
   Caso de uso do dono (onboarding no galpão) é imediato — 48h sobra.
3. **Lockout por convite** — após **5** tentativas falhas contra a MESMA linha (código
   certo, e-mail errado; ou tentativas repetidas de par), seta `code_locked_at` e passa a
   responder `423 invitation_code_locked`. Destrava só reemitindo (o dono gera novo
   código). Incrementado numa transação curta no caminho de falha do lookup-por-código.
   *Limite:* lockout-por-linha só morde quando o código existe; contra adivinhação CEGA
   (código errado → nenhuma linha) valem os tetos 4/5 abaixo.
4. **Rate-limit por IP e por e-mail** nos endpoints por código, **mais apertado** que os
   do token: `code-accept-ip` 5/10min, `code-preview-ip` 10/10min, e um teto por
   **e-mail submetido** (5/10min) para atacar o eixo que o IP não cobre.
5. **Teto GLOBAL de falhas por código** — um throttle rack-attack com discriminador
   constante (ex.: total de `invitation_by_code` que não casam, N/min no sistema) porque
   um atacante roda IPs. Com 2⁴⁰ de espaço e um teto global de, digamos, algumas centenas
   de tentativas/min, esgotar o espaço leva tempo geológico; combinado com expiração de
   48h, a probabilidade de acertar um código VÁLIDO na janela é desprezível.
6. **Uso único atômico** — **reusa o `SELECT ... FOR UPDATE`** já existente. O código
   localiza a linha; a consumação é o mesmo `consume` do `AcceptService`. Duas corridas
   pelo mesmo código serializam no lock; a segunda relê `used_at` e recebe `409
   invitation_already_used`. O `idx_memberships_one_per_invitation` continua sendo a rede.
7. **Invariante de e-mail mantida** — condição 5 do `validate!` inalterada. A `Membership`
   nasce com o `role` LIDO DA LINHA, nunca do cliente (o corpo do accept-por-código
   também rejeita `role`).
8. **Log sem código em claro** — o `throttled_responder` e o scrubber logam só
   `code_sha256[0,12]` (o `token_sha256` já existe; adicionar o análogo para código).
   Igualdade de tempo de resposta entre código inexistente e existente (sem canal lateral
   de temporização), como o preview de token já garante.

### B.3 O que NÃO fazer

- **Não** aceitar código sem estar autenticado. O código é localizador; a autenticação
  como o e-mail do convite é a autorização. (Fluxo: digita na entrada → autentica →
  consome; §D.)
- **Não** aceitar `role` no corpo do accept-por-código (mesma rejeição explícita `422
  unexpected_parameter` do accept-por-token).
- **Não** reintroduzir vazamento de existência: `423 locked`/`404 not_found`/`409` só
  para pares que já casaram e-mail+código; um código cego devolve o genérico sem
  distinguir "existe mas travado" de "não existe".

### B.4 Preview por código exige o par (código + e-mail)

Diferente do preview por token (que responde só com o token, porque o token já É o
segredo forte), o preview por código **só responde se `email` submetido == `email` do
convite**. Sem o e-mail certo, resposta genérica (mesma para inexistente/errado). Isso
mata a colheita de alvos por enumeração de códigos.

---

## C) FLUXO BACKEND

Princípio: **um caminho novo de LOOKUP, tudo o mais reusado.**

- **Model** (`invitation.rb`): `SHORT_CODE_ALPHABET`, `SHORT_CODE_LEN=8`,
  `CODE_VALIDITY=48.hours`; `self.generate_short_code`; `self.code_hash_for(code)` (HMAC
  com pepper); callback `assign_short_code on: :create` **condicional** (só quando o
  convite é criado com código — ver §F.1); `normalize_code(input)` (upper, tira
  hífen/espaço, mapeia ambíguos); helper `code_masked`/`code_status`.
- **CreateService**: se o convite deve ter código (§F.1), gera o código em claro UMA vez,
  guarda o `code_hash`, seta `code_expires_at`, e **retorna o código em claro na
  resposta** (única vez que ele existe fora do request do dono — a entity nunca reexpõe o
  claro depois, igual ao token que só vive no `invite_url`). `RecordNotUnique` no
  `code_hash` → retry de geração.
- **AcceptService**: novo `lookup_by_code(code, email)` que (1) checa lockout/expiração do
  código, (2) computa o HMAC no app, (3) `SELECT * FROM invitation_by_code($hash)`, (4)
  confere `email` submetido == `invitation.email` (senão incrementa `code_attempts` e
  responde genérico), e então chama o **mesmo `consume`** de hoje. Zero duplicação da
  lógica de transação/validação/pessoa.
- **PreviewService**: novo `preview_by_code(code, email)` exigindo o par (§B.4).
- **Endpoints**: **rota nova dedicada** (não sobrecarregar `:token`), porque o corpo
  agora carrega `email` e o método é `POST` mesmo no preview (o e-mail não vai em query
  string — regra de privacidade da casa):
  - `POST /api/v1/invitations/code/preview` `{ code, email }` → público, tenant-exempt.
  - `POST /api/v1/invitations/code/accept` `{ code, email }` → autenticado, tenant-exempt,
    `route_setting :policy, access: :authenticated`, `Referrer-Policy: no-referrer`.
  - Registrar as duas em `PUBLIC_ROUTES`/`TENANT_EXEMPT_ROUTES` de `root.rb` e no gerador
    cross-tenant (varredura só cresce). `DELETE`/`create` continuam nas rotas de domínio.
- **Entity**: `api/entities/invitation.rb` ganha `short_code` **só na criação** (o dono
  copia) e `code_status`/`code_expires_at` na listagem de pendentes (nunca o `code_hash`,
  nunca o claro depois da criação).
- **rack_attack**: novos throttles (§B.2.4/5) por PATH das rotas `/code/*`, discriminando
  por IP, por e-mail do corpo e um teto global; `throttled_responder` loga `code_sha256`.
- **Purge**: `purge_expired_invitations()` já apaga pendentes expirados há >30d — cobre a
  linha inteira. Considerar limpar `code_hash`/`code_expires_at` (anular o código) quando
  só o CÓDIGO expira mas o link ainda vale (48h < 7d): decisão G3.

---

## D) FLUXO FRONTEND

A seção "Tenho um convite" vive na **tela de entrada** (`AuthPage`, `/entrar`), porque é
onde o operador chega no celular. O link continua existindo como alternativa (a rota
`/convite/:token` fica intocada).

- **`lib/api/endpoints.ts`**: `invitationsApi.previewByCode({ code, email })` e
  `acceptByCode({ code, email })`, espelhando `preview`/`accept`. Novo campo `short_code?`
  no `InvitationDTO` (preenchido só na criação).
- **`lib/auth/invite.ts`**: `inviteStore` ganha `captureCode({ code, email })` /
  `readCode()` — análogo ao token, para sobreviver ao redirect do Google OAuth. Chave
  `robotrack.invite_code` no `sessionStorage` via `safeStorage`.
- **`AuthPage.tsx`**: seção nova (um `<details>`/collapsible "Tenho um código de
  convite", abaixo do bloco Google) com dois campos — **E-mail** (reusa `EMAIL_RE` e pode
  pré-preencher o `email` já existente no estado) e **Código** (`inputmode` texto,
  `autocapitalize=characters`, `maxLength` com máscara `XXXX-XXXX`). Ação:
  - Se **já autenticado** (raro nesta tela): `consumeInviteByCode(code, email)` direto.
  - Se **não**: `inviteStore.captureCode`, marca entrada por convite, e segue o login/
    cadastro; após auth, `handleInviteAfterAuth` dispara `consumeInviteByCode`.
- **`lib/auth/session.ts`**: `consumeInviteByCode(code, email)` **reusa o mesmo mapa de
  erros por código** de `consumeInvite` (expired/already_used/already_member/
  email_mismatch/person_conflict/404/genérico) + os novos `invitation_code_locked` (423) e
  o genérico de par inválido. `handleInviteAfterAuth` passa a checar token **e** código.
- **`lib/i18n/invitations.ts`**: novos literais (`codeSectionTitle`, `codeLabel`,
  `codePlaceholder`, `codeLocked`, `codeInvalidPair`, `codeAccepted`, …). O CI exige que
  strings de convite morem aqui.
- **`features/team/InviteDialog.tsx`**: ao criar, exibir **o código** (`XXXX-XXXX`, fonte
  tabular, botão "Copiar código" com o mesmo fallback do "Copiar link") ao lado do link —
  as duas representações do mesmo convite. Deixar claro que o código expira antes do link.
- **`features/team/TeamPanel.tsx`**: `LinhaConvite` mostra o `code_status` (ativo/
  expirado/travado) junto do link.

**Acessibilidade e toque (DESIGN/PRODUCT):**
- Campos com **fundo temático** (`bg-bg-main`/`text-text-main`/`border-input`) — regra F,
  senão branco-sobre-branco no escuro.
- Alvos **≥32px** (luva). Código em `.tabular` para não dançar largura.
- Erros por `aria-live="polite"` no campo certo (padrão do `AuthPage`), nunca "erro
  inesperado" genérico quando há código específico.
- Contraste AA (já medido no CI). Máscara/normalização tolerante (aceitar minúsculas,
  espaços, ambíguos) porque digitar no galpão erra.

**Estados de erro** (todos com texto próprio, discriminados pelo código do servidor):
código inválido/par não casa · expirado (`code_expires_at`) · já usado · tentativas
excedidas (423, "peça um novo código ao responsável") · e-mail autenticado ≠ e-mail do
convite (reusa o fluxo "sair e entrar com outra conta") · offline ("conecte-se para
aceitar").

---

## E) COMO ISSO VIRA UMA CHANGE OpenSpec

**Change NOVA: `invite-by-code`.** Não emenda `workspace-invitations` — ela está completa
e publicada, e o padrão da casa é uma change por capacidade, ff a `main` por grupo. Uma
emenda reabriria specs publicadas; uma change nova ADICIONA capacidade e declara
`workspace-invitations` como dependência (consumida, não modificada).

Capacidades/requisitos esboçados (a detalhar no `proposal.md`/`specs/` quando aprovado):

- **`invite-by-code`** (nova capacidade):
  - *Código como representação adicional do convite* — coluna hasheada, unicidade,
    expiração própria curta, geração cripto no alfabeto sem ambíguos.
  - *Lookup por código sem contexto de workspace* — `invitation_by_code` `SECURITY
    DEFINER` + ramo RLS, sem `BYPASSRLS`.
  - *Aceite por código atômico* — reusa `FOR UPDATE`, 6 validações, resolução de `Person`,
    one-shot; exige e-mail autenticado idêntico.
  - *Preview por código exige o par (código+e-mail)*.
  - *Endurecimento contra enumeração* — rate-limit apertado (IP/e-mail/global), lockout
    por convite, hashing com pepper, log sem claro, expiração curta.
  - *Entrada por código na tela de login* — seção "Tenho um convite", sobrevive ao OAuth,
    acessível e com alvo de toque de luva.

**Mapa de grupos (método da casa — `G0` reconciliação, ff a `main` por grupo):**

| Grupo | Entrega | Verifica (0 falhas) |
|---|---|---|
| **G0** | `EXECUCAO.md` reconciliando ESTE plano com a realidade; decisões §F já respondidas pelo dono. | `validate --strict` do esqueleto. |
| **G1** | Migration aditiva (`code_hash`/`code_expires_at`/`code_attempts`/`code_locked_at`, índice único parcial, `invitation_by_code`, ramo RLS); model (`generate_short_code`, `code_hash_for`, `assign_short_code`, `normalize_code`). | Specs de constraint/unicidade; RLS-por-código acha a linha sem workspace e NÃO por listagem; `schema_guard`; geração 10k códigos distintos, alfabeto sem I/L/O/U. |
| **G2** | Backend do aceite/preview por código (services reusando `consume`; rotas `/code/preview` e `/code/accept`; entity com `short_code` só na criação; allowlist + gerador cross-tenant). | Request specs espelhando os do token (6 validações, corrida, mismatch, expirado, usado, already_member, `role` no corpo → 422); preview exige par; cross-tenant 404. |
| **G3** | Endurecimento (rate-limit IP/e-mail/global, lockout por convite, pepper no `env_schema`, log `code_sha256`, timing-equality; purge/anulação do código). | Specs de rate-limit e lockout; log-scrubber (nunca código em claro); custo de brute-force documentado no EXECUCAO. |
| **G4** | Frontend (endpoints, `inviteStore` de código, seção na `AuthPage`, `consumeInviteByCode` reusando o mapa de erros, i18n, `InviteDialog`/`TeamPanel` exibindo o código). | `vitest` (form, normalização, estados de erro, sobrevive ao OAuth); regra F (fundo temático); alvo ≥32px; `tsc`/`lint`/sweeps. |
| **G5** | Docs (CONTINUIDADE/VALIDACAO/DESIGN se tocar token/primitivo), E2E do fluxo por código (Chromium aqui; WebKit/CI handoff), decisões registradas. | E2E verde em Chromium; `validate --strict`; docs sem afirmação falsa. |

Cada grupo: aplicar → specs dirigidos 0 falhas → `- [x]` em `tasks.md` → `validate
--strict` → **atualizar docs** → um commit `G<n>:` → ff `main` + push → resumo pt-BR ao
dono.

---

## F) QUESTÕES (decididas + em aberto)

> **§F.4 já DECIDIDA pelo dono** (ver abaixo). §F.1, §F.2 e §F.3 seguem em aberto — cada
> uma com minha recomendação.

### F.1 O código SUBSTITUI o link ou COEXISTE?
**Recomendação: COEXISTE.** O link continua sendo o caminho de 256 bits (o mais forte) e
a base de todo o fluxo já testado; o código é uma conveniência adicional para o galpão.
Todo convite tem link; o código é **opcional por convite** (o dono marca "gerar código"
ao criar, ou é sempre gerado — subquestão menor). Substituir o link seria abrir mão de um
mecanismo forte e maduro em favor de um mais fraco — sem ganho.

### F.2 FORMATO/COMPRIMENTO do código
**Recomendação: 8 caracteres, Crockford Base32 (sem I/L/O/U), exibido `XXXX-XXXX`,
expiração própria de 48h, guardado como HMAC com pepper.** 2⁴⁰ + as defesas ativas de §B
é o equilíbrio ergonomia×segurança para digitação com luva. Knob: 10 chars (2⁵⁰) se o
dono priorizar segurança; expiração 24h se quiser janela ainda menor.

### F.3 "TODO MUNDO PODE CONVIDAR" — mudar a matriz de autorização?
**NÃO DECIDO — questão do dono.** Hoje `PermissionMatrix[:manage_membership] = [:owner]`
(só o dono). Mudar para incluir `edit` toca uma **invariante de §4.1** (invariante 7) e o
raio é grande: `matrix_conformance_spec`, `legacy_parity` (o legado só deixa o dono
convidar), `inv_7_invite_scope_spec`, e a paridade linha-a-linha com `firestore.rules`.
**Recomendação: manter só o dono no v1 do `invite-by-code`** (esta change é sobre o
CANAL do convite — código vs. link —, não sobre QUEM convida). Se o dono quiser abrir a
convite a `edit`, que seja uma change SEPARADA de autorização, com sua própria decisão
registrada e a suíte de invariantes atualizada de propósito — nunca em silêncio.

### F.4 Código POR-CONVITE (um e-mail) ou código de WORKSPACE reutilizável (qualquer um pede entrada)? — ✅ DECIDIDO: POR-CONVITE
**A pergunta que muda TUDO no modelo de segurança. Decisão do dono: POR-CONVITE / por-e-mail.**

O código é uma **representação adicional do MESMO registro `invitations`**, já ligado a
um e-mail específico e um papel: cada convite gera o próprio código, amarrado àquele
e-mail, uso único, expirando. Isso **preserva a invariante central "e-mail idêntico ao
autenticado"** (o coração da segurança) e mantém o modelo de ameaça **próximo ao do
link** — sem a superfície muito maior de um código aberto. É o que todo este plano
(§A–§E) detalha. Esta decisão está fixada; não reabrir sem nova instrução do dono.

**Descartado (o dono NÃO quis):** código de workspace **reutilizável** — um único código
que qualquer pessoa digita para entrar/pedir entrada. Não é um convite: é outra entidade
(um "join code" de workspace). **Quebra o vínculo com o e-mail** (a proteção central
some), vira **segredo permanente e enumerável de altíssimo valor** (um acerto = acesso
para qualquer um, não para um e-mail), exigiria fila de **aprovação** + **rotação**, e
contradiz o não-objetivo já decidido em `workspace-invitations/design.md` ("convite por
link aberto — qualquer pessoa com o link entra — seria outra feature, com outro modelo de
ameaça"). Fica **fora** desta change; só voltaria como change própria, com aprovação
explícita e um `EXECUCAO.md` que trate o segredo permanente.

---

## Riscos / trade-offs registrados

- **Entropia menor é dívida permanente.** Mitigada por defesa ativa (rate-limit/lockout/
  expiração curta) + o vínculo de e-mail; nenhuma defesa isolada basta — é a soma.
- **Pepper é material de chave.** Se vazar, o `code_hash` volta a ser brute-forceável
  offline. Guardar em credentials/ENV, rotacionável; registrar no `env_schema` com guarda
  de boot (padrão de `delivery-and-observability`).
- **Duas expirações na mesma linha** (link 7d, código 48h) exige a UI ser clara sobre
  qual venceu. Mitigado por `code_status` explícito na listagem e no diálogo.
- **Lockout por convite é DoS-de-si-mesmo em potencial:** um brincalhão erra 5× o par e
  trava o código do colega. Mitigado por o lockout ser do CÓDIGO (o link segue válido) e
  destravável reemitindo; o e-mail-no-par eleva o custo de disparar o lockout alheio.
- **Aceite por código não funciona offline** (mesma razão do token — expira/revoga no
  intervalo). A UI diz "conecte-se para aceitar".

## O que NÃO fazer nesta change (não-objetivos)

- Envio de e-mail/SMS do código (o dono distribui como quiser — igual ao link).
- Código de workspace reutilizável (§F.4 — **descartado pelo dono**); só voltaria como
  change própria com nova decisão explícita.
- Mudar a matriz de autorização (§F.3) — change própria, se aprovada.
- Convite para papel `owner` (invariante 5, imutável).
- Tocar o fluxo do link (`/convite/:token`) — permanece intocado.
