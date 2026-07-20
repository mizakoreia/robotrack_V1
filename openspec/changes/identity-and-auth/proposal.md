## Why

A ESPECIFICACAO.md §3.1 descreve uma tela única de autenticação com alternância
login/cadastro, e-mail+senha (mínimo 6 caracteres), Google, checkbox "manter
conectado", timeout de segurança quando o armazenamento local está bloqueado e
captura do token de convite **antes** do login. A §4.2 acrescenta que a sessão é
persistente entre reinícios (opcional pelo "manter conectado"), que o token de
convite vive em armazenamento de sessão durante o fluxo de login e que o app
degrada graciosamente — apenas avisando — quando o navegador bloqueia storage.

Nada disso existe hoje. O template ai9 autentica por magic-link de 6 dígitos,
tem Devise configurado só como `:omniauthable`, **não tem coluna de senha**, e a
tabela `jwt_denylist` + a coluna `users.jti` existem mas **nenhuma estratégia de
revogação está ligada**: logout não invalida token nenhum. Google no legado era
**popup**; OmniAuth é redirect de página inteira, o que destrói o estado da página
no meio do fluxo — exatamente onde o token de convite precisa sobreviver. E o
**nome de exibição nunca é capturado** em lugar nenhum do fluxo, embora
`person.display_name` (D10), o snapshot de autor da trilha de avanços (D8), as
mensagens de notificação (§2.7) e o log de auditoria (§2.8) dependam dele.

Esta mudança é dona da **D4** e materializa o piso de identidade sobre o qual
`workspace-tenancy`, `authorization-policies` e todas as telas se apoiam.

## What Changes

- **BREAKING** — `User` passa a ter `database_authenticatable`: nova coluna
  `encrypted_password`, senha mínima de 6 caracteres (§3.1). Contas existentes do
  template (magic-link) ficam sem senha; o RoboTrack não tem base instalada, e
  `seal-template-baseline` já remove o magic-link.
- **BREAKING** — `devise-jwt` passa a usar `Devise::JWT::RevocationStrategies::Denylist`
  ligado à tabela `jwt_denylist`. A coluna `users.jti` e seu índice único são
  **removidos** (indicavam a estratégia `JTIMatcher`, que só permite uma sessão por
  usuário). Logout, a partir daqui, invalida o token de verdade.
- Emissão de JWT com tempo de vida ligado ao "manter conectado": 30 dias marcado,
  12 horas desmarcado. Rotação explícita por `POST /auth/v1/session/renew`, que
  denylista o `jti` antigo. Job Sidekiq purga linhas expiradas do denylist.
- `omniauth-google-oauth2` por **redirect de página inteira**, com vínculo por
  e-mail verificado a conta já existente (nunca duplicar usuário por e-mail) e
  entrega do token ao SPA por **fragmento de URL**, nunca por query string.
- Nova superfície HTTP em `app/controllers/api/auth/v1/`: `registration`,
  `session` (criar/destruir/renovar), `me`. Entradas na allowlist de rotas
  públicas de `api/root.rb`, **ancoradas**.
- Rate limiting rack-attack no login, porque um mínimo de 6 caracteres sem
  travamento é brute-forceável.
- **Tela de login/cadastro** no frontend (`/entrar`): alternância login/registro,
  campo **nome** obrigatório no registro que vira o nome de exibição, checkbox
  "manter conectado" que escolhe o meio de armazenamento, timeout de 1500 ms que
  impede o login de travar quando storage está bloqueado.
- Captura do token de convite em `sessionStorage` antes do login e consumo logo
  após a autenticação, sobrevivendo ao redirect completo do Google.
- Fonte única do token no cliente: elimina a duplicação `localStorage` cru +
  `auth-storage` do zustand que o template mantém sincronizada na mão.

### Não-objetivos

- **Criar workspace, Person ou Membership.** O bootstrap do workspace no primeiro
  login é de `workspace-tenancy` (D10). Aqui só existe `User`.
- **Emitir, validar ou consumir o convite no servidor.** É de
  `workspace-invitations`. Aqui o token de convite é uma string opaca que o
  cliente guarda e repassa ao endpoint daquela capacidade.
- **Autorização.** O JWT identifica; não autoriza. Papéis e matriz §4.1 são de
  `authorization-policies` (D3).
- **Recuperação de senha, confirmação de e-mail, 2FA, Facebook.** Fora da §3.1.
- **Remover magic-link, `LoginCode`, `LoginAttempt`, vedar `X-Skip-Auth`, criar
  `spec/factories` e o helper base de request.** É `seal-template-baseline`.
- **Autenticação do ActionCable.** Consome nosso token; a mudança do `?token=`
  em query string é de `realtime-collaboration` / `seal-template-baseline`.

## Capabilities

### New Capabilities

- `identity-and-auth`: identidade do usuário no servidor — senha Devise, ciclo de
  vida do JWT com denylist real, Google OAuth por redirect, nome de exibição,
  superfície HTTP de autenticação e sua proteção.
- `auth-client-session`: a experiência de autenticação no cliente — tela única
  login/cadastro, persistência de sessão sob "manter conectado", degradação
  quando o armazenamento está bloqueado, e o ciclo do token de convite antes e
  depois do login.

### Modified Capabilities

(nenhuma — `openspec/specs/` está vazio; nada foi construído ainda)

### Impact

- **Depende de** `seal-template-baseline`: a vedação do `X-Skip-Auth` (senão toda
  regra aqui é contornável por um header), a remoção do magic-link (senão duas
  autenticações coexistem), `spec/factories/users.rb` e o helper de request de
  auth. Consumimos e estendemos esse helper com `sign_in_as` (token realmente
  despachado pelo Warden, para que os testes de denylist sejam honestos) e
  `expired_bearer_for`.
- **Habilita** `workspace-tenancy` (precisa de `current_user` e do nome),
  `authorization-policies` (precisa de identidade autenticada), e o `LoginPage`
  que `app-shell-navigation` roteia.
- **Migração destrutiva**: remoção de `users.jti` e do NOT NULL de
  `users.user_type_id`. Exige dump de `users` antes.
- **Entrega** (cita `delivery-and-observability`): variáveis
  `DEVISE_JWT_SECRET_KEY`, `JWT_TTL_REMEMBER_DAYS`, `JWT_TTL_SESSION_HOURS`,
  `OAUTH_GOOGLE_REDIRECT_URI`, `FRONTEND_AUTH_CALLBACK_URL`, credenciais
  `oauth.google.client_id/client_secret`; a URI de redirect precisa ser
  cadastrada no console do Google por ambiente; o job de purga do denylist
  precisa de Sidekiq com agendamento em produção.
- **Frontend**: `App.tsx` ganha `/entrar`, `/auth/callback` e `/convite/:token`;
  `store/authStore.ts` é reescrito; `lib/api/client.ts` deixa de ler
  `localStorage` diretamente.
