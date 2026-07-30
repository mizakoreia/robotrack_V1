# Deploy do RoboTrack no Render (Blueprint) — passo a passo

Este guia sobe o RoboTrack no **Render** usando o Blueprint (`render.yaml`) que já
está no repositório. Feito para quem **não é desenvolvedor**: é copiar-colar. No
fim, o app fica no ar numa URL pública.

> **Não derruba a demo do Mac.** Este deploy é 100% na nuvem do Render, com **banco
> e Redis próprios**. A demo local (Mac + túneis) e o Render são dois mundos
> separados: dados diferentes, URLs diferentes. Um não enxerga o outro.

---

## 0. O que o Blueprint cria (visão geral)

| Serviço | O que é | Plano |
|---|---|---|
| `robotrack-backend` | API Rails (o cérebro) **+ Sidekiq embutido** (tarefas em segundo plano) | free |
| `robotrack-frontend` | Site React (a tela) | free (Static Site) |
| `robotrack-db` | Postgres gerenciado | free |
| `robotrack-kv` | 1 Redis (Key Value), com 3 dbs lógicos (cache/fila/cable) | free |

> **Sem worker separado no free.** O plano gratuito do Render **não** oferece
> Background Worker. Então o Sidekiq (tarefas em segundo plano) roda **dentro** do
> `robotrack-backend`, no mesmo processo. Nada a configurar — o start do backend já
> sobe os dois. Detalhes e o caminho para separá-los no plano pago estão no final.

**Por que 1 Redis com 3 dbs e 2 usuários de banco?** É exigência do próprio app (ele
recusa subir com topologia insegura ou como dono do banco). No free só se pode ter
**uma** Key Value por workspace, então cache, fila e broadcast dividem a mesma
instância em **bancos lógicos distintos** (o app deriva isso sozinho). Está explicado
no final, em "Decisões técnicas". Você não precisa entender para seguir — só precisa
nomear um usuário de banco exatamente `robotrack_app` no passo 4.

---

## 1. Contas necessárias

1. O código precisa estar no **GitHub** (repo `robotrack_V1`). Já está.
2. Crie uma conta em **https://render.com** → "Get Started" → **entre com o GitHub**
   (mais simples: já autoriza o Render a ler o repo).
   - Quando o Render pedir acesso ao GitHub, autorize **apenas o repositório
     `robotrack_V1`** (não precisa dar acesso a todos).

---

## 2. Criar o Blueprint

1. No painel do Render: **New +** → **Blueprint**.
2. Selecione o repositório **`robotrack_V1`** e a branch **`main`**.
3. O Render encontra o `render.yaml` sozinho e lista os serviços acima.
4. Dê um nome ao grupo (ex.: `robotrack`) e clique **Apply** / **Create**.

O Render começa a criar tudo. **É NORMAL o `robotrack-backend` FALHAR neste primeiro
deploy** — ele ainda não tem o usuário de banco `robotrack_app` (você cria no passo
4) nem os endereços que faltam (passo 5). Siga em frente.

---

## 3. Pegar as URLs públicas

Depois do Apply, cada serviço ganha uma URL. Anote as duas que vamos usar (no painel,
abra cada serviço e copie o endereço no topo, algo como `https://...onrender.com`):

- **Backend** → `https://robotrack-backend-XXXX.onrender.com`  → chamaremos de **URL-BACKEND**
- **Frontend** → `https://robotrack-frontend-XXXX.onrender.com` → chamaremos de **URL-FRONTEND**

(O sufixo `-XXXX` varia; use o que o painel mostrar.)

---

## 4. Criar o 2º usuário do banco (`robotrack_app`)

O Render entrega o banco com **um** usuário (o dono). O app precisa de um **segundo**
usuário, sem poderes de dono, para o dia a dia.

1. No painel, abra **`robotrack-db`**.
2. Vá em **Access Control** (ou "Database Users" / "Credentials", conforme a versão
   do painel) → **Add User**.
3. No nome do usuário, digite **exatamente**: `robotrack_app`  ← (esse nome importa)
4. Salve. O Render mostra as **conexões** desse usuário. Copie a **Internal Database
   URL** dele → chamaremos de **URL-APP** (começa com `postgresql://robotrack_app:...`).
5. Ainda em `robotrack-db`, copie também a **Internal Database URL do usuário
   principal** (o dono, chamado `robotrack`) → chamaremos de **URL-DONO**.

> Use sempre a **Internal** URL (rede interna do Render), não a External.

---

## 5. Preencher os valores que faltam (copiar-colar)

Estes são os únicos campos manuais. Todo o resto (senhas, tokens, Redis) o Render
gera e liga sozinho.

### 5a. No **`robotrack-backend`** → Environment (aba "Environment"):

| Campo | Valor a colar |
|---|---|
| `DATABASE_URL` | **URL-APP** (do `robotrack_app`, passo 4) |
| `MIGRATION_DATABASE_URL` | **URL-DONO** (do usuário principal, passo 4) |
| `ACTION_CABLE_URL` | `wss://` + URL-BACKEND sem `https://` + `/cable`  → ex.: `wss://robotrack-backend-XXXX.onrender.com/cable` |
| `APP_URL` | **URL-FRONTEND** (ex.: `https://robotrack-frontend-XXXX.onrender.com`) |
| `CORS_ORIGINS` | **URL-FRONTEND** (a mesma de cima, sem barra no fim) |

> Esses 5 campos aparecem porque estão num grupo compartilhado (`robotrack-shared`).
> Se o painel os mostrar dentro do grupo em vez do serviço, edite-os lá — o efeito é
> o mesmo (o backend herda).

### 5b. No **`robotrack-frontend`** → Environment:

| Campo | Valor a colar |
|---|---|
| `VITE_API_URL` | **URL-BACKEND** (ex.: `https://robotrack-backend-XXXX.onrender.com`) |
| `VITE_WS_URL` | `wss://` + URL-BACKEND sem `https://`  → ex.: `wss://robotrack-backend-XXXX.onrender.com` |

Salve nos dois serviços.

---

## 6. Subir de verdade (redeploy)

1. **`robotrack-backend`** → **Manual Deploy** → **Deploy latest commit**.
   - **Não há passo de "pre-deploy".** No plano free o Render não permite pre-deploy,
     então o release (migrar o banco + conceder os acessos ao `robotrack_app`)
     acontece **no início do próprio serviço**, toda vez que o backend sobe.
   - Por isso o **primeiro boot demora um pouco mais**: antes do app atender, ele
     roda as migrations (como o usuário dono/migrator) e reaplica os papéis. Só
     depois o Puma sobe como `robotrack_app`.
   - Acompanhe em **Logs** (aba **Logs** do `robotrack-backend`). Você verá as linhas
     `[render-start] Redis por função derivado ...`, `[render-start] release: ...`,
     `[render-start] subindo Sidekiq EMBUTIDO ...` e `[render-start] release
     concluído — subindo Puma ...`; em seguida o serviço fica **Live** (bolinha
     verde). O Sidekiq (tarefas em segundo plano) sobe **no mesmo processo** — não há
     serviço de worker separado para acompanhar.
2. **`robotrack-frontend`** → **Manual Deploy** → **Deploy latest commit** (para o
   site ser reconstruído já com `VITE_API_URL`/`VITE_WS_URL`).

> **Nota (cold start no free):** como o release roda no start, cada vez que o backend
> acorda de hibernar ele repete migrate + papéis. É **idempotente** (migrate e os
> GRANT/REVOKE podem rodar de novo sem efeito colateral), só adiciona alguns segundos
> ao primeiro request após dormir. No free é 1 instância, então não há corrida.

---

## 7. Validar que subiu

1. **Saúde do backend:** abra `URL-BACKEND/health/ready` no navegador → deve
   responder um JSON de "ok/ready" (status 200). Se responder, banco e Redis estão
   conectados.
2. **App no ar:** abra **URL-FRONTEND** → deve carregar a tela de entrada.
3. **Login demo / criar conta:** crie uma conta ou entre com o fluxo de convite.
   Depois crie um **workspace** e um **projeto** para confirmar que escreve no banco.
4. **Tempo real:** abra o app em duas abas no mesmo workspace e faça um avanço numa;
   a outra deve refletir (é o WebSocket `/cable`).

Se `/health/ready` responder erro, veja **Logs** do `robotrack-backend`:
- "topologia de Redis insegura" → os dbs derivados ficaram iguais (não deveria: o
  start deriva `/0`, `/1`, `/2`). Confira que a Key Value `robotrack-kv` existe e
  está ligada ao backend (`REDIS_URL`), e que você **não** colou um `REDIS_*_URL`
  manual no painel sobrescrevendo a derivação.
- "papel corrente tem privilégio UPDATE sobre audit_logs" → o `DATABASE_URL` está
  apontando para o **dono** em vez do `robotrack_app`. Corrija o `DATABASE_URL`
  (passo 5a) e redeploy.
- erro de conexão/`role ... does not exist` → o usuário `robotrack_app` não foi
  criado com esse nome exato (passo 4) ou as URLs estão trocadas.

---

## 8. Avisos honestos sobre o plano FREE

O free é ótimo para demonstrar, mas tem limites reais:

- **O Postgres free EXPIRA.** O Render permite **um** Postgres free por workspace, com
  **1 GB** e **expiração em ~30 dias** (14 dias de carência para migrar). O painel
  mostra a **data de expiração** exata na página do `robotrack-db`. Quando expira,
  **os dados somem**. Para algo que precisa durar, troque o banco para um plano pago
  (a partir de poucos dólares/mês — o preço atual aparece no painel).
- **O backend free HIBERNA.** Depois de ~15 min sem acesso, o serviço "dorme". O
  próximo acesso acorda o serviço e demora **~30–60s** (o "cold start"). Não é bug —
  é o free. Para ficar **sempre ligado**, suba `robotrack-backend` para o plano
  **Starter** (poucos dólares/mês).
- **Tarefas agendadas podem não rodar enquanto o backend hiberna.** Como o Sidekiq
  roda **dentro** do backend e o processo dorme quando ocioso, jobs *agendados por
  tempo* (ex.: expurgo de convite expirado) podem **atrasar ou pular** enquanto
  ninguém usa o app. **Não é crítico no beta:** as notificações são disparadas por
  **ação do usuário** — e essa ação acorda o serviço, que então processa a fila.
- **Só existe UMA Key Value free por workspace.** Por isso cache, fila e broadcast
  dividem `robotrack-kv` em dbs lógicos distintos, com `noeviction` (a fila e o
  broadcast nunca perdem dados; o cache degrada como "miss" sob pressão). Isso é
  seguro para o beta. **Não persiste**: se reiniciar, perde o conteúdo (cache/fila/
  broadcast são recriados). Produção séria: ver "Plano pago" abaixo.
- **O Static Site (frontend) é grátis e não hiberna** — só o backend dorme.

### Plano pago (quando o beta virar produção)

Nada precisa ser recriado — é só subir de plano o que precisar:

- **Sempre ligado + dados que duram:** `robotrack-backend` em **Starter** + Postgres
  em plano pago.
- **Worker Sidekiq dedicado** (tira a fila de dentro do web): reative o bloco
  `robotrack-worker` (comentado em `render.yaml`) num plano pago **e** remova o start
  do Sidekiq de `backend/bin/render-web-start` — senão os dois processariam a fila.
- **Isolamento real de Redis** (cache evictável numa instância à parte de fila/
  cable): crie Key Values pagas separadas e aponte `REDIS_CACHE_URL` /
  `REDIS_QUEUE_URL` / `REDIS_CABLE_URL` a hosts distintos (aí não se usa mais a
  derivação por db do start). O guard de topologia aceita tanto hosts distintos
  quanto dbs distintos.

É a decisão de custo que depende de você — dá para começar tudo free e migrar só o
que precisar, incrementalmente.

---

## 9. A demo do Mac e o Render convivem

- São **ambientes separados**: bancos diferentes, Redis diferente, URLs diferentes.
- Criar dados no Render **não afeta** a demo do Mac e vice-versa.
- Você pode manter os dois no ar ao mesmo tempo sem conflito. Os arquivos de túnel da
  demo (`vite.config.ts`, `client.ts`) **não** vão para o Render — o Blueprint usa a
  configuração de produção limpa.

---

## 10. Google login (opcional)

O login por **e-mail/senha e por código de convite funciona sem configurar nada**. O
botão "Entrar com Google" só funciona se você cadastrar as credenciais do Google
(Client ID/Secret) e registrar o redirect `URL-BACKEND/users/auth/google_oauth2/callback`
no Google Cloud. Como não é obrigatório para demonstrar, deixei de fora do Blueprint.
Se quiser, me avise que eu preparo esse passo à parte.

---

## 11. Manutenção (para quem for mexer no código depois)

- **`Dockerfile.backend` espelha os estágios de backend do `./Dockerfile`.** Se um dia
  o `./Dockerfile` mudar (versão do Ruby, pacotes, etc.), replique no `Dockerfile.backend`.
  Existe porque o Render sempre builda o **último** estágio de um Dockerfile, e o
  último do `./Dockerfile` é o nginx do frontend — não o backend.
- **Migrations destrutivas (`contract`)** são bloqueadas pelo release sem um backup
  verificado (`BACKUP_MANIFEST`). O deploy inicial e migrations comuns passam normal;
  se um dia um deploy travar citando backup, é uma migration `contract` — fale comigo.
- **Auto-deploy:** por padrão o Render redeploya a cada push na `main`. Se preferir
  deploy manual, desligue "Auto-Deploy" em cada serviço.

---

## 12. Decisões técnicas (por que a topologia é essa)

- **Dois papéis de banco.** O app **recusa** rodar conectado como o dono do banco: um
  guard de imutabilidade aborta o boot se o papel do runtime puder alterar o log de
  auditoria. Por isso o runtime usa o `robotrack_app` (2º usuário, sem posse), e as
  migrations usam o usuário dono do Render. O **requisito inegociável** — o runtime
  **nunca** contorna a segurança por linha (RLS) — está garantido: o usuário do Render
  é sem-superusuário e sem-BYPASSRLS, e a RLS é **forçada** (vale até para o dono).
  O único ponto que o Render não automatiza é **criar/colar** o 2º usuário (passos 4–5)
  — daí o passo manual.
- **Redis separado por função (1 instância no free, 3 dbs).** O app separa cache
  (pode descartar dados sob pressão) de fila e broadcast (não podem). Um guard aborta
  o boot se dois resolverem para o mesmo `(host, porta, db)`. No free só há **uma**
  Key Value por workspace, então o start (`bin/render-web-start`) deriva três URLs da
  mesma instância em **dbs lógicos** distintos (`/0` cache, `/1` fila, `/2` cable) —
  o guard passa. Escolhemos `noeviction` na instância para que fila e broadcast
  **nunca** percam dados; o hazard que o guard persegue (um cache `allkeys-lru`
  evictando jobs) fica neutralizado. O isolamento por **instância** separada existe
  no plano pago (ver "Plano pago") — no free, dbs distintos são a alternativa mínima
  que respeita o guard **sem afrouxar a segurança**.
- **Frontend cross-origin.** A autenticação é por token (Bearer) e o tempo real usa
  ticket, então o site pode falar com o backend em outro domínio via CORS — sem
  precisar de proxy de WebSocket (que CDN de site estático não faz).
