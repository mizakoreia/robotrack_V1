# EXECUCAO — realtime-collaboration

Mapa de execução. Escrito ANTES de qualquer código (commit G0). RETOMADA no fim.

## Ponto de partida

Branch empilhada sobre `workspace-settings` (COMPLETA). Onda D6. FULL-STACK. Reinstala o
tempo real como capacidade de primeira classe: canal por workspace autorizado por
membership NO BANCO, eventos de domínio pós-commit com `seq` monotônico, invalidação
mapeada de query keys (D9), convivência com otimista, fallback de polling OBSERVÁVEL,
reconciliação por lacuna e revogação de acesso ao vivo (§3.10). Também destrava o
handoff 5.9 do reset (`workspace-settings`).

## RECONCILIAÇÃO COM A REALIDADE (crítico — ler antes de codar)

- **`connection.rb` JÁ FOI LIMPO** (não é o template): `?token=` JWT obrigatório, conexão
  anônima já é REJEITADA, sem cadáver de `Purchase`/`allow_public_checkout_subscription?`.
  Da tarefa 1.2 sobra: trocar `?token=` por TICKET. **Janela de coexistência
  DESNECESSÁRIA**: o porte é pré-produção, não existe consumidor do Cable do template em
  produção — implemento ticket-only DESDE JÁ, sem a flag `CABLE_ALLOW_TOKEN_PARAM` (9.3
  fica satisfeita por construção: o caminho `?token=` deixa de existir; o spec de 1.4
  prova a rejeição de JWT em query).
- **Redis**: `redis-server` existe no container mas NÃO sobe sozinho — provisionamento de
  sessão ganha `redis-server --daemonize yes` (tickets usam Redis com TTL+GETDEL).
  `cable.yml` de TEST usa `adapter: test` → specs de canal/broadcast não dependem de
  Redis (ActionCable::TestHelper). Tickets em spec: Redis real (está de pé) ou fake
  in-memory — decidir no G1 (preferir Redis real, é 1 comando).
- **`useMyTasksLive` NÃO EXISTE** (a CONTINUIDADE o menciona; só `accessRevoked.ts` — o
  caminho PUXADO do 403 — existe). O cliente de tempo real nasce todo aqui, sem hook
  fiado a reusar. Corrigir a CONTINUIDADE no fechamento.
- **`Notification` model NÃO EXISTE** (`in-app-notifications` não construída) → o concern
  vai em `Project`/`Cell`/`Robot`/`Task`/`TaskAdvance`/`Membership`; `Notification` entra
  quando nascer (o spec de cobertura 3.6 enumera os EXISTENTES e ganha nota de handoff).
- **Soft-delete mudou o "destroy"**: a hierarquia NÃO sofre `destroy` — o
  `SoftDeleteService` usa `update_all` (SEM callbacks → `after_commit` NÃO dispara!).
  Eventos de exclusão/reset da hierarquia precisam de publicação EXPLÍCITA:
  `CrudService#destroy` publica `<entity>.deleted` e o reset publica `workspace.reset`
  (já previsto em 3.5 como agregado). O mesmo vale p/ `Tasks::DeleteService`
  (`update_columns`). O concern cobre create/update por caminho de model; os caminhos
  `update_all`/`insert_all` (reorder, batch de robôs, seed) usam o agregado 3.5.
- **`workspaces.realtime_seq`**: aditiva; app tem UPDATE em `workspaces`? roles.sql
  restringiu UPDATE de `workspaces` a colunas (name/updated_at) — o `UPDATE ...
  RETURNING` do seq PRECISA de GRANT de coluna `realtime_seq` ao `robotrack_app`
  (migration + roles.sql, mesmo caveat pg_dump -x do audit-log).
- **`qk` já tem tudo** que o eventMap precisa (overview/projectOverview/cellOverview/
  robot/tasks/myTasks/people/auditLogs/notifications). `members` não existe como key —
  ver o que TeamPanel usa no G5 e adicionar `qk.members` se preciso.
- **`offline-pwa` (D7) não existe** → 6.3 (`hasPendingFor`) vira CONTRATO: gate consome
  uma interface injetável com implementação default vazia; a fila real chega com o
  offline-pwa. Registrar handoff.
- **Playwright E2E (7.5, 9.2)**: o padrão do repo é integração RTL (divergência
  registrada desde robot-task-table; harness de `quality-and-accessibility` não existe).
  7.5/9.2 = integração com WebSocket/consumer mockado + (se viável) prova com dois
  QueryClients simulando duas sessões. Registrar divergência.
- **Indicador de transporte (7.3)**: a topbar tem `SaveIndicator` (persistenceStore);
  o slot de conexão é novo — componente pequeno lendo `realtimeStore`, montado na topbar.
- **`X-RoboTrack-Origin`**: `api/root.rb` before captura p/ `Current.origin_id`
  (`app/models/current.rb` NÃO existe — criar com ActiveSupport::CurrentAttributes);
  `client.ts` injeta o header (origin_id por aba via `crypto.randomUUID()` em memória).

## Ordem dos grupos (mapa)

| Grupo | Escopo | Tarefas |
|---|---|---|
| **G1** | Ticket de cable: `Realtime::CableTicketService` (Redis TTL 60s GETDEL), `POST /api/v1/cable_tickets` (+policy/mount), `connection.rb` ticket-only (sem `?token=`), specs dos 5 cenários | 1.1–1.4 (+9.3 por construção) |
| **G2** | `WorkspaceChannel`: stream `ws:<id>:v1`, autorização por Membership NO BANCO no subscribed, reverificação na entrega, igualdade não-membro/inexistente, specs incl. cross-tenant e `view` aceito | 2.1–2.3 |
| **G3** | Publicação: migration `realtime_seq` (+GRANT coluna), `Realtime::PublisherService` (UPDATE...RETURNING, envelope v/seq/type/entity/scope/actor/origin/at, rescue não-propagante), concern `RealtimePublishable` nos 6 models, `Current.origin_id` + captura do header, agregados (batch robôs, reset via seam do FactoryResetService, deleted da hierarquia via CrudService), spec de cobertura | 3.1–3.6 |
| **G4** | `GET /api/v1/workspaces/:id/sync?since=` (current_seq, gap, tipos alterados janela 10min, policy D3), specs (lacuna curta/longa/igual/tenant) | 4.1–4.2 |
| **G5** | Cliente: `lib/realtime/connection.ts` (ticket→consumer→subscribe, re-assinatura na troca), `realtimeStore` (connecting/live/degraded/offline, seq por ws, origin_id), `eventMap.ts` (união fechada + rollup + desconhecido→ws inteiro+aviso), fila de invalidação 250ms dedup `refetchType: 'active'` | 5.1–5.4 |
| **G6** | Convivência: header no axios + descarte do próprio eco, gate de represamento por mutação em voo (drena no onSettled), contrato `hasPendingFor` (D7 stub) + teto 30s, testes dos 5 cenários anti-flicker | 6.1–6.4 |
| **G7** | Fallback: detecção 8s/3-em-60s → degraded, backoff jitter, `refetchInterval` 20s/60s ativo-only, indicador topbar + métrica (handoff), reconciliação `/sync` no connect/reconnect, prova com WS bloqueado | 7.1–7.5 |
| **G8** | Revogação viva: `revokeWorkspaceAccess` unificado (evento + 403 — JÁ EXISTE `accessRevoked.ts` do caminho 403: ESTENDER, não duplicar; guarda de execução única), `stop_all_streams` no after_commit da revogação, 5 cenários | 8.1–8.3 |
| **G9** | Entrega: `VITE_REALTIME_ENABLED` (default on), E2E duas sessões (A registra 40→60, B vê ≤2s), fechamento + CONTINUIDADE (corrigir menção a useMyTasksLive) | 9.1–9.2 (+9.3 já) |

## Armadilhas previstas

- **after_commit e specs :tenancy**: DatabaseCleaner truncation (sem transação do RSpec)
  → `after_commit` DISPARA normal nos specs de tenancy. Nos demais (transacionais), não.
  Specs de publicação usam :tenancy.
- **Broadcast em test**: `adapter: test` + `have_broadcasted_to` — sem Redis.
- **Eco do publisher**: `Publisher` roda no after_commit DA REQUISIÇÃO — `Current.origin_id`
  precisa sobreviver até lá (CurrentAttributes reseta por request, after_commit ainda é
  dentro do request cycle — ok; em job NÃO há origin — nil é correto).
- **`UPDATE ... RETURNING` do seq dentro da transação da mutação** serializa mutações do
  MESMO workspace na linha de `workspaces` — aceito (baixo volume); operação em massa usa
  supressão + 1 envelope (3.5) exatamente para não segurar esse lock N vezes.
- **`invalidateQueries` vs guard D9**: invalidar `['ws', wsId]` (prefixo) é válido no
  guard (forma ws+tenant). O handler de tipo desconhecido usa isso.
- **`switchWorkspace` faz `clear()`** — a re-assinatura (5.1) deve ocorrer APÓS a troca;
  descartar assinatura anterior antes do clear evita evento de W1 escrevendo pós-clear.
- **jsdom não tem WebSocket real**: mockar `@rails/actioncable` (`createConsumer`) nos
  testes do cliente; a máquina de transporte é testável por callbacks injetados.

## Baseline

Backend 1203/0/8 (`--tag ~slow --seed 12345`, medido no fechamento de
hierarchy-soft-delete G4) + G5/G6 do workspace-settings verdes (131/0 dirigido).
Frontend 355/0; tsc limpo.

## REVISÃO DO BACKEND (pós-G4, antes do frontend)

Revisão adversarial do servidor (G1–G4). Dois achados registrados:

- **[CORRIGIDO — G3-fix] Perda silenciosa de evento na reserva de seq.** O `seq`
  era reservado na MESMA transação do traversal de `scope`; uma falha ali (ou no
  UPDATE) revertia o incremento e o evento sumia SEM lacuna, anulando o esquema
  seq/gap. Correção em `PublisherService#publish_change`: reserva o seq primeiro e
  isola o scope num savepoint (`safe_scope`) — falha degrada para `scope: {}` sem
  reverter o seq nem impedir o broadcast. Só o UPDATE do seq fica irredutível.
- **[ACEITO — não corrigir] `/sync` sub-invalida em queda longa (>10min) com
  atividade recente de outro tipo.** O código é FIEL ao design (D6.5: janela de
  10min, `queda curta: gap=false`); o conserto exato exigiria índice seq→tempo ou
  log de eventos (NÃO-OBJETIVO). E o buraco é coberto pela arquitetura em camadas:
  toda queda >10min passou por `degraded` (limiar 8s), onde o `refetchInterval` de
  20s (7.2) já mantém as queries ATIVAS frescas durante a queda inteira. No
  reconnect, o resíduo é uma query INATIVA de tipo não-enumerado, que refaz no
  remount. A Opção B (`gap:true` sempre) reintroduziria o "todo reconnect = refetch
  completo" que o `/sync` existe para evitar — pior numa rede de galpão. Registrado
  para não ser re-sinalizado.

## RETOMADA

Ler este arquivo + design.md (D6.1–D6.7). Estado por grupo em tasks.md (`- [x]`).
Protocolo por grupo: aplicar → specs dirigidos 0 falhas → marcar tasks → `npx --yes
@fission-ai/openspec@1.6.0 validate realtime-collaboration --strict` → UM commit
`G<n>:` → push `git push origin HEAD:realtime-collaboration` → resumo pt-BR
client-friendly → pedir autorização. Redis: `redis-server --daemonize yes` a cada
sessão nova (tickets). NUNCA duas suítes simultâneas.
