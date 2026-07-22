import { useState } from 'react'
import { Modal } from '@/components/ui/Modal'
import { Button } from '@/components/ui/Button'
import { backupApi, factoryResetApi } from '@/lib/api/endpoints'
import { queryClient } from '@/lib/queryClient'
import { settingsText as T } from '@/lib/i18n/settings'
import { downloadJson } from './UtilitiesPanel'

// workspace-settings 5.8 (§3.11, D12, D-RESET-GATE) — o modal de confirmação do
// reset de fábrica. NÃO existe caminho de UI que chegue ao reset sem backup: o
// confirmar dispara o EXPORT primeiro (baixa o RoboTrack_Database.json e captura o
// backupId) e SÓ ENTÃO chama o reset com a frase + backupId. O botão fica
// desabilitado até a frase digitada casar com o nome do workspace (conveniência —
// o servidor re-verifica com strip e caixa sensível).
//
// Pós-sucesso: a MESMA barreira de cache da troca de workspace (cancel → clear) —
// o reset muda o tenant INTEIRO; invalidação seletiva renderizaria dado apagado
// enquanto refaz o fetch. `switchWorkspace` não serve aqui (early-return no mesmo
// id), então o par cancel+clear é aplicado direto.

type Phase = 'idle' | 'exporting' | 'resetting' | 'done' | 'error-backup' | 'error-async' | 'error-reset'

export function FactoryResetModal({
  open,
  onClose,
  workspaceName,
}: {
  open: boolean
  onClose: () => void
  workspaceName: string
}) {
  const [phrase, setPhrase] = useState('')
  const [phase, setPhase] = useState<Phase>('idle')

  const busy = phase === 'exporting' || phase === 'resetting'
  const matches = phrase.trim() === workspaceName

  function close() {
    if (busy) return // não fechar no meio da operação
    setPhrase('')
    setPhase('idle')
    onClose()
  }

  async function confirm() {
    setPhase('exporting')
    let backupId: string | null = null
    try {
      const backup = await backupApi.create()
      if (backup.status === 202) {
        setPhase('error-async') // backup grande: sem arquivo síncrono, sem reset
        return
      }
      if (!backup.json || !backup.backupId) {
        setPhase('error-backup')
        return
      }
      downloadJson(backup.json, 'RoboTrack_Database.json')
      backupId = backup.backupId
    } catch {
      setPhase('error-backup')
      return
    }

    setPhase('resetting')
    try {
      await factoryResetApi.create(phrase, backupId)
      await queryClient.cancelQueries()
      queryClient.clear()
      setPhase('done')
    } catch {
      setPhase('error-reset')
    }
  }

  return (
    <Modal open={open} onClose={close} title={T.resetModalTitle}>
      <div className="space-y-3">
        <p className="text-sm text-text-muted">{T.resetSubtitle}</p>
        {phase !== 'done' && (
          <>
            <label className="label-sm block text-text-main" htmlFor="reset-phrase">
              {T.resetPhraseLabel(workspaceName)}
            </label>
            <input
              id="reset-phrase"
              className="input-base w-full"
              placeholder={T.resetPhrasePlaceholder}
              value={phrase}
              onChange={(e) => setPhrase(e.target.value)}
              disabled={busy}
            />
          </>
        )}
        {phase === 'exporting' && <p className="text-sm text-text-muted" role="status">{T.resetExporting}</p>}
        {phase === 'resetting' && <p className="text-sm text-text-muted" role="status">{T.resetResetting}</p>}
        {phase === 'done' && <p className="text-sm text-success-ink" role="status">{T.resetDone}</p>}
        {phase === 'error-backup' && <p className="text-sm text-danger-ink" role="alert">{T.resetErrorBackup}</p>}
        {phase === 'error-async' && <p className="text-sm text-danger-ink" role="alert">{T.exportAsync}</p>}
        {phase === 'error-reset' && <p className="text-sm text-danger-ink" role="alert">{T.resetErrorReset}</p>}
        <div className="flex justify-end gap-2 pt-2">
          {phase === 'done' ? (
            <Button type="button" onClick={close}>{T.resetCancel}</Button>
          ) : (
            <>
              <Button type="button" variant="ghost" onClick={close} disabled={busy}>
                {T.resetCancel}
              </Button>
              <Button type="button" variant="destructive" onClick={confirm} disabled={!matches || busy}>
                {T.resetConfirm}
              </Button>
            </>
          )}
        </div>
      </div>
    </Modal>
  )
}
