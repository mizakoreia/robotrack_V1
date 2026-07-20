# Log de auditoria append-only

## Why

A ESPECIFICACAO.md descreve o log de auditoria em três lugares que precisam ser lidos
juntos:

- **§1.1 — entidade "Log de auditoria (append-only)"**: `msg`, `ts` (servidor),
  `tsLocal` (texto formatado), `by`, `byName`.
- **§2.8**: append-only, **imutável — sem edição nem exclusão, nem pelo dono**. Um único
  registro automático existe hoje: conclusão de tarefa a 100% (§2.2 confirma: `100` →
  `Concluído` *+ grava log de auditoria*). Exibido em modal (§3.11), ordenado do mais
  recente, **limitado a 200 registros**.
- **§4.1 invariante 3**: "O log de auditoria é append-only **para todos, inclusive o
  dono**." E a matriz de permissões de §4.1: criar log é `owner`/`edit`; ler é todo mundo
  no workspace, inclusive `view`.

No legado isso era uma linha de `firestore.rules`:

```
match /workspaces/{wsId}/logs/{logId} {
  allow update, delete: if false;
}
```

`if false` é uma garantia de servidor: não existia caminho, nem para o dono, nem para o
console do Firebase operando com credencial de cliente. **O porte precisa entregar uma
garantia do mesmo calibre e ela não pode ser uma validação de model** — um model se
contorna com `AuditLog.find(id).update_column(:msg, "...")` no `rails console`, e um
`before_destroy` se contorna com `delete_all`. A invariante 3 só é real se estiver no
banco: privilégio revogado no papel da aplicação **e** trigger que levanta exceção.

Além disso, esta proposta resolve uma **contradição herdada** do plano anterior, fixada
agora pela decisão transversal **D12**: o plano tinha simultaneamente `REVOKE DELETE` em
`audit_logs` e um "reset de fábrica" (§3.11) que apagava tudo do workspace. As duas
regras nunca foram reconciliadas — na prática, o reset era **impossível de executar**: a
primeira instrução do serviço bateria no privilégio revogado e abortaria a transação
atômica inteira. A resolução: o reset **não toca em auditoria**; apaga
projetos/células/robôs/tarefas e **grava no próprio log** que ocorreu. `workspace-settings`
é dono do reset; esta capacidade é dona de garantir que o log **sobrevive** a ele e de
expor o caminho de escrita que registra o evento.

Por fim, o legado limitava a **exibição** a 200 registros e não limitava nada no
**armazenamento**. Com `REVOKE DELETE`, "limpar registros velhos" deixa de ser uma opção
disponível, então retenção precisa de um caminho que respeite a imutabilidade em vez de
contorná-la. Isso é tratado aqui, não adiado.

## What Changes

- **Tabela `audit_logs`** (uuid PK gerável no cliente, D1/D13; `workspace_id NOT NULL` +
  **RLS**, D2), com `msg`, `ts` (servidor), `ts_local` (texto formatado congelado),
  `by_person_id` (**D10**: identidade estável, não nome) e `by_name` (**snapshot
  histórico imutável** — a única forma legítima de nome de pessoa no esquema, conforme a
  convenção do `config.yaml`).
- **Imutabilidade no banco, em duas camadas**: `REVOKE UPDATE, DELETE ON audit_logs FROM`
  o papel de runtime da aplicação, **e** trigger `BEFORE UPDATE OR DELETE` que levanta
  exceção incondicionalmente — a segunda camada existe porque `REVOKE` não alcança o
  papel dono da tabela nem superusuário, e a política de RLS de `audit_logs` não declara
  cláusula `UPDATE`/`DELETE` alguma (terceira negação, por omissão).
- **Registro automático de conclusão a 100%** (§2.2/§2.8), gravado **na mesma transação**
  do avanço que levou a tarefa a 100 — não best-effort (ao contrário de notificações,
  §2.7).
- **Formato da mensagem como format string versionada em locale** (**D14**):
  `pt-BR.audit.task_completed.v1` em `config/locales/pt-BR.audit.yml`, produzindo
  `Em [<robô>], <responsáveis> concluiu a tarefa "<desc>" com 100%.` — nunca um literal
  interpolado em Ruby.
- **Texto renderizado congelado na linha**: `msg` e `ts_local` são materializados no
  INSERT. A linha também guarda `event_type` + `payload` (jsonb) para leitura por máquina.
- **Endpoint de leitura** `GET /api/v1/workspaces/:workspace_id/audit_logs`, teto **rígido
  de 200 no servidor**, `ORDER BY ts DESC`, e **modal de auditoria** no frontend (§3.11).
- **Nenhuma rota de escrita, atualização ou exclusão de log é exposta na API.** O único
  produtor é um service interno chamado por outras capacidades.
- **Sobrevivência ao reset de fábrica (D12)**: `audit_logs` não tem FK para
  projects/cells/robots/tasks (as referências vivem em `payload` como uuid + texto
  denormalizado), e a FK para `workspaces` é `ON DELETE RESTRICT`. O reset grava
  `workspace_reset` no log.
- **Retenção por particionamento mensal + arquivamento verificado** (capability separada),
  em vez de `DELETE`.
- **BREAKING (interno):** o papel Postgres usado pelo runtime deixa de ser o papel dono
  das tabelas. Exige duas credenciais distintas (migração vs. runtime) no deploy — ver
  dependência em `delivery-and-observability`.

### Não-objetivos

- **Não é versionamento de registro.** `paper_trail` está no Gemfile e totalmente não
  usado; esta proposta **não** o adota — justificativa em `design.md` (Decisão 8). Se
  ninguém mais o reivindicar, é dívida de `seal-template-baseline`.
- **Não implementa o reset de fábrica.** Dono: `workspace-settings` (D12). Aqui só a
  fronteira: o log sobrevive e há um caminho de escrita para registrar o evento.
- **Não cria eventos de auditoria além dos dois definidos** (`task_completed`,
  `workspace_reset`). Convites, mudanças de papel e CRUD de hierarquia **não** geram log
  nesta fase — o legado não gerava, e inventar eventos aumenta volume sem requisito.
  O esquema é extensível por `event_type`.
- **Não faz exportação/backup do log.** Backup JSON é §3.11 / `workspace-settings`.
- **Não implementa notificações** (§2.7, `in-app-notifications`) — semântica oposta:
  notificação é best-effort e mutável (`read`); log é transacional e imutável.
- **Não implementa tempo real no modal.** Se o log passar a atualizar ao vivo, é evento
  publicado por `realtime-collaboration` (D6).

## Capabilities

### New Capabilities

- `audit-log`: trilha append-only por workspace, imutável no nível do banco para todos os
  papéis inclusive o dono; registro automático de conclusão a 100% com format string
  versionada em locale; leitura limitada a 200 registros mais recentes; sobrevivência ao
  reset de fábrica.
- `audit-log-retention`: política de crescimento do armazenamento compatível com
  `REVOKE DELETE` — particionamento mensal por `ts`, arquivamento verificado para storage
  frio e `DETACH`/`DROP` de partição como DDL, jamais `DELETE` de linha.

### Modified Capabilities

Nenhuma. `openspec/specs/` está vazio — nada foi construído ainda.

### Impact

- **Depende de** `progress-advances` (Onda 5): o gatilho do único evento automático é a
  transição de progresso para 100 (§2.2). O log é escrito dentro da transação do avanço;
  a idempotência da retentativa offline vem do uuid cliente-gerado do avanço (D1/D7), não
  de dedup próprio do log.
- **Depende de** `workspace-tenancy` (D2 RLS, D10 `Person`) e `authorization-policies`
  (D3: `AuditLogPolicy`, route-sweep).
- **É dependência de** `workspace-settings` (Onda 8, D12) — o reset chama o service de
  registro; e de `commissioning-report` apenas indiretamente (o relatório usa
  `task_advances`, não `audit_logs` — fronteira explicitada no design).
- **Exige de** `delivery-and-observability`: duas credenciais Postgres (migração/runtime),
  bucket de storage frio + credencial, job Sidekiq mensal de arquivamento, alerta de
  falha de arquivamento e métrica de crescimento da tabela.
- **Exige de** `quality-and-accessibility` (D14): o arquivo de locale
  `config/locales/pt-BR.audit.yml` e a política de versionamento de format string.
