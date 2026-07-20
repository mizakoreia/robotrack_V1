# Spec — `workspace-context-switching`

## ADDED Requirements

### Requirement: Seletor de workspace só existe com mais de um workspace

O sistema SHALL renderizar o seletor de workspace como controle apenas quando o índice de
workspaces do usuário contiver **mais de um** workspace. Com exatamente um, o nome do
workspace SHALL ser exibido como texto estático, sem chevron, sem `cursor: pointer` e
fora da ordem de tabulação.

#### Scenario: Usuário com um só workspace não vê o seletor

- **WHEN** o índice de workspaces do usuário contém 1 entrada, "Planta Betim"
- **THEN** a barra de topo exibe o texto "Planta Betim"
- **AND** não há elemento com `role="button"` nem chevron no contexto do workspace
- **AND** o elemento não é alcançável por `Tab`

#### Scenario: Usuário com dois workspaces vê o seletor

- **WHEN** o índice contém "Planta Betim" e "Planta Camaçari"
- **THEN** um controle com `aria-haspopup="menu"` e chevron é renderizado
- **AND** ele exibe o nome do workspace corrente

#### Scenario: Seletor desabilitado não é aceitável como alternativa

- **WHEN** o índice contém 1 entrada
- **THEN** nenhum elemento do contexto do workspace possui atributo `disabled` ou
  `aria-disabled` (o controle simplesmente não existe)

### Requirement: Badge de papel sempre rotulado e nunca confundível com controle

O sistema SHALL exibir o papel do usuário no workspace corrente como badge estático com
os rótulos exatos "Dono", "Editor" ou "Somente leitura". O badge MUST NOT ter chevron,
`cursor: pointer`, `role` interativo nem entrada na ordem de tabulação.

#### Scenario: Papel owner exibe "Dono"

- **WHEN** o papel do usuário no workspace corrente é `owner`
- **THEN** o badge exibe "Dono"

#### Scenario: Papel view exibe "Somente leitura"

- **WHEN** o papel do usuário no workspace corrente é `view`
- **THEN** o badge exibe "Somente leitura"

#### Scenario: Badge não é confundível com o seletor

- **WHEN** o seletor de workspace e o badge de papel estão lado a lado na barra de topo
- **THEN** o badge não possui chevron e não é alcançável por `Tab`
- **AND** o seletor possui chevron e é alcançável por `Tab`

#### Scenario: Papel ausente ou desconhecido não inventa permissão

- **WHEN** o índice de workspaces retorna uma entrada sem papel definido
- **THEN** o badge exibe "Somente leitura"
- **AND** nenhuma ação de escrita é habilitada com base nessa entrada

### Requirement: Troca de workspace descarta o estado anterior por completo

Ao trocar de workspace, o sistema SHALL executar, nesta ordem e antes de qualquer render
do novo workspace: fechar overlays abertos, cancelar as queries em voo, **limpar o cache
inteiro do React Query** (`clear()`) e resetar as fatias de UI escopadas por workspace.
O sistema MUST NOT usar invalidação seletiva como mecanismo de descarte.

#### Scenario: Nenhum registro do workspace anterior é exibido após a troca

- **WHEN** o usuário está em "Planta Betim" com a Visão Geral em cache contendo os
  projetos "Linha 3" e "Linha 5", e troca para "Planta Camaçari"
- **THEN** em nenhum momento após a troca o texto "Linha 3" ou "Linha 5" está presente no
  documento
- **AND** a tela exibe estado de carregamento até a chegada dos dados de "Planta Camaçari"

#### Scenario: O cache é limpo, não invalidado

- **WHEN** a troca de workspace é executada
- **THEN** `queryClient.clear()` é chamado exatamente uma vez
- **AND** `queryClient.invalidateQueries()` NÃO é chamado como parte da troca
- **AND** `queryClient.getQueryCache().getAll()` retorna lista vazia imediatamente após

#### Scenario: Queries em voo são canceladas antes da limpeza

- **WHEN** há uma query `['ws','betim','projects']` em voo e a troca para `camacari` é
  disparada
- **THEN** `cancelQueries()` é chamado antes de `clear()`

#### Scenario: Resposta atrasada do workspace anterior não repovoa o cache

- **WHEN** a troca para `camacari` já ocorreu e a resposta HTTP da query
  `['ws','betim','projects']` chega 300ms depois
- **THEN** nenhuma entrada com `wsId = 'betim'` é escrita no cache
- **AND** nada de "betim" é renderizado

#### Scenario: Filtros de UI do workspace anterior são resetados

- **WHEN** o usuário havia definido o filtro segmentado como "Em andamento" em "Planta
  Betim" e troca para "Planta Camaçari"
- **THEN** o filtro segmentado volta ao valor padrão

#### Scenario: Menus abertos são fechados na troca

- **WHEN** o menu do seletor está aberto e o usuário escolhe outro workspace
- **THEN** o menu fecha e nenhum overlay órfão permanece em `#rt-overlays`

#### Scenario: Troca navega para a Visão Geral do novo workspace

- **WHEN** o usuário está em `/projeto/8f2a` de "Planta Betim" e troca para "Planta
  Camaçari"
- **THEN** a rota corrente passa a ser `/`
- **AND** nenhuma requisição para `/projeto/8f2a` do workspace anterior é emitida

#### Scenario: Escolher o workspace já corrente não faz nada

- **WHEN** o workspace corrente é "Planta Betim" e o usuário escolhe "Planta Betim"
- **THEN** o menu fecha, `clear()` NÃO é chamado e nenhuma navegação ocorre

### Requirement: O índice de workspaces é cache de UI, nunca fonte de autorização

O sistema SHALL tratar o índice de workspaces e o papel exibido como conveniência de
interface. Nenhuma decisão de escrita MUST depender do papel local; a negação é sempre do
servidor (§4.1 inv. 1 e 2).

#### Scenario: Papel local adulterado não concede escrita

- **WHEN** o papel no store local é alterado de `view` para `owner` e o usuário aciona
  uma ação de escrita
- **THEN** a requisição é emitida normalmente e o servidor responde 403
- **AND** o erro é apresentado ao usuário, sem tratamento como falha de interface

#### Scenario: 403 numa ação exibida como permitida recarrega o índice

- **WHEN** a UI exibia papel "Editor" e uma mutation retorna 403
- **THEN** o índice de workspaces é recarregado do servidor
- **AND** o badge de papel é atualizado com a resposta do servidor

#### Scenario: Workspace removido do índice devolve o usuário ao próprio workspace

- **WHEN** o workspace corrente deixa de constar no índice recarregado
- **THEN** o sistema executa o descarte completo de estado e passa ao workspace próprio
  do usuário
- **AND** exibe aviso de que o acesso foi removido

#### Scenario: Usuário view não vê os gatilhos de escrita, mas isso é só conveniência

- **WHEN** o papel corrente é "Somente leitura"
- **THEN** o item "Adicionar usuário" do menu da conta não é renderizado
- **AND** uma requisição forjada a esse fluxo ainda é rejeitada pelo servidor

### Requirement: Índice de workspaces com falha ou vazio degrada sem quebrar a casca

O sistema SHALL renderizar a casca mesmo quando o índice de workspaces falhar ou vier
vazio, sem seletor e sem badge, e SHALL oferecer nova tentativa.

#### Scenario: Falha de rede no índice mantém a casca navegável

- **WHEN** a requisição do índice de workspaces retorna erro de rede
- **THEN** sidebar e topbar são renderizadas
- **AND** o contexto do workspace exibe um estado de erro com ação de nova tentativa
- **AND** nenhum nome de workspace é exibido

#### Scenario: Índice vazio não renderiza seletor

- **WHEN** o índice retorna 0 entradas
- **THEN** nenhum seletor e nenhum badge de papel são renderizados
