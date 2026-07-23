## 1. Fundação do transporte no servidor

- [x] 1.1 Substituir a autenticação do Cable por ticket: `Realtime::CableTicketService`
  (emite ticket opaco no Redis, TTL 60s, consumo com `GETDEL`) + endpoint
  `POST /api/v1/cable_tickets` + linha de mount em `api/v1/base.rb`.
  (§Req. "Autenticação da conexão do Cable por ticket" — o mesmo ticket usado duas vezes
  falha na segunda conexão; hoje um `?token=` vale a sessão inteira e é reutilizável.)
- [x] 1.2 Reescrever `ApplicationCable::Connection#connect` para resolver o ticket, chamar
  `reject_unauthorized_connection` quando não houver usuário, remover o método morto
  `allow_public_checkout_subscription?` (referencia `Purchase`, model inexistente) e deixar
  `?token=` atrás da flag `CABLE_ALLOW_TOKEN_PARAM` (default `false` fora de development)
  como janela de coexistência do deploy.
  (§Req. ticket — conexão sem parâmetro nenhum é **rejeitada**, não estabelecida com
  `current_user = nil` como hoje em `connection.rb`; e com a flag ausente um JWT válido em
  query string também é rejeitado.)
- [x] 1.3 Ajustar `config/cable.yml` com `channel_prefix: robotrack_<env>` e
  `CABLE_REDIS_URL` própria (db distinto do Sidekiq), + inicializador que aborta o boot em
  produção se o adapter resolvido não for `redis`. Provisionamento e rota `/cable` no proxy
  são de `delivery-and-observability`.
  (§Req. "Isolamento do adapter" — boot em `production` com `adapter: async` aborta com erro
  explícito em vez de subir com broadcast que não sai do processo.)
- [x] 1.4 Spec de conexão cobrindo os 5 cenários de `Requirement: Autenticação da conexão`
  (ticket válido, reutilizado, expirado, ausente, JWT em query com flag off).
  (Verificação do grupo 1 — a suíte falha se `connect` voltar a aceitar conexão anônima.)

## 2. `WorkspaceChannel` e autorização de assinatura

- [x] 2.1 Criar `WorkspaceChannel` com `stream_from "ws:#{workspace_id}:v1"` e `reject`
  salvo se houver `Membership` ativa do `current_user`, consultada no banco.
  (§Req. "Autorização de assinatura" — usuário membro só de W2 assinando W1 é rejeitado e
  não recebe nenhum envelope de W1; a decisão não olha nada enviado pelo cliente.)
- [x] 2.2 Igualar a resposta de "não é membro" e "workspace inexistente", e adicionar
  reverificação de membership no ponto de entrega, com `reject_and_stop` quando sumir.
  (§Req. autorização + §Req. revogação — assinatura autorizada às 09h não continua
  autorizada às 10h; e um UUID inexistente não é distinguível de um workspace alheio.)
- [x] 2.3 Spec de canal com os 4 cenários de assinatura, incluindo o negativo entre tenants
  e o papel `view` sendo aceito.
  (Verificação do grupo 2 — o negativo cross-tenant é obrigatório; falha se qualquer byte
  de W1 chegar a um não-membro.)

## 3. Publicação de eventos de domínio

- [x] 3.1 Migration aditiva `add_column :workspaces, :realtime_seq, :bigint, null: false,
  default: 0` (reversível, sem backfill, sem destrutivo).
  (§Req. "Envelope versionado" — sem a coluna não há como detectar lacuna na reconexão.)
- [x] 3.2 Implementar `Realtime::PublisherService.publish` com incremento transacional do
  `seq` (`UPDATE ... RETURNING`), montagem do envelope (`v`, `seq`, `type`, `entity`,
  `scope` com os três ancestrais, `actor_person_id`, `origin_id`, `at`) e broadcast, com
  rescue que loga e incrementa contador em vez de propagar.
  (§Req. envelope + §Req. publicação — transação abortada não consome número: a mutação
  seguinte publica o mesmo `seq`; e Redis fora do ar não faz o POST de avanço responder 500.)
- [x] 3.3 Criar o concern `RealtimePublishable` com `after_commit on: [:create, :update,
  :destroy]` e incluí-lo em `Project`, `Cell`, `Robot`, `Task`, `TaskAdvance`, `Membership`
  e `Notification`.
  (§Req. publicação — evento sai só depois do commit; publicar dentro da transação entrega
  ponteiro para linha que pode sofrer rollback.)
- [x] 3.4 Capturar `X-RoboTrack-Origin` no `before` de `api/root.rb` para
  `Current.origin_id` e propagá-lo ao envelope.
  (§Req. "Evento não reverte interface otimista" — sem `origin_id` o autor do avanço recebe
  o próprio eco e refetcha por cima da própria atualização otimista.)
- [x] 3.5 Implementar publicação agregada para operação em massa: contexto de supressão de
  evento por linha, emitindo um único envelope terminal — `robot.batch_created` no lote de
  robôs (§3.4) e `workspace.reset` / `import.finished` na importação e no reset
  (`legacy-data-migration`, §1.4).
  (§Req. publicação — lote de 50 robôs produz 1 envelope com `scope.cell_id`, não 50; e
  importar 3.000 tarefas não gera 3.000 broadcasts nem contenção na linha `realtime_seq`.)
- [x] 3.6 Spec de cobertura que enumera os models de domínio e falha nomeando qualquer um
  que não inclua `RealtimePublishable`.
  (Verificação do grupo 3 — é a trava contra a regressão que originou esta proposta: uma
  entidade parar de ser ao vivo sem ninguém perceber.)

## 4. Reconciliação e endpoint de sync

- [ ] 4.1 Implementar `GET /api/v1/workspaces/:id/sync?since=` devolvendo `current_seq`,
  `gap` e os tipos de entidade alterados por `updated_at`/`created_at` dentro da janela de
  10 minutos, com policy de leitura de workspace (D3).
  (§Req. "Reconciliação após reconexão" — `since` de 40 minutos atrás responde `gap: true`
  sem enumerar; não-membro recebe 403 sem vazar `current_seq`.)
- [ ] 4.2 Spec de request para `/sync` cobrindo lacuna curta, lacuna longa, `since ==
  current_seq` e o negativo de tenant.
  (Verificação do grupo 4 — `since` igual ao atual não pode devolver entidades, senão todo
  reconnect vira refetch completo.)

## 5. Cliente de tempo real

- [ ] 5.1 Criar `lib/realtime/connection.ts`: obtenção do ticket, `createConsumer` do
  `@rails/actioncable`, assinatura do `WorkspaceChannel` do workspace corrente, e
  re-assinatura na troca de workspace descartando a anterior (`app-shell-navigation` §3.10).
  (§Req. autorização — trocar de W1 para W2 encerra a assinatura de W1; assinatura órfã
  continuaria invalidando chaves de um workspace que não está mais na tela.)
- [ ] 5.2 Criar `stores/realtimeStore.ts` (Zustand, estado de cliente por D9) com a máquina
  `connecting|live|degraded|offline`, últimos `seq` por workspace e `origin_id` da aba.
  (§Req. fallback — o estado é lido pelo indicador de conexão; sem ele o modo degradado é
  invisível e um `/cable` mal roteado passa meses despercebido.)
- [ ] 5.3 Escrever `lib/realtime/eventMap.ts` como `Record<EventType, Mapper>` sobre união
  fechada, com a tabela de D6.3 incluindo a cadeia de rollup derivada de `scope`.
  (§Req. invalidação — `task_advance.created` invalida também `cell`, `project` e
  `overview`; sem isso o anel ponderado (§2.1) e a contagem crua (§3.2) aparecem em
  desacordo na mesma tela; e um envelope `gizmo.created` fora da união cai no handler de
  tipo desconhecido, que invalida `['ws', wsId]` e avisa em vez de descartar em silêncio.)
- [ ] 5.4 Implementar a fila de invalidação com drenagem a cada 250 ms e deduplicação por
  chave, usando `refetchType: 'active'`.
  (§Req. invalidação — 8 envelopes do mesmo robô em 900 ms produzem 1 refetch, e query
  desmontada é marcada stale sem disparar requisição.)

## 6. Convivência com otimista e fila offline

- [ ] 6.1 Injetar `X-RoboTrack-Origin` no axios de `lib/api/client.ts` e descartar no
  cliente envelope cujo `origin_id` seja o da própria aba.
  (§Req. otimista — quem registrou 40→60 não recebe refetch do próprio eco e a tela
  permanece em 60.)
- [ ] 6.2 Implementar o gate de represamento: invalidação cuja chave intersecta a
  `mutationKey` de mutação em voo entra em fila por entidade e drena no `onSettled`
  (sucesso **ou** erro).
  (§Req. otimista — evento de terceiro durante POST em voo não faz a UI piscar 60→40→60; e
  um 409 de `lock_version` (§2.4) drena a fila em vez de deixá-la presa para sempre.)
- [ ] 6.3 Consumir `hasPendingFor(kind, id)` da fila offline de `offline-pwa` (D7) no mesmo
  gate, e aplicar o teto de 30 s de represamento marcando a tela como não-sincronizada.
  (§Req. otimista — avanço parado no IndexedDB represa a invalidação; passados 30 s a tela
  atualiza **e** admite que não está sincronizada, em vez de mentir indefinidamente.)
- [ ] 6.4 Testes de integração (Vitest + Testing Library) dos 5 cenários de
  `Requirement: Evento não reverte interface`, capturando os valores renderizados ao longo
  do tempo.
  (Verificação do grupo 6 — o teste falha se a sequência renderizada contiver 40 depois de
  60; asserção sobre estado final apenas não pega flicker.)

## 7. Fallback de polling

- [ ] 7.1 Implementar a detecção de degradação: sem `welcome` em 8 s ou 3 falhas em 60 s →
  `degraded`; backoff de retentativa (5 s, 15 s, 45 s, teto 2 min) com jitter, em paralelo
  ao polling.
  (§Req. fallback — com `Upgrade:` bloqueado pelo proxy, a sessão entra em `degraded` em
  8 s em vez de ficar em `connecting` para sempre.)
- [ ] 7.2 Aplicar `refetchInterval` de 20 s às queries ativas em `degraded`, com
  `refetchIntervalInBackground: false` e redução para 60 s após 5 min sem interação.
  (§Req. fallback — avanço de outro membro aparece em ≤20 s com WS bloqueado, e aba oculta
  não emite nenhuma requisição.)
- [ ] 7.3 Ligar o indicador de transporte da topbar (`app-shell-navigation`) e emitir a
  métrica de sessões em `degraded` para `delivery-and-observability`.
  (§Req. fallback — sessão degradada por >60 s exibe "atualizando periodicamente"; sem a
  métrica, 100% das sessões degradadas passa como normal.)
- [ ] 7.4 Implementar a reconciliação no `live`: chamar `/sync?since=<seq>` ao conectar e
  reconectar, invalidando conforme `gap`, e desligar todo `refetchInterval`.
  (§Req. reconciliação — após 45 s de queda com 6 mutações, o cliente converge; sem isso o
  cliente reconecta e mostra dado velho até alguém mexer na tela.)
- [ ] 7.5 Teste E2E (Playwright, harness de `quality-and-accessibility`) com WebSocket
  bloqueado no contexto do browser, verificando que a tela do robô ainda atualiza.
  (Verificação do grupo 7 — falha se a tela ficar congelada ou se o polling continuar rodando
  depois que o WS voltar a conectar.)

## 8. Revogação de acesso ao vivo (§3.10)

- [ ] 8.1 Implementar `revokeWorkspaceAccess(wsId)` no cliente — aviso, remoção do índice
  local, `removeQueries(['ws', wsId])`, navegação ao workspace próprio — idempotente por
  guarda de execução única, chamada pelos dois gatilhos: `membership.revoked` para o próprio
  usuário no handler do canal e 403 em rota do workspace corrente no interceptor de
  `lib/api/client.ts`.
  (§3.10 / §Req. revogação — evento e 403 chegando com 300 ms de diferença produzem um
  aviso e uma navegação, não dois; e com transporte em `degraded` a revogação ainda é
  detectada pelo 403 do próximo polling, em vez de deixar o usuário numa tela morta.)
- [ ] 8.2 Encerrar os streams no servidor (`stop_all_streams` + `reject_and_stop`) no
  `after_commit` da revogação de membership.
  (§Req. revogação — cliente que ignora o evento para de receber envelopes de W1 mesmo
  assim; a autorização não pode depender de cooperação do cliente.)
- [ ] 8.3 Teste de integração dos 5 cenários de revogação, incluindo o negativo em que a
  revogação é de outro membro.
  (Verificação do grupo 8 — falha se `membership.revoked` de D expulsar C da tela; deve
  apenas invalidar `members` e `people`.)

## 9. Prova ponta a ponta e entrega

- [ ] 9.1 Adicionar `VITE_REALTIME_ENABLED` (default ligado) que desativa todo o cliente de
  tempo real deixando a aplicação correta, só não ao vivo.
  (§Req. fallback — com a flag desligada nenhuma conexão de Cable é aberta e nenhuma tela
  quebra; rollback vira toggle em vez de redeploy.)
- [ ] 9.2 Teste E2E de duas sessões simultâneas na tela do mesmo robô: a sessão A registra
  40→60 e a sessão B observa 60 em ≤2 s sem recarregar.
  (§3.5 / §Req. invalidação — é o cenário que o plano anterior tinha perdido; falha se B
  precisar de F5.)
- [x] 9.3 Remover a flag `CABLE_ALLOW_TOKEN_PARAM` e o caminho de `?token=` após o deploy da
  janela de coexistência. **Satisfeita por construção no G1** (EXECUCAO §RECONCILIAÇÃO): o
  porte é pré-produção, sem consumidor do Cable do template em produção, então a janela de
  coexistência foi dispensada e o caminho `?token=` nunca foi introduzido — `connection.rb`
  nasce ticket-only e o cenário "JWT em query string não é aceito" já passa no spec de 1.4.
  (§Req. ticket — depois desta tarefa nenhum JWT de sessão trafega em URL; a prova é o spec
  de 1.4 continuando verde com o caminho ausente.)
