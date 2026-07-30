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
instância em **bancos lógicos distintos** (o app deriva isso sozinho). O segundo
usuário de banco (`robotrack_app`) o **app cria sozinho no primeiro boot** — você
**não** mexe em banco no painel. Está explicado no final, em "Decisões técnicas".
Você não precisa entender para seguir: **o único trabalho manual é colar uma URL em
cada serviço** (a URL pública do outro), no passo 4.

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
deploy** — faltam as duas URLs públicas que só existem depois que os serviços nascem
(você cola no passo 4). O banco o app resolve sozinho. Siga em frente.

---

## 3. Pegar as URLs públicas

Depois do Apply, cada serviço ganha uma URL. Anote as duas (no painel, abra cada
serviço e copie o endereço no topo, algo como `https://...onrender.com`):

- **Backend** → `https://robotrack-backend-XXXX.onrender.com`  → chamaremos de **URL-BACKEND**
- **Frontend** → `https://robotrack-frontend-XXXX.onrender.com` → chamaremos de **URL-FRONTEND**

(O sufixo `-XXXX` varia; use o que o painel mostrar.)

> **Você NÃO mexe no banco.** Não há passo de criar usuário nem de copiar URL de
> Postgres. O Render entrega o banco com um usuário (o dono) e liga a URL dele ao
> backend **automaticamente**; o segundo usuário (`robotrack_app`) o app cria sozinho
> no primeiro boot. (Por isso a UI do Render **não** serve aqui: ela só cria cópias do
> dono, não um usuário não-dono de verdade — daí o app fazer isso por conta própria.)

---

## 4. Colar as duas URLs que faltam (copiar-colar)

São os **únicos** campos manuais: cada serviço precisa saber o endereço público do
**outro** (o Render não liga a URL externa de um serviço a outro). Todo o resto —
senhas, tokens, Redis, **e todas as URLs de banco e de WebSocket** — o Render gera e o
app deriva sozinho.

### 4a. No **`robotrack-backend`** → aba **Environment**:

| Campo | Valor a colar |
|---|---|
| `APP_URL` | **URL-FRONTEND** (ex.: `https://robotrack-frontend-XXXX.onrender.com`, sem barra no fim) |

> Só isso. `CORS_ORIGINS` (mesma origem do frontend) e `ACTION_CABLE_URL` (o
> `/cable` deste próprio backend) são **derivados no start**; `DATABASE_URL` e
> `MIGRATION_DATABASE_URL` o Render/app resolvem sozinhos. Se o painel mostrar
> `APP_URL` dentro do grupo `robotrack-shared` em vez do serviço, edite-o lá — o
> efeito é o mesmo (o backend herda).

### 4b. No **`robotrack-frontend`** → aba **Environment**:

| Campo | Valor a colar |
|---|---|
| `VITE_API_URL` | **URL-BACKEND** (ex.: `https://robotrack-backend-XXXX.onrender.com`) |

> `VITE_WS_URL` (a versão `wss://` da mesma URL) é derivada no build — não se cola.

Salve nos dois serviços.

---

## 5. Subir de verdade (redeploy)

1. **`robotrack-backend`** → **Manual Deploy** → **Deploy latest commit**.
   - **Não há passo de "pre-deploy".** No plano free o Render não permite pre-deploy,
     então o release **e a criação do 2º usuário do banco** acontecem **no início do
     próprio serviço**, toda vez que o backend sobe.
   - Por isso o **primeiro boot demora um pouco mais**: antes do app atender, ele
     **cria o `robotrack_app`** (conectado como o dono), roda as migrations (como o
     dono/migrator) e reaplica os papéis/REVOKE. Só depois o Puma sobe como
     `robotrack_app`.
   - Acompanhe em **Logs** (aba **Logs** do `robotrack-backend`). Você verá as linhas
     `[render-start] Redis por função derivado ...`, `[render-start] DATABASE_URL de
     runtime derivado ...`, `[render-start] ACTION_CABLE_URL derivado ...`,
     `[render-start] release: migrate como MIGRATOR + roles/REVOKE do robotrack_app`
     e `[render-start] release concluído — subindo Puma como robotrack_app`; em
     seguida o serviço fica **Live** (bolinha verde). O Sidekiq (tarefas em segundo
     plano) sobe **no mesmo processo** — não há worker separado para acompanhar.
2. **`robotrack-frontend`** → **Manual Deploy** → **Deploy latest commit** (para o
   site ser reconstruído já com `VITE_API_URL`/`VITE_WS_URL`).

> **Nota (cold start no free):** como o release roda no start, cada vez que o backend
> acorda de hibernar ele repete a criação do papel + migrate. É **idempotente** (o
> `CREATE ROLE` só roda se faltar, e migrate/GRANT/REVOKE re-aplicam sem efeito
> colateral), só adiciona alguns segundos ao primeiro request após dormir. No free é 1
> instância, então não há corrida.

---

## 6. Validar que subiu

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
- "papel corrente tem privilégio UPDATE sobre audit_logs" → o runtime subiu como o
  **dono** em vez do `robotrack_app`. Não deveria acontecer (o `DATABASE_URL` é
  derivado no start); se acontecer, confira nos Logs a linha `DATABASE_URL de runtime
  derivado ...` e que você **não** colou um `DATABASE_URL` manual sobrescrevendo-a.
- `permission denied to create role` / `must have CREATEROLE` → o usuário primário do
  Render não tem CREATEROLE e **não** consegue criar o `robotrack_app`. É a única
  dependência dura deste desenho (ver "Decisões técnicas", § banco). Me avise: o
  plano B é criar o `robotrack_app` uma vez via **psql** (Admin App/console) e então
  o app só reaplica os GRANTs a cada boot.
- `role "robotrack_app" does not exist` → o release não chegou a rodar o `roles.sql`
  (provável boot abortado antes, por `APP_URL` ausente — passo 4a). Cole `APP_URL` e
  redeploy; o start cria o papel.

---

## 7. Avisos honestos sobre o plano FREE

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

## 8. A demo do Mac e o Render convivem

- São **ambientes separados**: bancos diferentes, Redis diferente, URLs diferentes.
- Criar dados no Render **não afeta** a demo do Mac e vice-versa.
- Você pode manter os dois no ar ao mesmo tempo sem conflito. Os arquivos de túnel da
  demo (`vite.config.ts`, `client.ts`) **não** vão para o Render — o Blueprint usa a
  configuração de produção limpa.

---

## 9. Google login (opcional)

O login por **e-mail/senha e por código de convite funciona sem configurar nada**. O
botão "Entrar com Google" só funciona se você cadastrar as credenciais do Google
(Client ID/Secret) e registrar o redirect `URL-BACKEND/users/auth/google_oauth2/callback`
no Google Cloud. Como não é obrigatório para demonstrar, deixei de fora do Blueprint.
Se quiser, me avise que eu preparo esse passo à parte.

---

## 10. Manutenção (para quem for mexer no código depois)

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

## 11. Decisões técnicas (por que a topologia é essa)

- **Dois papéis de banco, criados sozinhos.** O app **recusa** rodar conectado como o
  dono do banco: um guard de imutabilidade aborta o boot se o papel do runtime puder
  alterar o log de auditoria. Por isso o runtime usa o `robotrack_app` (2º usuário, sem
  posse), e as migrations usam o dono do Render. Como a UI do Render **não** cria um
  usuário nomeado não-dono (só "default credentials", que são cópias do dono), o próprio
  app cria o `robotrack_app` no 1º boot: o `bin/render-web-start` roda o `roles.sql`
  conectado como o dono (via `MIGRATION_DATABASE_URL`, ligado por `fromDatabase`), que
  faz `CREATE ROLE robotrack_app` com a senha `APP_DB_PASSWORD` (gerada pelo Render), e
  então deriva o `DATABASE_URL` de runtime dessa senha — **nenhuma URL de banco é colada
  à mão**. O **requisito inegociável** — o runtime **nunca** contorna a RLS — está
  garantido por construção: o dono do Render é sem-superusuário e sem-BYPASSRLS, então
  **não consegue conferir** SUPERUSER/BYPASSRLS ao `robotrack_app`; a RLS é **forçada**
  (vale até para o dono). **Única dependência dura:** o dono do Render precisa ter
  `CREATEROLE` (o Postgres gerenciado concede — a doc do Render descreve criar usuários
  por `CREATE USER` via SQL). Se algum dia não tiver, o `roles.sql` falha nomeando o
  privilégio, e o plano B é criar o `robotrack_app` uma vez via psql (Admin App) — o
  resto do release segue idêntico.
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
