import { useState } from 'react'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { Modal } from '@/components/ui/Modal'
import { useCreateTask } from './useTaskCrud'
import { robotTaskText } from '@/lib/i18n/robotTasks'

// robot-task-table 4.3 — cadastro de tarefa avulsa (categoria + descrição). Só é
// montado para owner/edit (o gatilho no cabeçalho já é gated). No sucesso, a lista
// invalida e a nova linha aparece no grupo da categoria.
export function AddTaskModal({
  robotId,
  open,
  onClose,
}: {
  robotId: string
  open: boolean
  onClose: () => void
}) {
  const [cat, setCat] = useState('')
  const [desc, setDesc] = useState('')
  const create = useCreateTask(robotId)
  const invalid = cat.trim() === '' || desc.trim() === '' || create.isPending

  function submit() {
    if (invalid) return
    create.mutate(
      { cat: cat.trim(), desc: desc.trim() },
      {
        onSuccess: () => {
          setCat('')
          setDesc('')
          onClose()
        },
      },
    )
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={robotTaskText.addTitle}
      footer={
        <>
          <Button type="button" variant="outline" onClick={onClose}>
            {robotTaskText.cancel}
          </Button>
          <Button type="button" onClick={submit} disabled={invalid}>
            {robotTaskText.add}
          </Button>
        </>
      }
    >
      <label className="label-sm mb-1 block text-text-muted" htmlFor="add-cat">
        {robotTaskText.addCategory}
      </label>
      <Input id="add-cat" value={cat} onChange={(e) => setCat(e.target.value)} className="mb-3" />
      <label className="label-sm mb-1 block text-text-muted" htmlFor="add-desc">
        {robotTaskText.addDescription}
      </label>
      <Input
        id="add-desc"
        value={desc}
        onChange={(e) => setDesc(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === 'Enter') submit()
        }}
      />
    </Modal>
  )
}
