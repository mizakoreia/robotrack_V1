import type { TransportState } from '../../store/realtimeStore'

// realtime-collaboration 7.3 — a métrica de "sessões em degraded" é de
// `delivery-and-observability` (não construída). HANDOFF: ponto único e
// injetável; o default é no-op. Sem isso, 100% das sessões degradadas por um
// `/cable` mal roteado passaria como normal e ninguém descobriria por meses.
type Sink = (state: TransportState, at: number) => void

let sink: Sink = () => {}

export function setTransportMetricSink(fn: Sink): void {
  sink = fn
}

export function reportTransportMetric(state: TransportState, at: number = Date.now()): void {
  try {
    sink(state, at)
  } catch {
    /* uma métrica nunca derruba o cliente */
  }
}
