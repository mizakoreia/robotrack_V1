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
| `robotrack-backend` | API Rails (o cérebro) | free |
| `robotrack-worker` | Sidekiq (tarefas em segundo plano) | free |
| `robotrack-frontend` | Site React (a tela) | free (Static Site) |
| `robotrack-db` | Postgres gerenciado | free |
| `robotrack-kv-cache` / `-queue` / `-cable` | 3 Redis (Key Value) | free |

**Por que 3 Redis e 2 usuários de banco?** É exigência do próprio app (ele recusa
subir com topologia insegura ou como dono do banco). Está explicado no final, em
"Decisões técnicas". Você não precisa entender para seguir — só precisa nomear um
usuário de banco exatamente `robotrack_app` no passo 4.

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
> o mesmo (web e worker herdam).

### 5b. No **`robotrack-frontend`** → Environment:

| Campo | Valor a colar |
|---|---|
| `VITE_API_URL` | **URL-BACKEND** (ex.: `https://robotrack-backend-XXXX.onrender.com`) |
| `VITE_WS_URL` | `wss://` + URL-BACKEND sem `https://`  → ex.: `wss://robotrack-backend-XXXX.onrender.com` |

Salve nos dois serviços.

---

## 6. Subir de verdade (redeploy)

1. **`robotrack-backend`** → **Manual Deploy** → **Deploy latest commit**.
   - Agora o release migra o banco e concede os acessos ao `robotrack_app`.
   - Acompanhe em **Logs**. No fim você deve ver o release concluir e o serviço
     ficar **Live** (bolinha verde). O `robotrack-worker` sobe junto (pode reiniciar
     1–2 vezes até o backend terminar o release — normal).
2. **`robotrack-frontend`** → **Manual Deploy** → **Deploy latest commit** (para o
   site ser reconstruído já com `VITE_API_URL`/`VITE_WS_URL`).

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
- "topologia de Redis insegura" → algum `REDIS_*_URL` ficou igual (não deveria, com
  as 3 instâncias). Confira que as 3 Key Value existem.
- "papel corrente tem privilégio UPDATE sobre audit_logs" → o `DATABASE_URL` está
  apontando para o **dono** em vez do `robotrack_app`. Corrija o `DATABASE_URL`
  (passo 5a) e redeploy.
- erro de conexão/`role ... does not exist` → o usuário `robotrack_app` não foi
  criado com esse nome exato (passo 4) ou as URLs estão trocadas.

---

## 8. Avisos honestos sobre o plano FREE

O free é ótimo para demonstrar, mas tem limites reais:

- **O Postgres free EXPIRA.** O Render remove bancos de dados gratuitos depois de um
  período (o painel mostra a **data de expiração** exata na página do `robotrack-db`).
  Quando expira, **os dados somem**. Para algo que precisa durar, troque o banco para
  um plano pago (a partir de poucos dólares/mês — o preço atual aparece no painel).
- **Web/worker free HIBERNAM.** Depois de ~15 min sem acesso, o serviço "dorme". O
  próximo acesso acorda o serviço e demora **~30–60s** (o "cold start"). Não é bug —
  é o free. Para ficar **sempre ligado**, suba `robotrack-backend` (e idealmente o
  `robotrack-worker`) para o plano **Starter** (poucos dólares/mês cada).
- **Os Redis (Key Value) free NÃO persistem.** Se reiniciam, perdem o conteúdo. Para
  a demo tudo bem (cache/fila/broadcast são recriados). Se for produção séria, vale
  plano pago com persistência na fila.
- **O Static Site (frontend) é grátis e não hiberna** — só o backend/worker dormem.

**Resumo do custo para "sempre ligado, dados que duram":** backend Starter + banco
pago (e, se quiser, worker Starter). É a decisão de custo que depende de você — dá
para começar tudo free e migrar só o que precisar depois, sem recriar nada.

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
- **Três Redis.** O app separa cache (pode descartar dados sob pressão) de fila e
  broadcast (não podem). Um guard aborta o boot se dois compartilharem a mesma
  instância. Três instâncias free resolvem sem truque.
- **Frontend cross-origin.** A autenticação é por token (Bearer) e o tempo real usa
  ticket, então o site pode falar com o backend em outro domínio via CORS — sem
  precisar de proxy de WebSocket (que CDN de site estático não faz).
