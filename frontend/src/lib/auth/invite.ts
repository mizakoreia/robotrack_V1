import { safeStorage } from '../safeStorage'

// code-only-invites: o convite é só por CÓDIGO. O PAR código+e-mail sobrevive às
// duas navegações de página inteira do Google (mesma aba, mesma origem) sob sua
// própria chave. É `{ code, email }` serializado — o par é o que o aceite por
// código exige. Quando o storage está bloqueado, cai para memória — que NÃO
// sobrevive ao redirect do Google; esse caso é detectado no retorno (ver
// OAuthCallbackPage).
const INVITE_CODE_KEY = 'robotrack.invite_code'

export interface InviteCodePair {
  code: string
  email: string
}

export const inviteStore = {
  // Par código+e-mail: `true` se persistiu no sessionStorage real (sobrevive ao redirect).
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
