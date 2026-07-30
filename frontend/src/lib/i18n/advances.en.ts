import type { AdvanceText } from './advances'

// internationalization G4 — tradução EN dos textos de avanço. Glossário confirmado:
// "Avanço" → "Progress update"; "Registrar avanço" → "Log progress" (decisão nº 1).
export const advanceTextEn: AdvanceText = {
  decrease: '−10%',
  increase: '+10%',
  progressLabel: 'Task progress',
  progressLabelFor: (task: string) => `Progress of "${task}"`,
  readOnlyHint: 'Only editors can log progress.',

  title: 'Log progress',
  from: 'From',
  to: 'To',
  toFieldLabel: 'Target progress (%)',
  statusChange: (status: string) => `New status: ${status}`,

  commentLabelRequired: 'Comment (required below 100%)',
  commentLabelOptional: 'Comment (optional)',
  commentPlaceholder: 'What was done?',
  commentRequiredHint: 'Explain what is left to complete.',

  confirm: 'Log',
  cancel: 'Cancel',
  close: 'Close',
  saving: 'Logging…',
  genericFailure: 'Could not log the progress update right now.',

  queuedTitle: 'Offline — progress update queued',
  queuedHint: "We'll send it as soon as the connection is back. Nothing was lost.",

  conflictTitle: 'Someone advanced this task while you were writing',
  conflictBy: (author: string, value: number) => `${author} logged ${value}%.`,
  conflictWhen: (when: string) => `At ${when}.`,
  recalculate: (value: number) => `Recalculate from ${value}%`,
  discard: 'Discard',
}
