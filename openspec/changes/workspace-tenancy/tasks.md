# Tarefas — workspace-tenancy

Pré-requisito duro: `seal-template-baseline` concluída. Enquanto `X-Skip-Auth`
furar a autenticação e a suíte não estiver verde com `spec/factories`, nenhum
teste negativo desta capacidade prova nada.

## 1. Fundação de esquema e papéis de banco

- [x] 1.1 Trocar `config.active_record.schema_format` para `:sql`, gerar
  `db/structure.sql` a partir do banco corrente e remover `db/schema.rb`.
  (design D-4 — `db:drop && db:create && db:schema:load` num banco limpo produz
  esquema idêntico ao migrado; se `schema.rb` sobreviver, o próximo CI monta o
  banco sem RLS e passa verde)
- [x] 1.2 Gerar dump lógico (`pg_dump -Fc`) dos ambientes já provisionados e
  documentar o comando de restauração antes de qualquer mudança de papel de
  banco. (backup obrigatório da 1.3 — sem ele, um `REVOKE` errado em staging não
  tem caminho de volta)
- [x] 1.3 Criar os papéis `robotrack_migrator` (dono das tabelas) e
  `robotrack_app` (runtime, sem `SUPERUSER`, sem `BYPASSRLS`) e separar
  `DATABASE_URL` de `MIGRATION_DATABASE_URL`. (`tenant-isolation` §Papel de banco
  — `SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user`
  retorna `f, f` na conexão de runtime; rollback = reapontar `DATABASE_URL`)
- [x] 1.4 Spec de guarda `spec/tenancy/db_role_spec.rb` que falha se o papel da
  conexão de runtime tiver `rolsuper` ou `rolbypassrls`. (`tenant-isolation`
  §Papel de banco — a suíte reprova quando alguém aponta `DATABASE_URL` para o
  superusuário local, que é o default de todo setup de desenvolvimento)

## 2. Tabelas de tenancy

- [x] 2.1 Migration `workspaces`: `id uuid` PK com default `gen_random_uuid()`
  mas fornecível pelo cliente, `name`, `owner_user_id NOT NULL` FK para `users`,
  índice único em `owner_user_id`. (`workspace-core` §Entidade Workspace — o
  segundo `INSERT` com o mesmo `owner_user_id` viola o índice único; sem coluna
  `responsibles`)
- [x] 2.2 Migration `people` (habilitando `citext` na mesma leva): `id`,
  `workspace_id NOT NULL`, `name NOT NULL`, `email citext NULL`,
  `user_id uuid NULL`, os índices únicos parciais de `(workspace_id, email)`,
  `(workspace_id, user_id)` e `(workspace_id, lower(btrim(name)))`, o único
  `(workspace_id, id)` alvo de FK composta, e a constraint
  `people_name_not_sentinel` (D11).
  (`workspace-membership` §Person e §Conjunto vazio — `"João Souza"` e
  `" joão souza "` colidem no mesmo workspace mas não entre workspaces; as
  quatro grafias de `"Não Atribuído"` falham no `INSERT`, e `"Ana Atribuído"`
  passa)
- [x] 2.3 Migration `memberships` com o enum Postgres `membership_role`
  (exatamente `edit` e `view`), FK composta
  `(workspace_id, person_id) → people(workspace_id, id)` e único
  `(workspace_id, user_id)`. (`workspace-membership` §Papéis e §Membership —
  `UPDATE memberships SET role='owner'` falha com `invalid input value for
  enum`, não com validação de model; `person_id` de outro workspace é rejeitado
  pela FK em vez de virar linha invisível)
- [x] 2.4 Trigger `memberships_owner_is_not_member`, que levanta exceção quando
  `NEW.user_id` é o `owner_user_id` do workspace. (`§1.1` — o dono não é membro;
  o `INSERT` falha em vez de criar dois papéis conflitantes para a mesma pessoa)
- [x] 2.5 Proteger `workspaces.owner_user_id`: `REVOKE UPDATE (owner_user_id)`
  para `robotrack_app` **e** trigger `workspaces_owner_immutable`.
  (`§4.1 inv. 5` — o `UPDATE` como `robotrack_app` falha por privilégio de
  coluna, e como `robotrack_migrator` falha pelo trigger)
- [x] 2.6 Spec de esquema exercitando 2.1–2.5 exclusivamente por SQL, sem passar
  por model. (barra de qualidade, item 5 — cada constraint é provada contornando o
  ActiveRecord, porque é exatamente por esse caminho que ela vai ser testada em
  produção)

## 3. Row Level Security

- [x] 3.1 Migration de RLS: `ENABLE` + `FORCE ROW LEVEL SECURITY` em `people`,
  `workspaces` e `memberships`, com a policy `tenant_isolation` (`USING` e
  `WITH CHECK`) em `people` e as policies de controle em `workspaces` e
  `memberships` combinando `app.current_workspace_id` com `app.current_user_id`,
  estas com `WITH CHECK` restrito ao tenant corrente.
  (`tenant-isolation` §RLS / design D-2 — `pg_class.relforcerowsecurity` é
  `true` nas três, só `ENABLE` deixaria o dono das tabelas ignorar a policy;
  listar workspaces funciona sem tenant setado, mas inserir membership em
  workspace alheio não)
- [x] 3.2 Helper `app/lib/tenant.rb` com `Tenant.with(workspace_id:, user_id:)`
  usando `set_config(..., true)` dentro de transação.
  (`tenant-isolation` §Contexto — após o fim do bloco, `current_setting` na
  mesma conexão retorna `NULL`; um `SET` não-local com `ensure` devolveria a
  conexão suja ao pool)
- [x] 3.3 Concern `WorkspaceScoped` (default scope, atribuição automática de
  `workspace_id` na criação) como reforço ergonômico do model.
  (design D-1 — é conveniência; a spec de 3.5 prova que `unscoped` continua
  isolado mesmo com o concern desligado)
- [x] 3.4 Spec de isolamento em leitura: `find` cross-tenant, `unscoped.count`,
  `select_all` cru — dataset com 12 projetos em `WS-A` e 30 em `WS-B`.
  (`tenant-isolation` §Isolamento — `unscoped.count` dentro de `WS-A` retorna
  12; se retornar 42, a garantia está no Ruby e não no banco)
- [x] 3.5 Spec de isolamento em escrita: `INSERT` com `workspace_id` alheio,
  `UPDATE` movendo linha entre tenants, `delete_all` alcançando outro tenant.
  (`tenant-isolation` §Isolamento — as três operações falham ou não afetam nada;
  as 30 linhas de `WS-B` permanecem)
- [x] 3.6 Spec de fail-closed: sem `Tenant.with`, `Person.count` é `0` e
  `Person.create!` levanta violação de policy num banco com 40 pessoas.
  (`tenant-isolation` §Fail-closed — o modo de falha por esquecimento é lista
  vazia, nunca vazamento)

## 4. Contexto de tenant nos pontos de entrada

- [x] 4.1 `Workspaces::ResolveCurrentService`: lê `X-Workspace-Id`, valida
  pertencimento e resolve o papel (`owner` derivado de `owner_user_id`, senão a
  membership). (`workspace-core` §Seleção — header ausente devolve `400
  workspace_context_missing`; workspace alheio e workspace inexistente devolvem
  ambos `403`, nunca `404`)
- [x] 4.2 Ligar o contexto no bloco `before` de `app/controllers/api/root.rb`,
  com allowlist explícita de rotas sem tenant (auth, health,
  `GET /api/v1/workspaces`). (`tenant-isolation` §Contexto — rota de auth não
  abre transação; rota de domínio fora da allowlist e sem resolução reprova o CI)
- [x] 4.3 Middleware de servidor do Sidekiq que abre `Tenant.with` a partir do
  primeiro argumento do job. (`tenant-isolation` §Contexto — job de domínio
  enfileirado sem `workspace_id` vai para a fila de mortos antes do `perform`,
  em vez de rodar com contexto nulo)
- [x] 4.4 Contexto de tenant na `ActionCable::Connection`, por
  `subscribe`/`receive`. (D6 / `realtime-collaboration` — uma subscrição a
  `WorkspaceChannel` de workspace alheio é rejeitada no `subscribed`)
- [x] 4.5 Spec de vazamento entre requests: request A no contexto de `WS-A`
  levanta exceção; request B, na mesma conexão do pool, vê
  `current_setting` `NULL`. (`tenant-isolation` §Contexto — este é o bug que o
  `SET LOCAL` existe para impedir e o único que um `ensure` não cobre)
- [x] 4.6 Spec de guarda de esquema: enumera `information_schema.tables`,
  subtrai a allowlist de não-tenant e falha se sobrar tabela sem
  `workspace_id NOT NULL`, sem `FORCE ROW LEVEL SECURITY` ou sem policy
  `tenant_isolation`. (`tenant-isolation` §workspace_id — este teste é o que faz
  D2 valer para as capacidades a jusante que nunca vão ler o `design.md`)

## 5. Bootstrap e identidade de domínio

- [x] 5.1 `Workspaces::BootstrapService`: cria workspace com
  `name = "Workspace de <display_name>"` — caindo para a parte local do e-mail
  quando o nome de exibição é vazio — e a `Person` do dono na mesma transação,
  com `INSERT ... ON CONFLICT (owner_user_id) DO NOTHING` + releitura.
  (`workspace-core` §Bootstrap — dois logins simultâneos criam um único
  workspace e nenhuma chamada levanta `RecordNotUnique`; conta Google sem nome
  produz `"Workspace de joao.pereira"`, nunca `"Workspace de "`)
- [x] 5.2 Emitir o evento `workspace.bootstrapped` sem semear o catálogo.
  (`workspace-core` §Bootstrap — `task_templates.count` é 0 ao fim do bootstrap;
  semear aqui inverteria a dependência de Onda 1 para Onda 4)
- [x] 5.3 `People::ResolveService`: casa por e-mail no workspace (case-insensitive)
  ou cria nova, preenchendo `user_id` na linha existente.
  (D10 / `workspace-membership` §Resolução — Ana com 7 tarefas atribuídas e
  `user_id NULL` aceita o convite e continua com as 7; a contagem de `people` não
  muda)
- [x] 5.4 Spec do bootstrap e da resolução, incluindo o caso cross-workspace
  (`Person` com o mesmo e-mail em `WS-B` não é reutilizada em `WS-A`) e o de
  remoção de membro preservando a `Person`.
  (`workspace-membership` §Resolução e §Membership — sem a `Person` do dono
  criada no bootstrap, `§2.3`, `§3.6` e `§2.7` retornam vazio para todo mundo)

## 6. Superfície de API e cliente

- [x] 6.1 `Api::Entities::Workspace` e endpoint `GET /api/v1/workspaces`,
  derivado ao vivo de `workspaces` + `memberships`, montado em `api/v1/base.rb`.
  (`workspace-core` §Índice — dono de `WS-A` e membro `view` de `WS-B` recebe
  exatamente dois itens; `WS-C` não aparece)
- [x] 6.2 `PATCH /api/v1/workspaces/:id` aceitando apenas `name`.
  (`workspace-core` §Imutabilidade — payload com `owner_user_id` devolve `422` e
  o valor persistido não muda; alterar só `name` devolve `200`)
- [x] 6.3 Enviar `X-Workspace-Id` no cliente axios (`frontend/src/lib/api/client.ts`)
  e adicionar `workspaces.list` em `endpoints.ts`, guardando o workspace corrente
  em Zustand e o papel **apenas** como rótulo vindo da resposta.
  (`workspace-core` §Índice / D9 — o papel nunca é lido de storage do cliente
  para decidir nada)
- [x] 6.4 Suíte de request negativa da superfície HTTP: `localStorage` adulterado
  com `{"id": "WS-C", "role": "owner"}` chamando `GET /api/v1/projects` com
  `X-Workspace-Id: WS-C`; `X-Skip-Auth: 1` em rota de domínio; e `role=owner`
  enviado num workspace onde o usuário é `view`.
  (`§4.1 inv. 2` / `tenant-isolation` §Fail-closed — `403` no primeiro, `401` no
  segundo, papel efetivo `view` no terceiro; adulterar o índice de UI não
  concede acesso porque o papel vem de `owner_user_id`/`memberships`)
- [x] 6.5 Rodar `db:drop && db:create && db:schema:load` num ambiente limpo e
  executar a suíte de isolamento inteira sobre o banco reconstruído.
  (`tenant-isolation` §Esquema em SQL — todos os cenários de negação passam; se
  algum passar por ausência de RLS no esquema carregado, 1.1 está incompleta)
