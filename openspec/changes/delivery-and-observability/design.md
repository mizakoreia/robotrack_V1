## Context

Esta capacidade está na Onda 0, junto de `seal-template-baseline` e `design-system`.
Ela não tem dependência de domínio — e é dependência de quase todo o resto. Três coisas
justificam ela existir antes do domínio:

1. **D6** declara adapter Redis obrigatório em produção; **D5** declara um alerta de
   divergência; **D7** declara poison message. Nenhum dos três tinha dono de infra.
2. `seal-template-baseline` **remove** `ExceptionNotifier`. Se o substituto não chega no
   mesmo ciclo, a janela entre os dois é um sistema sem visibilidade de exceção.
3. `audit-log` cria `audit_logs` com `REVOKE UPDATE, DELETE` (**D12**). Se a tabela
   nascer não-particionada, a retenção depois vira migration de terabytes com downtime.
   O substrato tem que estar decidido **antes** da migration existir — por isso o
   requisito de particionamento aqui é um contrato que `audit-log` implementa, não um
   retrofit.

### Inventário do que já existe (verificado no repo)

| Arquivo | Estado hoje | Problema |
|---|---|---|
| `Dockerfile` | multi-stage, `backend-prod` roda `rails assets:precompile` | app é API-only; roda como root; sem `HEALTHCHECK`; `bundle config without development test` no estágio base, então o `-dev` não tem gems de dev |
| `docker-compose.yml` | postgres 14, redis 7, backend, frontend, sidekiq | só dev; senha literal; sem healthcheck; sem `depends_on: condition: service_healthy` |
| `Procfile.dev` | `backend` / `worker` / `frontend` | não há `Procfile` de produção nem fase de release |
| `backend/config/database.yml` | só `development` e `test`, credenciais literais (`robotrack_user`/`silas777`) | **não existe seção `production`** — deploy não sobe; segredo versionado |
| `backend/config/cable.yml` | `production: adapter: redis, url: REDIS_URL` | adapter certo, mas **mesmo banco lógico** do Sidekiq e do cache; sem `channel_prefix` → dois ambientes no mesmo Redis se cruzam |
| `backend/config/initializers/sidekiq.rb` | `REDIS_URL` db 1 | idem |
| `production.rb` | `cache_store` redis db 1, `log_tags [:request_id]` | idem; log ainda é texto, não JSON |
| `backend/config/initializers/rack_attack.rb` | `MemoryStore`, throttle 60/min/IP, `logins/*` em `/api/v1/auth/login` | store por processo; path que **D4 remove**; safelist de `127.0.0.1` é inócua atrás de proxy (o IP real vem em `X-Forwarded-For`) |
| `backend/.env.example` | Asaas, WhatsApp, SMTP, JWT | descreve integrações que o seal remove; sem inventário das novas |
| `setup.sh` / `create_dev_db.sh` | onboarding de dev, lê `database.yml` para criar role/DB | `create_dev_db.sh` **lê `development` do `database.yml`** — mudar para `DATABASE_URL` quebra o script se não for ajustado junto |

Nota de correção ao briefing: `cable.yml` **já** usa `adapter: redis` em `development`
(não `async`). O buraco real não é o adapter — é o isolamento do banco lógico e o
`channel_prefix`. O requisito continua sendo desta capacidade.

## Goals / Non-Goals

**Goals**
- Um comando de deploy reproduzível que sobe web + worker + cable e roda migrations numa
  fase própria, com rollback documentado e ensaiado.
- Toda exceção não tratada em qualquer um dos três processos chega a um lugar
  pesquisável, com `workspace_id` anexado e sem PII no payload.
- Um canal de alerta único que D5, D7 e `workspace-invitations` chamam sem reinventar.
- Nenhuma tabela do sistema cresce sem política declarada.
- Nenhum endpoint de escrita de domínio fica sem teto de taxa.
- Nenhuma variável de ambiente existe fora do registro.

**Non-Goals**
- Escolha de provedor, IaC, autoscaling, multi-região, DR de outra região.
- Traço distribuído, profiling contínuo, análise de custo.
- Retenção legal/LGPD de dado pessoal (é decisão de produto, não de infra) — aqui só o
  mecanismo.

## Decisions

### D-DO-1 — Redis: três bancos lógicos com políticas distintas, não um

`REDIS_CACHE_URL` (db 0), `REDIS_QUEUE_URL` (db 1), `REDIS_CABLE_URL` (db 2). O boot em
`production`/`staging` **falha** se os três resolverem para o mesmo par `(host, db)`.

Motivo: cache quer `maxmemory-policy allkeys-lru` (descartar é correto); Sidekiq exige
`noeviction` (descartar é perder trabalho enfileirado); Cable é efêmero mas tem padrão de
pub/sub que compete por CPU com o `BRPOP` do Sidekiq. Hoje os três dividem `db 1`, então
qualquer pressão de memória no cache **apaga jobs**.

**Onde mora a invariante:** não é validação de model — é um check no boot
(`config/initializers/redis_topology.rb`) que aborta o processo, mais um requisito de
prova operacional (`CONFIG GET maxmemory-policy` por URL). Falha no boot, não em runtime.

**Alternativa descartada:** uma única instância com prefixos de chave. Prefixo não muda
política de eviction — o modo de falha (job sumindo silenciosamente sob pressão de
memória) continua existindo e é invisível.

### D-DO-2 — `channel_prefix` do ActionCable é obrigatório e inclui o ambiente

`channel_prefix: robotrack_<env>`. Sem ele, `staging` e `production` apontando para o
mesmo Redis (cenário normal em plano gratuito) entregam broadcast de um workspace de
staging a clientes de produção — vazamento entre tenants por caminho não-HTTP, que
`authorization-policies` não cobre porque nem passa por policy.

**Onde mora a invariante:** `cable.yml` + o mesmo check de boot de D-DO-1, que recusa
`channel_prefix` ausente ou igual entre dois ambientes que compartilham host Redis.

**Alternativa descartada:** confiar em instâncias Redis separadas por ambiente. É
verdade quando alguém paga por elas; o modo de falha é silencioso e catastrófico quando
não.

### D-DO-3 — Retenção de `audit_logs` por particionamento + `DROP`, nunca por `DELETE`

**D12** dá `REVOKE UPDATE, DELETE ON audit_logs` ao papel da aplicação. Retenção por
`DELETE` exige devolver o privilégio a alguém — e um privilégio que existe é um
privilégio que um bug usa. Decisão: `audit_logs` nasce **particionada por RANGE em
`recorded_at`, uma partição por mês**. A retenção roda `ALTER TABLE … DETACH PARTITION` +
`DROP TABLE` da partição inteira. `DROP TABLE` é privilégio de **owner/DDL**, não é
`DELETE` — o `REVOKE` permanece intacto e o papel de runtime da aplicação continua sem
poder apagar uma linha sequer.

Consequência vinculante para `audit-log`: a migration de criação **já** cria a tabela
particionada e a função/job que pré-cria a partição do mês seguinte. Se a partição do mês
corrente não existir, todo `INSERT` de auditoria falha — logo, pré-criação com folga de
**duas** partições à frente e alerta se a folga cair para uma.

Retenção padrão: **24 meses**. Antes do primeiro `DROP`, a partição é exportada para
armazenamento de objeto em formato lido pelo `legacy-data-migration`/backup JSON.

**Alternativa descartada (a):** retenção infinita. Aceitável no ano 1, insustentável e
transforma o problema numa migration de tabela grande sob lock mais tarde.
**Alternativa descartada (b):** `GRANT DELETE` a um papel de manutenção usado só pelo
job. Reintroduz exatamente o caminho de escrita que D12 fechou, e o job roda no mesmo
processo Sidekiq que o resto da app.

### D-DO-4 — `Ops::AlertService` é o único canal; severidade decide o destino

Singleton no idioma do template (`class << self`). Assinatura:
`Ops::AlertService.raise_alert(key:, severity:, message:, context: {})`, com
`severity ∈ {info, warning, critical}`.

- `info` → só log estruturado.
- `warning` → log + Sentry `capture_message` + webhook de chat.
- `critical` → tudo de `warning` + paginação (destino configurável por
  `ALERT_PAGER_URL`).

Deduplicação por `key` numa janela de 1 hora, no Redis de cache: o job de reconciliação
de D5 roda a cada hora sobre todos os workspaces; sem dedup, uma divergência crônica gera
24 páginas por dia e o alerta é silenciado por fadiga — que é o modo de falha real de
alerta, não a ausência dele.

**Onde mora a invariante:** a dedup é um `SET key NX EX 3600` no Redis de cache, atômico.
Não é `if !recently_alerted?`.

**Alternativa descartada:** cada capacidade chamar `Sentry.capture_message` direto.
Perde-se dedup, severidade uniforme e a possibilidade de trocar o destino num lugar só —
e foi exatamente esse acoplamento espalhado (`ExceptionNotifier` em todo `rescue_from`)
que quebrou o build do template.

### D-DO-5 — Migrations em fase de release separada, com expand/contract obrigatório

O deploy tem quatro passos ordenados: `build → release (db:migrate) → deploy web/worker →
smoke`. Migration **nunca** roda no boot da app (dois processos Puma migrando em paralelo
disputam o lock de `schema_migrations` e o segundo fica bloqueado até o timeout).

Toda migration que toca coluna/tabela existente segue **expand/contract**: expand
(aditivo, compatível com o código antigo) vai num deploy; contract (destrutivo) vai num
deploy **posterior**, depois que o código antigo saiu de circulação. Isso é o que torna
rollback de código possível sem rollback de schema — a única forma de rollback que é
rápida e segura.

Conexão de migration com `lock_timeout = 5s` e `statement_timeout = 15min`: uma migration
que não consegue o lock em 5s **falha o deploy** em vez de enfileirar todas as queries
atrás dela e derrubar o site.

**Onde mora a invariante:** um spec de CI que varre `db/migrate/` e falha se uma
migration contiver `remove_column`, `drop_table`, `change_column` ou `rename_column`
**sem** um marcador `# contract-of: <migration_version>` apontando para o expand
correspondente já em produção. Convenção em CHANGELOG não é aplicável; grep é.

**Alternativa descartada:** `rails db:migrate` no `CMD` do container. É o padrão do
template e o mais fácil; falha exatamente quando há mais de um processo — que é sempre em
produção.

### D-DO-6 — Rollback de código é a primeira linha; rollback de schema é exceção

Runbook em três degraus, com critério de escolha explícito:

1. **Redeploy da imagem anterior** (< 2 min). Sempre possível se D-DO-5 foi respeitado,
   porque o schema em produção é compatível com N-1.
2. **Feature flag / kill switch** para funcionalidade específica (variável de ambiente
   lida em runtime, sem redeploy).
3. **`db:rollback`** — só para o `expand` mais recente e só se ele for provadamente
   aditivo. **Ponto sem volta declarado:** depois que um `contract` roda, rollback de
   schema deixa de ser opção e o caminho é restore de backup com perda de dados igual ao
   RPO. O runbook nomeia esse ponto por migration.

### D-DO-7 — Rate limit por identidade, com IP como fallback, não o contrário

Chave de throttle: `user_id` quando há JWT válido; `ip` quando não há. Motivo concreto: o
usuário-alvo é engenheiro de comissionamento no chão de fábrica; uma equipe inteira sai
pelo mesmo NAT do galpão. Throttle por IP transforma "um usuário abusivo" em "a fábrica
inteira bloqueada" — e a fila offline de **D7** drena em rajada assim que o Wi-Fi volta,
com todos os aparelhos ao mesmo tempo.

Limites (por minuto, por identidade):
- leitura de domínio (`GET /api/v1/**`): 300
- escrita de domínio (`POST|PATCH|DELETE /api/v1/**`): 120
- criação em lote de robôs (`robot-tasks`, 1–50 por chamada): 10
- avanço de tarefa (`progress-advances`): 60
- autenticação (`identity-and-auth`, os paths de D4 — não o `/auth/login` do template): 5
- geração de relatório (`commissioning-report`): 5

`Retry-After` é obrigatório na resposta 429 (hoje só há `X-RateLimit-*`), porque a fila
offline precisa de um valor para recuar em vez de tentar de novo imediatamente e ser
bloqueada de novo.

**Onde mora a invariante:** store do `rack-attack` no Redis de cache (não `MemoryStore`),
que é o que faz o contador ser global em vez de por processo. Com 4 processos Puma, o
limite de hoje é 4× o declarado — o código atual está errado, não só incompleto.

**Alternativa descartada:** throttle no proxy/CDN. Não vê o `user_id`, só o IP — recai
exatamente no problema do NAT.

### D-DO-8 — Registro tipado de configuração com fail-fast no boot

`backend/config/env_schema.rb` declara cada variável: nome, obrigatória em quais
ambientes, tipo, default, e **qual capacidade a introduziu**. O boot em
`production`/`staging` aborta listando *todas* as ausentes de uma vez (não a primeira).
`.env.example` é **gerado** por rake task a partir do schema; um spec falha se o arquivo
gerado divergir do commitado.

**Onde mora a invariante:** o spec de divergência. Documentação que pode divergir do
código sempre diverge; a única forma de manter `.env.example` verdadeiro é gerá-lo e
testar a igualdade.

**Alternativa descartada:** `ENV.fetch('X', default)` espalhado — o padrão atual do
template. O default silencioso é o problema: `production.rb` hoje tem
`ACTION_CABLE_URL` com default `wss://example.com/cable`, que sobe alegremente e quebra o
WebSocket de todo mundo sem um único erro no log.

### D-DO-9 — CDN e service worker: contrato de cache explícito

O bundle React é servido de armazenamento estático + CDN. **D7** diz que o service worker
é network-first para asset próprio e nunca intercepta `/api`. Para isso não travar numa
versão:
- `index.html` e `sw.js`: `Cache-Control: no-store`.
- assets com hash no nome: `public, max-age=31536000, immutable`.
- `/api/**` na mesma origem via proxy do CDN, com `Cache-Control: no-store` e **sem**
  cache de resposta autenticada.

**Onde mora a invariante:** um smoke test pós-deploy que faz `HEAD` no `index.html` e num
asset com hash e assere os headers. Configuração de CDN é a coisa mais fácil de regredir
por clique no console do provedor.

**Alternativa descartada:** servir o bundle pelo Rails (`RAILS_SERVE_STATIC_FILES`, que o
`.env.example` já ativa). Funciona, mas coloca latência de asset na frente do mesmo pool
de threads Puma que atende `/api` — e o usuário está em 4G de galpão.

### D-DO-10 — Log estruturado JSON, sem corpo de requisição

lograge com formato JSON e campos: `request_id`, `method`, `path`, `status`, `duration`,
`db_runtime`, `user_id`, `workspace_id`, `person_id`, `policy` (de **D3**). Corpo de
requisição e resposta **nunca** são logados; `filter_parameter_logging.rb` cobre
`password`, `token`, `jwt`, `secret`, `invitation_token`, `authorization`.

`workspace_id` no log é o que torna um incidente investigável sem consultar o banco — e
é o campo que **D2** (RLS por `app.current_workspace_id`) já obriga a existir na request.

## Plano de migração

1. **Não destrutivo primeiro.** `env_schema.rb`, Sentry, lograge, health checks e
   `Ops::AlertService` entram sem mexer em dado. Podem ir antes de qualquer domínio.
2. **Redis split.** As três URLs passam a existir com default apontando para o valor
   antigo de `REDIS_URL`; o check de boot que *proíbe* colisão é ligado só em
   `production`/`staging`, e só depois que o ambiente real tiver os três provisionados.
   Isso evita quebrar dev no dia da mudança.
3. **`database.yml`.** Seção `production` via `DATABASE_URL` entra primeiro; `development`
   e `test` migram para `DATABASE_URL` com fallback ao valor atual **no mesmo commit em
   que `create_dev_db.sh` é ajustado** — o script lê `database.yml` para criar a role, e
   quebrá-lo trava o onboarding.
4. **Particionamento de `audit_logs`.** Coordenado com `audit-log` (Onda 6): esta
   capacidade entrega o *contrato* e a rake task de gestão de partição; a migration de
   criação é da `audit-log`. Não há retrofit porque a tabela ainda não existe.
5. **Rack-attack.** Store Redis e limites de domínio só depois que os endpoints existirem
   (Onda 4+). Entram primeiro os limites globais de leitura/escrita, que não dependem de
   path específico.
6. **Rollback ensaiado** em staging antes do primeiro deploy de produção — um ensaio que
   não aconteceu é um runbook que não existe.

## Riscos / Trade-offs

- **Particionar `audit_logs` acopla esta capacidade à `audit-log`.** Se `audit-log` criar
  a tabela sem partição, a correção depois é cara. Mitigação: o contrato está escrito como
  requisito verificável aqui e a `audit-log` cita como dependência. Se ainda assim
  divergir, o fallback é retenção infinita declarada — não `DELETE`.
- **Fail-fast no boot pode derrubar um deploy por uma variável cosmética.** Trade-off
  aceito: uma falha de deploy é barata e visível; um `wss://example.com/cable` em produção
  é caro e invisível. Mitigação: o schema marca obrigatoriedade por ambiente, então
  variável opcional não derruba nada.
- **Sentry é dependência de terceiro com custo e com PII.** Mitigação: `send_default_pii`
  desligado, scrubbing de `params` no cliente, e o `Ops::AlertService` abstrai o destino —
  trocar por outro backend é um arquivo.
- **Rate limit por `user_id` exige o JWT já decodificado quando o rack-attack roda.**
  Rack-attack é middleware, roda antes do Grape. Mitigação: decodificação leve (só
  `sub`/`jti`, sem hit no banco) dentro do bloco de throttle; se falhar, cai para IP. Um
  token forjado não ganha nada — o limite dele fica atrelado a um `sub` inexistente e a
  autenticação real ainda o rejeita.
- **Limites numéricos são chutes calibrados.** 120 escritas/min por usuário sai de "avanço
  a cada 0,5 s sustentado por um minuto", que é acima do humanamente plausível e abaixo do
  que a drenagem offline em rajada precisa. Precisa reaferição com dado real; por isso os
  valores vivem em ENV, não hardcoded.
- **Três bancos Redis lógicos numa instância ainda compartilham memória e CPU.** Isolar de
  verdade exige três instâncias. Trade-off de custo aceito para o porte inicial; o
  `env_schema` permite apontar para instâncias distintas sem mudar código.

## Perguntas em aberto

- Provedor de hospedagem (define se `release` é `release_command` de Fly/Render ou um job
  no CI). O runbook é escrito em termos de contrato até isso fechar.
- Retenção de `notifications`: 90 dias é o proposto; §2.7 não fala em histórico de
  notificação. Se a UI ganhar "central de notificações com histórico", o número sobe.
- Destino do alerta `critical` (PagerDuty? e-mail? Slack com menção?). Não bloqueia — o
  `Ops::AlertService` já isola a decisão atrás de `ALERT_PAGER_URL`.
- RPO/RTO alvo. O requisito escrito exige *um número declarado e testado*, não um número
  específico.

## Fora de escopo desta entrega (priorização declarada)

São três specs num change só, o que coloca `tasks.md` acima da banda sugerida (35 tarefas).
Ficaram de fora por orçamento, em ordem de prioridade para um change seguinte:
dashboard de métricas montado (aqui só há `/metrics` + alertas), traço distribuído,
autoscaling por profundidade de fila, canary/blue-green (o deploy é rolling simples com
rollback por redeploy), e três instâncias Redis fisicamente separadas em vez de três
bancos lógicos.
