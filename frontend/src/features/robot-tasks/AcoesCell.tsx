import { useState } from 'react'
import { Icon } from '@/components/icons/Icon'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { Modal } from '@/components/ui/Modal'
import { useUpdateTaskDesc, useDeleteTask } from './useTaskCrud'
import { robotTaskText } from '@/lib/i18n/robotTasks'
import type { TaskDTO } from '@/lib/api/endpoints'

// robot-task-table 4.3 (§3.5, §4.1) — a coluna Ações: editar a descrição e excluir
// a tarefa. SÓ renderiza para owner/edit — para `view` a coluna inteira sai do DOM
// (4.4), e o servidor é a garantia (403 nas policies de robot-tasks). A exclusão
// exige confirmação; ambas invalidam o trio (a linha some e o % do cabeçalho
// recalcula na mesma render, via useTaskCrud).

export function AcoesCell({ robotId, task }: { robotId: string; task: TaskDTO }) {
  const [editing, setEditing] = useState(false)
  const [confirming, setConfirming] = useState(false)
  const [desc, setDesc] = useState(task.desc)
  const update = useUpdateTaskDesc(robotId)
  const del = useDeleteTask(robotId)

  function saveEdit() {
    const trimmed = desc.trim()
    if (trimmed === '' || update.isPending) return
    update.mutate(
      { taskId: task.id, desc: trimmed, lockVersion: task.lock_version },
      { onSuccess: () => setEditing(false) },
    )
  }

  return (
    <div className="flex items-center gap-1">
      <Button
        type="button"
        size="sm"
        variant="ghost"
        aria-label={robotTaskText.editAria(task.desc)}
        onClick={() => {
          setDesc(task.desc)
          setEditing(true)
        }}
      >
        <Icon name="edit" size="sm" />
      </Button>
      <Button
        type="button"
        size="sm"
        variant="ghost"
        aria-label={robotTaskText.deleteAria(task.desc)}
        onClick={() => setConfirming(true)}
      >
        <Icon name="trash" size="sm" />
      </Button>

      <Modal
        open={editing}
        onClose={() => setEditing(false)}
        title={robotTaskText.editTitle}
        footer={
          <>
            <Button type="button" variant="outline" onClick={() => setEditing(false)}>
              {robotTaskText.cancel}
            </Button>
            <Button type="button" onClick={saveEdit} disabled={desc.trim() === '' || update.isPending}>
              {robotTaskText.save}
            </Button>
          </>
        }
      >
        <label className="label-sm mb-1 block text-text-muted" htmlFor="edit-desc">
          {robotTaskText.editField}
        </label>
        <Input
          id="edit-desc"
          value={desc}
          onChange={(e) => setDesc(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') saveEdit()
          }}
        />
      </Modal>

      <Modal
        open={confirming}
        onClose={() => setConfirming(false)}
        title={robotTaskText.deleteTitle}
        footer={
          <>
            <Button type="button" variant="outline" onClick={() => setConfirming(false)}>
              {robotTaskText.cancel}
            </Button>
            <Button
              type="button"
              variant="destructive"
              onClick={() => del.mutate(task.id, { onSuccess: () => setConfirming(false) })}
              disabled={del.isPending}
            >
              {robotTaskText.deleteAction}
            </Button>
          </>
        }
      >
        <p className="text-text-muted">{robotTaskText.deleteConfirm(task.desc)}</p>
      </Modal>
    </div>
  )
}
