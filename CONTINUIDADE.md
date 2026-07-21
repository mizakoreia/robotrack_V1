# Continuidade — estado em 21/07/2026

Ponto de retomada do porte. Para uma sessão nova de agente, o prompt de partida
está em [PROMPT DE RETOMADA](#prompt-de-retomada), no fim.

## Onde está o trabalho

**As branches são empilhadas, não independentes:**

```
main (48497fd)                     ← ondas 1–4, sem nada desta sessão
└── authorization-policies (6b89283)   change COMPLETA
    └── commissioning-hierarchy (b75b072)  change COMPLETA
        └── task-catalog (0c65ccb)         EM ANDAMENTO — 2 de 6 grupos
```

**`task-catalog` contém todo o trabalho.** É nela que se continua. Os PRs para a
`main` podem ser abertos depois, na ordem do empilhamento.

## Suítes (medidas na branch `task-catalog`)

| Suíte | Resultado |
|---|---|
| Backend `bundle exec rspec` (como `robotrack_app`) | **666 / 0 falhas / 12 pending** |
| Frontend `vitest run` | **75 / 0** |
| Frontend `tsc --noEmit` | limpo |

Todos os 12 pending nomeiam a capacidade que os desbloqueia — nenhum é dívida
anônima.

## Changes concluídas (7 de 24)

`seal-template-baseline`, `workspace-tenancy`, `identity-and-auth`,
`workspace-invitations` (anteriores) e:

- **`authorization-policies`** (G0..G6) — matriz §4.1 como dado, `Authorization::Context`
  (papel resolvido só no servidor), `BasePolicy` singleton + 12 policies, gate fail-closed
  no `before` de `Api::Root` (rota sem `route_setting :policy` nunca responde 200),
  contrato 401/403/404 sem vazamento, allowlist pública em YAML, route-sweep de 100% das
  rotas, 8 invariantes executáveis, varredura cross-tenant gerada, paridade 22/22 com o
  `firestore.rules` legado, guarda estático anti `role ==`, job de CI dedicado.
- **`commissioning-hierarchy`** (G0..G6) — `projects`/`cells`/`robots` com PK uuid gerável
  no cliente, FK composta `(pai_id, workspace_id)`, RLS forçada, `position` DEFERRABLE,
  `progress_cache` desde a origem, CRUD idempotente (201/200/409/404), reordenação em lote
  com advisory lock, e o cliente (hooks React Query, `newId()`, handler de drag & drop).
  Sem telas — `hierarchy-screens` é outra change.

Cada change tem seu `openspec/changes/<nome>/EXECUCAO.md` com o mapa de grupos, as
decisões tomadas na execução, as armadilhas encontradas e a CONCLUSÃO com o relatório
final. **Leia o EXECUCAO.md antes de tocar no código de uma change.**

## Onde parou: `task-catalog`

Feito (G0..G2): esquema `task_templates` (CHECK de domínio em `app_filters` aceitando os
6 valores da §1.2 mais `'Todas'`, unicidade por `lower(btrim(desc))`, RLS forçada), model
com a normalização D-TC-2, e `TaskTemplates::ApplicabilityFilter` em Ruby **e** SQL com
tabela de casos 6×4 provando que as duas versões não divergem.

Feito (G3 — tarefas 3.1–3.6): `TaskTemplates::DefaultCatalog` com os **31 itens** da §1.3
(9 categorias `A. Hardware`…`I. Aceitação`, todos `weight: 1`, **2** com filtro —
`Calibração de Cola` → `["Sealing"]`, `Check sinais de Gripper` → `["Handling","Solda
Ponto"]`, grafias do legado preservadas); spec de trava (31/9/2 + conjunto literal de
`desc`); `Workspaces::SeedDefaultTaskTemplatesService` com `insert_all!` único; seed
chamado DENTRO da transação do `BootstrapService` (guardado por `inserted == 1`, com
cenário de falha injetada provando rollback); scope `TaskTemplate.ordered` com `COLLATE
"C"` e spec de ordenação sob `C` **e** `pt-BR-x-icu`; spec de isolamento por workspace.
O seed deixou de passar pelo evento `workspace.bootstrapped` (não satisfaz a atomicidade
da §1.3) — ver EXECUCAO decisão 6.

**Próximo passo — TC-G4** (tarefas 4.1–4.6): policy `TaskTemplatePolicy` (verificação +
predicado), entity `Api::Entities::TaskTemplate` (com `appFilters` em camelCase), CRUD
`GET/POST/PATCH/DELETE /api/v1/task_templates` (coerce que tolera `apps`, `appFilters`
vence com warning), `GET /api/v1/meta/robot_applications` servindo `Robot::APPLICATIONS`,
e a varredura negativa (route-sweep + cross-tenant crescem juntas). Depois: **TC-G5**
(cliente), **TC-G6** (sincronização retroativa §2.6 — **depende da tabela `tasks`**, de
`robot-tasks`; por isso foi movido para o fim).

## Depois de `task-catalog`

`robot-tasks` (tarefas, `task_assignees` por `people.id`, criação de robôs em lote §2.5) —
caminho crítico, remove 4 pendings. Depois `progress-advances` e `progress-rollup`. Para
ter telas de verdade: `design-system` + `app-shell-navigation` + `hierarchy-screens` (hoje
a UI é a landing do template + autenticação + painel de equipe).

## Método (não abrir mão)

1. Uma change por vez, cada uma na sua branch, empilhada na anterior.
2. **Antes de qualquer código**, escrever `openspec/changes/<change>/EXECUCAO.md` com o
   mapa de grupos, decisões próprias, armadilhas previstas e seção RETOMADA — commit `G0`.
3. Executar grupo a grupo. Por grupo: aplicar → `bundle exec rspec` (0 falhas) → marcar
   `- [x]` em `tasks.md` → `npx --yes @fission-ai/openspec@1.6.0 validate <change>
   --strict` → **um commit** `G<n>: ...`.
4. Ao fim de cada grupo: resumir e **pedir autorização antes do próximo**.
5. Divergência entre o design e a realidade (ou entre duas changes): decidir, **registrar
   a decisão com o motivo** no EXECUCAO.md e anotar no `tasks.md`. Nunca em silêncio.
6. `pending` sempre nomeia a capacidade bloqueadora; nada de spec pendente fingindo
   cobertura de código que não existe.

## Regras que não podem regredir

- A aplicação conecta ao Postgres como `robotrack_app` — **sem SUPERUSER e sem
  BYPASSRLS** (inclusive nos seeds).
- Isolamento entre workspaces é **Row Level Security forçada**, não convenção de código.
- As invariantes moram no banco (trigger, constraint, índice único), não só no model.
- Vazamento entre tenants responde **404**, nunca 403 — corpo byte-idêntico ao de um id
  inexistente.
- As varreduras (autenticação, tenant, route-sweep de policy, cross-tenant) **só crescem**:
  rota nova nasce declarando policy e entrando no gerador cross-tenant no mesmo grupo.
- O repositório legado `mizakoreia/RoboTrack` é **somente referência de leitura** — nenhum
  arquivo dele entra neste repositório.

## Ambiente de desenvolvimento

Migrations rodam como `robotrack_migrator`; a suíte roda como `robotrack_app`. Detalhes em
[backend/db/PROVISIONING.md](backend/db/PROVISIONING.md):

```bash
cd backend
MIG_DEV="postgres://robotrack_migrator:mig_dev_pw@localhost/robotrack_dev"
MIG_TEST="postgres://robotrack_migrator:mig_dev_pw@localhost/robotrack_test"
RAILS_ENV=development DATABASE_URL=$MIG_DEV  bundle exec rails db:migrate
RAILS_ENV=test        DATABASE_URL=$MIG_TEST bundle exec rails db:migrate
bundle exec rspec

cd ../frontend
./node_modules/.bin/vitest run && ./node_modules/.bin/tsc --noEmit
```

O frontend usa **pnpm** (`pnpm-lock.yaml`); o `package-lock.json` está dessincronizado —
`npm ci` falha. Seed de demonstração da hierarquia:
`RAILS_ENV=development bundle exec rails runner db/seeds/hierarchy_demo.rb`.

## PROMPT DE RETOMADA

> Estou continuando o desenvolvimento do RoboTrack (github.com/mizakoreia/robotrack_V1):
> reimplementação de um sistema legado (PWA + Firestore) sobre um template Rails 8
> API-only + React 18/TS, organizada com OpenSpec — 24 changes em `openspec/changes/`,
> cada uma com proposta, design, deltas de spec e tarefas.
>
> Leia `CONTINUIDADE.md` na raiz do repositório: ele tem o estado atual, o que já foi
> entregue, onde parei e o método de trabalho. Depois leia
> `openspec/changes/task-catalog/EXECUCAO.md`, que é a change em andamento.
>
> Trabalhe na branch `task-catalog` (as branches são empilhadas; ela contém tudo).
> O próximo passo é o grupo TC-G3, descrito no CONTINUIDADE.md e nas tarefas 3.1–3.6.
>
> Siga o método: um grupo por vez, e ao fim de cada grupo me apresente um resumo e peça
> autorização antes de seguir para o próximo. Não regrida nenhuma das regras listadas na
> seção "Regras que não podem regredir".
