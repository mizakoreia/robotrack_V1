# Handoff de `progress-rollup` → `delivery-and-observability` (tarefas 4.3, 3.6)

Nota deixada por `progress-rollup`. Três coisas a montar quando você entregar o
canal de alerta, o `/metrics` e o agendamento Sidekiq.

## 1. Interface de alerta `Observability::Alert.notify`

`Progress::DivergenceReporter` consome, SE existir:

```ruby
Observability::Alert.notify(event: 'progress_cache.divergence', severity: :warning, payload: { ... })
```

- `payload` traz `workspace_id`, `level` (`robot`/`cell`/`project`), `scope_id`,
  `cached` (valor antigo — a evidência de qual escrita esqueceu a cascata),
  `computed` (valor correto) e `row_count`.
- **Enquanto a interface não existe**, o reporter cai em log estruturado
  (`Rails.logger.warn` + `ActiveSupport::Notifications.instrument`). O evento já
  existe; o que falta é o canal.
- **Checagem de boot (obrigatória, 4.3):** `Progress::ReconciliationJob.require_channel!`
  levanta erro em **produção** se `Observability::Alert` não estiver definida —
  o job NÃO corrige em silêncio. Garanta que a constante exista antes de agendar
  o job em produção.

## 2. Métrica `progress_cache_divergence_total`

`Progress::DivergenceReporter` incrementa, SE existir:

```ruby
Observability::Metrics.increment('progress_cache_divergence_total', labels: { workspace_id: ... })
```

| campo | valor |
|---|---|
| nome | `progress_cache_divergence_total` |
| tipo | counter |
| labels | `workspace_id` |
| incrementa quando | o job de reconciliação corrige uma linha divergente |

Um `409` de avanço é normal (dois engenheiros no mesmo robô). **Divergência de
cache é sempre anormal** — significa um caminho de escrita que esqueceu a cascata.
Sem a métrica por workspace, um caminho quebrado reaparece toda madrugada e
ninguém sabe.

## 3. Agendamento do `Progress::ReconciliationJob` (Sidekiq, diário)

- `Progress::ReconciliationJob#perform(workspace_id)` reconcilia **UM** workspace.
  É o modelo de fan-out: o cron enfileira **um job por workspace**.
- **A enumeração de todos os workspaces é sua** (`delivery-and-observability`): é
  operação privilegiada que cruza RLS — o runtime `robotrack_app` não vê além do
  tenant corrente (D2). O scheduler que roda com privilégio de enumeração lista
  os `workspaces.id` e enfileira o job de cada um.
- Intervalo proposto: **24 h** (o SLO de atualidade do cache para um caminho que
  esqueça a cascata é o intervalo do job). Se o custo for aceitável, 1 h estreita
  o SLO sem mudar código daqui (pergunta em aberto 2 do design).

## 4. Orçamentos de latência (3.6) — alvos de produção a medir no seu job de CI

`progress-rollup` trava o NÚMERO de statements (cascata = 3, bulk = 3, Visão Geral
data = 2 queries) deterministicamente. Os p95 de wall-clock são alvo de HARDWARE
e pertencem ao seu job de perf:

| Operação | Alvo p95 |
|---|---|
| `GET /api/v1/projects/overview` (20 projetos) | ≤ 120 ms |
| `Progress::CascadeRecompute` de 1 avanço | ≤ 25 ms |
| `Progress::BulkRecompute` do dataset de carga (93k tarefas) | ≤ 8 s |

O dataset de carga (`spec/support/progress_load_dataset.rb`, 93.000 tarefas) é
compartilhado com `quality-and-accessibility` e semeia em ~17 s no runner atual.
