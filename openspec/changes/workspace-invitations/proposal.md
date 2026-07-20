## Why

A ESPECIFICACAO.md §3.10 define o único caminho pelo qual uma segunda pessoa entra
num workspace do RoboTrack: um convite por e-mail, com papel `view` ou `edit`, que
vira um link único com token, expira em 7 dias e é de uso único. §4.1 transforma
esse fluxo em duas invariantes de segurança de nível de sistema:

- **Invariante 6** — o consumo do convite exige, **atomicamente**: token existente,
  não usado, não expirado, workspace correspondente, e-mail idêntico ao do usuário
  autenticado e papel igual ao do convite. A criação da associação de membro e a
  marcação de "usado" são **uma única transação**.
- **Invariante 7** — o convite só pode ser criado apontando para o workspace do
  próprio criador, com papel restrito a `view`/`edit`.

O legado codifica essas condições em `firestore.rules`, `match /invites/{token}`
(linhas 67–82) e no `create` de `workspaces/{wsId}/members/{memberUid}` (linhas
26–34). Aquelas regras são mais precisas que a prosa da spec — elas dizem, por
exemplo, que `wsId == request.auth.uid` (o criador é o dono, e o id do workspace é
o uid do dono), que `email` é comparado com `request.auth.token.email.lower()`, e
que o `update` do convite só é permitido na transição `used: false → true`. Este
change porta essas condições linha a linha para Rails 8 + Postgres, onde a
atomicidade que o Firestore não tinha (eram duas escritas em documentos distintos,
sem transação real) passa a existir de verdade.

Sem esta capacidade, o RoboTrack é monousuário: `workspace-tenancy` cria o
workspace do dono no primeiro login, e nada mais entra nele. Além disso, o aceite
de convite é **um dos dois únicos lugares que criam uma `Person`** (D10) — o outro
é o bootstrap do workspace. Sem ele, `robot-tasks` (atribuição), `progress-advances`
(auto-atribuição), `my-tasks-view` e `in-app-notifications` não têm destinatário
possível além do próprio dono. O WBS anterior esqueceu essa aresta e quebrou as
quatro capacidades a jusante.

## What Changes

- **Entidade `Invitation`** (`invitations`): `token` (chave pública opaca, único,
  vai na URL), `email` (do destinatário, normalizado para minúsculas), `role`
  (enum `view`/`edit`), `workspace_id`, `created_by_person_id`, `expires_at`
  (`created_at + 7 dias`), e os campos de consumo `used_at` / `used_by_user_id`.
  PK `uuid` gerável no cliente (D1), `workspace_id` `NOT NULL` sob RLS (D2).
- **Geração do link**: endpoint de criação retorna a URL absoluta
  `<APP_URL>/convite/<token>`. A UI oferece **copiar link** (o produto não envia
  e-mail — o dono distribui o link por fora; ver Não-objetivos).
- **Consumo atômico** (invariante 6): endpoint `POST /api/v1/invitations/:token/accept`
  que, numa única transação Postgres com `SELECT ... FOR UPDATE` sobre a linha do
  convite, valida as seis condições, resolve/cria a `Person` (D10), cria a
  `Membership` e marca o convite como usado. A unicidade do consumo é garantida por
  **índice único parcial** e por **constraint**, não só por código de service.
- **Coordenação com `workspace-tenancy` (D10)**: o aceite casa o e-mail do convite
  com uma `Person` existente do workspace que ainda não tem `user_id`; se casar,
  preenche `person.user_id`; se não, cria uma `Person` nova já com `user_id`.
  Dependência explícita — este change **não** define a tabela `people` nem
  `memberships`, apenas as consome.
- **Painel de equipe** (§3.10): membros atuais com mudança de papel e remoção,
  convites pendentes com revogação. Só o `owner` opera; `edit` e `view` só leem.
- **Revogação em tempo real** (§3.10): quando a membership do usuário some enquanto
  ele está no workspace, o cliente detecta a negação (403 da API ou evento
  `membership_revoked` do `WorkspaceChannel`), avisa, remove o workspace do índice
  local e volta ao workspace próprio.
- **Higiene operacional**: job Sidekiq de expurgo de convites expirados/consumidos,
  e **rate limiting** no endpoint de aceite (o token é adivinhável por força bruta
  se não houver teto).
- **Token pré-login**: o token chega na URL **antes** da autenticação.
  `identity-and-auth` (D4) guarda em `sessionStorage` e sobrevive ao redirect do
  Google; esta capacidade consome depois da autenticação, e trata o caso do usuário
  que autentica com um e-mail diferente do convite.

### Não-objetivos

- **Não envia e-mail.** Nem SMTP, nem template, nem fila de entrega. §3.10 descreve
  "gera link único com token. Copiar link" — a distribuição é manual. Um envio real
  exige provedor, domínio verificado e tratamento de bounce; isso é escopo de
  `delivery-and-observability` se um dia virar requisito.
- **Não altera o papel `owner`.** Convite só emite `view`/`edit` (invariante 7); o
  dono é imutável (invariante 5) e isso é dono de `workspace-tenancy`.
- **Não define as policies base.** A matriz §4.1 e o mecanismo de policy objects
  são de `authorization-policies` (D3); aqui declaramos apenas
  `InvitationPolicy` / `MembershipPolicy` dentro daquele mecanismo.
- **Não implementa a tela de Configurações → Equipe inteira.** §3.9 (chips de
  responsáveis, catálogo de tarefas-base, backup, reset) é de `workspace-settings`;
  aqui entregamos o painel de equipe como componente que aquela tela monta.
- **Não implementa o `WorkspaceChannel`.** É de `realtime-collaboration` (D6);
  aqui definimos o **evento** que ele publica e o comportamento do cliente ao
  recebê-lo, mais o fallback por 403 que funciona sem Cable nenhum.
- **Não trata convite offline.** Aceitar convite exige rede; a fila de mutations
  de `offline-pwa` (D7) explicitamente não enfileira aceite (ver design.md).

### Impact

- **Backend**: nova migration `invitations` (+ índices e constraints); novo
  `Invitations::CreateService`, `Invitations::AcceptService`,
  `Invitations::RevokeService`; `Memberships::UpdateRoleService`,
  `Memberships::RemoveService`; entities Grape; endpoints montados em
  `api/v1/base.rb`; policies novas; job `Invitations::PurgeExpiredJob`;
  regex de rota pública para `GET /api/v1/invitations/:token` (pré-visualização
  do convite antes do login) na allowlist de `api/root.rb`.
- **Frontend**: `features/team/` (painel de equipe), rota `/convite/:token`,
  hook de revogação em tempo real no shell, chaves React Query
  `['ws', wsId, 'members']` e `['ws', wsId, 'invitations']` (D9).
- **Dependências**: `authorization-policies` (bloqueante, Onda 2),
  `workspace-tenancy` (`Person`, `Membership`, RLS — D2/D10),
  `identity-and-auth` (token em `sessionStorage`, D4),
  `realtime-collaboration` (evento de revogação — degrada para 403 se ausente),
  `audit-log` (registro de convite/aceite/remoção — best-effort),
  `delivery-and-observability` (env `APP_URL`, Sidekiq em produção, alerta de
  rate limit).
- **BREAKING**: nenhum. Nada foi construído ainda.

## Capabilities

### New Capabilities

- `workspace-invitations`: entidade Convite, geração e cópia do link, expiração de
  7 dias, uso único e consumo atômico (invariantes 6 e 7), criação/casamento de
  `Person` no aceite, expurgo de expirados e rate limiting.
- `team-access-management`: painel de equipe (membros com mudança de papel e
  remoção, convites pendentes com revogação) e revogação de acesso em tempo real
  no cliente.

### Modified Capabilities

Nenhuma.
