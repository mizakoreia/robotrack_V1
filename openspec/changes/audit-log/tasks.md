# Tarefas — audit-log

Pré-requisitos de outras capacidades (não implementar aqui): `workspace-tenancy`
(`workspaces`, `people`, RLS e `app.current_workspace_id`), `authorization-policies`
(convenção de policy + route-sweep), `progress-advances` (`task_advances` e a transação de
avanço).

## 1. Papéis Postgres e credenciais

- [x] 1.1 Criar migration idempotente que cria os papéis `robotrack_migrator` (dono das
  tabelas) e `robotrack_app` (runtime), com `GRANT` padrão de DML no esquema de domínio
  para `robotrack_app`, e documentar em `delivery-and-observability` as duas credenciais
  resultantes (`DATABASE_URL` = `robotrack_app`, `MIGRATION_DATABASE_URL` =
  `robotrack_migrator`). (§4.1 inv. 3 — rodar a migration duas vezes seguidas não pode
  falhar com "role already exists"; deploy com uma credencial só deixa a camada de
  privilégio inerte)
- [x] 1.2 Adicionar verificação de boot que aborta o processo se
  `has_table_privilege(current_user, 'audit_logs', 'UPDATE')` for verdadeiro, com mensagem
  nomeando a tabela e o privilégio. (spec `audit-log` — subir com `DATABASE_URL` do papel
  dono precisa quebrar o boot, não passar silenciosamente)
- [x] 1.3 **Verificação:** spec que conecta como `robotrack_app` e afirma que
  `pg_catalog` não lista `UPDATE` nem `DELETE` sobre `audit_logs` para esse papel. (spec
  `audit-log-retention` — zero papéis de rotina com `DELETE`)

## 2. Esquema de `audit_logs`

- [x] 2.1 Migration criando `audit_logs` particionada por faixa sobre `ts`, PK `(ts, id)`,
  colunas `workspace_id`, `msg`, `ts`, `ts_local`, `by_person_id`, `by_name`, `event_type`,
  `format_version`, `payload`, FK `workspaces ON DELETE RESTRICT`, sem FK para hierarquia,
  incluindo `REVOKE UPDATE, DELETE ... FROM robotrack_app` e um `def down` que levanta
  `IrreversibleMigration` quando a tabela tem linhas. (§1.1 — `INSERT` sem `workspace_id`
  precisa violar `NOT NULL`; excluir um robô não pode levar registro junto; rollback depois
  do primeiro registro em produção não pode ser um `DROP TABLE` silencioso)
- [x] 2.2 Criar as partições dos 3 meses seguintes mais a partição `DEFAULT` e o índice
  `(workspace_id, ts DESC)` em cada uma. (spec `audit-log-retention` — registro
  `2026-03-14` tem que residir em `audit_logs_2026_03`)
- [x] 2.3 Habilitar RLS com políticas de `SELECT` e `INSERT` por
  `app.current_workspace_id`, sem declarar política de `UPDATE`/`DELETE`. (§4.1 inv. 3 —
  sessão do workspace A contando linhas com 3 de A e 5 de B tem que ver 3, e `INSERT` com
  `workspace_id` de B tem que falhar no `WITH CHECK`)
- [x] 2.4 Criar a função `audit_logs_immutable()` e a trigger `BEFORE UPDATE OR DELETE ...
  FOR EACH ROW`, que levanta exceção sem inspecionar papel ou linha. (§2.8 — `UPDATE` pelo
  papel dono da tabela, para quem o `REVOKE` não vale, tem que abortar)
- [x] 2.5 **Verificação:** spec que, como `robotrack_migrator`, tenta `UPDATE` e depois
  `DELETE` numa linha existente e espera exceção da trigger em ambos; e outro spec que
  confirma que `INSERT` continua passando. (spec `audit-log` — a trigger não pode barrar
  escrita legítima)

## 3. Model, service de escrita e locale

- [x] 3.1 Criar `AuditLog` (readonly no ActiveRecord, `self.primary_key = 'id'`, sem
  `has_many` reverso a partir da hierarquia) e a factory correspondente. (§2.8 — chamar
  `save` num registro carregado precisa levantar `ReadOnlyRecord` antes mesmo de tocar o
  banco)
- [x] 3.2 Criar `config/locales/pt-BR.audit.yml` com `audit.task_completed.v1` e
  `audit.workspace_reset.v1`. (D14 — a renderização de `R-014` / `Ana Ribeiro` /
  `"Solda ponto 3"` tem que sair exatamente
  `Em [R-014], Ana Ribeiro concluiu a tarefa "Solda ponto 3" com 100%.`)
- [x] 3.3 Implementar `AuditLog::RecordService.record!(workspace:, event:, by:, payload:)`
  no idioma singleton de `ApiResponseHandler`, renderizando `msg` e `ts_local` no momento
  do `INSERT` e gravando `format_version`. (Decisão 4 — publicar uma `v2` da format string
  não pode alterar o texto de um registro já gravado)
- [x] 3.4 Implementar os snapshots de nome do service: `by_person_id` a partir da `Person`
  do autor com `by_name` copiado (aceitando `by_person_id NULL`), e a junção de
  responsáveis para `%{assignees}` com os nomes vigentes na conclusão. (D10 — renomear a
  `Person` para `Ana R. Souza` não pode reescrever `by_name = 'Ana Ribeiro'`; dois
  responsáveis produzem `Ana Ribeiro, Bruno Sá ... concluiu`, no singular do `v1`)
- [x] 3.5 Adicionar spec de CI que compara as chaves `vN` do locale com as da branch `main`
  e falha se uma versão publicada foi editada. (Decisão 5 — alterar o texto de `v1` em vez
  de criar `v2` tem que quebrar o build nomeando a chave)
- [x] 3.6 **Verificação:** spec do service cobrindo autor sem `Person` resolvível
  (`by_name = '(nota anterior)'`, `by_person_id NULL`) e `by_name` vazio (rejeitado por
  `NOT NULL`). (§1.4 — importação legada não pode ser bloqueada por autor irresolúvel)

## 4. Gatilho de conclusão a 100%

- [x] 4.1 Ligar `AuditLog::RecordService.record!` à transição de progresso para `100` em
  `progress-advances`, **dentro** da transação do avanço. (§2.2 — avanço de `90` para
  `100` com `INSERT` de log forçado a falhar tem que deixar a tarefa em `90` e sem
  `task_advance` novo)
- [x] 4.2 Garantir que avanços que não atingem 100 não geram registro, incluindo transição
  de `N/A` e reabertura de tarefa. (§2.2 — avanço de `45` para `90` mantém a contagem de
  registros inalterada)
- [x] 4.3 **Verificação:** spec que reenvia a mesma mutação offline com o mesmo uuid
  cliente-gerado e afirma que continua existindo 1 registro `task_completed` para a tarefa.
  (Decisão 3 — a idempotência vem da PK do avanço; se ela deixar de valer, este spec é o
  detector)

## 5. Leitura, policy e endpoint

- [x] 5.1 Criar `AuditLogPolicy` com `index?` liberado para `owner`, `edit` e `view`, e
  nenhum outro método de ação. (§4.1 — membro `view` recebe `200 OK` no modal; não-membro
  recebe `403` sem corpo de registro)
- [x] 5.2 Criar `Api::Entities::AuditLog` (expondo `id`, `msg`, `ts`, `ts_local`,
  `by_name`, `event_type`, **sem** `payload` nem `by_person_id`) e montar
  `GET /api/v1/workspaces/:workspace_id/audit_logs` em `api/v1/base.rb` com
  `ORDER BY ts DESC` e clamp de `limit` a 200 no service. (§2.8 — `?limit=1000` num
  workspace com 250 registros retorna 200, e o payload interno não vaza no JSON)
- [x] 5.3 **Verificação:** spec de request cobrindo `POST`, `PUT`, `PATCH` e `DELETE` no
  recurso, todos esperando `404`, mais o route-sweep confirmando exatamente 1 endpoint de
  auditoria com policy declarada. (§4.1 inv. 1 — o dono não pode ter rota de exclusão nem
  por acidente de `resources`)

## 6. Modal de auditoria no frontend

- [x] 6.1 Adicionar `auditLogs.list(workspaceId)` em `lib/api/endpoints.ts` e o hook
  React Query com a chave `['ws', wsId, 'auditLogs']`. (D9 — nada de `useEffect` +
  `apiClient`; a chave precisa ser invalidável por `realtime-collaboration` depois)
- [x] 6.2 Implementar o modal de auditoria consumindo `msg` e `ts_local` verbatim, ordem já
  vinda do servidor, sem re-formatar data no cliente, com estados vazio e de erro. (Decisão
  4 — abrir o modal em um navegador em `UTC` e em outro em `America/Sao_Paulo` tem que
  mostrar o mesmo texto; workspace novo mostra estado vazio em vez de lista quebrada)
- [x] 6.3 **Verificação:** teste de componente com fixture de 250 registros afirmando que
  200 itens são renderizados, o primeiro é o mais recente e os 50 mais antigos não
  aparecem. (§2.8 — limite de exibição)

## 7. Fronteira com o reset de fábrica (D12)

- [ ] 7.1 Publicar o contrato de `AuditLog::RecordService.record!` para
  `workspace-settings`, com a chave `audit.workspace_reset.v1` e o `payload` esperado
  (`projects_count`). (D12 — o dono do reset precisa de um caminho de escrita pronto, não
  de um `AuditLog.create` ad hoc)
- [ ] 7.2 **Verificação:** spec de integração que executa o reset num workspace com 12
  registros e 3 projetos e afirma 13 registros ao final, com o 13º de tipo
  `workspace_reset` e os 12 anteriores byte-idênticos. (D12 — a contradição herdada só é
  considerada resolvida com este spec verde)
- [ ] 7.3 **Verificação:** spec negativo que emite
  `DELETE FROM audit_logs WHERE workspace_id = <id>` dentro da transação do reset e afirma
  rollback integral, com os 3 projetos ainda existentes. (spec `audit-log` — prova que a
  variante antiga do reset é impossível de executar, não apenas desaconselhada)

## 8. Retenção e observabilidade

- [ ] 8.1 Implementar job mensal de manutenção de partições: cria as dos 3 meses seguintes
  e alerta se a partição `DEFAULT` tiver linhas. (spec `audit-log-retention` — mês corrente
  sem partição não pode derrubar conclusão de tarefa)
- [ ] 8.2 Implementar exportação de partição para JSONL comprimido em storage frio, com
  contagem de linhas e checksum gravados no manifesto. (spec `audit-log-retention` —
  `AUDIT_ARCHIVE_BUCKET` ausente tem que falhar com erro nomeando a variável)
- [ ] 8.3 **Backup/prova antes do passo destrutivo:** implementar a verificação que compara
  contagem e checksum do arquivo com a partição e aborta em divergência. (spec
  `audit-log-retention` — partição de 4.312 linhas com arquivo de 4.310 aborta e preserva
  tudo)
- [ ] 8.4 Implementar o `DETACH PARTITION` + `DROP TABLE` da partição, gated pela
  verificação de 8.3 e por uma flag de confirmação da janela de 24 meses (default:
  desligada). (design §Perguntas em aberto 3 — enquanto a janela não for confirmada,
  partição de 30 meses é arquivada mas não destacada)
- [ ] 8.5 Expor métricas de contagem e tamanho por partição e o alerta de queda de
  contagem fora de janela de manutenção, coordenando com
  `delivery-and-observability`. (spec `audit-log-retention` — queda de 812.400 para 640.100
  sem manutenção declarada alerta; queda igual ao arquivado não alerta)
- [ ] 8.6 **Verificação:** spec do job afirmando que o SQL emitido contém `DETACH
  PARTITION` e `DROP TABLE` e não contém `DELETE FROM audit_logs`. (spec
  `audit-log-retention` — retenção por DML é o modo de falha que a invariante 3 proíbe)

## 9. Encerramento

- [ ] 9.1 Registrar em `seal-template-baseline` a recomendação de remover `paper_trail` do
  Gemfile, com o parecer da Decisão 8 anexado. (design Decisão 8 — a gem tem `destroy_all`
  e poda por `limit` na API pública, incompatíveis com §4.1 inv. 3)
- [ ] 9.2 **Verificação final:** suíte de contorno reunindo `update_column`, `update_all`,
  `delete_all`, `UPDATE` cru pelo papel de app e `UPDATE` cru pelo papel dono, todos
  esperando falha de banco. (§4.1 inv. 3 — se qualquer um desses passar, a invariante é
  teatro)
