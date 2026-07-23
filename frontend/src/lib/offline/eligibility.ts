import type { QueuedMutation } from './types'

// Grafo de dependência da fila (offline-pwa 4.1 / D7-4). Um item é ELEGÍVEL
// quando todos os uuids em `depends_on` estão em `resolved_uuids` — o conjunto do
// que o servidor já confirmou. Itens não elegíveis são PULADOS, não bloqueiam o
// `seq` seguinte: um `project.rename` independente (seq 4) sobe enquanto um
// `task.create` (seq 2) espera pelo robô.

export function isEligible(m: QueuedMutation, resolved: ReadonlySet<string>): boolean {
  return m.depends_on.every((uuid) => resolved.has(uuid))
}

// Itens enfileirados elegíveis, em ordem de `seq` crescente.
export function eligibleMutations(mutations: QueuedMutation[], resolved: ReadonlySet<string>): QueuedMutation[] {
  return mutations
    .filter((m) => m.state === 'enqueued')
    .filter((m) => isEligible(m, resolved))
    .sort((a, b) => a.seq - b.seq)
}

// O próximo a drenar: menor `seq` elegível (naturalmente pula os não elegíveis).
export function nextEligible(mutations: QueuedMutation[], resolved: ReadonlySet<string>): QueuedMutation | undefined {
  return eligibleMutations(mutations, resolved)[0]
}
