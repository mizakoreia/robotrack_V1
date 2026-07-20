## ADDED Requirements

### Requirement: Route-sweep bloqueante em CI

O sistema SHALL manter um spec que varre `Api::Root.routes` e falha se qualquer rota
não tiver `route_setting(:policy)` nem entrada correspondente em
`config/authorization/public_routes.yml`. A allowlist SHALL exigir `path`, `method` e
`reason` não-vazio por entrada, e o spec SHALL falhar também em entrada órfã — rota
listada que não existe mais (§4.1 inv. 1).

#### Scenario: Endpoint novo sem policy falha o CI

- **WHEN** um endpoint `GET /api/v1/workspaces/:workspace_id/gadgets` é montado em
  `api/v1/base.rb` sem `route_setting :policy`
- **THEN** `spec/authorization/route_sweep_spec.rb` SHALL falhar com mensagem contendo
  exatamente `GET /api/v1/workspaces/:workspace_id/gadgets`, uma rota por linha

#### Scenario: Allowlist sem motivo é inválida

- **WHEN** `public_routes.yml` recebe uma entrada com `path` e `method` mas `reason: ""`
- **THEN** o spec SHALL falhar apontando a entrada, mesmo que a rota exista

#### Scenario: Entrada órfã na allowlist falha

- **WHEN** a rota `POST /auth/v1/magic_login/request_code` é removida pelo
  `seal-template-baseline` mas continua listada em `public_routes.yml`
- **THEN** o spec SHALL falhar identificando a entrada órfã, impedindo acúmulo de
  permissão morta

#### Scenario: Sweep cobre 100% das rotas montadas

- **WHEN** o sweep roda com a API completa montada
- **THEN** a soma de (rotas com policy) + (rotas na allowlist) SHALL ser igual a
  `Api::Root.routes.size`, e o spec SHALL afirmar essa igualdade explicitamente

### Requirement: Suíte executável das 8 invariantes

O sistema SHALL manter `spec/authorization/invariants/` com exatamente 8 arquivos,
um por invariante da §4.1, nomeados `inv_1_..._spec.rb` a `inv_8_..._spec.rb`, cada
um provando sua invariante ponta a ponta por HTTP (não por unit test de policy
object). A suíte SHALL ser executável isoladamente com um único comando e SHALL ser
o critério de aceite do porte de autorização.

#### Scenario: As 8 invariantes rodam num comando

- **WHEN** `bundle exec rspec spec/authorization/invariants` é executado
- **THEN** o resultado SHALL reportar 8 grupos de exemplo, um por invariante, com o
  número da invariante no nome do grupo

#### Scenario: Invariante sem arquivo falha o meta-spec

- **WHEN** o arquivo `inv_5_owner_immutable_spec.rb` é excluído
- **THEN** `spec/authorization/invariants_completeness_spec.rb` SHALL falhar por
  contar 7 arquivos em vez de 8

#### Scenario: Invariante 3 falha se o REVOKE não estiver ativo

- **WHEN** a suíte roda contra um banco onde `audit_logs` ainda aceita
  `UPDATE`/`DELETE` do papel da aplicação
- **THEN** `inv_3` SHALL falhar, mesmo que nenhuma rota de escrita de log exista —
  a prova é do banco, não da API

#### Scenario: Invariante 8 falha se o CHECK de 500 chars não existir

- **WHEN** uma notificação é criada com `message` de **501** caracteres via `INSERT`
  direto
- **THEN** `inv_8` SHALL falhar caso a linha seja aceita, e SHALL passar quando o
  Postgres rejeitar por `CHECK char_length(message) <= 500`

#### Scenario: Invariante 8 falha se read nasce true

- **WHEN** uma notificação é criada pela API sem o campo `read` no corpo
- **THEN** a linha persistida SHALL ter `read = false`; e se o corpo enviar
  `"read": true`, o valor persistido SHALL ainda ser `false`

#### Scenario: Pending sem motivo é proibido

- **WHEN** `inv_6` é marcada `pending` porque `workspace-invitations` ainda não existe,
  sem texto de motivo
- **THEN** o meta-spec SHALL falhar; a marcação SHALL exigir motivo nomeando a
  capacidade responsável, ex.: `pending: "bloqueada por workspace-invitations"`

### Requirement: Varredura negativa de vazamento entre tenants

O sistema SHALL gerar, a partir da mesma tabela de rotas do sweep, um exemplo por
endpoint que recebe id de recurso, autenticando como membro do workspace **WS-B** e
endereçando recurso semeado em **WS-A**, exigindo `404`. Endpoint que o gerador não
cobrir SHALL constar de `config/authorization/cross_tenant_overrides.yml`; endpoint
sem gerador **e** sem override SHALL falhar o spec.

#### Scenario: Todo endpoint com id tem prova negativa

- **WHEN** a varredura roda sobre a API completa
- **THEN** para cada rota cujo path contém `:id` ou `:*_id` SHALL existir um exemplo
  executado, e a contagem de exemplos SHALL ser reportada e comparada com a contagem
  de rotas elegíveis

#### Scenario: Endpoint novo sem override e sem gerador falha

- **WHEN** um endpoint identifica o recurso por corpo (`POST .../bulk_delete` com
  `{"ids": [...]}`), fora do alcance do gerador, e não é listado no override
- **THEN** o spec SHALL falhar nomeando a rota

#### Scenario: Vazamento em rota de escrita é detectado

- **WHEN** um `PATCH .../robots/:id` é implementado com `Robot.find(params[:id])` sem
  escopo de workspace, e Diego (WS-B) o chama com `R-A1`
- **THEN** a varredura SHALL falhar por receber `200` onde esperava `404`, e `R-A1`
  SHALL ter sido alterado — o teste é o que impede o merge

#### Scenario: Listagem não vaza contagem de outro tenant

- **WHEN** Diego faz `GET /api/v1/workspaces/WS-B/projects` num banco com 12 projetos
  em WS-A e 3 em WS-B
- **THEN** o corpo SHALL ter 3 itens e o header `X-Total-Count` SHALL ser `3`

### Requirement: Checklist de paridade com firestore.rules

O sistema SHALL manter `config/authorization/legacy_parity.yml` com uma entrada por
declaração `allow` de `/Users/mizaelfelippe/Documents/GitHub/RoboTrack/firestore.rules`,
identificada por match path, verbo e número de linha. Cada entrada SHALL ter **ou** o
id de um exemplo RSpec que a cobre, **ou** um campo `divergence` com justificativa em
texto. O spec de paridade SHALL falhar se alguma entrada não tiver nenhum dos dois.

#### Scenario: Entrada sem cobertura nem divergência falha

- **WHEN** a entrada correspondente a `notifications` `allow update` (L61-62) fica sem
  `covered_by` e sem `divergence`
- **THEN** `spec/authorization/legacy_parity_spec.rb` SHALL falhar citando a linha 61

#### Scenario: Divergência de endurecimento é registrada, não silenciada

- **WHEN** a entrada de L61-62 declara
  `divergence: "rule legada permitia marcar notificação alheia como lida; §4.1 inv. 4 exige a própria"`
- **THEN** o spec SHALL passar para essa entrada e o texto SHALL aparecer no relatório
  impresso pelo spec

#### Scenario: Regra de dono inferido por uid é marcada como divergente

- **WHEN** a entrada de `workspaces` `allow update` (L18-19), que inferia dono de
  `request.auth.uid == wsId`, é avaliada
- **THEN** ela SHALL constar como divergência apontando que o porte deriva `owner` de
  `memberships.role`, conforme §4.1 inv. 2

#### Scenario: Contagem de allows confere

- **WHEN** o spec conta as declarações `allow` do arquivo legado
- **THEN** o número SHALL ser igual ao número de entradas do YAML, de modo que uma
  rule não coberta não possa ser omitida por esquecimento

### Requirement: Job de CI dedicado à autorização

O sistema SHALL executar `spec/authorization/` como job de CI separado e bloqueante,
distinto da suíte geral, para que uma falha de autorização apareça nomeada e não
diluída entre os demais testes. Citado como dependência de
`delivery-and-observability`.

#### Scenario: Job falha independentemente do restante da suíte

- **WHEN** o route-sweep falha e todos os outros 400 testes passam
- **THEN** o pipeline SHALL ficar vermelho no job `authorization` e o merge SHALL ser
  bloqueado

#### Scenario: Flag de enforcement não pode ficar desligada em test

- **WHEN** `AUTHZ_ENFORCE` está ausente ou `0` no ambiente `test`
- **THEN** um spec SHALL falhar afirmando que o enforcement está ligado, impedindo que
  a fase de rollout faseado se torne permanente
