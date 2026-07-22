import { describe, expect, it } from 'vitest'
import { render, screen } from '@testing-library/react'
import { ReportHeader } from '@/features/report/ReportHeader'
import type { CommissioningReportDTO } from '@/features/report/types'

// commissioning-report 2.3 (§3.8, D-R1) — o cabeçalho renderiza SÓ campos já
// derivados do payload (título/workspace/carimbo). Espelha a fixture congelada do
// backend (spec/fixtures/reports/commissioning_report.json).
export const reportFixture: CommissioningReportDTO = {
  scope: 'all',
  header: { title: 'PROTOCOLO DE COMISSIONAMENTO', workspace_name: 'Comissionamento Pintura 3' },
  stamp: { percent: 62, label: 'EM ANDAMENTO' },
  document_id: 'RT-20260720-1432',
  metadata: {
    scope_label: 'Workspace inteiro',
    document_id: 'RT-20260720-1432',
    issued_at: '2026-07-20T14:32:00-03:00',
    generated_by: 'Marina Alves',
    structure: '1 projeto(s) · 1 célula(s) · 1 robô(s) · 2 tarefa(s)',
    counts: { projects: 1, cells: 1, robots: 1, tasks: 2 },
  },
  status_distribution: [
    { status: 'Concluído', glyph: '✓', label: 'Concluído', count: 1 },
    { status: 'Em Andamento', glyph: '◐', label: 'Em andamento', count: 1 },
    { status: 'Pendente', glyph: '○', label: 'Pendente', count: 0 },
    { status: 'N/A', glyph: '—', label: 'N/A', count: 0 },
  ],
  tree: [
    {
      id: 'p1', name: 'Linha A — Carroceria', weighted_progress: 62,
      cells: [
        {
          id: 'c1', name: 'Célula 01 — Solda', weighted_progress: 62,
          robots: [
            {
              id: 'r1', name: 'R03 - Sealing', application: 'Sealing', weighted_progress: 62,
              tasks: [
                { id: 't1', description: 'Fixação da base', status: 'Concluído', symbol: '✓', percent: 100, assignees: ['Ana Lima'], advances: [{ recorded_at: '2026-07-18T14:02:00-03:00', author: 'Ana Lima', from: 40, to: 100, comment: 'Torqueado 40Nm' }] },
                { id: 't2', description: 'Alinhamento do 6º eixo', status: 'Em Andamento', symbol: '◐', percent: 45, assignees: [], advances: [] },
              ],
            },
          ],
        },
      ],
    },
  ],
  conclusions: [{ task_id: 't1', description: 'Fixação da base', concluded_by: 'Ana Lima', concluded_at: '2026-07-18T14:02:00-03:00' }],
  warnings: [],
}

describe('ReportHeader (2.3)', () => {
  it('renderiza título, workspace e carimbo (percent · label) do payload', () => {
    render(<ReportHeader report={reportFixture} />)
    expect(screen.getByRole('heading', { name: 'PROTOCOLO DE COMISSIONAMENTO' })).toBeInTheDocument()
    expect(screen.getByText('Comissionamento Pintura 3')).toBeInTheDocument()
    expect(screen.getByText('62%')).toBeInTheDocument()
    expect(screen.getByText('EM ANDAMENTO')).toBeInTheDocument()
  })
})
