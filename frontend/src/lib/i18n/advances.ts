// Módulo ÚNICO dos textos do avanço de tarefa (progress-advances / D14). Nenhum
// literal dessas mensagens vive fora daqui no frontend — o mesmo princípio de
// `invitations.ts`: são as strings que o operador lê no galpão, num momento de
// decisão (registrar progresso, resolver um conflito), e espalhá-las garante que
// uma fique dessincronizada das outras.
//
// O RÓTULO DO COMENTÁRIO é condicional (§2.4 item 3, D14): abaixo de 100 o
// comentário é obrigatório e o texto diz isso; a 100 é opcional. É a regra dura
// da spec traduzida em palavra, não um `if` solto no componente.

export const advanceText = {
  // Controles da linha (−10/+10/slider)
  decrease: '−10%',
  increase: '+10%',
  progressLabel: 'Progresso da tarefa',
  readOnlyHint: 'Só quem edita pode registrar avanço.',

  // Modal
  title: 'Registrar avanço',
  from: 'De',
  to: 'Para',
  toFieldLabel: 'Progresso alvo (%)',

  // Rótulo condicional do comentário
  commentLabelRequired: 'Comentário (obrigatório abaixo de 100%)',
  commentLabelOptional: 'Comentário (opcional)',
  commentPlaceholder: 'O que foi feito?',
  commentRequiredHint: 'Explique o que falta para concluir.',

  confirm: 'Registrar',
  cancel: 'Cancelar',
  saving: 'Registrando…',
  genericFailure: 'Não foi possível registrar o avanço agora.',

  // Conflito (409 / D-409) — não descarta o que a pessoa escreveu
  conflictTitle: 'Alguém avançou esta tarefa enquanto você escrevia',
  conflictBy: (author: string, value: number) => `${author} registrou ${value}%.`,
  conflictWhen: (when: string) => `Em ${when}.`,
  recalculate: (value: number) => `Recalcular a partir de ${value}%`,
  discard: 'Descartar',
} as const
