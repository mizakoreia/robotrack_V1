import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import { PaymentsPage } from '../PaymentsPage'
import * as endpoints from '@/lib/api/endpoints'

describe('Sales table', () => {
  beforeEach(() => {
    vi.spyOn(endpoints, 'salesApi', 'get').mockReturnValue({
      list: vi.fn().mockResolvedValue({ sales: [], total: 0 })
    } as any)
  })

  it('renders table headers and empty state', async () => {
    render(<PaymentsPage />)
    expect(screen.getByText('Vendas')).toBeInTheDocument()
    expect(screen.getByText('Cliente')).toBeInTheDocument()
    await waitFor(() => {
      expect(screen.getByText('Nenhuma venda encontrada')).toBeInTheDocument()
    })
  })
})

