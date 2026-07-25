## Context

`invite-by-code` (já em `main`) tornou o **código** uma representação adicional do MESMO
registro `invitations`, coexistindo com o **link** por decisão explícita §F.1 (todo
convite nasce com os dois; sem toggle na UI). O aceite é unificado: `AcceptService.consume`
roda as mesmas 6 validações da invariante §4.1 inv. 6 (token existente, não usado, não
expirado, workspace correspondente, **e-mail idêntico ao autenticado**, papel igual),
independentemente de a linha ter sido achada por `invitation_by_token` ou por
`invitation_by_code`. A segurança do código NÃO depende do link: mesmo adivinhando o
código, o atacante precisaria controlar a caixa de e-mail do convidado.

Reconciliação com a REALIDADE do repo (levantada nesta sessão de planejamento):

- **Frontend do link:** `InviteDialog.tsx` (região do link L92–104, `copiar()` L58–72,
  "Copiar link" L129–131), `TeamPanel.tsx`/`LinhaConvite` (input `invite_url` L227–233),
  `InviteRoute.tsx` (rota `/convite/:token`, registrada em `App.tsx:52`), `session.ts`
  (`consumeInvite` token L38–96, `handleInviteAfterAuth` ramo token L196–209), `invite.ts`
  (`INVITE_KEY`), DTO `invite_url` em `endpoints.ts`.
- **Backend do link:** `invitation_tokens.rb` (`GET ':token'` L82–87, `POST ':token/accept'`
  L96–108; o `namespace :code` L37–76 fica), `AcceptService`/`PreviewService`
  (`lookup_by_token`/`lookup`), entity `invite_url` (`AppUrl.invite_url`),
  `root.rb` `PUBLIC_ROUTES`/`TENANT_EXEMPT_ROUTES` + `public_routes.yml`.
- **Já pronto e reusado (não tocar):** o caminho de código inteiro — `AuthPage` "Tenho um
  código", `JoinByCodeDialog`, `consumeInviteByCode`, `code/preview`, `code/accept`,
  `invitation_by_code`, `row_by_code`, lockout/rate-limit do código.
- **Acoplamento:** o model ainda tem `validates :token, presence` e `assign_token on:
  :create`. Se a coluna FICA (D2), esses seguem gerando um token **dormente** (nunca
  exposto) — nada quebra. Só um corte de coluna exigiria removê-los.

## Decisões

### D1 — Profundidade: remover a ROTA pública e os endpoints por token (não só esconder na UI). **RECOMENDADO — pendente de confirmação do dono (ver DA-2).**

"Código-só" de verdade significa que **não existe caminho por link** — nem UI, nem rota
pública. Esconder o link só na UI deixaria `GET /api/v1/invitations/:token` de pé (um
convite vazado por link ainda seria aceitável, e a superfície pública não-autenticada
continuaria existindo). Então removemos:

- as rotas `GET ':token'` e `POST ':token/accept'`;
- os ramos de token de `AcceptService`/`PreviewService` (construtor sem `token:`);
- a exposição de `invite_url` na entity e o uso de `AppUrl.invite_url`;
- a rota SPA `/convite/:token` e todo o ramo de token no cliente.

**Alternativa descartada (UI-only):** esconder o link no `InviteDialog`/`TeamPanel` e
manter tudo no backend. Mais barato e trivialmente reversível, MAS não entrega "código-só"
(a rota pública e o aceite por token continuam vivos e exploráveis por quem tiver um link
antigo). Fica como o *fallback* se o dono quiser o passo mínimo (DA-2, opção A).

### D2 — Manter a coluna `token`/`invitation_by_token`/ramo de RLS **dormentes** (sem migração destrutiva). **RECOMENDADO.**

O corte de rota (D1) já entrega o produto código-só. Dropar a coluna `token`, a função
`invitation_by_token` e o 2º ramo do `USING` da RLS é uma **migração destrutiva** que:
(a) exige backup antes (regra da casa: "tarefa destrutiva exige backup/rollback imediatamente
antes"); (b) mexe na policy de RLS de uma tabela com isolamento forçado (risco alto, baixo
retorno); (c) obriga trocar `validates :token`/`assign_token` no model. O ganho é só ~1
coluna e uma função `SECURITY DEFINER` inertes. **A invariante do banco não muda** — a linha
segue isolada por workspace/código; o ramo de token do `USING` fica sem quem o acione (só é
ativado por `set_config('app.invitation_token', …)`, que nenhum código chama mais).

**Alternativa descartada (dropar a coluna):** schema mais limpo, mas migração destrutiva +
mudança de RLS + backup, desproporcional. Se um dia quiserem, é uma change própria
(`drop-invitation-token`) com backup e rollback — não esta.

**Onde a invariante mora:** inalterada — RLS forçada em `invitations` (workspace) + o
`AcceptService.consume` (as 6 validações da inv. 6) + o índice único de membership por
convite. Esta change **não afrouxa** nenhuma; só remove um **localizador** (token) e sua
rota.

### D3 — O aceite continua atômico e por e-mail; muda só o localizador.

`AcceptService`/`PreviewService` deixam de aceitar `token:`. O código (`row_by_code` +
`invitation_by_code`) vira o único caminho até a linha. As 6 validações, o `SELECT … FOR
UPDATE`, a resolução de `Person`, o one-shot e o `reject_unexpected_parameters!` ficam
byte-a-byte iguais — só some o ramo `@token`.

### D4 — A allowlist pública **encolhe**: exceção consciente à regra "só cresce".

`CONTINUIDADE.md` fixa que as varreduras (pública/tenant/route-sweep/cross-tenant) **só
crescem**. Aqui elas **encolhem**: removemos as entradas de token de `PUBLIC_ROUTES`,
`TENANT_EXEMPT_ROUTES` e `public_routes.yml`, porque as rotas correspondentes deixam de
existir. Isso é seguro e desejável (menos superfície pública), mas é uma **reversão
declarada** de um invariante de processo — registrada aqui e no `EXECUCAO.md` para não
passar em silêncio. A regra continua valendo para rota NOVA (nasce declarando policy); o
que fazemos é retirar allowlist de rota REMOVIDA. O route-sweep de 100% das rotas deve
seguir verde (as rotas de token somem das duas listas juntas).

### D5 — Convites já criados: fora do escopo de código, decisão do dono (DA-1).

Todo convite hoje nasce com código (invite-by-code), então nenhum convite pendente fica
**sem** código. MAS o código só é mostrado UMA vez, na criação; um convite pendente antigo
pode ter sido entregue ao convidado **só como link**. Removida a rota de token, esse
convidado perde o único caminho que tinha. Isso é uma decisão de **operação**, não de
schema — ver DA-1. O plano não força um caminho; recomenda drenar/re-emitir antes do corte.

## Decisões em aberto (para o dono)

### DA-1 — O que fazer com os convites pendentes que só têm link entregue?

Opções: (a) **drenar** — aceitar/expirar os pendentes atuais antes de mergear o corte
(mais simples; o galpão é pequeno); (b) **re-emitir** — o dono revoga e cria de novo (o
novo já é código-só) e passa o código; (c) **janela de graça** — manter `POST
':token/accept'` por N dias e só então remover (contradiz "código-só imediato", mais
código temporário). **Recomendação: (a) drenar** — checar `TeamPanel` (convites pendentes)
e resolver antes do merge; é operação de minutos e evita código de transição.

### DA-2 — Confirmar a profundidade (D1) vs. o passo mínimo.

(A) **UI-only** — esconder o link no `InviteDialog`/`TeamPanel`, backend intocado. Rápido,
reversível, MAS o aceite/preview por token seguem públicos (não é "código-só" de verdade).
(B, recomendado) **Remover rota + endpoints por token** (D1), coluna dormente (D2). Entrega
código-só real sem migração destrutiva. (C) **B + dropar a coluna** — schema limpo, mas
migração destrutiva + mudança de RLS + backup; desproporcional agora. **Recomendação: (B).**

## Riscos / trade-offs

- **Estranhar um convidado com link antigo** (DA-1). Mitigação: drenar antes do corte.
- **Encolher allowlist** (D4) contraria um invariante de processo — mitigado por registro
  explícito + route-sweep verde (rota e allowlist saem juntas).
- **Coluna dormente** (D2) deixa `token`/`invitation_by_token` no schema sem uso — custo
  ~zero, documentado; não é dívida escondida.
- **Testes que exercitam o token** (request specs de preview/accept por token, e2e
  `invite-code.spec` na parte de link, sweeps de rota pública) precisam ser **removidos ou
  reescritos** para código-só — senão a suíte fica vermelha por cobrir rota que não existe.
  Mapeado nas tarefas de verificação.
