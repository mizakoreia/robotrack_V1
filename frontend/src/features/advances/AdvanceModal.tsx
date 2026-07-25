import { useState } from 'react'
import { Button } from '../../components/ui/Button'
import { Modal } from '../../components/ui/Modal'
import { advanceText } from '../../lib/i18n/advances'
import { newId } from '../../lib/ids'
import { clampProgress } from './useAdvanceDraft'
import { readAdvanceConflict, useRecordAdvance, wasQueued } from './useRecordAdvance'
import { deriveStatusTarget, type TaskStatus } from './statusTarget'
import type { AdvanceConflict } from '../../lib/api/endpoints'

// progress-advances 5.3/5.5 (§2.4 itens 2–3, D14/D-409) — o modal de confirmação
// do avanço.
//
// A regra dura vive aqui em DUAS formas coerentes: o rótulo do comentário troca
// (obrigatório abaixo de 100, opcional a 100) E o botão de confirmar fica
// bloqueado quando `para < 100` e o comentário é vazio ou só espaços. Três
// espaços não habilitam — a mesma checagem `btrim` do banco.
//
// O 409 NÃO é erro de rede: preserva o comentário digitado, troca o corpo por
// "Fulano registrou X%", e oferece *Recalcular a partir de X%* (reaplica o mesmo
// delta sobre o novo valor, com um uuid NOVO — é outro fato) ou *Descartar*.
// Nunca reenvia sozinho.

export interface AdvanceModalProps {
  robotId: string
  taskId: string
  from: number
  initialTo: number
  lockVersion: number
  onDone: () => void // fechar e resetar o rascunho no pai
  // robot-task-table 2.1 (§2.2) — MODO STATUS: aberto pelo StatusSelect. O envio
  // leva `status` (a tabela-verdade resolve no servidor — `N/A` NÃO vira
  // `progress: 0`, que degradaria para `Pendente`); `initialTo` é só a prévia
  // derivada, e o campo numérico some (quem quer % livre usa o slider/±).
  toStatus?: TaskStatus
}

export function AdvanceModal({
  robotId,
  taskId,
  from,
  initialTo,
  lockVersion,
  onDone,
  toStatus,
}: AdvanceModalProps) {
  const [to, setTo] = useState<number>(initialTo)
  const [comment, setComment] = useState('')
  const [advanceId, setAdvanceId] = useState<string>(() => newId())
  const [conflict, setConflict] = useState<AdvanceConflict | null>(null)
  // impeccable-remediation G2 (Princípio 2 — estado honesto): offline, o avanço é
  // ENFILEIRADO. O modal não pode fechar como "salvo"; mostra a verdade.
  const [queued, setQueued] = useState(false)
  // `lock_version` corrente do envio: começa no da abertura (5.4) e, após um
  // *Recalcular*, passa a ser o que o 409 devolveu.
  const [currentLock, setCurrentLock] = useState<number>(lockVersion)
  const [baseFrom, setBaseFrom] = useState<number>(from)

  const mutation = useRecordAdvance(robotId)

  const requiresComment = to < 100
  const commentMissing = comment.trim() === ''
  const confirmDisabled = mutation.isPending || (requiresComment && commentMissing)

  function submit() {
    if (confirmDisabled) return
    setConflict(null)
    mutation.mutate(
      {
        taskId,
        id: advanceId,
        // XOR — modo status manda `status` e NENHUM progress (§2.2 no servidor).
        ...(toStatus ? { toStatus } : { toProgress: to }),
        comment: comment.trim() === '' ? undefined : comment,
        recordedAt: new Date().toISOString(),
        lockVersion: currentLock,
      },
      {
        onSuccess: (result) => {
          // Sem rede → enfileirado: NÃO fecha como salvo; mostra o estado honesto.
          if (wasQueued(result)) setQueued(true)
          else onDone()
        },
        onError: (error) => {
          const c = readAdvanceConflict(error)
          if (c) setConflict(c) // preserva `comment`; NÃO reenvia
        },
      },
    )
  }

  // *Recalcular a partir de X%*: reaplica o MESMO delta (to − baseFrom) sobre o
  // valor que o outro operador deixou, com um uuid NOVO — é outro avanço. No modo
  // status a intenção é ABSOLUTA ("marcar N/A"), não um delta: mantém o status e
  // re-deriva a prévia pela tabela-verdade sobre o valor novo (§2.2).
  function recalculate() {
    if (!conflict) return
    const newFrom = conflict.task.progress
    if (toStatus) {
      setTo(deriveStatusTarget(toStatus, newFrom))
    } else {
      const delta = to - baseFrom
      setTo(clampProgress(newFrom + delta))
    }
    setBaseFrom(newFrom)
    setCurrentLock(conflict.task.lock_version)
    setAdvanceId(newId()) // outro fato → outro uuid
    setConflict(null)
  }

  const commentLabel = requiresComment
    ? advanceText.commentLabelRequired
    : advanceText.commentLabelOptional

  // impeccable-remediation G2 — o AdvanceModal era o ÚNICO diálogo fora do primitivo
  // `Modal` (um `<div role=dialog>` inline no `<td>`, sem portal/overlay/fixed/trap —
  // `aria-modal` sem trap prende o leitor "fora" do diálogo). Agora usa o primitivo:
  // portal em #rt-overlays, position:fixed, focus-trap, scroll-lock, Esc devolve o
  // foco ao gatilho. O rodapé muda por estado (enfileirado / conflito / normal).
  const footer = queued ? (
    <Button type="button" onClick={onDone}>
      {advanceText.close}
    </Button>
  ) : conflict ? (
    <>
      <Button type="button" onClick={recalculate}>
        {advanceText.recalculate(conflict.task.progress)}
      </Button>
      <Button type="button" variant="outline" onClick={onDone}>
        {advanceText.discard}
      </Button>
    </>
  ) : (
    <>
      <Button type="button" onClick={submit} disabled={confirmDisabled}>
        {mutation.isPending ? advanceText.saving : advanceText.confirm}
      </Button>
      <Button type="button" variant="outline" onClick={onDone}>
        {advanceText.cancel}
      </Button>
    </>
  )

  return (
    <Modal open onClose={onDone} title={advanceText.title} footer={footer}>
      {queued ? (
        <div role="status">
          <p className="text-sm font-medium text-warning-ink">{advanceText.queuedTitle}</p>
          <p className="mt-1 text-sm text-text-muted">{advanceText.queuedHint}</p>
        </div>
      ) : conflict ? (
        <div>
          <p className="text-sm font-medium text-warning-ink">{advanceText.conflictTitle}</p>
          {conflict.latest_advance && (
            <p className="mt-1 text-sm text-text-muted">
              {advanceText.conflictBy(
                conflict.latest_advance.author_name_snapshot,
                conflict.latest_advance.to_progress,
              )}
            </p>
          )}
        </div>
      ) : (
        <>
          <p className="text-sm text-text-muted">
            {advanceText.from} {baseFrom}% → {advanceText.to} {to}%
          </p>

          {toStatus ? (
            <p className="mt-1 text-sm font-medium">{advanceText.statusChange(toStatus)}</p>
          ) : (
            <>
              {/* Sem slider aqui: o alvo é definido pelo slider da LINHA e a
                  observação abre depois que o arraste termina. Este campo permite
                  só um ajuste fino do valor recebido; ambos escrevem em `to`. */}
              <label className="mt-3 block text-sm" htmlFor="avanco-para">
                {advanceText.toFieldLabel}
              </label>
              <input
                id="avanco-para"
                type="number"
                min={0}
                max={100}
                value={to}
                onChange={(e) => setTo(clampProgress(Number(e.target.value)))}
                className="mt-1 w-24 rounded-md border border-input bg-bg-main px-3 py-2 text-sm text-text-main"
              />
            </>
          )}

          <label className="mt-3 block text-sm" htmlFor="avanco-comentario">
            {commentLabel}
          </label>
          <textarea
            id="avanco-comentario"
            value={comment}
            onChange={(e) => setComment(e.target.value)}
            placeholder={advanceText.commentPlaceholder}
            rows={3}
            className="mt-1 w-full rounded-md border bg-bg-main px-3 py-2 text-sm text-text-main"
          />
          {requiresComment && commentMissing && (
            <p className="mt-1 text-sm text-text-muted">{advanceText.commentRequiredHint}</p>
          )}

          {mutation.isError && !conflict && (
            <p role="alert" aria-live="polite" className="mt-2 text-sm text-danger-ink">
              {advanceText.genericFailure}
            </p>
          )}
        </>
      )}
    </Modal>
  )
}
