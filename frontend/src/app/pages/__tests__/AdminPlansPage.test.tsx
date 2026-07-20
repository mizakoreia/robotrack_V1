import { describe, it, expect, vi } from 'vitest'
import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'
import { AdminPlansPage } from '../AdminPlansPage'

vi.mock('@/lib/api/endpoints', () => ({
  plansAdminApi: {
    list: async () => ({ plans: [
      { id: '1', title: 'Robotrack Start', identifier: 'robotrack-start', price: 49.9, billing_kind: 'one_time', active: true, free: false, popular: false, features: [ { id: '11', title: 'Tema Dark/Light', identifier: 'theme-toggle', active: true } ] },
      { id: '2', title: 'Robotrack Pro', identifier: 'robotrack-pro', price: 199.9, billing_kind: 'subscription', active: true, free: false, popular: true, features: [ { id: '21', title: 'Console Admin', identifier: 'console-access', active: true } ] }
    ], total: 2 }),
    delete: async () => ({ success: true })
  },
  planFeaturesAdminApi: {
    list: async () => ({ plan_features: [
      { id: '11', title: 'Tema Dark/Light', identifier: 'theme-toggle', active: true },
      { id: '21', title: 'Console Admin', identifier: 'console-access', active: true }
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

describe('AdminPlansPage', () => {
  it('lista planos com filtros e cartões', async () => {
    render(<Wrapper><AdminPlansPage /></Wrapper>)
    await waitFor(() => expect(screen.getByText(/Robotrack Start/i)).toBeDefined())
    await waitFor(() => expect(screen.getByText(/Robotrack Pro/i)).toBeDefined())
    fireEvent.change(screen.getByPlaceholderText(/Buscar por título/i), { target: { value: 'Pro' } })
  })
})
