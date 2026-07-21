import { safeStorage } from '../safeStorage'

// Estado efêmero do fluxo OAuth (identity-and-auth 5.4/6.6). Guarda, em
// sessionStorage:
//   - a escolha de "manter conectado" feita ANTES do redirect do Google, para o
//     callback saber em qual storage gravar a sessão de volta;
//   - um marcador de que a entrada no fluxo foi por um link de convite, usado
//     para detectar o convite perdido quando o storage bloqueia o token.
const REMEMBER_KEY = 'robotrack.oauth_remember'
const ENTRY_KEY = 'robotrack.entry_was_invite'

export const oauthState = {
  setRemember(v: boolean): void {
    safeStorage.set('session', REMEMBER_KEY, v ? 'true' : 'false')
  },
  getRemember(): boolean {
    return safeStorage.get('session', REMEMBER_KEY) === 'true'
  },
  clearRemember(): void {
    safeStorage.remove('session', REMEMBER_KEY)
  },

  markInviteEntry(): void {
    safeStorage.set('session', ENTRY_KEY, '1')
  },
  wasInviteEntry(): boolean {
    return safeStorage.get('session', ENTRY_KEY) === '1'
  },
  clearInviteEntry(): void {
    safeStorage.remove('session', ENTRY_KEY)
  },
}
