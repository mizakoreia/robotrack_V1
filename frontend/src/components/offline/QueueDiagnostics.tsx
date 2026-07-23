import { useState } from 'react'
import { downloadQueueExport } from '@/lib/offline/export'

// UI de diagnóstico da fila offline (offline-pwa 8.3). O botão "Exportar backup"
// baixa um JSON com todos os itens da fila — a rede de segurança antes de qualquer
// migração de esquema (8.4): mesmo que uma migração quarentene itens, o conteúdo
// (o avanço registrado às 14h) fica recuperável.
export function QueueDiagnostics() {
  const [busy, setBusy] = useState(false)

  const onExport = async () => {
    setBusy(true)
    try {
      await downloadQueueExport()
    } finally {
      setBusy(false)
    }
  }

  return (
    <section aria-labelledby="queue-diag-title" className="space-y-2">
      <h2 id="queue-diag-title" className="panel-header">
        Fila offline
      </h2>
      <div className="surface-panel space-y-2 rounded-lg border p-4">
        <p className="label-sm text-text-muted">
          Baixe uma cópia das alterações ainda não sincronizadas. Útil antes de limpar dados do
          navegador ou reportar um problema.
        </p>
        <button
          type="button"
          className="rounded-md bg-accent/15 px-3 py-1.5 text-sm text-accent-ink"
          onClick={() => void onExport()}
          disabled={busy}
        >
          {busy ? 'Exportando…' : 'Exportar fila offline'}
        </button>
      </div>
    </section>
  )
}
