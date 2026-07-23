import { describe, it, expect, beforeEach } from 'vitest'
import { render, screen, act } from '@testing-library/react'
import { ConnectionIndicator } from '../ConnectionIndicator'
import { useRealtimeStore } from '@/store/realtimeStore'

describe('ConnectionIndicator (7.3)', () => {
  beforeEach(() => useRealtimeStore.setState({ transport: 'live', synced: true }))

  it('live/connecting não mostram nada (o silêncio é o estado saudável)', () => {
    useRealtimeStore.setState({ transport: 'live' })
    const { container } = render(<ConnectionIndicator />)
    expect(container.firstChild).toBeNull()
    act(() => useRealtimeStore.setState({ transport: 'connecting' }))
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
  })

  it('degraded → "Atualizando periodicamente"', () => {
    useRealtimeStore.setState({ transport: 'degraded', synced: true })
    render(<ConnectionIndicator />)
    expect(screen.getByRole('status')).toHaveTextContent('Atualizando periodicamente')
    expect(screen.getByRole('status')).not.toHaveTextContent('não sincronizado')
  })

  it('degraded + represamento estourado → admite "não sincronizado" (6.3)', () => {
    useRealtimeStore.setState({ transport: 'degraded', synced: false })
    render(<ConnectionIndicator />)
    expect(screen.getByRole('status')).toHaveTextContent('não sincronizado')
  })

  it('offline → "Sem conexão"', () => {
    useRealtimeStore.setState({ transport: 'offline' })
    render(<ConnectionIndicator />)
    expect(screen.getByRole('status')).toHaveTextContent('Sem conexão')
  })
})
