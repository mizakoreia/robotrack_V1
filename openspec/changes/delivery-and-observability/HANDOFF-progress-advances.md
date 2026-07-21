# Handoff de `progress-advances` → `delivery-and-observability` (tarefa 6.2)

Nota deixada por `progress-advances`. Duas coisas a registrar quando você montar o
schema tipado de config (D-DO-8) e o `/metrics` (D-DO-4/D-DO-10).

## 1. Variável de ambiente: `ADVANCE_RECORDED_AT_SKEW_MINUTES`

Registre em `backend/config/env_schema.rb` (D-DO-8):

| campo | valor |
|---|---|
| nome | `ADVANCE_RECORDED_AT_SKEW_MINUTES` |
| tipo | inteiro |
| default | `10` |
| obrigatória em | **nenhum ambiente** (opcional — tem default seguro) |
| capacidade que introduziu | `progress-advances` |

**O que faz:** no registro de avanço (`TaskAdvances::CreateService`), um
`recorded_at` do cliente mais adiantado que `now() + SKEW` (relógio do tablet à
frente) é **clampado** para agora, com `recorded_at_adjusted = true` — não é
rejeitado (D8/D-TS). O passado além de 90 dias também clampa. O valor hoje é lido
por `ENV.fetch('ADVANCE_RECORDED_AT_SKEW_MINUTES', '10')`.

**Por que registrar mesmo com default:** é exatamente o modo de falha que D-DO-8
existe para pegar — um deploy sem a variável sobe usando `10` em silêncio e o
teste de clamp continua verde, então a ausência **nunca aparece**. O registro (e
o `.env.example` gerado) torna a variável visível sem depender de um erro.

Há também uma CHECK de banco correlata (`chk_ta_recorded_at`:
`recorded_at <= created_at + interval '10 minutes'`) com o `10` **fixo em SQL**. O
clamp da aplicação usa `SKEW` para caber com folga sob essa CHECK; se algum dia o
schema tornar a janela do banco configurável, este env var é o candidato natural a
alimentá-la. Por ora: default `10` dos dois lados, e o clamp garante a coerência.

## 2. Métrica: contagem de `409` de avanço por workspace

Exponha em `/metrics` (o `Ops`/observabilidade desta change) um contador:

| campo | valor |
|---|---|
| nome sugerido | `advance_conflict_total` |
| tipo | counter |
| labels | `workspace_id` |
| incrementa quando | `TaskAdvances::CreateService` responde `409 conflito_de_versao` |

**Por que:** um `409` isolado é o caso normal de dois engenheiros no mesmo robô
(D-409 — é feature, não erro). Mas `409` **crônico** num mesmo workspace/robô é
sinal de um problema real: relógios dessincronizados, uma automação reenviando, ou
dois turnos brigando pela mesma tarefa. Sem a métrica por workspace, não há como
distinguir o conflito saudável do patológico — o log estruturado (D-DO-10) registra
cada um, mas ninguém lê log procurando tendência.

O `409` já sai no log estruturado com `workspace_id` (D-DO-10 obriga o campo, e a
RLS/D2 garante que ele existe na request). A métrica é a agregação disso; a fonte
do incremento é o mesmo ponto onde o service traduz `StaleObjectError`/divergência
de `lock_version` para `409`.

## Estado atual (o que já existe do lado de `progress-advances`)

- `SKEW_MINUTES = ENV.fetch('ADVANCE_RECORDED_AT_SKEW_MINUTES', '10').to_i` em
  `backend/app/services/task_advances/create_service.rb`.
- O `409` é emitido em dois pontos do mesmo service (check manual de `lock_version`
  e `rescue ActiveRecord::StaleObjectError`), ambos com corpo `conflito_de_versao`.
- Ainda **não** há `/metrics` nem `env_schema.rb` — são desta change
  (`delivery-and-observability`). Este handoff é o que garante que a variável e a
  métrica entrem nesses dois lugares quando você os construir.
