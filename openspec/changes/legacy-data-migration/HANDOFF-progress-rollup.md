# Handoff de `progress-rollup` → `legacy-data-migration` (tarefa 5.2)

Nota deixada por `progress-rollup`. Leia ANTES de escrever a transação do
importador legado.

## Ao final da importação, recalcule o cache EM MASSA — senão a Visão Geral zera.

O importador cria projetos/células/robôs/tarefas em massa (`insert_all`). Esses
caminhos **suprimem a cascata por linha** — e devem, senão 93.000 tarefas
disparariam dezenas de milhares de recálculos em cascata numa transação. Mas isso
deixa todo `progress_cache` em `0`, e a Visão Geral mostraria tudo zerado.

**A correção é obrigatória e é uma linha:**

```ruby
ActiveRecord::Base.transaction do
  Progress.without_cascade do
    # ... todo o insert_all de projetos, células, robôs, tarefas ...
  end
  Progress::BulkRecompute.call(workspace_id: workspace_id) # 3 statements, antes do commit
end
```

- `Progress.without_cascade { }` — flag de thread que faz `CascadeRecompute` virar
  no-op no bloco.
- `Progress::BulkRecompute.call(workspace_id:)` — recalcula os três níveis do
  workspace em exatamente 3 `UPDATE ... FROM`, dentro da MESMA transação, antes do
  commit.
- O sweep de `progress-rollup` (2.6) reprova qualquer bloco `without_cascade` que
  não termine em `BulkRecompute` — então não dá para esquecer sem o CI avisar.

## Verificação obrigatória: dump antes, zero-divergência depois

1. **Antes** de qualquer recálculo sobre dado importado, rode o dump pré-destrutivo
   (`progress-rollup` 5.1): `rake progress:dump_cache[<workspace_id>,<path>]` ou
   `Progress::CacheDump.call(workspace_id:, path:)`. Sem ele, um bug nas views
   torna o estado anterior irrecuperável.
2. **Depois** do importador, rode a reconciliação e exija **zero** divergência:
   `Progress::ReconciliationJob.reconcile_workspace(workspace_id)` não deve emitir
   nenhum evento `progress_cache.divergence`. Qualquer divergência aqui é bug do
   importador ou das views — não cache velho. (Cenário provado em
   `spec/progress/backfill_spec.rb`.)

## O que você pode assumir como pronto

- `Progress.without_cascade`, `Progress::BulkRecompute.call(workspace_id:)`,
  `Progress::CacheDump.call(workspace_id:, path:)` e
  `Progress::ReconciliationJob.reconcile_workspace(workspace_id)` existem e são
  cobertos por spec.
- `progress_cache` é `smallint NOT NULL DEFAULT 0` (só o ponderado §2.1); a
  contagem crua NÃO é cacheada — é calculada ao vivo por `subtree_raw_completion`.
- Tudo roda sob RLS: abra o contexto do tenant (`Tenant.with`/`app.current_workspace_id`)
  como em qualquer escrita; o `robotrack_app` não tem BYPASSRLS.
