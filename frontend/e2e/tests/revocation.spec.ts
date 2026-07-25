import { test, expect, SEED, entrarNoWorkspace, apiBase } from '../fixtures/session'

// quality-and-accessibility 7.5 (Fluxo 4, D6 / §3.10) — revogação AO VIVO. O membro
// `edit` está com a tela do Robô aberta; o dono o remove; a sessão do membro sai do
// workspace em ≤5 s com um AVISO PERSISTENTE, e uma escrita em voo depois da
// revogação recebe 403 (a UI reverte o otimista). A sessão do DONO segue operante —
// um broadcast que deslogasse todo mundo passaria no assert principal e quebraria o
// produto. Requer `rt:seed:e2e[convite]` (o `member` é `edit`) + realtime no ar.
//
// DIVERGÊNCIA DE-QA-B3.1: o design dizia "anúncio em `#rt-alerts`"; a implementação
// avisa por um TOAST PERSISTENTE (`sonner`, `duration: Infinity`) — que é assertivo
// e sobrevive, cumprindo a mesma intenção. Afirmamos o TOAST (a realidade), não o
// `#rt-alerts`; alimentar a live-region também é melhoria menor anotada, não bloqueio.

test.describe('7.5 — revogação ao vivo', () => {
  test('dono remove o membro: a sessão do membro sai em ≤5s e a escrita pós-revogação dá 403', async ({
    ownerPage,
    memberPage,
    baseURL,
  }) => {
    // Membro edit com a tela do Robô aberta (tem controles — é edit).
    await entrarNoWorkspace(memberPage, SEED.workspace.id)
    await memberPage.goto(`/robo/${SEED.robot.id}`)
    await expect(memberPage.getByRole('slider', { name: 'Progresso da tarefa' }).first()).toBeVisible()

    // Dono remove o membro (o botão dispara `window.confirm` — aceitamos).
    ownerPage.on('dialog', (d) => void d.accept())
    await ownerPage.goto('/configuracoes/equipe')
    const membros = ownerPage.getByRole('region', { name: 'Membros' })
    await membros.getByText(SEED.member.email).waitFor()
    await ownerPage
      .getByRole('listitem')
      .filter({ hasText: SEED.member.email })
      .getByRole('button', { name: 'Remover' })
      .click()

    // A sessão do membro detecta em ≤5s (realtime `membership.revoked` do próprio
    // usuário) e AVISA de forma persistente — nomeando o workspace perdido.
    await expect(memberPage.getByText(new RegExp(`acesso a ${SEED.workspace.name} foi removido`, 'i'))).toBeVisible({
      timeout: 5_000,
    })

    // Escrita em voo DEPOIS da revogação: POST de avanço com o token do membro → 403
    // (a autorização reavalia a membership; a UI reverte o valor otimista).
    const token = await memberPage.evaluate(() => {
      const raw = localStorage.getItem('robotrack.session')
      return raw ? ((JSON.parse(raw) as { accessToken?: string }).accessToken ?? '') : ''
    })
    const res = await memberPage.request.post(`${apiBase(baseURL)}/api/v1/tasks/${SEED.task.id}/advances`, {
      headers: {
        Authorization: `Bearer ${token}`,
        'X-Workspace-Id': SEED.workspace.id,
        'Content-Type': 'application/json',
      },
      data: { id: '0e2e0000-0000-4000-8000-0000000f0002', progress: 60, comment: 'em voo pós-revogação' },
    })
    expect(res.status()).toBe(403)

    // A sessão do DONO segue OPERANTE (não foi deslogado pelo broadcast).
    await expect(ownerPage.getByRole('region', { name: 'Membros' })).toBeVisible()
  })
})
