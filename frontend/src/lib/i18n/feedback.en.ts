import type { FeedbackText } from './feedback'

// internationalization G4 — tradução EN do canal de feedback do beta. Glossário
// confirmado: "Send feedback".
export const feedbackTextEn: FeedbackText = {
  menuItem: 'Send feedback',
  title: 'Send feedback',
  intro:
    'Found a problem or have an idea? Let us know — that is how RoboTrack improves during the beta.',
  messageLabel: 'Your message',
  messagePlaceholder: 'Describe what happened, what you expected, or what you would like to see…',
  contextNote:
    'We include the following so we can understand the context: the screen you are on, the workspace, your role and device information. No password or sensitive data is collected.',
  contextToggleShow: 'See what will be sent',
  contextToggleHide: 'Hide details',
  send: 'Send feedback',
  sending: 'Sending…',
  cancel: 'Cancel',
  successToast: 'Thank you! We received your feedback.',
  errorEmpty: 'Write your message before sending.',
  errorGeneric: 'Could not send right now. Check your connection and try again.',

  inboxTitle: 'Tester feedback',
  inboxSubtitle:
    'Messages sent from within the app by the members of this workspace, each with its context.',
  inboxLoading: 'Loading…',
  inboxError: 'Could not load the feedback.',
  inboxEmpty: 'No feedback received yet. When a tester sends some, it appears here.',
  inboxCount: (n: number) => `${n} ${n === 1 ? 'message' : 'messages'}`,
  inboxAnon: 'Author removed',
  contextLabel: 'Context',
}
