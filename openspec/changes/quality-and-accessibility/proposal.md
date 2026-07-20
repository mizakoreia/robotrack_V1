## Why

Quatro afirmações do produto não têm hoje **nenhum mecanismo que as prove**, e as
quatro estão escritas como fato nas fontes de verdade:

1. **`DESIGN.md §Accessibility`** afirma *"atingido e medido nos dois temas"* e
   **`PRODUCT.md §Accessibility & Inclusion`** fixa o alvo (contraste de corpo
   ≥ 4.5:1, foco visível, teclado, alvo de toque grande, `prefers-reduced-motion`).
   O WBS anterior traduziu isso em **quatro tarefas** — contraste, teclado,
   movimento e alvo de toque — e **zero** cobertura de leitor de tela: nenhum ARIA,
   nenhum `aria-live` para o indicador de gravação (`DESIGN.md §Components`,
   *Save indicator*) nem para o centro de notificações (§2.7), nenhuma gestão de
   foco para o pulso de 100% (§3.5). Um requisito de a11y sem número medido não é
   verificável; "atende AA" não é aceite.
2. **Não existe um único teste ponta a ponta.** Os dois maiores riscos do porte —
   vazamento entre tenants (§4.1 inv. 1/4) e sincronização offline (§4.2, §4.3) —
   são exatamente os que **nenhum teste unitário pega**: ambos exigem duas sessões
   reais, um service worker real, um WebSocket real e uma transição de rede real.
3. **Não há orçamento de performance nenhum.** N+1 aparecia no plano anterior como
   cláusula de passagem em duas tarefas, sem orçamento de query, sem dataset de
   carga, sem teste de dashboard em escala — enquanto o `DESIGN.md §Luz ambiente`
   media a luz com **24 cards em tela a 1x de CPU**, número que ninguém pode
   reproduzir porque não há dataset que produza 24 cards.
4. **D14 não tinha dono.** O produto é inteiramente pt-BR e tem *format strings* em
   três caminhos onde a string é **dado persistido, não decoração**: mensagem de
   notificação (§2.7), mensagem de log de auditoria (§2.8, append-only com
   `REVOKE UPDATE, DELETE` por D12) e o relatório A4 que o cliente assina (§3.8).
   Nenhuma tarefa do plano anterior era dona delas.

Esta capacidade é a **Onda 10**: depende de todas as telas e é o portão que decide
se elas podem ser entregues. Ela é dona de **D14**.

## What Changes

**E2E — Playwright, cinco fluxos que nenhum teste unitário cobre.**
Suíte em `e2e/`, rodando contra a stack real (Rails + Vite build + Postgres +
Redis), com dataset semeado determinístico. Os cinco fluxos:
convite ponta a ponta entre **dois usuários** (dois `BrowserContext` no mesmo
teste); registrar avanço **offline** e sincronizar ao voltar; **troca de workspace**
provando ausência de vazamento no DOM e na rede; **revogação de acesso ao vivo**
via `WorkspaceChannel`; e o **relatório A4** gerado de um dataset conhecido, com
os números conferidos contra valores literais.

**Acessibilidade — WCAG AA medido, com valores concretos, nos dois temas.**
- Tabela de contraste **calculada, não estimada**, sobre os tokens reais do
  `DESIGN.md` com composição alfa das camadas (`--bg-panel` é `rgba(...)` sobre
  `--bg-main`; a pílula tinge 15% sobre o painel). O cálculo já expôs **três
  reprovações reais** nos tokens atuais, que esta proposta corrige:
  - **BREAKING (token)** `--accent-solid #3b82f6` com texto branco = **3.68:1** →
    `#2563eb` = **5.17:1**;
  - **BREAKING (token)** `--danger-solid #ef4444` com texto branco = **3.76:1** →
    `#dc2626` (escuro) = **4.83:1** / `#b91c1c` (claro) = **6.47:1**;
  - **BREAKING (token)** tinta de `N/A` `#a1a1aa` sobre a própria pílula no tema
    claro = **2.25:1** → `--na-ink #52525b` = **6.09:1**.
- Camada de leitor de tela que **não existia**: `role="progressbar"` nas barras,
  `role="img"` + rótulo nos anéis, `aria-live="polite"` no indicador de gravação e
  no centro de notificações, `aria-live="assertive"` só para erro de persistência,
  gestão de foco no modal e no pulso de 100%.
- Teclado: `:focus-visible` com contorno medido ≥ 3:1 contra as duas superfícies,
  menus por setas, **Esc devolvendo o foco ao gatilho**, foco preso no modal.
- `prefers-reduced-motion`, e alvo de toque **≥ 32px** — requisito de **ambiente**
  (luva, galpão), não de conformidade; WCAG 2.2 AA exige 24px e nós excedemos.
- Varredura `axe-core` em 8 telas × 2 temas no CI, **zero violação `serious` ou
  `critical`**.

**Performance — orçamento com número, dataset e teste que reprova o CI.**
- **Dataset de carga semeado** (`rt:seed:load`): 2 workspaces; o de carga com
  4 projetos, 24 células, 240 robôs, 7.440 tarefas, 22.320 avanços, 8.000 logs de
  auditoria — e o segundo workspace como **isca de vazamento**.
- **Orçamento de query por tela**, constante e independente do tamanho do dataset
  (a Visão Geral com 4 projetos e com 400 projetos executa o mesmo nº de queries).
- **Orçamento de bundle** por chunk, medido no build de produção em gzip.
- Teste de INP com **24 cards em tela**, reproduzindo o número do `DESIGN.md`.

**D14 — strings pt-BR centralizadas e versionadas.**
Backend em `config/locales/pt-BR.{notifications,audit,report,errors}.yml`;
frontend num módulo único `frontend/src/lib/i18n/pt-BR.ts` com chaves tipadas.
Notificação e log de auditoria persistem **chave + argumentos + snapshot
renderizado**, com `format_version`: mudar a string **não reescreve o passado**.
Sweep de teste que reprova literal solto nos três caminhos.

**Dívida de teste do template** que `seal-template-baseline` sana e nós
**estendemos**: `spec/factories` (o baseline cria as do template; nós criamos as do
domínio RoboTrack e o *builder* de cenário), helper de auth de request
compartilhado (o baseline entrega `sign_in_as`; nós entregamos o helper
multi-tenant `as_member_of`), e a suíte do frontend que importa páginas
inexistentes (o baseline remove os órfãos; nós adicionamos o guarda que impede a
reintrodução).

### Não-objetivos

- **Não** implementamos nenhuma tela, componente, token ou endpoint. Corrigimos
  três valores de token e definimos contratos de ARIA — a implementação dos
  componentes é de `design-system`, `hierarchy-screens`, `robot-task-table`,
  `app-shell-navigation` e `commissioning-report`.
- **Não** escrevemos os testes unitários/de request de cada capacidade. Cada dona
  escreve os seus. Nós entregamos a infraestrutura compartilhada (dataset,
  helpers, matchers de orçamento) e **só** os testes que atravessam capacidades.
- **Não** entregamos i18n multi-idioma. O produto é pt-BR; D14 é sobre
  **centralização e versionamento de format string**, não sobre tradução. Não há
  seletor de idioma, não há fallback de locale, `I18n.available_locales` fica com
  um item só.
- **Não** entregamos o pipeline de CI, os *runners*, o cache de dependência nem o
  ambiente efêmero de Postgres/Redis onde o E2E roda — é de
  `delivery-and-observability`. Nós declaramos o que precisamos dele.
- **Não** entregamos observabilidade de performance em **produção** (RUM, APM,
  tracing). Nosso orçamento é medido em CI, em dataset fixo. Produção é de
  `delivery-and-observability`.
- **Não** perseguimos WCAG AAA, nem testes com leitores de tela reais
  (NVDA/VoiceOver) automatizados — testamos a **árvore de acessibilidade**, que é
  o que é determinístico. Uma passagem manual com VoiceOver fica como tarefa
  humana única, não como gate de CI.
- **Não** cobrimos com E2E o que teste de request já cobre. Cinco fluxos, não
  cinquenta: a suíte E2E que demora 20 minutos é a suíte E2E que é desligada.

## Capabilities

### New Capabilities

- `end-to-end-testing`: harness Playwright, dataset determinístico, fixtures
  multi-usuário e multi-contexto, e os cinco fluxos ponta a ponta.
- `accessibility-compliance`: tabela de contraste medida nos dois temas com
  correção dos três tokens reprovados, contrato ARIA/`aria-live`/foco, teclado,
  movimento reduzido, alvo de toque, e o gate `axe-core` no CI.
- `performance-budgets`: dataset de carga semeado, orçamento de query por tela,
  orçamento de bundle por chunk, orçamento de INP com 24 cards, e os testes que
  reprovam o CI quando qualquer um estoura.
- `localized-string-management`: D14 — catálogo pt-BR de backend e frontend,
  format strings versionadas nos três caminhos persistidos, e o sweep que barra
  literal solto.

### Modified Capabilities

(nenhuma — `openspec/specs/` está vazio)

### Impact

- **Depende de** (Onda 10 — todas as telas): `seal-template-baseline` (suíte verde,
  factories base, helper de auth); `design-system` (os tokens que medimos e os três
  que corrigimos); `workspace-tenancy` (D2/RLS — o dataset semeia dois workspaces e
  o E2E de vazamento depende do contexto de tenant); `authorization-policies`
  (D3 — o E2E de revogação exercita a policy ao vivo); `workspace-invitations`
  (§3.10 — fluxo 1); `realtime-collaboration` (D6/`WorkspaceChannel` — fluxo 4);
  `offline-pwa` (D7 — fluxo 2, service worker e fila IndexedDB);
  `commissioning-report` (§3.8 — fluxo 5); `progress-rollup` (D15 — o dataset de
  carga é o mesmo em que as duas métricas divergem); `in-app-notifications` (§2.7),
  `audit-log` (§2.8) e `commissioning-report` (§3.8) como consumidores de D14;
  `delivery-and-observability` (job de CI, serviços efêmeros, artefato de trace,
  variáveis `E2E_BASE_URL`/`PLAYWRIGHT_WORKERS`).
- **É dependência de**: nenhuma capacidade de produto — mas é **gate de release**.
  Os orçamentos e o gate `axe-core` reprovam o merge de qualquer capacidade que os
  estoure, inclusive as que já estiverem prontas.
- **BREAKING**: três valores de token de cor mudam (`--accent-solid`,
  `--danger-solid`, tinta de `N/A` no tema claro). São mudanças de aparência sobre
  as quais `design-system` é a implementadora; a razão de contraste medida é a
  justificativa e o valor atual é a reprovação. Nenhuma quebra de API ou de dados.
- **Buraco de entrega declarado**: o E2E precisa de Postgres e Redis efêmeros no
  CI, do build de produção do frontend servido (não do `vite dev`, que não registra
  o service worker do mesmo jeito), e de retenção de artefato para os traces de
  falha. Isso é responsabilidade de `delivery-and-observability` e está citado nas
  tarefas.
