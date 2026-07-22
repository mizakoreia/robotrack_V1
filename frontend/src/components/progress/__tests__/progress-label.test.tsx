import { describe, expect, it } from 'vitest'
import { render, screen } from '@testing-library/react'
import { readFileSync, readdirSync, statSync } from 'node:fs'
import { join } from 'node:path'
import type { ReactElement } from 'react'
import { ProgressRing } from '../ProgressRing'
import { MetricStat } from '../MetricStat'
import { progressText, type ProgressMetricKind } from '../../../lib/i18n/progress'

// progress-rollup 6.3/6.5/6.1 (D15/D14) — os sweeps de rótulo. Todo componente
// que exibe progresso é renderizado e falha se o nome acessível não contiver um
// dos dois rótulos; a Visão Geral mostra hub 20% e anel 58% com rótulos DISTINTOS;
// e nenhum literal de rótulo vive fora do módulo de strings.

const LABELS = [progressText.metrics.weighted.label, progressText.metrics.raw_count.label]

// Registro dos componentes que EXIBEM progresso (o sweep cresce com eles).
const PROGRESS_COMPONENTS: Array<{ name: string; render: (metric: ProgressMetricKind) => ReactElement }> = [
  { name: 'ProgressRing', render: (m) => <ProgressRing value={58} metric={m} /> },
  { name: 'MetricStat', render: (m) => <MetricStat completed={1} total={5} percent={20} metric={m} /> },
]

describe('sweep de rótulo (6.3)', () => {
  PROGRESS_COMPONENTS.forEach(({ name, render: renderComp }) => {
    it(`${name} anuncia o rótulo da métrica no nó acessível`, () => {
      const { unmount } = render(renderComp('weighted'))
      const acessivel = screen.getByLabelText(new RegExp(LABELS[0], 'i'))
      expect(acessivel).toBeInTheDocument()
      unmount()
    })
  })
})

describe('anel do card com a métrica ponderada (6.2)', () => {
  it('ProgressRing value=58 metric=weighted expõe "Progresso ponderado" e "58%"', () => {
    render(<ProgressRing value={58} metric="weighted" />)
    const node = screen.getByRole('img')
    expect(node).toHaveAccessibleName('Progresso ponderado: 58%')
  })
})

describe('hub e card na mesma tela, rótulos distintos (6.5 — dataset de divergência)', () => {
  it('anel 58% (ponderado) e hub 1/5 20% (crua) aparecem juntos, rotulados e distintos', () => {
    render(
      <div>
        <MetricStat completed={1} total={5} percent={20} metric="raw_count" />
        <ProgressRing value={58} metric="weighted" />
      </div>,
    )
    // os dois rótulos, distintos
    expect(screen.getByLabelText(/Progresso físico/i)).toBeInTheDocument()
    expect(screen.getByLabelText(/Progresso ponderado/i)).toBeInTheDocument()
    // os dois números da divergência, simultâneos
    expect(screen.getByText(/1\/5 · 20%/)).toBeInTheDocument()
    expect(screen.getByText('58%')).toBeInTheDocument()
  })
})

describe('lint de rótulo literal (6.1)', () => {
  it('nenhum literal de rótulo vive fora de lib/i18n/progress.ts', () => {
    const root = join(__dirname, '../../../') // src/
    const modulo = join(root, 'lib/i18n/progress.ts')
    const offenders: string[] = []

    const walk = (dir: string) => {
      for (const entry of readdirSync(dir)) {
        const full = join(dir, entry)
        if (statSync(full).isDirectory()) {
          if (entry !== 'node_modules') walk(full)
          continue
        }
        if (!/\.(ts|tsx)$/.test(entry)) continue
        if (full === modulo) continue
        if (full.includes('__tests__')) continue // este próprio spec cita os rótulos
        const content = readFileSync(full, 'utf8')
        for (const label of LABELS) {
          if (content.includes(label)) offenders.push(`${full}: ${label}`)
        }
      }
    }
    walk(root)

    expect(offenders, `rótulo literal fora de progress.ts:\n${offenders.join('\n')}`).toHaveLength(0)
  })
})
