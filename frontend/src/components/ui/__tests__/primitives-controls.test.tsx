import { describe, expect, it } from 'vitest'
import { useState } from 'react'
import { render, screen, fireEvent, act } from '@testing-library/react'
import { Badge } from '../Badge'
import { StatusSelect } from '../StatusSelect'
import { Chip } from '../Chip'
import { SaveIndicator } from '../SaveIndicator'
import { FilterBar } from '../FilterBar'
import { Modal } from '../Modal'
import { IconButton } from '../IconButton'

// design-system 6.7 (§5.2, D-DS-9) — a11y e comportamento dos primitivos. Sem axe
// instalado (e o G8 proíbe novas deps), a verificação é ESTRUTURAL — roles, aria e
// nomes acessíveis; a auditoria axe de TELA montada é de quality-and-accessibility
// (não-objetivo desta change). As restrições de a11y que SÃO de tipo (label
// obrigatório, badge não-clicável) são provadas por `@ts-expect-error`.

describe('Badge — rótulo estático (6.1)', () => {
  it('é um <span> não focável, com tinta do status', () => {
    const { container } = render(<Badge status="success">Concluído</Badge>)
    const el = screen.getByText('Concluído')
    expect(el.tagName).toBe('SPAN')
    expect(el).not.toHaveAttribute('tabindex')
    expect(el.className).toContain('text-success-ink')
  })

  it('passar onClick num Badge é erro de tipo (badge não é controle)', () => {
    // @ts-expect-error — BadgeProps não tem onClick de propósito (D-DS-2 §5.2)
    const el = <Badge status="na" onClick={() => {}}>x</Badge>
    expect(el).toBeTruthy()
  })
})

describe('StatusSelect — controle, árvore ≠ Badge (6.2)', () => {
  it('renderiza <select> + chevron do sprite (não suprimível)', () => {
    const { container } = render(
      <StatusSelect value="a" onChange={() => {}} options={[{ value: 'a', label: 'A' }]} aria-label="status" />,
    )
    expect(container.querySelector('select')).toBeTruthy()
    expect(container.querySelector('use')?.getAttribute('href')).toBe('#i-chevron-down')
  })

  it('a árvore do StatusSelect difere da do Badge do mesmo status', () => {
    const badge = render(<Badge status="success">Feito</Badge>).container.innerHTML
    const select = render(
      <StatusSelect status="success" value="s" onChange={() => {}} options={[{ value: 's', label: 'Feito' }]} />,
    ).container.innerHTML
    expect(select).not.toEqual(badge)
    expect(select).toContain('<select')
  })
})

describe('Chip — estático vs removível (6.3)', () => {
  it('estático é um <span> sem botão focável', () => {
    const { container } = render(<Chip label="Ana" />)
    expect(container.querySelector('button')).toBeNull()
  })

  it('removível tem botão com aria-label do nome e alvo ≥ 32×32', () => {
    render(<Chip label="Bruno" onRemove={() => {}} />)
    const btn = screen.getByRole('button', { name: 'Remover Bruno' })
    expect(btn.className).toContain('h-8')
    expect(btn.className).toContain('w-8')
  })
})

describe('SaveIndicator — não mente estado (6.5)', () => {
  it('erro NÃO afirma "Salvo" e é aria-live polite', () => {
    const { container } = render(<SaveIndicator state="error" />)
    const el = container.firstElementChild as HTMLElement
    expect(el).toHaveAttribute('aria-live', 'polite')
    expect(el.textContent).not.toBe('Salvo')
    expect(el.textContent?.toLowerCase()).toContain('erro')
  })

  it('saved diz "Salvo" com tinta de sucesso', () => {
    render(<SaveIndicator state="saved" />)
    expect(screen.getByText('Salvo').closest('span')?.className).toContain('text-success-ink')
  })
})

describe('FilterBar — ativo é sólido, não cheio (6.6)', () => {
  it('o segmento ativo usa bg-accent-solid (não bg-accent) e role=tab', () => {
    render(
      <FilterBar
        value="todos"
        onChange={() => {}}
        options={[
          { value: 'todos', label: 'Todos' },
          { value: 'meus', label: 'Meus' },
        ]}
      />,
    )
    const ativo = screen.getByRole('tab', { name: 'Todos' })
    expect(ativo).toHaveAttribute('aria-selected', 'true')
    expect(ativo.className).toContain('bg-accent-solid')
    expect(ativo.className).not.toMatch(/bg-accent\b(?!-solid)/)
    expect(ativo.className).toContain('h-8')
  })
})

describe('Modal — Esc devolve o foco ao gatilho (6.4)', () => {
  function Harness() {
    const [open, setOpen] = useState(false)
    return (
      <>
        <button onClick={() => setOpen(true)}>abrir</button>
        <Modal open={open} onClose={() => setOpen(false)} title="Registrar avanço">
          <input aria-label="campo" />
        </Modal>
      </>
    )
  }

  it('abre com role=dialog aria-modal; Esc fecha e devolve o foco ao gatilho', () => {
    render(<Harness />)
    const trigger = screen.getByRole('button', { name: 'abrir' })
    act(() => trigger.focus())
    fireEvent.click(trigger)

    const dialog = screen.getByRole('dialog')
    expect(dialog).toHaveAttribute('aria-modal', 'true')

    fireEvent.keyDown(document, { key: 'Escape' })
    expect(screen.queryByRole('dialog')).toBeNull()
    expect(document.activeElement).toBe(trigger)
  })
})

describe('IconButton — label obrigatório é de tipo (6.7 / D-DS-9)', () => {
  it('sem label é erro de tsc; com label expõe o nome acessível', () => {
    // @ts-expect-error — `label` é obrigatório: botão só-ícone sem nome não compila
    const semNome = <IconButton icon="trash" />
    expect(semNome).toBeTruthy()

    render(<IconButton icon="trash" label="Excluir tarefa" />)
    expect(screen.getByRole('button', { name: 'Excluir tarefa' })).toBeTruthy()
  })
})
