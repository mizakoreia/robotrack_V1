# Spec — `workspace-invitations` (consistência — G4)

Equipe/Convites hoje parecem "outro app": tokens legados, tipografia de template,
`window.confirm()` e `role="dialog"` sem semântica. A crítica marca como o pior ponto de
consistência (Nielsen 4 = 2/4, com 4 padrões distintos de confirmação de exclusão).

## ADDED Requirements

### Requirement: Equipe/Convites usam o design-system único

O sistema SHALL renderizar `TeamPanel` e `InviteDialog` com os tokens e a tipografia do
sistema (`text-text-muted`, `text-danger-ink`, `.panel-header`), e SHALL NÃO usar os
tokens legados de template (`text-muted-foreground`, `text-destructive`, `text-xl font-semibold`).

*Porquê: `text-destructive` (#ef4444) como texto de erro fica fora do gate de contraste; a
tipografia de template é a anti-referência "SaaS genérico".*

#### Scenario: as telas de time não usam tokens de template

- **WHEN** `TeamPanel` e `InviteDialog` renderizam
- **THEN** o texto muted usa `text-text-muted` e o erro usa `text-danger-ink`
- **AND** nenhuma classe `text-muted-foreground`, `text-destructive` ou `text-xl` permanece nesses arquivos

### Requirement: Um só padrão de confirmação de exclusão

O sistema SHALL confirmar remoção de membro e revogação de convite através do primitivo
`Modal`, e SHALL NÃO usar `window.confirm()` (diálogo do SO, não-temático, fora do
contrato do `Modal`).

*Porquê: `window.confirm()` é o 4º padrão de confirmação diferente no app; unificar reduz a
carga de consistência.*

#### Scenario: remover membro confirma via Modal

- **WHEN** o dono aciona remover um membro ou revogar um convite
- **THEN** a confirmação abre no primitivo `Modal` (portal + trap + Esc)
- **AND** nenhuma chamada a `window.confirm` permanece em `TeamPanel`

### Requirement: As duas telas "Equipe" são distinguíveis

O sistema SHALL dar títulos distintos às duas superfícies hoje ambas chamadas "Equipe" — a
de responsáveis atribuíveis (`PeoplePanel`) e a de membros/papéis/convites (`TeamPanel`) —
e cruzar link entre elas.

#### Scenario: os dois H2 não colidem

- **WHEN** as duas telas renderizam seus cabeçalhos
- **THEN** os títulos são distintos (ex.: "Responsáveis" vs. "Equipe")
- **AND** há um link cruzado de uma para a outra
