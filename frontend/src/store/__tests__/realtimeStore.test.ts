import { describe, it, expect, beforeEach } from 'vitest'
import { useRealtimeStore } from '../realtimeStore'

describe('realtimeStore (5.2)', () => {
  beforeEach(() => useRealtimeStore.getState().reset())

  it('noteSeq só AVANÇA (envelope fora de ordem não retrocede o since)', () => {
    const { noteSeq } = useRealtimeStore.getState()
    noteSeq('w1', 10)
    noteSeq('w1', 7) // fora de ordem
    noteSeq('w1', 12)
    expect(useRealtimeStore.getState().lastSeq['w1']).toBe(12)
  })

  it('seqs de workspaces distintos são independentes', () => {
    const { noteSeq } = useRealtimeStore.getState()
    noteSeq('w1', 5)
    noteSeq('w2', 99)
    expect(useRealtimeStore.getState().lastSeq).toEqual({ w1: 5, w2: 99 })
  })

  it('transport transita e reset zera transporte+seqs mas mantém o originId da aba', () => {
    const origin = useRealtimeStore.getState().originId
    expect(origin).toBeTruthy()
    useRealtimeStore.getState().setTransport('live')
    useRealtimeStore.getState().noteSeq('w1', 3)
    useRealtimeStore.getState().reset()
    expect(useRealtimeStore.getState().transport).toBe('connecting')
    expect(useRealtimeStore.getState().lastSeq).toEqual({})
    expect(useRealtimeStore.getState().originId).toBe(origin)
  })
})
