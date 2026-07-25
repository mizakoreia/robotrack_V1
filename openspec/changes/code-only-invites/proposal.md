## Why

Hoje um convite tem DUAS representações do mesmo registro `invitations`: um **link**
opaco (`/convite/:token`, 7 dias) e um **código** curto (`XXXX-XXXX`, 48h, HMAC),
introduzidos por `workspace-invitations` (link) e `invite-by-code` (código). O
`invite-by-code` decidiu de propósito (§F.1) que os dois **coexistem** — todo convite
nasce com link E código.

O dono agora quer **código-só**: o link some do produto. O motivo é de uso real — o
público que aceita convite é o **operador de chão de fábrica no celular** (ver
`PRODUCT.md`, "Users"), para quem digitar um código curto com o e-mail é mais simples e
mais robusto que abrir um link que passa por app de mensagem, encurtador e preview. O
link também é uma **superfície pública** (`GET /api/v1/invitations/:token` sem
autenticação) que deixa de existir se não há link.

Cobre a ESPECIFICACAO §2.4 (convite/aceite) e preserva a invariante §4.1 inv. 6
(consumo atômico com **e-mail idêntico ao autenticado**) — que já é o que torna o
código seguro sem o link. Não há tradução de Firebase nova aqui: é remoção de uma
representação que o porte tinha adicionado.

## What Changes

- **Frontend — remover toda a superfície de LINK:**
  - `InviteDialog`: some a região do link (input `invite_url` + "Copiar link"), fica só
    a região do código + "Copiar código".
  - `TeamPanel`/`LinhaConvite`: some o input `invite_url` da lista de convites pendentes.
  - Remover a rota pública `/convite/:token` (`InviteRoute.tsx` + `App.tsx`) e o ramo de
    token do `session.ts` (`consumeInvite`, o branch de token do `handleInviteAfterAuth`)
    e do `inviteStore` (chave `INVITE_KEY`). O caminho de código (`AuthPage` "Tenho um
    código", `JoinByCodeDialog`, `consumeInviteByCode`) permanece intacto.
  - DTO: parar de expor/consumir `invite_url`.
- **Backend — remover os endpoints públicos por token, mantendo o registro:**
  - Remover `GET /api/v1/invitations/:token` (preview) e `POST
    /api/v1/invitations/:token/accept` (aceite) — o `namespace :code` (preview/accept por
    código) fica.
  - `AcceptService`/`PreviewService`: remover os ramos `lookup_by_token`/`lookup` de token
    (o construtor deixa de aceitar `token:`); o código passa a ser o único localizador.
  - Entity: parar de expor `invite_url`; `AppUrl.invite_url` deixa de ser usado.
  - Remover as entradas de token das allowlists (`PUBLIC_ROUTES`, `TENANT_EXEMPT_ROUTES`,
    `config/authorization/public_routes.yml`). A allowlist pública **encolhe** — exceção
    consciente à regra "só cresce" (ver design D4), registrada aqui.
- **Banco — SEM migração destrutiva (decisão recomendada):** a coluna `token`, a função
  `invitation_by_token` e o ramo de RLS por token ficam **dormentes** (não expostos por
  rota nenhuma). Nenhum `DROP`. Reabrir o link no futuro é reverter só código.
  Alternativa (remover coluna/função) descartada em D2.

## Não-objetivos

- **Não** remover a coluna `token`/`invitation_by_token`/o ramo de RLS por token do banco
  (fica dormente — D2). Um corte de schema é uma change futura opcional, com backup antes.
- **Não** introduzir "código de workspace reutilizável" (link aberto disfarçado) — já
  rejeitado por `invite-by-code` §F.4 e por `workspace-invitations` como não-objetivo.
- **Não** mexer no formato/expiração/lockout do código (isso é `invite-by-code`); aqui o
  código só deixa de ter um par (o link).
- **Não** alterar a invariante de e-mail (§4.1 inv. 6) nem o `AcceptService.consume` (as 6
  validações) — só o **localizador** (por código, nunca por token).
- **Não** decidir sozinho o destino dos convites JÁ criados com link — ver a decisão
  aberta DA-1 em `design.md` e no resumo ao dono.

## Capabilities

- `code-only-invites` (MODIFIED/REMOVED): o convite passa a ter o **código como único
  caminho**; a representação por link (rota pública, preview/accept por token, `invite_url`)
  é removida do produto.
