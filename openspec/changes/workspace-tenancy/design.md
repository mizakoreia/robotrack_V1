# Design — workspace-tenancy

## Context

O legado é Firestore. Tenancy ali era **estrutural**: todo dado de domínio vivia
sob `workspaces/{wsId}/...`, e as rules (`firestore.rules`) só precisavam checar
`exists(/workspaces/$(wsId)/members/$(request.auth.uid))`. Não havia como
"esquecer o filtro" — o caminho *era* o filtro.

O alvo é Postgres relacional plano. O filtro passa a ser uma cláusula `WHERE`, e
cláusulas `WHERE` se esquecem: num `has_many` mal escrito, num `find_by(id:)` de
parâmetro do cliente, num relatório com SQL cru, num job que recebe só o id do
robô. O WBS anterior tratou tenancy como convenção de model mais um teste, e
gastou constraint de banco em invariantes de risco muito menor. Postgres RLS não
aparece uma única vez nas 184 tarefas dele. Este documento inverte isso.

Duas premissas herdadas do legado que precisam de tradução consciente:

- **O dono não é membro** (`§1.1 Membro do workspace`). No Firestore isso era
  natural: `request.auth.uid == wsId`. Num esquema relacional vira uma escolha de
  modelagem que, se feita errada (owner como `role = 'owner'` em `memberships`),
  reintroduz exatamente a violação de `§4.1 inv. 5` que a spec proíbe.
- **Responsável por nome** (`assignees: ["João"]`, `resp: "Não Atribuído"`). Isso
  é um FK textual. O `config.yaml` do projeto proíbe explicitamente nome de
  pessoa como chave estrangeira. D10 e D11 são a tradução.

## Goals / Non-Goals

**Goals**

1. Isolamento de tenant garantido pelo banco, não pelo Ruby. Um `Task.count` num
   `rails console` de produção conectado com a credencial da aplicação deve
   retornar 0 se não houver tenant setado.
2. `Person` existindo para todo mundo que pode ser responsável, com ou sem conta.
3. Papel resolvido no servidor a cada request, a partir da única fonte válida.
4. Bootstrap idempotente e seguro sob concorrência (dois logins simultâneos).
5. Fail-closed em todo caminho de erro: sem contexto, nada é lido nem escrito.

**Non-Goals**

- Decisão de autorização por ação (`authorization-policies`).
- Autenticação (`identity-and-auth`).
- Convite/token/e-mail (`workspace-invitations`).
- Suporte a um usuário ser dono de mais de um workspace. `§1.1` diz "um workspace
  por usuário dono" e o id do workspace é o id do dono. Preservamos a cardinalidade
  (índice único em `owner_user_id`) mas **não** o acoplamento de identificadores —
  `workspaces.id` é uuid próprio. Se no futuro um usuário precisar de dois
  workspaces próprios, basta derrubar o índice; nada mais depende dele.
- Sharding, schema-per-tenant ou banco-por-tenant. Ver Decisão 1.

## Decisions

### D-1. Tenancy é uma coluna com RLS, não um schema por tenant (⬥ D2)

`workspace_id uuid NOT NULL REFERENCES workspaces(id)` em **toda** tabela de
domínio, mesmo quando derivável: `cells` tem `workspace_id` apesar de ter
`project_id`; `task_advances` tem `workspace_id` apesar de estar a quatro níveis
de profundidade. A desnormalização é deliberada — a política RLS precisa ser
avaliável numa única linha, sem join recursivo, porque um join dentro de uma
policy é avaliado por linha e recursivamente sujeito às policies das tabelas
joinadas.

Sobre cada tabela de tenant:

```sql
ALTER TABLE <t> ENABLE ROW LEVEL SECURITY;
ALTER TABLE <t> FORCE  ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON <t>
  USING      (workspace_id = current_setting('app.current_workspace_id', true)::uuid)
  WITH CHECK (workspace_id = current_setting('app.current_workspace_id', true)::uuid);
```

`FORCE` não é opcional: sem ele o **dono da tabela** ignora a policy, e o dono da
tabela é quem roda as migrations — bastaria a app conectar com a mesma credencial
(que é o default de todo `DATABASE_URL` de template) para a RLS ser decorativa.

O segundo argumento `true` de `current_setting` significa "não levante erro se a
variável não existir": ela retorna `NULL`, a comparação vira `NULL`, e `NULL` não
é `TRUE` — logo nenhuma linha passa no `USING` e nenhuma linha passa no
`WITH CHECK`. **Fail-closed por construção**, não por `if`.

*Alternativas descartadas.*
**(a) `default_scope` no model.** É o que o plano anterior propôs. Contornável
por `unscoped`, por SQL cru, por `find_by_sql`, por qualquer console e por
qualquer gem que consulte direto. Fica como reforço ergonômico (concern
`WorkspaceScoped`), nunca como garantia.
**(b) Schema por tenant (`SET search_path`).** Isolamento forte, mas migrations
passam a ser N execuções, o número de tabelas cresce linearmente com clientes, e
qualquer query analítica cross-workspace (não temos hoje, mas relatório agregado
é pedido óbvio) fica inviável. Custo desproporcional para times pequenos que é o
perfil do produto (PRODUCT.md).
**(c) Banco por tenant.** Mesmo problema, amplificado, mais custo de operação.

### D-2. Duas variáveis de sessão, não uma (⬥ D2)

`app.current_workspace_id` sozinha não resolve o seletor de workspace: para
listar os workspaces do usuário é preciso ler `workspaces` e `memberships`
**antes** de haver um tenant escolhido. Por isso existe também
`app.current_user_id`, e as duas tabelas de controle têm policy própria:

```sql
-- memberships: vejo o meu tenant corrente, ou sempre as minhas próprias linhas
USING (workspace_id = current_setting('app.current_workspace_id', true)::uuid
       OR user_id   = current_setting('app.current_user_id',      true)::uuid)

-- workspaces: o meu tenant corrente, o que eu possuo, ou onde sou membro
USING (id = current_setting('app.current_workspace_id', true)::uuid
       OR owner_user_id = current_setting('app.current_user_id', true)::uuid
       OR EXISTS (SELECT 1 FROM memberships m
                  WHERE m.workspace_id = workspaces.id
                    AND m.user_id = current_setting('app.current_user_id', true)::uuid))
```

`people` e todas as tabelas de domínio usam a policy pura de tenant — nunca
`app.current_user_id`. `users` e `jwt_denylist` não são tabelas de tenant e ficam
fora da RLS.

O `WITH CHECK` de `memberships` e `workspaces` é **só** a cláusula de
`workspace_id`/`id`: um usuário não pode inserir uma membership em um workspace
que não é o tenant corrente, mesmo que o `USING` deixe ele ler.

### D-3. Onde a variável é setada, e o que acontece se não for (⬥ D2)

`app/lib/tenant.rb`:

```ruby
Tenant.with(workspace_id:, user_id:) do ... end
```
abre `ActiveRecord::Base.transaction` e emite
`SELECT set_config('app.current_workspace_id', $1, true)` — o terceiro argumento
`true` é `is_local`, ou seja, o valor morre no `COMMIT`/`ROLLBACK`.

Três pontos de entrada, e só três:

1. **HTTP** — o bloco `before` de `backend/app/controllers/api/root.rb` (o mesmo
   bloco único onde o template já faz auth). Resolve `X-Workspace-Id`, valida
   pertencimento, abre o contexto.
2. **Sidekiq** — middleware de servidor. Todo job de domínio carrega
   `workspace_id` como primeiro argumento; o middleware o consome e abre o
   contexto. Job de domínio sem esse argumento é erro de programação e falha
   alto.
3. **ActionCable** — `Connection#connect` resolve tenant a partir do
   `WorkspaceChannel` (`realtime-collaboration`, D6) e abre o contexto por
   `subscribe`/`receive`.

**Se não for setada**: leitura devolve zero linhas e escrita levanta
`ActiveRecord::StatementInvalid` (`new row violates row-level security policy`).
Nós não dependemos disso como mensagem de erro — as rotas de domínio validam o
header antes e devolvem `400` (`X-Workspace-Id` ausente) ou `403` (usuário não
pertence). A RLS é o que acontece quando alguém **esquece** de validar, e é por
isso que ela precisa existir mesmo com a validação no lugar.

*Alternativa descartada:* `SET` (não-local) com `reset` num `ensure`. É o padrão
mais comum em artigos, e é errado num pool de conexões: qualquer caminho que
devolva a conexão sem passar pelo `ensure` — `Timeout`, `exit!`, uma exceção num
`ensure` aninhado, um `checkin` forçado pelo reaper — devolve a conexão **suja**
ao pool, e o próximo request pega o tenant do request anterior. Esse é
literalmente o bug de vazamento que a capacidade existe para impedir. `SET LOCAL`
não tem esse modo de falha: o fim da transação limpa, sempre.

*Trade-off aceito:* um request de domínio inteiro fica dentro de uma transação.
Consequências: (i) nenhuma chamada HTTP externa ou enfileiramento síncrono dentro
do contexto — jobs são enfileirados via `after_commit`; (ii) transações longas
seguram tuplas mortas do autovacuum; mitigado por não haver rota de domínio de
longa duração (relatório é leitura, gerado sob a mesma transação); (iii) rotas
sem tenant (auth, health, `GET /api/v1/workspaces`) **não** entram em transação.

### D-4. `db/structure.sql` em vez de `db/schema.rb`

Policy, trigger, `REVOKE` de coluna, `CHECK` com expressão e enum nativo não são
representáveis em `schema.rb`. Deixar `schema_format = :ruby` produziria um
`schema.rb` regenerado **sem a RLS**, e o próximo ambiente montado com
`db:schema:load` (CI, staging, máquina nova) nasceria sem isolamento e verde nos
testes. Trocamos para `:sql`. Custo: conflitos de merge em `structure.sql` são
mais chatos. Aceito — a alternativa é um modo de falha silencioso que só aparece
em produção.

### D-5. `owner` não é um valor de `membership_role` (`§4.1 inv. 5`)

`membership_role` é um enum Postgres com exatamente dois valores: `edit`, `view`.
O dono é `workspaces.owner_user_id`. Resolução:

```
role_for(user) = :owner  se workspaces.owner_user_id == user.id
               = membership.role  se existe membership (workspace_id, user_id)
               = nil (sem acesso)
```

Consequências que caem de graça:
- "Promover membro a dono" é **inexprimível**: não há valor de enum para gravar.
- "Rebaixar o dono a editor" também: um trigger `BEFORE INSERT OR UPDATE` em
  `memberships` levanta exceção se `NEW.user_id = (SELECT owner_user_id FROM
  workspaces WHERE id = NEW.workspace_id)`. O dono nunca vira linha de membership
  (`§1.1`), e não há caminho para dois papéis conflitantes.
- Trocar o dono é bloqueado em duas camadas:
  `REVOKE UPDATE (owner_user_id) ON workspaces FROM robotrack_app` (a app não tem
  privilégio na coluna) mais um trigger `BEFORE UPDATE` que levanta exceção se
  `NEW.owner_user_id IS DISTINCT FROM OLD.owner_user_id` (cobre também o papel
  de migração e qualquer conexão administrativa).

*Alternativa descartada:* `role` com três valores e `validates :role, ...` no
model. É a modelagem "óbvia" e é a que permite `UPDATE memberships SET
role='owner'` num console — exatamente o que `§4.1 inv. 5` proíbe.

### D-6. `Person` é a identidade de domínio; `user_id` é nullable (⬥ D10)

```
people(id uuid PK, workspace_id uuid NOT NULL, name text NOT NULL,
       email citext NULL, user_id uuid NULL REFERENCES users(id),
       created_at, updated_at)
```

- `UNIQUE (workspace_id, id)` — existe só para servir de alvo das FKs compostas
  (ver D-8).
- `UNIQUE (workspace_id, email) WHERE email IS NOT NULL` — casamento por e-mail
  no aceite de convite é determinístico.
- `UNIQUE (workspace_id, user_id) WHERE user_id IS NOT NULL` — um usuário é no
  máximo uma pessoa por workspace.
- `UNIQUE (workspace_id, lower(btrim(name)))` — o importador legado resolve nomes
  → `Person` (`§1.4 item 1`); sem esta constraint, `"João"` e `"joão "` viram
  duas pessoas e "Minhas Tarefas" mostra metade das tarefas.

`user_id` nullable é o ponto inteiro: `§1.1 Tarefa` tem `assignees` como lista de
nomes livres, e `PRODUCT.md` descreve chão de fábrica. Atribuir tarefa a um
técnico terceirizado sem conta é o caso normal, não a exceção. Quando essa pessoa
depois aceita um convite, `People::ResolveService` casa por e-mail e **preenche**
`user_id` na linha existente — o histórico de atribuições não se parte.

Duas linhas de `Person` nascem por caminhos distintos e só esses dois:
(a) **bootstrap**, para o dono, com `user_id` preenchido;
(b) **aceite de convite**, casando por e-mail no workspace ou criando nova.
Um terceiro caminho (cadastro manual de responsável em `workspace-settings`,
`§3.9`) cria `Person` com `user_id = NULL` e reusa o mesmo service.

*Alternativa descartada:* usar `User` direto como responsável. Quebra o caso do
técnico sem conta, e amarra dado de domínio (nome exibido no relatório) ao ciclo
de vida da conta — se o usuário for excluído, o relatório de comissionamento
perde o autor. `Person` é `workspace_scoped` e sobrevive à remoção do membro.

### D-7. `"Não Atribuído"` é abolido no banco, não no importador (⬥ D11)

```sql
CONSTRAINT people_name_not_sentinel
  CHECK (btrim(lower(name)) NOT IN ('não atribuído', 'nao atribuido'))
```

Ausência de responsável é `task_assignees` vazio (`robot-tasks`), nunca uma
`Person` sentinela. A string `"Não atribuído"` existe apenas como literal de
i18n no frontend (D14).

O `CHECK` mora no banco e não no importador de propósito: `legacy-data-migration`
tem a obrigação de filtrar (`§1.4 item 1`), mas se esquecer, queremos que a
importação **falhe alto** em vez de criar silenciosamente uma pessoa fantasma que
aparece no seletor de responsáveis de todo workspace importado. Duas grafias
cobertas porque o export legado tem ambas.

Consequência para `§1.1 Workspace.responsibles` ("lista de textos; sempre contém
`Não Atribuído`"): a coluna **não existe**. `responsibles` é a projeção de
`people` do workspace. No bootstrap, essa projeção tem exatamente uma linha — o
dono.

### D-8. Integridade referencial cross-tenant via FK composta

RLS impede *ler* a linha errada; não impede *apontar* para ela. Uma
`memberships.person_id` que referencie uma `Person` de outro workspace é dado
corrompido que a RLS torna invisível (e portanto indepurável). Padrão adotado e
obrigatório para toda FK de domínio a jusante:

```sql
FOREIGN KEY (workspace_id, person_id) REFERENCES people (workspace_id, id)
```

O `workspace_id` da linha filha participa da FK, então apontar para fora do
próprio tenant é rejeitado pelo banco. Custo: índices compostos em vez de
simples. `authorization-policies` e `commissioning-hierarchy` herdam este padrão.

### D-9. O índice de workspaces é derivado, não materializado (`§4.1 inv. 2`)

`§1.1 Índice do usuário` descreve um documento por usuário com
`workspaces: [{id, name, role}]`. Não replicamos essa tabela. `GET
/api/v1/workspaces` é uma query sobre `workspaces` + `memberships` no contexto de
`app.current_user_id`.

Motivo: uma tabela de índice precisa ser invalidada em toda mudança de papel,
remoção de membro e renomeação de workspace, e a versão desatualizada dela é
indistinguível de uma adulterada. Derivar elimina a classe inteira de bug.

O que a resposta carrega (`role`) é **rótulo de UI**. Nenhum request de domínio
lê papel do cliente: o `before` de `api/root.rb` recebe `X-Workspace-Id` (um id,
não um papel), resolve o papel no servidor e o injeta em `current_role`. Um
cliente que forje `{"id": "<ws alheio>", "role": "owner"}` no `localStorage`
consegue apenas fazer o servidor devolver `403` mais rápido.

### D-10. Bootstrap idempotente sob concorrência

`Workspaces::BootstrapService.call(user:)` é chamado (a) pelo gancho de primeiro
login de `identity-and-auth` e (b) defensivamente por
`Workspaces::ResolveCurrentService` quando um usuário autenticado não tem
workspace próprio. Precisa ser seguro sob dois logins simultâneos (celular +
desktop, cenário real do produto).

Garantia: `UNIQUE INDEX ON workspaces (owner_user_id)` mais
`INSERT ... ON CONFLICT (owner_user_id) DO NOTHING` seguido de releitura. O
perdedor da corrida não levanta exceção nem cria segundo workspace. A criação da
`Person` do dono acontece na **mesma transação** — não pode existir workspace sem
a `Person` do dono, senão `§2.3` (auto-atribuição) quebra para o dono desde o
primeiro dia.

`name` é `"Workspace de #{user.display_name}"` (`§1.1`). Se `display_name` for
vazio (conta Google sem nome), cai para a parte local do e-mail; nunca produz
`"Workspace de "`.

O bootstrap **não** semeia o catálogo de tarefas-base. Ele emite um evento
`workspace.bootstrapped` que `task-catalog` consome (`§1.3`). Acoplar aqui
inverteria a dependência da Onda 1 para a Onda 4.

### D-11. Papéis de banco

| Papel | Uso | Privilégios |
|---|---|---|
| `robotrack_migrator` | DDL, `db:migrate` | dono das tabelas; sem `BYPASSRLS` |
| `robotrack_app` | runtime (Puma, Sidekiq, Cable) | `SELECT/INSERT/UPDATE/DELETE`; sem `owner_user_id` em `UPDATE`; sem `SUPERUSER`, sem `BYPASSRLS` |

Duas URLs de conexão: `DATABASE_URL` (app) e `MIGRATION_DATABASE_URL`. Um teste
de guarda consulta `pg_roles` e falha se o papel corrente tiver `rolbypassrls` ou
`rolsuper` — porque `DATABASE_URL` apontando para o superusuário é o default de
todo ambiente de desenvolvimento e desliga a RLS inteira sem nenhum sinal.
Provisionamento dos papéis e das variáveis: `delivery-and-observability`.

## Plano de migração

Não há dado de domínio a migrar — `openspec/specs/` está vazio e nenhuma tabela
RoboTrack existe. Ainda assim, duas etapas são destrutivas em ambientes já
provisionados:

1. **Remoção de `db/schema.rb`** (D-4). Precedida de tarefa que gera
   `structure.sql` a partir do banco corrente e verifica que
   `db:drop && db:create && db:schema:load` reconstrói um banco idêntico. O
   arquivo antigo é preservado no commit anterior (rollback = `git revert`).
2. **`REVOKE` e troca do papel de conexão** (D-11). Precedida de dump lógico
   (`pg_dump -Fc`) e de verificação de que o papel novo consegue rodar a suíte
   inteira. Rollback: reapontar `DATABASE_URL` para o papel anterior — o `REVOKE`
   sozinho não perde dado.

A ordem das migrations é rígida: `workspaces` → `people` → `memberships` →
RLS/policies → triggers/`REVOKE`. Habilitar RLS antes de existir o helper
`Tenant.with` deixaria a suíte vermelha por motivo certo; por isso o helper e a
allowlist de rotas entram na mesma leva.

## Riscos / Trade-offs

- **Transação por request (D-3).** Aumenta contenção e prende conexões. Mitigado
  por: nenhuma chamada externa dentro do contexto, `after_commit` para enfileirar
  jobs, e rotas sem tenant fora da transação. Monitorar `pg_stat_activity` com
  alerta de transação > 5s — `delivery-and-observability`.
- **RLS custa plano de query.** A policy vira predicado em toda query. Mitigado
  por índice em `workspace_id` em toda tabela de domínio (obrigatório, não
  opcional) e por `workspace_id` ser a primeira coluna dos índices compostos.
  `quality-and-accessibility` mede com o dataset de carga.
- **Esquecer `workspace_id` numa tabela nova.** Uma tabela de domínio criada sem
  a coluna simplesmente não tem RLS e vaza. Mitigação: spec de guarda que
  enumera `information_schema.tables`, subtrai uma allowlist explícita de tabelas
  não-tenant (`users`, `workspaces`, `jwt_denylist`, `schema_migrations`,
  `ar_internal_metadata`) e falha se sobrar qualquer tabela sem `workspace_id
  NOT NULL`, sem `FORCE ROW LEVEL SECURITY` ou sem policy `tenant_isolation`.
  Este teste é o que faz D2 valer para as 20 capacidades a jusante que não vão
  ler este documento.
- **`X-Skip-Auth` do template.** Enquanto esse header furar a autenticação, todo
  teste negativo de tenancy é teatro: sem `current_user` não há tenant a resolver
  e a request nunca chega à RLS — ou pior, chega com contexto de outra pessoa.
  Dependência dura de `seal-template-baseline`; a suíte de guarda inclui um caso
  que envia `X-Skip-Auth: 1` numa rota de domínio e exige `401`.
- **`citext`.** Requer `CREATE EXTENSION citext`. Ambientes gerenciados
  (RDS/Cloud SQL) suportam; um Postgres sem a extensão quebra a migration.
  Alternativa se necessário: `text` mais índice em `lower(email)` — mesma
  garantia, ergonomia pior.
- **Multi-workspace no frontend.** Trocar de workspace precisa descartar todo o
  cache do React Query, e a convenção `['ws', wsId, ...]` (D9) só protege se
  ninguém criar query key sem o `wsId`. É `app-shell-navigation` que fecha isso;
  aqui só garantimos que o servidor nunca devolve dado do workspace anterior.

## Perguntas em aberto

1. **Renomear workspace** — `§1.1` não descreve edição de `name` e `§3.11` só
   fala de reset. Assumimos que renomear é permitido ao dono; a rota fica em
   `workspace-settings`. Se a decisão for "nome imutável", basta um `REVOKE
   UPDATE (name)`, mas isso precisa ser decidido antes daquela capacidade.
2. **Membro removido e depois readmitido** — a `Person` sobrevive (D-6) e a nova
   `Membership` reencontra a mesma `Person` por e-mail. Se o e-mail dele mudou
   entre as duas, cria-se uma segunda `Person` e o histórico se parte. Não há
   fusão de pessoas nesta capacidade; se virar requisito, é
   `workspace-settings`.
3. **Contexto de tenant em tarefas de manutenção** (`rails runner`, rake de
   reconciliação de D5). Elas são legitimamente cross-tenant. A saída é iterar
   workspaces abrindo `Tenant.with` por vez, mas isso precisa ser convenção
   escrita, não descoberta — proposto como item de runbook em
   `delivery-and-observability`.
