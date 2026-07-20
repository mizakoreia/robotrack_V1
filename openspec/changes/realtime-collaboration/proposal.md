## Why

O sistema legado é ao vivo **em toda tela**, não por decisão de produto explícita, mas
porque o `onSnapshot` do Firestore assinava a árvore inteira do workspace: duas pessoas
abertas na mesma tabela de robô (§3.5) viam o avanço uma da outra aparecer sem recarregar;
a Visão Geral (§3.2) reagia à criação de um robô por outro membro; a revogação de acesso
(§3.10) era detectada por negação de permissão vinda do próprio listener. Isso é
propriedade de produto real para o público do RoboTrack (PRODUCT.md): duas ou três pessoas
comissionando a mesma célula ao mesmo tempo, cada uma com o celular na mão, precisam ver o
estado convergido — senão registram avanço em cima de leitura velha e brigam com o
`lock_version` (§2.4).

O plano de trabalho anterior portou **três** caminhos estreitos de broadcast — autenticação
de canal, notificação nova e revogação de acesso — e **nenhum** evento de mutação de
projeto, célula, robô, tarefa ou avanço. A colaboração ao vivo foi rebaixada a "só
notificações" sem nunca constar em lista de corte de escopo e sem que existisse sequer uma
tarefa de decisão "ActionCable vs. polling". Esta proposta reinstala tempo real como
capacidade de primeira classe e é a dona da decisão transversal **D6**.

Referências: §3.10 (revogação em tempo real), §3.5 (tabela do robô), §2.4 (concorrência de
avanço), §2.7 (notificações), §4.3 (offline).

## What Changes

- **`WorkspaceChannel`**, um stream por workspace (`ws:<workspace_id>`), com autorização de
  assinatura decidida por `Membership` ativa consultada no banco no momento do `subscribed`
  — nunca pelo índice de workspaces em cache no cliente (`workspace-tenancy`).
- **Handshake de token fora da query string.** O template autentica o Cable por
  `?token=` (`backend/app/channels/application_cable/connection.rb`), que vaza JWT
  completo em `access.log`, histórico de proxy e APM. Passa a valer um **ticket de cable**
  de vida curta e uso único, trocado por `POST /api/v1/cable_tickets`. **BREAKING** para
  qualquer consumidor do Cable do template.
- **Publicação de eventos de domínio**: toda mutação de `projects`, `cells`, `robots`,
  `tasks`, `task_advances`, `memberships` e `notifications` publica um evento no canal do
  workspace, a partir de um ponto único (`Realtime::Publisher`) chamado **após commit**.
- **Envelope de evento versionado** com `seq` monotônico por workspace, permitindo que um
  cliente que reconecta detecte lacuna e reconcilie em vez de assumir que não perdeu nada.
- **Invalidação de cache no cliente**: mapa explícito evento → query key React Query, na
  convenção fixada por `app-shell-navigation` (**D9**).
- **Coexistência com atualização otimista e fila offline** (`offline-pwa`, **D7**): evento
  que chega enquanto há mutação otimista pendente para a mesma entidade não pode fazer a UI
  piscar de volta para o valor antigo.
- **Fallback de polling** quando o WebSocket não estabelece (proxy de chão de fábrica
  bloqueia `Upgrade:` com frequência), com intervalo definido e degradação por foco/visibilidade.
- **Revogação de acesso ao vivo** (§3.10): aviso, remoção do workspace da lista local,
  retorno ao workspace próprio, encerramento da assinatura pelo servidor.
- **Adapter Redis obrigatório em produção**: o `cable.yml` deste repo já declara `redis`,
  mas sem `channel_prefix`, sem separação da URL do Sidekiq e sem verificação de boot. O
  provisionamento do Redis, a rota `/cable` no proxy e o alerta de queda são entregues por
  `delivery-and-observability` — citado como dependência, não implementado aqui.

### Não-objetivos

- **Não é edição colaborativa de texto.** Nada de CRDT, OT, cursores remotos ou presença
  ("fulano está vendo"). O modelo é invalidação de cache, não sincronização de documento.
- **Não substitui o controle de concorrência.** O `lock_version`/409 de `progress-advances`
  (§2.4) continua sendo a única autoridade sobre escrita conflitante. Tempo real reduz a
  chance de 409, não a elimina.
- **Não entrega alerta do sistema operacional nem push.** Notificação e Web Push são de
  `in-app-notifications`; este canal só transporta o evento.
- **Não define o service worker nem a fila offline.** É de `offline-pwa` (D7); aqui só se
  define o **contrato de interação** entre evento recebido e mutação pendente.
- **Não faz broadcast entre workspaces.** Não existe canal global de usuário nesta proposta;
  um usuário com três workspaces mantém três assinaturas.
- **Não entrega histórico de eventos persistido.** O `seq` detecta lacuna; a reconciliação é
  refetch, não replay de log.

## Capabilities

### New Capabilities

- `realtime-collaboration`: canal por workspace autorizado por membership, publicação de
  eventos de domínio pós-commit, invalidação de query keys no cliente, convivência com
  atualização otimista e fila offline, fallback de polling, reconciliação por lacuna de
  `seq` e revogação de acesso ao vivo.

### Modified Capabilities

_(nenhuma — `openspec/specs/` está vazio; nada foi construído ainda.)_

## Impact

- **Backend novo**: `app/channels/workspace_channel.rb`,
  `app/services/realtime/publisher_service.rb`, `app/models/concerns/realtime_publishable.rb`,
  `app/services/realtime/cable_ticket_service.rb`, endpoint
  `api/v1/cable_tickets` + linha de mount em `api/v1/base.rb`, entity de envelope,
  contador `workspaces.realtime_seq`, endpoint `GET /api/v1/workspaces/:id/sync` para o
  polling e a reconciliação.
- **Backend alterado**: `application_cable/connection.rb` (ticket em vez de `?token=`,
  `reject_unauthorized_connection` quando não há usuário — hoje a conexão anônima é
  aceita), `config/cable.yml` (`channel_prefix`, URL própria), `config/environments/*`
  (`allowed_request_origins`).
- **Frontend novo**: `lib/realtime/` (cliente `@rails/actioncable`, máquina de estado de
  transporte, mapa evento → query key, reconciliador), `stores/realtimeStore.ts` (Zustand,
  estado de transporte para o indicador de conexão do `app-shell-navigation`).
- **Dependências**: `in-app-notifications` (Onda 6, define o payload de notificação),
  `app-shell-navigation` (Onda 2, D9 — convenção de query key e troca de workspace),
  `workspace-tenancy` (D2 — membership e RLS), `authorization-policies` (D3 — policy de
  leitura reusada na assinatura), `offline-pwa` (D7 — contrato com a fila; consumidor,
  não pré-requisito), `delivery-and-observability` (Redis, `/cable` no proxy, alerta),
  `seal-template-baseline` (remoção dos canais `lead_chat`/`whatsapp_instance` e da
  referência a `Purchase` em `connection.rb`, que hoje é `NameError` em runtime).
- **Risco de entrega**: sem `/cable` roteado com upgrade de WebSocket no proxy de produção e
  sem Redis multi-processo, a capacidade degrada silenciosamente para polling em 100% das
  sessões — daí o requisito de que o modo de transporte seja **observável**, não invisível.
