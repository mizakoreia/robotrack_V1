# Design — audit-log

## Context

O legado expressava a invariante 3 (§4.1) em uma linha de `firestore.rules`:
`allow update, delete: if false` sobre `workspaces/{ws}/logs/{logId}`. Não era convenção
nem disciplina de código: era o servidor recusando. Nenhum cliente, nenhum papel, nenhum
dono conseguia mutar um registro.

O porte para Rails perde essa garantia de graça. Um `before_update { throw :abort }` no
model é contornado por `update_column`, `update_all`, `delete_all`, por uma migration, ou
por qualquer `psql` apontado para o mesmo banco. **A invariante 3 é a única invariante do
RoboTrack cujo adversário declarado é o próprio dono do dado** — todas as outras protegem
um usuário de outro. Isso muda onde ela pode morar: não pode morar em nada que o dono
controle em tempo de execução.

Ao mesmo tempo, §2.8 é modesto no volume: **um** evento automático. O risco real não é
throughput, é (a) a garantia de imutabilidade ser teatro e (b) a tabela crescer para
sempre sem caminho de poda, porque o mecanismo óbvio de poda foi revogado de propósito.

O plano anterior tinha as duas regras — `REVOKE DELETE` e "reset de fábrica apaga tudo do
workspace" — coexistindo sem reconciliação. Não é um detalhe de redação: o reset era
descrito como **operação atômica** (§3.11), então a primeira instrução a bater no
privilégio revogado abortaria a transação inteira e o reset **nunca completaria**. D12
fixa a resolução e este documento a implementa do lado do log.

## Goals / Non-Goals

**Goals**
- Imutabilidade verificável por teste que ataca o banco diretamente, não o model.
- Registro de conclusão a 100% fiel: escrito ou a operação falha — sem log fantasma nem
  avanço sem log.
- Mensagem como dado versionado, não como literal (D14), com o texto exibido congelado.
- Exibição limitada a 200 e crescimento de armazenamento com política declarada.
- Fronteira com `workspace-settings` escrita, não subentendida.

**Non-Goals**
- Auditar CRUD de hierarquia, convites e mudanças de papel (fora de §2.8).
- Versionamento campo-a-campo de registros (`paper_trail`) — ver Decisão 8.
- Assinatura criptográfica encadeada (hash chain) das linhas — ver Riscos.
- Busca textual, filtro por autor ou paginação profunda no modal (§2.8 pede 200 e ordem).

## Decisions

### Decisão 1 — A imutabilidade mora em três lugares no banco, nenhum deles no model

| Camada | Onde | O que barra |
|---|---|---|
| Privilégio | `REVOKE UPDATE, DELETE ON audit_logs FROM robotrack_app` | Todo DML de mutação vindo do runtime, inclusive `update_column`, `update_all`, `delete_all`, e o `rails console` de produção (que usa a mesma credencial). |
| Trigger | `BEFORE UPDATE OR DELETE ON audit_logs FOR EACH ROW EXECUTE FUNCTION audit_logs_immutable()` → `RAISE EXCEPTION` incondicional | Qualquer papel que ainda tenha o privilégio: o **dono da tabela** e superusuário — exatamente os papéis que `REVOKE` não alcança. |
| RLS | Política com cláusulas `SELECT` e `INSERT` apenas; nenhuma política `UPDATE`/`DELETE` declarada | Com RLS habilitada, ausência de política = negação. Terceira negação, por omissão, e a única que também vale para o papel de migração se `FORCE ROW LEVEL SECURITY` estiver ativo. |

**A migração cria dois papéis Postgres**: `robotrack_migrator` (dono das tabelas, roda
DDL) e `robotrack_app` (runtime, `SELECT, INSERT` em `audit_logs`, DML completo no
resto). `DATABASE_URL` da aplicação usa `robotrack_app`;
`MIGRATION_DATABASE_URL` usa `robotrack_migrator`. Isso é requisito de deploy — citado em
`delivery-and-observability`.

*Alternativa descartada:* `before_destroy`/`before_update` com `throw :abort` no model
ActiveRecord. Descartada porque não sobrevive a `update_column`, `update_all`,
`delete_all`, `import`, nem ao console — e §4.1 inv. 3 nomeia o dono como parte do
conjunto protegido; o dono é justamente quem tem acesso ao console.

*Alternativa descartada:* só o `REVOKE`, sem trigger. Descartada porque `REVOKE` não tem
efeito sobre o papel dono da tabela; um `rails db:migrate` acidental (que roda como
`robotrack_migrator`) conseguiria um `UPDATE`. A trigger fecha esse caso e é o que os
testes de contorno atacam.

*Alternativa descartada:* tabela em banco separado só-append. Descartada porque quebra a
atomicidade exigida na Decisão 3 (o log e o avanço têm que commitar juntos) e duplica a
superfície de tenancy.

### Decisão 2 — Retenção por particionamento e DDL, não por DML

`audit_logs` é `PARTITION BY RANGE (ts)`, uma partição por mês, criadas com antecedência
de 3 meses por job mensal. Retenção: partições com mais de **24 meses** são exportadas em
JSONL comprimido para storage frio, o arquivo é **verificado** (contagem de linhas e
checksum conferem com a partição) e só então a partição é `DETACH`ed e `DROP`ada.

Isso não é um contorno da imutabilidade — é a leitura correta dela. A invariante proíbe
**mutar ou apagar um registro individual** (DML, dentro do escopo de uma sessão de
aplicação). Descartar um período inteiro é DDL, operação de administração de esquema,
executada por `robotrack_migrator` fora do caminho de request, com registro do que foi
arquivado. Importante: `DETACH`/`DROP PARTITION` **não dispara a trigger de linha**, e é
essa a razão de a poda ser expressa como DDL — se ela fosse `DELETE`, a trigger a barraria
e a única saída seria conceder `DELETE`, o que destruiria a garantia para todo o resto.

Consequência de esquema aceita: em tabela particionada a chave primária deve conter a
chave de partição. A PK é **`(ts, id)`**, com `id uuid` cliente-gerável (D1). Não existe
índice único global sobre `id` sozinho — em tabela particionada isso exigiria a chave de
partição —, então a unicidade de `id` repousa no uuid v4 e é auditada por um check de
duplicidade no job mensal de arquivamento (que já varre a partição inteira).
Referências externas ao log **não existem** (nada aponta para `audit_logs`),
então uma PK composta não vaza para nenhum outro esquema.

*Alternativa descartada:* retenção infinita em tabela única. Descartada não pelo modal
(que lê 200 linhas por índice) mas pelo backup JSON de §3.11 e pelo `VACUUM`/índice: com
um evento por conclusão de tarefa e workspaces de comissionamento gerando milhares de
conclusões por projeto, o custo é linear e sem teto, e o operador não teria nenhuma
alavanca a não ser conceder `DELETE`. Preferimos decidir agora do que sob pressão.

*Alternativa descartada:* job de retenção com `DELETE FROM audit_logs WHERE ts < ...`.
Descartada porque exige `GRANT DELETE` a algum papel operacional, e a existência desse
privilégio é exatamente o que a invariante 3 proíbe — um privilégio que existe será usado.

*Alternativa descartada:* arquivar **antes** de ter storage frio configurado. Descartada:
o `DROP` só é permitido depois da verificação do arquivo; sem bucket configurado o job
falha e alerta, e a partição fica. Dependência explícita de `delivery-and-observability`
(`AUDIT_ARCHIVE_BUCKET`, credencial, alerta de falha, métrica de crescimento).

### Decisão 3 — O log de conclusão é transacional, ao contrário da notificação

§2.7 diz que falha ao notificar **nunca** pode derrubar o save. §2.8 não diz nada
parecido, e §4.1 inv. 3 trata o log como registro de verdade. Portanto: o INSERT em
`audit_logs` acontece **na mesma transação** do `task_advance` que levou a tarefa a 100.
Se o log falhar, o avanço não commita.

*Alternativa descartada:* enfileirar o log no Sidekiq como a notificação. Descartada
porque produziria "tarefa concluída sem registro de conclusão" em caso de fila caída —
uma trilha imutável com buracos é pior que uma indisponibilidade momentânea, e o custo do
INSERT síncrono é uma linha.

**Idempotência**: retentativa da fila offline (D7) reexecuta a transação inteira; o
`task_advance` tem uuid cliente-gerado (D1) e sua PK conflita, abortando a transação
antes de duplicar o log. **Esta capacidade não implementa dedup próprio** — a chave de
idempotência é do avanço e mora em `progress-advances`. Se aquela transação for
reestruturada, este acoplamento precisa ser revisto (ver Perguntas em aberto).

### Decisão 4 — `msg` é renderizado no INSERT e congelado; `payload` guarda os dados

A linha carrega ambos:
- `event_type` (enum texto: `task_completed`, `workspace_reset`), `format_version` (int),
  `payload` (jsonb com `robot_id`/`robot_name`, `task_id`/`task_desc`, `assignee_names`);
- `msg` (texto já renderizado) e `ts_local` (texto já formatado).

A renderização usa a format string de locale (Decisão 5) **no momento da escrita** e o
resultado é gravado. A exibição usa `msg` verbatim, nunca re-renderiza.

*Alternativa descartada:* guardar só `event_type` + `payload` e renderizar na leitura.
Descartada porque uma edição futura no arquivo de locale **reescreveria retroativamente o
texto de registros históricos** — mutação de auditoria por uma porta lateral, violando o
espírito da invariante 3 sem tocar em uma linha do banco. Guardar `payload` além do `msg`
custa pouco e mantém o log legível por máquina para relatório e migração.

`ts_local` segue o mesmo raciocínio: é renderizado no servidor no fuso do workspace
(`America/Sao_Paulo` por padrão) e congelado. *Alternativa descartada:* formatar no
cliente a partir de `ts` — descartada porque registros importados do legado (§1.4) já
trazem `tsLocal` gravado com uma formatação que não temos como reproduzir, e porque o
texto exibido passaria a variar com o fuso do navegador de quem lê.

### Decisão 5 — Format string versionada em locale (D14)

`config/locales/pt-BR.audit.yml`:

```yaml
pt-BR:
  audit:
    task_completed:
      v1: 'Em [%{robot}], %{assignees} concluiu a tarefa "%{task}" com 100%%.'
    workspace_reset:
      v1: '%{by_name} executou o reset de fábrica do workspace. Projetos removidos: %{projects_count}.'
```

Regra dura: **uma versão publicada nunca é editada.** Mudar o texto cria `v2` e incrementa
`format_version` nas linhas novas. Um spec de CI falha se uma chave `vN` já referenciada
por linhas existentes for alterada (comparação com o arquivo na `main`).

*Alternativa descartada:* interpolar em Ruby (`"Em [#{robot.name}], ..."`). Descartada por
D14 e porque tornaria impossível a checagem de CI acima — o texto histórico ficaria
indistinguível de código.

*Nota de fidelidade ao legado:* `%{assignees}` é a junção dos nomes dos responsáveis
**no momento da conclusão** (snapshot, D10/D11) e o verbo fica no singular como no legado
("concluiu"), inclusive com múltiplos responsáveis. Não corrigimos a concordância: mudar
o texto é `v2`, e não há requisito para isso.

### Decisão 6 — Autoria por `person_id` + snapshot de nome (D10)

`by_person_id uuid` FK para `people` com `ON DELETE SET NULL` (nullable) e
`by_name text NOT NULL`. Se a `Person` for removida, o registro continua nomeando quem
agiu. Registros importados do legado sem correspondência resolvível têm
`by_person_id IS NULL` e `by_name` vindo do export — inclusive `"(nota anterior)"` (§1.4).

`by_name` é **a única forma legítima de nome de pessoa no esquema** junto com o snapshot
equivalente em `task_advances` — não é chave, não é usada em nenhum `WHERE` de
autorização, e é imutável por construção (a tabela inteira é).

*Alternativa descartada:* só `by_person_id`, com o nome resolvido por join na leitura.
Descartada porque renomear uma pessoa reescreveria a trilha histórica, e porque a pessoa
pode ser removida (D10 permite `Person` sem `User`, e membros saem do workspace).

### Decisão 7 — Fronteira com o reset de fábrica (D12)

`audit_logs` **não tem FK alguma para** `projects`, `cells`, `robots`, `tasks`. As
referências ficam em `payload` como uuid + texto denormalizado. Isso é deliberado: é o que
faz o log sobreviver ao `DELETE` em cascata do reset sem depender da ordem das instruções.
A FK para `workspaces` é `ON DELETE RESTRICT` — o log impede a remoção da linha de
workspace, e D12 já estabelece que o reset **não** remove o workspace.

Contrato oferecido a `workspace-settings`:
`AuditLog::RecordService.record!(workspace:, event: :workspace_reset, by:, payload:)`,
chamado **dentro** da transação do reset, depois dos deletes. Se o registro falhar, o
reset inteiro faz rollback — o reset é atômico (§3.11) e "reset sem rastro" é o cenário que
D12 existe para impedir.

*Alternativa descartada:* `ON DELETE CASCADE` a partir de `projects` para preservar
integridade referencial. Descartada porque seria literalmente a contradição que D12
resolve: o reset apagaria a auditoria dele mesmo.

### Decisão 8 — `paper_trail` não serve; log de domínio ≠ versionamento de registro

`paper_trail` está no Gemfile e não é usado em lugar nenhum. Avaliado e **rejeitado** para
este caso, por quatro razões independentes:

1. **Semântica errada.** `paper_trail` grava diffs por registro (`item_type`, `item_id`,
   `object_changes`), respondendo "o que mudou nesta linha". §2.8 pede uma **narrativa de
   evento de negócio em pt-BR** — "Em [R-014], Ana concluiu a tarefa ... com 100%" — que
   não é derivável de um diff de coluna sem reconstruir o texto na leitura, exatamente o
   que a Decisão 4 proíbe.
2. **A tabela `versions` é mutável por design.** A API pública da gem inclui
   `PaperTrail::Version.destroy_all`, `limit` (poda automática de versões antigas) e
   `reify`/rollback. Adotar a gem é adotar métodos cujo propósito é apagar e reverter
   trilha. Aplicar `REVOKE UPDATE, DELETE` sobre `versions` quebraria a gem; não aplicar
   quebraria a invariante 3.
3. **Sem tenancy.** `versions` não tem `workspace_id` e a gem não conhece RLS. Seria uma
   segunda superfície de vazamento entre tenants, contra D2.
4. **Volume desproporcional.** Versionar todo o domínio produz ordens de magnitude mais
   linhas que os dois eventos de §2.8, agravando o problema de retenção da Decisão 2 sem
   atender a nenhum requisito.

Conclusão: são coisas distintas. O log de auditoria de domínio é uma **tabela de eventos
de negócio append-only**, escrita explicitamente por um service; versionamento de registro
é uma ferramenta de depuração/undo que o RoboTrack não pede em lugar nenhum da spec.
Recomendação: `paper_trail` sai do Gemfile em `seal-template-baseline` (dívida de template
já catalogada), a menos que outra capacidade o reivindique.

### Decisão 9 — Leitura: teto de 200 no servidor, papel `view` incluso

`GET /api/v1/workspaces/:workspace_id/audit_logs`. `limit` do cliente é **clampeado** a
200 no service; não há `offset`, não há paginação. `AuditLogPolicy.index?` = qualquer
membro do workspace, inclusive `view` (§4.1: "Ler tudo do workspace" ✅ para os três
papéis). **Nenhuma rota `POST`/`PATCH`/`PUT`/`DELETE` de log existe** — o route-sweep de
D3 vê apenas o `index` declarado. Índice `(workspace_id, ts DESC)` em cada partição
sustenta a consulta.

*Alternativa descartada:* paginação infinita no modal. Descartada porque §2.8 especifica
200 e porque, sem teto, o endpoint vira o caminho barato para varrer o histórico inteiro
de um tenant.

## O que ficou fora do escopo de tarefas

`tasks.md` fecha em 34 tarefas, um pouco acima do teto de 30 — o excedente é a capability
de retenção (grupo 8), que é o que impede a tabela de virar problema operacional e não
tinha dono em nenhuma outra proposta. Foi priorizado assim, e o seguinte ficou **fora**:

- **Eventos de auditoria além de `task_completed` e `workspace_reset`** (convites, mudança
  de papel, CRUD de hierarquia). O esquema é extensível por `event_type`; nenhum requisito
  os pede.
- **Atualização ao vivo do modal.** Fica para `realtime-collaboration` (D6) — a chave de
  query já é a convencionada por D9 para permitir a invalidação depois.
- **Restauração de partição arquivada de volta ao banco quente.** O arquivo em storage frio
  é legível, mas não há caminho automatizado de re-anexação; se virar necessidade
  operacional, é uma proposta própria.
- **Filtro, busca ou paginação profunda no modal.** §2.8 pede 200 e ordem, nada mais.

## Plano de migração

1. Migration cria os papéis `robotrack_migrator`/`robotrack_app` e os `GRANT`s de base.
   Não destrutiva; idempotente (`DO $$ ... IF NOT EXISTS`).
2. Migration cria `audit_logs` particionada + partições dos 3 meses seguintes + trigger +
   RLS + `REVOKE`. Tabela nova, sem dado preexistente: **não há passo destrutivo**.
3. Deploy troca `DATABASE_URL` para `robotrack_app`. **Este é o passo de risco**: se a
   aplicação subir com o papel dono, a camada 1 fica inerte (a trigger continua valendo).
   Um smoke test de boot verifica `has_table_privilege('audit_logs','UPDATE') = false` e
   **recusa subir** se for verdadeiro.
4. Job mensal de criação de partição futura e job mensal de arquivamento entram
   desabilitados; ligados após o primeiro ciclo de verificação em staging.
5. Rollback: reverter a migration de `audit_logs` é `DROP TABLE` — só admissível enquanto
   a tabela estiver vazia. Depois do primeiro registro em produção, o rollback do passo 2
   é **proibido** e a reversão se dá pelo caminho de arquivamento (Decisão 2). A migration
   declara isso em `def down` com `raise ActiveRecord::IrreversibleMigration` quando a
   tabela tem linhas.

## Riscos / Trade-offs

- **Papel dono ainda pode `DROP TABLE`.** Nenhuma configuração dentro do Postgres protege
  contra um DBA determinado. Mitigação fora do banco: backup/PITR e alerta de queda brusca
  de contagem — `delivery-and-observability`. Assumido: a invariante protege contra
  mutação pela aplicação e pelo console de aplicação, não contra um administrador de
  infraestrutura.
- **Sem hash chain.** Não há prova criptográfica de que a sequência não foi adulterada via
  restauração de backup manipulado. Trade-off aceito: §2.8 pede imutabilidade operacional,
  não não-repúdio forense. Se virar requisito, entra como coluna `prev_digest` — decidido
  não fazer agora para não pagar o custo de reprocessamento na verificação.
- **PK composta `(ts, id)`.** Custo de particionar. Aceitável porque nada referencia
  `audit_logs`; vira problema se alguém criar FK para ele — proibido explicitamente na
  spec de retenção.
- **Log transacional acopla a escrita do avanço à saúde do log.** Uma partição faltante
  para o mês corrente derruba conclusões de tarefa. Mitigação: partições criadas com 3
  meses de antecedência, mais uma partição `DEFAULT` como rede (que o job de arquivamento
  alerta se receber linhas).
- **`format_version` é disciplina, não constraint.** O check de CI que compara o locale
  com a `main` é a única barreira contra editar uma versão publicada. Um force-push a
  contorna.

## Perguntas em aberto

1. Fuso do `ts_local`: fixo em `America/Sao_Paulo` ou coluna `timezone` no workspace?
   Assumido fixo nesta fase; `workspace-tenancy` decide se workspace ganha fuso.
2. Se `progress-advances` mover o INSERT do avanço para fora de uma transação única
   (ex.: batching offline), a idempotência da Decisão 3 deixa de valer e este log precisa
   de chave de dedup própria. Aresta a confirmar com aquela capacidade.
3. Retenção de **24 meses** é um chute informado (ciclo de comissionamento automotivo
   típico + margem). Precisa de confirmação do produto antes de o primeiro `DROP` rodar —
   até lá o job só arquiva e não destaca.
