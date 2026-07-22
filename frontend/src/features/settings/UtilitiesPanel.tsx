import { useState } from 'react'
import { Button } from '@/components/ui/Button'
import { backupApi } from '@/lib/api/endpoints'
import { settingsText as T } from '@/lib/i18n/settings'

// workspace-settings 4.5 (§3.11, D-EXP) — o painel de Utilitários. Por ora só o
// export de backup (o reset de fábrica e o modal de auditoria entram no G5/G6). É
// `owner`-only (o pai só renderiza este painel para o dono); o botão baixa o
// `RoboTrack_Database.json`. Acima do teto, o servidor responde 202 (geração
// assíncrona) e o painel avisa. O `backupId` capturado alimenta o reset (G5).

// Dispara o download do arquivo no navegador. Isolado para o teste poder cobrir o
// fluxo sem depender de `URL.createObjectURL` (ausente no jsdom).
export function downloadJson(json: string, filename: string) {
  if (typeof URL.createObjectURL !== 'function') return
  const url = URL.createObjectURL(new Blob([json], { type: 'application/json' }))
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}

export function UtilitiesPanel({ onBackup }: { onBackup?: (backupId: string) => void }) {
  const [state, setState] = useState<'idle' | 'pending' | 'done' | 'async' | 'error'>('idle')

  async function exportBackup() {
    setState('pending')
    try {
      const result = await backupApi.create()
      if (result.backupId) onBackup?.(result.backupId)
      if (result.status === 202) {
        setState('async')
      } else if (result.json) {
        downloadJson(result.json, 'RoboTrack_Database.json')
        setState('done')
      } else {
        setState('error')
      }
    } catch {
      setState('error')
    }
  }

  return (
    <section aria-labelledby="utilities-panel-title" className="space-y-3">
      <h2 id="utilities-panel-title" className="panel-header">{T.utilitiesTitle}</h2>
      <div className="surface-panel space-y-2 rounded-lg border p-4">
        <p className="font-medium text-text-main">{T.exportTitle}</p>
        <p className="label-sm text-text-muted">{T.exportSubtitle}</p>
        <Button type="button" onClick={exportBackup} disabled={state === 'pending'}>
          {state === 'pending' ? T.exportPending : T.exportButton}
        </Button>
        {state === 'done' && <p className="text-sm text-success-ink" role="status">{T.exportDone}</p>}
        {state === 'async' && <p className="text-sm text-text-muted" role="status">{T.exportAsync}</p>}
        {state === 'error' && <p className="text-sm text-danger-ink" role="alert">{T.exportError}</p>}
      </div>
    </section>
  )
}
