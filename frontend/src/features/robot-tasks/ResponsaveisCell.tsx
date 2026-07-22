import { useState } from 'react'
import { Icon } from '@/components/icons/Icon'
import { Chip } from '@/components/ui/Chip'
import { AssignmentModal } from './AssignmentModal'
import { robotTaskText } from '@/lib/i18n/robotTasks'
import type { TaskDTO } from '@/lib/api/endpoints'

// robot-task-table 3.1/3.3 (§3.5, D-RTT-4/7) — a célula Responsáveis.
//
// D-RTT-4: `assignees` (responsáveis AGORA) e `contributors` (quem já avançou) são
// conjuntos distintos. Chips PRIMÁRIOS = assignees; SECUNDÁRIOS = contributors
// MENOS a intersecção (quem é os dois aparece só uma vez, na forma primária). A
// subtração é a única lógica de conjunto do cliente (D-RTT-4).
//
// D-RTT-7: o aviso "Atribuir…" (progress > 0 AND assignees = []) é ADORNO não
// bloqueante DENTRO da célula, com ícone + texto (nunca só o ícone). A célula
// inteira é o botão que abre o modal de atribuição — por isso o aviso é conteúdo
// do botão, não um `<button>` aninhado (HTML inválido).
//
// O `<Chip>` do design-system não tem prop `variant`; a distinção 1º/2º é por
// `className` (secundário = contorno esmaecido). Registrado na EXECUCAO.

function secondaryContributors(task: TaskDTO) {
  const assigneeIds = new Set(task.assignees.map((a) => a.id))
  return task.contributors.filter((c) => !assigneeIds.has(c.id))
}

export function ResponsaveisCell({ task }: { task: TaskDTO }) {
  const [open, setOpen] = useState(false)
  const secondary = secondaryContributors(task)
  const showWarning = task.progress > 0 && task.assignees.length === 0

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        aria-label={robotTaskText.openAssignAria(task.desc)}
        className="flex w-full flex-wrap items-center gap-1.5 rounded-md py-1 text-left hover:bg-accent/5"
      >
        {task.assignees.map((a) => (
          <Chip key={`a-${a.id}`} label={a.name} />
        ))}
        {secondary.map((c) => (
          <Chip
            key={`c-${c.id}`}
            label={c.name}
            className="border border-current/25 bg-transparent text-text-muted"
          />
        ))}

        {showWarning ? (
          <span className="label-md inline-flex items-center gap-1 font-medium text-warning-ink">
            <Icon name="alert" size="sm" />
            {robotTaskText.assignWarning}
          </span>
        ) : (
          task.assignees.length === 0 &&
          secondary.length === 0 && <span className="text-text-muted">{robotTaskText.noAssignees}</span>
        )}
      </button>

      {open && <AssignmentModal task={task} onClose={() => setOpen(false)} />}
    </>
  )
}
