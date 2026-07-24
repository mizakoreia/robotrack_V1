# EXECUCAO — legacy-data-migration (G0: reconciliação com a realidade)

> **STATUS FINAL: DORMENTE (não-aplicável).** Decidido com o dono após G8: o sistema novo
> **começa do zero**, sem dado legado a migrar. Não há Firebase antigo com dado real, logo
> não há `RoboTrack_Database.json` e o corte (8.6/8.7) nunca será executado. A capacidade
> ficou 36/38 construída e testada contra fixtures sintéticas; o código vive isolado em
> `Legacy::*` (dead-code inofensivo). Mantido dormente (custo zero) em vez de removido —
> reabrir só se surgir uma fonte de dados a importar. O resto deste doc é o registro da
> construção.


A migração do sistema legado (PWA + Firestore) para o Postgres relacional. O trabalho
NÃO é "copiar JSON": é transformar as 5 regras de leitura tolerante do legado em 5 regras
de escrita, uma vez só, idempotente e com prova de equivalência (design D-LDM-1..8).

## Fonte da verdade (importante)

**O contrato de formato é a SPEC desta change** (`design.md` + `specs/*` +
`config/legacy_export_v1.schema.json`), NÃO o código do repositório legado
`mizakoreia/robotrack`. O legado é um PWA quebrado/não-confiável: serve, no máximo, como
curiosidade histórica. Nada dele entra aqui, e nenhuma decisão de formato se apoia nele.
O que o porte precisa saber sobre o formato antigo já está DECLARADO no `design.md`/§4.4.

## Divisão permanente e explícita (D-LDM-8, Riscos)

- **36 de 38 tarefas rodam contra FIXTURE SINTÉTICA** (tarefa 1.2), escrita à mão a partir
  da §1.1/§4.4 — exercita todos os casos de §1.4 e de D-LDM-7.
- **2 tarefas `[BLOQUEADO: export]`** (8.6, 8.7): só executáveis com o `RoboTrack_Database.json`
  real, que **não está no git** (é export do Firestore vivo; sai do console do Firebase).
  Ficam abertas e anotadas — não viram `[x]` falso.

## Reconciliação por grupo (o que JÁ existe vs o delta)

- **Grupo 1 (contrato+fixtures) — DELTA.** Não há `legacy_export_v1.schema.json` nem as
  fixtures. Construir. (workspace-settings §3.11 já EXPORTA JSON — o acordo de schema comum
  é 1.3; ver o `backup_export_service`.)
- **Grupo 2 (infra) — PARCIALMENTE JÁ FEITO:**
  - **2.2 JÁ SATISFEITA** — `people` já tem `people_name_not_sentinel CHECK (btrim(lower(name))
    <> ALL (ARRAY['não atribuído','nao atribuido']))` E `index_people_on_workspace_id_and_
    normalized_name UNIQUE (workspace_id, lower(btrim(name))) WHERE archived_at IS NULL`
    (structure.sql:725,1570). A camada 3 de D-LDM-3 (o sentinela morre no BANCO) já vale.
    Marcar reconciliada; 7.2 testa contra ESSA constraint.
  - **2.1/2.3/2.4/2.5 DELTA** — criar `legacy_import_runs` + `legacy_id_map` (migration), a
    etapa de backup `pg_dump -Fc` e o `rake legacy:rollback` + spec. **[FEITO G2]**
    - **RECONCILIAÇÃO 2.1:** `legacy_id_map` carrega `workspace_id` DENORMALIZADO (a spec
      lista só `run_id`); sem ele o `schema_guard` reprovaria e o rollback não escoparia
      por RLS. Ambas as tabelas com FORCE RLS + `tenant_isolation`.
    - **RECONCILIAÇÃO 2.4 (a grande):** D-LDM-6 fala em "apagar em ordem inversa de
      dependência", mas o porte tem DUAS tabelas append-only IMUTÁVEIS por REVOKE+trigger:
      `task_advances` (D-IMUT) e `audit_logs` (D12). Uma tarefa importada com avanço legado
      é travada pela FK RESTRICT do avanço → DELETE físico impossível (o MESMO muro que fez
      o `FactoryResetService` ARQUIVAR em vez de deletar). Portanto o rollback: (a) ARQUIVA
      a hierarquia do run (`deleted_at`, só ids mapeados — filho pós-corte sobrevive), (b)
      DELETA as folhas sem trava (task_assignees, notifications, task_templates, memberships,
      people — uma a uma, pulando quem virou autor de avanço real), (c) NÃO toca
      `task_advances`/`audit_logs` importados (imutáveis; marcação legada evita confusão),
      (d) grava 1 entrada `audit_logs`. Isso exigiu um `event_type` NOVO `legacy_rollback`
      (migration `20260724110002` estende o CHECK particionado; model/locale/snapshot
      atualizados). "N robôs restantes" passou a significar N VISÍVEIS (`deleted_at IS NULL`).
- **Grupo 3 (pré-processador §4.4) — DELTA.** `Legacy::NormalizeExportService` + `rake
  legacy:normalize` (promove `workspace.projects`/`logs` a topo, remove sentinela, no-op
  em canônico, atômico por temp+rename).
- **Grupo 4 (identidade+idempotência) — DELTA.** `Legacy::IdDerivation` (UUIDv5 sobre o
  caminho legado), wrapper `INSERT … ON CONFLICT (id) DO NOTHING` + `legacy_id_map`, set de
  `app.current_workspace_id` por workspace + procedência `ownerUid`.
- **Grupo 5 (importadores por entidade) — FEITO. Duas reconciliações de schema:**
  - **(a) Membership NÃO é criada:** `memberships.user_id` é NOT NULL (FK `users`), e o mapa
    ownerUid-Firebase → user Rails não é definido nesta change (mesma lacuna do 4.3). Os
    membros do arquivo entram como PESSOAS (via resolver), não como membership/acesso. "Nenhum
    convite importado" vale trivialmente. O acesso real é reconstruído fora deste porte.
  - **(b) Homônimos na mesma célula:** commissioning-hierarchy D-H8 força `UNIQUE (cell_id,
    lower(name))` — CONTRADIZ o cenário de legacy-import "dois R05 viram duas linhas". Não
    afrouxamos a constraint nem quarentenamos (a spec pede duas linhas): DESAMBIGUAMOS o nome
    do colidente (`R05`→`R05 (2)`), determinístico por ordem de aparição, com aviso
    `nome_desambiguado`. O id vem do CAMINHO (índice/id), não do nome → idempotente. Mesmo
    guard aplicado a células (nome) e tarefas (desc), que têm o mesmo índice único parcial.
  - Os "8 services" viraram SEÇÕES do orquestrador `Legacy::ImportService` (métodos por
    entidade) + `AssigneeResolver`/`StatusDerivation`/`ImportReport` à parte. A cascata de
    §1.4, obs→avanço e quarentena vivem no mesmo caminho (as provas por-regra são G6).
- **Grupo 5 (alvos de schema que já existiam):** `people`
  (sentinela no banco ✓), `task_assignees` por `person_id` (robot-tasks ✓), `task_advances`
  contrato `legacy` (`legacy` bool, `by` NULL só se legacy, comentário isento — migration
  20260721160002 ✓), `progress_cache` em robots/cells ✓, enum `task_status` ✓, CHECK
  `chk_robots_application` (6 apps, NÃO é enum — validar em Ruby e quarentenar) ✓,
  `notifications` (msg ≤500, read) ✓. Construir os ~8 services.
- **Grupo 6 (as 3 regras de §1.4) — DELTA.** Cascata de responsáveis (assignees:[] PARA a
  cascata), `obs`→avanço `legacy` (`recorded_at` de `_updatedAt`/`exportedAt`, nunca
  `Time.now`), status↔progresso incoerente (`progress` é fonte da verdade), quarentena
  genérica.
- **Grupo 7 (prova do sentinela) — DELTA (specs), defesa JÁ no banco.** 7.1 importa e prova
  0 pessoas sentinela; 7.2 tenta `INSERT` cru e exige violação de CHECK — a CHECK JÁ existe
  (2.2), então 7.2 testa o que já vale.
- **Grupo 8 (validação/dry-run/corte) — DELTA + 2 BLOQUEADOS.** `Legacy::SampleValidator`
  (recalcula §2.1 ponderado em Ruby PURO, sem AR — prova a tradução), seleção adversarial
  da amostra, `rake legacy:import[arquivo,dry_run]`, recusa de sha256 divergente sem
  `--force`, runbook de corte. **8.6/8.7 = BLOQUEADO: export.**

## Regras que o importador NÃO pode violar (do design)

- Idempotência mora na **PK** (UUIDv5 do caminho), não numa consulta. Toda escrita é
  `ON CONFLICT (id) DO NOTHING` — nunca `DO UPDATE` (sobrescreveria edição pós-corte).
- Nenhuma `Person` "Não Atribuído", em NENHUMA circunstância (3 camadas: normalize →
  resolver único → CHECK do banco).
- Dado inválido → **quarentena** com `legacy_path`+campo+valor+motivo; NUNCA afrouxar
  CHECK nem "consertar" (`progress:150` não vira `100`). Exceção com regra: status↔progresso
  incoerente → `progress` manda, `status` derivado por §2.2.
- Roda como `robotrack_app` sob RLS; `app.current_workspace_id` setado por workspace; sem
  ele, falha ANTES da 1ª escrita (nunca grava no workspace errado).
- `recorded_at` de avanço legado é DETERMINÍSTICO (deriva do arquivo), senão o UUIDv5 do
  avanço muda entre runs e a idempotência (4.4) quebra.

## Ordem de execução

G1 contrato+fixtures → G2 infra (só o delta; 2.2 reconciliada) → G3 normalize → G4 núcleo
(IdDerivation + writer) → G5 importadores → G6 as 3 regras → G7 provas do sentinela →
G8 validação/dry-run/runbook. Por grupo: aplicar → specs dirigidos 0 falhas → `- [x]` →
`validate --strict` → UM commit `G<n>:` → ff `main`. 8.6/8.7 ficam abertos (export ausente).
