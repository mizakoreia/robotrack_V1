## Context

Esta capacidade não constrói produto. Ela constrói os **instrumentos que provam** o
que as fontes de verdade afirmam, e os **portões que reprovam** quem estoura.

Três fatos moldam todo o desenho:

1. **O ambiente é hostil e é requisito.** `PRODUCT.md §Users` descreve celular na
   mão, **de luva**, sob luz forte e irregular de galpão. Isso não é "acessibilidade
   como conformidade" — é a condição normal de uso do usuário mediano. Por isso o
   alvo de toque é **32px** e não os 24px que WCAG 2.2 AA exige, e por isso o tema
   escuro é o primário. Um requisito de a11y aqui falha em campo, não em auditoria.
2. **As afirmações do `DESIGN.md` estão erradas em três pontos, e só o cálculo
   mostrou.** O documento diz *"Medido em `dashboard`, `mytasks`, `settings` e
   `robot`, nos dois temas: nenhum texto abaixo do mínimo AA"* — e, duas linhas
   acima, admite que `--accent-solid` dá 3.68:1 e `--danger-solid` 3.76:1, *"os dois
   reprovam em AA"*. As duas frases se contradizem, e a contradição sobreviveu
   porque ninguém tinha um número reprodutível. O cálculo com composição alfa achou
   ainda uma terceira: a tinta de `N/A` no tema claro dá **2.25:1**. É o argumento
   de por que a tabela de contraste vira **teste**, não parágrafo de documentação.
3. **Os dois maiores riscos do porte são invisíveis para teste unitário.**
   Vazamento entre tenants só se prova com duas sessões concorrentes; sincronização
   offline só se prova com um service worker registrado e a rede realmente
   derrubada. Um mock de `navigator.onLine` prova que o código lê uma flag, não que
   a fila drena na ordem certa quando a rede volta.

## Goals / Non-Goals

**Goals**
- Todo requisito de a11y carrega um **número medido** e o par de cores/elementos de
  onde ele saiu. "Atende AA" é reprovado em revisão.
- Cinco fluxos E2E, escolhidos porque nenhum outro nível de teste os alcança.
- Orçamento de query **constante em relação ao tamanho do dataset** — é o que
  detecta N+1, e não um limite absoluto que se afrouxa quando incomoda.
- D14 com **format string versionada e snapshot persistido**: mudar o texto de uma
  notificação não pode reescrever um log de auditoria de seis meses atrás.
- Suíte E2E abaixo de **8 minutos** em paralelo de 4 *workers*. Acima disso ela é
  desligada por quem está com pressa, e aí ela não existe.

**Non-Goals**
- Cobertura de linha como meta. Não fixamos percentual de SimpleCov; ele mede o
  que foi executado, não o que foi verificado.
- Testes com leitores de tela reais como gate. Testamos a **árvore de
  acessibilidade** (determinística); VoiceOver/NVDA ficam como passagem manual
  registrada, uma vez, antes do release.
- Performance de produção (RUM/APM/tracing) — `delivery-and-observability`.
- i18n de verdade. Um locale, sem fallback, sem seletor.
- Testes de carga reais (k6, milhares de usuários concorrentes). Medimos **forma**
  de query e p95 de request único em dataset grande, não concorrência.

## Decisions

### D-QA-1 — Playwright, não Cypress, não Selenium

**Decisão:** Playwright (`@playwright/test`), Chromium + WebKit, sem Firefox.

**Por quê, ligado aos fluxos que precisamos:**
- Dois usuários num teste só exigem **dois `BrowserContext` independentes no mesmo
  processo**, com cookies e `localStorage` separados. Playwright faz isso
  nativamente (`browser.newContext()` × 2). É requisito duro dos fluxos 1
  (convite) e 4 (revogação ao vivo), onde as duas sessões precisam existir
  **simultaneamente** — o dono revoga enquanto o convidado está com a tela aberta.
- Offline real: `context.setOffline(true)` corta a rede na camada do navegador, e
  Playwright **registra e controla service workers** (`context.serviceWorkers()`).
  É requisito do fluxo 2 e de D7.
- Trace viewer com DOM, rede e console por passo — que é o que torna uma falha
  intermitente de E2E depurável em vez de ser marcada como `skip`.

**Alternativa descartada — Cypress:** não suporta duas sessões de usuário
independentes no mesmo spec (o modelo é uma origem, um contexto; `cy.session`
alterna, não coexiste). Isso **elimina** os fluxos 1 e 4, que são metade da razão
de existir da suíte. Suporte a service worker é historicamente frágil.
**Alternativa descartada — Selenium/Capybara:** duas sessões exigem dois drivers e
dois processos; sem controle de service worker; e teríamos o E2E em Ruby, longe do
código de UI que ele exercita.
**Firefox fica de fora** deliberadamente: o custo de CI triplica e o produto é um
PWA de chão de fábrica — Chromium (Android/desktop) e WebKit (iOS) cobrem o parque.

### D-QA-2 — O dataset E2E é semeado por *task* do backend, nunca pela UI

**Decisão:** todo estado inicial de E2E vem de `bin/rails rt:seed:e2e[cenario]`,
executado antes do teste; a UI só é usada para o que o teste está de fato
verificando. Cada cenário é idempotente e trunca o que semeia.

**Por quê:** o fluxo 5 (relatório) precisa de um dataset onde as **duas métricas de
D15 divergem** e onde os números do A4 são conferíveis contra literais. Construir
isso clicando são ~200 interações antes do primeiro assert, e cada uma é um ponto
de falha intermitente que não tem nada a ver com o relatório.

**Alternativa descartada — construir via API dentro do teste:** menos frágil que a
UI, mas amarra o dataset ao contrato da API, que ainda vai mudar; e paga latência
HTTP por linha (7.440 tarefas). O seed roda `insert_all` em transação.
**Alternativa descartada — dump SQL restaurado:** rápido, mas apodrece a cada
migration e ninguém consegue ler o diff.

**Onde mora a garantia de determinismo:** o seed usa **UUIDs literais fixos**
(D1 permite PK fornecida pelo cliente), não `Faker` com semente. Semente aleatória
com `srand` quebra silenciosamente quando a ordem de geração muda. UUID literal no
teste é o mesmo UUID no seed, e o assert cita o UUID.

### D-QA-3 — Contraste é **calculado**, não amostrado por screenshot

**Decisão:** um módulo de cálculo (`e2e/a11y/contrast.ts`) lê os tokens do CSS
compilado, **compõe as camadas alfa** e calcula a razão WCAG 2.1. O teste
compara com uma **tabela de valores esperados literais** e falha se o valor
computado divergir do esperado em mais de 0.01 — para cima ou para baixo.

**Por quê a composição alfa é obrigatória:** quase nenhuma superfície do RoboTrack
é opaca. `--bg-panel` é `rgba(18,26,47,0.7)` **sobre** `--bg-main`; a pílula de
status tinge 15% **sobre** o painel; `--bg-sunken` é `rgba(0,0,0,0.28)` sobre o
painel. Medir "texto sobre `--bg-panel`" tratando o token como cor sólida dá um
número que não existe na tela. É exatamente por isso que a tinta de `N/A` passou
despercebida: `#a1a1aa` contra um painel branco imaginário parece defensável;
contra a pílula `N/A` real (que é `#a1a1aa` a 15% sobre o painel claro, ou seja
`rgb(233,233,234)`) dá **2.25:1**.

**Alternativa descartada — axe-core sozinho:** o axe amostra o pixel renderizado, o
que é ótimo, mas (a) não roda em combinações que não estão na tela naquele momento,
(b) desiste quando há gradiente ou `backdrop-filter` atrás — e o RoboTrack tem os
dois em toda superfície de vidro, então o axe reporta `incomplete`, não `pass`.
Usamos os dois: **cálculo** para a matriz completa e determinística, **axe** para
pegar o que a matriz não previu (rótulo faltando, ordem de heading, `aria-*`
inválido).

**Falha para cima também:** se alguém "melhora" um token e o valor sobe, o teste
falha. Não é rigidez gratuita — é o gatilho para atualizar a tabela conscientemente
em vez de deixar a documentação divergir da realidade outra vez.

#### Tabela medida (composição alfa aplicada, sRGB, WCAG 2.1)

**Tema escuro** — `--bg-panel` resolvido = `rgb(15,22,39)`:

| Par | Razão | Mín. | |
|---|---|---|---|
| `--text-main #f8fafc` / `--bg-main #0a0f1d` | **18.26:1** | 4.5 | ✓ |
| `--text-main` / `--bg-panel` (resolvido) | **17.09:1** | 4.5 | ✓ |
| `--text-main` / `--bg-menu` (resolvido) | **17.08:1** | 4.5 | ✓ |
| `--text-muted #94a3b8` / `--bg-main` | **7.45:1** | 4.5 | ✓ |
| `--text-muted` / `--bg-panel` | **6.97:1** | 4.5 | ✓ |
| `--text-muted` / `--bg-sunken` sobre painel | **7.38:1** | 4.5 | ✓ |
| `--accent #3b82f6` como texto / `--bg-panel` | **4.86:1** | 4.5 | ✓ |
| branco / `--accent-solid #3b82f6` | **3.68:1** | 4.5 | ✗ |
| branco / `--danger-solid #ef4444` | **3.76:1** | 4.5 | ✗ |
| `--success-ink` / pílula success (15% s/ painel) | **5.58:1** | 4.5 | ✓ |
| `--warning-ink` / pílula warning | **6.48:1** | 4.5 | ✓ |
| `--accent-ink #60a5fa` / pílula accent | **5.83:1** | 4.5 | ✓ |
| `--danger-ink #f87171` / pílula danger | **5.62:1** | 4.5 | ✓ |
| `#a1a1aa` / pílula N/A | **5.46:1** | 4.5 | ✓ |
| `--accent` (anel) / `--track` | **3.80:1** | 3.0 | ✓ |

**Tema claro** — `--bg-panel` resolvido = `rgb(253,254,254)`:

| Par | Razão | Mín. | |
|---|---|---|---|
| `--text-main #0f172a` / `--bg-main #f1f5f9` | **16.30:1** | 4.5 | ✓ |
| `--text-main` / `--bg-panel` | **17.69:1** | 4.5 | ✓ |
| `--text-muted #475569` / `--bg-main` | **6.92:1** | 4.5 | ✓ |
| `--text-muted` / `--bg-panel` | **7.51:1** | 4.5 | ✓ |
| `--text-muted` / `--bg-sunken` sobre painel | **6.93:1** | 4.5 | ✓ |
| `--accent #2563eb` como texto / `--bg-panel` | **5.12:1** | 4.5 | ✓ |
| branco / `--accent-solid #2563eb` | **5.17:1** | 4.5 | ✓ |
| `--success-ink #065f46` / pílula success `rgb(218,244,236)` | **6.62:1** | 4.5 | ✓ |
| `--warning-ink #92400e` / pílula warning | **6.27:1** | 4.5 | ✓ |
| `--danger-ink #991b1b` / pílula danger | **6.77:1** | 4.5 | ✓ |
| `--accent-ink #1e40af` / pílula accent | **7.28:1** | 4.5 | ✓ |
| `#a1a1aa` / pílula N/A `rgb(233,233,234)` | **2.25:1** | 4.5 | ✗ |
| `--accent` (anel) / `--track` | **4.00:1** | 3.0 | ✓ |

**Prova de que a variante `-ink` é obrigatória (não redundância de token):** usar a
cor cheia como texto sobre a própria pílula, no tema claro, dá success **2.18:1**,
warning **1.90:1**, danger **3.07:1**, accent **3.07:1** — as quatro reprovam.
No escuro, `--accent` cheio sobre a pílula dá **4.03:1** e `--danger` **4.13:1** —
as duas reprovam. É o número que impede alguém de "simplificar" o sistema
eliminando os `-ink`.

**Três correções, com o valor de destino:**
- `--accent-solid`: `#3b82f6` → **`#2563eb`** nos dois temas (3.68 → **5.17:1**).
- `--danger-solid`: `#ef4444` → **`#dc2626`** no escuro (**4.83:1**), **`#b91c1c`**
  no claro (**6.47:1**).
- tinta de `N/A` no claro: `#a1a1aa` → **`#52525b`** (2.25 → **6.09:1**). No escuro
  `#a1a1aa` fica (5.46:1) — a assimetria é a mesma que o `DESIGN.md` já documenta
  para azul e vermelho: a pílula clareia o fundo no claro e o escurece no escuro.

Implementação dos três é de `design-system`; aqui mora o número e o teste.

### D-QA-4 — `aria-live` é **um** por região, e o indicador de gravação é `polite`

**Decisão:** exatamente **três** regiões `aria-live` no app inteiro, todas montadas
uma vez no shell e nunca condicionalmente:
- `#rt-status` — `aria-live="polite"` `aria-atomic="true"`: indicador de gravação
  (`salvando` / `salvo` / `erro ao salvar`) e confirmações de mutação.
- `#rt-notifications` — `aria-live="polite"`: chegada de notificação (§2.7).
- `#rt-alerts` — `aria-live="assertive"` `role="alert"`: **só** falha de
  persistência e perda de acesso ao workspace (revogação ao vivo).

**Por quê essa divisão:** `assertive` interrompe o leitor de tela no meio da frase.
Usar `assertive` para "salvo" transforma cada avanço registrado numa interrupção —
e o usuário registra dezenas por turno. Mas usar `polite` para "você perdeu acesso
a este workspace" deixa a pessoa continuar digitando num formulário que não vai
salvar. A régua é: **`assertive` só quando a ação em curso da pessoa deixou de ser
possível.**

**Por quê montada uma vez, nunca condicional:** uma região `aria-live` inserida no
DOM **junto** com seu conteúdo não é anunciada — o leitor de tela precisa observar
a região desde antes da mudança. É o erro mais comum de implementação de
`aria-live` e ele passa em qualquer teste de snapshot de DOM. Por isso há cenário
de teste específico que monta o shell vazio e afirma que as três regiões já
existem.

**Alternativa descartada — `role="status"` nos componentes:** espalha regiões vivas
por toda a árvore; duas visíveis ao mesmo tempo produzem anúncio duplicado ou
engolido, dependendo do leitor.

**Onde mora a invariante:** um teste de componente monta o `AppShell` sem nenhuma
rota e afirma a existência e os atributos das três regiões; um sweep afirma que
`aria-live` não aparece em nenhum outro arquivo de `src/` fora do módulo do shell.

### D-QA-5 — O pulso de 100% (§3.5) move o foco; o anel é `role="img"`

**Decisão:** quando uma tarefa chega a 100% e o `successPulse` dispara, o foco
**não** é movido (isso roubaria o foco de quem está no meio de outra ação); em vez
disso o texto de resultado vai para `#rt-status`, e o anel do robô expõe
`role="img"` com `aria-label` **completo e legível**:
`"Progresso do robô R01 - Solda: 100 por cento, ponderado"` — incluindo o rótulo da
métrica exigido por **D15**. Barras de progresso usam `role="progressbar"` com
`aria-valuenow`/`aria-valuemin`/`aria-valuemax` e `aria-valuetext` em pt-BR.

**Por quê `role="img"` no anel e `progressbar` na barra:** o anel é SVG decorativo
com um `<path>` — sem `role`, leitores anunciam o conteúdo do SVG (ou nada). Ele
não é um controle e não é indeterminado: é um valor pronto, ou seja, uma imagem com
descrição. A barra do hub, essa sim, é a representação canônica de `progressbar`.
Isso não é preferência estética: é a distinção que o `DESIGN.md §Components` já faz
entre anel (leitura de um valor) e barra de hub (progresso agregado).

**Por quê o foco não se move:** o pulso pode disparar por ação de **outra pessoa**
(D6, colaboração ao vivo). Mover foco por evento remoto é hostil e é falha de
`3.2.x` do WCAG. O único caso em que o foco se move é o de **Esc fechando menu ou
modal**, que devolve o foco **ao gatilho** — invariante testada por cenário próprio.

### D-QA-6 — Orçamento de query é **constante**, medido por dois tamanhos

**Decisão:** cada tela orçada é medida **duas vezes** — no dataset pequeno e no
dataset de carga — e o teste falha se o número **variar**, mesmo que ambos fiquem
sob o teto absoluto.

**Por quê:** um teto absoluto ("≤ 30 queries") é a forma padrão de não pegar N+1: o
dataset de teste tem 3 projetos, o N+1 gera 3 queries extras, e passa folgado. A
assinatura de N+1 é **variação com o tamanho**, e é isso que se mede. O teto
absoluto continua existindo como segundo gate, mas o gate real é a constância.

**Orçamentos (queries SQL por request, contadas via `ActiveSupport::Notifications`
em `sql.active_record`, descontando `SCHEMA`/`TRANSACTION`):**

| Tela / endpoint | Queries | p95 no dataset de carga |
|---|---|---|
| Visão Geral (`GET /projects`, 4 projetos) | **≤ 6** | 150 ms |
| Projeto (`GET /projects/:id/cells`, 6 células) | **≤ 6** | 150 ms |
| Célula (`GET /cells/:id/robots`, 10 robôs) | **≤ 6** | 150 ms |
| Robô (`GET /robots/:id/tasks`, 31 tarefas + responsáveis) | **≤ 8** | 200 ms |
| Minhas Tarefas (`GET /me/tasks`, ~120 linhas) | **≤ 6** | 200 ms |
| Notificações (`GET /notifications`, 50) | **≤ 4** | 100 ms |
| Relatório A4 (`GET /report`, workspace inteiro: 240 robôs, 7.440 tarefas, 22.320 avanços) | **≤ 12** | 1.200 ms |

O relatório é o único com teto de latência alto e é proposital: ele agrega a árvore
inteira com histórico por tarefa (§3.8). O que **não** é negociável ali é o nº de
queries — 12 constantes com 240 robôs é a diferença entre um relatório e um
timeout.

**Dataset de carga (`rt:seed:load`), tamanhos exatos:**
- `WS-CARGA`: 4 projetos · 24 células (6/projeto) · 240 robôs (10/célula) ·
  **7.440 tarefas** (31/robô, os 31 padrões de §1.2) · **22.320 avanços**
  (3/tarefa) · 12 pessoas · 5 memberships · 1.500 notificações · 8.000 logs de
  auditoria.
- `WS-ISCA`: 1 projeto · 1 célula · 1 robô · 31 tarefas, **com nomes distintivos**
  (`ISCA-*`) para que qualquer vazamento apareça como texto reconhecível no DOM ou
  no corpo JSON, e não como um id que ninguém confere.
- Os 24 cards do `WS-CARGA` **não** são coincidência: são o número que o
  `DESIGN.md §Luz ambiente` cita como cenário medido. A tela de Projeto exibe 6
  células e a Visão Geral 4 projetos; a de Célula exibe 10 robôs. Os 24 cards
  medidos vêm da tela de célula com o *grid* em 5 colunas + hubs — o teste de INP
  força viewport de 1440×900 e conta 24 `.card` em tela antes de medir.

### D-QA-7 — Orçamento de bundle por chunk, em gzip, no build de produção

| Alvo | Teto (gzip) | Por quê esse número |
|---|---|---|
| JS do *entry* inicial | **250 KB** | shell + auth + Visão Geral em 3G de galpão |
| CSS inicial | **40 KB** | Tailwind purgado + tokens dos dois temas |
| Chunk do relatório (`/relatorio`, lazy) | **120 KB** | carrega só quem gera A4 |
| Chunk de gráficos (Recharts, lazy) | **180 KB** | nunca no *entry* |
| Soma de todos os chunks | **900 KB** | teto do PWA pré-cacheado |

**Regra estrutural, testada além do tamanho:** `recharts`, `gsap`, `@tiptap/*` e
`slate*` **não podem** aparecer no grafo do chunk inicial. O sweep inspeciona o
`stats.json` do Rollup por **nome de módulo**, não só por bytes: uma dependência
pesada que entra no *entry* mas ainda cabe nos 250 KB hoje passa no teste de
tamanho e quebra no próximo commit. (TipTap **e** Slate coexistirem é dívida do
template; `seal-template-baseline` remove um dos dois — se ambos ainda existirem,
este sweep falha e nomeia os dois.)

### D-QA-8 (D14) — Chave + argumentos + **snapshot renderizado**, com `format_version`

**Decisão:** notificações (§2.7) e logs de auditoria (§2.8) persistem **quatro**
colunas de mensagem:
- `message_key` (ex.: `audit.task.status_changed`),
- `message_args` (`jsonb`, valores já resolvidos: nomes, números, ids),
- `message` (o texto pt-BR **renderizado no momento da escrita**, ≤ 500 chars),
- `format_version` (`integer`, versão do catálogo naquele momento).

A **exibição usa `message`**, o snapshot. `message_key` + `message_args` existem
para reprocessamento, análise e para provar que a linha veio do catálogo.

**Por quê o snapshot vence a renderização em leitura:** o log de auditoria tem
`REVOKE UPDATE, DELETE` (D12) — ele é imutável **por decisão de banco**. Renderizar
em leitura significa que trocar uma vírgula no `pt-BR.audit.yml` **reescreve
retroativamente** o texto de todos os registros históricos, contornando o `REVOKE`
por fora. A imutabilidade morreria no lugar onde ninguém a procura: no catálogo de
strings. O mesmo argumento vale, com força ainda maior, para o relatório A4 —
`commissioning-report` produz um documento que **o cliente assina** (§3.8); o texto
daquele documento não pode mudar depois de assinado.

**Alternativa descartada — só o texto renderizado, sem chave:** é o que o legado
fazia, e torna impossível saber se uma linha veio do catálogo ou de um literal que
alguém digitou num service. Sem a chave, o sweep de D14 não teria o que verificar.
**Alternativa descartada — só chave + args, renderizando em leitura:** economiza
bytes e quebra a imutabilidade, como acima.

**`format_version` sobe quando o *significado* muda**, não quando a redação muda.
Trocar "Tarefa concluída por %{nome}" por "Tarefa concluída por %{nome} em
%{data}" adiciona um argumento — as linhas antigas não têm `data` em `message_args`
e não podem ser rerrenderizadas. É o que a versão registra.

**Onde mora a invariante (três camadas, nesta ordem):**
1. **Banco** — `CHECK (message_key ~ '^[a-z][a-z0-9_.]*$')` e
   `message_key NOT NULL` em `notifications` e `audit_logs`. Uma linha sem chave
   não entra. (As colunas são criadas pelas migrations de `in-app-notifications` e
   `audit-log`; nós especificamos a semântica e o `CHECK`.)
2. **Serviço** — `Rt::Message.render(key, **args)` é o **único** caminho de escrita;
   ele resolve pelo `I18n`, valida que todos os `%{...}` do template foram
   fornecidos (`I18n::MissingInterpolationArgument` vira erro, não string com
   `%{nome}` literal aparecendo em produção) e retorna `[texto, versão]`.
3. **Sweep de CI** — `spec/i18n/string_sweep_spec.rb` varre
   `app/services/notifications/`, `app/services/audit_logs/` e
   `app/services/reports/` procurando literal de string com 3+ letras ou qualquer
   caractere acentuado, fora de `# rt:i18n-ok` explícito. Mais
   `I18n` completeness: toda chave usada existe, **e** toda chave definida é usada
   (chave órfã é sintoma de string que voltou a ser literal em algum lugar).

**Frontend:** módulo único `frontend/src/lib/i18n/pt-BR.ts` exportando um objeto
`const` com `as const`, e `t(key, params)` **tipado** — chave inexistente é erro de
**TypeScript**, não de runtime. Não usamos i18next: uma dependência de 40 KB para
um locale, sem plural complexo além do que `Intl.PluralRules` já resolve, não paga.
Sweep de Vitest sobre `src/features/**` e `src/components/**` procurando nó de
texto JSX com caractere acentuado ou palavra pt-BR fora de `t(...)`.

### D-QA-9 — Vazamento entre tenants é verificado no **DOM e no corpo da resposta**, por texto

**Decisão:** o E2E de troca de workspace (fluxo 3) afirma que, depois de trocar de
`WS-CARGA` para `WS-ISCA`, a string `ISCA-` **não** aparece em nenhum lugar do DOM
enquanto se está em `WS-CARGA`, e vice-versa — e que **nenhuma resposta de rede
capturada** durante a sessão contém o id do workspace oposto.

**Por quê texto e não id:** um assert por id passa quando o vazamento é de nome
(um cache de React Query não invalidado exibindo o nome antigo do projeto por 300ms
antes do refetch é exatamente o bug que D9 e a troca de workspace de
`app-shell-navigation` existem para prevenir, e ele nunca aparece numa asserção de
id). Por isso o `WS-ISCA` tem nomes com prefixo próprio: o vazamento vira uma
string que o teste procura literalmente.

**Isto não substitui os testes negativos de `authorization-policies`.** Aqueles
provam que o servidor **nega**; este prova que o cliente **não mostra** o que já
carregou. São falhas diferentes com causas diferentes.

## Riscos / Trade-offs

- **E2E intermitente mata a suíte.** Mitigação: zero `waitForTimeout` — só
  espera por estado (`expect(locator).toBeVisible()`, resposta de rede específica);
  `retries: 1` no CI e **zero** localmente (retry local esconde flake de quem podia
  consertar); trace + vídeo retidos só em falha; e **falhar duas vezes seguidas no
  `main` marca o teste como bloqueante, não como candidato a `skip`**. Um teste E2E
  desabilitado é pior que ausente, porque dá a impressão de cobertura.
- **A tabela de contraste engessa o design.** É proposital, mas o custo é real:
  qualquer mudança de token exige atualizar a tabela. Aceitamos — a atualização é
  uma linha e é onde a decisão fica registrada. O risco maior é o oposto: tabela
  atualizada mecanicamente para "fazer o teste passar" com um valor reprovado.
  Mitigação: o teste tem os mínimos (4.5 texto, 3.0 não-texto) **codificados
  separadamente** da tabela de valores esperados; baixar um valor abaixo do mínimo
  falha mesmo com a tabela atualizada.
- **Orçamento de query constante pode ser burlado com cache.** Se alguém adicionar
  um cache de aplicação, o segundo request tem menos queries e o teste de constância
  vira ruído. Mitigação: a medição roda com cache de query do AR limpo entre as
  duas amostras, e o teste declara isso explicitamente.
- **`format_version` é um campo que ninguém vai lembrar de incrementar.** Risco
  aceito e mitigado parcialmente: o `Rt::Message` lê a versão de uma constante por
  namespace no próprio YAML, e o sweep falha se o conjunto de argumentos de uma
  chave mudar sem a versão subir (comparando com um *snapshot* de assinatura de
  chaves versionado no repo). Não pega mudança puramente redacional — e não deve.
- **Dataset de carga de 22.320 avanços deixa o CI mais lento.** Ele é semeado uma
  vez por job (`insert_all`, ~8 s) e usado por todos os testes de orçamento.
  Não é usado pelos testes de request comuns, que continuam com factories mínimas.
- **32px de alvo de toque conflita com densidade de tabela.** A tabela do robô
  (§3.5) tem 6 colunas e reflui para cartões no mobile. No desktop, 32px de altura
  por controle numa tabela de 31 linhas é alto. Trade-off aceito e delimitado: o
  mínimo de 32px vale para **controles tocáveis** (`.status-select`, botões de
  ícone, chips clicáveis); não vale para linha de tabela inteira nem para link de
  texto em fluxo — que o WCAG 2.5.8 já isenta.
- **A capacidade é grande e as tarefas foram consolidadas.** Quatro frentes num
  change só produzem naturalmente mais do que o alvo de 30 tarefas. `tasks.md`
  fecha em **39**, e isso está declarado em vez de disfarçado: consolidar mais
  produziria tarefas que são duas, que é o defeito pior. Tarefas fortemente
  acopladas já foram fundidas (os dois sweeps de literal de D14; o teto de bundle
  e a regra de composição, que leem o mesmo `stats.json`; o módulo de contraste e
  sua tabela de esperados). Mitigação do risco de tarefa-que-é-duas: cada tarefa
  agrupada tem **um único critério de falha** citado entre parênteses — se um
  agrupamento precisar de dois critérios independentes durante a execução, ele deve
  ser quebrado ali mesmo.
- **O que ficou fora do escopo por priorização**, e não por decisão de produto:
  teste de mutação sobre as policies; auditoria de a11y das telas de erro e de
  offline (cobrimos as 8 principais); orçamento de performance do service worker
  (tempo de instalação e tamanho do pré-cache — `offline-pwa` mede o seu);
  medição de contraste dos estados `:hover`/`:active`, que só medimos em repouso;
  e teste de leitor de tela real como gate. Se algum destes virar prioridade,
  entra como change próprio, não inflando este.
- **Ficou de fora, conscientemente:** teste de contraste sobre a camada
  `.glass-sheen` em movimento (a luz ambiente muda o fundo continuamente sob o
  cursor). Medimos na posição de repouso, que é onde `prefers-reduced-motion` e o
  toque deixam a luz. Medir o pior caso da luz em movimento exigiria varrer o
  espaço de posições — desproporcional para um halo de accent a baixa opacidade.
  Registrado como pergunta em aberto.

## Plano de migração

Não há dado a migrar — nada foi construído. A ordem de introdução importa:

1. **Antes das telas:** catálogo pt-BR, `Rt::Message`, factories de domínio, helper
   `as_member_of`, dataset de carga. São dependências de quem vem depois; entregues
   cedo, evitam que 20 capacidades inventem 20 padrões de string e de fixture.
2. **Junto com `design-system`:** os três tokens corrigidos e a tabela de
   contraste. Corrigir `--accent-solid` depois de 12 telas usarem é uma varredura
   visual em todas elas.
3. **Depois das telas (Onda 10 propriamente):** os cinco fluxos E2E, o gate
   `axe-core` e os orçamentos de query/bundle/INP. Só aí existe o que medir.

Os itens (1) e (2) são de fato **pré-requisito** e estão nos grupos 1–3 de
`tasks.md`; declará-los como Onda 10 inteira seria mentir sobre a ordem.

## Perguntas em aberto

- **Qual é o pior caso de contraste sob a luz ambiente em movimento?** Medimos em
  repouso. Se a medição de repouso do `--text-muted` sobre painel (6.97:1 escuro)
  cair perto de 4.5:1 com o halo em cima, a folga some. Ação proposta: uma medição
  única e manual do halo no seu ponto de maior opacidade, registrada na tabela como
  nota — não como teste.
- **WebKit no CI vale o custo?** Chromium cobre Android e desktop; WebKit cobre
  iOS, onde o comportamento de service worker e de `IndexedDB` é notoriamente
  diferente — e o fluxo 2 depende dos dois. Proposta: rodar os 5 fluxos em Chromium
  a cada PR e a matriz completa (Chromium + WebKit) só no `main`, para não pagar o
  dobro em cada revisão. Decidir com `delivery-and-observability`, que é dono do
  orçamento de CI.
- **O p95 de 1.200 ms do relatório é aceitável para o usuário, ou é só aceitável
  para o teste?** 240 robôs é um workspace grande; o mediano terá ~30. Se o campo
  mostrar workspaces maiores que o dataset de carga, o relatório vira job assíncrono
  com download — decisão de `commissioning-report`, não nossa, mas o número sai
  daqui.
