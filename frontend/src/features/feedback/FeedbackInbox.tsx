import { useState } from 'react'
import { useFeedbacks } from './useFeedback'
import type { FeedbackDTO } from '@/lib/api/endpoints'
import { feedbackText as T } from '@/lib/i18n/feedback'
import { localeTag } from '@/lib/i18n/lang'

// send-feedback — a caixa de leitura do DONO, montada owner-only na tela de
// Configurações. Lista simples e legível (sem grade de cards idênticos — PRODUCT):
// mensagem em destaque, autor + quando, e o contexto sob um disclosure.
// internationalization D-I3 — recriado por chamada para seguir o locale corrente
// (o remount por idioma não re-avalia um const de módulo).
const whenFmt = () => new Intl.DateTimeFormat(localeTag(), { dateStyle: 'short', timeStyle: 'short' })

export function FeedbackInbox() {
  const { data, isLoading, isError } = useFeedbacks()

  return (
    <section aria-labelledby="feedback-inbox-title" className="space-y-3">
      <div className="flex items-baseline justify-between gap-3">
        <h2 id="feedback-inbox-title" className="panel-header">
          {T.inboxTitle}
        </h2>
        {data && data.length > 0 && (
          <span className="label-sm tabular-nums text-text-muted">{T.inboxCount(data.length)}</span>
        )}
      </div>
      <p className="max-w-[68ch] text-sm text-text-muted">{T.inboxSubtitle}</p>

      {isLoading && <p className="text-sm text-text-muted">{T.inboxLoading}</p>}
      {isError && (
        <p role="alert" className="text-sm text-danger-ink">
          {T.inboxError}
        </p>
      )}
      {data && data.length === 0 && !isLoading && !isError && (
        <p className="surface-panel rounded-lg border p-4 text-sm text-text-muted">{T.inboxEmpty}</p>
      )}

      {data && data.length > 0 && (
        <ul className="space-y-2">
          {data.map((f) => (
            <li key={f.id}>
              <FeedbackItem feedback={f} />
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}

function FeedbackItem({ feedback }: { feedback: FeedbackDTO }) {
  const [open, setOpen] = useState(false)
  const who = feedback.submitter ? feedback.submitter.name : T.inboxAnon
  const email = feedback.submitter?.email
  const entries = Object.entries(feedback.context ?? {})

  return (
    <div className="surface-panel space-y-2 rounded-lg border p-4">
      <p className="whitespace-pre-wrap break-words text-text-main">{feedback.message}</p>
      <div className="label-sm flex flex-wrap items-center gap-x-2 gap-y-1 text-text-muted">
        <span className="font-medium text-text-main">{who}</span>
        {email && <span className="break-all">{email}</span>}
        <span aria-hidden="true">·</span>
        <time dateTime={feedback.created_at} className="tabular-nums">
          {whenFmt().format(new Date(feedback.created_at))}
        </time>
      </div>
      {entries.length > 0 && (
        <div>
          <button
            type="button"
            onClick={() => setOpen((s) => !s)}
            className="label-sm font-medium text-accent-ink underline-offset-2 hover:underline"
            aria-expanded={open}
          >
            {T.contextLabel}
          </button>
          {open && (
            <dl className="mt-2 space-y-1">
              {entries.map(([key, value]) => (
                <div key={key} className="flex gap-2 text-sm">
                  <dt className="shrink-0 font-mono text-text-muted">{key}</dt>
                  <dd className="min-w-0 break-words text-text-main">{String(value ?? '—')}</dd>
                </div>
              ))}
            </dl>
          )}
        </div>
      )}
    </div>
  )
}
