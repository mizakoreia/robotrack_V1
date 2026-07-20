import { describe, it, expect, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'
import { AdminFeaturesPage } from '../AdminFeaturesPage'

vi.mock('@/lib/api/endpoints', () => ({
  planFeaturesAdminApi: {
    list: async () => ({ plan_features: [
      { id: '11', title: 'Tema Dark/Light', identifier: 'theme-toggle', active: true, permission: { id: 'p1', key: 'theme_toggle' } },
      { id: '21', title: 'Console Admin', identifier: 'console-access', active: true, permission: { id: 'p2', key: 'console_access' } }
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

describe('AdminFeaturesPage', () => {
  it('lista features e mostra permission.key', async () => {
    render(<Wrapper><AdminFeaturesPage /></Wrapper>)
    await waitFor(() => expect(screen.getAllByText(/Features/i).length).toBeGreaterThan(0))
    await waitFor(() => expect(screen.getByText(/Tema Dark\/Light/i)).toBeDefined())
    await waitFor(() => expect(screen.getAllByText(/Permissão:/i).length).toBeGreaterThan(0))
  })
})
