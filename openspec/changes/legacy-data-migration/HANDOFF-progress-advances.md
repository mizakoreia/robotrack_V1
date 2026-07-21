# Handoff de `progress-advances` → `legacy-data-migration` (D-LEG)

Nota deixada por `progress-advances` (tarefa 6.1). Leia ANTES de escrever a
conversão de `obs` (a "nota anterior") do export legado.

## `tasks` NÃO tem coluna `obs`. A nota vira uma entrada da trilha, no import.

O legado convertia `obs` **preguiçosamente** — no primeiro registro de avanço de
uma tarefa com `obs` preenchido e `history` vazio, transformava `obs` na primeira
entrada (`byName: "(nota anterior)"`, `legacy: true`) e apagava `obs`.

`progress-advances` (D-LEG) **moveu isso para o importador em lote, de propósito,
e isto muda o requisito** — não finja que não. A conversão acontece UMA vez, no
momento do import, e `tasks` **nunca** tem coluna `obs`. Diferença observável (a
favor do usuário): a nota aparece na trilha desde o dia 1, em vez de ficar
invisível até alguém tocar a tarefa.

## Contrato EXATO da entrada legada (é isto que você insere em `task_advances`)

Para cada tarefa do export cujo `obs` (ou campo equivalente do documento legado)
não é vazio, insira UMA linha em `task_advances`:

| coluna | valor |
|---|---|
| `id` | uuid do cliente (D1) — determinístico por tarefa, para o import ser idempotente |
| `workspace_id` | o do tenant destino |
| `task_id` | a tarefa importada |
| `by` | **`NULL`** |
| `author_name_snapshot` | **`'(nota anterior)'`** (string exata, com parênteses) |
| `legacy` | **`true`** |
| `from_progress` | `0` |
| `to_progress` | `0` |
| `comment` | o conteúdo de `obs` |
| `recorded_at` | timestamp legado da tarefa, ou o do import se ausente |

### Por que cada campo é assim (as CHECKs do banco vão te cobrar)

- **`by = NULL` só é permitido com `legacy = true`.** A CHECK
  `chk_ta_author_null_only_legacy` (`"by" IS NOT NULL OR legacy`) rejeita autor
  nulo em entrada não-legada. É a única brecha de autor nulo no sistema, e existe
  para você.
- **`to_progress = 0` com `comment` preenchido passa** porque a regra dura do
  comentário (`to_progress = 100 OR legacy OR btrim(comment) <> ''`) é satisfeita
  por `legacy = true` — mesmo se `obs` viesse vazio-mas-presente. Não dependa do
  comentário para satisfazer a CHECK; dependa de `legacy`.
- **`author_name_snapshot` é NOT NULL sempre** (inclusive legado): use a string
  literal `'(nota anterior)'`, nunca vazio.
- A trilha é **imutável** (REVOKE UPDATE/DELETE + trigger): insira certo na
  primeira vez. Não há UPDATE de correção depois.

## O que você pode assumir como PRONTO (esquema entregue por `progress-advances`)

- `task_advances (id, workspace_id, task_id, by, author_name_snapshot,
  from_progress, to_progress, comment, legacy, recorded_at, recorded_at_adjusted,
  created_at)` com RLS **forçada** (policies só de SELECT e INSERT), FK composta
  `(task_id, workspace_id) → tasks` **ON DELETE RESTRICT**, FK composta
  `(workspace_id, by) → people` **ON DELETE RESTRICT**.
- CHECKs: faixas `0..100`, comentário obrigatório abaixo de 100 exceto `legacy`,
  `char_length(comment) <= 1000`, `by IS NOT NULL OR legacy`,
  `recorded_at <= created_at + interval '10 minutes'`.
- Inserção pelo role de runtime (`robotrack_app`), sob contexto de tenant aberto.
  **Você não tem BYPASSRLS** — abra `app.current_workspace_id` como toda escrita.

## Coordenação com o handoff de `robot-tasks`

O `HANDOFF-robot-tasks.md` deste mesmo diretório manda resolver **responsável**
(nome → `Person` → `task_assignees`, sem sentinela `"Não Atribuído"`). Este
handoff é ortogonal: trata só da **nota `obs` → entrada `legacy` na trilha**. Os
dois rodam no mesmo importador, sobre o mesmo documento de export.
