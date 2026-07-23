import { describe, it, expect, beforeEach } from 'vitest'
import { render, screen, act } from '@testing-library/react'
import { LiveRegions } from '../LiveRegions'
import { LiveAnnouncer } from '../LiveAnnouncer'
import { useLiveRegionStore, announce } from '@/store/liveRegionStore'
import { useRealtimeStore } from '@/store/realtimeStore'

describe('quality-and-accessibility 5.1 — regiões vivas persistentes', () => {
  beforeEach(() => {
    useLiveRegionStore.setState({ status: '', notifications: '', alerts: '' })
    useRealtimeStore.setState({ transport: 'live', synced: true })
  })

  it('as três regiões existem VAZIAS no DOM desde a montagem (não inseridas com texto)', () => {
    const { container } = render(<LiveRegions />)
    const status = container.querySelector('#rt-status')!
    const notifs = container.querySelector('#rt-notifications')!
    const alerts = container.querySelector('#rt-alerts')!
    expect(status).toBeInTheDocument()
    expect(notifs).toBeInTheDocument()
    expect(alerts).toBeInTheDocument()
    expect(status.textContent).toBe('')
    // status = polite/atomic; alerts = assertive + role=alert
    expect(status).toHaveAttribute('aria-live', 'polite')
    expect(status).toHaveAttribute('aria-atomic', 'true')
    expect(alerts).toHaveAttribute('aria-live', 'assertive')
    expect(alerts).toHaveAttribute('role', 'alert')
  })

  it('announce() muda o texto da região já montada (é o que o leitor anuncia)', () => {
    const { container } = render(<LiveRegions />)
    act(() => announce('alerts', 'Você saiu do workspace'))
    expect(container.querySelector('#rt-alerts')!.textContent).toBe('Você saiu do workspace')
    act(() => announce('notifications', '2 não lidas'))
    expect(container.querySelector('#rt-notifications')!.textContent).toBe('2 não lidas')
  })

  it('LiveAnnouncer roteia a TRANSIÇÃO de transporte para #rt-status (não o estado inicial)', () => {
    const { container } = render(
      <>
        <LiveRegions />
        <LiveAnnouncer />
      </>,
    )
    // montou em 'live' → nada anunciado (não fala "conectado" ao abrir)
    expect(container.querySelector('#rt-status')!.textContent).toBe('')
    act(() => useRealtimeStore.setState({ transport: 'offline' }))
    expect(container.querySelector('#rt-status')!.textContent).toBe('Sem conexão')
    act(() => useRealtimeStore.setState({ transport: 'live' }))
    expect(container.querySelector('#rt-status')!.textContent).toBe('Conexão restabelecida')
  })
})
