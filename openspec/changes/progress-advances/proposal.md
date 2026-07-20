## Why

O RoboTrack não é um gerenciador de tarefas: é um **registro de comissionamento**. O que
o produto vende é a garantia de que todo número de progresso exibido num relatório A4
assinado tem, atrás dele, uma entrada nominal, datada e imutável dizendo quem mexeu e o
que foi feito. Essa garantia mora inteira nesta capacidade.

Cobre `ESPECIFICACAO.md` §2.2 (máquina de estados da tarefa), §2.3 (auto-atribuição),
§2.4 (registro de avanço — fluxo obrigatório), a entidade **Avanço** de §1.1 e §1.4
item 2 (nota livre legada `obs` → primeira entrada de histórico). Depende de
`robot-tasks` (tabela `tasks`, `task_assignees`, `lock_version`), que é sua única
dependência de onda anterior além do que já está posto por `workspace-tenancy` (D2, D10),
`authorization-policies` (D3) e `commissioning-hierarchy` (D1).

Três traduções conscientes de Firebase → Rails/Postgres:

- **`serverTimestamp()` → dois timestamps (D8).** O legado escrevia o timestamp do avanço
  com `serverTimestamp()`, o que dava a ele uma resposta definida para "registrei às 14h
  no galpão sem sinal e o app sincronizou às 17h": o avanço era 17h, e o engenheiro que
  lia a trilha via uma hora que não aconteceu. O porte separa `recorded_at` (quando a
  pessoa agiu, enviado pelo cliente) de `created_at` (quando o servidor persistiu).
  Trilha e relatório exibem `recorded_at`.
- **Array `history` embutido no documento da tarefa → tabela `task_advances`
  append-only.** O que no Firestore era convenção ("ninguém edita o array") vira
  `REVOKE UPDATE, DELETE`, política RLS sem cláusula de UPDATE/DELETE e trigger de
  bloqueio.
- **Regra `to < 100 ⇒ comentário obrigatório` que só existia no JS do modal → CHECK
  constraint.** Um model se contorna por `rails console`; uma constraint não.

## What Changes

- **Nova tabela `task_advances`** (uuid PK gerável no cliente por D1, `workspace_id`
  NOT NULL sob RLS por D2): `task_id`, `by` (→ `people.id`, **nullable**, só para a
  entrada legada), `author_name_snapshot` (nome do autor no momento do registro — o único
  nome legítimo do esquema, snapshot histórico imutável), `from_progress`/`to_progress`
  (0–100), `comment`, `legacy` (bool), `recorded_at`, `created_at`.
- **Invariantes no banco, não no model:** CHECK de comentário obrigatório quando
  `to_progress < 100`; CHECK de faixa 0–100; CHECK "autor nulo só se `legacy`";
  CHECK de coerência status↔progresso em `tasks`; trigger de `workspace_id` coerente com o
  da tarefa; `REVOKE UPDATE, DELETE` + trigger de imutabilidade.
- **Máquina de estados §2.2** implementada como serviço transacional
  `Tasks::ApplyTransitionService`, acoplando status e progresso **nos dois sentidos** —
  incluindo a exceção que o WBS anterior perdia: progresso `0` numa tarefa `N/A`
  **preserva `N/A`**, não vira `Pendente`.
- **Endpoint `POST /api/v1/tasks/:task_id/advances`** — a **única** porta de escrita de
  `tasks.progress`. `PATCH /tasks/:id` deixa de aceitar `progress` (**BREAKING** em
  relação a qualquer rascunho de `robot-tasks` que o exponha).
- **Auto-atribuição §2.3** dentro da mesma transação do avanço.
- **Fluxo de UI do modal "Registrar avanço"** (§2.4): gatilhos, valor calculado lido do
  estado atual, rótulos condicionais do comentário, confirmação, cancelamento que reverte
  o slider, e o que a tela faz com um 409.
- **Semântica de concorrência**: `lock_version` (já criado por `robot-tasks`) enviado pelo
  cliente; conflito → `409` com o estado atual no corpo; retentativa com o mesmo uuid de
  avanço é **idempotente** (pré-requisito de `offline-pwa`, D7).
- **§1.4 item 2 muda de lugar, de propósito e declaradamente**: a conversão de `obs` em
  entrada legada passa a ocorrer **no importador em lote** (`legacy-data-migration`), não
  preguiçosamente em runtime. Consequência: `tasks` **não tem coluna `obs`**. Ver
  `design.md` → Decisão D-LEG.

### Não-objetivos

- **Cálculo e cache de progresso agregado** (robô/célula/projeto, `progress_cache`,
  job de reconciliação): é `progress-rollup` (D5). Aqui só emitimos o evento de que a
  tarefa mudou.
- **Redação da mensagem, destinatários e dedup das notificações** (§2.7): é
  `in-app-notifications`. Aqui só definimos que a publicação é **best-effort e
  pós-commit**, e nunca derruba o save.
- **Formato da mensagem do log de auditoria** (§2.8): é `audit-log`. Aqui só definimos
  que a conclusão a 100% grava auditoria **dentro da mesma transação**.
- **Renderização da tabela de tarefas, do modal de histórico e dos dois avisos de estado
  incompleto** (§3.5): é `robot-task-table`. Entregamos a ela o contrato de dados e o
  aviso de mudança de condição do alerta "trilha faltando".
- **Fila de mutations, service worker e atualização otimista offline**: é `offline-pwa`
  (D7). Entregamos a ele idempotência por uuid e `recorded_at` do cliente.
- **Importador do export Firestore**: é `legacy-data-migration`. Entregamos a ele o
  contrato da entrada `legacy` (ver D-LEG).
- **Edição de descrição, peso, categoria e responsáveis da tarefa**: é `robot-tasks`.
  Só a **auto**-atribuição do autor é nossa.

## Capabilities

### New Capabilities

- `progress-advances`: trilha `task_advances` append-only, máquina de estados
  status↔progresso, auto-atribuição do autor, semântica de concorrência otimista e
  idempotência, autorização do registro de avanço e contrato da entrada legada.
- `advance-modal-flow`: fluxo de UI obrigatório do modal "Registrar avanço" — gatilhos
  (slider passo 5, botões −10/+10), leitura do valor a partir do estado atual, regra de
  comentário condicional, cancelamento revertendo o slider e tratamento de 409.

### Modified Capabilities

Nenhuma. `openspec/specs/` está vazio — nada foi construído ainda.

### Impact

- **Banco**: 1 tabela nova (`task_advances`) + 1 índice composto de leitura da trilha +
  CHECK constraint nova em `tasks` (coerência `Concluído` ⇔ 100) + 3 triggers +
  `REVOKE UPDATE, DELETE`. Nada destrutivo: `tasks` só ganha constraint.
- **Backend**: `app/models/task_advance.rb`, `app/services/task_advances/create_service.rb`,
  `app/services/tasks/apply_transition_service.rb`,
  `app/policies/task_advance_policy.rb`, `app/api/entities/task_advance.rb`, endpoint
  Grape montado em `api/v1/base.rb`, `config/locales/pt-BR.advances.yml` (D14).
- **Frontend**: `features/advances/` (modal, hook de mutation, store de rascunho),
  extensão de `lib/api/endpoints.ts`, query keys `['ws', wsId, 'robot', robotId, 'tasks']`
  e `['ws', wsId, 'task', taskId, 'advances']` (D9).
- **Avisos a outras capacidades** — precisam ler isto antes de fechar suas specs:
  - `robot-task-table`: a condição do aviso "trilha faltando" **não fala mais em nota**.
    Passa a ser `0 < progress < 100 AND advances_count = 0`, porque a nota legada já é
    uma entrada da trilha desde o import (D-LEG).
  - `robot-tasks`: `PATCH /tasks/:id` **não aceita `progress`**; e `status` só via o
    mesmo serviço de transição.
  - `legacy-data-migration`: contrato da entrada `legacy` (autor nulo,
    `author_name_snapshot = "(nota anterior)"`, `from_progress = to_progress = 0`,
    isenção da CHECK de comentário).
  - `offline-pwa`: uuid de avanço gerado no cliente + `recorded_at` do cliente + 409
    como sinal de conflito, não como erro de rede.
  - `delivery-and-observability`: precisamos de `ADVANCE_RECORDED_AT_SKEW_MINUTES`
    (padrão `10`) e de uma métrica de contagem de 409 por workspace.
