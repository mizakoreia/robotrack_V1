import { useQuery } from '@tanstack/react-query'
import { overviewApi } from '../../lib/api/endpoints'
import { qk } from '../../lib/query/keys'
import { useWorkspaceStore } from '../../store/workspaceStore'

// A feature reexpõe os tipos de VIEW dos overviews: as telas (em app/) consomem-nos
// daqui, não de `lib/api/endpoints` — a camada de API fica atrás dos hooks (D9, e o
// sweep de convenção reprova componente que importe `lib/api/*`).
export type {
  WorkspaceOverviewDTO,
  ProjectOverviewDTO,
  CellOverviewDTO,
  OverviewProjectCard,
  OverviewCellCard,
  OverviewRobotCard,
  RawCompletionEnvelope,
  WeightedEnvelope,
} from '../../lib/api/endpoints'

// hierarchy-screens 4.1 / 5.1 (D9, D-I) — os hooks de leitura dos overviews. Uma
// query por tela, key da factory (`['ws', wsId, 'overview']` etc.). O tipo do
// retorno separa `weighted_progress` (anel) de `raw_completion` (hub): não há campo
// `progress` genérico, então trocar um pelo outro na chamada NÃO compila (D15).
export function useWorkspaceOverview() {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  return useQuery({
    queryKey: qk.overview(wsId ?? '_'),
    queryFn: () => overviewApi.workspace(),
    enabled: Boolean(wsId),
  })
}

export function useProjectOverview(projectId: string | null) {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  return useQuery({
    queryKey: qk.projectOverview(wsId ?? '_', projectId ?? '_'),
    queryFn: () => overviewApi.project(projectId as string),
    enabled: Boolean(wsId && projectId),
  })
}

export function useCellOverview(cellId: string | null) {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  return useQuery({
    queryKey: qk.cellOverview(wsId ?? '_', cellId ?? '_'),
    queryFn: () => overviewApi.cell(cellId as string),
    enabled: Boolean(wsId && cellId),
  })
}
