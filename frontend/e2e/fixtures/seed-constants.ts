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
  // Workspace do dono (id do cliente — D1 — para o bootstrap abrir o próprio
  // contexto de RLS ao criá-lo).
  workspace: {
    id: '0e2e0000-0000-4000-8000-0000000000a1',
    name: 'WS-E2E',
  },
} as const satisfies { owner: SeededUser; guest: SeededUser; workspace: { id: string; name: string } }
