import React from 'react'
import { Button } from '@/components/ui/Button'

export function HeroCampfire() {
  const [, setPlansVisible] = React.useState(false)
  React.useEffect(() => {
    const plansEl = document.getElementById('plans')
    const quickPayEl = document.getElementById('quick-pay-btn')
    if (!plansEl || !quickPayEl) return
    const obs = new IntersectionObserver(
      (entries) => {
        const e = entries[0]
        setPlansVisible(e.isIntersecting)
        const card = document.querySelector('.header-card-toggle') as HTMLElement | null
        if (card) {
          card.classList.toggle('campfire-card-out', e.isIntersecting)
          card.classList.toggle('campfire-card-in', !e.isIntersecting)
        }
      },
      { root: null, threshold: 0.2 }
    )
    obs.observe(plansEl)
    const obsQuick = new IntersectionObserver((entries) => {
      const e = entries[0]
      window.dispatchEvent(new CustomEvent('quickpay:visible', { detail: { visible: e.isIntersecting } }))
    }, { root: null, threshold: 0.2 })
    obsQuick.observe(quickPayEl)
    return () => { obs.disconnect(); obsQuick.disconnect() }
  }, [])

  return (
    <section className="px-6 md:px-12 pt-28 pb-12 campfire-body">
      <div className="max-w-6xl mx-auto lg:pr-[var(--header-card-w)]">
        <div className="max-w-3xl lg:pr-6 lg:mr-[48px]">
          <h1 className="text-5xl md:text-7xl font-extrabold tracking-tight">Crie e lance seus produtos com velocidade</h1>
          <p className="mt-4 text-base md:text-lg text-muted-foreground">Stack moderna, automações e um fluxo centrado em pagamento para acelerar sua operação.</p>
          <div className="mt-8 flex items-center gap-4">
            <a id="quick-pay-btn" href="#" target="_blank" rel="noopener noreferrer">
              <Button variant="uiverse" className="px-4 py-2 h-11 text-sm">Pagamento rápido</Button>
            </a>
            <a href="#plans" className="text-sm underline">Ver planos</a>
          </div>
        </div>
      </div>
    </section>
  )
}
