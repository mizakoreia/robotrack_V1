# Runbook — corte de migração do legado (RoboTrack_Database.json)

> legacy-data-migration 8.5 (D-LDM-5, D-LDM-6, D-LDM-8). A ordem do big-bang único, com o
> gatilho de rollback. Decidir o rollback às 3h sob pressão, sem runbook, é o modo de falha.

## Pré-requisitos

- `RoboTrack_Database.json` real, exportado do Firebase **vivo** (não está no git).
- `LEGACY_IMPORT_BACKUP_DIR` apontando para um diretório **gravável** (o run recusa iniciar
  sem ele — rede de segurança grossa, D-LDM-6).
- `LEGACY_IMPORT_WORKSPACE_ID` = o workspace de **destino** já criado (o porte NÃO cria
  workspace do zero: o mapa ownerUid-Firebase → user Rails não é definido nesta change).
- Papel `robotrack_app` (sob RLS; o import nunca roda como dono/BYPASSRLS).

## Ordem do corte

1. **normalize** — `rake legacy:normalize[RoboTrack_Database.json,canonico.json]`
   Promove `workspace.projects`/`logs` a topo, remove o sentinela "Não Atribuído", emite
   `schemaVersion: 1`. Idempotente (rodar 2× dá SHA-256 idêntico). Já-canônico é no-op.
2. **schema + dry-run** — `rake legacy:import[canonico.json,true]`
   Valida `schemaVersion == 1` e o arquivo contra `config/legacy_export_v1.schema.json`
   (um `application: 42` falha citando o caminho, **antes** de qualquer escrita). Percorre
   o arquivo inteiro e imprime contagens por entidade + a **quarentena prevista**. NÃO
   escreve e NÃO exige backup. É aqui que se dimensiona a janela (tarefa 8.6).
3. **backup + import** — `LEGACY_IMPORT_WORKSPACE_ID=<ws> rake legacy:import[canonico.json]`
   `pg_dump -Fc` para `LEGACY_IMPORT_BACKUP_DIR` (grava `backup_path`; recusa iniciar se o
   dump falhar). Cria `legacy_import_runs` (com `file_sha256`) e importa idempotentemente
   (`ON CONFLICT (id) DO NOTHING`). Reimportar arquivo de **sha diferente** no mesmo
   workspace exige `LEGACY_IMPORT_FORCE=true` e cita os dois hashes.
4. **recompute** — `rake progress:recompute[<ws>]`
   Recalcula `progress_cache` dos 3 níveis (o import não o computa). Pré-requisito da 5.
5. **validate** — `rake legacy:validate_sample[canonico.json,<ws>]`
   Recalcula §2.1 em Ruby PURO a partir do arquivo (oráculo independente) e compara com o
   `progress_cache` de uma amostra determinística e adversarial (≥20 robôs). **Tolerância
   zero**: um único robô divergente reprova o run inteiro.
6. **2º run (prova de idempotência)** — repetir o passo 3 no mesmo arquivo.
   O relatório deve reportar `criados: 0` para cada entidade e `count(*)` inalterado.

## Gatilho de rollback

Qualquer divergência em (5), ou erro operacional em (3), dispara:

```
rake legacy:rollback[<run_id>]
```

Desfaz **exatamente** o que aquele run criou (por `legacy_id_map`), e só isso — dado criado
por usuários depois do corte é preservado. A hierarquia é **arquivada** (não deletada:
`task_advances`/`audit_logs` são imutáveis — mesmo muro do factory-reset); as folhas soltas
são deletadas; `audit_logs` não é apagado e ganha 1 entrada `legacy_rollback`. Depois do
rollback, volta-se ao passo 2 (dry-run) para re-diagnosticar.

## Divergência de contrato conhecida (D-LDM-8)

O exportador de `workspace-settings` §3.11 hoje emite `schemaVersion: 2` (campo `advances`),
enquanto o importador aceita **apenas** `schemaVersion: 1` (campo `history`). Um arquivo v2
é recusado citando "versão suportada: 1". O alinhamento das duas pontas (o exportador emitir
v1, ou o importador passar a aceitar v2) é uma decisão dos dois donos — até lá, o corte
consome o `RoboTrack_Database.json` do Firebase (v1) direto, sem passar pelo exportador novo.
