# Design — workspace-settings

## Context

Onda 8. Depende de `task-catalog` (modelo de `task_templates`), `workspace-invitations`
(memberships e revogação de convite) e `audit-log` (tabela imutável e caminho de escrita).
Escopo: §3.9 e §3.11 da ESPECIFICACAO.md, mais o modal de §2.8 na parte de tela.

Esta capacidade é dona de **D12** e concentra a única operação em massa destrutiva do
produto. Duas heranças do plano anterior precisam ser resolvidas aqui, não adiadas:

1. `REVOKE UPDATE, DELETE ON audit_logs` **e** "reset apaga o workspace" coexistiam. A
   contradição não é de estilo: `DELETE FROM workspaces WHERE id = $1` cascateia para
   `audit_logs`, o `DELETE` bate no privilégio revogado, `PG::InsufficientPrivilege` sobe
   e a transação atômica aborta inteira. O reset **nunca poderia rodar**.
2. §3.11 nomeia o arquivo de export literalmente (`RoboTrack_Database.json`), e o plano
   anterior não decidiu se isso é um contrato de formato.

## Goals / Non-Goals

**Goals**
- Painel de Equipe operando sobre `Person` (D10), sem o sentinela abolido por D11.
- Tela do catálogo com a regra de `Misto / Geral` limpando o filtro.
- Export com formato **decidido e justificado**, testável por round-trip contra
  `legacy-data-migration`.
- Reset atômico, owner-only, com backup obrigatório, rollback definido e **destino
  declarado para cada entidade do workspace** — sem "e o resto".
- Auditoria sobrevive ao reset e registra que ele ocorreu.

**Non-Goals**
- Restauração de backup pela UI (ver D-RESTORE).
- Retenção de longo prazo dos arquivos de backup (`delivery-and-observability`).
- Definição do modelo de `task_templates` e de `audit_logs`.
- Backup automático agendado.

## Decisions

### D-SENTINEL — a regra "`Não Atribuído` não é removível" é abolida, não portada

§3.9 dizia que o chip `"Não Atribuído"` não podia ser removido. Essa regra **não tem
razão de ser própria**: ela protegia um sentinela do modelo legado (`responsibles` do
workspace sempre continha a string; `resp` recebia `assignees[0] || "Não Atribuído"`,
§1.4 item 1). Por **D11** o sentinela deixa de existir: ausência de responsável é
`task_assignees` vazio.

Consequência declarada: **todo chip da Equipe é removível.** `"Não atribuído"` passa a
ser um rótulo de UI renderizado quando o conjunto de responsáveis está vazio, nunca uma
linha em `people`.

Onde a invariante mora: índice único parcial
`CREATE UNIQUE INDEX ... ON people (workspace_id, lower(name)) WHERE archived_at IS NULL`
impede duplicata de chip ativo, e uma `CHECK (btrim(name) <> '')` impede chip vazio.
Impedir a *criação* de uma pessoa literalmente chamada "Não Atribuído" é obrigação do
importador (`legacy-data-migration` filtra o valor, D11) — aqui não se bloqueia por
string, porque bloquear um nome próprio arbitrário na UI seria arbitrário.

*Alternativa descartada:* portar a regra e marcar uma `Person` como
`system: true`. Recria o sentinela sob outro nome, reintroduz o caso especial em todo
seletor de responsável e contradiz D11 diretamente.

### D-PERSON-DEL — remover chip é arquivar, nunca `DELETE`

`task_advances` é append-only (D8) e carrega `author_name_snapshot`; `audit_logs` carrega
`by_person_id`. Um `DELETE` físico ou quebra FK ou apaga história.

Remover um chip:
1. `people.archived_at = now()` (a pessoa some dos seletores e dos chips ativos);
2. `DELETE FROM task_assignees WHERE person_id = $1` — atribuições **abertas** caem, para
   que a pessoa não continue aparecendo como responsável em tarefas vivas;
3. `task_advances` e `audit_logs` **intocados** — a história diz quem fez, e continua
   dizendo.

Uma `Person` com `user_id NOT NULL` **ou** com membership ativa **não pode ser
arquivada por esta tela** (`409`): remover alguém que tem conta é remoção de membro, e
isso é de `workspace-invitations`, com suas próprias consequências (revogação em tempo
real, D6). Onde a invariante mora: policy + `CHECK` não serve aqui (é relacional), então
constraint via trigger `BEFORE UPDATE OF archived_at ON people` que levanta exceção se
existir membership ativa — assim `rails console` também bate na parede.

### D-EXP — `RoboTrack_Database.json` é um **superset aditivo do formato legado**, arquivo único

O nome literal em §3.11 é um contrato. Três opções foram consideradas:

- **(a) Formato legado puro** (documento aninhado no formato Firestore: workspace →
  `projects[] → cells[] → robots[] → tasks[]`, com `resp`, `apps`, `obs`). *Descartada:*
  é **lossy**. Não expressa `person_id` (D10), `recorded_at` vs. `created_at` (D8),
  `task_advances` estruturado nem `audit_logs`. Um backup lossy é inútil como pré-requisito
  do reset — que é justamente o uso mais crítico do export.
- **(b) Formato nativo novo, sem parentesco com o legado.** *Descartada:* joga fora a
  compatibilidade que o nome do arquivo promete, e obrigaria `legacy-data-migration` a
  manter dois parsers (o do legado, para arquivos de usuários, e o nosso) sem ganho.
- **(c) Dois arquivos / dois formatos.** *Descartada:* dobra a superfície de teste,
  garante drift entre eles, e §3.11 nomeia **um** arquivo.

**Escolhida: um arquivo, formato legado como esqueleto, campos nativos aditivos.** O
JSON mantém o aninhamento e **todas** as chaves do legado com a mesma semântica, e
acrescenta:

- envelope de topo `"_rt": { "schemaVersion": 2, "exportedAt": <ISO8601>,
  "workspaceId": <uuid>, "counts": {...}, "checksum": <sha256 do payload sem `_rt`> }`;
- `assigneeIds: [uuid]` em cada tarefa, **ao lado** de `assignees: [nome]` (o legado lê
  nomes; o nosso importador prefere ids);
- `advances: [...]` com `recordedAt` e `createdAt` explícitos (D8), ao lado do `history`
  legado;
- coleções de topo `people`, `memberships`, `invitations`, `notifications`, `auditLogs`,
  `taskTemplates`.

Isso funciona porque (i) ids do legado eram strings opacas, e uuid é uma string opaca
válida — nenhum leitor legado quebra; (ii) leitores legados ignoram chaves desconhecidas,
que era como o cliente Firestore lia. **O formato é lossless na direção nativa e legível
na direção legada.** O contrato é fixado por um fixture versionado
(`spec/fixtures/backup/roboTrack_database_v2.json`) compartilhado com
`legacy-data-migration`, e por um teste de round-trip export → import → export que exige
**igualdade byte a byte** do payload (com `_rt.exportedAt` e `checksum` excluídos da
comparação). Chaves ordenadas alfabeticamente na serialização para que a igualdade byte a
byte seja alcançável.

`schemaVersion: 2` porque `1` é o legado implícito; o importador decide o parser por essa
chave, e sua ausência significa `1`.

### D-EXP-ROLE — export é `owner`-only, apesar de `view` poder ler tudo

§4.1 dá leitura de todo o workspace aos três papéis, então a leitura literal permitiria
`view` exportar. Mas o arquivo carrega `memberships` e `invitations` com **e-mails** —
dado pessoal que a UI nunca expõe a `view` (o painel de equipe é `owner`, §3.10) — e um
arquivo baixado sai do alcance de qualquer revogação futura. Export é, na prática,
exfiltração autorizada.

**Decisão:** `POST /workspace/backups` é `owner`. `edit` e `view` recebem `403`.
*Alternativa descartada:* export com redação de e-mails para não-donos — produz um
arquivo que **não** serve de backup, com o mesmo nome de um que serve. Dois artefatos
indistinguíveis com garantias diferentes é pior que uma negação.

### D-RESET — destino declarado de **cada** entidade

Uma transação (`SERIALIZABLE`), na ordem abaixo. `workspace_id` fixo pelo RLS (D2).

| Entidade | Destino | Porquê |
|---|---|---|
| `projects`, `cells`, `robots` | **DELETE** | §3.11 "apaga todos os projetos" |
| `tasks`, `task_assignees` | **DELETE** (cascade dos robôs) | pendem de robô |
| `task_advances` | **DELETE** (cascade das tarefas) | append-only ≠ indestrutível; a trilha é *de uma tarefa* e a tarefa deixou de existir. Distinto de `audit_logs`, que é do workspace |
| `notifications` | **DELETE** | todo `ctx` aponta para robô/tarefa apagados; manter produz navegação para 404 |
| `task_templates` | **DELETE + re-seed dos 31 padrões (§1.3)** | "reset de **fábrica**" é voltar ao estado de fábrica, não a vazio; o seed é de `task-catalog` e é invocado aqui |
| `people` | **PRESERVADAS**, inclusive as arquivadas | a `Person` do dono é exigida por D10 e é a autora da entrada de auditoria do reset; apagar pessoas quebraria `audit_logs.by_person_id` (FK) e violaria D12 por via indireta |
| `memberships` | **PRESERVADAS** | §4.1 trata "remover membro" como ação distinta do reset; remover acesso sem aviso é surpresa e é caminho de `workspace-invitations` |
| `invitations` pendentes | **REVOGADAS** (`revoked_at = now()`), não deletadas | são promessas de acesso a um workspace cujo conteúdo deixou de existir; uso único e expiração (§4.1 inv. 6) não bastam. Revogar preserva a trilha do convite |
| `workspaces` (a linha) | **PRESERVADA**; `name` intocado | apagá-la cascateia para `audit_logs` → `PG::InsufficientPrivilege` → aborta tudo. É exatamente o bug de D12. E o dono ficaria sem tenant até um novo bootstrap |
| `audit_logs` | **PRESERVADOS** + **1 entrada nova** | D12, §4.1 inv. 3 |
| preferência de tema | **INTOCADA** | é local do cliente (§4.2), não é estado do workspace |
| `workspace_backups` | **PRESERVADOS** | apagar o registro do backup logo após usá-lo como pré-condição destruiria a única prova de que houve backup |

**BREAKING vs. §3.11:** o texto diz "apaga todos os projetos **e o workspace**". Aqui o
registro do workspace sobrevive; o que é apagado é o **conteúdo**. Justificativa acima.
Excluir o workspace de verdade (encerrar a conta) não é escopo desta capacidade e não
tem tela em nenhuma seção da spec.

A entrada de auditoria é gravada **na mesma transação**, depois dos deletes, com formato
versionado (D14):
`"Reset de fábrica executado por <nome>. Removidos: <n> projetos, <n> células, <n> robôs, <n> tarefas, <n> avanços, <n> notificações. <n> convites pendentes revogados. Catálogo restaurado ao padrão. Backup <backup_id>."`

### D-RESET-GATE — confirmação por frase **e** backup recente, ambos verificados no servidor

Dois portões independentes:

1. `confirmation_phrase` deve ser **exatamente igual** a `workspace.name` após `strip`
   das bordas, comparação **sensível a maiúsculas**. Comparado no servidor; a validação
   do cliente é conveniência (§4.1 inv. 1). Divergência → `422`, nada executa, **nenhuma**
   entrada de auditoria (tentativa falha não é evento de domínio; se virasse log, um
   membro `edit` poluiria auditoria imutável batendo no endpoint).
2. `backup_id` deve referenciar um `workspace_backups` do **mesmo** workspace,
   `status = completed`, com `created_at >= now() - interval '15 minutes'`. Ausente,
   alheio ou velho → `422` com código distinto. Isto torna mecânica a regra do briefing
   "tarefa destrutiva exige backup imediatamente antes": não dá para pular pela API.

*Alternativa descartada:* confirmação por digitar `RESET` ou um checkbox. Uma frase
constante é muscle memory e vaza entre workspaces; o nome do workspace obriga a olhar
para **qual** workspace está prestes a ser esvaziado.

### D-RESET-ROLLBACK — rollback é a própria transação; recuperação é o arquivo

Falha em qualquer passo → `ROLLBACK`, `500`/`409`, estado idêntico ao anterior,
**nenhuma** entrada de auditoria (ela é escrita dentro da transação e morre junto). O
`WorkspaceBackup` fica registrado — houve backup, não houve reset.

Recuperação após um reset **bem-sucedido e arrependido** é fora de banda: o arquivo
`RoboTrack_Database.json` é reimportado pelo importador idempotente de
`legacy-data-migration`. Como os ids são uuid gerados no cliente (D1) e preservados no
export, a reimportação **restaura os mesmos ids** — as entradas de auditoria anteriores,
que referenciam robôs e tarefas por id no texto, voltam a fazer sentido.

### D-RESTORE — sem restauração pela UI na v1

*Alternativa descartada:* botão "Restaurar backup" ao lado de "Exportar". Restauração é
uma escrita em massa com conflito de id contra o estado atual e precisa de política de
merge (substituir? mesclar? falhar?), que não está especificada em lugar nenhum e não é
decidível aqui. Um caminho de restauração pela metade é mais perigoso que nenhum.
Registrado em Perguntas em aberto.

### D-CATALOG-FILTER — `Misto / Geral` é ausência de filtro, não um valor

Na tela, o editor de filtro de aplicação é multi-seleção sobre o enum de §1.2. Marcar
`Misto / Geral` **desmarca todas as outras e envia `app_filters: []`**. `[]` significa
"vale para todas" (§3.9). A **semântica** de `app_filters` (inclusive aceitar `apps`
legado) é de `task-catalog`; a tela apenas nunca envia `["Misto / Geral"]`.

Onde a invariante mora: `CHECK (NOT (app_filters @> ARRAY['Misto / Geral']))` na tabela
de `task-catalog` — citada aqui como dependência, não criada aqui. A tela não pode ser a
única guardiã, porque a API é pública.

### D-THEME — Zustand `persist`, escuro por padrão, ignora o SO

Reusa o `themeStore` já existente no template (chave `theme-storage`), classe `dark` no
`<html>` (Tailwind `darkMode: ['class']`). **Não** lê `prefers-color-scheme` (§5.1: a
escolha é deliberadamente independente do SO). Storage bloqueado (§4.2): o store cai para
memória, o tema volta a escuro no próximo carregamento e um toast avisa uma única vez.
Preferência é do **dispositivo**, não do workspace — trocar de workspace não muda o tema.

### D-AUDIT-MODAL — a tela lê, e só

`GET /api/v1/workspace/audit_logs?limit=200`, ordem `recorded_at DESC`. Aberta a todos os
papéis (§4.1: ler é de todos). Sem controle de edição ou exclusão em lugar nenhum da UI —
não porque a UI é educada, mas porque o `REVOKE` de `audit-log` faria a chamada explodir.

## Risks / Trade-offs

- **O reset é irreversível dentro do app.** Mitigado pelo backup obrigatório de ≤15 min,
  pela frase de confirmação com o nome do workspace e por alerta de operação
  (`delivery-and-observability`). Aceito: reversão in-app exigiria D-RESTORE.
- **Superset aditivo cresce o arquivo** (nomes *e* ids, `history` *e* `advances`). Um
  workspace grande gera JSON de dezenas de MB. Mitigado: export síncrono só até um teto
  de contagem; acima disso vira job Sidekiq com download por link. O teto e o job estão
  em `tasks.md`.
- **Preservar memberships após reset** deixa membros com acesso a um workspace vazio, sem
  aviso. Aceito: o evento no `WorkspaceChannel` faz o app deles recarregar e cair no
  estado vazio, que é honesto. Remover acesso silenciosamente seria pior.
- **`task_advances` são apagadas enquanto `audit_logs` sobrevivem** — assimetria que vai
  parecer incoerente para quem ler o código sem contexto. Documentada no service e na
  tabela de D-RESET: a trilha pertence à tarefa, o log pertence ao workspace.
- **Round-trip byte a byte** é um teste rígido; qualquer campo novo em qualquer
  capacidade downstream o quebra. É intencional: é assim que se percebe que o formato de
  backup ficou defasado.

## Plano de migração

1. Migration aditiva: `people.archived_at` (nullable) + índice único parcial + trigger de
   membership; tabela `workspace_backups`. Nada destrutivo, reversível.
2. Export entra **antes** do reset — a ordem em `tasks.md` é obrigatória, o reset depende
   do `backup_id`.
3. O fixture do formato v2 é publicado antes de `legacy-data-migration` começar; qualquer
   mudança nele exige bump de `_rt.schemaVersion`.
4. Feature flag `FEATURE_FACTORY_RESET` desligada por padrão até o teste de round-trip
   passar em staging com dataset de carga.

## O que ficou de fora por priorização

A capacidade cobre três superfícies (tela, export, reset) e a lista de tarefas encostou no
teto do orçamento. Ficaram fora, conscientemente: restauração de backup pela UI
(D-RESTORE), backup agendado, retenção de longo prazo dos arquivos
(`delivery-and-observability`), exportação por escopo parcial (só um projeto) e
edição em lote do catálogo. Nenhum deles é exigido por §3.9 ou §3.11.

## Perguntas em aberto

- Restauração de backup pela UI (D-RESTORE): qual política de merge com o estado atual?
  Adiado para depois da v1.
- O teto de export síncrono (proposta: 5.000 tarefas) precisa ser calibrado contra o
  dataset de carga de `quality-and-accessibility`.
- Se um dia existir "excluir workspace de verdade", `audit_logs` precisa de destino —
  provavelmente export para arquivo frio antes do drop do schema. Fora de escopo.
