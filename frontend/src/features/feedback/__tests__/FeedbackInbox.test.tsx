import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, cleanup } from '@testing-library/react'

// send-feedback — a caixa do dono. Estados distintos (carregando/erro/vazio/lista),
// autor + contexto por item, e o fallback de autor removido.

const { useFeedbacksMock } = vi.hoisted(() => ({ useFeedbacksMock: vi.fn() }))

vi.mock('../useFeedback', () => ({ useFeedbacks: useFeedbacksMock }))

import { FeedbackInbox } from '../FeedbackInbox'
import { feedbackText as T } from '@/lib/i18n/feedback'
import type { FeedbackDTO } from '@/lib/api/endpoints'

function seed(state: Partial<{ data: FeedbackDTO[]; isLoading: boolean; isError: boolean }>) {
  useFeedbacksMock.mockReturnValue({ data: undefined, isLoading: false, isError: false, ...state })
}

const UM: FeedbackDTO = {
  id: 'f1',
  message: 'O slider trava com luva',
  context: { route: '/robo/7', role: 'edit' },
  created_at: '2026-07-30T12:00:00Z',
  submitter: { name: 'Léo', email: 'leo@fabrica.com' },
}

describe('FeedbackInbox', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    cleanup()
  })

  it('carregando: mostra o estado de carga', () => {
    seed({ isLoading: true })
    render(<FeedbackInbox />)
    expect(screen.getByText(T.inboxLoading)).toBeInTheDocument()
  })

  it('erro: mostra o estado de erro', () => {
    seed({ isError: true })
    render(<FeedbackInbox />)
    expect(screen.getByText(T.inboxError)).toBeInTheDocument()
  })

  it('vazio: mostra o estado vazio', () => {
    seed({ data: [] })
    render(<FeedbackInbox />)
    expect(screen.getByText(T.inboxEmpty)).toBeInTheDocument()
  })

  it('lista: mensagem, autor, contagem e contexto sob disclosure', () => {
    seed({ data: [UM] })
    render(<FeedbackInbox />)
    expect(screen.getByText('O slider trava com luva')).toBeInTheDocument()
    expect(screen.getByText('Léo')).toBeInTheDocument()
    expect(screen.getByText('leo@fabrica.com')).toBeInTheDocument()
    expect(screen.getByText(T.inboxCount(1))).toBeInTheDocument()

    // contexto recolhido por padrão; abre ao clicar
    expect(screen.queryByText('/robo/7')).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: T.contextLabel }))
    expect(screen.getByText('/robo/7')).toBeInTheDocument()
  })

  it('autor removido: cai no fallback anônimo', () => {
    seed({ data: [{ ...UM, submitter: null }] })
    render(<FeedbackInbox />)
    expect(screen.getByText(T.inboxAnon)).toBeInTheDocument()
  })
})
