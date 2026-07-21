# Continuidade — estado em 21/07/2026

Ponto de retomada do porte. Para uma sessão nova de agente, o prompt de partida
está em [PROMPT DE RETOMADA](#prompt-de-retomada), no fim.

## Onde está o trabalho

**As branches são empilhadas, não independentes:**

```
main (48497fd)                       ← ondas 1–4, sem nada desta sessão
└── authorization-policies (6b89283)     change COMPLETA
    └── commissioning-hierarchy (b75b072)  change COMPLETA
        └── task-catalog                   change COMPLETA — 6 de 6 (TC-G6 fechou)
            └── robot-tasks                 change COMPLETA — 6 de 6 grupos
                └── progress-advances (branch atual)  change COMPLETA — 6 de 6 grupos
```

**`progress-advances` contém todo o trabalho** (empilhada sobre `robot-tasks`). É
nela que se continua. Push por branch canônica (`git push origin
HEAD:progress-advances`). Os PRs para a `main` podem ser abertos depois, na ordem
do empilhamento.

## Suítes (medidas na branch `progress-advances`)

| Suíte | Resultado |
|---|---|
| Backend `bundle exec rspec` (como `robotrack_app`, `--seed 12345`) | **877 / 0 falhas / 9 pending** |
| Frontend `vitest run` | **95 / 0** |
| Frontend `tsc --noEmit` | limpo |

Todos os 10 pending nomeiam a capacidade que os desbloqueia — nenhum é dívida
anônima. (Dois pendings de cascade — `tasks→robots` e `task_assignees→tasks` —
destravaram e viraram verdes ao longo de `robot-tasks`.)

> Nota de ambiente: `spec/requests/auth/rate_limit_spec.rb` é levemente FLAKY na
> suíte completa (estado do Rack::Attack sensível à ordem aleatória do RSpec);
> passa isolado. Não é regressão desta sessão. Rodar com `--seed` fixo estabiliza.

## Changes concluídas (9 de 24)

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
- **`robot-tasks`** (G0..G6, COMPLETA) — a Tarefa como esquema relacional (`tasks` com enum
  `task_status`, CHECK 0–100, FK composta com CASCADE, RLS, índice único
  `(robot_id, lower(btrim(desc)))`), `task_assignees` por `person_id` (FKs compostas, sem
  `resp`, sem `"Não Atribuído"`), CRUD de tarefa (409 por id/versão, PATCH rejeita
  `progress`/`status`), atribuição por PUT de conjunto com diff + evento, e criação de robôs
  em lote §2.5 (normalizer clamp/dedup, transação única com `insert_all`, materialização das
  tarefas-base filtradas pela Aplicação, assistente de 2 passos). Benchmark da leva máxima
  (1550 linhas ~185 ms), fronteira provando que `progress-advances` NÃO foi antecipado, e
  handoff a `legacy-data-migration`. Decisões de execução 1/7/8/9 no EXECUCAO.
- **`task-catalog`** (G0..G6, COMPLETA) — catálogo `task_templates` (CHECK de domínio,
  unicidade por `desc` normalizada, RLS), `ApplicabilityFilter` Ruby+SQL, seed dos 31
  padrões na transação do bootstrap, CRUD + `GET /meta/robot_applications`, cliente TS, e a
  **sincronização retroativa** (`SyncToRobotService` + `POST /robots/:id/sync_task_templates`)
  que aplica os templates faltantes a robôs existentes sem sobrescrever, com backstop de
  concorrência pelo índice único de `tasks`. O TC-G6 fechou depois de `robot-tasks`.
- **`progress-advances`** (G0..G6, COMPLETA) — a máquina de estados progresso↔status §2.2 e
  a trilha de avanço **imutável**. `task_advances` (RLS forçada só com SELECT+INSERT, REVOKE
  UPDATE/DELETE + trigger, FK composta `ON DELETE RESTRICT`, CHECKs da regra dura do
  comentário/autor-nulo-só-legacy/skew de `recorded_at`), `tasks` ganhou soft-delete e a
  CHECK `done ⇒ 100`. `ApplyTransitionService` (tabela-verdade pura, sem aasm),
  `TaskAdvances::CreateService` (idempotência por uuid ANTES do `lock_version`, 409 com
  estado atual, clamp de `recorded_at`, auto-atribuição do autor, evento pós-commit — tudo
  numa transação com `requires_new: true`, um savepoint que um bug de concorrência real
  exigiu). API `POST`/`GET /tasks/:task_id/advances` (`TaskAdvancePolicy`, 409 no formato
  D-409), entity com `advances_count`/`last_comment`. Frontend `features/advances/` (slider
  `draft ?? server`, ±10 lendo cache vivo, modal com rótulo condicional e resolução de 409
  sem perder o comentário, read-only para `view`). Três handoffs de contrato
  (`legacy-data-migration`, `robot-task-table`, `delivery-and-observability`) e e2e dos 5
  efeitos. Decisões de execução 1–10 no EXECUCAO.

Cada change tem seu `openspec/changes/<nome>/EXECUCAO.md` com o mapa de grupos, as
decisões tomadas na execução, as armadilhas encontradas e a CONCLUSÃO com o relatório
final. **Leia o EXECUCAO.md antes de tocar no código de uma change.**

## Onde parou: `progress-advances` COMPLETA; a trilha de avanço fechada

Fechou (6/6 grupos) — ver `openspec/changes/progress-advances/EXECUCAO.md`
(decisões 1–10). O progresso agora tem UMA porta de escrita (a trilha imutável), a
máquina de estados progresso↔status vive em service puro, o modal de avanço existe
no frontend, e os contratos para `legacy-data-migration`/`robot-task-table`/
`delivery-and-observability` estão escritos como `HANDOFF-progress-advances.md` no
diretório de cada uma.

**Pendência conhecida (documentada, não atribuída):** a tensão D-H6×D-IMUT — hard
delete de robô/projeto que arraste tarefas com avanços daria 500 no trigger de
imutabilidade. A resolução completa é **soft-delete de hierarquia** (uma follow-up
em `commissioning-hierarchy`); a suíte segue verde porque `tasks` já é soft-delete
e a FK `task_advances→tasks` é RESTRICT. Ver EXECUCAO decisão 6.

**Próximo passo — `progress-rollup`** (o `progress_cache` consolidado sobe a
hierarquia a partir dos avanços). Ver a seção abaixo.

## Depois de `progress-advances`

`progress-rollup` (o `progress_cache` consolidado — soma ponderada dos avanços subindo
robô→célula→projeto). Para ter telas de verdade: `design-system` + `app-shell-navigation` +
`hierarchy-screens` + `robot-task-table` (esta última CONSOME `progress-advances`: monta a
tabela do robô, o aviso "trilha faltando" com `advances_count`, e reusa
`<AdvanceControls>` — ver o `HANDOFF-progress-advances.md` no diretório dela). Hoje a UI é a
landing do template + autenticação + painel de equipe + os hooks/lógica sem tela final.

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
> entregue, onde parei e o método de trabalho. `task-catalog`, `robot-tasks` e
> `progress-advances` estão COMPLETAS (leia os EXECUCAO.md delas). O núcleo da Tarefa e a
> trilha de avanço estão fechados de ponta a ponta.
>
> Trabalhe na branch `progress-advances` (as branches são empilhadas; ela contém tudo). O
> próximo passo é a change **`progress-rollup`** (o `progress_cache` consolidado — soma
> ponderada dos avanços subindo robô→célula→projeto). Comece pelo `EXECUCAO.md` dela
> (commit G0) — antes de qualquer código. Push por branch canônica
> (`git push origin HEAD:progress-rollup`).
>
> Siga o método: um grupo por vez, e ao fim de cada grupo me apresente um resumo e peça
> autorização antes de seguir para o próximo. Não regrida nenhuma das regras listadas na
> seção "Regras que não podem regredir".
