import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor, cleanup } from '@testing-library/react'

// send-feedback — o modal de envio. As falhas a caçar: enviar mensagem vazia (não
// deve — erro inline, sem request); no sucesso não fechar (deve fechar + toast);
// na falha fechar (não deve — fica aberto com o texto). A mutation é mockada; o
// contexto automático é montado pela própria tela.

const { mutateMock, resetMock, toastSuccessMock } = vi.hoisted(() => ({
  mutateMock: vi.fn(),
  resetMock: vi.fn(),
  toastSuccessMock: vi.fn(),
}))

let pending = false

vi.mock('../useFeedback', () => ({
  useSubmitFeedback: () => ({ mutate: mutateMock, reset: resetMock, isPending: pending }),
}))

vi.mock('sonner', () => ({ toast: { success: toastSuccessMock } }))

vi.mock('react-router-dom', async () => {
  const real = await vi.importActual<typeof import('react-router-dom')>('react-router-dom')
  return { ...real, useLocation: () => ({ pathname: '/robo/42' }) }
})

import { SendFeedbackDialog } from '../SendFeedbackDialog'
import { useWorkspaceStore } from '@/store/workspaceStore'
import { feedbackText as T } from '@/lib/i18n/feedback'

const onCloseMock = vi.fn()

function abrir() {
  render(<SendFeedbackDialog open onClose={onCloseMock} />)
}

describe('SendFeedbackDialog', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    cleanup()
    pending = false
    useWorkspaceStore.setState({
      currentWorkspaceId: 'ws1',
      currentRoleLabel: 'view',
      workspaces: [{ id: 'ws1', name: 'Fábrica Demo', role: 'view' }],
    } as never)
  })

  it('mostra a intro e o campo de mensagem', () => {
    abrir()
    expect(screen.getByText(T.intro)).toBeInTheDocument()
    expect(screen.getByLabelText(T.messageLabel)).toBeInTheDocument()
  })

  it('mensagem vazia NÃO envia e mostra erro inline', () => {
    abrir()
    fireEvent.click(screen.getByRole('button', { name: T.send }))
    expect(screen.getByText(T.errorEmpty)).toBeInTheDocument()
    expect(mutateMock).not.toHaveBeenCalled()
  })

  it('envia mensagem + contexto automático (rota/workspace/papel/dispositivo)', () => {
    abrir()
    fireEvent.change(screen.getByLabelText(T.messageLabel), { target: { value: '  achei um bug  ' } })
    fireEvent.click(screen.getByRole('button', { name: T.send }))

    expect(mutateMock).toHaveBeenCalledTimes(1)
    const [payload] = mutateMock.mock.calls[0]
    expect(payload.message).toBe('achei um bug') // trim
    expect(payload.context.route).toBe('/robo/42')
    expect(payload.context.workspace_id).toBe('ws1')
    expect(payload.context.workspace_name).toBe('Fábrica Demo')
    expect(payload.context.role).toBe('view')
    expect(typeof payload.context.user_agent).toBe('string')
  })

  it('sucesso: dá toast de agradecimento e fecha', async () => {
    mutateMock.mockImplementation((_input, opts) => opts.onSuccess())
    abrir()
    fireEvent.change(screen.getByLabelText(T.messageLabel), { target: { value: 'ótimo app' } })
    fireEvent.click(screen.getByRole('button', { name: T.send }))

    await waitFor(() => expect(toastSuccessMock).toHaveBeenCalledWith(T.successToast))
    expect(onCloseMock).toHaveBeenCalled()
  })

  it('falha: NÃO fecha e mostra erro (o texto fica para reenviar)', async () => {
    mutateMock.mockImplementation((_input, opts) => opts.onError(new Error('x')))
    abrir()
    fireEvent.change(screen.getByLabelText(T.messageLabel), { target: { value: 'tentativa' } })
    fireEvent.click(screen.getByRole('button', { name: T.send }))

    await waitFor(() => expect(screen.getByText(T.errorGeneric)).toBeInTheDocument())
    expect(onCloseMock).not.toHaveBeenCalled()
    expect((screen.getByLabelText(T.messageLabel) as HTMLTextAreaElement).value).toBe('tentativa')
  })

  it('o disclosure de contexto revela a rota atual', () => {
    abrir()
    fireEvent.click(screen.getByRole('button', { name: T.contextToggleShow }))
    expect(screen.getByText('/robo/42')).toBeInTheDocument()
  })

  it('Esc fecha o diálogo', () => {
    abrir()
    fireEvent.keyDown(document, { key: 'Escape' })
    expect(onCloseMock).toHaveBeenCalled()
  })
})
