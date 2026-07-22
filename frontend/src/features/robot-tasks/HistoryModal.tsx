import { Modal } from '@/components/ui/Modal'
import { useTaskTrail } from './useTaskTrail'
import { robotTaskText } from '@/lib/i18n/robotTasks'
import type { TaskDTO } from '@/lib/api/endpoints'

// robot-task-table 5.1/5.2 (§3.5, §2.4 item 3, D8) — a timeline completa de avanços.
//
// Ordem pelo SERVIDOR (recorded_at DESC, created_at DESC, id DESC) — o cliente NÃO
// reordena; dois `recorded_at` iguais mantêm a mesma ordem entre recarregamentos.
// Cada entrada exibe autor, `de% → para%`, a data de AÇÃO (`recorded_at`, não
// `created_at` — D8) e o comentário. Entradas `legacy` ganham marcador. Um avanço
// `→100` sem comentário mostra marcador EXPLÍCITO de ausência ("sem comentário"),
// nunca herdando visualmente o texto da entrada vizinha (§2.4 item 3).
//
// A casca (focus trap, Esc devolve o foco ao gatilho) é o `Modal` do design-system.

export function HistoryModal({ task, onClose }: { task: TaskDTO; onClose: () => void }) {
  const { data: trail, isLoading, isError } = useTaskTrail(task.id, true)

  return (
    <Modal open onClose={onClose} title={robotTaskText.historyTitle}>
      {isLoading ? (
        <p className="text-text-muted">{robotTaskText.historyLoading}</p>
      ) : isError ? (
        <p className="text-danger-ink">{robotTaskText.historyLoadError}</p>
      ) : !trail || trail.length === 0 ? (
        <p className="text-text-muted">{robotTaskText.historyEmpty}</p>
      ) : (
        <ol className="space-y-3">
          {trail.map((a) => (
            <li key={a.id} className="border-l-2 border-accent/40 pl-3">
              <div className="flex flex-wrap items-center gap-2">
                <span className="font-medium">{a.author_name_snapshot}</span>
                <span className="label-sm tabular-nums text-text-muted">
                  {robotTaskText.historyFromTo(a.from_progress, a.to_progress)}
                </span>
                {a.legacy && (
                  <span className="label-sm rounded-pill bg-na/15 px-2 py-0.5 text-na-ink">
                    {robotTaskText.historyLegacy}
                  </span>
                )}
              </div>
              <time className="label-sm text-text-muted" dateTime={a.recorded_at}>
                {new Date(a.recorded_at).toLocaleString('pt-BR')}
              </time>
              {/* marcador explícito de ausência: não herda o comentário do vizinho */}
              {a.comment ? (
                <p className="mt-0.5 text-text-muted">{a.comment}</p>
              ) : (
                <p className="mt-0.5 italic text-text-muted/70">{robotTaskText.historyNoComment}</p>
              )}
            </li>
          ))}
        </ol>
      )}
    </Modal>
  )
}
