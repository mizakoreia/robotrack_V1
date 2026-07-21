// task-catalog 6.2 (D9) — chaves de cache do catálogo de tarefas-base.
//
// UM lugar só, mesmo motivo de `hierarchyKeys`: `realtime-collaboration` vai
// invalidar exatamente estas chaves. O prefixo `['ws', wsId, ...]` é o que
// `accessRevoked` remove em bloco quando o acesso ao workspace é revogado.
//
// `robotApplications` é GLOBAL (não leva `wsId`): o enum é o mesmo para todo
// tenant e é buscado uma vez, com `staleTime` infinito. `robotTasks` é a chave
// que a sincronização invalida — ela pertence a `robot-tasks`/`robot-task-table`,
// e é reproduzida aqui apenas para a mutation de sync apontar para o mesmo lugar
// que aquela tela lê (divergir quebraria o refetch sem erro visível).
export const catalogKeys = {
  taskTemplates: (wsId: string | null) => ['ws', wsId, 'taskTemplates'] as const,
  robotApplications: () => ['meta', 'robotApplications'] as const,
  robotTasks: (wsId: string | null, robotId: string) =>
    ['ws', wsId, 'robot', robotId, 'tasks'] as const,
}
