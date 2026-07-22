// app-shell-navigation 1.2 (D9) — a factory TIPADA de query keys. Toda query de
// domínio começa com `['ws', wsId, …]`: o `wsId` no PRIMEIRO segmento é o que faz
// `queryClient.clear()` na troca de workspace ser a barreira de vazamento entre
// tenants (D-A), e é o alvo que `realtime-collaboration` (D6) invalida ao receber
// um evento. Chamar a factory sem `wsId` NÃO compila; não há mais array literal
// solto onde um typo em `'projects'` passe despercebido.
export const qk = {
  ws: (wsId: string) => ['ws', wsId] as const,
  projects: (wsId: string) => ['ws', wsId, 'projects'] as const,
  project: (wsId: string, id: string) => ['ws', wsId, 'project', id] as const,
  // hierarchy-screens D-I — os overviews agregados de cada tela.
  overview: (wsId: string) => ['ws', wsId, 'overview'] as const,
  projectOverview: (wsId: string, id: string) => ['ws', wsId, 'project', id, 'overview'] as const,
  cellOverview: (wsId: string, id: string) => ['ws', wsId, 'cell', id, 'overview'] as const,
  cells: (wsId: string, projectId: string) => ['ws', wsId, 'cells', projectId] as const,
  robot: (wsId: string, id: string) => ['ws', wsId, 'robot', id] as const,
  tasks: (wsId: string, robotId: string) => ['ws', wsId, 'robot', robotId, 'tasks'] as const,
  myTasks: (wsId: string) => ['ws', wsId, 'my-tasks'] as const,
  notifications: (wsId: string) => ['ws', wsId, 'notifications'] as const,
  search: (wsId: string, q: string) => ['ws', wsId, 'search', q] as const,
} as const

// Prefixos NÃO-domínio permitidos fora da forma `['ws', …]`: metadados globais
// (enum de aplicações), o índice de workspaces (que é pré-tenant, D-H), e auth.
const NON_DOMAIN_PREFIXES = new Set(['meta', 'workspaces', 'auth'])

// Uma key é válida se for de um prefixo não-domínio conhecido, OU se começar com
// `['ws', <tenant>, …]`. O guard checa a FORMA, não a segurança (a barreira de
// vazamento é o `clear()` na troca + o RLS do servidor). Por isso o tenant pode
// ser `null`/`undefined`: é a query DESABILITADA (`enabled: Boolean(wsId)`) antes
// de um workspace ser escolhido — forma correta, tenant ainda pendente, nunca
// busca dado. O que é rejeitado é a key SEM o prefixo `ws` (`['projects']` — o
// erro que o guard existe para pegar) e o tenant string VAZIO (`''` é bug real).
export function isValidQueryKey(key: unknown): boolean {
  if (!Array.isArray(key) || key.length === 0) return false
  if (typeof key[0] === 'string' && NON_DOMAIN_PREFIXES.has(key[0])) return true
  if (key[0] !== 'ws') return false
  const tenant = key[1]
  if (tenant === null || tenant === undefined) return true // query pendente (desabilitada)
  return typeof tenant === 'string' && tenant.length > 0
}

export function assertValidQueryKey(key: unknown): void {
  if (isValidQueryKey(key)) return
  throw new Error(
    `query key fora da convenção D9 (use a factory qk.* — ['ws', wsId, …]): ${JSON.stringify(key)}`,
  )
}
