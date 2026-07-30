import { useEffect, useState } from 'react'
import { useLocation } from 'react-router-dom'
import { toast } from 'sonner'
import { Modal } from '@/components/ui/Modal'
import { Button } from '@/components/ui/Button'
import { useWorkspaceStore } from '@/store/workspaceStore'
import { useSubmitFeedback } from './useFeedback'
import type { FeedbackContext } from '@/lib/api/endpoints'
import { feedbackText as T } from '@/lib/i18n/feedback'

// send-feedback — o modal de envio de feedback do beta, no primitivo `Modal`
// (overlay, foco preso, Esc devolve ao gatilho). Vive na casca (AppShell), aberto
// por `?feedback=1` a partir do item do menu da conta — sempre disponível em
// qualquer rota autenticada, sem poluir a topbar.
//
// CAPTURA AUTOMÁTICA de contexto: o tester só escreve a mensagem; a tela, o
// workspace, o papel e o dispositivo vão juntos, montados no momento do envio (a
// rota é a atual). `workspace_id` da RLS é do servidor (header) — o que mandamos
// aqui é só rótulo para o dono ler.
export function SendFeedbackDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const location = useLocation()
  const currentWorkspaceId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const role = useWorkspaceStore((s) => s.currentRoleLabel)
  const workspaces = useWorkspaceStore((s) => s.workspaces)

  const [message, setMessage] = useState('')
  const [error, setError] = useState<string | null>(null)
  const submit = useSubmitFeedback()

  // Cada abertura começa limpa. Só reagimos à ABERTURA: `submit` (react-query)
  // troca de identidade a cada render, e incluí-lo aqui reiniciaria o campo a cada
  // tecla. Fora as dependências, o corpo só usa setters de estado (estáveis).
  useEffect(() => {
    if (open) {
      setMessage('')
      setError(null)
      submit.reset()
    }
  }, [open])

  if (!open) return null

  function buildContext(): FeedbackContext {
    const wsName = workspaces.find((w) => w.id === currentWorkspaceId)?.name ?? null
    return {
      route: location.pathname,
      workspace_id: currentWorkspaceId,
      workspace_name: wsName,
      role,
      user_agent: navigator.userAgent,
      language: navigator.language,
      viewport: `${window.innerWidth}x${window.innerHeight}`,
    }
  }

  function onSubmit(ev: React.FormEvent) {
    ev.preventDefault()
    const text = message.trim()
    if (!text) {
      setError(T.errorEmpty)
      return
    }
    setError(null)
    submit.mutate(
      { message: text, context: buildContext() },
      {
        onSuccess: () => {
          toast.success(T.successToast)
          onClose()
        },
        onError: () => setError(T.errorGeneric),
      },
    )
  }

  const busy = submit.isPending

  return (
    <Modal open={open} onClose={onClose} title={T.title}>
      <form onSubmit={onSubmit} noValidate className="space-y-3" aria-label={T.title}>
        <p className="max-w-[60ch] text-sm text-text-main">{T.intro}</p>

        <div>
          <label htmlFor="feedback-message" className="block text-sm font-medium text-text-main">
            {T.messageLabel}
          </label>
          <textarea
            id="feedback-message"
            rows={5}
            autoFocus
            maxLength={4000}
            aria-invalid={!!error}
            value={message}
            onChange={(e) => setMessage(e.target.value)}
            placeholder={T.messagePlaceholder}
            className="mt-1 w-full resize-y rounded-md border border-input bg-bg-main px-3 py-2 text-text-main placeholder:text-text-muted"
          />
        </div>

        <ContextDisclosure context={buildContext()} />

        <p aria-live="polite" className="min-h-[1.25rem] text-sm text-danger-ink">
          {error}
        </p>

        <div className="flex items-center justify-end gap-2">
          <Button type="button" variant="outline" size="sm" onClick={onClose}>
            {T.cancel}
          </Button>
          <Button type="submit" size="sm" disabled={busy}>
            {busy ? T.sending : T.send}
          </Button>
        </div>
      </form>
    </Modal>
  )
}

// Transparência (estado honesto, PRODUCT §2): o tester pode conferir exatamente o
// que vai junto. Recolhido por padrão — não rouba a atenção de escrever.
function ContextDisclosure({ context }: { context: FeedbackContext }) {
  const [shown, setShown] = useState(false)
  return (
    <div className="rounded-md border border-input bg-bg-main px-3 py-2">
      <p className="text-sm text-text-muted">{T.contextNote}</p>
      <button
        type="button"
        onClick={() => setShown((s) => !s)}
        className="mt-1 text-sm font-medium text-accent-ink underline-offset-2 hover:underline"
        aria-expanded={shown}
      >
        {shown ? T.contextToggleHide : T.contextToggleShow}
      </button>
      {shown && (
        <dl className="mt-2 space-y-1">
          {Object.entries(context).map(([key, value]) => (
            <div key={key} className="flex gap-2 text-sm">
              <dt className="shrink-0 font-mono text-text-muted">{key}</dt>
              <dd className="min-w-0 break-words text-text-main">{String(value ?? '—')}</dd>
            </div>
          ))}
        </dl>
      )}
    </div>
  )
}
