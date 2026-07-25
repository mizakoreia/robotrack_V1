// invite-by-code — normalização e máscara do código de convite no cliente.
//
// Espelha a `Invitation.normalize_code` do backend (Crockford Base32, sem I/L/O/U):
// maiúsculas, sem hífen/espaço, ambíguos de leitura mapeados (I/L→1, O→0). Digitar
// no galpão erra — a tolerância é requisito, não gentileza. O backend normaliza de
// novo, então o cliente é só ergonomia; a igualdade de hash é do servidor.

const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'
export const CODE_LENGTH = 8

// Forma canônica: 8 chars do alfabeto, sem separadores. É o que se envia ao
// servidor e o que se guarda no par.
export function normalizeInviteCode(input: string): string {
  const mapped = input
    .toUpperCase()
    .replace(/[\s–—-]/g, '')
    .replace(/I/g, '1')
    .replace(/L/g, '1')
    .replace(/O/g, '0')
  return Array.from(mapped)
    .filter((ch) => ALPHABET.includes(ch))
    .slice(0, CODE_LENGTH)
    .join('')
}

// Máscara de exibição `XXXX-XXXX` a partir de qualquer entrada parcial. O hífen é
// cosmético; a normalização o remove.
export function formatInviteCode(input: string): string {
  const canonical = normalizeInviteCode(input)
  if (canonical.length <= 4) return canonical
  return `${canonical.slice(0, 4)}-${canonical.slice(4)}`
}

export function isCompleteInviteCode(input: string): boolean {
  return normalizeInviteCode(input).length === CODE_LENGTH
}
