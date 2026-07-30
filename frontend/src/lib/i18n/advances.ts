import { defineText } from './defineText'
import { advanceTextEn } from './advances.en'

// Módulo ÚNICO dos textos do avanço de tarefa (progress-advances / D14). Nenhum
// literal dessas mensagens vive fora daqui no frontend — o mesmo princípio de
// `invitations.ts`: são as strings que o operador lê no galpão, num momento de
// decisão (registrar progresso, resolver um conflito), e espalhá-las garante que
// uma fique dessincronizada das outras.
//
// O RÓTULO DO COMENTÁRIO é condicional (§2.4 item 3, D14): abaixo de 100 o
// comentário é obrigatório e o texto diz isso; a 100 é opcional. É a regra dura
// da spec traduzida em palavra, não um `if` solto no componente.
//
// internationalization D-I2 — `advanceText` é o eixo de idioma (pt-BR + en) sob o
// MESMO nome; os ~29 consumidores não mudam. O pt-BR canônico vive neste objeto (os
// sweeps o leem); o en em `advances.en.ts`. "Avanço"→"Progress update",
// "Registrar avanço"→"Log progress" (decisão do dono nº 1).
const advanceTextPtBR = {
  // Controles da linha (−10/+10/slider)
  decrease: '−10%',
  increase: '+10%',
  progressLabel: 'Progresso da tarefa',
  // impeccable critique P1 — o slider é o controle mais importante da linha e era
  // anônimo para o leitor de tela ("Progresso, slider" em toda linha). Nomeado por
  // tarefa, o operador sabe QUAL tarefa está avançando (D15 — métrica nomeada para SR).
  progressLabelFor: (task: string) => `Progresso de "${task}"`,
  readOnlyHint: 'Só quem edita pode registrar avanço.',

  // Modal
  title: 'Registrar avanço',
  from: 'De',
  to: 'Para',
  toFieldLabel: 'Progresso alvo (%)',
  // Modo status (robot-task-table 2.1, §2.2) — o modal aberto pelo StatusSelect
  // nomeia o status escolhido; o `para%` exibido é o derivado da tabela-verdade.
  statusChange: (status: string) => `Novo status: ${status}`,

  // Rótulo condicional do comentário
  commentLabelRequired: 'Comentário (obrigatório abaixo de 100%)',
  commentLabelOptional: 'Comentário (opcional)',
  commentPlaceholder: 'O que foi feito?',
  commentRequiredHint: 'Explique o que falta para concluir.',

  confirm: 'Registrar',
  cancel: 'Cancelar',
  close: 'Fechar',
  saving: 'Registrando…',
  genericFailure: 'Não foi possível registrar o avanço agora.',

  // Offline / enfileirado (progress-advances 7.2 / Princípio 2 — estado honesto):
  // quando sem rede, o avanço é ENFILEIRADO, não salvo. O modal não pode fechar
  // como "salvo" — diz a verdade e o usuário fecha ciente.
  queuedTitle: 'Sem rede — avanço enfileirado',
  queuedHint: 'Vamos enviar assim que a conexão voltar. Nada foi perdido.',

  // Conflito (409 / D-409) — não descarta o que a pessoa escreveu
  conflictTitle: 'Alguém avançou esta tarefa enquanto você escrevia',
  conflictBy: (author: string, value: number) => `${author} registrou ${value}%.`,
  conflictWhen: (when: string) => `Em ${when}.`,
  recalculate: (value: number) => `Recalcular a partir de ${value}%`,
  discard: 'Descartar',
}

// internationalization D-I2 — SEM `as const`: o tipo alarga os literais para `string`
// e `en` pode ter outro texto. Os sweeps leem o TEXTO do arquivo, não o tipo — o
// canônico pt-BR segue estático e verificável. O idioma é resolvido no runtime.
export type AdvanceText = typeof advanceTextPtBR
export const advanceText: AdvanceText = defineText(advanceTextPtBR, advanceTextEn)
