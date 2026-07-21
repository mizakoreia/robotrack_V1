// progress-advances (D9) — a chave de cache da TRILHA de avanço de uma tarefa.
//
// Separada de `catalogKeys` de propósito: a trilha pertence a esta capacidade, e
// `realtime-collaboration` vai invalidar exatamente esta chave ao receber o
// evento `task.advanced`. O prefixo `['ws', wsId, ...]` é o que `accessRevoked`
// remove em bloco na revogação de acesso.
export const advanceKeys = {
  trail: (wsId: string | null, taskId: string) =>
    ['ws', wsId, 'task', taskId, 'advances'] as const,
}
