## Why

O dono pediu o app em **inglês além do português**, com um **seletor de idioma
(PT/EN) mostrado como bandeira** (Brasil / Reino Unido), e uma ressalva forte:
**muito cuidado com os termos técnicos de robótica/comissionamento** — traduzir com
rigor e **perguntar quando houver dúvida**. Hoje o produto é pt-BR de ponta a ponta.

Isto **não** é uma tradução do legado (o legado PWA/Firestore era pt-BR fixo e não
tinha i18n — não-objetivo de lá). É uma capacidade **nova**, pedida pelo dono. Cobre
transversalmente a ESPECIFICACAO — toda superfície de texto (§2.x UI, §2.7
notificações, §2.8 auditoria, §8.2 Protocolo de Comissionamento) — sem alterar
regra de negócio; muda **em que idioma** a mesma regra é lida.

### O que a auditoria encontrou (estado real — reconciliado em G0)

- **Frontend:** não há framework de i18n nem mecanismo de locale. `lib/i18n/*` são
  **11 módulos pt-BR planos** (~337 chaves; 41 são funções que embutem gramática pt —
  artigos `do`/`pelo`/`pela`, plural `n===1?`), disciplina de fonte-única por
  capacidade — **não** uma camada de tradução. `<html lang="pt-BR">` é fixo.
  **~82% dos arquivos com texto de UI NÃO usam `lib/i18n`** (25/138 importam): o
  shell, a tela de entrada (`AuthPage`), a Ajuda (`AjudaPage`, 476 linhas), Visão
  Geral/hierarquia e os gráficos carregam **literais pt-BR inline**. Seis pontos de
  formatação (`Intl`/`toLocaleString`/`localeCompare`) fixam `'pt-BR'`. **Sem lib de
  data, sem RTL** (EN é LTR — não precisa).
- **Backend:** a infra rails-i18n já **declara** `available_locales = [pt-BR, en]` e
  fallback `pt-BR → en`, mas **não existe um único arquivo `en.*.yml`** e
  `raise_on_missing_translations = true` em dev/test — ou seja, qualquer caminho sob
  `:en` **quebra hoje**. Não há tratamento de `Accept-Language`, não há coluna
  `locale` no usuário, nada troca o locale por requisição.
- **Mensagens CONGELADAS no servidor (o ponto difícil):**
  - **Notificações** — `notifications.msg` + `ts_local` são renderizados em pt-BR e
    **congelados na linha por destinatário no INSERT**; um trigger bloqueia UPDATE de
    `msg`. Transientes (≤500 chars, invariante única = `read:false`).
  - **Auditoria** — `audit_logs.msg` + `ts_local` **congelados no INSERT** e
    **imutáveis por design**: `REVOKE UPDATE,DELETE` + trigger `RAISE EXCEPTION` +
    RLS + guarda de boot + snapshot byte-a-byte no CI + strings versionadas `vN`.
    **É o ponto de reversão não-trivial.**
  - **Protocolo de Comissionamento** — `report.v1.*` é **resolvido na LEITURA** (não
    gravado; sem assinatura/hash no código, só blocos de assinatura em branco e um
    `document_id` de timestamp não-único), mas tratado como **contrato versionado**
    porque PDFs já impressos foram assinados com a grafia v1.

Detalhe completo, com arquivos e linhas, em `EXECUCAO.md`.

### O portão obrigatório: o GLOSSÁRIO

Antes de qualquer tradução em massa, o dono revisa `GLOSSARIO.md` (pt-BR → EN
proposto → nota de dúvida), cobrindo domínio + as **6 aplicações de robô**, as **9
categorias** e as **31 tarefas-base**. Estas três listas estão **gravadas em pt-BR no
banco** (enum `task_status`, CHECK de `robots.application`, linhas de `task_templates`
casadas por `desc` na importação legada): o EN é **camada de exibição**, nunca rename
de dado — traduzir o dado quebraria CHECK, enum e importação.

## What Changes

> **Esta change é de PLANEJAMENTO (G0).** Materializa o mapa, o glossário e os grupos.
> **Nada é traduzido nem aplicado aqui.** Os grupos G1+ só executam **após o dono
> confirmar o glossário**.

- **Fundação de i18n no frontend (própria, leve — sem dep pesada, respeitando
  `no-heavy-deps.test.ts`):** um `useLanguageStore` (Zustand + `persist`, espelho
  exato do `themeStore` → `localStorage['rt-lang']`, default `pt-BR`) e um aplicador
  `useLanguage()` que fixa `document.documentElement.lang`. Os 11 módulos `lib/i18n`
  ganham um **eixo de idioma**; as 4 varreduras D14 (`invitations`/`feedback`/
  `progress`/`report`) e o **parser da regra G** do `convention-sweep` (que hoje
  assume literal plano de uma linha) são **atualizados para a nova forma no mesmo
  grupo** — senão o CI trava. Plural/interpolação por `Intl.PluralRules` + ramo EN;
  os 6 pontos de formatação passam a receber o locale.
- **Seletor de idioma (impeccable):** controle **de verdade** (não badge — regra dura
  da casa), com **bandeira BR/GB como ícone/asset SVG, NUNCA emoji** (o
  `no-emoji.test.ts` reprovaria 🇧🇷/🇬🇧). `PortalMenu` com **dois alvos explícitos**
  (Português / English), como o controle seguir/silenciar — **não** um toggle que
  cicla (ambíguo sob luva). `aria-label` "Idioma / Language"; cada opção nomeada por
  extenso; alvo de toque **≥40px**; a bandeira é `aria-hidden`, o **nome acessível é o
  idioma**. Mora no **menu da conta** (rodapé da sidebar, ao lado de "Alternar tema"),
  no painel **Aparência** das Configurações, e na **tela de entrada** (`AuthPage`) —
  para o primeiro EN conseguir ler o login.
- **Extração dos literais inline → `lib/i18n`** (o shell, `AuthPage`, `AjudaPage`,
  Visão Geral/hierarquia, gráficos), **ainda em pt-BR**, para que o EN seja uma
  camada por cima e não uma reescrita de componente.
- **Tradução EN** de todas as strings do frontend, **só depois do glossário aprovado**.
- **Backend `en.*.yml`** (espelho dos 10 `pt-BR.*.yml`) + **resolução de locale por
  requisição** (`Accept-Language` e, quando logado, a preferência da conta) via
  `I18n.with_locale`. O Protocolo passa a resolver `report.v1.*` no **locale do
  leitor** na geração (mantendo o versionamento de contrato do documento assinado).
- **Persistência da preferência na conta** — coluna **aditiva `users.locale`**
  (`🟡 reversível por `DROP``), sincronizada do cliente. Habilita: seguir a pessoa
  entre dispositivos, e **congelar a notificação no locale do DESTINATÁRIO** e a
  **auditoria no locale do ATOR** no momento do INSERT. **É a ÚNICA migração de banco.**
- **Mensagens congeladas — estratégia "congela-para-frente, não reescreve-para-trás"
  (híbrida):** manter o congelamento de notificação/auditoria e o contrato do
  Protocolo; suportar EN resolvendo **no momento da escrita/geração** no locale certo
  (destinatário / ator / leitor). **Linhas históricas permanecem no idioma em que
  nasceram** — correto para uma trilha de auditoria e para um PDF já assinado.
  Nenhuma tabela congelada é tocada; **nenhuma migração destrutiva; nenhum ponto
  🔴 de reversão não-trivial.**

### Não-objetivos

- **Re-localização retroativa** de linhas já congeladas (auditoria/notificação) via
  guardar `chave+args` e renderizar na leitura. É o `🔴` **não-trivial**: exige
  migração na tabela **imutável** de auditoria (contra `REVOKE`+trigger+snapshot),
  backfill **com perda** (o `%{comment}` truncado a 500 é irreversível), e afrouxar o
  trigger de notificações. **Fora de escopo**; documentado como alternativa descartada
  em `design.md`.
- **Reescrever a grafia legada** das tarefas-base no banco (a importação casa por
  `desc`). EN é exibição.
- **Um terceiro idioma / RTL / seleção automática por geolocalização.** Só PT e EN,
  default pt-BR.
- **Traduzir a landing `components/campfire/`** neste porte (lazy, fora dos sweeps).
- **Mudar o enum de status, o CHECK de aplicação ou o esquema de `task_templates`.**

## Capabilities

### New Capabilities

- `internationalization`: o eixo de idioma dos módulos de texto, o seletor PT/EN por
  bandeira (não-emoji, acessível), a persistência por dispositivo (`rt-lang`) e por
  conta (`users.locale`), a resolução de locale por requisição no backend, e a
  estratégia de mensagens congeladas (congela-para-frente).

### Modified Capabilities

- `workspace-settings`: o painel **Aparência** ganha o controle de idioma.
- `in-app-notifications`: `MessageBuilder`/`CreateService` resolvem a `msg` no locale
  do **destinatário** (não mais `LOCALE` fixo pt-BR) no INSERT.
- `audit-log`: `RecordService` congela a `msg` no locale do **ator**; strings `en`
  publicadas como versões, sem tocar linhas históricas nem a imutabilidade.
- `commissioning-report`: `CommissioningReportService#t` resolve `report.v1.*` no
  locale do **leitor** na geração.

### Impact

- **Depende de** `workspace-tenancy` (COMPLETO): `users`/`people`, RLS — a coluna
  `users.locale` é aditiva e não muda tenancy.
- **Toca** `app-shell-navigation`, `identity-and-auth` (AuthPage), `hierarchy-screens`,
  `quality-and-accessibility` (contraste/alvo do seletor, `no-emoji`).
- **Reversão:** todo o frontend e os `en.*.yml` revertem por remoção de arquivo
  (`🟢`). A **única** migração é `users.locale`, **aditiva e reversível por `DROP`**
  (`🟡`). **Não há grupo `🔴`** — a estratégia foi desenhada para não tocar as tabelas
  imutáveis. O caminho `🔴` (re-localização retroativa) é **não-objetivo explícito**.
