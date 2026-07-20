# workspace-tenancy

## Why

A ESPECIFICACAO.md descreve um sistema multi-tenant desde a primeira linha do
modelo de domínio: `§1.1 Workspace` estabelece um workspace por usuário dono,
`§1.1 Membro do workspace` estabelece que o papel vem da associação de membro e
que **o dono não é membro**, e `§1.1 Índice do usuário` diz textualmente que o
índice de workspaces do usuário "é apenas cache de UI — adulterar esse índice
não concede acesso". `§4.1 inv. 2` repete a regra como invariante obrigatória e
`§4.1 inv. 5` exige que o dono do workspace seja imutável.

O template ai9 não tem nada disso. Não existe `Workspace`, `Membership`,
`tenant_id` nem `default_scope`; todo dado é um dataset global. Portar o RoboTrack
sobre essa base sem uma camada de tenancy no banco significa que qualquer bug de
escopo em qualquer um dos ~20 recursos a jusante vaza dados de comissionamento
de um cliente para outro — e comissionamento de célula automotiva é dado de
cliente sob NDA.

Duas lacunas herdadas do legado precisam ser fechadas aqui, e não a jusante:

- O Firestore expressava tenancy como caminho de documento
  (`workspaces/{ws}/projects/{p}`), o que dava isolamento estrutural de graça.
  Um esquema relacional plano não dá. **D2**: `workspace_id` desnormalizado e
  `NOT NULL` em toda tabela de domínio, mais **Postgres RLS** com
  `app.current_workspace_id` setada por request. Convenção de scope no model é
  reforço, não a garantia — um `Model.find` num console de produção contorna
  qualquer `default_scope`.
- O legado endereçava responsáveis **por nome** (`assignees: ["João"]`,
  `resp: "Não Atribuído"`). **D10**: a identidade de domínio passa a ser
  `Person`, estável e independente de `User`, com `person.user_id` **nullable** —
  atribuir tarefa a um técnico de chão de fábrica que não tem conta é caso real.
  Sem uma linha de `Person` existindo, auto-atribuição (`§2.3`), "Minhas Tarefas"
  (`§3.6`) e notificações (`§2.7`) retornam vazio para todo mundo.
  **D11**: o sentinela `"Não Atribuído"` é abolido do modelo; ausência de
  responsável é conjunto vazio, e a string vira literal de UI.

Esta é a raiz do caminho crítico. `authorization-policies`, e por transitividade
toda a hierarquia de comissionamento, dependem do contexto de tenant existir e
ser confiável.

## What Changes

- **Esquema de tenancy**: tabelas `workspaces`, `people`, `memberships` (todas
  `uuid` PK, D1/D13), enum Postgres `membership_role` com exatamente `edit` e
  `view`, e o contrato de que **toda tabela de domínio futura carrega
  `workspace_id uuid NOT NULL REFERENCES workspaces(id)`**, mesmo quando o valor
  é derivável por join.
- **Row Level Security** habilitada e **forçada** (`FORCE ROW LEVEL SECURITY`)
  nas tabelas de tenant, com política única `tenant_isolation` avaliada contra
  duas variáveis de sessão: `app.current_workspace_id` e `app.current_user_id`.
  Sem variável setada, a política é falsa → zero linhas na leitura e erro na
  escrita (fail-closed).
- **Papel de banco separado**: DDL roda como `robotrack_migrator` (dono das
  tabelas); a aplicação conecta como `robotrack_app`, sem `SUPERUSER` e sem
  `BYPASSRLS`. Requer provisionamento de credencial — cite
  `delivery-and-observability`.
- **BREAKING (interno)**: `config.active_record.schema_format` passa de `:ruby`
  para `:sql`. `db/schema.rb` não consegue representar policies, triggers,
  `REVOKE` de coluna nem enums nativos; ele seria regenerado silenciosamente sem
  a RLS e o próximo `db:schema:load` recriaria o banco **sem isolamento**.
  `db/schema.rb` é removido e substituído por `db/structure.sql`.
- **Contexto de tenant por request**: helper `Tenant.with(workspace_id:,
  user_id:)` que abre transação e emite `SET LOCAL`. Ligado em três pontos de
  entrada: o bloco `before` de `app/controllers/api/root.rb`, um middleware de
  servidor Sidekiq e a `ActionCable::Connection`. Rotas sem tenant (auth, health,
  listagem de workspaces) são uma allowlist explícita.
- **Bootstrap do workspace no primeiro login**: idempotente, cria o `Workspace`
  com `name = "Workspace de <nome do dono>"` (`§1.1`), a `Person` do dono
  (D10) e nada mais. O catálogo de 31 tarefas-base (`§1.3`) é semeado por
  `task-catalog` através de um hook — não é implementado aqui.
- **Papéis**: `owner` é derivado de `workspaces.owner_user_id`, **não** é um
  valor de `membership_role`. Promover um membro a dono é inexprimível no
  esquema. `owner_user_id` é protegido por `REVOKE UPDATE (owner_user_id)` mais
  trigger (`§4.1 inv. 5`).
- **Índice de workspaces do usuário**: endpoint `GET /api/v1/workspaces` derivado
  ao vivo de `workspaces` + `memberships`. Não há tabela de índice materializada.
  O papel devolvido é rótulo de UI; toda request resolve o papel de novo no
  servidor (`§4.1 inv. 2`).
- **`responsibles`**: deixa de ser lista de textos no workspace e passa a ser a
  tabela `people`. No bootstrap nasce com exatamente uma linha — a `Person` do
  dono — e **nunca** com `"Não Atribuído"`: um `CHECK` no banco rejeita esse nome
  (D11).

### Não-objetivos

- Autorização por ação (matriz `§4.1` completa, policy objects, route-sweep) —
  é `authorization-policies` (D3). Aqui entregamos apenas a **resolução** do
  papel e o isolamento de linhas, não a decisão de "pode ou não pode".
- Login, senha, JWT, Google — é `identity-and-auth` (D4). Consumimos apenas um
  `current_user` já autenticado e um gancho de "primeiro login".
- Convites, token, e-mail, expiração — é `workspace-invitations`. Aqui
  entregamos apenas o serviço de resolução `Person` que o aceite de convite
  chama, e a coluna `memberships.invitation_id`.
- Seletor de workspace na topbar e descarte de estado ao trocar — é
  `app-shell-navigation` (`§3.10`). Aqui entregamos o endpoint que ele consome.
- Seed do catálogo de tarefas-base — é `task-catalog` (`§1.3`).
- Reset de fábrica e exclusão de workspace — é `workspace-settings` (D12).
- Importação de dados legados e filtragem de `"Não Atribuído"` no export do
  Firestore — é `legacy-data-migration` (`§1.4`). O `CHECK` que criamos é a rede
  que faz aquele importador falhar alto se esquecer o filtro.

## Capabilities

### New Capabilities

- `workspace-core`: entidade Workspace, bootstrap idempotente no primeiro login,
  imutabilidade do dono, seleção do workspace corrente por request e índice de
  workspaces do usuário como cache de UI derivado.
- `workspace-membership`: `Person` como identidade de domínio desacoplada de
  `User`, `Membership` com papéis `edit`/`view`, resolução server-side do papel
  (incluindo `owner` derivado) e abolição do sentinela `"Não Atribuído"`.
- `tenant-isolation`: `workspace_id NOT NULL` desnormalizado, políticas RLS
  forçadas, variáveis de sessão por request, papel de banco sem `BYPASSRLS` e
  propagação do contexto para jobs e ActionCable.

### Modified Capabilities

(nenhuma — `openspec/specs/` está vazio)

### Impact

- **Backend**: novas migrations em `backend/db/migrate/`; `db/schema.rb` →
  `db/structure.sql`; novos models `Workspace`, `Person`, `Membership`; novo
  `app/models/concerns/workspace_scoped.rb`; novo `app/lib/tenant.rb`; novos
  services `Workspaces::BootstrapService`, `Workspaces::ResolveCurrentService`,
  `People::ResolveService`; nova entity `Api::Entities::Workspace`; novo endpoint
  `Api::V1::Workspaces` montado em `api/v1/base.rb`; alteração do bloco `before`
  em `api/root.rb`; middleware Sidekiq; `ActionCable::Connection`.
- **Frontend**: `lib/api/endpoints.ts` ganha `workspaces.list`; o cliente axios
  passa a enviar `X-Workspace-Id`. O workspace corrente é estado de cliente
  (Zustand), o **papel não é** — ele vem da resposta e é rótulo.
- **Infra**: duas credenciais de banco (`DATABASE_URL` da app e
  `MIGRATION_DATABASE_URL`), papéis criados antes do primeiro deploy. Dependência
  de `delivery-and-observability`.
- **Depende de**: `seal-template-baseline` (suíte verde, `spec/factories`, helper
  de auth de request, `X-Skip-Auth` vedado — enquanto esse header furar a
  autenticação, nenhum teste negativo de tenancy prova nada).
- **É dependência de**: `authorization-policies`, e por transitividade de toda a
  Onda 3 em diante.
