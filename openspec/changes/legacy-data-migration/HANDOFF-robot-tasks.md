# Handoff de `robot-tasks` → `legacy-data-migration` (D-RT-2)

Nota deixada por `robot-tasks` (tarefa 6.3). Leia ANTES de escrever o importador
do `defaultTasks`/`tasks` legado.

## O esquema novo NÃO tem `resp`. A leitura tolerante é SUA, e só sua.

`robot-tasks` decidiu (D-RT-2) resolver o condicional pendente do plano antigo:

- A tabela `tasks` **não** tem coluna `resp` e nunca terá. Não existe grafia de
  compatibilidade no banco.
- **Nenhum** service de `robot-tasks` executa `resp = assignees[0] || "Não
  Atribuído"`. Essa regra de escrita retroativa do legado existia para manter um
  *leitor antigo* vivo durante a transição do PWA — e aqui não há leitor antigo:
  o Firestore é desligado num corte único.
- Responsável é `person_id` (tabela `task_assignees`), e ausência de responsável
  é **conjunto vazio**, nunca uma `Person` chamada `"Não Atribuído"`.

## O que o importador precisa fazer (a leitura tolerante de §1.4 item 1)

Sobre o **JSON de export** (nunca sobre uma linha do Postgres), para cada tarefa:

1. Se o documento legado tem `assignees` (lista de nomes), use-a.
2. Senão, se tem `resp` (string única) **e** `resp != "Não Atribuído"`, trate
   como `[resp]`.
3. Senão, conjunto vazio.

Depois, para cada nome resultante:

- Resolva **nome → `Person`** casando por nome normalizado dentro do workspace
  (`lower(btrim(name))`), criando `Person` com `user_id` nulo quando não houver
  correspondência.
- **Descarte `"Não Atribuído"`** (D11) — nunca crie uma `Person` com esse nome
  (o banco já barra: `people_name_not_sentinel` CHECK).
- Insira linhas em `task_assignees (task_id, person_id, workspace_id)`.
- Se um nome legado não resolver para nenhuma pessoa, a tarefa fica com **conjunto
  vazio** — nunca com um sentinela.

## Por que isto importa

Sem este handoff, o importador reintroduziria a gravação `resp = assignees[0] ||
"Não Atribuído"` que `robot-tasks` removeu — ressuscitando um nome como chave,
um segundo caminho de verdade sobre quem é responsável (que divergiria do join na
primeira atribuição múltipla) e o sentinela `"Não Atribuído"` como valor
persistido (quebrando o filtro de "Minhas Tarefas" §3.6 e a dedup de
destinatários de notificação §2.7).

## Contrato de esquema que você pode assumir como pronto

- `tasks (id, workspace_id, robot_id, cat, desc, weight, progress, status,
  position, lock_version)` com RLS forçada e índice único
  `(robot_id, lower(btrim(desc)))`.
- `task_assignees (id, workspace_id, task_id, person_id)` com FKs compostas por
  `workspace_id`, único `(task_id, person_id)`, CASCADE de `tasks`, RESTRICT de
  `people`, RLS forçada.
- `status` é o enum `task_status` (`Pendente`/`Em Andamento`/`Concluído`/`N/A`);
  grave os literais exatos, com acento.
