import { useOfflineQueueStore, selectFailed } from '@/store/offlineQueueStore'
import { closureFrom } from '@/lib/offline/cascade'
import { discardWithClosure, fixAndResend } from '@/lib/offline/reconcile'
import type { QueuedMutation } from '@/lib/offline/types'

// Painel de reconciliação (offline-pwa 5.4 / D7-5, §2.4). Aparece quando há itens
// `failed`. Oferece EXATAMENTE duas ações por item, nomeadas em pt-BR — o descarte
// é sempre explícito. O rótulo "Descartar N" conta o fechamento transitivo (o item
// falho + os órfãos bloqueados que sairão junto).

const CLASS_LABEL: Record<NonNullable<QueuedMutation['failure_class']>, string> = {
  esgotado: 'não foi possível enviar após várias tentativas',
  permanente: 'o servidor recusou esta alteração',
  conflito: 'outra pessoa alterou isto enquanto você estava offline',
  auth: 'sua sessão expirou',
}

export function ReconciliationPanel({ onFix }: { onFix?: (item: QueuedMutation) => void }) {
  const failed = useOfflineQueueStore(selectFailed)
  const mutations = useOfflineQueueStore((s) => s.mutations)
  const refresh = useOfflineQueueStore((s) => s.refresh)

  if (failed.length === 0) return null

  const handleDiscard = async (id: string) => {
    await discardWithClosure(id)
    await refresh()
  }
  const handleFix = async (item: QueuedMutation) => {
    if (onFix) {
      onFix(item)
      return
    }
    // Sem editor externo: reenvia o corpo atual (destrava a cascata). Um editor por
    // tipo (renomear robô etc.) é responsabilidade do host via `onFix`.
    await fixAndResend(item.id, item.body)
    await refresh()
  }

  return (
    <section aria-labelledby="reconciliation-title" className="space-y-2 rounded-lg border border-danger/40 p-4">
      <h2 id="reconciliation-title" className="panel-header text-danger">
        Alterações que precisam da sua atenção
      </h2>
      <ul className="space-y-3">
        {failed.map((item) => {
          const count = closureFrom(mutations, item.id).size
          return (
            <li key={item.id} className="space-y-2">
              <p className="text-sm">
                <span className="font-medium">{item.kind}</span>
                {' — '}
                {item.failure_class ? CLASS_LABEL[item.failure_class] : (item.last_error ?? 'falhou')}
              </p>
              <div className="flex gap-2">
                <button
                  type="button"
                  className="rounded-md bg-accent/15 px-3 py-1.5 text-sm text-accent-ink"
                  onClick={() => void handleFix(item)}
                >
                  Corrigir e reenviar
                </button>
                <button
                  type="button"
                  className="rounded-md px-3 py-1.5 text-sm text-danger"
                  onClick={() => void handleDiscard(item.id)}
                >
                  {count > 1 ? `Descartar ${count} alterações` : 'Descartar alteração'}
                </button>
              </div>
            </li>
          )
        })}
      </ul>
    </section>
  )
}
