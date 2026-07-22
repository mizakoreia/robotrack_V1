import { useRef, useState } from 'react'
import { Icon } from '@/components/icons/Icon'
import { AdvanceModal } from '@/features/advances/AdvanceModal'
import { HistoryModal } from './HistoryModal'
import { robotTaskText } from '@/lib/i18n/robotTasks'
import { useWorkspaceStore } from '@/store/workspaceStore'
import type { TaskDTO } from '@/lib/api/endpoints'

// robot-task-table 3.2/3.4 (§3.5, D-RTT-6/7) — a célula Trilha.
//
// Exibe o comentário do ÚLTIMO avanço (por `recorded_at`, já resolvido no servidor
// em `last_advance`) e um botão de contagem que abre o histórico. `aria-label`
// informa o número de entradas (só-ícone/número não basta).
//
// D-RTT-6: o aviso "Registre o avanço…" dispara em `0 < progress < 100 AND
// advances_count = 0`. A cláusula legada "nem nota" saiu — a nota `obs` do legado
// já virou 1 entrada `legacy` no importador, contada em `advances_count`; por isso
// uma tarefa migrada (advances_count = 1) NÃO mostra o aviso. NÃO trocar `>` por
// `>=`: progresso 100 sem avanços não é pendência de trilha.
//
// D-RTT-7: o aviso é botão que abre o modal de AVANÇO (registrar), distinto do
// botão de contagem que abre o HISTÓRICO. Ambos não bloqueiam nada. Para `view`
// (sem edição) o aviso vira adorno estático — o servidor é a garantia (403).

export function TrilhaCell({ robotId, task }: { robotId: string; task: TaskDTO }) {
  const role = useWorkspaceStore((s) => s.currentRoleLabel)
  const canEdit = role === 'owner' || role === 'edit'
  const [showHistory, setShowHistory] = useState(false)
  const [recording, setRecording] = useState(false)
  const recordRef = useRef<HTMLButtonElement>(null)

  const showWarning = task.progress > 0 && task.progress < 100 && task.advances_count === 0
  const comment = task.last_advance?.comment ?? task.last_comment

  return (
    <>
      <div className="flex flex-col items-start gap-1">
        {comment ? (
          <span className="text-text-muted">{comment}</span>
        ) : task.advances_count === 0 && !showWarning ? (
          <span className="text-text-muted">{robotTaskText.noTrail}</span>
        ) : null}

        {task.advances_count > 0 && (
          <button
            type="button"
            onClick={() => setShowHistory(true)}
            aria-label={robotTaskText.trailCountAria(task.advances_count, task.desc)}
            className="label-sm inline-flex items-center gap-1 rounded-md px-1.5 py-0.5 text-accent-ink hover:bg-accent/10"
          >
            <Icon name="list" size="sm" />
            {task.advances_count}
          </button>
        )}

        {showWarning &&
          (canEdit ? (
            <button
              ref={recordRef}
              type="button"
              onClick={() => setRecording(true)}
              className="label-md inline-flex items-center gap-1 rounded-md py-0.5 font-medium text-warning-ink hover:underline"
            >
              <Icon name="alert" size="sm" />
              {robotTaskText.trailWarning}
            </button>
          ) : (
            <span className="label-md inline-flex items-center gap-1 font-medium text-warning-ink">
              <Icon name="alert" size="sm" />
              {robotTaskText.trailWarning}
            </span>
          ))}
      </div>

      {showHistory && <HistoryModal task={task} onClose={() => setShowHistory(false)} />}
      {recording && (
        <AdvanceModal
          robotId={robotId}
          taskId={task.id}
          from={task.progress}
          initialTo={task.progress}
          lockVersion={task.lock_version}
          onDone={() => {
            setRecording(false)
            recordRef.current?.focus()
          }}
        />
      )}
    </>
  )
}
