import { test, expect, SEED, entrarNoWorkspace, apiBase } from '../fixtures/session'

// quality-and-accessibility 7.1 slice 3 (§4.1 inv. 4 / D-RTT gating) — "UI
// desabilitada sozinha NÃO é autorização". Um membro `view`:
//   (a) não tem os controles de avanço no DOM (FORA do DOM, não `disabled` — o
//       servidor é a garantia, robot-task-table);
//   (b) um POST forjado direto na API responde 403 (autorização fail-closed).
//
// Usa o `viewer` PRÉ-SEMEADO como membro `view` — a membership que o aceite de um
// convite `view` criaria. NÃO re-convida `guest` (que o spec do convite consome
// como convidado `edit`): re-convidar colidiria no banco único de uma rodada. A
// coreografia dono-convida-view→aceita é o MESMO caminho da slice 1 (só muda o
// papel); o que esta slice adiciona é o gating + o 403, que é o que importa.

test.describe('7.1 slice 3 — membro view: sem controle + 403 forjado', () => {
  test('o membro view NÃO tem os controles de avanço no DOM', async ({ viewerPage }) => {
    await entrarNoWorkspace(viewerPage, SEED.workspace.id)
    await viewerPage.goto(`/robo/${SEED.robot.id}`)
    // 1º expect: o robô carregou (nome no cabeçalho) — antes de afirmar AUSÊNCIA.
    await expect(viewerPage.getByRole('heading', { name: new RegExp(SEED.robot.name) })).toBeVisible()

    // Controle FORA do DOM (não apenas `disabled`): o slider de avanço não existe
    // para quem só lê. `disabled` sozinho seria burlável por quem forja o DOM.
    await expect(viewerPage.getByRole('slider', { name: 'Progresso da tarefa' })).toHaveCount(0)
  })

  test('POST de avanço forjado com o token do view responde 403', async ({ viewerPage, baseURL }) => {
    // O adversário que a UI não impede: lê o token da sessão do view e forja o POST
    // direto no backend. A autorização é fail-closed NO SERVIDOR.
    const token = await viewerPage.evaluate(() => {
      const raw = localStorage.getItem('robotrack.session')
      return raw ? ((JSON.parse(raw) as { accessToken?: string }).accessToken ?? '') : ''
    })
    expect(token).not.toEqual('')

    const res = await viewerPage.request.post(`${apiBase(baseURL)}/api/v1/tasks/${SEED.task.id}/advances`, {
      headers: {
        Authorization: `Bearer ${token}`,
        'X-Workspace-Id': SEED.workspace.id,
        'Content-Type': 'application/json',
      },
      data: { id: '0e2e0000-0000-4000-8000-0000000f0001', progress: 60, comment: 'forjado' },
    })
    // 403 (não 404): o view É membro do workspace — a falha é de PAPEL, não de
    // tenant. (Cross-tenant seria 404, corpo byte-idêntico a id inexistente.)
    expect(res.status()).toBe(403)
  })
})

// 7.1 slice 4 — sobrevivência do token ao redirect do Google. Anotado no design
// (EXECUCAO §274) como CANDIDATO A INTEGRAÇÃO, não E2E: exige um stub de OAuth
// (o provedor real não roda determinístico no CI). Fica como `fixme` explícito —
// a cobertura mora no fluxo de callback (`/auth/callback`) testado em RTL.
test.fixme('7.1 slice 4 — token sobrevive ao redirect do Google (stub de OAuth — integração)', () => {})
