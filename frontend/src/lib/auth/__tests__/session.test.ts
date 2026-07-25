import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'

// identity-and-auth 6.8 — ciclo de sessão e do convite por CÓDIGO (§4.2).
// code-only-invites: o convite é só por CÓDIGO (o link por token foi removido).
// As falhas a caçar: o convite ser descartado em silêncio quando o
// `sessionStorage` está bloqueado; ser reconsumido a cada recarga; um convite
// expirado prender o usuário numa tela de erro; e o cache do React Query do
// usuário anterior sobreviver ao logout.
//
// O quarto cenário de 6.8 — "401 encerra sem laço" — é exercitado em
// `src/lib/api/__tests__/client.session.test.ts`, que instrumenta o adapter do
// axios e prova que o 401 limpa o store, não retenta e não dispara renovação.

const { acceptByCodeMock, previewByCodeMock, logoutMock, toastMock } = vi.hoisted(() => ({
  acceptByCodeMock: vi.fn(),
  previewByCodeMock: vi.fn(),
  logoutMock: vi.fn(),
  toastMock: { warning: vi.fn(), error: vi.fn(), success: vi.fn(), info: vi.fn() },
}))

vi.mock('../../api/endpoints', () => ({
  authApi: { logout: logoutMock },
  invitationsApi: { acceptByCode: acceptByCodeMock, previewByCode: previewByCodeMock },
}))

vi.mock('sonner', () => ({ toast: toastMock }))

import { handleInviteAfterAuth, performLogout } from '../session'
import { inviteStore } from '../invite'
import { oauthState } from '../oauthState'
import { safeStorage, withStorageTimeout } from '../../safeStorage'
import { useAuthStore } from '../../../store/authStore'
import { queryClient } from '../../queryClient'

const PAR = { code: 'ABCD1234', email: 'joao@fabrica.com' }

function limparTudo() {
  inviteStore.clearCode()
  oauthState.clearInviteEntry()
  oauthState.clearRemember()
  useAuthStore.getState().clearSession()
  queryClient.clear()
  try {
    sessionStorage.clear()
    localStorage.clear()
  } catch {
    /* storage bloqueado no teste */
  }
}

describe('ciclo do convite por código', () => {
  beforeEach(() => {
    acceptByCodeMock.mockReset().mockResolvedValue(undefined)
    logoutMock.mockReset().mockResolvedValue(undefined)
    Object.values(toastMock).forEach((fn) => fn.mockReset())
    limparTudo()
  })

  it('par guardado antes do login é consumido logo após autenticar', async () => {
    inviteStore.captureCode(PAR)
    expect(inviteStore.readCode()).toEqual(PAR)

    await handleInviteAfterAuth()

    expect(acceptByCodeMock).toHaveBeenCalledTimes(1)
    expect(acceptByCodeMock).toHaveBeenCalledWith(PAR)
    // A chave é removida: a recarga não o reconsome.
    expect(inviteStore.readCode()).toBeNull()
  })

  it('não reconsome o convite numa recarga posterior', async () => {
    inviteStore.captureCode(PAR)
    await handleInviteAfterAuth()
    acceptByCodeMock.mockClear()

    await handleInviteAfterAuth() // "recarga"

    expect(acceptByCodeMock).not.toHaveBeenCalled()
  })

  it('convite expirado (410) avisa e mantém o usuário autenticado, sem lançar', async () => {
    inviteStore.captureCode(PAR)
    acceptByCodeMock.mockRejectedValue({ response: { status: 410 } })

    await expect(handleInviteAfterAuth()).resolves.toBeUndefined()

    expect(toastMock.warning).toHaveBeenCalledWith(expect.stringMatching(/expirou/i))
    expect(inviteStore.readCode()).toBeNull()
  })

  it('convite perdido no redirect (storage bloqueado) é detectado, não descartado em silêncio', async () => {
    // A entrada foi por um convite, mas o par não sobreviveu.
    oauthState.markInviteEntry()
    expect(inviteStore.readCode()).toBeNull()

    await handleInviteAfterAuth()

    expect(acceptByCodeMock).not.toHaveBeenCalled()
    expect(toastMock.warning).toHaveBeenCalledWith(expect.stringMatching(/peça o código/i))
    // O marcador é consumido: não avisa de novo na próxima navegação.
    expect(oauthState.wasInviteEntry()).toBe(false)
  })

  it('sem convite e sem marcador, não avisa nem chama o aceite', async () => {
    await handleInviteAfterAuth()

    expect(acceptByCodeMock).not.toHaveBeenCalled()
    expect(toastMock.warning).not.toHaveBeenCalled()
  })
})

describe('storage bloqueado não trava o fluxo', () => {
  let setItemSpy: ReturnType<typeof vi.spyOn>

  beforeEach(() => {
    limparTudo()
    // Safari privado / bloqueador: qualquer escrita lança.
    setItemSpy = vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('QuotaExceededError')
    })
  })

  afterEach(() => {
    setItemSpy.mockRestore()
    limparTudo()
  })

  it('safeStorage cai para memória em vez de propagar a exceção', () => {
    const persistiu = safeStorage.set('session', 'chave', 'valor')

    expect(persistiu).toBe(false) // não persistiu no storage REAL
    expect(safeStorage.get('session', 'chave')).toBe('valor') // mas segue legível
  })

  it('o convite é capturado em memória e ainda é consumível no mesmo carregamento', async () => {
    const persistiu = inviteStore.captureCode(PAR)

    expect(persistiu).toBe(false)
    expect(inviteStore.readCode()).toEqual(PAR)

    await handleInviteAfterAuth()
    expect(acceptByCodeMock).toHaveBeenCalledWith(PAR)
  })

  it('o handshake do storage resolve dentro do timeout, sem pendurar o login', async () => {
    const resultado = await withStorageTimeout(() => {
      useAuthStore.getState().setSession('token-x', { id: 'u1' }, { remember: true })
      return useAuthStore.getState().memoryOnly
    }, 1500)

    expect(resultado.timedOut).toBe(false)
    // Sessão vive em memória (storage bloqueado), mas o login prosseguiu.
    expect(useAuthStore.getState().isAuthenticated).toBe(true)
    expect(useAuthStore.getState().memoryOnly).toBe(true)
  })

  it('withStorageTimeout devolve timedOut quando a operação estoura o prazo', async () => {
    vi.useFakeTimers()
    const promessa = withStorageTimeout(() => new Promise(() => {}) as unknown as string, 1500)
    await vi.advanceTimersByTimeAsync(1600)
    const resultado = await promessa
    vi.useRealTimers()

    expect(resultado.timedOut).toBe(true)
  })
})

describe('logout', () => {
  beforeEach(() => {
    acceptByCodeMock.mockReset().mockResolvedValue(undefined)
    logoutMock.mockReset().mockResolvedValue(undefined)
    Object.values(toastMock).forEach((fn) => fn.mockReset())
    limparTudo()
  })

  it('chama DELETE da sessão, limpa store, storages, cache e redireciona', async () => {
    useAuthStore.getState().setSession('token-x', { id: 'u1' }, { remember: true })
    inviteStore.captureCode(PAR)
    queryClient.setQueryData(['perfil'], { nome: 'Ana' })
    const redirect = vi.fn()

    await performLogout(redirect)

    expect(logoutMock).toHaveBeenCalledTimes(1)
    expect(useAuthStore.getState().isAuthenticated).toBe(false)
    expect(useAuthStore.getState().accessToken).toBeNull()
    expect(inviteStore.readCode()).toBeNull()
    // Cache do usuário anterior NÃO sobrevive à troca de usuário na mesma aba.
    expect(queryClient.getQueryData(['perfil'])).toBeUndefined()
    expect(redirect).toHaveBeenCalledWith('/entrar')
  })

  it('com a rede fora, limpa o estado local mesmo assim', async () => {
    useAuthStore.getState().setSession('token-x', { id: 'u1' }, { remember: true })
    logoutMock.mockRejectedValue(new Error('network down'))
    const redirect = vi.fn()

    await expect(performLogout(redirect)).resolves.toBeUndefined()

    expect(useAuthStore.getState().isAuthenticated).toBe(false)
    expect(redirect).toHaveBeenCalledWith('/entrar')
  })

  it('a sessão não fica em localStorage quando "manter conectado" está desmarcado', () => {
    useAuthStore.getState().setSession('token-curto', { id: 'u1' }, { remember: false })

    expect(safeStorage.get('session', 'robotrack.session')).toContain('token-curto')
    expect(safeStorage.get('local', 'robotrack.session')).toBeNull()
  })

  it('trocar de modo limpa o armazenamento anterior', () => {
    useAuthStore.getState().setSession('token-longo', { id: 'u1' }, { remember: true })
    expect(safeStorage.get('local', 'robotrack.session')).toContain('token-longo')

    useAuthStore.getState().clearSession()
    useAuthStore.getState().setSession('token-curto', { id: 'u1' }, { remember: false })

    expect(safeStorage.get('local', 'robotrack.session')).toBeNull()
    expect(safeStorage.get('session', 'robotrack.session')).toContain('token-curto')
  })
})
