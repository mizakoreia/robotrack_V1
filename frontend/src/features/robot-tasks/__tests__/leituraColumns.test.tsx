import { describe, expect, it, beforeEach } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import { ResponsaveisCell } from '@/features/robot-tasks/ResponsaveisCell'
import { TrilhaCell } from '@/features/robot-tasks/TrilhaCell'
import { useWorkspaceStore } from '@/store/workspaceStore'
import type { TaskDTO } from '@/lib/api/endpoints'

// robot-task-table 3.5 (§3.5, D-RTT-4/6/7) — a matriz dos DOIS avisos e a
// disjunção assignees/contributors. A suíte falha se alguém reintroduzir a nota
// legada `obs`, trocar `>` por `>=`, ou mesclar contribuidores em responsáveis.

function task(over: Partial<TaskDTO> = {}): TaskDTO {
  return {
    id: 't1', robot_id: 'r1', cat: 'A. Hardware', desc: 'Fixar base', weight: 1,
    progress: 0, status: 'Pendente', position: 0, lock_version: 0, updated_at: '',
    assignees: [], advances_count: 0, last_comment: null, contributors: [],
    last_advance: null, ...over,
  }
}

beforeEach(() => {
  useWorkspaceStore.setState({
    workspaces: [{ id: 'betim', name: 'Betim', role: 'owner' }],
    currentWorkspaceId: 'betim',
    currentRoleLabel: 'owner',
  })
})

describe('Responsáveis — chips 1º/2º (D-RTT-4)', () => {
  it('assignee Ana + avanço de Bruno: Ana primário e Bruno secundário (2 chips)', () => {
    render(
      <ResponsaveisCell
        task={task({ assignees: [{ id: 'ana', name: 'Ana' }], contributors: [{ id: 'bruno', name: 'Bruno' }] })}
      />,
    )
    expect(screen.getByText('Ana')).toBeInTheDocument()
    expect(screen.getByText('Bruno')).toBeInTheDocument()
  })

  it('Ana responsável E única contribuidora: um único chip Ana', () => {
    render(
      <ResponsaveisCell
        task={task({
          progress: 60,
          assignees: [{ id: 'ana', name: 'Ana' }],
          contributors: [{ id: 'ana', name: 'Ana' }],
        })}
      />,
    )
    expect(screen.getAllByText('Ana')).toHaveLength(1)
  })
})

describe('Aviso "Atribuir…" — matriz progresso × responsável (D-RTT-7)', () => {
  const cases: [number, boolean, boolean][] = [
    // [progress, temResponsavel, esperaAviso]
    [0, false, false],
    [0, true, false],
    [30, false, true],
    [30, true, false],
    [100, false, true], // progresso 100 sem responsável ainda pede atribuição (progress > 0)
    [100, true, false],
  ]
  it.each(cases)('progress=%s, responsavel=%s → aviso=%s', (progress, temResp, espera) => {
    const { unmount } = render(
      <ResponsaveisCell
        task={task({ progress, assignees: temResp ? [{ id: 'ana', name: 'Ana' }] : [] })}
      />,
    )
    if (espera) expect(screen.getByText('Atribuir…')).toBeInTheDocument()
    else expect(screen.queryByText('Atribuir…')).toBeNull()
    unmount()
  })

  it('progress=45, sem responsável, contribuidor Bruno: aviso E chip secundário Bruno', () => {
    render(
      <ResponsaveisCell task={task({ progress: 45, assignees: [], contributors: [{ id: 'bruno', name: 'Bruno' }] })} />,
    )
    expect(screen.getByText('Atribuir…')).toBeInTheDocument()
    expect(screen.getByText('Bruno')).toBeInTheDocument()
  })
})

describe('Aviso "Registre o avanço…" — matriz progresso × avanços (D-RTT-6)', () => {
  const cases: [number, number, boolean][] = [
    // [progress, advances_count, esperaAviso]
    [0, 0, false],
    [50, 0, true],
    [100, 0, false], // 100 sem avanços NÃO é pendência de trilha (não trocar > por >=)
    [50, 1, false],
    [0, 1, false],
    [100, 3, false],
  ]
  it.each(cases)('progress=%s, advances=%s → aviso=%s', (progress, advances_count, espera) => {
    const { unmount } = render(<TrilhaCell robotId="r1" task={task({ progress, advances_count })} />)
    if (espera) expect(screen.getByText('Registre o avanço…')).toBeInTheDocument()
    else expect(screen.queryByText('Registre o avanço…')).toBeNull()
    unmount()
  })

  it('tarefa migrada (advances_count=1 legacy, progress=40): sem aviso E comentário visível', () => {
    render(
      <TrilhaCell
        robotId="r1"
        task={task({
          progress: 40,
          advances_count: 1,
          last_comment: 'Nota importada do legado',
          last_advance: {
            comment: 'Nota importada do legado',
            recorded_at: '2026-01-01T10:00:00Z',
            author_name_snapshot: 'Importador',
            legacy: true,
          },
        })}
      />,
    )
    expect(screen.queryByText('Registre o avanço…')).toBeNull()
    expect(screen.getByText('Nota importada do legado')).toBeInTheDocument()
  })
})

describe('Trilha — comentário e contagem (§3.5, D8)', () => {
  it('3 avanços: mostra o comentário do último por recorded_at e botão com aria de 3 entradas', () => {
    render(
      <TrilhaCell
        robotId="r1"
        task={task({
          progress: 60,
          advances_count: 3,
          last_comment: 'Cabeamento concluído, falta teste',
          last_advance: {
            comment: 'Cabeamento concluído, falta teste',
            recorded_at: '2026-02-01T09:00:00Z',
            author_name_snapshot: 'Ana',
            legacy: false,
          },
        })}
      />,
    )
    expect(screen.getByText('Cabeamento concluído, falta teste')).toBeInTheDocument()
    const btn = screen.getByRole('button', { name: /3 entradas/ })
    expect(within(btn).getByText('3')).toBeInTheDocument()
  })
})
