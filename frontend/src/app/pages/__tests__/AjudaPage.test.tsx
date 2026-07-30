import { describe, expect, it } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import { AjudaPage } from '../AjudaPage'

// ajuda-screen — a tela de Ajuda: um índice navegável + as seções que ele aponta,
// vindos da MESMA lista (não podem divergir). O teste trava a descoberta (índice)
// e a precisão (as seções que o dono pediu que a Ajuda cubra).

describe('AjudaPage', () => {
  it('tem título e um índice navegável com âncoras internas', () => {
    render(<AjudaPage />)
    expect(screen.getByRole('heading', { level: 1, name: 'Ajuda' })).toBeInTheDocument()

    const toc = screen.getByRole('navigation', { name: 'Seções da ajuda' })
    const links = within(toc).getAllByRole('link')
    expect(links.length).toBeGreaterThanOrEqual(10)
    // cada link do índice aponta para uma âncora (#id) da própria página
    for (const a of links) {
      expect(a.getAttribute('href')).toMatch(/^#[a-z-]+$/)
    }
  })

  it('cada seção do índice tem um destino real na página (âncora existe)', () => {
    const { container } = render(<AjudaPage />)
    const toc = screen.getByRole('navigation', { name: 'Seções da ajuda' })
    for (const a of within(toc).getAllByRole('link')) {
      const id = a.getAttribute('href')!.slice(1)
      expect(container.querySelector(`section#${id}`), `seção #${id} ausente`).toBeTruthy()
    }
  })

  it('cobre os assuntos que o dono pediu, com os fatos reais do app', () => {
    render(<AjudaPage />)
    const headings = screen
      .getAllByRole('heading', { level: 2 })
      .map((h) => h.textContent)
      .join(' | ')

    for (const assunto of [
      'O que é o RoboTrack',
      'Como o trabalho se organiza',
      'Papéis e permissões',
      'Navegando pelo app',
      'Montando a estrutura',
      'Registrando o avanço',
      'Atribuindo responsáveis',
      'Convidando pessoas',
      'Notificações',
      'Usando sem internet',
      'Excluindo itens',
      'Relatório de comissionamento',
    ]) {
      expect(headings).toContain(assunto)
    }

    // fatos precisos (não inventar funcionalidade)
    expect(screen.getByText(/Workspace/)).toBeInTheDocument()
    expect(screen.getByText(/comentário é obrigatório/i)).toBeInTheDocument()
    expect(screen.getByText(/XXXX-XXXX/)).toBeInTheDocument()
    expect(screen.getByText(/mais específico vence/i)).toBeInTheDocument()
    // convite é por CÓDIGO — a Ajuda NÃO menciona convite por link
    expect(screen.queryByText(/convite por link|link de convite/i)).toBeNull()
  })

  it('a matriz de papéis marca excluir/resetar como exclusivo do dono', () => {
    render(<AjudaPage />)
    const linha = screen.getByRole('rowheader', { name: /Excluir cards e resetar/i }).closest('tr')!
    const celulas = within(linha).getAllByRole('cell')
    // Dono = Sim, Editor e Visualizador = não
    expect(celulas[0]).toHaveTextContent('Sim')
    expect(celulas[1]).not.toHaveTextContent('Sim')
    expect(celulas[2]).not.toHaveTextContent('Sim')
  })
})
