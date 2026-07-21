// commissioning-hierarchy 6.3 (D9) — as chaves de cache da hierarquia.
//
// UM lugar só, porque `realtime-collaboration` vai invalidar exatamente estas
// chaves quando o evento chegar: divergir delas quebra o tempo real SEM erro
// visível (a tela simplesmente não atualiza). O prefixo é sempre
// ['ws', wsId, ...] — o mesmo que `accessRevoked` remove em bloco quando o
// acesso ao workspace é revogado.
export const hierarchyKeys = {
  projects: (wsId: string | null) => ['ws', wsId, 'projects'] as const,
  cells: (wsId: string | null, projectId: string) => ['ws', wsId, 'project', projectId, 'cells'] as const,
  robots: (wsId: string | null, cellId: string) => ['ws', wsId, 'cell', cellId, 'robots'] as const,
}
