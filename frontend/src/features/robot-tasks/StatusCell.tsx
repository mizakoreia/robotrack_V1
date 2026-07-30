import { useRef, useState } from 'react'
import { StatusSelect, type StatusOption } from '@/components/ui/StatusSelect'
import { Badge, type BadgeStatus } from '@/components/ui/Badge'
import { AdvanceModal } from '@/features/advances/AdvanceModal'
import { deriveStatusTarget, type TaskStatus } from '@/features/advances/statusTarget'
import { useWorkspaceStore } from '@/store/workspaceStore'
import { statusLabel, baseTaskLabel } from '@/lib/i18n/dataLabels'
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

export const STATUS_COLOR: Record<TaskStatus, BadgeStatus> = {
  Pendente: 'warning',
  'Em Andamento': 'accent',
  Concluído: 'success',
  'N/A': 'na',
}

// internationalization G4/D-I4 — o VALUE continua o valor pt-BR do enum (é o que vai
// ao servidor); só o LABEL é traduzido na exibição. Construído no render (o remount por
// idioma re-executa) — um const de módulo congelaria em pt-BR.
const STATUS_VALUES: TaskStatus[] = ['Pendente', 'Em Andamento', 'Concluído', 'N/A']
const statusOptions = (): StatusOption[] => STATUS_VALUES.map((s) => ({ value: s, label: statusLabel(s) }))

export function StatusCell({ robotId, task }: { robotId: string; task: TaskDTO }) {
  const role = useWorkspaceStore((s) => s.currentRoleLabel)
  const canEdit = role === 'owner' || role === 'edit'
  const [pending, setPending] = useState<TaskStatus | null>(null)
  const wrapRef = useRef<HTMLSpanElement>(null)

  if (!canEdit) {
    return <Badge status={STATUS_COLOR[task.status]}>{statusLabel(task.status)}</Badge>
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
        options={statusOptions()}
        aria-label={`Status de ${baseTaskLabel(task.desc)}`}
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
