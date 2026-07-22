import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, within, renderHook, act } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import { RobotRouteKey } from '@/app/pages/RobotRouteKey'
import { useSuccessPulse } from '@/features/robot-tasks/useSuccessPulse'
import { STATUS_COLOR } from '@/features/robot-tasks/StatusCell'
import { robotTasksApi, type TaskDTO } from '@/lib/api/endpoints'
import { useWorkspaceStore } from '@/store/workspaceStore'

// robot-task-table 6.5 (§5.1, §3.5, DESIGN.md §Motion/Accessibility) — a verificação
// da trilha 6: o pulso aos 100% (uma vez, na transição observada), o refluxo em
// cartões preservando as 6 informações, os alvos de toque ≥40px e o contraste AA das
// variantes de status nos dois temas (jsdom não computa layout/axe; o contraste é
// calculado a partir dos tokens de design — trocar uma variante por outra de baixo
// contraste reprova).

// ---- 6.3 pulso ----
describe('useSuccessPulse (6.3)', () => {
  it('pulsa na transição <100 → 100, uma vez; 100→100 e 40→90 não pulsam', () => {
    let progress = 90
    const { result, rerender } = renderHook(() => useSuccessPulse(progress))
    expect(result.current.pulsing).toBe(false)

    progress = 100
    rerender()
    expect(result.current.pulsing).toBe(true) // cruzou para 100

    act(() => result.current.clear()) // onAnimationEnd
    expect(result.current.pulsing).toBe(false)

    progress = 100
    rerender()
    expect(result.current.pulsing).toBe(false) // 100→100 não repulsa
  })

  it('40 → 90 não pulsa (só a chegada exata a 100)', () => {
    let progress = 40
    const { result, rerender } = renderHook(() => useSuccessPulse(progress))
    progress = 90
    rerender()
    expect(result.current.pulsing).toBe(false)
  })
})

// ---- 6.1 / 6.2 refluxo em cartões + alvos ----
const HEADER = {
  id: 'r1', cell_id: 'c1', name: 'R01', application: 'Solda Ponto',
  weighted_progress: { value: 40, metric: 'weighted' as const, label: 'Progresso ponderado' },
}
function task(over: Partial<TaskDTO> = {}): TaskDTO {
  return {
    id: 't1', robot_id: 'r1', cat: 'A. Hardware', desc: 'Fixar base', weight: 1,
    progress: 45, status: 'Em Andamento', position: 0, lock_version: 0, updated_at: '',
    assignees: [{ id: 'ana', name: 'Ana' }], advances_count: 2, last_comment: 'meio',
    contributors: [], last_advance: null, ...over,
  }
}

// injeta matchMedia → mobile (min-width:768px NÃO casa)
function mockViewport(isDesktop: boolean) {
  Object.defineProperty(window, 'matchMedia', {
    configurable: true,
    writable: true,
    value: (q: string) => ({
      matches: isDesktop,
      media: q,
      addEventListener: () => {},
      removeEventListener: () => {},
      addListener: () => {},
      removeListener: () => {},
      onchange: null,
      dispatchEvent: () => false,
    }),
  })
}

describe('refluxo em cartões e alvos de toque (6.1/6.2)', () => {
  beforeEach(() => {
    mockViewport(false) // mobile: renderiza cartões
    useWorkspaceStore.setState({
      workspaces: [{ id: 'betim', name: 'Betim', role: 'owner' }],
      currentWorkspaceId: 'betim', currentRoleLabel: 'owner',
    })
    vi.spyOn(robotTasksApi, 'getRobot').mockResolvedValue(HEADER)
    vi.spyOn(robotTasksApi, 'listForRobot').mockResolvedValue([task()])
  })
  afterEach(() => {
    vi.restoreAllMocks()
    // @ts-expect-error limpa o mock de viewport
    delete window.matchMedia
  })

  async function renderPage() {
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
    render(
      <QueryClientProvider client={client}>
        <MemoryRouter initialEntries={['/robo/r1']}>
          <Routes>
            <Route path="/robo/:id" element={<RobotRouteKey />} />
          </Routes>
        </MemoryRouter>
      </QueryClientProvider>,
    )
    await screen.findAllByText('Fixar base')
  }

  it('o cartão mobile preserva as SEIS informações (rótulos de seção)', async () => {
    await renderPage()
    const card = document.querySelector('article')
    expect(card).not.toBeNull()
    const c = within(card as HTMLElement)
    // rótulos das colunas viram rótulos de linha do cartão
    expect(c.getByText('Status')).toBeInTheDocument()
    expect(c.getByText('Progresso')).toBeInTheDocument()
    expect(c.getByText('Responsáveis')).toBeInTheDocument()
    expect(c.getByText('Trilha')).toBeInTheDocument()
    expect(c.getByText('Fixar base')).toBeInTheDocument() // Tarefa
    // Ações: editar/excluir presentes no cartão
    expect(c.getByLabelText('Editar a descrição de Fixar base')).toBeInTheDocument()
  })

  it('os alvos ± e editar/excluir têm min ≥40px', async () => {
    await renderPage()
    for (const label of ['+10%', '−10%']) {
      expect(screen.getAllByLabelText(label)[0].className).toMatch(/min-h-\[40px\]/)
    }
    expect(screen.getAllByLabelText('Editar a descrição de Fixar base')[0].className).toMatch(/min-h-\[40px\]/)
    expect(screen.getAllByLabelText('Excluir Fixar base')[0].className).toMatch(/min-h-\[40px\]/)
  })

  it('a leitura de progresso expõe role=progressbar (6.4)', async () => {
    await renderPage()
    const bars = screen.getAllByRole('progressbar')
    expect(bars.length).toBeGreaterThan(0)
    expect(bars[0]).toHaveAttribute('aria-valuenow', '45')
  })
})

// ---- 6.5 contraste AA das variantes de status nos dois temas ----
// Tokens de design (globals.css). O ink é o texto; a pílula é a cor cheia a 15%
// sobre o fundo do painel. Contraste ink×pílula ≥ 4.5 (AA texto normal).
const TOKENS = {
  dark: {
    panel: '#121a2f',
    ink: { success: '#34d399', warning: '#fbbf24', accent: '#60a5fa', danger: '#f87171', na: '#d4d4d8' },
    full: { success: '#10b981', warning: '#f59e0b', accent: '#3b82f6', danger: '#ef4444', na: '#71717a' },
  },
  light: {
    panel: '#ffffff',
    ink: { success: '#065f46', warning: '#92400e', accent: '#1e40af', danger: '#b91c1c', na: '#3f3f46' },
    full: { success: '#10b981', warning: '#f59e0b', accent: '#3b82f6', danger: '#ef4444', na: '#71717a' },
  },
} as const

function hexToRgb(h: string) {
  const s = h.replace('#', '')
  return [0, 2, 4].map((i) => parseInt(s.slice(i, i + 2), 16))
}
function relLum([r, g, b]: number[]) {
  const f = (c: number) => {
    const x = c / 255
    return x <= 0.03928 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4
  }
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
}
function contrast(a: number[], b: number[]) {
  const la = relLum(a) + 0.05
  const lb = relLum(b) + 0.05
  return la > lb ? la / lb : lb / la
}
function composite(fg: number[], bg: number[], alpha: number) {
  return fg.map((c, i) => Math.round(c * alpha + bg[i] * (1 - alpha)))
}

describe('contraste AA das variantes de status (6.5)', () => {
  const statuses = Object.entries(STATUS_COLOR) as [string, keyof typeof TOKENS.dark.ink][]
  for (const theme of ['dark', 'light'] as const) {
    for (const [status, variant] of statuses) {
      it(`${theme}: "${status}" (${variant}) passa AA (≥4.5)`, () => {
        const t = TOKENS[theme]
        const pill = composite(hexToRgb(t.full[variant]), hexToRgb(t.panel), 0.15)
        const ratio = contrast(hexToRgb(t.ink[variant]), pill)
        expect(ratio).toBeGreaterThanOrEqual(4.5)
      })
    }
  }
})
