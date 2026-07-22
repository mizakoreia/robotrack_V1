# Handoff de `progress-rollup` → `commissioning-report` (tarefa 6.4, §3.8)

Nota deixada por `progress-rollup`. Leia ao montar o carimbo e o corpo do
relatório A4.

## O carimbo NOMEIA a métrica ponderada. O corpo usa o ponderado (§2.1).

Os percentuais do corpo hierárquico do relatório (projeto → célula → robô) são o
**progresso ponderado (§2.1)** — o mesmo `progress_cache` que a Visão Geral lê no
envelope `weighted_progress`. O relatório NÃO pode misturar as duas métricas no
mesmo bloco sem rotulá-las (D15).

### Contrato

- **Carimbo do documento:** declara, em texto, que os percentuais do corpo usam o
  **progresso ponderado**. Use o rótulo centralizado
  `I18n.t('progress.metrics.weighted.label')` → "Progresso ponderado" (nunca um
  literal — o lint de `progress-rollup` 6.1 reprova literais de rótulo).
- **Percentual do projeto no corpo** = `projects.progress_cache` (o ponderado).
  Um projeto de `progress_cache = 58` mostra **58%** no corpo, e o carimbo cita a
  métrica ponderada.
- **Distribuição de status** (`1 Concluído, 1 Pendente, 3 N/A`) é rotulada como
  **distribuição de status**, NÃO como progresso. O número da contagem crua
  (§3.2, ex.: `20%`) **não** aparece rotulado como o anel do projeto — se
  aparecer, rotule-o explicitamente como "Progresso físico (tarefas concluídas)"
  (`I18n.t('progress.metrics.raw_count.label')`), nunca solto.

### Cenário a adicionar ao contrato consumido

> **Carimbo declara a métrica**
> - QUANDO o relatório de um projeto com `progress_cache = 58` é gerado
> - ENTÃO o carimbo contém a menção ao progresso ponderado
> - E o percentual do projeto no corpo é `58%`
> - E o `20%` da contagem crua NÃO aparece rotulado como o anel do projeto

## O que você pode assumir como pronto

- `projects/cells/robots.progress_cache` é `smallint` (0..100), só o **ponderado**,
  mantido atualizado pela cascata (`progress-rollup` G2).
- Os envelopes `weighted_progress` / `raw_completion` e os rótulos pt-BR
  centralizados (`config/locales/pt-BR.progress.yml`) existem.
- A contagem crua vem ao vivo de `subtree_raw_completion` (agregável em robô/
  célula/projeto/workspace) — não é cacheada.
