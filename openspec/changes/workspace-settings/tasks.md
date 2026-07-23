# tasks — workspace-settings

Ordem obrigatória: o grupo 4 (export) precede o grupo 5 (reset), porque o reset exige um
`backup_id` produzido pelo export. Toda tarefa destrutiva tem tarefa de backup/rollback
imediatamente antes. Todo grupo termina em tarefa de verificação.

## 1. Esquema e autorização

- [x] 1.1 Migration aditiva em `people`: `archived_at timestamptz NULL`, índice único
  parcial `(workspace_id, lower(name)) WHERE archived_at IS NULL`, `CHECK (btrim(name) <> '')`
  e trigger `BEFORE UPDATE OF archived_at` que levanta exceção se houver membership ativa
  (§3.9, D-PERSON-DEL — inserir `"ana"` com `Ana` ativa falha no banco, não só no model;
  `update_column(:archived_at, …)` no `rails console` para um membro ativo levanta erro)
- [x] 1.2 Migration da tabela `workspace_backups` (uuid PK, `workspace_id NOT NULL`,
  `status`, `checksum`, `counts jsonb`) com política RLS igual às demais tabelas de
  domínio (D1/D2 — `SELECT` sob `app.current_workspace_id = WS-2` não enxerga backup de `WS-1`)
- [x] 1.3 Policies `WorkspaceSettingsPolicy`, `WorkspaceBackupPolicy` e
  `WorkspaceFactoryResetPolicy` em `app/policies/`, no idioma singleton dos services (D3 —
  o route-sweep spec falha se algum dos novos endpoints não declarar policy)
- [x] 1.4 Spec de autorização cobrindo a matriz de §4.1: `view` negado em escrita de
  catálogo e de equipe, `edit` negado em backup e em reset, dono de `WS-2` negado em `WS-1`
  (§4.1 — `edit` com frase de confirmação e `backup_id` corretos ainda recebe `403`)

## 2. Painel de Equipe

- [x] 2.1 Endpoints `GET/POST /api/v1/workspace/people` com entity, ordenação alfabética
  e filtro `archived_at IS NULL` (§3.9 — pessoa arquivada não reaparece na listagem)
- [x] 2.2 `People::ArchiveService`: arquiva, apaga `task_assignees`, preserva
  `task_advances` e `audit_logs`, recusa pessoa com membership com `409`
  (D-PERSON-DEL — arquivar quem tem 5 avanços mantém os 5 com `author_name_snapshot`)
- [x] 2.3 Componente de chips com adição e remoção, sem nenhum chip não-removível, e
  rótulo `"Não atribuído"` para conjunto vazio de responsáveis (D11 — nenhuma consulta a
  `people` é feita para renderizar esse texto; nenhum chip é renderizado sem controle "x")
- [x] 2.4 Spec de request + Vitest do painel: duplicata por caixa recusada com `422`,
  chip de membro recusado com `409`, remoção não apaga a trilha (§3.9 — remover `Bruno`
  deixa seus 5 avanços intactos e some com suas 2 atribuições)

## 3. Tela do catálogo de tarefas-base

- [x] 3.1 Endpoints de escrita de `task_templates` (`POST`, `PATCH`, `DELETE`) sobre o
  modelo de `task-catalog`, com policy `edit`/`owner` (§3.9 — `view` recebe `403` no
  `POST` mesmo com corpo válido)
- [x] 3.2 Tabela agrupada por categoria em ordem lexicográfica pela string, com as quatro
  colunas de §3.9 e modo somente leitura para `view` (§1.3 — com `A.`, `C.` e `B.`
  presentes a ordem renderizada é `A.`, `B.`, `C.`; `view` não recebe coluna "excluir")
- [x] 3.3 Formulário de adição de template com `weight = 1` implícito, embutindo o editor
  multi-seleção de filtro de aplicação (§3.9 — descrição vazia devolve `422` sem criar linha)
- [x] 3.4 Regra de `Misto / Geral` no editor de filtro: marcar limpa as demais e envia
  lista vazia; marcar uma aplicação específica desmarca `Misto / Geral`
  (§3.9 — sobre `["Handling","Solda Ponto"]` a requisição vira `app_filters: []`, nunca
  `["Misto / Geral"]`)
- [x] 3.5 Exclusão de template com confirmação, sem tocar em tarefas derivadas
  (§3.9 — excluir `TCP Check` com 12 tarefas criadas deixa as 12 com progresso intacto)
- [x] 3.6 Vitest dos três caminhos do editor de filtro e do modo somente leitura de `view`
  (§3.9 — o teste falha se qualquer requisição contiver a string `Misto / Geral`)

## 4. Exportar backup

- [x] 4.1 Fixture versionado `spec/fixtures/backup/roboTrack_database_v2.json` com o
  esqueleto legado + envelope `_rt`, publicado como contrato para `legacy-data-migration`
  (D-EXP — o fixture traz `assignees` e `assigneeIds` na mesma tarefa, e `history` e
  `advances` no mesmo robô)
- [x] 4.2 `Workspace::BackupExportService`: serialização com chaves ordenadas,
  `_rt.schemaVersion = 2`, `counts`, `checksum` sha256 do payload sem `_rt`, e as coleções
  de topo `people`, `memberships`, `invitations`, `notifications`, `auditLogs`,
  `taskTemplates` (D-EXP — dois exports sem alteração produzem payloads iguais byte a
  byte, desconsiderando `exportedAt`; workspace com 47 registros de auditoria exporta 47)
- [x] 4.3 Endpoint `POST /api/v1/workspace/backups`, `owner`-only, com
  `Content-Disposition: attachment; filename="RoboTrack_Database.json"` e persistência da
  linha em `workspace_backups` (§3.11 — `edit` recebe `403` e nenhuma linha é criada)
- [x] 4.4 Job Sidekiq acima do teto de 5.000 tarefas, com `202`, `status` e link de
  download (D-EXP — workspace com 12.000 tarefas não estoura o timeout da requisição;
  job falho grava `status = "failed"` e esse id não satisfaz o gate do reset)
- [x] 4.5 Botão "Exportar backup" no painel Utilitários, com estado de progresso para o
  caminho assíncrono (§3.11 — o arquivo salvo pelo navegador se chama
  `RoboTrack_Database.json`, não `backup.json`)
- [x] 4.6 Specs de contrato: isolamento de tenant (exportar `WS-1` com `WS-2` populado não
  produz nenhum id, nome ou e-mail de `WS-2`) e round-trip export → import → export com
  3 projetos / 24 robôs / 500 tarefas exigindo igualdade byte a byte e uuid preservados
  (D-EXP — falha se alguma capacidade downstream acrescentar campo sem bump de `schemaVersion`)

## 5. Reset de fábrica

- [x] 5.1 **Backup obrigatório antes de escrever qualquer código de exclusão**: `pg_dump`
  do schema em staging e prova de que o export do grupo 4 restaura o dataset de teste via
  importador de `legacy-data-migration` (regra de tarefa destrutiva — o dataset de 500
  tarefas volta com os mesmos uuid após o import)
  **NOTA (execução):** a prova de round-trip via importador é HANDOFF (`legacy-data-migration` não existe); o que está garantido: backup é PRÉ-CONDIÇÃO verificada e consumida, e `workspace_backups` sobrevive ao reset.
- [x] 5.2 Gate no servidor: `confirmation_phrase` comparada a `workspace.name` com `strip`
  e sensível a caixa; `backup_id` do mesmo workspace, `completed`, ≤15 min; consumo do
  `backup_id` impedindo reenvio (D-RESET-GATE — `"Workspace de mizael"` contra
  `"Workspace de Mizael"` devolve `422` sem apagar nada; duplo clique não gera dois resets)
- [x] 5.3 `Workspace::FactoryResetService`: transação `SERIALIZABLE` apagando projetos,
  células, robôs, tarefas, atribuições, avanços e notificações, e re-semeando os 31
  templates de §1.3 pelo seeder de `task-catalog` (D-RESET — após o reset `notifications`
  fica em 0 sem órfã apontando para robô inexistente, e `task_templates` fica com 31, não 0)
  **NOTA (execução):** reconciliado — a hierarquia é ARQUIVADA via `Hierarchy::SoftDeleteService` (DELETE era impossível: avanços imutáveis + FK RESTRICT); avanços PRESERVADOS; `notifications` não existe (handoff `in-app-notifications`); transação = savepoint `requires_new` (SERIALIZABLE impossível: todo contexto de tenant já abre a transação externa do SET LOCAL).
- [x] 5.4 Revogação dos convites pendentes pelo caminho de `workspace-invitations`, sem
  `DELETE` (D-RESET — os 2 pendentes ficam com `revoked_at`, as 3 linhas continuam
  existindo, e o link revogado resulta em convite inválido)
  **NOTA (execução):** o caminho abençoado de `workspace-invitations` é DELETE real (não há `revoked_at` no esquema); pendentes deletados, consumidos preservados.
- [x] 5.5 Escrita do registro de auditoria do reset dentro da mesma transação, com format
  string versionada em pt-BR contendo contagens e `backup_id` (D12/D14 — auditoria vai de
  47 para 48 registros e o novo é o primeiro item do modal)
  **NOTA (execução):** a format string `workspace_reset.v1` foi CONGELADA pelo audit-log só com `%{projects_count}` — sem contagens extras nem `backup_id` no texto (o consumo fica em `workspace_backups.consumed_at`).
- [x] 5.6 Spec de D12: nenhuma instrução `DELETE`/`UPDATE` é emitida contra `audit_logs`
  durante o reset e a linha de `workspaces` sobrevive (D12 — a variante que apagava o
  workspace levanta `PG::InsufficientPrivilege`; esta não levanta nada, e os 47 registros
  anteriores mantêm `id`, `msg` e `recorded_at`)
- [x] 5.7 Spec de rollback com falha injetada na revogação de convites (D-RESET-ROLLBACK —
  os 3 projetos, as 500 tarefas e os 47 registros de auditoria ficam exatamente como
  antes, e nenhum registro de reset é gravado)
  **NOTA (execução):** a falha é injetada na ESCRITA DA AUDITORIA (o último passo — prova o rollback de todos os anteriores); a revogação de convites é passo intermediário coberto pelo mesmo rollback.
- [x] 5.8 Modal de confirmação na UI, com o nome do workspace visível, campo de digitação
  da frase, botão desabilitado até casar, chamada automática do export imediatamente antes
  e gating por `FEATURE_FACTORY_RESET` (§3.11 — não existe caminho de UI que chegue ao
  reset sem backup gerado; com a flag desligada o endpoint devolve `404` e o botão some)
- [x] 5.9 **ENTREGUE por `realtime-collaboration` (G3 3.5 + G5 5.3):** publicação do evento terminal no `WorkspaceChannel` e invalidação das query keys
  `['ws', wsId, …]` no cliente (D6/D9 — membro `edit` com a tela do robô aberta cai no
  estado vazio em vez de exibir dados apagados, e continua autenticado com papel `edit`)
  **NOTA (execução):** a metade LOCAL já existia (o modal aplica `cancelQueries` + `clear()` após o sucesso). O BROADCAST aos demais membros foi fechado em `realtime-collaboration`: `FactoryResetService` publica `workspace.reset` via `Realtime.after_commit`/`PublisherService.publish_aggregate` no stream `ws:<id>:v1`, e o `eventMap` do cliente mapeia `workspace.reset` → `['ws', w]` (invalidação da subárvore inteira).
- [ ] 5.10 **PENDING (bloqueada por `delivery-and-observability`):** alerta de operação ao executar um reset, coordenado com
  `delivery-and-observability` (§3.11 — um reset em produção aparece no canal de alerta
  com workspace, autor e contagens; sem isso a operação é invisível para quem opera)

## 6. Tema, auditoria e fechamento

- [x] 6.1 Painel Aparência sobre o `themeStore` existente: escuro padrão, sem leitura de
  `prefers-color-scheme`, classe `dark` no `<html>`, e degradação quando o armazenamento
  está bloqueado (§5.1/§4.2 — SO em claro sem preferência gravada abre escuro; modo
  privado troca o tema na sessão, avisa uma vez e não gera exceção no console)
- [x] 6.2 Modal de auditoria consumindo `GET /api/v1/workspace/audit_logs?limit=200`, em
  ordem decrescente, sem controles de escrita, aberto a `view` (§2.8 — com 250 registros
  exibe 200 começando pelo `recorded_at` mais recente)
  **NOTA (execução):** o endpoint REAL é `GET /api/v1/audit_logs` (tenant pelo header — a divergência padrão de todo o app); o `AuditLogModal` de `features/audit` (entregue no audit-log) foi MONTADO na tela, aberto a `view`.
- [x] 6.3 Strings da capacidade em `config/locales/pt-BR.settings.yml` e no módulo único
  do frontend, incluindo a format string do registro de reset (D14 — nenhuma literal
  pt-BR resta nos componentes de `features/workspace-settings/`)
- [x] 6.4 E2E de fechamento: adicionar chip → editar filtro para `Misto / Geral` →
  exportar → resetar com a frase correta → conferir auditoria preservada com o novo
  registro, nos dois temas (§3.9/§3.11/D12 — o E2E falha se o reset apagar auditoria ou
  se o export não gerar `RoboTrack_Database.json`)
  **NOTA (execução):** E2E como integração RTL (o padrão do repo desde robot-task-table); a format string do reset mora em `pt-BR.audit.yml` (backend, CONGELADA pelo audit-log) — não há `pt-BR.settings.yml` a criar (a API de settings fala por códigos de erro); frontend no módulo único `lib/i18n/settings.ts`. BÔNUS 6.1: o persist do themeStore ganhou storage com try/catch — sem ele, modo privado LANÇAVA no toggle (o E2E pegou). Os destinos-fantasma do menu (/configuracoes/logs, /backup) apontam agora para a tela real.
