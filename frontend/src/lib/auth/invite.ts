import { safeStorage } from '../safeStorage'

// Token de convite (identity-and-auth 6.4 / D4.4). Vive em sessionStorage sob
// `robotrack.invite_token` durante o fluxo de login e sobrevive às duas
// navegações de página inteira do Google (mesma aba, mesma origem). Quando o
// storage está bloqueado, cai para memória — que NÃO sobrevive ao redirect do
// Google; esse caso é detectado no retorno (ver OAuthCallbackPage).
const INVITE_KEY = 'robotrack.invite_token'
// invite-by-code: o PAR código+e-mail sobrevive às mesmas duas navegações do
// Google, sob sua própria chave. É `{ code, email }` serializado — o par é o que o
// aceite por código exige.
const INVITE_CODE_KEY = 'robotrack.invite_code'

export interface InviteCodePair {
  code: string
  email: string
}

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

  // Par código+e-mail (análogo ao token, para o fluxo por código).
  captureCode(pair: InviteCodePair): boolean {
    return safeStorage.set('session', INVITE_CODE_KEY, JSON.stringify(pair))
  },
  readCode(): InviteCodePair | null {
    const raw = safeStorage.get('session', INVITE_CODE_KEY)
    if (!raw) return null
    try {
      const parsed = JSON.parse(raw) as Partial<InviteCodePair>
      if (typeof parsed?.code === 'string' && typeof parsed?.email === 'string') {
        return { code: parsed.code, email: parsed.email }
      }
    } catch {
      /* valor corrompido — trata como ausente */
    }
    return null
  },
  clearCode(): void {
    safeStorage.remove('session', INVITE_CODE_KEY)
  },
}
