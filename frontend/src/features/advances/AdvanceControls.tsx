import { useRef } from 'react'
import { Button } from '../../components/ui/Button'
import { advanceText } from '../../lib/i18n/advances'
import { useWorkspaceStore } from '../../store/workspaceStore'
import { useAdvanceDraft } from './useAdvanceDraft'
import { AdvanceModal } from './AdvanceModal'

// progress-advances 5.2/5.6 (§2.4 itens 1 e 5, §4.1, D-UI) — os controles de
// avanço de UMA linha da tabela: os botões `−10`/`+10`, o slider e o modal.
//
// `view` é SÓ-LEITURA (5.6): os botões somem, o slider é `aria-disabled` e o
// modal não abre. Não é segurança (o servidor devolve 403 a um `view` que forçar
// o envio) — é não oferecer uma ação que seria negada. O rótulo `role` do store
// é rótulo, não autoridade.
//
// O slider é controlado por `value = draft ?? serverProgress` (D-UI): arrastar
// define o rascunho; cancelar/`Esc` o zera e o slider VOLTA ao servidor, sem
// requisição nenhuma — e o foco retorna ao controle de origem.

export function AdvanceControls({ robotId, taskId }: { robotId: string; taskId: string }) {
  const role = useWorkspaceStore((s) => s.currentRoleLabel)
  const canEdit = role === 'owner' || role === 'edit'
  const draft = useAdvanceDraft(robotId, taskId)
  const originRef = useRef<HTMLElement | null>(null)

  // Guarda o controle que abriu o rascunho, para devolver o foco no cancelar.
  function remember(e: React.SyntheticEvent) {
    originRef.current = e.currentTarget as HTMLElement
  }

  function close() {
    draft.reset()
    originRef.current?.focus()
  }

  function onSliderKeyDown(e: React.KeyboardEvent) {
    if (e.key === 'Escape') close()
  }

  return (
    // robot-task-table 6.1 — `flex-wrap`: em 375px (cartão mobile) os controles
    // quebram linha em vez de estourar a borda e rolar a página na horizontal.
    <div className="flex flex-wrap items-center gap-2">
      {canEdit && (
        <Button
          type="button"
          size="sm"
          variant="outline"
          className="min-h-[40px] min-w-[40px]" // robot-task-table 6.2 — alvo de toque ≥40px
          aria-label={advanceText.decrease}
          onClick={(e) => {
            remember(e)
            draft.step(-10)
          }}
        >
          {advanceText.decrease}
        </Button>
      )}

      <input
        type="range"
        min={0}
        max={100}
        step={5} // robot-task-table 2.2 (§3.5) — arrastar uma posição a partir de 30 propõe 35
        value={draft.value}
        aria-label={advanceText.progressLabel}
        aria-disabled={!canEdit}
        disabled={!canEdit}
        // robot-task-table 6.2 — `pan-y`: arrastar o dedo na vertical ROLA a página
        // em vez de mudar o progresso; só o gesto horizontal move o slider.
        className="touch-pan-y"
        onKeyDown={onSliderKeyDown}
        onChange={(e) => {
          if (!canEdit) return
          remember(e)
          draft.setDraft(Number(e.target.value))
        }}
      />
      {/* robot-task-table 6.4 — leitura com role=progressbar para o leitor de tela */}
      <span
        className="w-10 text-sm tabular-nums"
        role="progressbar"
        aria-valuenow={draft.value}
        aria-valuemin={0}
        aria-valuemax={100}
      >
        {draft.value}%
      </span>

      {canEdit && (
        <Button
          type="button"
          size="sm"
          variant="outline"
          className="min-h-[40px] min-w-[40px]" // robot-task-table 6.2 — alvo de toque ≥40px
          aria-label={advanceText.increase}
          onClick={(e) => {
            remember(e)
            draft.step(10)
          }}
        >
          {advanceText.increase}
        </Button>
      )}

      {!canEdit && <span className="sr-only">{advanceText.readOnlyHint}</span>}

      {canEdit && draft.isOpen && draft.origin && (
        <AdvanceModal
          robotId={robotId}
          taskId={taskId}
          from={draft.origin.from}
          initialTo={draft.value}
          lockVersion={draft.origin.lockVersion}
          onDone={close}
        />
      )}
    </div>
  )
}
