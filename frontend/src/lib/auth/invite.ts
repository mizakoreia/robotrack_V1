import { safeStorage } from '../safeStorage'

// Token de convite (identity-and-auth 6.4 / D4.4). Vive em sessionStorage sob
// `robotrack.invite_token` durante o fluxo de login e sobrevive às duas
// navegações de página inteira do Google (mesma aba, mesma origem). Quando o
// storage está bloqueado, cai para memória — que NÃO sobrevive ao redirect do
// Google; esse caso é detectado no retorno (ver OAuthCallbackPage).
const INVITE_KEY = 'robotrack.invite_token'

export const inviteStore = {
  // Devolve `true` se persistiu no sessionStorage real (sobrevive ao redirect).
  capture(token: string): boolean {
    return safeStorage.set('session', INVITE_KEY, token)
  },
  read(): string | null {
    return safeStorage.get('session', INVITE_KEY)
  },
  clear(): void {
    safeStorage.remove('session', INVITE_KEY)
  },
}
