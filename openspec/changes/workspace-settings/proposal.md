# Configurações do workspace: equipe, catálogo, backup, reset e tema

## Why

A ESPECIFICACAO.md espalha as configurações do workspace por duas seções curtas que,
lidas juntas, escondem a operação mais perigosa do produto inteiro:

- **§3.9** — *Equipe*: lista de responsáveis como chips, adicionar e remover, com a
  ressalva de que `"Não Atribuído"` **não é removível**. *Tarefas-base*: tabela do
  catálogo (categoria, descrição, filtro de aplicação, excluir), adicionar template, e
  editar o filtro de aplicação — com a regra de que escolher `Misto / Geral` **limpa** o
  filtro (= vale para todas as aplicações).
- **§3.11** — *Utilitários*: exportar backup em JSON com nome de arquivo literal
  (`RoboTrack_Database.json`), **reset de fábrica** (apaga todos os projetos e o
  workspace, só o dono, com confirmação explícita, em operação atômica), alternância de
  tema claro/escuro persistida localmente, e o **modal de auditoria** (§2.8).
- **§4.1** — a matriz de permissões separa duas linhas distintas: "editar catálogo de
  templates e responsáveis" é `owner`+`edit`; "excluir workspace / reset de fábrica" é
  **`owner` sozinho**. E a invariante 3 declara o log de auditoria append-only **para
  todos, inclusive o dono**.

Três dessas linhas se contradizem e o plano anterior nunca reconciliou:

1. **§3.9 vs. D11.** A regra "`Não Atribuído` não é removível" só existia porque o
   legado usava a string como **sentinela** dentro da lista `responsibles` do workspace
   (§1.1) e como valor de `resp` (§1.4 item 1). Removê-la quebraria o modelo. Pela
   decisão transversal **D11** esse sentinela foi **abolido**: ausência de responsável é
   conjunto vazio e `"Não atribuído"` vira apenas uma string de UI. Logo a regra de
   não-removibilidade **desaparece** — não é portada. Isto é uma mudança de
   comportamento declarada, não um esquecimento.
2. **§3.11 vs. §4.1 inv. 3 (a contradição de D12).** O plano anterior tinha
   simultaneamente `REVOKE UPDATE, DELETE` em `audit_logs` e um reset de fábrica que
   "apaga todos os projetos e o workspace". As duas regras são incompatíveis: apagar o
   workspace cascateia para `audit_logs`, a instrução bate no privilégio revogado e
   **aborta a transação atômica inteira**. O reset, como planejado, era **fisicamente
   impossível de executar** e ninguém percebeu. **D12** fixa a resolução e esta proposta
   é dona dela: o reset **não apaga a auditoria**; apaga projetos/células/robôs/tarefas e
   **grava no próprio log** que o reset ocorreu.
3. **§3.11 nomeia o arquivo.** `RoboTrack_Database.json` é um nome literal, não uma
   descrição. Nome literal é **contrato de formato**: existem arquivos desse nome no
   disco de usuários do legado, e `legacy-data-migration` consome exatamente esse formato
   na direção oposta. O plano anterior tratou o export como "serializa o estado" e não
   decidiu nada sobre compatibilidade. Esta proposta decide (ver `design.md`, D-EXP).

Além disso, o plano anterior descrevia o reset em uma linha e **omitia tudo que importa**:
não havia backup antes, não havia rollback, e não se dizia o que acontece com a `Person`
do dono, as memberships, os convites pendentes e as notificações. Uma operação que apaga
dados de produção sem destino declarado por entidade não é especificação — é um bug com
formatação de markdown.

## What Changes

- **Tela de configurações do workspace** (rota `/ws/:wsId/settings`), com quatro painéis:
  Equipe, Tarefas-base, Utilitários e Aparência. Gate de papel na UI **e** por policy
  (**D3**): `view` não recebe nenhum controle de escrita; `edit` recebe os de catálogo e
  equipe; só `owner` recebe Utilitários destrutivos.
- **Equipe (§3.9)** como chips de `Person` (**D10**), não de string. Adicionar cria
  `Person` com `user_id NULL` (pessoa do chão de fábrica sem conta). Remover é
  **arquivamento** (`archived_at`), nunca `DELETE` físico — `task_advances` carrega
  `author_name_snapshot` e a trilha é append-only. **BREAKING vs. §3.9:** não existe mais
  chip não-removível; a regra do sentinela `"Não Atribuído"` é abolida por **D11**.
- **Tela do catálogo de tarefas-base (§3.9)**: tabela agrupada por categoria em ordem
  lexicográfica pelo prefixo alfabético (§1.3), colunas categoria/descrição/filtro de
  aplicação/excluir; formulário de adição; editor multi-seleção do filtro de aplicação
  em que marcar `Misto / Geral` **esvazia** o conjunto (`app_filters = []` = vale para
  todas). O **modelo, o enum de Aplicação, o seed dos 31 templates e a semântica de
  `app_filters` (incluindo aceitar `apps` legado) são de `task-catalog`** — esta
  capacidade entrega a tela e os endpoints de escrita que ela consome.
- **Exportar backup (§3.11)**: `POST /api/v1/workspace/backups` produz
  `RoboTrack_Database.json` num **formato superset aditivo** do legado (decisão D-EXP),
  registra um `WorkspaceBackup` com hash e contagens, e devolve `backup_id` +
  download. Escopo `owner` (carrega e-mails de membros e convites).
- **Reset de fábrica (§3.11 + D12)**: `POST /api/v1/workspace/factory_reset`, exclusivo
  do `owner`, exigindo (a) frase de confirmação igual ao nome do workspace, validada **no
  servidor**, e (b) um `backup_id` do próprio workspace criado há **≤ 15 minutos**. Uma
  única transação: apaga projetos → células → robôs → tarefas → avanços → notificações,
  revoga convites pendentes, restaura o catálogo ao seed de fábrica, **preserva
  `audit_logs`** e grava nele a entrada do reset. O registro `workspaces` **não é
  apagado**; memberships e `Person` sobrevivem. Destino por entidade em `design.md`.
- **Alternância de tema** claro/escuro no painel Aparência, persistida localmente via o
  `themeStore` Zustand já existente no template, **escuro por padrão e deliberadamente
  sem seguir a preferência do SO** (§5.1), com degradação silenciosa quando o
  armazenamento está bloqueado (§4.2).
- **Modal de auditoria (§2.8)**: 200 registros mais recentes, ordem decrescente. Só a
  tela — **modelo, imutabilidade e retenção são de `audit-log`**.
- Eventos de mutação publicados no `WorkspaceChannel` (**D6**); o reset publica um evento
  terminal que força os clientes conectados a descartar o estado do workspace.

### Não-objetivos

- **Não** define `task_templates`, o enum de Aplicação, o seed dos 31 itens nem a
  sincronização retroativa de templates → `task-catalog`.
- **Não** define `audit_logs`, `REVOKE`, trigger de imutabilidade nem retenção →
  `audit-log`.
- **Não** faz gestão de membros/papéis nem revogação de convite pela via normal →
  `workspace-invitations`. O reset apenas **invoca** a revogação existente.
- **Não** implementa o importador do JSON exportado → `legacy-data-migration`. Esta
  capacidade fixa o formato e entrega o fixture de round-trip; o consumo é de lá.
- **Não** define tokens de tema, Chip, Modal ou Card → `design-system`.
- **Não** cria interface de restauração de backup dentro do app na v1 (só download +
  importador de `legacy-data-migration` por linha de comando). Justificado em `design.md`.
- **Não** entrega retenção server-side dos arquivos de backup além dos 15 min exigidos
  pelo gate do reset; armazenamento de longo prazo é de `delivery-and-observability`.

## Capabilities

### New Capabilities

- `workspace-settings-screen`: tela de configurações — painel de Equipe (chips de
  `Person`), tela do catálogo de tarefas-base, alternância de tema e modal de auditoria,
  com gate de papel em todos os controles.
- `workspace-backup-export`: export do estado completo do workspace como
  `RoboTrack_Database.json` em formato superset do legado, com registro de `WorkspaceBackup`.
- `workspace-factory-reset`: reset de fábrica atômico, exclusivo do dono, com
  confirmação por frase, backup obrigatório recente, destino declarado por entidade e
  preservação da auditoria (**D12**).

### Modified Capabilities

Nenhuma. `openspec/specs/` está vazio — nada foi construído ainda.

### Impact

- **Backend**: `app/controllers/api/v1/workspace_settings.rb`, `.../workspace_backups.rb`,
  `.../workspace_factory_reset.rb` montados em `api/v1/base.rb`; services
  `Workspace::BackupExportService`, `Workspace::FactoryResetService`,
  `People::ArchiveService`; policies `WorkspaceSettingsPolicy`, `WorkspaceBackupPolicy`,
  `WorkspaceFactoryResetPolicy` (**D3**, route-sweep); entities de backup; migration da
  tabela `workspace_backups` e da coluna `people.archived_at`; locale
  `config/locales/pt-BR.settings.yml` (**D14**).
- **Frontend**: `features/workspace-settings/` (páginas e painéis), extensão de
  `lib/api/endpoints.ts`, query keys `['ws', wsId, 'people']`,
  `['ws', wsId, 'task-templates']`, `['ws', wsId, 'audit-logs']` (**D9**).
- **Depende de**: `task-catalog` (modelo de template), `workspace-invitations` (revogação
  de convite, painel de membros), `audit-log` (modelo e caminho de escrita),
  `authorization-policies`, `workspace-tenancy` (RLS, `Person`), `design-system`,
  `app-shell-navigation`, `realtime-collaboration` (**D6**).
- **Entrega**: precisa de um diretório de artefatos de backup com escrita e TTL em
  produção (variável `BACKUP_STORAGE_PATH` ou bucket), e de alerta quando um
  `factory_reset` executa — ambos são de `delivery-and-observability`.
- **Risco de dado**: esta é a única capacidade do projeto que apaga dados de produção em
  massa. Toda tarefa destrutiva em `tasks.md` tem tarefa de backup imediatamente antes.
