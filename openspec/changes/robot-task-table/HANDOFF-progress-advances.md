# Handoff de `progress-advances` → `robot-task-table` (D-LEG / §3.5)

Nota deixada por `progress-advances` (tarefa 6.1). Leia ANTES de montar a coluna
"Trilha" e o aviso "trilha faltando" da tabela do robô.

## O aviso "trilha faltando" muda de definição. A cláusula "nem nota" MORREU.

§3.5 descrevia o aviso como *"progresso entre 0 e 100 e nenhum histórico **nem
nota**"*. Não há mais "nota fora da trilha": `progress-advances` (D-LEG) eliminou
a coluna `obs` de `tasks` — a antiga nota do legado agora é uma **entrada
`legacy` da própria trilha** (ver `legacy-data-migration/HANDOFF-progress-advances.md`).

**A condição do aviso passa a ser, exatamente:**

```
0 < progress < 100  AND  advances_count = 0
```

- `advances_count` conta **inclusive** entradas `legacy`. Logo, uma tarefa em 40%
  com apenas 1 entrada `legacy` (a nota portada) **NÃO** exibe o alerta — ela tem
  trilha, ainda que só a nota antiga.
- Tarefa em 0% ou em 100% nunca exibe o aviso (a faixa é aberta nos dois lados).

## Você NÃO precisa consultar a trilha para isso. O campo já vem na tarefa.

A entity `Task` (backend, `progress-advances` 4.3) **já expõe**:

- `advances_count: number` — total de entradas da trilha (legacy incluídas).
- `last_comment: string | null` — o comentário do avanço mais recente pela ordem
  da trilha (`recorded_at`, depois `created_at`, depois `id`).

Monte o aviso **só com `advances_count`** — nada de um segundo GET na trilha. O
backend pré-carrega `task_advances` na listagem (`Tasks::ListService` usa
`includes(:task_advances)`), então os dois campos vêm sem N+1.

O tipo TS já existe em `frontend/src/lib/api/endpoints.ts` (`TaskDTO`, com
`advances_count`/`last_comment`). **Quem POPULA o cache
`catalogKeys.robotTasks(wsId, robotId)` com `TaskDTO[]` é você** (`robot-task-table`) —
`progress-advances` deixou o tipo e o `taskAdvancesApi`, mas a leitura da lista
`GET /api/v1/robots/:robot_id/tasks` (que já existe, de `robot-tasks`) é montada na
sua tela. O modal de avanço (`features/advances/AdvanceControls`) lê `progress`/
`lock_version` desse mesmo cache; se você não o popular, o modal cai no fallback 0.

## Integração com o modal de avanço (já entregue)

`progress-advances` G5 entregou `features/advances/`:

- `<AdvanceControls robotId taskId />` — os botões `−10`/`+10`, o slider e o modal
  de confirmação. **Monte um por linha** da tabela, na coluna de progresso.
- Ele é role-gated: `view` não vê os botões e o slider é `aria-disabled`. Não
  reimplemente esse gate.
- No sucesso, ele invalida `catalogKeys.robotTasks(wsId, robotId)` **e** a trilha
  (`advanceKeys.trail(wsId, taskId)`). Sua tabela reflete o novo progresso e o
  `advances_count` sem reload — desde que leia dessa chave.

## Resumo do contrato

| Item | Valor |
|---|---|
| Condição do aviso | `0 < progress < 100 AND advances_count = 0` |
| `advances_count` inclui `legacy`? | **Sim** |
| Fonte do dado | campo `advances_count` da entity `Task` (sem consulta extra) |
| Modal de avanço | reusar `<AdvanceControls>`, não reescrever |
| Cache que a tabela deve popular/ler | `catalogKeys.robotTasks(wsId, robotId)` → `TaskDTO[]` |
