import { useEffect, useRef } from 'react'
import { Button } from '@/components/ui/Button'
import { robotTaskText } from '@/lib/i18n/robotTasks'
import type { TaskDTO } from '@/lib/api/endpoints'

// robot-task-table 3.2 (§3.5, D8) — o modal de histórico em sua forma MÍNIMA da
// G3: exibe a entrada MAIS RECENTE (`last_advance`, resolvida no servidor por
// `recorded_at DESC`), com autor, comentário, data de AÇÃO e marcador `legacy`. A
// G5 (5.1/5.2) troca isto pela timeline paginada completa (via
// `taskAdvancesApi.list`), com `de% → para%` por entrada. A casca é a definitiva.

export function HistoryModal({ task, onClose }: { task: TaskDTO; onClose: () => void }) {
  const ref = useRef<HTMLDivElement>(null)
  const last = task.last_advance

  useEffect(() => {
    ref.current?.focus()
  }, [])

  return (
    <div
      ref={ref}
      role="dialog"
      aria-modal="true"
      aria-label={`${robotTaskText.historyTitle}: ${task.desc}`}
      tabIndex={-1}
      onKeyDown={(e) => {
        if (e.key === 'Escape') {
          e.stopPropagation()
          onClose()
        }
      }}
      className="mt-2 rounded-lg border bg-background p-4"
    >
      <h3 className="font-medium">{robotTaskText.historyTitle}</h3>

      {last ? (
        <div className="mt-3 border-l-2 border-accent/40 pl-3">
          <div className="flex items-center gap-2">
            <span className="font-medium">{last.author_name_snapshot}</span>
            {last.legacy && (
              <span className="label-sm rounded-pill bg-na/15 px-2 py-0.5 text-na-ink">
                {robotTaskText.historyLegacy}
              </span>
            )}
          </div>
          <time className="label-sm text-text-muted" dateTime={last.recorded_at}>
            {new Date(last.recorded_at).toLocaleString('pt-BR')}
          </time>
          <p className="mt-1 text-text-muted">
            {last.comment ?? <em>{robotTaskText.historyNoComment}</em>}
          </p>
        </div>
      ) : (
        <p className="mt-3 text-text-muted">{robotTaskText.historyEmpty}</p>
      )}

      <p className="label-sm mt-3 text-text-muted">{robotTaskText.historyFullComing}</p>

      <div className="mt-4">
        <Button type="button" variant="outline" onClick={onClose}>
          {robotTaskText.close}
        </Button>
      </div>
    </div>
  )
}
