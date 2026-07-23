// realtime-collaboration 5.3 / D6.2, D6.3 — o mapa evento → query keys. O
// envelope é PONTEIRO (identidade + escopo, sem conteúdo): o cliente traduz o
// `type` para as chaves da convenção D9 (`['ws', wsId, …]`) e invalida; o React
// Query refaz o fetch pelas rotas normais (policy + RLS).
//
// EXAUSTIVO POR CONSTRUÇÃO: `Record<EventType, Mapper>` sobre uma união fechada —
// um `type` novo sem entrada aqui é erro de COMPILAÇÃO. Em runtime, um `type`
// DESCONHECIDO (envelope de uma versão futura do servidor) cai no handler que
// invalida `['ws', wsId]` inteiro e AVISA — nunca é engolido em silêncio.
//
// A cadeia de rollup sai do `scope`: como as chaves reais são aninhadas
// (`['ws',w,'project',p,'cells']`, `['ws',w,'cell',c,'robots']`,
// `['ws',w,'robot',r,'tasks']`), invalidar o PREFIXO do ancestral
// (`['ws',w,'cell',c]`) já casa a lista-filha por baixo — é por isso que o
// `scope` carrega os três ancestrais mesmo quando a entidade é uma tarefa: sem
// isso o anel de progresso (§2.1) fica velho enquanto a linha já atualizou (D15).

export type QueryKey = readonly unknown[]

export interface RealtimeScope {
  project_id?: string | null
  cell_id?: string | null
  robot_id?: string | null
}

export interface RealtimeEnvelope {
  v: number
  seq: number
  workspace_id: string
  type: string
  // `user_id` só vem em eventos de membership (8.1): é como o cliente sabe se a
  // revogação é dele. É identidade/ponteiro, não conteúdo.
  entity: { kind: string; id: string; user_id?: string } | null
  scope: RealtimeScope
  actor_person_id: string | null
  origin_id: string | null
  at: string
}

export type EventType =
  | 'project.created' | 'project.updated' | 'project.deleted' | 'project.reordered'
  | 'cell.created' | 'cell.updated' | 'cell.deleted' | 'cell.reordered'
  | 'robot.created' | 'robot.updated' | 'robot.deleted' | 'robot.reordered'
  | 'robot.batch_created'
  | 'task.created' | 'task.updated' | 'task.deleted' | 'task.assigned'
  | 'task_advance.created'
  | 'membership.created' | 'membership.role_changed' | 'membership.revoked'
  | 'notification.created'
  | 'workspace.updated' | 'workspace.reset'

type Mapper = (wsId: string, env: RealtimeEnvelope) => QueryKey[]

// Cadeia de rollup derivada do `scope` (do mais específico ao overview). Cada
// entrada é PREFIXO: `['ws',w,'cell',c]` invalida `cellOverview` E a lista
// `…,'robots']`; `['ws',w,'project',p]` invalida o projeto E `…,'cells']`;
// `['ws',w,'robot',r]` invalida o robô E `…,'tasks']`.
function rollup(w: string, s: RealtimeScope): QueryKey[] {
  const keys: QueryKey[] = []
  if (s.robot_id) keys.push(['ws', w, 'robot', s.robot_id])
  if (s.cell_id) keys.push(['ws', w, 'cell', s.cell_id])
  if (s.project_id) keys.push(['ws', w, 'project', s.project_id])
  keys.push(['ws', w, 'overview'])
  return keys
}

const project: Mapper = (w, e) => [['ws', w, 'projects'], ...rollup(w, e.scope)]
const cell: Mapper = (w, e) => rollup(w, e.scope)
const robot: Mapper = (w, e) => rollup(w, e.scope)
const robotBatch: Mapper = (w, e) => rollup(w, e.scope)
const task: Mapper = (w, e) => [['ws', w, 'my-tasks'], ...rollup(w, e.scope)]
const taskAdvance: Mapper = (w, e) => {
  const keys: QueryKey[] = [['ws', w, 'my-tasks'], ...rollup(w, e.scope)]
  if (e.entity?.id) keys.push(['ws', w, 'task', e.entity.id, 'advances'])
  return keys
}
// TeamPanel usa `['ws',w,'members']`/`['ws',w,'invitations']`; `people` é a chave
// do painel de Equipe de settings. Sem cadeia de rollup (escopo de workspace).
const membership: Mapper = (w) => [['ws', w, 'members'], ['ws', w, 'invitations'], ['ws', w, 'people']]
const notification: Mapper = (w) => [['ws', w, 'notifications']]
const workspaceWide: Mapper = (w) => [['ws', w]]

export const eventMap: Record<EventType, Mapper> = {
  'project.created': project,
  'project.updated': project,
  'project.deleted': project,
  'project.reordered': project,
  'cell.created': cell,
  'cell.updated': cell,
  'cell.deleted': cell,
  'cell.reordered': cell,
  'robot.created': robot,
  'robot.updated': robot,
  'robot.deleted': robot,
  'robot.reordered': robot,
  'robot.batch_created': robotBatch,
  'task.created': task,
  'task.updated': task,
  'task.deleted': task,
  'task.assigned': task,
  'task_advance.created': taskAdvance,
  'membership.created': membership,
  'membership.role_changed': membership,
  'membership.revoked': membership,
  'notification.created': notification,
  'workspace.updated': workspaceWide,
  'workspace.reset': workspaceWide,
}

// Traduz um envelope nas query keys a invalidar. Tipo desconhecido → subárvore
// inteira do workspace + aviso (nunca descarte silencioso).
export function keysForEvent(wsId: string, env: RealtimeEnvelope): QueryKey[] {
  const mapper = eventMap[env.type as EventType]
  if (!mapper) {
    // eslint-disable-next-line no-console
    console.warn(`[realtime] tipo de evento desconhecido "${env.type}" — invalidando ['ws', ${wsId}] inteiro`)
    return [['ws', wsId]]
  }
  return mapper(wsId, env)
}
