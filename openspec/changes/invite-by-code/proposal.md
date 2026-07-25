## Why

A ESPECIFICACAO.md §3.10 define o convite por e-mail como o único caminho para uma
segunda pessoa entrar num workspace; `workspace-invitations` já o entregou como um
**link** `<APP_URL>/convite/<token>` de 256 bits, uso único, expirando em 7 dias, com
consumo atômico (invariantes 6 e 7 de §4.1). O link funciona bem para quem recebe uma
mensagem e clica, mas o usuário-alvo do RoboTrack (§ contexto do produto: engenheiro
de comissionamento no chão de fábrica, celular na mão, às vezes de luva, sob luz forte)
muitas vezes já está logado, ou prefere **digitar** um código curto a abrir um link.

Este change adiciona uma **representação adicional do MESMO convite**: um código curto
e legível no formato `XXXX-XXXX` (Crockford Base32, sem os ambíguos I/L/O/U), que a
pessoa digita — com o e-mail — numa seção "Tenho um convite" da tela de entrada. O
código **coexiste** com o link; não o substitui.

O ponto de segurança que organiza todo o design: um código curto é uma **credencial
fraca e enumerável** (2⁴⁰ ≈ 1,1×10¹²), ao contrário do token de 256 bits, que é
inviável de adivinhar por entropia pura. Ele só é seguro porque **não é credencial
suficiente sozinho**: é um LOCALIZADOR de uma linha `invitations` cujo consumo continua
exigindo a invariante central da §4.1 (invariante 6) — o e-mail do convite tem de ser
**idêntico ao e-mail autenticado**. Adivinhar o código de um convite para
`joao@fabrica.com` é inútil para quem não controla a conta do João. O código transforma
"adivinhe o código" em "adivinhe o código E controle a conta-alvo". Somado a isso, o
change endurece o eixo enumerável com defesas ATIVAS que o token de 256 bits não
precisava: hashing com pepper, expiração curta própria (48h), lockout por convite, e
rate-limit apertado por IP, por e-mail e global.

Traduzindo o legado: não há equivalente Firestore para o código — é capacidade nova.
Ela CONSOME `workspace-invitations` (o `AcceptService`, o `invitation_by_token`, o ramo
RLS por token, o log-scrubber, o rack-attack) sem modificá-lo, reusando o mesmo
`SELECT ... FOR UPDATE` e as mesmas seis validações; a única diferença é COMO a linha é
encontrada (por `invitation_by_code` em vez de `invitation_by_token`).

## What Changes

- **Coluna hasheada na mesma linha `invitations`** (migration ADITIVA): `code_hash`
  (HMAC-SHA256 do código com pepper de servidor, único por índice parcial),
  `code_expires_at` (expiração PRÓPRIA, 48h, mais curta que os 7 dias do link),
  `code_attempts` (contador de falhas contra a linha, para lockout) e `code_locked_at`
  (trava após N falhas). O código em claro **nunca** é persistido nem logado.
- **Geração criptográfica** do código no alfabeto Crockford Base32 (32 símbolos, exclui
  I/L/O/U), 8 caracteres exibidos `XXXX-XXXX`; colisão tratada por retry no
  `RecordNotUnique` do índice único.
- **Lookup por código sem contexto de workspace**: função `invitation_by_code(text)`
  `SECURITY DEFINER` (recebe já o HASH computado no app — o pepper nunca entra no banco)
  + terceiro ramo no `USING` da policy `tenant_isolation` de `invitations`, espelhando
  o padrão de `invitation_by_token`. Sem `BYPASSRLS`, sem listagem — acesso por
  igualdade de hash, nunca varredura.
- **Aceite por código atômico**: `Invitations::AcceptService` ganha
  `lookup_by_code(code, email)` que localiza a linha e chama o **mesmo `consume`** de
  hoje (transação, `FOR UPDATE`, seis validações, resolução de `Person`, one-shot).
  Zero duplicação da lógica; a invariante de e-mail (condição 5) é preservada intacta.
- **Preview por código exige o par (código + e-mail)**: diferente do preview por token
  (que responde só com o token, já forte), o preview por código só responde quando o
  e-mail submetido casa com o e-mail do convite — matando a colheita de alvos de
  phishing por enumeração de códigos.
- **Rotas novas dedicadas**: `POST /api/v1/invitations/code/preview` (público,
  tenant-exempt) e `POST /api/v1/invitations/code/accept` (autenticado, tenant-exempt).
  `POST` mesmo no preview porque o e-mail vai no CORPO, nunca em query string (regra de
  privacidade da casa). Ambas declaradas na allowlist e cobertas pelas varreduras.
- **Endurecimento contra enumeração**: rate-limit `code-accept-ip` 5/10min,
  `code-preview-ip` 10/10min, teto por e-mail submetido (5/10min) e teto GLOBAL de
  falhas de código; lockout por convite após 5 falhas do par (`423
  invitation_code_locked`); pepper registrado no `env_schema`; `throttled_responder` e
  scrubber logam só `code_sha256[0,12]`; igualdade de tempo entre código inexistente e
  existente.
- **Entrada por código na tela de login**: seção "Tenho um código de convite" na
  `AuthPage`, com campos E-mail e Código (máscara `XXXX-XXXX`, normalização tolerante),
  sobrevivendo ao redirect do Google OAuth via `sessionStorage`, reusando o mapa de
  erros de `consumeInvite`. `InviteDialog`/`TeamPanel` exibem o código ao lado do link.

### Não-objetivos

- **Não envia e-mail/SMS do código.** O dono distribui como quiser, igual ao link.
- **Não cria código de workspace reutilizável** (§F.4 do PLANO, DESCARTADO pelo dono):
  um único código que qualquer um digita para pedir entrada é outra entidade (um "join
  code"), quebra o vínculo com o e-mail (a proteção central), vira segredo permanente
  de altíssimo valor, e contradiz o não-objetivo já registrado em
  `workspace-invitations/design.md` ("convite por link aberto — qualquer pessoa com o
  link entra — seria outra feature, com outro modelo de ameaça"). Só voltaria como
  change própria, com decisão explícita.
- **Não altera a matriz de autorização** (§F.3 do PLANO): só o dono convida
  (`PermissionMatrix[:manage_membership] = [:owner]`) permanece. Abrir a `edit` toca a
  invariante 7 e a paridade com o legado — seria change SEPARADA de autorização.
- **Não altera o fluxo do link** (`/convite/:token`): permanece intocado.
- **Não altera o papel `owner`**: convite só emite `view`/`edit` (invariante 5/7).
- **Não trata aceite por código offline**: aceitar exige rede (o código pode expirar/
  travar/ser consumido no intervalo); a UI diz "conecte-se para aceitar".

### Impact

- **Backend**: migration aditiva sobre `invitations` (colunas de código, índice único
  parcial, `invitation_by_code`, ramo RLS); `Invitation` ganha
  `SHORT_CODE_ALPHABET`/`generate_short_code`/`code_hash_for`/`normalize_code`/
  `assign_short_code`/`code_status`; `CreateService` gera e retorna o código em claro
  UMA vez; `AcceptService`/`PreviewService` ganham caminhos por código; nova classe de
  rotas (ou extensão de `InvitationTokens`) `POST /code/preview` e `POST /code/accept`;
  `Api::Entities::Invitation` expõe `short_code` só na criação e `code_status`/
  `code_expires_at` na listagem; `rack_attack` novos throttles; `env_schema` ganha
  `INVITATION_CODE_PEPPER`; scrubber ganha padrão do código; allowlist
  (`PUBLIC_ROUTES`/`TENANT_EXEMPT_ROUTES`/`public_routes.yml`).
- **Frontend**: `invitationsApi.previewByCode`/`acceptByCode`, `short_code?` no
  `InvitationDTO`; `inviteStore.captureCode`/`readCode`; seção na `AuthPage`;
  `consumeInviteByCode` reusando o mapa de erros; novos literais em
  `lib/i18n/invitations.ts`; `InviteDialog`/`TeamPanel` exibindo o código.
- **Dependências** (consumidas, não modificadas): `workspace-invitations`
  (`AcceptService`, `invitation_by_token`, ramo RLS, scrubber, rack-attack),
  `authorization-policies` (route-sweep, cross-tenant, public-routes),
  `delivery-and-observability` (`env_schema`, pepper como material de chave),
  `identity-and-auth` (`sessionStorage` sobrevivendo ao OAuth).
- **BREAKING**: nenhum. Tudo é aditivo; o link continua idêntico.

## Capabilities

### New Capabilities

- `invite-by-code`: código curto por-convite como representação adicional do convite
  (coluna hasheada, unicidade, expiração própria, geração cripto sem ambíguos); lookup
  por código sem contexto de workspace (`invitation_by_code` + ramo RLS, sem
  BYPASSRLS); aceite por código atômico reusando `FOR UPDATE` e as seis validações,
  exigindo e-mail autenticado idêntico; preview por código exigindo o par
  (código+e-mail); endurecimento contra enumeração (rate-limit IP/e-mail/global,
  lockout por convite, hashing com pepper, log sem claro, expiração curta); entrada por
  código na tela de login sobrevivendo ao OAuth, acessível e com alvo de toque de luva.

### Modified Capabilities

Nenhuma. `workspace-invitations` é consumida, não modificada.
