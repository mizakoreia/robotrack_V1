import { describe, expect, it } from 'vitest'
import { render, screen } from '@testing-library/react'
import { ReportHeader } from '@/features/report/ReportHeader'
import { ReportMetadata } from '@/features/report/ReportMetadata'
import { ReportDistribution } from '@/features/report/ReportDistribution'
import { ReportBody } from '@/features/report/ReportBody'
import { ReportConclusions } from '@/features/report/ReportConclusions'
import { ReportSignatures } from '@/features/report/ReportSignatures'
import { ReportDocument } from '@/features/report/ReportDocument'
import { HISTORY_PAGE_CHUNK } from '@/features/report/ReportBody'
import type { ReportAdvanceDTO } from '@/features/report/types'
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
                { id: 't1', description: 'Fixação da base', status: 'Concluído', symbol: '✓', percent: 100, assignees: ['Ana Lima'], advances: [{ recorded_at: '2026-07-18T14:02:00-03:00', author: 'Ana Lima', from: 40, to: 100, comment: 'Torqueado 40Nm', transition: 'de 40% para 100%' }], truncated_notice: null },
                { id: 't2', description: 'Alinhamento do 6º eixo', status: 'Em Andamento', symbol: '◐', percent: 45, assignees: [], advances: [], truncated_notice: null },
              ],
            },
          ],
        },
      ],
    },
  ],
  conclusions: [{ task_id: 't1', description: 'Fixação da base', concluded_by: 'Ana Lima', concluded_at: '2026-07-18T14:02:00-03:00' }],
  signatures: [
    { key: 'commissioner', label: 'Comissionador' },
    { key: 'client', label: 'Cliente / Aceite' },
  ],
  footer: {
    document_id: 'RT-20260720-1432',
    generated_at: '2026-07-20T14:32:00-03:00',
    generated_at_label: 'Documento gerado em',
    traceability: 'Documento de rastreabilidade — os horários refletem o momento do registro de cada avanço (recorded_at), não o de sincronização.',
  },
  labels: {
    section_distribution: 'Distribuição de status',
    section_body: 'Comissionamento por projeto',
    section_conclusions: 'Conclusões',
    weighted_progress: 'progresso ponderado',
    col_symbol: 'Símbolo', col_description: 'Tarefa', col_status: 'Status',
    col_percent: '%', col_assignees: 'Responsáveis', no_assignees: '—',
    concluded_by: 'Concluído por', concluded_at: 'Em',
    signature_name: 'Nome', signature_field: 'Assinatura', signature_date: 'Data',
    history_continues: '— histórico continua na próxima página —',
    meta_scope: 'Escopo', meta_document_id: 'Id do documento', meta_issued_at: 'Emitido em',
    meta_generated_by: 'Gerado por', meta_structure: 'Estrutura',
  },
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

describe('ReportMetadata (3.2)', () => {
  it('renderiza id, escopo, gerado por e estrutura do payload (sem reformatar o id)', () => {
    render(<ReportMetadata report={reportFixture} />)
    expect(screen.getByText('RT-20260720-1432')).toBeInTheDocument() // id byte a byte
    expect(screen.getByText('Workspace inteiro')).toBeInTheDocument()
    expect(screen.getByText('Marina Alves')).toBeInTheDocument()
    expect(screen.getByText('1 projeto(s) · 1 célula(s) · 1 robô(s) · 2 tarefa(s)')).toBeInTheDocument()
  })
})

describe('ReportDistribution (4.2)', () => {
  it('mostra as 4 linhas com glifo do payload e contagem (inclusive zeradas)', () => {
    render(<ReportDistribution report={reportFixture} />)
    for (const glyph of ['✓', '◐', '○', '—']) {
      expect(screen.getByText(glyph)).toBeInTheDocument()
    }
    expect(screen.getByText('Concluído')).toBeInTheDocument()
    expect(screen.getByText('Pendente')).toBeInTheDocument()
    // zeradas presentes
    const pendente = screen.getByText('Pendente').closest('li')!
    expect(pendente.textContent).toContain('0')
  })
})

describe('ReportBody (5.4)', () => {
  it('renderiza robô com Aplicação, tarefa e histórico; tarefa sem avanço não tem bloco de histórico', () => {
    render(<ReportBody report={reportFixture} />)
    expect(screen.getByText('R03 - Sealing')).toBeInTheDocument()
    expect(screen.getByText('Sealing')).toBeInTheDocument()
    expect(screen.getByText('Fixação da base')).toBeInTheDocument()
    // histórico da tarefa concluída (transição pronta do servidor)
    expect(screen.getByText('de 40% para 100%')).toBeInTheDocument()
    // a tarefa "Alinhamento" (sem avanços) → sem transição
    expect(screen.queryByText('de 0% para')).toBeNull()
    // sem responsável mostra o traço do payload, nunca "Não Atribuído"
    expect(screen.queryByText('Não Atribuído')).toBeNull()
  })

  it('nível vazio não estoura (projeto sem células renderiza traço)', () => {
    const empty: CommissioningReportDTO = {
      ...reportFixture,
      tree: [{ id: 'p9', name: 'Projeto Vazio', weighted_progress: 0, cells: [] }],
    }
    render(<ReportBody report={empty} />)
    expect(screen.getByText('Projeto Vazio')).toBeInTheDocument()
  })
})

describe('ReportSignatures (7.1)', () => {
  it('exatamente um bloco Comissionador e um Cliente / Aceite, ambos em branco (sem o usuário logado)', () => {
    const { container } = render(<ReportSignatures report={reportFixture} />)
    expect(screen.getByText('Comissionador')).toBeInTheDocument()
    expect(screen.getByText('Cliente / Aceite')).toBeInTheDocument()
    // 3 linhas (Nome/Assinatura/Data) × 2 blocos, todas vazias
    expect(container.querySelectorAll('.rpt-sign-line')).toHaveLength(6)
    expect(screen.getAllByText('Nome')).toHaveLength(2)
    // nada pré-preenchido: nenhum nome de pessoa dentro da seção
    expect(container.textContent).not.toContain('Marina Alves')
    expect(container.textContent).not.toContain('Ana Lima')
  })
})

describe('ReportDocument (7.1/7.3, D-R3)', () => {
  it('tabela raiz com thead corrido (título + id) e tfoot com rodapé (id byte a byte, rastreabilidade)', () => {
    const { container } = render(<ReportDocument report={reportFixture} />)
    const running = container.querySelector('thead.rpt-running')!
    expect(running.textContent).toContain('RT-20260720-1432')
    expect(running.textContent).toContain('PROTOCOLO DE COMISSIONAMENTO')
    const tfoot = container.querySelector('tfoot')!
    expect(tfoot.textContent).toContain('RT-20260720-1432') // o id CARIMBADO, não outro
    expect(tfoot.textContent).toContain('Documento gerado em')
    expect(tfoot.textContent).toContain('Documento de rastreabilidade')
    // e o documento completo dentro do tbody
    expect(screen.getByRole('heading', { name: 'PROTOCOLO DE COMISSIONAMENTO' })).toBeInTheDocument()
    expect(screen.getByText('Distribuição de status')).toBeInTheDocument()
  })
})

describe('quebra de página (7.4, D-R4)', () => {
  const adv = (n: number): ReportAdvanceDTO => ({
    recorded_at: '2026-07-18T14:02:00-03:00', author: 'Ana Lima',
    from: n, to: n + 1, comment: null, transition: `de ${n}% para ${n + 1}%`,
  })
  const withAdvances = (count: number) => ({
    ...reportFixture,
    tree: [{
      ...reportFixture.tree[0],
      cells: [{
        ...reportFixture.tree[0].cells[0],
        robots: [{
          ...reportFixture.tree[0].cells[0].robots[0],
          tasks: [{ ...reportFixture.tree[0].cells[0].robots[0].tasks[0], advances: Array.from({ length: count }, (_, i) => adv(i)) }],
        }],
      }],
    }],
  })

  it('tarefa+histórico é um tbody.rpt-task; até o limiar não há faixa nem fatia', () => {
    const { container } = render(<ReportBody report={withAdvances(HISTORY_PAGE_CHUNK)} />)
    expect(container.querySelectorAll('tbody.rpt-task')).toHaveLength(1)
    expect(container.querySelector('.rpt-task--long')).toBeNull()
    expect(container.querySelector('.rpt-continuation')).toBeNull()
  })

  it('acima do limiar (24 entradas) o bloco vira longo e a fatia de continuação traz a faixa do payload', () => {
    const { container } = render(<ReportBody report={withAdvances(24)} />)
    expect(container.querySelector('tbody.rpt-task--long')).not.toBeNull()
    const conts = container.querySelectorAll('tbody.rpt-task-cont')
    expect(conts).toHaveLength(1) // 24 = 18 + 6 → uma fatia de continuação
    expect(conts[0].querySelector('.rpt-continuation')!.textContent).toContain(
      '— histórico continua na próxima página —',
    )
    // nenhuma entrada se perde na fatiagem: 24 <li> no total
    expect(container.querySelectorAll('.rpt-history li')).toHaveLength(24)
  })
})

describe('ReportConclusions (6.3)', () => {
  it('lista as conclusões com quem concluiu; some quando não há conclusões', () => {
    const { unmount } = render(<ReportConclusions report={reportFixture} />)
    expect(screen.getByText('Concluído por: Ana Lima')).toBeInTheDocument()
    unmount()
    const { container } = render(<ReportConclusions report={{ ...reportFixture, conclusions: [] }} />)
    expect(container).toBeEmptyDOMElement()
  })
})
