import { afterEach, describe, expect, it } from 'vitest'
import { setLang } from '../lang'
import { statusLabel, applicationLabel, categoryLabel, baseTaskLabel } from '../dataLabels'

// internationalization G4 / D-I4 — prova do MAPA DE EXIBIÇÃO. O valor gravado (pt-BR)
// nunca muda; a função só troca o RÓTULO quando en. Em pt-BR devolve o valor; um valor
// desconhecido cai no fallback (texto custom do usuário não é "traduzido").
afterEach(() => setLang('pt-BR'))

describe('dataLabels — exibição de valores gravados em pt-BR', () => {
  it('em pt-BR devolve o valor inalterado (o dado)', () => {
    setLang('pt-BR')
    expect(statusLabel('Concluído')).toBe('Concluído')
    expect(applicationLabel('Solda Ponto')).toBe('Solda Ponto')
    expect(categoryLabel('E. Trajetórias')).toBe('E. Trajetórias')
    expect(baseTaskLabel('Otimização de Trajetoria')).toBe('Otimização de Trajetoria')
  })

  it('em en traduz o RÓTULO (glossário confirmado)', () => {
    setLang('en')
    expect(statusLabel('Concluído')).toBe('Done') // decisão nº 3 (tela)
    expect(statusLabel('Em Andamento')).toBe('In Progress')
    expect(applicationLabel('Solda Ponto')).toBe('Spot Welding') // decisão nº 6
    expect(applicationLabel('Solda MIG')).toBe('MIG Welding')
    expect(categoryLabel('E. Trajetórias')).toBe('E. Trajectories') // decisão nº 5
    expect(baseTaskLabel('Teach Traj. Com Peça')).toBe('Teach Trajectory — With Part')
    expect(baseTaskLabel('Otimização de Trajetoria')).toBe('Trajectory Optimization')
  })

  it('valor desconhecido (tarefa-base custom) cai no fallback, mesmo em en', () => {
    setLang('en')
    expect(baseTaskLabel('Minha tarefa personalizada')).toBe('Minha tarefa personalizada')
    expect(statusLabel(null)).toBe('')
  })

  it('cobre as 4 status, 6 aplicações e 9 categorias em en', () => {
    setLang('en')
    expect(['Pendente', 'Em Andamento', 'Concluído', 'N/A'].map(statusLabel)).toEqual([
      'Pending', 'In Progress', 'Done', 'N/A',
    ])
    expect(['Misto / Geral', 'Solda Ponto', 'Solda MIG', 'Handling', 'Sealing', 'Outros'].map(applicationLabel)).toEqual([
      'Mixed / General', 'Spot Welding', 'MIG Welding', 'Handling', 'Sealing', 'Others',
    ])
    expect(categoryLabel('B. Rede')).toBe('B. Network')
    expect(categoryLabel('H. Otimização')).toBe('H. Optimization')
  })
})
