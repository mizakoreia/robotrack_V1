# Tasks — `task-catalog`

Pré-requisito de todas: `commissioning-hierarchy` entregue (tabelas `projects`, `cells`,
`robots` com `workspace_id` e RLS ativa).

## 1. Tipo de Aplicação e esquema

- [ ] 1.1 Migration `CREATE TYPE robot_application AS ENUM` com os seis valores de §1.2, na
      ordem `Misto / Geral`, `Solda Ponto`, `Solda MIG`, `Handling`, `Sealing`, `Outros`;
      `down` faz `DROP TYPE`. (§1.2 — `SELECT enum_range(NULL::robot_application)` devolve
      6 rótulos na ordem declarada; um 7º valor não existe e `'Solda a Laser'::robot_application`
      levanta `InvalidTextRepresentation`.)
      *(NÃO APLICADA — EXECUCAO decisão 1: `commissioning-hierarchy` já entregou
      `robots.application` como `text` + CHECK dos 6 literais (D-H10, que
      descartou enum por não ser reversível em migration transacional). A
      INVARIANTE que 1.1 defende — banco rejeita valor fora da lista — já vale e
      tem spec. Criar o tipo agora exigiria ALTER TYPE destrutivo para trocar
      uma constraint funcionando por outra menos reversível.)*
- [ ] 1.2 **Backup antes de destrutivo:** dump de `robots` (`pg_dump -t robots`) e task de
      rollback documentada, antes de qualquer `ALTER TYPE` na coluna existente. (§1.2 —
      se `robots.application` já existir como `varchar` com algum valor fora do enum, a
      conversão do 1.3 aborta e o dump é o único caminho de volta.)
      *(SEM EFEITO — não há `ALTER TYPE` a fazer; ver 1.1.)*
- [ ] 1.3 Migration que converte `robots.application` para `robot_application` (`USING
      application::robot_application`) **ou**, se `commissioning-hierarchy` ainda não criou
      a coluna, apenas registra a dependência do tipo. (§1.2 — após a migration,
      `UPDATE robots SET application = 'xpto'` falha no banco, não no model.)
      *(JÁ VALE — `chk_robots_application` faz exatamente isso desde
      `commissioning-hierarchy`, provado em `spec/models/hierarchy_models_spec.rb`
      ("application fora do CHECK é rejeitada pelo banco").)*
- [x] 1.4 Migration `CREATE TABLE task_templates`: `id uuid PK DEFAULT gen_random_uuid()`,
      `workspace_id uuid NOT NULL REFERENCES workspaces`, `cat text NOT NULL`,
      `desc text NOT NULL`, `weight numeric NOT NULL DEFAULT 1 CHECK (weight > 0)`,
      `app_filters text[] NOT NULL DEFAULT '{}'`, timestamps. (§1.1 — `INSERT` sem
      `workspace_id` falha; `INSERT` com `app_filters = NULL` falha; `weight = 0` falha.)
- [x] 1.5 CHECK de domínio em `app_filters` (`app_filters <@ ARRAY['Misto / Geral','Solda
      Ponto','Solda MIG','Handling','Sealing','Outros','Todas']`) mais os índices
      `(workspace_id, cat, desc)` e único `(workspace_id, lower(btrim(desc)))`. (§1.2/§3.9
      — `'{"solda ponto"}'` é rejeitado e `'{"Todas"}'` é aceito, porque o importador legado
      precisa gravá-lo; e criar um segundo `" payload "` no mesmo workspace falha com
      `23505`.)
- [x] 1.6 Policy RLS em `task_templates` amarrada a `app.current_workspace_id`, no mesmo
      padrão de D2. (§4.1 inv. 1 — `SET app.current_workspace_id = '<A>'; SELECT * FROM
      task_templates WHERE workspace_id = '<B>'` retorna zero linhas mesmo como
      `SELECT *` sem `WHERE`.)
- [x] 1.7 **Verificação:** spec de schema que roda os cinco casos negativos acima direto no
      banco, com o model desabilitado (`ActiveRecord::Base.connection.execute`). (§4.1
      inv. 1 — se algum CHECK/RLS estiver só no model, o spec passa por SQL cru e falha.)

## 2. Model, normalização e componente de aplicabilidade

- [x] 2.1 Model `TaskTemplate` com `belongs_to :workspace`, validações de presença de `cat`
      e `desc` (com `strip` antes) e `weight > 0`. (§3.9 — `desc: "   "` é `422` e não cria
      linha, em vez de criar template com descrição em branco.)
- [x] 2.2 Normalização de `app_filters` no model (callback `before_validation`): vazio, ou
      contém `"Misto / Geral"`, ou contém `"Todas"` → `[]`; senão remove duplicatas
      preservando ordem. (§3.9 — `TaskTemplate.create!(app_filters: ["Handling","Misto /
      Geral"])` chamado do console persiste `{}`, não `{"Handling"}`.)
- [x] 2.3 `TaskTemplates::ApplicabilityFilter` — componente único que implementa a
      predicate de §2.5 (vazio OU `"Misto / Geral"` OU `"Todas"` OU a Aplicação do robô),
      com variante SQL para uso em `WHERE`. (§2.5 — um template `{"Todas"}` gravado direto
      no banco é aplicável a um robô `Solda MIG`; a versão simplificada `app_filters = '{}'
      OR application = ANY(app_filters)` faria esse template sumir.)
- [x] 2.4 **Verificação:** tabela de casos compartilhada (6 Aplicações × 4 formas de
      filtro) executada contra a versão Ruby e a versão SQL do filtro. (§2.5 — se as duas
      divergirem em qualquer célula, o spec falha; esse é o modo de falha que faz robô
      criado em lote e robô sincronizado terem conjuntos de tarefas diferentes.)

## 3. Catálogo padrão e seed

- [ ] 3.1 `backend/app/services/task_templates/default_catalog.rb` com os 31 itens de §1.3
      transcritos literalmente, em ordem de categoria, todos `weight: 1`, filtro apenas em
      `Calibração de Cola` (`["Sealing"]`) e `Check sinais de Gripper` (`["Handling","Solda
      Ponto"]`). (§1.3 — a constante tem `size == 31`, 9 `cat` distintos e exatamente 2
      entradas com filtro não vazio.)
- [ ] 3.2 Spec de trava do catálogo: compara o conjunto de `desc` com a lista literal de
      §1.3 e verifica as três contagens (31 / 9 / 2). (§1.3 — adicionar ou renomear
      qualquer item quebra o spec, forçando atualização consciente da spec funcional.)
- [ ] 3.3 `Workspaces::SeedDefaultTaskTemplatesService` com `insert_all` único, recebendo o
      `workspace` como argumento. (§1.3 — 31 linhas criadas com uma única query; o spec
      conta as queries e falha se virarem 31 `INSERT`s.)
- [ ] 3.4 Chamar o seed no bootstrap de workspace de `workspace-tenancy`, dentro da mesma
      transação de `Workspace.create`. (§1.3 — injetando falha no `insert_all`, nenhum
      workspace fica persistido; não existe workspace com 0 templates.)
- [ ] 3.5 Spec de ordenação lexicográfica: listagem devolve `A. Hardware` … `I. Aceitação`
      nessa ordem, com `ORDER BY cat COLLATE "C"`, rodando com `lc_collate` de `pt_BR.UTF-8`
      e de `C`. (§1.3 nota — sem a collation explícita a ordem muda entre ambientes e a tela
      de configurações embaralha as categorias só em produção.)
- [ ] 3.6 **Verificação:** spec de isolamento do seed — workspace A exclui `Speed up`,
      workspace B continua com 31. (§1.3 — prova que o catálogo é propriedade do workspace
      e não uma tabela global compartilhada.)

## 4. Policy e API do catálogo

- [ ] 4.1 `TaskTemplatePolicy` (`index?`/`show?` para `owner`/`edit`/`view`;
      `create?`/`update?`/`destroy?` para `owner`/`edit`), no idioma singleton de D3.
      (§4.1 — `view` em `create?` retorna `false`; a policy é testada isoladamente, sem
      passar por HTTP.)
- [ ] 4.2 Entity `Api::Entities::TaskTemplate` (`id`, `cat`, `desc`, `weight`,
      `appFilters` em camelCase) e endpoints de leitura `GET /api/v1/task_templates` e
      `GET /api/v1/task_templates/:id`, montados em `api/v1/base.rb` com policy declarada.
      (§1.4 item 3 / §3.9 — a resposta nunca contém a chave `apps`; buscar id de outro
      workspace responde `404`, não `403`, com zero linhas retornadas pela RLS.)
- [ ] 4.3 Endpoint `POST /api/v1/task_templates` com coerce de params que aceita `apps` e
      `appFilters`, `appFilters` vencendo em caso de conflito, com log estruturado do
      conflito. (§1.4 item 3 — `{"apps":["Sealing"]}` cria template com filtro `Sealing`;
      enviar os dois grava `Sealing` e emite o warning.)
- [ ] 4.4 Endpoints `PATCH` e `DELETE /api/v1/task_templates/:id` com a mesma tolerância de
      `apps`. (§3.9 — `PATCH` com `appFilters: ["Misto / Geral"]` num template `Sealing`
      persiste `{}` e o template passa a valer para robô `Solda MIG`.)
- [ ] 4.5 Endpoint `GET /api/v1/meta/robot_applications` devolvendo `enum_range` do tipo.
      (§1.2 — a resposta tem 6 itens na ordem do enum e não inclui `"Todas"`.)
- [ ] 4.6 **Verificação:** request specs negativos — `view` em `POST`/`PATCH`/`DELETE`
      recebe `403` com contagem de linhas idêntica antes e depois; `edit` do workspace A
      em template do workspace B recebe `404` e o `desc` original permanece. (§4.1 inv. 1 e
      2 — bloqueio de UI não conta; o teste bate direto no endpoint com token válido.)

## 5. Sincronização retroativa

- [ ] 5.1 Registrar como dependência explícita em `robot-tasks` o índice único
      `(robot_id, lower(btrim(desc)))` em `tasks`, e falhar a implementação desta
      capacidade se ele não existir. (§2.6 — sem o índice, duas sincronizações concorrentes
      do mesmo robô produzem 58 tarefas em vez de 29.)
- [ ] 5.2 `TaskTemplates::SyncToRobotService`: lock na linha do robô, seleção por
      `ApplicabilityFilter`, diferença por `lower(btrim(desc))` contra as tarefas do robô,
      `insert_all` das faltantes com `progress: 0`, `status: "Pendente"`, sem responsável, e
      `position` continuando a maior atual. (§2.6 — robô `Handling` com `TCP Check` em
      progresso `60` termina com 30 tarefas, `TCP Check` ainda em `60` e `position 0`.)
- [ ] 5.3 Retorno `{ added_count: N }` contando linhas efetivamente inseridas, não o
      tamanho do conjunto aplicável. (§2.6 — robô com `TCP Check` e `Power On` pré-existentes
      responde `addedCount: 28`, não `30`.)
- [ ] 5.4 Endpoint `POST /api/v1/robots/:id/sync_task_templates` com
      `TaskTemplatePolicy.sync?` declarada. (§4.1 — `view` recebe `403` e a contagem de
      tarefas do robô não muda.)
- [ ] 5.5 Spec de aplicabilidade concreta na sincronização: robô `Solda MIG` não recebe
      `Calibração de Cola`; robô `Sealing` recebe `Calibração de Cola` e não recebe `Check
      sinais de Gripper`; robô `Handling` recebe `Check sinais de Gripper`. (§2.5/§2.6 —
      inverter os dois filtros do seed faz este spec falhar em três pontos.)
- [ ] 5.6 Spec de não-sobrescrita e de tolerância de descrição: tarefa `Power On` com
      progresso `100`, responsável `Ana` e 3 entradas de histórico permanece intacta, e o
      robô com a tarefa `"tcp check "` não recebe `"TCP Check"`. (§2.6 — um `upsert` no
      lugar do `insert` das faltantes zeraria progresso e histórico; comparação por
      igualdade exata duplicaria TCP Check em todo robô importado do legado.)
- [ ] 5.7 **Verificação:** spec de concorrência — duas chamadas simultâneas de
      sincronização no mesmo robô, partindo de zero tarefas, terminam com exatamente 29
      tarefas e a segunda informa `0` ou falha. (§2.6 — sem o lock e o índice, o resultado
      é 58.)

## 6. Cliente e fechamento

- [ ] 6.1 `frontend/src/lib/api/endpoints.ts`: grupo `taskTemplates` com list/create/
      update/destroy e `robots.syncTaskTemplates`, tipados com `appFilters` (nunca `apps`).
      (§1.4 item 3 — o tipo TS não expõe `apps`; o nome legado morre na fronteira do
      backend.)
- [ ] 6.2 Hooks React Query com as chaves `['ws', wsId, 'taskTemplates']` e
      `['meta','robotApplications']` (`staleTime: Infinity`), seguindo D9; a mutation de
      sync invalida `['ws', wsId, 'robot', robotId, 'tasks']`. (§2.6/D9 — após sincronizar,
      a tabela do robô mostra as 29 tarefas novas sem reload manual.)
- [ ] 6.3 Tipo `RobotApplication` derivado do endpoint de metadados, sem lista literal em
      TS. (§1.2 — um `grep` por `"Solda MIG"` no `frontend/src` retorna zero ocorrências
      fora de testes e de fixtures.)
- [ ] 6.4 **Verificação:** teste de integração ponta a ponta do fluxo de §3.9 relevante ao
      modelo — criar template com filtro `Sealing`, editar para `Misto / Geral`, sincronizar
      um robô `Solda MIG` e confirmar que a tarefa agora aparece. (§3.9 — se a normalização
      de `Misto / Geral` não limpar o filtro, a tarefa não aparece e o teste falha.)
