// Fila offline — modelo (offline-pwa D7-3/D7-4/D7-8). A fila é um LOG DE COMANDOS,
// não um diff de estado: "+10 duas vezes offline" vira DOIS avanços na trilha, que
// é o produto. Cada item guarda o comando HTTP inteiro mais o grafo de dependência.

export type MutationState =
  | 'enqueued' // esperando drenar
  | 'inflight' // requisição em voo (uma por vez)
  | 'done' // 2xx — podável
  | 'failed' // erro permanente / quarentena (sobrevive até decisão do usuário)
  | 'blocked' // dependente de um item que falhou (fechamento transitivo)

// União FECHADA de comandos suportados. Fechada de propósito: um kind novo tem de
// ser adicionado aqui (e ganhar overlay/classificação), não aparecer por acaso.
export type MutationKind =
  | 'project.create'
  | 'project.rename'
  | 'cell.create'
  | 'cell.rename'
  | 'robot.create'
  | 'robot.rename'
  | 'robot.batch_create'
  | 'task.create'
  | 'task.update'
  | 'advance.create'

export type MutationMethod = 'POST' | 'PATCH' | 'PUT' | 'DELETE'

export interface QueuedMutation {
  id: string // uuid do cliente (D1) — keyPath do object store
  seq: number // monotônico por dispositivo; ordem de drenagem crescente (D7-3)
  kind: MutationKind
  resource_uuid: string // recurso que este comando cria/afeta; entra em resolved_uuids no 2xx
  workspace_id: string
  method: MutationMethod
  url: string
  body: unknown
  depends_on: string[] // uuids que precisam estar resolvidos antes (D7-4) — SEM default
  recorded_at: string // ISO, carimbado no ENFILEIRAMENTO (D8), não no envio
  state: MutationState
  attempts: number
  next_attempt_at: number | null
  last_error: string | null
}

// O que o produtor fornece. `depends_on` é OBRIGATÓRIO (sem default no tipo): um
// hook novo que o esqueça não compila — é a rede de segurança de D7-4. `recorded_at`
// é opcional aqui (default = instante do enfileiramento); os campos de estado e
// `seq` são atribuídos pela fila.
export type EnqueueInput = Pick<
  QueuedMutation,
  'id' | 'kind' | 'resource_uuid' | 'workspace_id' | 'method' | 'url' | 'body' | 'depends_on'
> & { recorded_at?: string }

export interface ResolvedUuid {
  uuid: string
  at: string
}

// Erro de fila cheia (D7-12): rejeição na ENTRADA, a fila existente é preservada.
export class QueueFullError extends Error {
  constructor(message = 'Fila offline cheia — conecte-se para sincronizar') {
    super(message)
    this.name = 'QueueFullError'
  }
}
