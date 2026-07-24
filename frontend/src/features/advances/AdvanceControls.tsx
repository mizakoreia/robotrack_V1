import { useRef, useState } from 'react'
import { advanceText } from '../../lib/i18n/advances'
import { useWorkspaceStore } from '../../store/workspaceStore'
import { useAdvanceDraft } from './useAdvanceDraft'
import { AdvanceModal } from './AdvanceModal'

// progress-advances 5.2/5.6 (§2.4 itens 1 e 5, §4.1, D-UI) — os controles de
// avanço de UMA linha da tabela: o slider e o modal.
//
// FLUXO (pedido do dono): SEM botões ±10. Arrastar o slider mostra o valor ao
// vivo, mas a caixa de observação SÓ abre quando o arraste TERMINA (soltar o
// ponteiro / soltar a tecla) — não a cada pixel arrastado. O valor solto é o que
// o modal leva e o Registrar envia.
//
// `view` é SÓ-LEITURA (5.6): o slider é `aria-disabled` e o modal não abre. Não é
// segurança (o servidor devolve 403 a um `view` que forçar o envio) — é não
// oferecer uma ação que seria negada.
//
// Enquanto o modal não abriu, o slider é controlado por `pending ?? serverProgress`
// (arraste ao vivo); cancelar/`Esc` zera tudo e o slider VOLTA ao servidor sem
// requisição nenhuma — e o foco retorna ao controle de origem.

export function AdvanceControls({ robotId, taskId }: { robotId: string; taskId: string }) {
  const role = useWorkspaceStore((s) => s.currentRoleLabel)
  const canEdit = role === 'owner' || role === 'edit'
  const draft = useAdvanceDraft(robotId, taskId)
  const originRef = useRef<HTMLElement | null>(null)
  // Valor ao vivo do arraste ANTES de o modal abrir (null = slider mostra o servidor).
  const [pending, setPending] = useState<number | null>(null)

  // Enquanto o modal está aberto o valor mora no draft; antes, no `pending`.
  const sliderValue = draft.isOpen ? draft.value : pending ?? draft.serverProgress()

  function remember(e: React.SyntheticEvent) {
    originRef.current = e.currentTarget as HTMLElement
  }

  function close() {
    draft.reset()
    setPending(null)
    originRef.current?.focus()
  }

  // Fim do arraste: se o valor mudou em relação ao servidor, ABRE o modal com ele.
  // Se o modal já estava aberto (arrastar de novo), mantém o draft sincronizado.
  function commit(e: React.SyntheticEvent) {
    if (!canEdit || pending === null) return
    remember(e)
    if (pending !== draft.serverProgress()) draft.setDraft(pending)
  }

  function onSliderKeyDown(e: React.KeyboardEvent) {
    if (e.key === 'Escape') close()
  }

  return (
    // robot-task-table 6.1 — `flex-wrap`: em 375px (cartão mobile) os controles
    // quebram linha em vez de estourar a borda e rolar a página na horizontal.
    <div className="flex flex-wrap items-center gap-2">
      <input
        type="range"
        min={0}
        max={100}
        step={5} // robot-task-table 2.2 (§3.5) — arrastar uma posição a partir de 30 propõe 35
        value={sliderValue}
        aria-label={advanceText.progressLabel}
        aria-disabled={!canEdit}
        disabled={!canEdit}
        // robot-task-table 6.2 — `pan-y`: arrastar o dedo na vertical ROLA a página
        // em vez de mudar o progresso; só o gesto horizontal move o slider.
        className="touch-pan-y"
        onKeyDown={onSliderKeyDown}
        // Arrastar: atualiza o valor ao vivo (readout), mas NÃO abre o modal.
        onChange={(e) => {
          if (!canEdit) return
          const next = Number(e.target.value)
          setPending(next)
          if (draft.isOpen) draft.setDraft(next) // já aberto: segue sincronizado
        }}
        // Fim do arraste (ponteiro/toque) ou da tecla: aí sim abre a observação.
        onPointerUp={commit}
        onKeyUp={commit}
      />
      {/* robot-task-table 6.4 — leitura com role=progressbar para o leitor de tela */}
      <span
        className="w-10 text-sm tabular-nums"
        role="progressbar"
        aria-valuenow={sliderValue}
        aria-valuemin={0}
        aria-valuemax={100}
      >
        {sliderValue}%
      </span>

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
