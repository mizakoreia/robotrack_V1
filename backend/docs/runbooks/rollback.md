# Runbook — rollback de deploy (delivery-and-observability 8.1)

Decisão em 30 segundos. Escolha o degrau MAIS BAIXO que resolve; subir de degrau
custa mais e arrisca mais.

## Degrau 1 — Redeploy da imagem anterior (padrão)

**Quando:** o código novo tem bug, mas o ESQUEMA não mudou de forma incompatível
(migrations desta versão foram só `expand` — adições, nada destrutivo).

**Como:** repromover a tag da imagem anterior na plataforma. Os processos
`web`/`worker` sobem no código antigo; o esquema atual (expandido) é compatível
com ele por construção (expand/contract).

**Reversível:** sim, imediato. Sem perda de dado.

## Degrau 2 — Kill switch por ENV

**Quando:** o bug está numa capacidade isolada e há um toggle (ex.:
`VITE_REALTIME_ENABLED=false` desliga o tempo real; feature flags de servidor).

**Como:** mudar a variável e reiniciar (ou recarregar). A aplicação segue correta,
só sem aquela capacidade.

**Reversível:** sim. Sem perda de dado. Mais rápido que um redeploy quando aplicável.

## Degrau 3 — `db:rollback` (ÚLTIMO recurso, com restrição dura)

**Quando:** só quando uma migration `expand` desta versão precisa ser desfeita E
NÃO é `contract`.

**Restrição (o ponto sem volta):** `db:rollback` **RECUSA** migrations marcadas
`# contract-of:` — uma contração destrutiva (`remove_column`/`drop_table`/…) já
descartou o dado; desfazê-la por migration não o traz de volta. O guard
(`ops:refuse_contract_rollback`) aborta com esta mensagem.

**Para reverter uma contração destrutiva:** NÃO é rollback de esquema — é
**RESTORE do backup verificado**. O RPO (janela de perda) é o `taken_at` do
manifesto do backup. Uma migration `contract` só chega a rodar depois de o
`bin/release` confirmar um backup fresco (< 1h) e restaurado (8.3), justamente
para que este caminho exista.

## Critério de escolha (resumo)

| Situação | Degrau |
|---|---|
| Bug de código, esquema compatível | 1 (redeploy anterior) |
| Bug isolado com toggle | 2 (kill switch) |
| Migration `expand` a desfazer, sem dado perdido | 3 (`db:rollback`) |
| Contração destrutiva a reverter | Restore do backup (não é rollback) |

## Pré-requisito declarado

Este runbook DEVE ter sido ensaiado em staging antes do primeiro deploy de
produção (8.4) — um runbook nunca ensaiado é um runbook que não existe.
