import { useEffect, useRef } from 'react'
import { Button } from '@/components/ui/Button'
import { Chip } from '@/components/ui/Chip'
import { robotTaskText } from '@/lib/i18n/robotTasks'
import type { TaskDTO } from '@/lib/api/endpoints'

// robot-task-table 3.1 (§3.5) — o modal de atribuição em sua forma MÍNIMA da G3:
// mostra, só-leitura, os responsáveis atuais (já "marcados") e os contribuidores.
// A G5 (5.3/5.4) substitui esta lista por checkboxes de TODAS as pessoas do
// workspace + cadastro de pessoa nova, salvando via PUT /tasks/:id/assignees. A
// casca (título, foco, Esc, Fechar) já é a definitiva — só o corpo cresce.

export function AssignmentModal({ task, onClose }: { task: TaskDTO; onClose: () => void }) {
  const ref = useRef<HTMLDivElement>(null)
  const assigneeIds = new Set(task.assignees.map((a) => a.id))
  const contributors = task.contributors.filter((c) => !assigneeIds.has(c.id))

  // Foco inicial no diálogo + `Esc` fecha (foco volta ao gatilho no pai via onClose).
  useEffect(() => {
    ref.current?.focus()
  }, [])

  return (
    <div
      ref={ref}
      role="dialog"
      aria-modal="true"
      aria-label={`${robotTaskText.assignTitle}: ${task.desc}`}
      tabIndex={-1}
      onKeyDown={(e) => {
        if (e.key === 'Escape') {
          e.stopPropagation()
          onClose()
        }
      }}
      className="mt-2 rounded-lg border bg-background p-4"
    >
      <h3 className="font-medium">{robotTaskText.assignTitle}</h3>

      <p className="label-sm mt-3 text-text-muted">{robotTaskText.assignResponsibles}</p>
      <div className="mt-1 flex flex-wrap gap-1.5">
        {task.assignees.length === 0 ? (
          <span className="text-text-muted">{robotTaskText.noAssignees}</span>
        ) : (
          task.assignees.map((a) => <Chip key={a.id} label={a.name} />)
        )}
      </div>

      {contributors.length > 0 && (
        <>
          <p className="label-sm mt-3 text-text-muted">{robotTaskText.assignContributors}</p>
          <div className="mt-1 flex flex-wrap gap-1.5">
            {contributors.map((c) => (
              <Chip key={c.id} label={c.name} className="border border-current/25 bg-transparent text-text-muted" />
            ))}
          </div>
        </>
      )}

      <p className="label-sm mt-3 text-text-muted">{robotTaskText.assignEditComing}</p>

      <div className="mt-4">
        <Button type="button" variant="outline" onClick={onClose}>
          {robotTaskText.close}
        </Button>
      </div>
    </div>
  )
}
