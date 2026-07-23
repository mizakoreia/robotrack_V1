import type { QueuedMutation } from './types'

// Fechamento transitivo de dependentes (offline-pwa 5.3 / D7-5). Quando um item
// vai para `failed`, todo item que depende dele — direta ou indiretamente — fica
// ÓRFÃO e vai para `blocked` (não `failed`: não falhou, ficou sem pai). Os
// independentes continuam drenando.
//
// Também é a contagem do rótulo "Descartar N alterações": N = o item falho + este
// fechamento.

// IDs das mutations que dependem (transitivamente) de qualquer uuid em `rootUuids`.
export function transitiveDependents(
  mutations: QueuedMutation[],
  rootUuids: Iterable<string>,
): Set<string> {
  const roots = new Set(rootUuids)
  const dependents = new Set<string>()

  let changed = true
  while (changed) {
    changed = false
    for (const m of mutations) {
      if (dependents.has(m.id)) continue
      if (m.depends_on.some((uuid) => roots.has(uuid))) {
        dependents.add(m.id)
        // Quem depende deste item também fica órfão: seu uuid vira raiz.
        if (!roots.has(m.resource_uuid)) {
          roots.add(m.resource_uuid)
          changed = true
        }
      }
    }
  }
  return dependents
}

// Conjunto a descartar/contar a partir de um item falho: ele próprio + os órfãos.
export function closureFrom(mutations: QueuedMutation[], failedId: string): Set<string> {
  const failed = mutations.find((m) => m.id === failedId)
  if (!failed) return new Set()
  const orphans = transitiveDependents(mutations, [failed.resource_uuid])
  orphans.add(failedId)
  return orphans
}
