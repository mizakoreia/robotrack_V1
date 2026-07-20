## Why

Esta capacidade cobre **§1.4 (compatibilidade com dados legados)** e **§4.4 (migrações
automáticas implementadas)** da ESPECIFICACAO.md. Ela é a última onda do porte (Onda 9)
porque só faz sentido quando todo o domínio já está modelado: sem `workspaces`, `people`,
`memberships`, `projects`, `cells`, `robots`, `tasks`, `task_assignees`, `task_templates`,
`task_advances`, `audit_logs` e `notifications` no lugar, não há para onde importar.

O insumo é um único arquivo: o export do Firestore do sistema legado,
`RoboTrack_Database.json` — o **mesmo formato** que `workspace-settings` (§3.11) produz
na direção oposta (exportar backup). Nós o consumimos; eles o emitem. O formato é um
contrato de duas pontas e precisa ser escrito uma vez só.

O documento Firestore é um grafo aninhado (`workspace → projects[] → cells[] → robots[]
→ tasks[] → history[]`) com três compatibilidades de leitura tolerante acumuladas ao
longo da vida do produto (§1.4 itens 1/2/3) e duas migrações estruturais inacabadas
(§4.4). No legado, essas cinco coisas eram **código de runtime**: rodavam em cada
leitura, no cliente, de forma preguiçosa. No porte relacional isso não pode continuar —
um esquema com constraints não aceita "dado meio migrado que se conserta na próxima
leitura". As cinco viram **regras do importador**, executadas uma vez, offline, num
processo com backup e rollback.

Duas capacidades já declararam que estão nos entregando essa responsabilidade e nós
precisamos honrar o contrato delas:

- `progress-advances` → **§1.4 item 2 mudou de lugar de propósito**: a conversão de `obs`
  em entrada de histórico deixa de ser preguiçosa-em-runtime e passa a ocorrer no
  importador em lote. Consequência declarada por eles: `tasks` **não tem coluna `obs`**.
  Contrato da entrada legada (proposal.md deles, seção "Avisos a outras capacidades" e
  design D-LEG): autor nulo, `author_name_snapshot = "(nota anterior)"`,
  `from_progress = to_progress = 0`, `legacy = true`, isenta da CHECK de comentário.
- `robot-tasks` → **§1.4 item 1 é implementado exclusivamente aqui** (design D-RT-2). O
  esquema novo não carrega `resp` e o backend nunca grava
  `resp = assignees[0] || "Não Atribuído"`. A cascata de leitura tolerante existe só
  dentro do importador.
- `task-catalog` → §1.4 item 3 (`apps` ≡ `appFilters`) é aceito na fronteira da API deles
  (design D-TC-5); nós aceitamos o mesmo par de nomes na fronteira do **arquivo**.

Por fim, **D11**: o sentinela `"Não Atribuído"` é abolido no modelo. Ausência de
responsável é conjunto vazio. Um importador ingênuo que faça "resolva cada nome de
`assignees`/`resp` para uma linha de `Person`" cria alegremente uma pessoa **chamada
"Não Atribuído"** — e a partir daí ela aparece no modal de atribuição (§3.5), recebe
notificação (§2.7) e polui "Minhas Tarefas" (§3.6). Essa armadilha é o ponto de falha
mais provável desta capacidade inteira.

## What Changes

- **Pré-processador estrutural offline (§4.4)** — `rake legacy:normalize[in,out]`. Lê o
  export bruto, detecta o formato antigo (projetos aninhados no documento do workspace;
  logs aninhados) e emite um export **canônico** com projetos e logs promovidos a
  coleções próprias. **BREAKING (mecanismo, em relação ao legado):** deixa de ser código
  de runtime disparado pela primeira leitura do dono e passa a ser uma tarefa offline
  explícita. As três propriedades do legado ("uma única vez", "só pelo dono", "atômica")
  são preservadas por outros meios, não por acidente de quem leu primeiro — ver
  `design.md` D-LDM-1.
- **Importador idempotente e re-executável** — `rake legacy:import[file]`, um serviço por
  tipo de entidade, todos derivando PK **determinística** (UUIDv5 sobre o caminho legado)
  e gravando com `INSERT … ON CONFLICT (id) DO NOTHING`. Segunda execução do mesmo
  arquivo cria **zero** registros novos e não altera nenhum campo.
- **As três regras de leitura tolerante de §1.4**, agora no importador:
  1. **Responsáveis** — cascata `assignees` (lista) → `resp` ≠ `"Não Atribuído"` →
     vazio; nomes resolvidos para `people.id` (D10).
  2. **Nota livre → histórico** — tarefa com `obs` preenchido vira a **primeira** entrada
     de `task_advances` no contrato `legacy` de `progress-advances`.
  3. **Filtro de aplicação** — `appFilters` e o nome antigo `apps` são aceitos, com
     precedência definida quando os dois vierem.
- **Filtro do sentinela `"Não Atribuído"` (D11)** em ponto único, com **defesa em
  profundidade no banco**: CHECK em `people.name` — não só um `reject` em Ruby.
- **Normalização defensiva (§1.4)** — projeto sem `cells`, célula sem `robots`, robô sem
  `tasks`, tarefa sem `history` importam como lista vazia; nunca abortam o run.
- **Renumeração de ordem** — `_ord` (timestamp na criação, §2.9) e a posição implícita nos
  arrays viram `position` inteira contígua 0-based, conforme
  `commissioning-hierarchy` já declarou.
- **Backup e rollback** — `pg_dump` obrigatório antes de qualquer escrita; tabela
  `legacy_import_runs` registrando cada execução; `rake legacy:rollback[run_id]`
  removendo apenas o que aquele run criou.
- **Validação por amostragem (≥20 robôs, diferença zero de progresso)** — comparada
  contra o **JSON de export**, não contra o sistema legado vivo (ver Não-objetivos e
  `design.md` D-LDM-5).
- **Compatibilidade de formato do backup** — o schema JSON versionado
  (`legacy_export_v1.schema.json`) é escrito aqui e **consumido por
  `workspace-settings`** como formato de saída do "Exportar backup JSON" (§3.11).

### Não-objetivos

- **Manter o sistema legado (PWA + Firebase) executável para comparação lado a lado.**
  O plano anterior pedia isso sem nunca providenciar infraestrutura, credenciais ou
  ambiente. Recusamos explicitamente: a fonte de verdade da validação é o **arquivo de
  export**, que é imutável, versionável e commitável como fixture. Se alguém quiser a
  comparação contra o sistema vivo, é projeto separado com custo próprio.
- **Sincronização contínua / dupla escrita / migração incremental.** É um corte único
  (big-bang) por workspace. Não há janela de operação simultânea.
- **UI de importação.** O importador é CLI/rake, operado por quem faz o deploy. Botão
  "importar" na tela é escopo futuro; `workspace-settings` só exporta.
- **Definição do cálculo de progresso.** É `progress-rollup` (D5, D15). Nós só
  **recalculamos e conferimos**, usando a implementação deles.
- **Migração de contas de usuário do Firebase Auth** (senhas, provedores). É
  `identity-and-auth` (D4). Importamos `people`, não credenciais; `person.user_id` fica
  nulo até a pessoa aceitar convite (D10).
- **Alteração de qualquer schema de domínio.** Só criamos `legacy_import_runs` e
  `legacy_id_map`. Se um dado legado não couber numa constraint existente, isso é um
  **quarantine record**, não um relaxamento de constraint.

### BREAKING

- **BREAKING (legado):** `tasks.obs` e `tasks.resp` não existem no destino. Todo dado
  neles é convertido (item 2 / item 1) ou descartado com registro em quarentena.
- **BREAKING (legado):** `"Não Atribuído"` deixa de ser um valor de dado. Nenhuma linha
  de `people` pode tê-lo como nome (D11).
- **BREAKING (mecanismo):** §4.4 deixa de ser migração automática em runtime.

## Capabilities

### New Capabilities

- `legacy-import`: importador idempotente e re-executável do export Firestore para o
  esquema relacional — mapeamento por tipo de entidade, PK determinística, as três regras
  de leitura tolerante de §1.4, filtro do sentinela `"Não Atribuído"` (D11), normalização
  defensiva e quarentena de registros irreparáveis.
- `legacy-structural-migrations`: as duas migrações estruturais de §4.4 (projetos
  aninhados → registro próprio; logs aninhados → coleção própria) reimplementadas como
  pré-processador offline, com as garantias de execução única, autoria do dono e
  atomicidade preservadas explicitamente.
- `legacy-import-validation`: backup obrigatório, rollback por run, validação por
  amostragem de ≥20 robôs contra o export, e o schema JSON versionado compartilhado com
  `workspace-settings`.

### Modified Capabilities

Nenhuma. `openspec/specs/` está vazio — nada foi construído ainda.

### Impact

- **Banco**: 2 tabelas novas de infraestrutura (`legacy_import_runs`, `legacy_id_map`) +
  1 CHECK novo em `people` (`name <> 'Não Atribuído'`, D11) + 1 índice único
  `(workspace_id, lower(name))` em `people`. Nenhuma tabela de domínio é alterada.
- **Backend**: `lib/tasks/legacy.rake`, `app/services/legacy/normalize_export_service.rb`,
  `app/services/legacy/import_*_service.rb` (um por entidade),
  `app/services/legacy/assignee_resolver.rb`, `app/services/legacy/id_derivation.rb`,
  `app/services/legacy/sample_validator.rb`, `config/legacy_export_v1.schema.json`,
  `config/locales/pt-BR.legacy.yml` (D14).
- **Frontend**: nenhum. Esta capacidade não tem tela.
- **Entrega** (`delivery-and-observability`): precisa de `LEGACY_IMPORT_BACKUP_DIR`,
  `LEGACY_IMPORT_BATCH_SIZE` (padrão `500`) e de um runbook de corte com janela de
  manutenção. O import roda **fora** do Sidekiq (processo rake dedicado) para não
  competir com fila de produção.
- **Avisos a outras capacidades** — precisam ler isto antes de fechar suas specs:
  - `workspace-settings`: o exportador de §3.11 **deve** emitir
    `config/legacy_export_v1.schema.json`, com `schemaVersion` no topo. Não invente
    formato próprio.
  - `progress-advances`: dependemos da isenção da CHECK de comentário para
    `legacy = true` e de `by` nullable. Se isso mudar, o item 2 de §1.4 fica
    inimportável.
  - `workspace-tenancy`: dependemos de um caminho de criação de `Person` com
    `user_id` nulo, sem convite (D10), e do CHECK de D11.
  - `task-catalog`: pode receber `app_filters` contendo `"Todas"` vindo do legado; a
    predicate de filtro precisa continuar tratando isso (eles já declararam).
- **Dependência de insumo não satisfeita**: o arquivo `RoboTrack_Database.json` **não
  está no repositório** e não existe em nenhum caminho conhecido. Todas as tarefas de
  execução (validação por amostragem, run real, medição de volume) estão **bloqueadas**
  nesse insumo; as tarefas de código são planejáveis contra fixtures sintéticas. O
  `tasks.md` marca cada tarefa bloqueada com `[BLOQUEADO: export]`.
