import { useState } from 'react'
import { Modal } from '@/components/ui/Modal'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { Chip } from '@/components/ui/Chip'
import { robotTaskText } from '@/lib/i18n/robotTasks'
import {
  useWorkspacePeople,
  useAssigneeSelection,
  useReplaceAssignees,
} from '@/features/tasks/useTaskAssignees'
import type { TaskDTO } from '@/lib/api/endpoints'

// robot-task-table 5.3/5.4 (§3.5, D2/D10/D11) — o modal de atribuição.
//
// Checkboxes de TODAS as pessoas do workspace, com os responsáveis atuais já
// marcados; salva via `PUT /tasks/:id/assignees` (o conjunto por IDENTIDADE, D11 —
// desmarcar todos deixa `assignees` vazio, NÃO cria "Não Atribuído"). A lista vem
// do workspace atual (a RLS garante que pessoa de outro workspace não aparece, D2).
//
// Cadastro (5.4, D10): o nome é `btrim`; em branco é rejeitado; se já existe uma
// pessoa com o mesmo nome normalizado, MARCA a existente e informa a duplicidade em
// vez de criar uma segunda. A pessoa nova entra já marcada.
//
// `view` (canEdit=false) recebe o modal só-leitura: checkboxes desabilitados, sem
// cadastro e sem salvar. O servidor é a garantia (403 no PUT).

function normalize(name: string) {
  return name.trim().replace(/\s+/g, ' ').toLocaleLowerCase('pt-BR')
}

export function AssignmentModal({
  robotId,
  task,
  canEdit,
  onClose,
}: {
  robotId: string
  task: TaskDTO
  canEdit: boolean
  onClose: () => void
}) {
  const people = useWorkspacePeople()
  const { selected, toggle, createAndSelect, personIds } = useAssigneeSelection(
    task.assignees.map((a) => a.id),
  )
  const replace = useReplaceAssignees(robotId)
  const [name, setName] = useState('')
  const [notice, setNotice] = useState<string | null>(null)

  async function addPerson() {
    const trimmed = name.trim()
    if (trimmed === '') {
      setNotice(robotTaskText.assignBlank)
      return
    }
    // D10 — dedup por nome normalizado: marca a existente em vez de duplicar.
    const existing = (people.data ?? []).find((p) => normalize(p.name) === normalize(trimmed))
    if (existing) {
      if (!selected.has(existing.id)) toggle(existing.id)
      setNotice(robotTaskText.assignDuplicate(existing.name))
      setName('')
      return
    }
    await createAndSelect(trimmed)
    setNotice(null)
    setName('')
  }

  function save() {
    if (replace.isPending) return
    replace.mutate({ taskId: task.id, personIds: personIds() }, { onSuccess: onClose })
  }

  return (
    <Modal
      open
      onClose={onClose}
      title={robotTaskText.assignTitle}
      footer={
        canEdit ? (
          <>
            <Button type="button" variant="outline" onClick={onClose}>
              {robotTaskText.cancel}
            </Button>
            <Button type="button" onClick={save} disabled={replace.isPending}>
              {replace.isPending ? robotTaskText.assignSaving : robotTaskText.assignSave}
            </Button>
          </>
        ) : (
          <Button type="button" variant="outline" onClick={onClose}>
            {robotTaskText.close}
          </Button>
        )
      }
    >
      <p className="label-sm mb-2 text-text-muted">{robotTaskText.assignPeople}</p>

      {people.isError ? (
        <p className="text-danger-ink">{robotTaskText.assignLoadError}</p>
      ) : (people.data ?? []).length === 0 ? (
        <p className="text-text-muted">{robotTaskText.assignEmpty}</p>
      ) : (
        <ul className="space-y-1">
          {(people.data ?? []).map((p) => (
            <li key={p.id}>
              <label className="flex min-h-[40px] cursor-pointer items-center gap-2 rounded-md px-2 hover:bg-accent/5">
                <input
                  type="checkbox"
                  checked={selected.has(p.id)}
                  disabled={!canEdit}
                  onChange={() => toggle(p.id)}
                  className="h-4 w-4"
                />
                <span>{p.name}</span>
              </label>
            </li>
          ))}
        </ul>
      )}

      {canEdit && (
        <div className="mt-4 border-t pt-3">
          <label className="label-sm mb-1 block text-text-muted" htmlFor="assign-add">
            {robotTaskText.assignAddLabel}
          </label>
          <div className="flex gap-2">
            <Input
              id="assign-add"
              value={name}
              placeholder={robotTaskText.assignAddPlaceholder}
              onChange={(e) => setName(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  e.preventDefault()
                  void addPerson()
                }
              }}
            />
            <Button type="button" variant="outline" onClick={() => void addPerson()}>
              {robotTaskText.assignAddButton}
            </Button>
          </div>
          {notice && (
            <p role="status" className="label-sm mt-1 text-text-muted">
              {notice}
            </p>
          )}
        </div>
      )}

      {/* prévia dos marcados (chips), para confirmar antes de salvar */}
      {selected.size > 0 && (
        <div className="mt-3 flex flex-wrap gap-1.5">
          {(people.data ?? [])
            .filter((p) => selected.has(p.id))
            .map((p) => (
              <Chip key={p.id} label={p.name} />
            ))}
        </div>
      )}
    </Modal>
  )
}
