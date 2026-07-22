import { useParams } from 'react-router-dom'
import { RobotTaskTablePage } from './RobotTaskTablePage'

// robot-task-table D-RTT-1 — a rota do robô é montada com `key={robotId}`: navegar de
// um robô a outro (e voltar ao mesmo) DESMONTA a árvore, garantindo o reset do filtro
// mesmo quando o `useEffect([robotId])` não redispara (mesmo id, árvore não desmontada).
export function RobotRouteKey() {
  const { id } = useParams<{ id: string }>()
  return <RobotTaskTablePage key={id} />
}
