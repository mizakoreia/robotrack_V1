import { describe, it, expect, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { HomePage } from '../HomePage'
import { MemoryRouter } from 'react-router-dom'

vi.mock('@/lib/api/endpoints', () => ({
  plansApi: {
    list: async () => ({ plans: [
      { id: 1, title: 'Robotrack Start', price: 49.9, billing_kind: 'one_time', is_popular: false, features: [ { id: 11, title: 'Tema Dark/Light' } ] },
      { id: 2, title: 'Robotrack Pro', price: 199.9, billing_kind: 'subscription', is_popular: true, features: [ { id: 21, title: 'Tema Dark/Light' }, { id: 22, title: 'Console de Administração' } ] },
    ], total: 2 })
  }
}))

function Wrapper({ children }: { children: React.ReactNode }) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false, staleTime: 0 } } })
  return (
    <QueryClientProvider client={client}>
      <MemoryRouter>
        {children}
      </MemoryRouter>
    </QueryClientProvider>
  )
}

describe('HomePage Plans Section', () => {
  it('loads and renders plans comparison', async () => {
    render(<Wrapper><HomePage /></Wrapper>)
    await waitFor(() => expect(screen.getByText(/Escolha o plano ideal/i)).toBeDefined())
    await waitFor(() => expect(screen.getAllByText(/Robotrack Start/i).length).toBeGreaterThan(0))
    await waitFor(() => expect(screen.getAllByText(/Robotrack Pro/i).length).toBeGreaterThan(0))
    await waitFor(() => expect(screen.getByText(/Comparação de planos/i)).toBeDefined())
  })
})
