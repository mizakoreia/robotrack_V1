import { openQueueDb, type QueueDB } from './db'
import { listMutations, transition } from './queue'
import { closureFrom, transitiveDependents } from './cascade'

// Reconciliação de itens falhos (offline-pwa 5.4 / D7-5, §2.4). Duas ações, e
// SÓ estas duas — o descarte é sempre explícito, nunca automático, nunca por TTL.

// Quantas alterações "Descartar N" descarta: o item falho + o fechamento
// transitivo dos dependentes bloqueados. É a contagem do rótulo do botão.
export async function closureCount(failedId: string, db?: QueueDB): Promise<number> {
  const all = await listMutations(undefined, db)
  return closureFrom(all, failedId).size
}

// "Descartar N alterações": remove o item e todo o fechamento transitivo da fila.
// A sobreposição otimista correspondente desaparece (G7) e a UI volta à verdade do
// servidor. Devolve quantos itens saíram.
export async function discardWithClosure(failedId: string, db?: QueueDB): Promise<number> {
  const d = db ?? (await openQueueDb())
  const all = await listMutations(undefined, d)
  const ids = closureFrom(all, failedId)
  const tx = d.transaction('mutations', 'readwrite')
  for (const id of ids) await tx.store.delete(id)
  await tx.done
  return ids.size
}

// "Corrigir e reenviar": edita o corpo do item falho, devolve-o a `enqueued`
// (zerando erro/tentativas/estado do servidor) e DESTRAVA os órfãos bloqueados —
// eles voltam a `enqueued` e a cascata drena de novo. O 409 de lock_version passa
// por aqui: nunca reenvio automático, só depois da correção do usuário.
export async function fixAndResend(failedId: string, newBody: unknown, db?: QueueDB): Promise<void> {
  const d = db ?? (await openQueueDb())
  const all = await listMutations(undefined, d)
  const item = all.find((m) => m.id === failedId)
  if (!item) return

  await transition(
    failedId,
    'enqueued',
    {
      body: newBody,
      attempts: 0,
      next_attempt_at: null,
      last_error: null,
      failure_class: undefined,
      server_state: undefined,
    },
    d,
  )

  const orphans = transitiveDependents(all, [item.resource_uuid])
  for (const oid of orphans) {
    const orphan = all.find((m) => m.id === oid)
    if (orphan?.state === 'blocked') {
      await transition(oid, 'enqueued', { last_error: null }, d)
    }
  }
}
