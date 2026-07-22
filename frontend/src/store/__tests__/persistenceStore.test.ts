import { describe, expect, it, beforeEach } from 'vitest'
import { usePersistenceStore, selectSaveState } from '../persistenceStore'

// app-shell-navigation 6.1/6.2 (D-D) — o store de persistência e o indicador como
// projeção pura. O contrato contra o qual `offline-pwa` vai programar: `inFlight`
// nunca negativo (dedup por id), e a precedência `erro > salvando > salvo` sem
// expiração por tempo.

function reset() {
  usePersistenceStore.setState({
    inFlightIds: new Set(),
    inFlight: 0,
    queued: 0,
    failed: 0,
    lastSavedAt: null,
  })
}

beforeEach(reset)

describe('persistenceStore (D-D)', () => {
  it('beginMutation soma; settleMutation subtrai', () => {
    const s = usePersistenceStore.getState()
    s.beginMutation('a')
    s.beginMutation('b')
    expect(usePersistenceStore.getState().inFlight).toBe(2)
    s.settleMutation('a')
    expect(usePersistenceStore.getState().inFlight).toBe(1)
  })

  it('settleMutation do MESMO id duas vezes NÃO leva inFlight a negativo', () => {
    const s = usePersistenceStore.getState()
    s.beginMutation('a')
    s.settleMutation('a')
    s.settleMutation('a') // segundo settle do mesmo id: nada muda
    expect(usePersistenceStore.getState().inFlight).toBe(0)
  })

  it('beginMutation do mesmo id duas vezes conta UMA vez (Set)', () => {
    const s = usePersistenceStore.getState()
    s.beginMutation('a')
    s.beginMutation('a')
    expect(usePersistenceStore.getState().inFlight).toBe(1)
  })

  it('settle com ok=false incrementa failed; ok=true grava lastSavedAt', () => {
    const s = usePersistenceStore.getState()
    s.beginMutation('a')
    s.settleMutation('a', false)
    expect(usePersistenceStore.getState().failed).toBe(1)
    expect(usePersistenceStore.getState().lastSavedAt).toBeNull()

    s.beginMutation('b')
    s.settleMutation('b', true)
    expect(usePersistenceStore.getState().lastSavedAt).not.toBeNull()
  })

  it('settle de um id NUNCA visto não incrementa failed nem grava lastSavedAt', () => {
    const s = usePersistenceStore.getState()
    s.settleMutation('fantasma', false)
    expect(usePersistenceStore.getState().failed).toBe(0)
    s.settleMutation('fantasma', true)
    expect(usePersistenceStore.getState().lastSavedAt).toBeNull()
  })

  it('setQueueDepth nunca fica negativo', () => {
    usePersistenceStore.getState().setQueueDepth(-5)
    expect(usePersistenceStore.getState().queued).toBe(0)
  })
})

describe('selectSaveState (D-D) — projeção pura, precedência erro > salvando > salvo', () => {
  it('sem nada em voo: salvo', () => {
    expect(selectSaveState({ inFlight: 0, queued: 0, failed: 0 })).toBe('saved')
  })

  it('inFlight > 0: salvando', () => {
    expect(selectSaveState({ inFlight: 1, queued: 0, failed: 0 })).toBe('saving')
  })

  it('queued = 3 com inFlight = 0: salvando (nunca salvo)', () => {
    expect(selectSaveState({ inFlight: 0, queued: 3, failed: 0 })).toBe('saving')
  })

  it('failed > 0 vence salvando e salvo: erro', () => {
    expect(selectSaveState({ inFlight: 5, queued: 2, failed: 1 })).toBe('error')
  })

  it('erro continua até uma escrita nova ter sucesso (resetErrors zera)', () => {
    const s = usePersistenceStore.getState()
    s.beginMutation('a')
    s.settleMutation('a', false)
    expect(selectSaveState(usePersistenceStore.getState())).toBe('error')
    s.resetErrors()
    expect(selectSaveState(usePersistenceStore.getState())).toBe('saved')
  })
})
