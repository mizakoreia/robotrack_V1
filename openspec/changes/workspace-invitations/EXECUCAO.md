# EXECUCAO — workspace-invitations

Mapa de execução das 29 tarefas de `tasks.md`, quebradas em **grupos coerentes**,
um grupo por invocação. Cada grupo é aplicado, verificado e commitado
isoladamente antes do seguinte começar. Mesmo método de
`seal-template-baseline/EXECUCAO.md` (Onda 0), `workspace-tenancy/EXECUCAO.md`
(Onda 1) e `identity-and-auth/EXECUCAO.md` (Onda 2).

Este arquivo é escrito **antes** de qualquer código, de propósito: a sessão já
caiu por limite de uso duas vezes nas ondas anteriores. Se cair de novo, o
próximo agente retoma pela seção **RETOMADA** no fim deste arquivo.

## Ponto de partida

- Branch: `workspace-invitations`, criada de `identity-and-auth` (onde o trabalho
  da Onda 2 vive; a `main` não tem nada disso). **Sem push** — não há credencial.
- Baseline das suítes (antes de tocar em código, medido em 21/07/2026, backend
  rodando como `robotrack_app`): **backend 181 exemplos / 0 falhas**,
  **frontend 32 testes / 0 falhas**, **`npx tsc --noEmit` limpo**.
- Dois papéis de banco de `workspace-tenancy` **continuam valendo**: runtime
  (inclusive rspec) conecta como `robotrack_app` (sem SUPERUSER/BYPASSRLS);
  migrations rodam como `robotrack_migrator`. Ver `backend/db/PROVISIONING.md`.
- `memberships.invitation_id uuid NULL` **já existe** (criada por
  `20260720180003_create_memberships.rb`), mas **sem** FK e **sem** o índice
  único parcial. A tarefa 1.3 é aditiva sobre essa coluna, não a cria.

## O objetivo central desta change

**Fechar a ponta solta deixada pela Onda 2.** O frontend já chama
`POST /api/v1/invitations/:token/accept` (`lib/api/endpoints.ts` →
`authApi.acceptInvite`, disparado por `lib/auth/session.ts` e
`features/auth/InviteRoute.tsx`) e **o endpoint não existe no backend**. O
contrato servidor é desenhado a partir do cliente que já existe, não o contrário:

| O cliente já faz | O servidor precisa entregar |
|---|---|
| `POST /api/v1/invitations/<token>/accept`, **sem corpo** | rota autenticada, **sem** `X-Workspace-Id` (o convidado ainda não é membro) |
| trata `410` como "convite expirou" (aviso, mantém sessão) | `410 invitation_expired` |
| trata qualquer outro erro como "não foi possível aceitar agora" | códigos distintos por causa (`404/409/403/422`) para a UI melhorar depois |
| guarda o token em `sessionStorage` antes do login e limpa em qualquer desfecho | pré-visualização pública `GET /api/v1/invitations/:token` |

E a invariante que dá nome à change: **consumo atômico** (invariante 6).

## Critério de agrupamento

`tasks.md` tem 6 seções. A ordem de dependência real é quase 1:1 com elas, com
duas correções:

- A **seção 5 é mista**: 5.1–5.3 e 5.5 são cliente, 5.4 é servidor (publicação do
  evento de revogação a partir de `Memberships::RemoveService`, que nasce em 4.3).
  Aplicar 5.4 num grupo de frontend deixaria o serviço da seção 4 incompleto entre
  dois commits. Por isso **5.4 sobe para o grupo do painel de equipe no servidor**.
- A **seção 4 é mista**: 4.1–4.4 e 4.7 são servidor, 4.5–4.6 são cliente. O grupo
  de servidor precisa estar verde antes de a UI consumir a superfície; separo por
  lado, não por número.

A independência entre grupos é *sequencial*, não *paralela*: cada grupo parte de
uma base sã e entrega outra base sã. G1→G2→…→G6, sem paralelismo.

## Mapa de grupos

| Grupo | Área | Tarefas | Lado | Depende de |
|---|---|---|---|---|
| **G0** | Este mapa de execução | — | — | baseline |
| **G1** | Esquema do convite (tabela, enum, constraints, RLS, função por token) | 1.1–1.5 | back | baseline |
| **G2** | Criação de convite (model, policy, service, endpoints, link) | 2.1–2.5 | back | G1 |
| **G3** | **Consumo atômico** (accept + preview + `Person` + concorrência real) | 3.1–3.6 | back | G2 |
| **G4** | Painel de equipe no servidor + revogação (evento e fallback 403) | 4.1–4.4, 4.7, 5.4 | back | G3 |
| **G5** | Frontend: painel de equipe, diálogo de convite, fluxo do convidado, revogação | 4.5, 4.6, 5.1–5.3, 5.5 | front | G4 |
| **G6** | Operação e endurecimento (rate limit, expurgo, APP_URL, i18n, suíte de invariantes) | 6.1–6.5 | ambos | G5 |

Total: 29 tarefas em 6 grupos de trabalho.

## Decisões de desenho já fixadas pela change (não reabrir)

- **D-INV-1** — `token` é coluna única e opaca (`rt_inv_` + `SecureRandom.urlsafe_base64(32)`),
  **não** a PK. PK é `uuid` (D1).
- **D-INV-2** — atomicidade em **três camadas**: transação com `SELECT … FOR UPDATE`
  na linha do convite; índice único parcial `memberships (invitation_id) WHERE
  invitation_id IS NOT NULL`; `CHECK` de coerência `used_at`/`used_by_user_id`.
  `RecordNotUnique` é traduzido para `409 invitation_already_used`, nunca 500.
- **D-INV-3** — as seis validações do consumo, cada uma com **código distinto**:
  `404 invitation_not_found`, `409 invitation_already_used`, `410 invitation_expired`,
  `422 invitation_workspace_mismatch`, `403 invitation_email_mismatch`,
  `422 unexpected_parameter` (o `role` **nunca** vem do cliente — é lido do convite;
  mandar `role` no corpo é erro explícito, não silêncio).
- **D-INV-4** — invariante 7 em três lugares: `InvitationPolicy.create?` (exige
  `owner`), enum Postgres `invitation_role ('view','edit')` (owner não é
  representável) e FK composta `(workspace_id, created_by_person_id) → people
  (workspace_id, id)`.
- **D-INV-5** — o aceite resolve `Person` por **e-mail** (nunca por nome): casa com
  `Person` de `user_id IS NULL`, ou cria nova; `409 person_email_conflict` se já
  vinculada a outro usuário.
- **D-INV-6** — token chega pré-login; o aceite é pós-autenticação; a
  pré-visualização devolve `email_masked`, nunca o e-mail inteiro nem o `workspace_id`.
- **D-INV-7** — revogação em tempo real: evento `membership_revoked` (empurrado,
  degrada a no-op sem `realtime-collaboration`) **mais** fallback por `403
  workspace_access_revoked` (funciona sozinho).
- **D-INV-8** — rate limit: aceite 10/10min por IP e por usuário; pré-visualização
  20/10min por IP; log com SHA-256 do token truncado, **nunca** o token.
- **D-INV-9** — expurgo diário só de `used_at IS NULL AND expires_at < now() - 30d`.

## Decisões que EU tomo aqui (não estavam resolvidas na change)

Registradas para não serem redescobertas — e para a change poder ser revisada.

1. **`authorization-policies` (D3) não existe ainda.** É declarada dependência
   bloqueante da Onda 2, mas não foi implementada (não há `app/policies/`). Não
   invento o mecanismo inteiro dela aqui, e também não deixo a autorização solta
   nos endpoints: crio um piso mínimo `app/policies/application_policy.rb` +
   `InvitationPolicy` + `MembershipPolicy`, com a mesma forma que
   `authorization-policies` vai generalizar (objeto por recurso, `#create?`,
   `#destroy?`, …, decidindo a partir do papel **resolvido no servidor**). Quando
   aquela change chegar, absorve estes objetos em vez de competir com eles.
2. **Perguntas em aberto do `design.md`, decididas:**
   - *(1) `people.email` é único por workspace?* **Sim** — o índice único parcial
     `index_people_on_workspace_id_and_email` já existe desde a Onda 1. O
     casamento de D-INV-5 é determinístico; não há desempate a fazer.
   - *(2) convite pendente + membership ativa?* **Sim, permitido**, e o aceite
     responde `409 already_member` **sem consumir** o token (fica pendente e
     revogável pelo dono) — a proposta do design, agora fixada.
   - *(3) dois convites pendentes para o mesmo e-mail no mesmo workspace?*
     **Proibido**, por índice único parcial `invitations (workspace_id, email)
     WHERE used_at IS NULL`, respondendo `409 invitation_already_pending`. O
     legado permitia N; permitir N deixaria o dono sem saber qual link vale, e a
     revogação viraria adivinhação.
3. **`audit_logs` é de `audit-log` (não entregue).** A tarefa 4.2 pede snapshot da
   membership antes da remoção *em `audit_logs`*. Não crio a tabela de outra
   change. Crio `membership_revocations` — **append-only** (`REVOKE UPDATE,
   DELETE` para `robotrack_app`), com o snapshot completo (workspace, person,
   user, role, invitation_id, quem removeu, quando). Ela serve **dois** propósitos:
   o backup reversível de 4.2 **e** o `403 workspace_access_revoked` de 5.3 —
   veja a decisão 4. Quando `audit-log` chegar, ela pode ser absorvida.
4. **`workspace_access_revoked` sem furar a anti-enumeração.** `ResolveCurrentService`
   hoje devolve `403 workspace_access_denied` tanto para workspace alheio quanto
   para inexistente — de propósito (a diferença vazaria *quais workspaces existem*).
   Emitir `workspace_access_revoked` "quando o workspace existe e você não é
   membro" reintroduziria exatamente esse vazamento. A saída: o código
   `workspace_access_revoked` é emitido **apenas** quando existe linha em
   `membership_revocations` para (workspace, usuário) — ou seja, só para quem
   comprovadamente **teve** acesso e portanto já sabe que o workspace existe.
   Nada novo vaza; os dois casos continuam `403`.
5. **5.5 "E2E" sem harness de E2E.** Não há Playwright/Cypress no projeto e
   introduzir um é escopo de `quality-and-accessibility`. O fluxo completo é
   coberto por **dois** testes que se encontram no meio: um request spec de ponta
   a ponta no servidor (dono convida → convidado autentica e aceita → dono remove
   → convidado recebe `403 workspace_access_revoked`) e um teste de cliente da
   rotina `handleAccessRevoked` (aviso persistente, índice local, cache React
   Query, navegação). Registrado como desvio consciente.
6. **Rotas do token são isentas de tenant, e a isenção passa a ser ciente de
   método.** `GET /api/v1/invitations/:token` e `POST …/:token/accept` acontecem
   **fora** de um workspace corrente (o convidado ainda não é membro), enquanto
   `DELETE /api/v1/invitations/:id` é rota de domínio normal. Como as duas famílias
   compartilham o mesmo padrão de path, `Api::Root.tenant_exempt?` passa a aceitar
   o método (mesma forma que `public_route?` já tem desde a Onda 2), e o
   `tenant_route_sweep_spec` passa a usar a versão ciente de método. A varredura
   **continua não-vácua**: `DELETE /api/v1/invitations/:id` e os três endpoints de
   `memberships` entram nela.

## Armadilhas previstas (o mapa mais valioso deste arquivo)

1. **`FORCE ROW LEVEL SECURITY` também vincula o dono da tabela — logo, um
   `SECURITY DEFINER` cujo dono é o `robotrack_migrator` NÃO enxerga a linha.**
   A função `invitation_by_token(text)` da tarefa 1.4 não pode simplesmente
   `SELECT` a linha: a policy de tenant a esconderia. Solução: a política de
   `invitations` ganha uma segunda cláusula `USING (token =
   current_setting('app.invitation_token', true))`, e a função faz
   `set_config('app.invitation_token', <token>, true)` (local à transação) antes
   do `SELECT`. Isso mantém a garantia que importa — acesso **só por token
   exato**, nunca listagem — e não introduz nenhum papel com `BYPASSRLS`.
2. **`schema_guard_spec` reprova tabela de domínio nova sem `workspace_id NOT
   NULL` + índice começando por `workspace_id` + `FORCE RLS` + policy
   `tenant_isolation`.** Vale para `invitations` **e** para
   `membership_revocations`. Não é opcional e não tem allowlist a usar: as duas
   são tabelas de domínio de verdade.
3. **`tenant_route_sweep_spec` enumera as rotas Grape e exige `400
   workspace_context_missing` sem header.** Todo endpoint novo de domínio
   (`POST/GET /api/v1/invitations`, `DELETE /api/v1/invitations/:id`, os três de
   `memberships`) tem de passar. Os dois endpoints por token entram na isenção
   ciente de método (decisão 6) — e a isenção é declarada, não implícita.
4. **`auth_route_sweep_spec` asserta o tamanho e o conteúdo exato de
   `PUBLIC_ROUTES`.** A pré-visualização pública (3.4) **exige** atualizar esse
   spec no mesmo grupo, senão G3 fica vermelho por motivo certo.
5. **Specs de concorrência não podem rodar sob a transação do RSpec.** Duas
   threads com conexões distintas não enxergam linhas criadas dentro da transação
   não-commitada do exemplo. Os specs 3.5/3.6 levam a tag `:tenancy` (que o
   `rails_helper` já mapeia para truncation) e criam os dados **fora** da
   transação. Além disso: cada thread precisa de `ActiveRecord::Base.connection_pool`
   próprio (`with_connection`) e o pool do `database.yml` tem de comportar as
   threads — se o pool for menor que a concorrência do teste de carga (50), o
   teste falha por espera de conexão e não pela propriedade sob teste.
6. **`Tenant.with` abre transação própria.** Rotas isentas de tenant **não** são
   embrulhadas pelo `Tenant::TransactionMiddleware`; o `AcceptService` abre a sua
   com `Tenant.with(workspace_id: invitation.workspace_id, …)` — e é dentro dela
   que o `FOR UPDATE` acontece. Rotas de domínio, ao contrário, **já** estão numa
   transação: chamar `Tenant.with` lá dentro criaria savepoint aninhado. Serviços
   desta change checam em qual dos dois mundos estão.
7. **Rack::Attack safelista `127.0.0.1`/`::1`.** Os specs de rate limit têm de
   usar `REMOTE_ADDR` não-local (o de auth já faz isso, é o precedente a copiar), e
   limpar `Rack::Attack.cache.store` no `before`/`after` — senão um exemplo
   envenena o seguinte.
8. **O token é credencial e o `filter_parameter_logging` atual filtra `token`** —
   o que cobre `params[:token]`. Mas o token vai no **PATH**, e path não passa por
   filtro de parâmetro: `GET /api/v1/invitations/rt_inv_ABC` aparece em claro no
   log de request do Rails. Isso precisa ser tratado explicitamente em 6.1 (o log
   estruturado do bloqueio usa hash) e verificado por grep — não basta confiar no
   filtro de parâmetro.
9. **`people.email` é `citext`.** O casamento por e-mail já é case-insensitive no
   banco; mesmo assim o convite normaliza na **escrita** (`strip.downcase` +
   `CHECK (email = lower(email))`), porque a comparação da invariante 6 é literal
   com `current_user.email.downcase`.
10. **A `Person` do criador do convite pode não existir.** A FK composta exige
    `created_by_person_id` pertencente ao workspace. O dono tem `Person` criada
    pelo bootstrap da Onda 1 — mas o serviço não assume: resolve via
    `People::ResolveService` (que casa por e-mail ou cria) antes de inserir.

## Decisões de ambiente (herdadas, sem regressão)

A conexão de runtime continua `robotrack_app` (sem SUPERUSER/BYPASSRLS); a RLS
continua **forçada**; os specs de isolamento continuam verdes; a varredura de
rotas de tenant continua não-vácua. Migrations rodam como `robotrack_migrator`,
contra dev **e** test, e só então a suíte roda como `app`:

```bash
export PATH="$HOME/.rbenv/shims:$PATH"
MIG_DEV="postgres://robotrack_migrator:mig_dev_pw@localhost/robotrack_dev"
MIG_TEST="postgres://robotrack_migrator:mig_dev_pw@localhost/robotrack_test"

RAILS_ENV=development DATABASE_URL=$MIG_DEV  bundle exec rails db:migrate   # gera structure.sql
RAILS_ENV=test        DATABASE_URL=$MIG_TEST bundle exec rails db:migrate   # sincroniza o test DB
bundle exec rspec                                                          # roda como robotrack_app
```

`db/roles.sql` é reaplicado quando um `REVOKE` novo entra (o
`membership_revocations` append-only de G4) — pelo mesmo motivo da Onda 1:
`pg_dump -x` **omite** GRANT/REVOKE, então um rebuild por `db:schema:load`
nasceria sem o `REVOKE` se ele morasse só na migration.

## Protocolo por grupo

1. Aplicar as tarefas do grupo (migrations como `migrator`, código, specs).
2. `bundle exec rspec` (backend, como `robotrack_app`) e, quando o grupo tocar o
   front, `npx vitest run` + `npx tsc --noEmit`. Comparar com o estado esperado.
3. Marcar `- [ ]` → `- [x]` em `tasks.md` para as tarefas do grupo.
4. `npx --yes @fission-ai/openspec@1.6.0 validate workspace-invitations --strict`.
5. Commit local descrevendo o grupo. **Nenhum push.**
6. Conferir que nenhum `.env` real entrou e que `backend/coverage/` ficou fora do
   commit (é artefato; só o commit inicial o tem).

## Estado esperado da suíte por grupo

| Após | Backend (rspec, como `robotrack_app`) | Frontend (vitest) |
|---|---|---|
| Baseline | 181 / 0 | 32 / 0 |
| G1 | + spec de esquema por SQL cru (6 inserções inválidas) verde | inalterado |
| G2 | + specs de criação (positivo e os cinco negativos) verdes | inalterado |
| G3 | + accept/preview/`Person`/concorrência/carga verdes; `auth_route_sweep` atualizado | inalterado |
| G4 | + papel, remoção, revogação e o negativo do painel verdes; sweep de tenant maior | inalterado |
| G5 | inalterado (ou + o request spec de ponta a ponta) | + testes do painel, do diálogo e da revogação |
| G6 | + rate limit, expurgo, `APP_URL`, grep de i18n, suíte das invariantes 6 e 7 | + strings pt-BR num módulo único |
| Alvo final | 0 falhas | 0 falhas, `tsc` limpo |

## Comandos de CLI de apoio

```bash
npx --yes @fission-ai/openspec@1.6.0 validate workspace-invitations --strict
npx --yes @fission-ai/openspec@1.6.0 show     workspace-invitations --json --deltas-only
```

O CLI é a fonte da verdade sobre artefatos e validação; o recorte em G1..G6 é a
camada desta execução, registrada aqui.

## Progresso

- [ ] G1 — Esquema do convite (1.1–1.5)
- [ ] G2 — Criação de convite (2.1–2.5)
- [ ] G3 — Consumo atômico (3.1–3.6)
- [ ] G4 — Painel de equipe no servidor + revogação (4.1–4.4, 4.7, 5.4)
- [ ] G5 — Frontend: painel, diálogo, fluxo do convidado, revogação (4.5, 4.6, 5.1–5.3, 5.5)
- [ ] G6 — Operação e endurecimento (6.1–6.5)

## RETOMADA

**Se a sessão caiu, comece por aqui.**

1. `git log --oneline -8` na branch `workspace-invitations`. Cada grupo é **um**
   commit, com prefixo `G<n>:`. O último commit `G<n>` diz onde parou; o grupo
   seguinte é o próximo da tabela **Mapa de grupos** acima.
2. `openspec/changes/workspace-invitations/tasks.md` tem o estado fino: as
   tarefas marcadas `- [x]` estão feitas e verificadas (só marco depois da suíte
   verde). Se houver `- [x]` sem commit correspondente, a sessão caiu no meio —
   confira `git status` e rode a suíte antes de confiar.
3. Rode a baseline do ponto em que está, **antes** de escrever qualquer código:
   ```bash
   export PATH="$HOME/.rbenv/shims:$PATH"
   cd backend  && bundle exec rspec                      # esperado: 0 falhas
   cd frontend && npx vitest run && npx tsc --noEmit     # esperado: 0 falhas
   ```
   Se o backend acusar migration pendente, rode as duas migrações como
   `robotrack_migrator` (bloco **Decisões de ambiente** acima) — o `robotrack_app`
   não faz DDL, e essa é a causa mais provável de erro no boot da suíte.
4. Leia a seção **Armadilhas previstas** antes de tocar no grupo — ela existe
   para você não redescobrir o `FORCE RLS` sobre `SECURITY DEFINER` (armadilha 1)
   nem a concorrência sob transação do RSpec (armadilha 5).
5. Regras invioláveis do bloco: **sem push**, **nenhum `.env` real em commit**,
   nenhuma regressão das ondas anteriores (runtime sem SUPERUSER/BYPASSRLS, RLS
   forçada, specs de isolamento verdes, varredura de rotas de tenant não-vácua).
6. Quando os seis grupos estiverem `- [x]`: atualizar **Progresso** e escrever a
   seção **CONCLUSÃO** aqui (mesmo formato das ondas anteriores: tabela de suítes
   antes/depois, testes de fechamento, pendências para outras changes) e **parar**.
