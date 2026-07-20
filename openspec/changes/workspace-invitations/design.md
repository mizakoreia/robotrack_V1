## Context

O legado é Firestore. O convite vive em `/invites/{token}` — a **chave do documento
é o token**, e o token vai na URL. As regras (`firestore.rules` 67–82) permitem:

- `get` a qualquer usuário autenticado (é assim que o convidado lê o convite antes
  de aceitar);
- `list` só ao criador (`resource.data.createdBy == request.auth.uid`);
- `create` só com `createdBy == uid`, **`wsId == uid`** (invariante 7 — no legado o
  id do workspace *é* o uid do dono, então "workspace do próprio criador" e "sou o
  dono" colapsam na mesma condição), `used == false`, `role in ['view','edit']`,
  `email is string` e `email.size() <= 254`;
- `update` **só** na transição `used: false → true`, e só se
  `resource.data.email == request.auth.token.email.lower()`;
- `delete` só ao criador (é a revogação).

E o `create` de `workspaces/{wsId}/members/{memberUid}` (26–34) repete o dossiê
inteiro do convite como pré-condição: existe, `used == false`, `wsId` bate,
`email == myEmail()`, `role` do convite **igual** ao `role` que está sendo gravado
na membership, e `expiresAt` ausente **ou** maior que `request.time.toMillis()`.

Duas observações que a prosa da §3.10 não tem e as regras têm:

1. O legado só compara `email` com `request.auth.token.email.lower()` — ou seja,
   **e-mail do convite é armazenado já em minúsculas**, sem normalização no
   momento da comparação. Portar isso significa normalizar na escrita, não na
   leitura.
2. `expiresAt` é **opcional** nas regras (`!('expiresAt' in ...)`) — convites
   antigos, criados antes da introdução da expiração, nunca expiram. Isso é um
   bug do legado que não portamos: `expires_at` é `NOT NULL` no destino.

E a falha estrutural do legado: **isso não é atômico.** Marcar o convite como usado
e criar a membership são duas escritas em coleções diferentes, avaliadas
independentemente pelas rules. Dois clientes com o mesmo link, em corrida, podem
ambos passar no `create` da membership antes de qualquer `update` do convite
acontecer. O Firestore não oferece transação de segurança — as rules avaliam o
estado no momento da requisição. A invariante 6 é, no legado, uma **intenção não
garantida**. No destino ela vira garantia real.

Contexto do template (ai9): Grape em `app/controllers/api/`, services singleton com
`ApiResponseHandler` retornando `{success:, data:, status:}`, rotas públicas por
allowlist de regex em `api/root.rb`, PKs uuid em tabelas novas (D1/D13), Sidekiq
configurado, ActionCable com canal por `identified_by :current_user`.

## Goals / Non-Goals

**Goals**

- Invariante 6 garantida por **transação + índice único parcial + CHECK constraint**,
  de forma que nem um bug de service nem o console do Rails consigam produzir duas
  memberships a partir de um token.
- Invariante 7 garantida por **policy + validação de model + constraint de
  integridade referencial**, de forma que um convite não possa apontar para um
  workspace do qual o criador não é dono.
- Aceite de convite como um dos dois pontos de criação de `Person` (D10), com
  casamento por e-mail explícito e testado.
- Painel de equipe e revogação em tempo real conforme §3.10.
- Caminho negativo completo: e-mail divergente, token usado, expirado, papel
  adulterado, workspace alheio, `edit` tentando convidar, corrida entre dois
  consumos.

**Non-Goals**

- Envio de e-mail (ver proposal.md → Não-objetivos).
- Convite para papel `owner`; transferência de propriedade.
- Convite por link "aberto" (qualquer pessoa com o link entra). §3.10 amarra o
  convite a um e-mail exato; um link aberto seria outra feature, com outro modelo
  de ameaça.
- Reenvio/renovação de convite expirado. O dono revoga e cria outro — um convite
  é imutável depois de criado, exceto pela transição de consumo. Isso mantém a
  invariante 6 simples: não existe convite cujo `role` ou `email` mudou depois de
  o link ter sido distribuído.

## Decisions

### D-INV-1 — O token é uma coluna única e opaca, não a PK

A PK é `uuid` (D1/D13, uniforme com todo o resto do domínio). O `token` é uma
**coluna separada**, `text NOT NULL`, com índice único, gerada como
`SecureRandom.urlsafe_base64(32)` (256 bits de entropia, ~43 chars URL-safe).

*Alternativa descartada:* usar o token como PK, espelhando o legado
(`/invites/{token}`). Descartada porque quebra a uniformidade de D1 (todo FK do
domínio é uuid), impede geração no cliente e, principalmente, porque o token é um
**segredo** — segredos não devem ser PKs referenciadas por FKs em logs de
auditoria e em `used_by`. Separando, podemos revogar/rotacionar o segredo sem
tocar nas referências.

*Alternativa descartada:* uuid como token. Descartada porque uuidv4 tem 122 bits
e é reconhecível como uuid; o token vai numa URL que pode vazar por referrer e
histórico. 256 bits com prefixo próprio (`rt_inv_`) é mais barato de rotacionar
e mais fácil de detectar em varredura de segredos.

**Onde mora:** `CREATE UNIQUE INDEX idx_invitations_token ON invitations (token)`.

### D-INV-2 — A atomicidade do consumo mora em três camadas, não numa

Esta é a decisão central do change. A invariante 6 é expressa **três vezes**, em
níveis de contorno decrescente:

1. **Transação + lock pessimista** (`Invitations::AcceptService`):
   ```
   Invitation.transaction do
     inv = Invitation.lock('FOR UPDATE').find_by!(token: token)
     # 6 validações — ver D-INV-3
     person = resolve_or_create_person(inv, current_user)
     Membership.create!(workspace: inv.workspace, person:, role: inv.role,
                        invitation: inv)
     inv.update!(used_at: Time.current, used_by_user_id: current_user.id)
   end
   ```
   O `FOR UPDATE` serializa dois consumos concorrentes do **mesmo token**: o
   segundo bloqueia até o primeiro commitar, relê a linha já com `used_at`
   preenchido e falha na validação "não usado".

2. **Índice único parcial** — impede que o mesmo convite produza duas memberships,
   mesmo que alguém contorne o service:
   ```sql
   ALTER TABLE memberships ADD COLUMN invitation_id uuid
     REFERENCES invitations(id) ON DELETE RESTRICT;
   CREATE UNIQUE INDEX idx_memberships_one_per_invitation
     ON memberships (invitation_id) WHERE invitation_id IS NOT NULL;
   ```
   Duas transações que passassem simultaneamente pelo lock (impossível com
   `FOR UPDATE`, mas o índice é a rede) colidem em `unique_violation`. O service
   traduz `ActiveRecord::RecordNotUnique` para o mesmo erro de "convite já usado".

3. **CHECK constraint de coerência dos campos de consumo** — impede o estado
   meio-consumido:
   ```sql
   ALTER TABLE invitations ADD CONSTRAINT chk_invitations_consumption
     CHECK ((used_at IS NULL AND used_by_user_id IS NULL)
         OR (used_at IS NOT NULL AND used_by_user_id IS NOT NULL));
   ```

*Alternativa descartada:* apenas `lock_version` otimista. Descartada porque a
corrida aqui não é "dois updates no mesmo registro" e sim "duas criações derivadas
de um registro"; o otimista detectaria o segundo `update` do convite, mas a
segunda membership já teria sido criada e commitada num ponto anterior da
transação — a menos que se ordenasse a escrita do convite antes, o que só desloca
o problema. `FOR UPDATE` + índice único é mais curto e prova a propriedade.

*Alternativa descartada:* advisory lock por token (`pg_advisory_xact_lock`).
Descartada por ser redundante: a linha do convite já existe e já pode ser
travada; advisory lock só seria necessário se o recurso disputado não tivesse
linha própria.

*Alternativa descartada:* `used` booleano espelhando o legado. Descartada em favor
de `used_at timestamptz NULL` — carrega a mesma informação (`used = used_at IS NOT NULL`)
mais a auditoria de quando, e permite o índice único parcial de pendentes (D-INV-4).

**Corrida entre dois consumos do mesmo token:** o primeiro a adquirir o `FOR UPDATE`
vence, cria membership + `Person` (se necessário) e marca `used_at`. O segundo
desbloqueia, relê `used_at IS NOT NULL` e recebe **`409 Conflict`** com código
`invitation_already_used`. Nunca `500`, nunca duas memberships, nunca duas
`Person` para o mesmo e-mail. Existe um spec dedicado que dispara as duas threads
contra o mesmo token (ver tasks 3.5).

### D-INV-3 — As seis validações do consumo, portadas linha a linha

Dentro da transação, na ordem, com o mapeamento explícito para `firestore.rules`:

| # | Condição | Origem (rules) | Falha |
|---|---|---|---|
| 1 | token existe | `exists(/invites/$(token))` L28 | `404 invitation_not_found` |
| 2 | `used_at IS NULL` | `.data.used == false` L29 | `409 invitation_already_used` |
| 3 | `expires_at > now()` | `expiresAt > request.time.toMillis()` L33-34 | `410 invitation_expired` |
| 4 | `invitation.workspace_id == membership.workspace_id` | `.data.wsId == wsId` L30 | `422 invitation_workspace_mismatch` |
| 5 | `invitation.email == current_user.email.downcase` | `.data.email == myEmail()` L31 | `403 invitation_email_mismatch` |
| 6 | `role` criado == `invitation.role` | `.data.role == request.resource.data.role` L32 | `422 invitation_role_mismatch` |

A condição 6 no destino é **estrutural, não comparativa**: o cliente não envia
`role` no aceite. O `role` da membership é lido do convite. Isso elimina a classe
inteira de "papel adulterado". Mesmo assim, o endpoint **rejeita** um `role` no
corpo da requisição (`422 unexpected_parameter`) em vez de ignorá-lo em silêncio
— ignorar deixaria um atacante crendo que teve sucesso e esconderia a tentativa
do log.

A condição 3 **não** replica a tolerância do legado (`!('expiresAt' in ...)`):
`expires_at` é `NOT NULL DEFAULT now() + interval '7 days'`. Convite sem
expiração não é representável no destino.

A condição 5 compara com `current_user.email.downcase`. O e-mail do convite é
normalizado na **escrita** (`before_validation { self.email = email.to_s.strip.downcase }`),
mais `CHECK (email = lower(email))` — para que uma inserção por console também
não consiga criar um convite com e-mail em maiúsculas que nunca casaria. Sem
normalização Unicode adicional e **sem** tratamento de aliases (`user+tag@`,
pontos do Gmail): o e-mail é comparado literalmente, como no legado. Casar
aliases criaria um caminho de escalonamento — quem controla `a+x@dom` não
necessariamente controla `a@dom`.

### D-INV-4 — Invariante 7 mora em policy + validação + constraint composta

"Convite só aponta para o workspace do próprio criador, papel em `view`/`edit`":

- **Papel**: enum Postgres `invitation_role` (`'view'`,`'edit'`). `owner` não é um
  valor representável na coluna. Isso é mais forte que o `role in ['view','edit']`
  das rules, que é só uma checagem de valor.
- **Workspace do criador**: no legado, `wsId == request.auth.uid` porque o id do
  workspace *é* o uid do dono. No destino essa identidade não existe — precisamos
  da checagem explícita. Mora em **`InvitationPolicy.create?`** (D3), que exige
  membership `owner` do `current_person` naquele `workspace_id`, **mais** uma FK
  composta que impede que o criador seja de outro workspace:
  ```sql
  ALTER TABLE invitations
    ADD CONSTRAINT fk_invitations_creator_in_workspace
    FOREIGN KEY (workspace_id, created_by_person_id)
    REFERENCES people (workspace_id, id);
  ```
  (requer índice único `people (workspace_id, id)`, que `workspace-tenancy` já
  cria para as FKs compostas de D2.)
  A FK composta não sabe se o criador é `owner` — só que ele pertence ao
  workspace. O "é owner" fica na policy e num teste de integração dedicado.

*Alternativa descartada:* trigger `BEFORE INSERT` consultando `memberships` para
exigir `role = 'owner'`. Descartada porque o papel é mutável (o dono pode ser
rebaixado? não — invariante 5 diz que o dono é imutável), mas principalmente
porque um trigger que faz `SELECT` em outra tabela em cada insert de convite é
custo permanente para uma tabela de baixo volume; a policy + o route-sweep de D3
cobrem, e há teste negativo explícito.

**RLS (D2)**: `invitations` tem `workspace_id NOT NULL` e política RLS por
`app.current_workspace_id`, como toda tabela de domínio. **Exceção deliberada:**
a leitura pública do convite pelo token (pré-login) e o aceite acontecem **fora**
de um workspace corrente — o usuário ainda não é membro. Esses dois caminhos usam
um role de banco dedicado com `BYPASSRLS` ausente e uma política RLS extra
`USING (true)` restrita ao acesso **por token exato** através de uma função
`SECURITY DEFINER` `invitation_by_token(text)`. Nunca há listagem sem workspace.

### D-INV-5 — O aceite é um dos dois pontos que criam `Person` (D10)

Dependência dura de `workspace-tenancy`. Algoritmo, dentro da mesma transação:

1. Procura `Person` no `invitation.workspace_id` com `email = invitation.email`
   **e `user_id IS NULL`** → é alguém que o dono já cadastrou como responsável de
   chão de fábrica; preenche `person.user_id = current_user.id`. Isso preserva
   todo o histórico de atribuições daquela pessoa.
2. Se existe `Person` com aquele e-mail e `user_id` **já preenchido e diferente**
   → `409 person_email_conflict`. Não sobrescrevemos vínculo de conta.
3. Se não existe → cria `Person` nova com `workspace_id`, `email`,
   `user_id = current_user.id`, `name = current_user.display_name`.

O casamento é por e-mail, **não por nome** — nomes não são únicos e D11 já aboliu
o sentinela `"Não Atribuído"`. Se `workspace-tenancy` não expuser
`people.email`, este change está bloqueado; a coluna é requisito declarado
(task 1.1 verifica).

*Alternativa descartada:* criar sempre uma `Person` nova no aceite. Descartada
porque produz duplicata para o caso mais comum do produto: o dono cadastra "João
Silva, joao@fabrica.com" como responsável, atribui tarefas, e só depois convida.
Duas `Person` significam histórico partido e "Minhas Tarefas" vazio.

### D-INV-6 — O token chega pré-login; o aceite é pós-autenticação

Fluxo, com a fronteira com `identity-and-auth` (D4) explícita:

1. `GET /convite/:token` no frontend. Rota **pública**.
2. O cliente grava o token em `sessionStorage` (mecanismo de D4 — sobrevive ao
   redirect do Google OAuth, que é redirect e não popup exatamente por isto).
3. `GET /api/v1/invitations/:token` (rota pública, na allowlist de regex de
   `api/root.rb`) devolve **apenas** `{ workspace_name, role, email_masked,
   expires_at, status }`. `email_masked` = `j***@fabrica.com`. Nunca o e-mail
   completo, nunca o id do workspace, nunca a lista de membros — o token é
   endereçável por quem o tiver, e vazar o e-mail completo de um convite
   entrega um alvo de phishing.
4. Usuário autentica (login ou cadastro).
5. O shell, ao montar autenticado, vê o token em `sessionStorage` e dispara
   `POST /api/v1/invitations/:token/accept` (sem corpo). Limpa `sessionStorage`
   **em qualquer desfecho**, sucesso ou erro — senão o erro se repete a cada
   navegação.
6. Se o e-mail autenticado ≠ e-mail do convite: mensagem explícita nomeando o
   e-mail mascarado do convite e oferecendo "sair e entrar com outra conta". Não
   fazemos logout automático.

### D-INV-7 — Revogação em tempo real: evento + fallback por 403

§3.10 exige detectar a perda de acesso **enquanto** o usuário está no workspace.
Dois caminhos, e o segundo funciona sozinho:

- **Empurrado**: ao remover uma membership, o backend publica
  `{ type: 'membership_revoked', workspace_id, person_id }` no `WorkspaceChannel`
  (D6, de `realtime-collaboration`). O cliente do usuário afetado reage
  imediatamente.
- **Puxado (fallback)**: o interceptor de resposta do `apiClient` já existe para
  401 (refresh single-flight). Adicionamos tratamento de **403 com código
  `workspace_access_revoked`**: qualquer requisição ao workspace corrente
  responde isso quando não há mais membership.

Em ambos os casos o cliente executa a mesma rotina única `handleAccessRevoked()`:
avisa (toast persistente, não auto-dismiss), remove o workspace do índice local
(o cache de UI de `workspace-tenancy`), **descarta o cache React Query com prefixo
`['ws', wsId]`** (D9 — sem isso, dados do workspace perdido continuam na tela) e
navega para o workspace próprio.

*Alternativa descartada:* só polling. Descartada porque §3.10 diz "detecta a
negação" — o gatilho natural é a própria negação, e polling adiciona tráfego
constante para um evento raro. O fallback por 403 já é o polling implícito do uso
normal do app.

*Alternativa descartada:* revogar o JWT do usuário removido. Descartada porque o
usuário pode ser membro de outros workspaces; invalidar a sessão inteira o
desloga de tudo. A denylist de D4 é para logout, não para revogação de tenancy.

### D-INV-8 — Rate limiting no aceite

O token tem 256 bits — força bruta é inviável por entropia, mas o endpoint de
aceite é o alvo natural de enumeração e o de maior custo (transação + lock). Teto
por **IP** e por **usuário autenticado**: 10 tentativas / 10 minutos, via
`Rack::Attack` (nova gem) com store Redis (já configurado para Sidekiq). Resposta
`429` com `Retry-After`. `GET /api/v1/invitations/:token` (público, pré-login) tem
teto mais apertado: 20 / 10 min por IP.

Emitir alerta ao ultrapassar o teto é de `delivery-and-observability` — aqui
apenas garantimos que o bloqueio produz log estruturado com o token **hasheado**,
nunca em claro.

### D-INV-9 — Expurgo

Job Sidekiq diário `Invitations::PurgeExpiredJob`: apaga convites com
`used_at IS NULL AND expires_at < now() - interval '30 days'`. Os **consumidos
não são apagados** — `memberships.invitation_id` os referencia com
`ON DELETE RESTRICT`, e essa referência é a prova auditável de por que aquela
pessoa tem acesso. A janela de 30 dias além da expiração existe para que um
usuário que clica num link velho receba `410 invitation_expired` (mensagem útil)
em vez de `404` (mensagem confusa) durante o período em que o link ainda circula.

### D-INV-10 — Painel de equipe

Componente `features/team/TeamPanel`, montado por `workspace-settings` (§3.9).
Duas listas: membros (`['ws', wsId, 'members']`) e convites pendentes
(`['ws', wsId, 'invitations']`). Só o `owner` vê os controles de mutação; `edit` e
`view` veem as listas em leitura — a UI é conveniência, o servidor é a segurança
(invariante 1).

Regras de mutação, todas em `MembershipPolicy`:
- Mudar papel: só `owner`, só entre `view` e `edit`, **nunca** para/de `owner`
  (invariante 5).
- Remover membro: só `owner`. O dono **não pode remover a si mesmo** —
  `422 cannot_remove_owner`; um workspace sem dono é irrecuperável.
- Revogar convite pendente: só `owner`, só se `used_at IS NULL`. Revogar é
  `DELETE` real (o legado também deleta, L81). Um convite consumido não é
  revogável — remova o membro.

## Risks / Trade-offs

- **`FOR UPDATE` sob carga.** Serializa consumos do mesmo token, que é
  exatamente o objetivo, e nada mais — tokens distintos não se bloqueiam. Risco
  real é o lock ser mantido durante a criação de `Person`; a transação é curta e
  toca 3 tabelas. Mitigação: `statement_timeout` explícito na transação e teste
  de carga com 50 aceites concorrentes de tokens distintos (task 3.6).
- **Dependência dura de `workspace-tenancy` para `people.email`.** Se aquela
  capacidade entregar `people` sem `email`, D-INV-5 é impossível e o aceite passa
  a criar sempre `Person` nova — a duplicata que D-INV-5 existe para evitar.
  Mitigação: task 1.1 é uma verificação bloqueante do contrato, antes de
  qualquer código.
- **Vazamento por referrer.** O token está na URL. Mitigação:
  `Referrer-Policy: no-referrer` na rota `/convite/:token`, e o frontend
  **substitui a URL** (`history.replaceState`) removendo o token assim que o
  grava em `sessionStorage`, para não deixá-lo no histórico do navegador.
- **`email_masked` ainda vaza estrutura.** `j***@fabrica.com` revela domínio e
  primeira letra. Aceito: sem nenhuma dica, o usuário que autenticou com a conta
  errada não tem como saber qual conta usar, e o erro vira um beco sem saída.
- **Revogação em tempo real depende de `realtime-collaboration` (Onda 8) para o
  caminho empurrado.** Esta capacidade é da Onda 3. Trade-off assumido: o
  fallback por 403 (D-INV-7) é entregue **agora** e é suficiente para satisfazer
  §3.10; o caminho empurrado é uma tarefa condicionada (5.3) que só melhora a
  latência da detecção. Sem isso, a capacidade ficaria bloqueada cinco ondas.
- **Sem envio de e-mail, o link pode ser distribuído por canal inseguro.** É o
  comportamento do legado e do produto. Mitigado pela amarração ao e-mail exato:
  quem recebe o link e não é o destinatário não consegue consumi-lo.
- **Aceite não funciona offline** e não entra na fila de D7. Enfileirar um aceite
  significaria aceitar um convite que pode ter expirado ou sido revogado no
  intervalo, e a resolução do conflito não teria resposta boa. A UI diz "conecte-se
  para aceitar o convite".

## Plano de migração

Não há dados legados de convite a migrar: convites são efêmeros (7 dias) e o
export do Firestore que `legacy-data-migration` consome não inclui `/invites`
(é coleção de topo, fora de `/workspaces/{ws}`). **As memberships existentes**
são migradas por `workspace-tenancy`, com `invitation_id NULL` — daí o índice
único ser **parcial** (`WHERE invitation_id IS NOT NULL`). Sem a cláusula parcial,
toda membership migrada colidiria em `NULL`... na verdade não colidiria (NULLs são
distintos no índice único do Postgres), mas a cláusula parcial documenta a
intenção e mantém o índice pequeno.

A migration é **puramente aditiva**: cria `invitations`, adiciona
`memberships.invitation_id` nullable. Nenhuma coluna removida, nenhum dado
destruído. Rollback = `DROP TABLE invitations` + `remove_column`.

## Perguntas em aberto

1. **`people.email` é único por workspace?** D-INV-5 assume que o casamento por
   e-mail é determinístico. Se `workspace-tenancy` permitir duas `Person` com o
   mesmo e-mail no mesmo workspace, o passo 1 precisa de desempate. Proposta:
   índice único parcial `people (workspace_id, lower(email)) WHERE email IS NOT NULL`
   — a decidir com o dono de D10.
2. **Um usuário pode ter convite pendente e membership ativa ao mesmo tempo?**
   Proposta: sim, mas o aceite retorna `409 already_member` sem consumir o token
   (deixa o convite pendente para revogação limpa pelo dono). A alternativa —
   consumir silenciosamente — esconde do dono que ele convidou alguém que já
   estava dentro.
3. **Dois convites pendentes para o mesmo e-mail no mesmo workspace?** Proposta:
   proibir, via índice único parcial
   `invitations (workspace_id, email) WHERE used_at IS NULL`. Criar um segundo
   convite retorna o primeiro, ou o dono revoga e recria. Precisa de confirmação
   de produto — o comportamento do legado é permitir N.
