// commissioning-hierarchy 6.5 (§2.9, D-H4) — a parte do drag & drop que NÃO é
// React: mover um item numa lista e reagir ao 409 do servidor.
//
// Função pura + resultado tipado, de propósito: `hierarchy-screens` pluga a
// alça de arraste e o toast por cima disto, e o teste do comportamento não
// precisa montar componente nenhum.

export interface Positioned {
  id: string
}

/** Reordena localmente para o feedback otimista (índice de origem → destino). */
export function moveItem<T extends Positioned>(items: T[], from: number, to: number): T[] {
  if (from === to || from < 0 || to < 0 || from >= items.length || to >= items.length) return items
  const copia = items.slice()
  const [movido] = copia.splice(from, 1)
  copia.splice(to, 0, movido)
  return copia
}

export type ReorderOutcome =
  | { status: 'ok'; items: unknown[] }
  | { status: 'conflict'; currentIds: string[] }
  | { status: 'error'; error: unknown }

interface ReorderErrorBody {
  error?: string
  details?: { current_ids?: string[] }
}

function bodyOf(error: unknown): { status?: number; body?: ReorderErrorBody } {
  const e = error as { response?: { status?: number; data?: ReorderErrorBody } }
  return { status: e?.response?.status, body: e?.response?.data }
}

// O 409 acontece quando outra pessoa criou/excluiu um irmão entre o carregamento
// da tela e o drop. NÃO reenviamos a ordem: gravar por cima apagaria o item novo
// da lista. O chamador recarrega o escopo e o usuário refaz o arrasto.
export async function submitReorder(
  send: () => Promise<unknown[]>,
): Promise<ReorderOutcome> {
  try {
    return { status: 'ok', items: await send() }
  } catch (error) {
    const { status, body } = bodyOf(error)
    if (status === 409 && body?.error === 'reorder_conflict') {
      return { status: 'conflict', currentIds: body.details?.current_ids ?? [] }
    }
    return { status: 'error', error }
  }
}
