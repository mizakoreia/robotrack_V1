import { useRef, useState } from 'react'
import { StatusSelect, type StatusOption } from '@/components/ui/StatusSelect'
import { Badge, type BadgeStatus } from '@/components/ui/Badge'
import { AdvanceModal } from '@/features/advances/AdvanceModal'
import { deriveStatusTarget, type TaskStatus } from '@/features/advances/statusTarget'
import { useWorkspaceStore } from '@/store/workspaceStore'
import type { TaskDTO } from '@/lib/api/endpoints'

// robot-task-table 2.1 (§3.5, §2.2) — a célula de Status: o StatusSelect do
// design-system (chevron obrigatório) SEMPRE controlado pelo status PERSISTIDO.
// Escolher outra opção NÃO muda a pílula: abre o modal de avanço com o `para%`
// derivado da tabela-verdade (§2.2) e o envio leva `status` — a pílula só muda
// quando o servidor devolver a tarefa nova e a invalidação re-renderizar a linha.
// Cancelar simplesmente fecha: `value` nunca saiu do persistido, nada a desfazer.
//
// Para `view` (D-RTT-9, antecipado do 4.4 para não regredir a coerência da linha:
// o AdvanceControls ao lado já se remove) o controle NEM RENDERIZA — Badge
// estático, sem chevron, sem alvo morto. A garantia real é o 403 do servidor.

const STATUS_COLOR: Record<TaskStatus, BadgeStatus> = {
  Pendente: 'warning',
  'Em Andamento': 'accent',
  Concluído: 'success',
  'N/A': 'na',
}

const STATUS_OPTIONS: StatusOption[] = (
  ['Pendente', 'Em Andamento', 'Concluído', 'N/A'] as TaskStatus[]
).map((s) => ({ value: s, label: s }))

export function StatusCell({ robotId, task }: { robotId: string; task: TaskDTO }) {
  const role = useWorkspaceStore((s) => s.currentRoleLabel)
  const canEdit = role === 'owner' || role === 'edit'
  const [pending, setPending] = useState<TaskStatus | null>(null)
  const wrapRef = useRef<HTMLSpanElement>(null)

  if (!canEdit) {
    return <Badge status={STATUS_COLOR[task.status]}>{task.status}</Badge>
  }

  function close() {
    setPending(null)
    wrapRef.current?.querySelector('select')?.focus() // devolve o foco ao gatilho
  }

  return (
    <span ref={wrapRef}>
      <StatusSelect
        value={task.status}
        status={STATUS_COLOR[task.status]}
        options={STATUS_OPTIONS}
        aria-label={`Status de ${task.desc}`}
        onChange={(next) => {
          if (next !== task.status) setPending(next as TaskStatus)
        }}
      />
      {pending && (
        <AdvanceModal
          robotId={robotId}
          taskId={task.id}
          from={task.progress}
          initialTo={deriveStatusTarget(pending, task.progress)}
          toStatus={pending}
          lockVersion={task.lock_version}
          onDone={close}
        />
      )}
    </span>
  )
}
