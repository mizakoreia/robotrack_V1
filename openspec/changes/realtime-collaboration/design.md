## Context

O legado obtinha tempo real de graça: `onSnapshot` numa árvore de documentos entregava
tanto o dado novo quanto a negação de permissão (§3.10) no mesmo canal. O porte perde as
duas coisas de uma vez. Um Rails 8 + React só é ao vivo se alguém publicar e alguém
invalidar; e nada em `progress-advances`, `commissioning-hierarchy` ou `robot-task-table`
faz isso — essas capacidades param na resposta HTTP.

O estado do template (inspecionado em `backend/app/channels/`):

- `ApplicationCable::Connection` identifica por `current_user`, decodifica JWT de
  `request.params[:token]` e — decisivo — faz `self.current_user = user if user.present?`
  **sem** `reject_unauthorized_connection`. Conexão sem token é aceita com
  `current_user = nil`. `DashboardChannel#subscribed` faz `stream_for("dashboard:kpis")`
  sem checar nada: hoje qualquer anônimo assina. Vedar isso é de
  `seal-template-baseline`; esta capacidade **depende** disso e não pode ser construída em
  cima do comportamento atual.
- `connection.rb` ainda referencia `Purchase.by_any_id` em
  `allow_public_checkout_subscription?`, e o model `Purchase` não existe no repo — método
  morto que vira `NameError` se alguém o chamar.
- `config/cable.yml` já usa `redis` em dev e prod (não `async`), mas **sem `channel_prefix`**
  e reutilizando o mesmo `REDIS_URL`/db do Sidekiq. Sem prefixo, dois ambientes apontando
  para o mesmo Redis cruzam broadcast — um evento de staging chega em produção. O default
  `redis://localhost:6379/1` colide com o db do Sidekiq.

Restrição de campo que molda tudo: a rede é de chão de fábrica. Wi-Fi de galpão com
handoff entre APs, celular alternando 4G/Wi-Fi, e proxy corporativo que frequentemente
bloqueia `Upgrade: websocket`. Reconexão não é caso raro; é o caso comum.

## Goals / Non-Goals

**Goals**

1. Duas sessões na mesma tabela de robô convergem em ≤2s sem recarregar (§3.5).
2. Assinatura autorizada por membership no banco, verificada no `subscribed` e reverificada
   a cada evento entregue; um usuário de outro workspace nunca recebe byte de dado alheio.
3. Nenhum flicker: evento que chega durante mutação otimista pendente jamais reverte a UI.
4. Degradação honesta e observável quando o WebSocket não conecta — a tela continua
   atualizando, e o modo de transporte é visível para usuário e para métrica.
5. Cliente que reconecta **detecta** que perdeu eventos, em vez de presumir que não perdeu.
6. Revogação de acesso (§3.10) é detectada ao vivo, não no próximo 403 casual.

**Non-Goals**

- Presença, cursores, digitação, CRDT.
- Entrega garantida/at-least-once com persistência de eventos. O canal é best-effort; a
  garantia é a reconciliação por `seq`.
- Ordenação total entre workspaces. `seq` é monotônico **por workspace**, só.
- Push/notificação do SO (`in-app-notifications`).

## Decisions

### D6.1 — ActionCable com um `WorkspaceChannel`, não polling puro, não SSE, não canal por recurso

**Decisão.** Um canal, `WorkspaceChannel`, um stream por workspace
(`ws:<workspace_id>:v1`). Todos os eventos de domínio do workspace passam por ele.

**Alternativa descartada — polling puro a cada 15s como único mecanismo.** Custa menos
infra, mas em 24 cards de robô abertos num hub (`hierarchy-screens`) o React Query com
`refetchInterval` bate no servidor a cada ciclo por query montada, e a latência mediana de
convergência vira 7,5s — o que é notavelmente pior que o legado num cenário onde duas
pessoas registram avanço na mesma célula. Polling fica como **fallback** (D6.6), não como
mecanismo primário.

**Alternativa descartada — SSE (`ActionController::Live`).** Unidirecional, mais fácil de
atravessar proxy, mas consome um thread Puma por conexão aberta; com 30 sessões
simultâneas o pool acaba. ActionCable roda em servidor de conexão própria.

**Alternativa descartada — um canal por recurso** (`RobotChannel`, `ProjectChannel`).
Reproduz a granularidade do `onSnapshot`, mas a contagem de assinaturas explode (24 cards =
24 subscriptions, cada uma com round-trip de autorização) e a autorização passa a ser
decidida por objeto, multiplicando a superfície de erro. Um canal por workspace faz a
autorização acontecer **uma vez**, no lugar mais barato de acertar: a membership.

**Onde a invariante mora.** Não no `subscribed` sozinho. `WorkspaceChannel#subscribed` faz
`reject unless Memberships::ActiveFor.call(user, ws_id)` — mas isso é consulta pontual. A
garantia real é dupla:
- **RLS** (D2): o publisher lê o workspace no contexto do request que originou a mutação,
  então nenhum dado de outro tenant pode entrar num envelope de workspace errado — o
  `workspace_id` do envelope vem da própria linha, sob `app.current_workspace_id`.
- **Reverificação na entrega**: `WorkspaceChannel` sobrescreve o ponto de entrega e
  descarta o envelope + chama `reject_and_stop` se a membership sumiu (D6.7). Uma
  assinatura autorizada em T0 não é autorização em T+1h.

### D6.2 — Ponteiro, não payload

**Decisão.** O envelope carrega **identidade e ponteiros**, não o estado da entidade:

```json
{ "v": 1, "seq": 4821, "workspace_id": "…", "type": "task_advance.created",
  "entity": { "kind": "task", "id": "…" },
  "scope": { "project_id": "…", "cell_id": "…", "robot_id": "…" },
  "actor_person_id": "…", "origin_id": "c3f1…", "at": "2026-07-20T14:03:11.482Z" }
```

O cliente mapeia isso para query keys e invalida; o React Query refaz o fetch pelas rotas
normais, que já passam por policy e RLS.

**Alternativa descartada — evento com payload completo da entidade.** Convergência em um
round-trip a menos e menos carga de leitura. Rejeitada por três motivos, em ordem de peso:

1. **Autorização.** Payload no envelope significa que o canal vira uma segunda superfície de
   leitura, paralela às policies de D3, com sua própria matriz §4.1 para manter em dia. O
   route-sweep spec de `authorization-policies` não cobre broadcast. Ponteiro mantém uma
   única porta de leitura.
2. **Custo sob 24 cards.** Contra a intuição, o payload é pior aqui. Com ponteiro, um
   avanço registrado invalida `['ws',w,'robot',R,'tasks']` e a chave de rollup do ancestral;
   das 24 queries montadas no hub, **as demais não são invalidadas** e nenhum fetch dispara
   — o custo é 1 envelope de ~300 bytes e 1 refetch, e só se aquele robô estiver visível
   (React Query não refaz query inativa até remontar). Com payload, cada evento carrega
   estado que na maioria dos casos ninguém está olhando, e para o card do hub o payload da
   tarefa **não basta** de qualquer jeito — o card mostra progresso consolidado (§2.1), que
   depende de `progress_cache` recalculado no servidor. Ou seja: payload paga banda em
   todos os eventos e ainda obriga refetch nos casos de rollup.
3. **Coerência.** Payload cria duas fontes de verdade para a mesma linha em cache (a que veio
   pelo WS e a que veio pelo HTTP), com ordenação relativa indefinida. Ponteiro tem uma só.

**Custo aceito.** Uma rajada — 8 avanços registrados em 20s por outro membro — vira 8
invalidações da mesma chave. Mitigado por **coalescência**: as invalidações entram numa fila
e são drenadas a cada 250ms com deduplicação por chave (D6.4), então a rajada vira 1 refetch.

### D6.3 — Mapeamento evento → query key

Convenção de D9 (`app-shell-navigation`): `['ws', wsId, …]`. O mapa é um módulo único,
`frontend/src/lib/realtime/eventMap.ts`, e é **exaustivo por construção** — um tipo de
evento sem entrada no mapa é erro de compilação (`Record<EventType, Mapper>` sobre uma
união fechada) e, em runtime, cai num handler que invalida `['ws', wsId]` inteiro e emite
um `console.warn` marcado, para nunca ser silenciosamente ignorado.

| Evento | Query keys invalidadas |
|---|---|
| `project.created` / `.updated` / `.deleted` / `.reordered` | `['ws',w,'projects']`, `['ws',w,'project',p]`, `['ws',w,'overview']` |
| `cell.created` / `.updated` / `.deleted` / `.reordered` | `['ws',w,'project',p]`, `['ws',w,'cell',c]`, `['ws',w,'overview']` |
| `robot.created` / `.updated` / `.deleted` / `.reordered` | `['ws',w,'cell',c]`, `['ws',w,'robot',r]`, `['ws',w,'project',p]`, `['ws',w,'overview']` |
| `robot.batch_created` (1–50, `robot-tasks`) | `['ws',w,'cell',c]`, `['ws',w,'project',p]`, `['ws',w,'overview']` — **um** evento agregado, não N |
| `task.created` / `.updated` / `.deleted` / `.assigned` | `['ws',w,'robot',r,'tasks']`, `['ws',w,'my-tasks']`, + cadeia de rollup |
| `task_advance.created` | `['ws',w,'robot',r,'tasks']`, `['ws',w,'task',t,'advances']`, `['ws',w,'my-tasks']`, + cadeia de rollup |
| `membership.created` / `.role_changed` / `.revoked` | `['ws',w,'members']`, `['ws',w,'people']`; se for o próprio usuário → D6.7 |
| `notification.created` | `['ws',w,'notifications']` |
| `workspace.updated` / `.reset` | `['ws',w]` (subárvore inteira) |

"Cadeia de rollup" = `['ws',w,'robot',r]`, `['ws',w,'cell',c]`, `['ws',w,'project',p]`,
`['ws',w,'overview']`, derivada do `scope` do envelope — é por isso que `scope` carrega os
três ancestrais mesmo quando a entidade é uma tarefa. Sem isso o anel de progresso de
`progress-rollup` (§2.1) fica velho enquanto a linha da tabela já atualizou, que é pior que
não atualizar nada: mostra duas métricas em desacordo na mesma tela (D15).

Invalidação usa `invalidateQueries({ queryKey, refetchType: 'active' })`: query desmontada
é marcada stale e refeita ao remontar, não refeita agora.

### D6.4 — Evento durante mutação otimista pendente: `origin_id` + supressão por entidade

Este é o ponto duro. Cenário: usuário registra avanço 40→60, `robot-task-table` aplica
otimista (60 na tela), o POST está em voo ou na fila offline (D7). Chega
`task_advance.created`. Invalidação ingênua dispara refetch; o servidor ainda não commitou
(ou nem recebeu, se offline); a resposta traz **40**; a UI pisca 60→40→60. Em rede de
galpão isso acontece o tempo todo, e o usuário conclui que o app perdeu o registro dele.

**Decisão — três mecanismos, nesta ordem:**

1. **Eco próprio descartado por `origin_id`.** O cliente gera um `origin_id` (UUID) por
   aba/sessão, envia em todo request mutante no header `X-RoboTrack-Origin`, e o publisher
   copia para o envelope. Envelope com `origin_id === meuOrigin` é **descartado** —
   quem originou já aplicou a mutação otimista e já vai reconciliar pela resposta HTTP.
   Isso mata a maioria absoluta dos flickers, que são auto-infligidos.
2. **Gate de mutação pendente.** O React Query já sabe quais mutações estão em voo
   (`useMutationState` / `isMutating` por `mutationKey`). Uma invalidação cuja chave
   intersecta a **mutation key** de uma mutação pendente não é aplicada: entra numa fila de
   invalidações adiadas, chaveada pela entidade. Quando a última mutação daquela entidade
   assenta (`onSettled`, sucesso **ou** erro), a fila é drenada. Efeito: a UI otimista nunca
   compete com um refetch; o refetch acontece depois, quando o valor do servidor já inclui
   a escrita local.
3. **Fila offline como caso do mesmo gate.** A fila de D7 (`offline-pwa`) expõe um seletor
   `hasPendingFor(entityKind, entityId)`. Uma mutação enfileirada, não enviada, conta como
   pendente para o gate — senão um evento de outro membro faria a tela mostrar o valor do
   servidor por cima de um avanço que ainda nem saiu do IndexedDB. Enquanto houver item na
   fila para aquela entidade, a invalidação fica represada e o indicador de gravação
   (`app-shell-navigation`, §"indicador de gravação") mostra pendência — degradação
   **honesta**: a tela está desatualizada e diz que está.

**Alternativa descartada — aplicar o payload do evento por cima do cache com merge
last-write-wins por timestamp.** Exige payload (contra D6.2) e um relógio confiável; com
`recorded_at` vindo do cliente (D8), relógio de celular de campo e fila offline que pode
enviar horas depois, LWW por timestamp **perde escrita legítima**. Rejeitado.

**Alternativa descartada — simplesmente não invalidar enquanto a aba não tiver foco.**
Resolve o flicker por acidente e cria bug pior: a pessoa volta pro app e vê dado velho até
mexer. O gate certo é por mutação pendente, não por foco.

**Teto da fila adiada.** Invalidação represada por mais de **30s** (mutação travada, rede
morta) é aplicada mesmo assim quando a mutação sai de "em voo" para "enfileirada
offline", com a UI já marcada como não-sincronizada — não vale represar indefinidamente.

### D6.5 — `seq` monotônico por workspace e reconciliação na reconexão

**Decisão.** `workspaces.realtime_seq bigint NOT NULL DEFAULT 0`. O publisher incrementa
com `UPDATE workspaces SET realtime_seq = realtime_seq + 1 … RETURNING realtime_seq`,
dentro da transação da mutação, e o broadcast sai **`after_commit`**. O cliente guarda o
último `seq` visto.

Na reconexão o cliente manda `GET /api/v1/workspaces/:id/sync?since=<seq>`, que responde
`{ current_seq, gap: bool, entity_kinds: [...] }` — os **tipos** de entidade tocados desde
`since`, não os eventos. Se `gap` for verdadeiro ou o servidor não conseguir determinar
(ver abaixo), o cliente invalida `['ws', w]` inteiro.

**Por que o `seq` está no `UPDATE` da mesma transação.** É o que garante que
`seq` e commit não divergem: se a transação aborta, o número não foi consumido. O custo é
uma linha quente por workspace — serialização de todas as mutações do workspace na mesma
linha. Aceitável: o workspace é uma equipe de 2–5 pessoas, não um feed global. Se um dia
não for, a saída é `nextval` de sequence por workspace (não transacional, gera buracos —
buraco é falso positivo de `gap`, que só custa um refetch a mais).

**Sobre "quais entidades mudaram desde `since`".** Não há log de eventos persistido
(não-objetivo). O `/sync` responde consultando `updated_at > (SELECT … )` nas tabelas de
domínio do workspace com um teto de janela de **10 minutos**. Fora dessa janela o servidor
responde `gap: true` sem detalhar, e o cliente invalida tudo. É deliberadamente burro: uma
reconexão longa é rara e um refetch completo do workspace é barato para o tamanho de dado
do RoboTrack.

**Alternativa descartada — confiar na reentrega do ActionCable.** ActionCable não tem
replay. Eventos publicados durante a desconexão simplesmente não existem para aquele
cliente. Um cliente que reconecta e não reconcilia mostra dado velho **indefinidamente**,
até alguém mexer — que é exatamente o bug que o plano anterior teria produzido.

### D6.6 — Transporte: WebSocket com fallback de polling, máquina de estados explícita

Estados: `connecting → live` | `connecting → degraded(polling) → connecting` (retry) |
`offline`.

- Tentativa de WebSocket no mount da sessão de workspace. Sem `welcome` em **8s**, ou
  3 falhas de conexão em 60s → `degraded`.
- Em `degraded`, React Query passa a `refetchInterval` de **20s** nas queries **ativas**
  (`refetchIntervalInBackground: false` — aba escondida não pesquisa) e o cliente faz
  `GET /sync` no mesmo ciclo para atualizar o `seq`. 20s porque o ciclo de trabalho real é
  "registrar avanço, andar até o próximo robô": abaixo disso a banda de galpão sofre sem
  ganho perceptível, acima disso a colaboração deixa de parecer ao vivo.
- Reduz para **60s** após 5 minutos sem interação (documento oculto ou sem input), e volta
  a 20s ao primeiro foco.
- Retentativa de WebSocket com backoff exponencial (5s, 15s, 45s, teto 2min) + jitter, **em
  paralelo** ao polling. Sucesso → `live`, polling desligado, reconciliação de D6.5.
- `navigator.onLine === false` → `offline`, nada de polling, e o indicador de conexão
  (`app-shell-navigation`) mostra o estado; a fila de D7 assume.

**O modo é observável.** `realtimeStore` expõe o estado, a topbar mostra "ao vivo" /
"atualizando periodicamente" / "offline", e a proporção de sessões em `degraded` é métrica
emitida para `delivery-and-observability`. Sem isso, um `/cable` mal roteado no proxy
degrada 100% das sessões e ninguém descobre por meses.

**Alternativa descartada — long-polling do próprio ActionCable.** ActionCable não tem
transporte de fallback (diferente do Socket.IO). Reimplementar um é semanas de trabalho
para servir a um caso — proxy hostil — que `refetchInterval` do React Query já resolve com
código que a aplicação inteira já usa (D9).

### D6.7 — Revogação de acesso ao vivo (§3.10)

Dois caminhos, porque o WebSocket pode estar caído justamente quando a revogação acontece:

1. **Pelo canal.** `membership.revoked` cujo `person_id`/`user_id` é o do próprio usuário →
   o cliente mostra o aviso ("Seu acesso a <workspace> foi removido"), remove o workspace do
   índice local (`workspace-tenancy` trata o índice como cache de UI), limpa **toda** a
   subárvore `['ws', w]` do cache do React Query, e navega para o workspace próprio. Do lado
   do servidor, o mesmo `after_commit` chama `stop_all_streams` + `reject_and_stop` na
   conexão daquele usuário, para o caso de a rejeição do cliente falhar.
2. **Pelo HTTP.** Qualquer resposta **403** de rota sob `/api/v1/workspaces/:id/…` para o
   workspace corrente dispara o mesmo procedimento no interceptor do
   `lib/api/client.ts`. É o caminho que cobre revogação em modo `degraded` — e é o análogo
   direto da "negação de permissão" que o `onSnapshot` do legado entregava.

O procedimento é **uma função só**, chamada pelos dois caminhos, e é idempotente: os dois
podem disparar quase simultaneamente e o usuário vê um aviso, não dois.

**Onde a invariante mora.** Na `Membership` (linha removida/`revoked_at`) e na RLS de D2 —
não no canal. O canal é a **detecção**; a negação é do banco. Se os dois caminhos falharem,
o usuário continua vendo cache local obsoleto e **toda** requisição sua dá 403; ele não lê
dado novo. Vazamento de dado novo é impossível; o que se resolve aqui é a experiência.

### D6.8 — Ticket de cable em vez de JWT na query string

**Decisão.** `POST /api/v1/cable_tickets` (autenticado por Bearer normal) devolve um ticket
opaco de **60s**, uso único, guardado no Redis (`cable_ticket:<jti>` com TTL), com o
`user_id`. O cliente conecta em `/cable?ticket=<t>`. `Connection#connect` resolve,
**consome** (`GETDEL`) e faz `reject_unauthorized_connection` se falhar — corrigindo, de
passagem, o `self.current_user = user if user.present?` atual, que aceita anônimo.

**Por quê.** WebSocket em browser não permite header `Authorization` no handshake; alguma
credencial tem que ir na URL. Mas a URL do handshake vai para `access.log` do proxy e do
Rails, para histórico de APM, e para qualquer coisa entre o galpão e o servidor. Um JWT de
sessão ali é comprometimento de sessão inteira a partir de um log. Um ticket de 60s de uso
único vazado num log é inútil na hora em que alguém lê o log.

**Alternativa descartada — `Sec-WebSocket-Protocol` como carreador do token.** Funciona e
não vai para log de URL, mas transforma um valor sensível num campo com semântica de
negociação de subprotocolo que proxies inspecionam e às vezes reescrevem — e o
`@rails/actioncable` não expõe isso de forma limpa.

**Alternativa descartada — cookie `HttpOnly` de sessão.** É o mais limpo, mas D4 fixou
JWT em `Authorization`, sem sessão de cookie; introduzir cookie só para o Cable adiciona
CSRF e configuração de `SameSite`/CORS cross-origin (Vite em outra origem) para benefício
que o ticket já entrega.

### D6.9 — Publicação num ponto único, após commit

`Realtime::PublisherService.publish(event_type:, entity:, scope:, actor:, origin_id:)`,
chamado por um concern `RealtimePublishable` incluído nos models de domínio via
`after_commit on: [:create, :update, :destroy]`.

**Depois do commit, sempre.** Publicar dentro da transação entrega evento de linha que pode
sofrer rollback: o cliente refetcha, não vê nada, e fica com invalidação inútil — ou pior,
com dado que "apareceu e sumiu".

**Alternativa descartada — publicar no service de cada capacidade.** Distribui a
responsabilidade por sete capacidades escritas por autores diferentes, e a primeira que
esquecer produz exatamente o bug desta proposta: uma tela que não é ao vivo, sem ninguém
notar. Um único ponto acoplado ao ciclo de vida do model é auditável — e **testável**: há
um spec que enumera os models de domínio e falha se algum não inclui o concern.

**Alternativa descartada — trigger no Postgres com `NOTIFY`.** Impossível de contornar
(ganha em garantia), mas exige um listener dedicado, não enxerga `origin_id`
(que é contexto de request) e complica migrations. Rejeitado pelo `origin_id`, que é o
que sustenta D6.4.

**Falha no publish nunca derruba a mutação.** `PublisherService` engole exceção de Redis,
loga estruturado e incrementa contador de erro. Um Redis fora do ar deixa o sistema **não
ao vivo**, não quebrado — e o `seq` do cliente fica para trás, então a próxima reconexão
reconcilia sozinha. É a mesma disciplina best-effort de §2.7.

## Risks / Trade-offs

- **Linha quente do `realtime_seq`.** Mutações concorrentes no mesmo workspace serializam
  no `UPDATE`. Com 2–5 pessoas é ruído; com importação em massa
  (`legacy-data-migration`) é contenção real. Mitigação: o importador publica **um** evento
  `workspace.reset`/`import.finished` no fim e suprime eventos por linha (flag de contexto
  no publisher). Sem isso, importar 3.000 tarefas gera 3.000 broadcasts.
- **Coalescência mascara evento.** Drenar a 250ms com dedup pode fundir dois eventos
  distintos numa invalidação. Aceito: invalidação é idempotente e o refetch traz o estado
  final dos dois.
- **Gate de mutação pendente pode represar demais.** Rede ruim + fila offline longa deixam
  a tela desatualizada por minutos. Mitigado pelo teto de 30s (D6.4) e pelo indicador
  honesto — mas é uma escolha consciente de *desatualizado e sinalizado* em vez de
  *piscante e enganoso*.
- **Cliente não confiável para descartar.** O descarte por `origin_id` é do cliente. Um
  cliente adulterado poderia ignorar — mas só se prejudica (vê refetch a mais). Não é
  fronteira de segurança; a fronteira é membership + RLS.
- **Fan-out de assinatura.** Usuário com três workspaces abre três subscriptions na mesma
  conexão. É barato, mas o alerta de conexões do Cable precisa contar **subscriptions**, não
  conexões, para não subestimar carga — dito a `delivery-and-observability`.
- **Ordem de entrega.** ActionCable não garante ordem sob reconexão parcial. Como o
  envelope é ponteiro (D6.2), evento fora de ordem só causa refetch a mais — nunca estado
  errado. É o principal argumento estrutural a favor de D6.2, e o motivo de não ser
  seguro adicionar payload depois sem reabrir esta decisão.

## Plano de migração

1. Depende de `seal-template-baseline` ter vedado o Cable anônimo e removido
   `lead_chat`/`whatsapp_instance` e a referência morta a `Purchase` em `connection.rb`.
2. `cable.yml` ganha `channel_prefix: robotrack_<env>` e `CABLE_REDIS_URL` própria
   (db separado do Sidekiq). Provisionamento e rota `/cable` com upgrade de WS no proxy:
   `delivery-and-observability`.
3. Migration aditiva `add_column :workspaces, :realtime_seq, :bigint, null: false,
   default: 0` — sem backfill, sem destrutivo, reversível.
4. `?token=` e `?ticket=` coexistem atrás de `CABLE_ALLOW_TOKEN_PARAM` (default `false` em
   produção) só durante o deploy; a flag é removida na tarefa final. Sem janela de
   coexistência o deploy derruba toda sessão aberta no meio do turno.
5. Frontend entra atrás de `VITE_REALTIME_ENABLED`. Desligado, a aplicação continua
   correta — só não é ao vivo. Isso torna rollback um toggle, não um redeploy.

## Perguntas em aberto

- O `origin_id` deve ser por **aba** ou por **dispositivo**? Por aba, duas abas do mesmo
  usuário se atualizam mutuamente (correto, e testável). Por dispositivo, não. Assumido
  **por aba**; a fila offline de D7 é por origem de dispositivo (IndexedDB compartilhado),
  então uma mutação enfileirada por outra aba chega com `origin_id` alheio e o gate de
  D6.4 precisa consultar a fila, não só o `origin_id` — já previsto no item 3 de D6.4, mas
  vale confirmar com `offline-pwa`.
- `notification.created` chega pelo `WorkspaceChannel` ou por um canal de usuário?
  Assumido **workspace**, com o cliente filtrando por destinatário. Isso significa que o
  envelope de notificação trafega para membros que não são destinatários — por isso o
  envelope não carrega o texto (§2.7 permite até 500 chars), só o ponteiro. Confirmar com
  `in-app-notifications`.
- O `/sync` cobre `task_advances` por `created_at` (append-only, D8) ou precisa de
  `recorded_at`? Assumido `created_at`, porque `recorded_at` vem do cliente e pode ser
  passado — usar `recorded_at` na janela de reconciliação perderia avanço enfileirado offline.

## Fora de escopo por priorização

Presença ("quem está nesta tela"), replay de eventos persistidos, throttle por usuário
no canal (rack-attack cobre o HTTP; o Cable fica com o limite de subscriptions do servidor)
e broadcast seletivo por papel (`view` recebe os mesmos eventos que `edit` — são ponteiros,
e a leitura subsequente passa por policy).
