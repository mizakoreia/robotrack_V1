// quality-and-accessibility 6.2 / D-QA-2 — os UUIDs e credenciais que o
// `rt:seed:e2e` planta são LITERAIS FIXOS (D1 permite PK do cliente), nunca
// Faker com semente: o mesmo id no seed é o id no assert, e o assert cita o id.
// Este arquivo é a fonte única compartilhada entre o seed (Ruby) e os specs (TS)
// — se divergir do `backend/lib/tasks/e2e.rake`, o teste de contrato `seed
// -constants.spec.ts` reprova.

// Tipo largo (não `typeof SEED.owner`, que fixaria os literais do owner e
// rejeitaria o guest ao passá-lo à mesma função).
export interface SeededUser {
  id: string
  name: string
  email: string
  password: string
}

export const SEED = {
  // Cenário BASE — o dono do workspace e um convidado, para o smoke do harness e
  // como alicerce dos fluxos que precisam de duas sessões (1 convite, 4 revogação).
  owner: {
    id: '0e2e0000-0000-4000-8000-000000000001',
    name: 'Dona E2E',
    email: 'owner@e2e.robotrack.local',
    password: 'e2e-owner-pw-2026',
  },
  guest: {
    id: '0e2e0000-0000-4000-8000-000000000002',
    name: 'Convidado E2E',
    email: 'guest@e2e.robotrack.local',
    password: 'e2e-guest-pw-2026',
  },
  // Terceiro usuário: JÁ é membro `edit` do workspace do dono. A suíte roda
  // INTEIRA com UMA semente — o spec do convite precisa de um convidado
  // NÃO-membro, o do avanço de alguém que já escreve.
  member: {
    id: '0e2e0000-0000-4000-8000-000000000003',
    name: 'Membro E2E',
    email: 'member@e2e.robotrack.local',
    password: 'e2e-member-pw-2026',
  },
  // Workspace do dono (id do cliente — D1 — para o bootstrap abrir o próprio
  // contexto de RLS ao criá-lo).
  workspace: {
    id: '0e2e0000-0000-4000-8000-0000000000a1',
    name: 'WS-E2E',
  },
  // Hierarquia do cenário [convite]: 1 tarefa a 40% (o convidado registra +10 → 50).
  project: { id: '0e2e0000-0000-4000-8000-0000000000b1', name: 'Linha E2E' },
  cell: { id: '0e2e0000-0000-4000-8000-0000000000c1', name: 'Célula E2E' },
  robot: { id: '0e2e0000-0000-4000-8000-0000000000d1', name: 'R01 E2E' },
  task: { id: '0e2e0000-0000-4000-8000-0000000000e1', desc: 'Soldar ponto A', progress: 40 },
} as const satisfies {
  owner: SeededUser
  guest: SeededUser
  member: SeededUser
  workspace: { id: string; name: string }
  project: { id: string; name: string }
  cell: { id: string; name: string }
  robot: { id: string; name: string }
  task: { id: string; desc: string; progress: number }
}
