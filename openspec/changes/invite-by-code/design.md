## Context

`workspace-invitations` entregou o convite como um link com token de 256 bits. Toda a
maquinaria já existe e é madura: `invitation_by_token` (SECURITY DEFINER + ramo RLS que
lê a linha por token exato sem workspace corrente, sem BYPASSRLS), o `AcceptService`
(transação + `SELECT ... FOR UPDATE` + seis validações + resolução de `Person` +
one-shot, com rejeições como EXCEÇÃO por causa do commit-on-return do Rails 7+), o
`PreviewService`, o `rack_attack` (accept-ip/accept-session/preview-ip + log só do
`token_sha256[0,12]`), o `invitation_log_scrubber` (troca `rt_inv_...` por hash no log)
e o fluxo frontend (`InviteRoute` → `sessionStorage` sobrevivendo ao OAuth → `AuthPage`
→ `consumeInvite`).

Este change adiciona um **código curto** como SEGUNDA representação do MESMO registro
`invitations`. O código é de baixa entropia (2⁴⁰), então o trabalho de design não é
"como achar a linha" (isso é uma cópia do padrão do token) — é **como impedir que a
baixa entropia vire uma porta**. A resposta é a soma de: (a) o vínculo com o e-mail
autenticado, que o token e o código compartilham e que sozinho já torna a adivinhação
inútil sem controlar a conta-alvo; e (b) defesas ativas que só o código precisa.

Decisões do dono já fixadas (PLANO §F): código é **por-convite/por-e-mail** (§F.4),
**coexiste** com o link (§F.1), formato **8 chars Crockford Base32, 48h, HMAC com
pepper** (§F.2), e **só o dono convida** nesta change (§F.3).

## Decisões

### D1 — Código é uma COLUNA na linha existente, não um segundo registro

**Decisão.** Migration puramente aditiva sobre `invitations`: `code_hash`,
`code_expires_at`, `code_attempts`, `code_locked_at`. O código herda a mesma linha, o
mesmo `workspace_id`, o mesmo `email`, o mesmo `role`, a mesma unicidade de pendente por
e-mail.

**Onde a invariante mora.** No BANCO: índice único parcial
`index_invitations_on_code_hash ... WHERE code_hash IS NOT NULL` garante unicidade do
código mesmo contra um `INSERT` por console. A coerência "código pertence ao convite"
é estrutural — é a mesma linha.

**Alternativa descartada.** Uma tabela `invitation_codes` separada (1:1 com
`invitations`). Rejeitada: duplicaria a RLS, a expiração, o `workspace_id` e a FK do
criador; exigiria um segundo `SECURITY DEFINER` e um segundo ramo RLS coordenados; e
abriria a porta para o estado inconsistente "código sem convite". A coluna na mesma
linha é a tradução fiel de "representação adicional do MESMO convite".

### D2 — `code_hash` (HMAC com pepper), nunca o código em claro

**Decisão.** O banco guarda `HMAC-SHA256(pepper, normalize(code))`. O pepper vem de
`INVITATION_CODE_PEPPER` (credentials/ENV, registrado no `env_schema` com guarda de
boot), **nunca versionado, nunca dentro do banco**. O app computa o HMAC e passa o HASH
para `invitation_by_code(hash)`; a função só seta a variável de sessão e seleciona por
igualdade.

**Onde a invariante mora.** No app (cálculo do HMAC, pepper fora do banco) + no banco
(coluna `code_hash`, índice único, ramo RLS por igualdade de hash).

**Por que HMAC e não bcrypt.** O lookup precisa ser DETERMINÍSTICO para indexar e achar
a linha por igualdade — bcrypt salga por linha e exigiria varredura da tabela inteira,
o que a RLS por-linha nem permitiria. HMAC com pepper dá determinismo + resistência a
brute-force offline: se o banco vazar, sem o pepper o `code_hash` não é reconstruível.

**Por que o app computa o HMAC, não a função.** Manter o pepper FORA do banco: uma
função `SECURITY DEFINER` que computasse o HMAC precisaria do pepper como parâmetro ou
como GUC, e qualquer um dos dois o exporia num `pg_stat_statements`/log de query. O app
computa; a função recebe já o hash.

**Alternativa descartada.** Guardar o código em claro (como o token). Rejeitada: o
token pode ficar em claro porque adivinhá-lo é inviável por entropia (256 bits) — ele
JÁ é o segredo. O código de 2⁴⁰ é fraco; em claro, um vazamento de banco vira acesso
pronto. A assimetria de entropia justifica a assimetria de armazenamento.

### D3 — Lookup por código espelha `invitation_by_token`

**Decisão.** Terceiro ramo no `USING` da policy `tenant_isolation`:
`OR code_hash = NULLIF(current_setting('app.invitation_code_hash', true), '')`. O
`WITH CHECK` continua PURO de workspace (ler por código não autoriza escrever). Função
`invitation_by_code(p_code_hash text)` `SECURITY DEFINER STABLE` que faz
`set_config('app.invitation_code_hash', p_code_hash, true)` e
`RETURN QUERY SELECT * FROM invitations WHERE code_hash = p_code_hash`.

**Onde a invariante mora.** No banco (policy RLS + função). Mesmo padrão fail-closed do
token: quem não conhece o código não seta a GUC, `current_setting` devolve NULL, a
comparação vira NULL, NULL não é TRUE.

**Alternativa descartada.** Dar `BYPASSRLS` ao runtime para o lookup. Rejeitada
categoricamente: destruiria a garantia central da Onda 1 (a app conecta sem BYPASSRLS).

### D4 — Aceite por código REUSA `consume`, muda só o lookup

**Decisão.** `AcceptService` ganha `lookup_by_code(code, email)`: (1) normaliza o
código, (2) computa o HMAC, (3) chama a checagem de lockout/expiração do código, (4)
`SELECT * FROM invitation_by_code($hash)`, (5) confere `email` submetido ==
`invitation.email` (senão incrementa `code_attempts` e responde genérico), e então
chama o **mesmo `consume(workspace_id, id)`** de hoje. As seis validações, a resolução
de `Person`, o one-shot e o rollback são exatamente os mesmos.

**Onde a invariante mora.** Invariante 6 inteira permanece no `consume` já existente
(banco: `FOR UPDATE` + `chk_invitations_consumption` + `idx_memberships_one_per_
invitation`; service: as seis validações). O caminho por código só adiciona duas guardas
ANTES do `consume` (lockout, par e-mail+código) e nada remove.

**Alternativa descartada.** Um `AcceptByCodeService` separado que reimplementasse a
transação. Rejeitada: duplicaria a lógica mais delicada da §4.1 (invariante 6) e faria
as duas cópias divergirem na primeira correção. A regra da casa é reusar.

### D5 — Preview por código exige o PAR (código + e-mail)

**Decisão.** `preview_by_code(code, email)` só responde `200` com
`workspace_name`/`role`/`email_masked`/`status` quando `email` submetido ==
`invitation.email`. Sem o par correto: resposta genérica idêntica à de código
inexistente (mesmo corpo, mesmo tempo).

**Por quê.** O preview por TOKEN pode responder só com o token porque o token já é o
segredo forte — quem o tem, merece saber para onde leva. O código é enumerável; se o
preview por código respondesse a qualquer código adivinhado, um atacante colheria uma
lista de `workspace_name`/`email_masked`/`role` — alvos de phishing prontos. Exigir o
e-mail no par mata a colheita: adivinhar o código não basta, é preciso já saber o
e-mail-alvo.

**Onde a invariante mora.** No service (`preview_by_code`) + na igualdade de resposta
(sem canal lateral).

**Alternativa descartada.** Preview por código só com o código (simétrico ao token).
Rejeitada pelo vetor de colheita acima.

### D6 — Rotas dedicadas `/code/preview` e `/code/accept` (POST), antes do `:token`

**Decisão.** Duas rotas novas: `POST /api/v1/invitations/code/preview` (público,
tenant-exempt) e `POST /api/v1/invitations/code/accept` (autenticado, tenant-exempt).
`POST` mesmo no preview porque o e-mail viaja no CORPO — a regra de privacidade da casa
proíbe dado pessoal em query string. Declaradas na mesma classe Grape das rotas por
token (que já seta `Referrer-Policy: no-referrer`), **antes** da rota `:token/accept`.

**Armadilha registrada (roteamento).** `POST /invitations/code/accept` casaria o padrão
`POST /invitations/:token/accept` com `token = "code"`. O Grape resolve por ORDEM de
declaração; por isso as rotas `code/*` são declaradas ANTES de `:token/accept` na mesma
classe. Espelha o cuidado de `identity-and-auth` com `session/?$` vs `session/renew`.

**Onde a invariante mora.** Na allowlist declarada de `Api::Root`
(`PUBLIC_ROUTES`/`TENANT_EXEMPT_ROUTES`), no `public_routes.yml` (para o route-sweep) e
no `route_setting :policy, access: :authenticated` do accept. As rotas `/code/*` NÃO têm
segmento `:id`, então não entram na varredura cross-tenant (que só é elegível para
`/:(\w+_)?id`) — e isso está correto: elas não endereçam recurso por id; o lookup é por
hash sob RLS.

**Alternativa descartada.** Sobrecarregar `POST /invitations/:token/accept` para também
aceitar código no corpo. Rejeitada: colidiria semânticas (token no path vs. par no
corpo), embaralharia os throttles e violaria a ordem de roteamento.

### D7 — Expiração própria de 48h e lockout por convite

**Decisão.** `code_expires_at` default 48h (contra 7 dias do link); após 5 falhas do par
(código certo, e-mail errado) contra a MESMA linha, seta `code_locked_at` e responde
`423 invitation_code_locked`. Destrava reemitindo (o dono gera novo código). O
incremento de `code_attempts` roda numa transação curta no caminho de FALHA do lookup.

**Onde a invariante mora.** No banco (`code_expires_at`, `code_attempts`,
`code_locked_at` como colunas) + no service (checagem antes do `consume`).

**Limite honesto (registrado).** O lockout-por-linha só morde quando o código EXISTE
(código certo, e-mail errado). Contra adivinhação CEGA (código errado → nenhuma linha,
nada a travar) valem os tetos de rack-attack (IP/e-mail/global). Nenhuma defesa isolada
basta: é a soma de e-mail + expiração curta + lockout + rate-limit.

**Trade-off registrado (DoS-de-si-mesmo).** Um brincalhão pode errar 5× o par e travar o
código de um colega. Mitigado por: o lockout é do CÓDIGO (o LINK segue válido e
consumível), é destravável reemitindo, e exigir o e-mail no par eleva o custo de
disparar o lockout alheio (é preciso já saber o e-mail-alvo).

### D8 — Rate-limit em três eixos, mais apertado que o do token

**Decisão.** `code-accept-ip` 5/10min, `code-preview-ip` 10/10min, teto por **e-mail
submetido** 5/10min, e um teto **GLOBAL** de falhas de código por minuto (discriminador
constante), porque um atacante distribui IPs. Todos por PATH das rotas `/code/*`. O
`throttled_responder` loga `code_sha256[0,12]`, nunca o código.

**Por quê o teto global.** Com 2⁴⁰ de espaço e um teto global de algumas centenas de
tentativas/min no sistema, esgotar o espaço leva tempo geológico; combinado com a
expiração de 48h, a probabilidade de acertar um código VÁLIDO na janela é desprezível.
O custo de brute-force fica documentado no EXECUCAO.

**Armadilha registrada.** A regex existente `ACCEPT_PATH` de rack-attack
(`/invitations/[^/]+/accept`) TAMBÉM casa `/invitations/code/accept` — então os
throttles do token (accept-ip 10/10) também incidem sobre o accept por código. Isso é
benigno (o teto mais apertado do código, 5/10, é o que morde primeiro); registrado para
não surpreender. O log do token nesse caso registra `token_sha256 = sha256("code")` —
inócuo.

### D9 — Código em claro só existe UMA vez, na criação

**Decisão.** `CreateService`, ao criar o convite com código, gera o claro uma vez,
guarda o `code_hash`, seta `code_expires_at`, e retorna o claro na resposta (`short_code`
na entity SÓ na criação). Depois disso a entity nunca reexpõe o claro — exatamente como
o token, que só vive embutido no `invite_url`. `RecordNotUnique` no `code_hash` →
retry de geração.

**Onde a invariante mora.** Na entity (`short_code` exposto só quando presente na
criação; `code_hash` NUNCA exposto) + no service (claro efêmero).

## Riscos / trade-offs

- **Entropia menor é dívida permanente.** Mitigada pela SOMA de defesas ativas + vínculo
  de e-mail; nenhuma isolada basta (registrado em D7).
- **Pepper é material de chave.** Se vazar, o `code_hash` volta a ser brute-forceável
  offline. Guardado em credentials/ENV, rotacionável, com guarda de boot (D2).
- **Duas expirações na mesma linha** (link 7d, código 48h): a UI precisa deixar claro
  qual venceu — `code_status` explícito na listagem e no diálogo.
- **Aceite por código não funciona offline** (mesma razão do token): a UI diz
  "conecte-se para aceitar".
