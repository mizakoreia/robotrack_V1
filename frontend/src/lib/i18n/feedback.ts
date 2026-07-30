import { defineText } from './defineText'
import { feedbackTextEn } from './feedback.en'

// Módulo ÚNICO dos textos do canal de feedback do beta (send-feedback, D14). Sem
// literal solto nas telas — o envio e a caixa do dono leem daqui.
const feedbackTextPtBR = {
  // Item do menu da conta + título do modal
  menuItem: 'Enviar feedback',
  title: 'Enviar feedback',
  intro:
    'Encontrou um problema ou tem uma ideia? Conte pra gente — é assim que o RoboTrack melhora durante o beta.',
  messageLabel: 'Sua mensagem',
  messagePlaceholder: 'Descreva o que aconteceu, o que esperava, ou o que gostaria de ver…',
  // Nota de transparência sobre o contexto capturado automaticamente
  contextNote:
    'Enviamos junto, para entender o contexto: a tela em que você está, o workspace, seu papel e informações do dispositivo. Nenhuma senha ou dado sensível é coletado.',
  contextToggleShow: 'Ver o que será enviado',
  contextToggleHide: 'Ocultar detalhes',
  send: 'Enviar feedback',
  sending: 'Enviando…',
  cancel: 'Cancelar',
  // Estados de resultado
  successToast: 'Obrigado! Recebemos seu feedback.',
  errorEmpty: 'Escreva sua mensagem antes de enviar.',
  errorGeneric: 'Não foi possível enviar agora. Verifique a conexão e tente novamente.',

  // Caixa de leitura do dono (em Configurações, owner-only)
  inboxTitle: 'Feedback dos testers',
  inboxSubtitle:
    'Mensagens enviadas de dentro do app pelos membros deste workspace, com o contexto de cada uma.',
  inboxLoading: 'Carregando…',
  inboxError: 'Não foi possível carregar os feedbacks.',
  inboxEmpty: 'Nenhum feedback recebido ainda. Quando um tester enviar, aparece aqui.',
  inboxCount: (n: number) => (n === 1 ? '1 feedback' : `${n} feedbacks`),
  inboxAnon: 'Autor removido',
  contextLabel: 'Contexto',
}

// internationalization D-I2 — SEM `as const`: o tipo alarga os literais para `string`
// e `en` pode ter outro texto. Os sweeps leem o TEXTO do arquivo, não o tipo.
export type FeedbackText = typeof feedbackTextPtBR
export const feedbackText: FeedbackText = defineText(feedbackTextPtBR, feedbackTextEn)
