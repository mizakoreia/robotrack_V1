import { describe, expect, it } from 'vitest'
import { moveItem, submitReorder } from '../reorder'

// commissioning-hierarchy 6.6 (§2.9) — depois do 409 a lista volta ao estado do
// SERVIDOR; ficar presa na ordem otimista que o servidor rejeitou seria o pior
// dos mundos (a tela mostraria uma ordem que não existe).
describe('moveItem', () => {
  const itens = [{ id: 'a' }, { id: 'b' }, { id: 'c' }]

  it('move do índice de origem para o de destino', () => {
    expect(moveItem(itens, 2, 0).map((i) => i.id)).toEqual(['c', 'a', 'b'])
    expect(moveItem(itens, 0, 2).map((i) => i.id)).toEqual(['b', 'c', 'a'])
  })

  it('devolve a MESMA referência quando não há movimento (evita render à toa)', () => {
    expect(moveItem(itens, 1, 1)).toBe(itens)
    expect(moveItem(itens, -1, 0)).toBe(itens)
    expect(moveItem(itens, 0, 9)).toBe(itens)
  })
})

describe('submitReorder', () => {
  it('sucesso devolve a lista final do servidor', async () => {
    const resultado = await submitReorder(async () => [{ id: 'c' }, { id: 'a' }])
    expect(resultado).toEqual({ status: 'ok', items: [{ id: 'c' }, { id: 'a' }] })
  })

  it('409 reorder_conflict devolve o conjunto ATUAL para o chamador recarregar', async () => {
    const erro = {
      response: {
        status: 409,
        data: { error: 'reorder_conflict', details: { current_ids: ['a', 'b', 'novo'] } },
      },
    }

    const resultado = await submitReorder(async () => {
      throw erro
    })

    expect(resultado).toEqual({ status: 'conflict', currentIds: ['a', 'b', 'novo'] })
  })

  it('outros erros não viram conflito silencioso', async () => {
    const erro = { response: { status: 500, data: {} } }
    const resultado = await submitReorder(async () => {
      throw erro
    })
    expect(resultado.status).toBe('error')
  })
})
