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
  it('digitar 99 no passo 1 limita a 50 e o passo 2 mostra exatamente 50 campos', () => {
    render(<BatchRobotWizard cellId="c1" />)
    const qty = goToStep2WithQuantity('99')
    expect(qty.value).toBe('50') // clamp visual

    fireEvent.click(screen.getByText('Avançar'))
    expect(screen.getAllByLabelText(/Nome do robô/)).toHaveLength(50)
  })

  it('0 vira 1 campo', () => {
    render(<BatchRobotWizard cellId="c1" />)
    goToStep2WithQuantity('0')
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
