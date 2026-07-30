# Design — internationalization

pt-BR. Cada decisão registra a alternativa descartada e o porquê, e marca **onde a
invariante mora** (model, policy, constraint, trigger, índice, RLS, sweep de CI ou
storage).

## D-I1 — Abordagem: solução própria leve sobre a infra existente (não uma lib pesada)

**Decisão.** Frontend: um `useLanguageStore` (Zustand + `persist`) espelhando o
`themeStore`, e um eixo de idioma dentro dos módulos `lib/i18n` já existentes.
Backend: **reusar rails-i18n** (já presente; `available_locales` já lista `:en`),
adicionando `en.*.yml` e resolução de locale por requisição.

**Alternativas descartadas.**
- **`react-i18next` / `i18next` / `FormatJS`.** Rejeitada: o projeto **bane deps
  pesadas** (`no-heavy-deps.test.ts`, guarda de bundle) e já tem uma disciplina de
  texto (`lib/i18n` + varreduras D14). Trocar por um framework jogaria fora a
  fonte-única-por-capacidade e traria runtime/bundle que o produto recusa.
- **Solução própria do zero no backend também.** Rejeitada: rails-i18n **já está
  configurado** com `:en` disponível e fallback `pt-BR → en`. Reinventar seria
  ignorar infra pronta.

**Onde mora.** O idioma corrente mora no **storage** (`localStorage['rt-lang']` via
`zustandStorage`, com fallback de memória do `safeStorage`) e, quando logado, na
**coluna `users.locale`** (fonte durável). O backend resolve por requisição em um
`around_action`/middleware com `I18n.with_locale`.

## D-I2 — Forma do módulo de texto e o parser dos sweeps (o risco de CI)

**Decisão.** Cada módulo `lib/i18n/<x>.ts` passa a expor os dois idiomas mantendo
**literais planos de uma linha por chave** (ex.: `{ 'pt-BR': { title: 'Equipe' },
en: { title: 'Team' } }`), e um resolvedor `L(<x>Text)` que devolve o mapa do idioma
corrente. As **funções de interpolação/plural** ganham ramo por idioma.

**Por quê / a armadilha.** A regra **G** do `convention-sweep.test.ts` e as varreduras
`*.i18n.test.ts` **parseiam os módulos com regex** que assume `chave: 'valor'` plano
numa linha. Uma forma aninhada arbitrária **quebraria o CI silenciosamente**. Então a
mudança de forma e a **atualização desses parsers** são a **mesma tarefa**, no mesmo
grupo (G1), com prova verde antes de seguir.

**Alternativa descartada.** Módulos paralelos `*.en.ts` separados. Rejeitada: dobra o
número de arquivos, e as varreduras D14 (que casam **frase pt-BR literal**) não
cobririam as cópias EN — divergência garantida.

**Onde mora.** Nos **sweeps de CI** (`convention-sweep` regra G,
`invitations.i18n.test.ts`, `feedback.i18n.test.ts`, `progress-label.test.tsx`,
`report/literalSweep.test.ts`), estendidos para conhecer o eixo de idioma.

## D-I3 — Plural, interpolação, datas e números por locale

**Decisão.** Plural via `Intl.PluralRules` (nativo, sem dep); as funções pt-BR
`n===1?` ganham a categoria `one/other` por idioma. Os **6 pontos** que fixam `'pt-BR'`
(`report/format.ts`, `feedback/FeedbackInbox.tsx`, `robot-tasks/HistoryModal.tsx`,
`robot-tasks/AssignmentModal.tsx`, `settings/CatalogPanel.tsx`,
`kpi/PerformanceIndicators.tsx`) passam a receber o locale corrente.

**Alternativa descartada.** `date-fns`/`dayjs`. Rejeitada: `Intl.DateTimeFormat`
nativo já resolve; nenhuma lib de data é necessária (nem existe hoje).

**Onde mora.** Nos call-sites de formatação (parâmetro de locale) e no `useLanguage()`
(que expõe o locale corrente).

## D-I4 — Dado de domínio é EXIBIÇÃO traduzida, nunca rename (status, aplicações, catálogo)

**Decisão.** Status (`task_status`), as 6 aplicações (`Robot::APPLICATIONS`) e as 31
tarefas-base/9 categorias (`task_templates.cat/desc`) **permanecem gravados em pt-BR**.
O EN é um mapa `Record<valorPtBR, string>` resolvido na tela.

**Por quê.** Estão amarrados no banco: o **enum** `task_status`, o **CHECK**
`application IN (...6 literais...)`, o **CHECK** `done-implies-100` (ligado ao valor
`Concluído`), e a **importação legada** que casa `task_templates` por `desc` (por isso
os erros de grafia são preservados). Renomear o dado quebraria CHECK, enum e importação.

**Alternativa descartada.** Migrar os valores para chaves neutras (ex.: `pending`) e
traduzir os dois idiomas. Rejeitada: migração destrutiva de enum + CHECK + reescrita da
importação legada; alto risco, `🔴`, para zero ganho de produto (o rótulo é exibição).

**Onde mora.** Num mapa de exibição no frontend (chaveado pelo valor pt-BR do banco) e
nos `en.*.yml` de rótulo onde o servidor renderiza (relatório).

## D-I5 — Mensagens congeladas: "congela-para-frente, não reescreve-para-trás" (o cerne)

Três subsistemas, três realidades — **uma estratégia coerente**: resolver o idioma **no
momento da escrita/geração**, no locale da pessoa certa, e **não** reescrever história.

### D-I5a — Notificações (congeladas por destinatário no INSERT)

**Decisão.** `MessageBuilder`/`CreateService` deixam de fixar `LOCALE = :'pt-BR'` e
renderizam a `msg` **no locale do DESTINATÁRIO** (a `msg` já é materializada por
destinatário; o locale vem de `users.locale`, default pt-BR). Congela na linha, como
hoje.

**Prós/contras.** ✔ zero mudança no caminho de leitura; ✔ notificação nasce no idioma
de quem lê; ✔ sem afrouxar o trigger de imutabilidade; ✖ trocar de idioma **depois** não
reescreve notificações antigas (aceitável: transientes, envelhecem).

**Onde mora.** No `MessageBuilder` (parâmetro de locale) e na leitura de `users.locale`
do destinatário dentro do `CreateService#insert_for`. O trigger `notifications_only_
read_update` **permanece intacto** (não gravamos colunas novas).

### D-I5b — Auditoria (congelada + imutável por design)

**Decisão.** **Manter o congelamento.** `RecordService` passa a renderizar a `msg` no
locale do **ATOR** no INSERT (default pt-BR); strings `en` entram como conteúdo das
mesmas versões `vN`. **Linhas históricas não são tocadas.**

**Prós/contras.** ✔ preserva `REVOKE UPDATE,DELETE` + trigger + RLS + guarda de boot +
snapshot de CI; ✔ a trilha registra fielmente o que foi mostrado no momento do evento;
✖ um registro de 2025 em pt-BR continua pt-BR mesmo se a pessoa virar EN (correto para
auditoria — é história).

**Alternativa descartada (o `🔴`).** Guardar `chave + args (jsonb)` e renderizar na
leitura, para trocar idioma retroativamente. **Rejeitada e marcada como não-objetivo:**
exige migração na tabela **append-only imutável** (contra `REVOKE`/trigger/snapshot),
backfill **com perda** (args não foram guardados; `ts_local` é string), e o `down` já é
`IrreversibleMigration` com linhas. É o único caminho que produziria um ponto de
reversão **não-trivial** — e não vale para uma trilha cujo requisito é justamente
**não** ser reescrita.

**Onde mora.** No `RecordService` (locale do ator) e nos `en.audit.*.yml` versionados;
a imutabilidade continua no banco (REVOKE/trigger) e no snapshot de CI.

### D-I5c — Protocolo de Comissionamento (resolvido na leitura)

**Decisão.** `CommissioningReportService#t` passa a resolver `report.v1.*` no locale do
**LEITOR** na geração (hoje usa `default_locale`). Adiciona-se `en.report.yml` sob
`report.v1.*`. O **versionamento de contrato** (`v1`, string publicada não se
sobrescreve) é mantido — um PDF **já impresso e assinado** em pt-BR é artefato de
papel; a regeneração digital apenas honra o idioma corrente.

**Prós/contras.** ✔ tecnicamente barato (não há tabela, assinatura nem hash no
código — só blocos em branco e um `document_id` de timestamp não-único); ✔ trocar de
idioma re-emite no idioma novo; ✖ restrição de **processo**: mudar a grafia de uma
`report.v1.*` publicada é mudança material → cria chave nova, não sobrescreve (sweep
8.2 vigia). `document_id`/timezone estão acoplados a `America/Sao_Paulo` — decidir se o
timezone segue o locale (proposta: **não** — o horário é rastreabilidade do registro,
independe do idioma).

**Onde mora.** No `CommissioningReportService#t` (locale do leitor) e no sweep de
literal do relatório, estendido para EN.

## D-I6 — Persistência: por dispositivo (base) + por conta (durável). ÚNICA migração.

**Decisão.** Base **por dispositivo** em `localStorage['rt-lang']` (default `pt-BR`,
mesma semântica "só neste dispositivo" do tema, mesma degradação sob storage
bloqueado). Quando logado, **sincroniza** com a coluna **aditiva `users.locale`**
(`text`, default `'pt-BR'`, `CHECK locale IN ('pt-BR','en')`), fonte durável que segue
a pessoa entre dispositivos e alimenta o congelamento server-side (D-I5a/b).

**Por quê os dois.** Só dispositivo não deixaria o servidor saber o idioma de quem lê a
notificação/auditoria; só conta não cobriria o **pré-login** (a tela de entrada) nem o
storage bloqueado. Base local + espelho na conta cobre os dois.

**Alternativa descartada.** Só `Accept-Language` do navegador. Rejeitada: frágil (muda
com o SO/navegador), não é escolha explícita do usuário; serve no máximo de **default
de primeira visita** — mas o dono pediu **default pt-BR fixo**, então `Accept-Language`
fica como sinal secundário, não como fonte.

**Onde mora.** Migração aditiva `users.locale` (`🟡`, reversível por `DROP`) + `CHECK`
do par de valores; `PATCH /users/me` (ou similar) que **só** deixa a pessoa mudar **o
próprio** locale (política, não UI). RLS/tenancy **não** mudam.

## D-I7 — Seletor de idioma: controle acessível com bandeira não-emoji (impeccable)

**Decisão.** Um **controle** (não badge — regra dura "badge é rótulo, seletor é
controle, nunca se parecem"), com **bandeira BR/GB como asset/ícone SVG**, **sem
emoji**. Interação = `PortalMenu` com **dois alvos explícitos** ("Português (Brasil)" /
"English (UK)"), ≥40px cada — **não** um toggle que cicla (ambíguo sob luva; mesmo
raciocínio do controle seguir/silenciar, D-P9 de `notification-preferences`).
`aria-label` do gatilho = "Idioma / Language"; a **bandeira é `aria-hidden`** e o **nome
acessível é o idioma**; há **rótulo de texto visível** (ex.: "PT"/"EN" no gatilho, nome
por extenso no menu) para legibilidade de galpão (Princípio 1). Contraste AA nos dois
temas (guarda de CI).

**Por quê não emoji.** `no-emoji.test.ts` reprova 🇧🇷/🇬🇧 (regional-indicator =
`Emoji_Presentation`). Bandeiras têm cor própria (não seguem `currentColor` como os
ícones de traço), então entram como **SVG com fills próprios** (sprite dedicado de
bandeiras ou asset inline), documentado como exceção controlada ao sistema de ícones
monocromático — a bandeira é decorativa; o significado está no texto.

**Localização.** (1) **Menu da conta** (rodapé da sidebar, `AppShell` array de itens,
ao lado de "Alternar tema") — sempre acessível; (2) painel **Aparência** das
Configurações; (3) **tela de entrada** (`AuthPage`) — pré-login, para o primeiro EN ler
o login. Cuidado com a **regra G** (nome de item do shell não colide com botão de outra
tela): o rótulo do item de idioma é único.

**Alternativa descartada.** Só um toggle de bandeira no topbar que alterna PT⇄EN ao
toque. Rejeitada: cicla sem revelar o estado-alvo, ruim sob luva; e um único glifo sem
texto fere a legibilidade e a acessibilidade.

**Onde mora.** No `useLanguageStore` (estado), no primitivo do seletor
(`components/…`), no array de itens do `AppShell`, no `AppearancePanel` e no `AuthPage`;
a11y e contraste travados pelos sweeps de `quality-and-accessibility` e `no-emoji`.

## D-I8 — Ordem de execução e o portão do glossário

**Decisão.** G1–G3 (fundação, extração de inline, tradução EN) e G4 (backend) **não
traduzem uma linha antes de o dono assinar o `GLOSSARIO.md`**. A tradução de dado de
domínio (status/aplicações/catálogo/relatório) depende das linhas ⚠️ resolvidas. G5
(coluna `users.locale`) é a única com migração e pode vir por último (o congelamento
server-side depende dela; até lá o servidor usa default pt-BR).

**Onde mora.** No método da casa (tasks.md com risco de banco marcado; `EXECUCAO.md`
registrando a decisão por grupo) e no próprio `GLOSSARIO.md` como artefato de revisão.
