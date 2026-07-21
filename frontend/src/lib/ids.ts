// commissioning-hierarchy 6.2 (D1/D-H1) — identidade gerada no CLIENTE.
//
// O id nasce aqui, não no servidor: é a pré-condição do offline (§4.2). Criar
// um robô sem rede exige ter o id ANTES da resposta, senão não há alvo para as
// tarefas dele nem para a fila de mutations de `offline-pwa`.
//
// O fallback importa: `crypto.randomUUID` não existe em contexto inseguro
// (http em rede local) nem em Safari antigo. Um fallback que gerasse "string
// qualquer" faria todo POST offline voltar 422 ao sincronizar — o servidor
// valida UUID v1–v8 RFC 4122. Este gera v4 de verdade.

export function newId(): string {
  const c = globalThis.crypto

  if (c && typeof c.randomUUID === 'function') return c.randomUUID()

  const bytes = new Uint8Array(16)
  if (c && typeof c.getRandomValues === 'function') {
    c.getRandomValues(bytes)
  } else {
    for (let i = 0; i < 16; i++) bytes[i] = Math.floor(Math.random() * 256)
  }

  bytes[6] = (bytes[6] & 0x0f) | 0x40 // versão 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80 // variante RFC 4122

  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('')
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
}

// Mesma regra do servidor (`Hierarchy::IdValidator`): v1–v8, variante RFC 4122.
export const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

export function isValidId(id: string): boolean {
  return UUID_RE.test(id)
}
