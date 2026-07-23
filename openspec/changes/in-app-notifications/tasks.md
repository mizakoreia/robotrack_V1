## 1. Esquema e invariantes no banco

- [x] 1.1 Criar enum Postgres `notification_type` (`assign`, `progress`, `done`) e a tabela `notifications` com todas as colunas de D-N2 — inclusive `recorded_at`, `created_at` e `ts_local`, presentes desde a migration original. (§1.1 — um INSERT sem `recorded_at` ou sem `ts_local` falha por `NOT NULL`; não há migration de retrofit adicionando esses campos depois)
- [x] 1.2 Adicionar `workspace_id NOT NULL` + política RLS de `notifications` no mesmo idioma de D2. (§4.1 inv. 1 — `SET app.current_workspace_id` do workspace A e `SELECT * FROM notifications` retorna zero linhas do workspace B, mesmo como superusuário da aplicação)
- [x] 1.3 Implementar a invariante 8 no banco: CHECK `msg_max_500` (`char_length(msg) <= 500`), CHECK de coerência `read`/`read_at`, e trigger `BEFORE INSERT` que **falha** quando `NEW.read IS TRUE`. (§4.1 inv. 8 — `INSERT` em SQL puro com `msg` de 501 chars levanta `CheckViolation` e com 500 chars passa; `INSERT ... read = true` levanta exceção e a linha não existe, em vez de existir corrigida para `false`)
- [x] 1.4 Adicionar trigger `BEFORE UPDATE` que rejeita qualquer UPDATE afetando coluna fora de `{read, read_at}` e qualquer transição `read: true → false`. (§4.1 inv. 4 — `UPDATE notifications SET msg = 'x', read = true` é rejeitado por inteiro: nem `msg` nem `read` mudam)
- [x] 1.5 Criar o índice único parcial de idempotência de `assign` (`recipient_person_id, ctx_task_id, type, recorded_at` WHERE `type = 'assign'`) e os dois índices de leitura/retenção de D-N10. (§2.7 — inserir duas vezes a mesma `assign` levanta violação de unicidade em vez de criar linha duplicada)
- [x] 1.6 Escrever spec de banco que exercita 1.3–1.5 **por SQL cru**, contornando o model, provando que as invariantes 4 e 8 não dependem do ActiveRecord. (§4.1 inv. 4 e 8 — `update_column(:msg, 'x')` no console levanta erro do Postgres, não passa)

## 2. Mensagens versionadas

- [x] 2.1 Criar `config/locales/pt-BR.notifications.yml` com o bloco `v1` contendo as três format strings exatas de §2.7 (D14). (§2.7 — `I18n.t('notifications.v1.progress', ...)` produz `Bruno registrou 45% na tarefa "Ajuste de TCP" (robô R03 - Handling): Calibrado eixo 6`, com `%%` escapado corretamente e sem espaço antes do `%`)
- [x] 2.2 Implementar `Notifications::MessageBuilder` (objeto puro) que renderiza a chave por `type`, grava `format_version` e trunca **apenas** `%{comment}` com `…` quando a `msg` passa de 500. (§2.7 + inv. 8 — comentário de 900 chars gera `msg` de exatamente 500 chars com a descrição da tarefa e o nome do robô íntegros; a truncagem nunca corta o nome do robô)
- [x] 2.3 Adicionar spec de contrato que compara as três strings renderizadas caractere a caractere com os literais de §2.7, e um teste de grep que falha se `atribuiu você à tarefa` aparecer fora do locale e de testes. (D14 — mover a string para um `.rb` quebra o CI)

## 3. Destinatários e regras de disparo

- [x] 3.1 Implementar `Notifications::RecipientResolver` com as duas fontes de conjunto bruto — `:assign` usa o delta `novos_assignees − assignees_anteriores`, `:progress`/`:done` usam todos os responsáveis atuais — seguidas de dedup por `person_id` e subtração de `actor_person_id`, nessa ordem. (§2.7 — tarefa com `[Ana, Bruno]` recebendo `[Ana, Bruno, Diego]` produz exatamente 1 destinatário, Diego; responsáveis `[Ana, Bruno, Diego]` com Bruno como autor produzem 2; autor como único responsável produz conjunto vazio, não erro)
- [x] 3.2 Implementar `Notifications::EventClassifier` (função pura) que mapeia `(from, to)` para `:progress` (`0 < to < 100`), `:done` (`to == 100`) ou `nil` (`to == 0`). (§2.7 — avanço `45 → 0` retorna `nil` e nenhuma notificação é criada; `60 → 100` retorna `:done` e **não** `:progress`)
- [x] 3.3 Escrever spec de tabela do resolver + classifier cobrindo os cinco casos-limite: autoatribuição por §2.3, autor único responsável, reset para 0, 100%, e pessoa repetida no conjunto bruto. (§2.3/§2.7 — autoatribuição não gera `assign` para o próprio autoatribuído)

## 4. Persistência best-effort

- [x] 4.1 Implementar `Notifications::CreateService` (contrato singleton do template) que compõe classifier + resolver + builder e insere as linhas, tolerando violação do índice único de 1.5 sem levantar. (§2.7 — reexecutar o serviço com os mesmos parâmetros não cria segunda linha e conclui com sucesso)
- [x] 4.2 Implementar `NotifyTaskEventJob` (`queue: :notifications`, `retry: 5`) chamando o serviço, com reporte estruturado de erro no esgotamento das retentativas. (D-N7 — job que levanta `CheckViolation` reporta ao rastreador e vai para a dead set; não retenta infinitamente)
- [x] 4.3 Ligar o job por `after_commit` nos pontos de `progress-advances` (registro de avanço) e `robot-tasks` (mudança de `task_assignees`), **fora** da transação. (§2.7 — rollback da transação do avanço enfileira zero jobs; e uma exceção dentro do job deixa o `task_advance` persistido com progresso 45)
- [x] 4.4 Escrever spec de resiliência: Redis indisponível e criação de notificação levantando exceção, ambos com o avanço permanecendo salvo e a requisição retornando sucesso. (§2.7 — "falha ao notificar nunca derruba o save": a resposta do avanço é 2xx com Sidekiq fora do ar)

## 5. API e autorização

- [ ] 5.1 Criar `Api::Entities::Notification` e o endpoint de listagem paginada (`recorded_at DESC`, escopo `recipient_person_id = current_person`) com header de contagem de não lidas. (§3.10 — Ana listando num workspace onde Bruno tem 20 notificações recebe zero linhas de Bruno)
- [ ] 5.2 Criar `POST /notifications/:id/read` e `POST /notifications/read_all` — e **nenhum** `PATCH /notifications/:id` genérico. (§4.1 inv. 4 — o route-sweep prova que não existe rota de update genérica sobre `notifications`; a superfície é removida, não filtrada)
- [ ] 5.3 Implementar `NotificationPolicy` (D3) exigindo `recipient_person_id == current_person.id` em `mark_read?` para os três papéis, e negando `create?` para `view`. (§4.1 inv. 4 — o **dono** do workspace marcando a notificação de Ana como lida recebe negação, porque a spec diz "a própria")
- [ ] 5.4 Registrar os endpoints no route-sweep de D3 e escrever as specs de negação: `view` alterando `msg` além de `read`; `view` marcando notificação alheia; `view` criando notificação; membro do workspace A tocando notificação do workspace B. (§4.1 inv. 4 e 1 — cada um dos quatro é negado, o de outro tenant sem vazar a existência do id; e remover a declaração de policy de `read_all` quebra o CI)

## 6. Centro de notificações (UI)

- [ ] 6.1 Criar o hook `useNotifications` sobre React Query com a query key `['ws', wsId, 'notifications']` (D9) e a contagem de não lidas derivada. (D9 — nenhum `useEffect + apiClient` novo; a lista invalida ao marcar como lida sem `window.location.reload()`)
- [ ] 6.2 Construir o painel do centro de notificações (lista, estado vazio, marcar como lida individual e todas) usando os componentes de `design-system`, com `aria-live="polite"` na contagem. (§3.10 — marcar 1 de 3 como lida move o badge de `3` para `2` sem recarregar; leitor de tela anuncia a mudança)
- [ ] 6.3 Implementar `ctxToPath(notification)` e a navegação do item da lista até a tela do robô com a tarefa destacada. (§2.7 — `ctx` com `ctx_robot_id` nulo mantém a pessoa no centro de notificações com aviso, em vez de navegar para rota inválida)
- [ ] 6.4 Escrever teste de componente do painel cobrindo badge, marcação como lida e `ctx` quebrado. (§2.7 — clique em item com `ctx` incompleto não produz tela em branco nem erro de rota)

## 7. Alerta do sistema operacional

- [ ] 7.1 Implementar `useOsNotificationAlerts` como ponto único de construção de alerta, com a marca d'água **em memória** de D-N8 (a primeira resposta de listagem da sessão só inicializa, nunca dispara) e a regra de lint que proíbe `new Notification(` fora dele. (§2.7 — recarregar com 10 não lidas de ontem e permissão concedida dispara exatamente 0 alertas do SO; introduzir a chamada num componente quebra o lint no CI)
- [ ] 7.2 Adicionar o controle "Ativar alertas do sistema" no centro de notificações, chamando `requestPermission()` só nesse clique. (§2.7 — carregar o app com `permission === 'default'` não invoca `requestPermission`; o Chrome não bloqueia o site por pedido não solicitado)
- [ ] 7.3 Adicionar supressão por `document.visibilityState === 'visible'` e deduplicação por id já alertado. (§2.7 — a mesma notificação chegando via evento em tempo real e via refetch dispara 1 alerta, não 2)
- [ ] 7.4 Implementar `onclick` do alerta: `window.focus()` + navegação por `ctx`, incluindo troca de workspace quando a notificação é de outro workspace. (§2.7 — clicar num alerta do workspace B estando no A troca de workspace antes de navegar, sem misturar estado)
- [ ] 7.5 Escrever teste do hook com `Notification` mockado cobrindo os quatro cenários críticos: 10 não lidas antigas no reload → 0 alertas; item novo pós-carga → 1 alerta; permissão negada → 0 construções; 2 dias offline com 40 pendentes → 0 alertas. (§2.7 — o primeiro é o modo de falha explícito desta capacidade; sem esse teste ele volta silenciosamente)

## 8. Retenção e fechamento

- [ ] 8.1 Implementar o scope `Notification.purgeable` (`read = true AND recorded_at < now() - interval '90 days'`) e provar por `EXPLAIN` que ele usa o índice de 1.5. (D-N10 — não lida de 730 dias NÃO consta em `purgeable`; lida de 91 dias consta)
- [ ] 8.2 Abrir issue de handoff para `delivery-and-observability` com a política de retenção, a fila `notifications` e o alerta de fila parada — o cron de expurgo e a configuração de produção são de lá. (Barra de qualidade, item 8 — a capacidade não deixa buraco de entrega: fila nomeada, concorrência e alerta ficam nominalmente atribuídos)
- [ ] 8.3 Rodar a suíte completa da capacidade (banco, serviços, API, negação, UI, hook) e registrar o resultado. (§2.7 + §4.1 inv. 4 e 8 — verde exige simultaneamente: 501 chars falha no banco, `view` alterando `msg` é negado, e reload com não lidas antigas dispara zero alertas)
