import { describe, expect, it, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { BatchRobotWizard } from '../BatchRobotWizard'

// robot-tasks 5.6 (§2.5) — o assistente: digitar 99 no passo 1 mostra 50 campos
// (clamp), e o placeholder NUNCA vira o nome de um robô (campos vazios não são
// enviados). Uma única requisição com uuids do cliente.

vi.mock('../../catalog/useTaskTemplates', () => ({
  useRobotApplications: () => ({ data: ['Misto / Geral', 'Solda MIG', 'Sealing'] }),
}))

const mutate = vi.fn()
vi.mock('../useBatchRobots', async (original) => {
  const real = await original<typeof import('../useBatchRobots')>()
  return { ...real, useBatchCreateRobots: () => ({ mutate, isPending: false }) }
})

beforeEach(() => mutate.mockReset())

function goToStep2WithQuantity(value: string) {
  const qty = screen.getByLabelText('Quantidade') as HTMLInputElement
  fireEvent.change(qty, { target: { value } })
  return qty
}

describe('BatchRobotWizard', () => {
  // Bug de UX de primeiro uso (demo real): o clamp rodava a cada tecla, então
  // apagar o campo devolvia 1 na hora e só dava para chegar a 10+ acrescentando
  // dígitos depois do 1. O clamp 1..50 tem de acontecer no BLUR / no avanço.
  it('deixa apagar o campo enquanto digita (estado vazio permitido)', () => {
    render(<BatchRobotWizard cellId="c1" />)
    const qty = goToStep2WithQuantity('')
    expect(qty.value).toBe('') // NÃO volta a 1 por tecla
  })

  it('deixa digitar valores intermediários sem pular para 10+', () => {
    render(<BatchRobotWizard cellId="c1" />)
    const qty = screen.getByLabelText('Quantidade') as HTMLInputElement
    fireEvent.change(qty, { target: { value: '' } })
    fireEvent.change(qty, { target: { value: '7' } })
    expect(qty.value).toBe('7') // digitar 7 dá 7, não 17

    fireEvent.click(screen.getByText('Avançar'))
    expect(screen.getAllByLabelText(/Nome do robô/)).toHaveLength(7)
  })

  it('blur com o campo vazio volta ao mínimo válido (1)', () => {
    render(<BatchRobotWizard cellId="c1" />)
    const qty = goToStep2WithQuantity('')
    fireEvent.blur(qty)
    expect(qty.value).toBe('1')
  })

  it('digitar 99 limita a 50 no blur e o passo 2 mostra exatamente 50 campos', () => {
    render(<BatchRobotWizard cellId="c1" />)
    const qty = goToStep2WithQuantity('99')
    expect(qty.value).toBe('99') // sem clamp por tecla
    fireEvent.blur(qty)
    expect(qty.value).toBe('50') // clamp visual no blur

    fireEvent.click(screen.getByText('Avançar'))
    expect(screen.getAllByLabelText(/Nome do robô/)).toHaveLength(50)
  })

  it('51 vira 50 ao avançar mesmo sem blur', () => {
    render(<BatchRobotWizard cellId="c1" />)
    goToStep2WithQuantity('51')
    fireEvent.click(screen.getByText('Avançar'))
    expect(screen.getAllByLabelText(/Nome do robô/)).toHaveLength(50)
  })

  it('0 vira 1 campo', () => {
    render(<BatchRobotWizard cellId="c1" />)
    goToStep2WithQuantity('0')
    fireEvent.click(screen.getByText('Avançar'))
    expect(screen.getAllByLabelText(/Nome do robô/)).toHaveLength(1)
  })

  it('valor negativo é tratado como o mínimo (1)', () => {
    render(<BatchRobotWizard cellId="c1" />)
    goToStep2WithQuantity('-5')
    fireEvent.click(screen.getByText('Avançar'))
    expect(screen.getAllByLabelText(/Nome do robô/)).toHaveLength(1)
  })

  it('só os campos preenchidos viram robôs; o placeholder nunca é enviado', () => {
    render(<BatchRobotWizard cellId="c1" />)
    goToStep2WithQuantity('3')
    fireEvent.click(screen.getByText('Avançar'))

    const inputs = screen.getAllByLabelText(/Nome do robô/) as HTMLInputElement[]
    fireEvent.change(inputs[0], { target: { value: 'R-A' } })
    fireEvent.change(inputs[2], { target: { value: '  R-B  ' } }) // trim no cliente também
    // inputs[1] fica vazio — o placeholder "R01 - Solda" não deve ser enviado.

    fireEvent.click(screen.getByText(/Criar/))
    expect(mutate).toHaveBeenCalledTimes(1)

    const arg = mutate.mock.calls[0][0] as {
      application: string
      robots: { id: string; name: string }[]
    }
    expect(arg.application).toBe('Misto / Geral') // primeira Aplicação por padrão
    expect(arg.robots.map((r) => r.name)).toEqual(['R-A', 'R-B'])
    expect(arg.robots.every((r) => r.id.length > 0)).toBe(true)
  })

  it('a Aplicação escolhida no passo 1 vai na requisição', () => {
    render(<BatchRobotWizard cellId="c1" />)
    fireEvent.change(screen.getByLabelText('Aplicação'), { target: { value: 'Sealing' } })
    goToStep2WithQuantity('1')
    fireEvent.click(screen.getByText('Avançar'))

    const input = screen.getByLabelText('Nome do robô 1')
    fireEvent.change(input, { target: { value: 'R-Sealing' } })
    fireEvent.click(screen.getByText(/Criar/))

    expect(mutate.mock.calls[0][0].application).toBe('Sealing')
  })
})
