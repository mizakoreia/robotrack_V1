import { test, expect, SEED, entrarNoWorkspace, apiBase } from '../fixtures/session'

// quality-and-accessibility 7.4 (Fluxo 3, §4.1 inv. 1 / D9) — troca de workspace SEM
// vazamento. O dono tem DOIS workspaces (WS-E2E + WS-ISCA, tudo prefixado `ISCA-`).
// Depois da troca, `switchWorkspace` LIMPA o cache inteiro: nenhum texto `ISCA-`
// aparece nas telas do WS-E2E (nem o inverso), uma URL profunda cruzada responde
// **404** (corpo sem o nome do robô do outro tenant — 403 com o nome já seria
// vazamento), e o cache velho NÃO pisca no primeiro render (asserção de estado
// final, count 0). Requer `rt:seed:e2e[troca]`.

test.describe('7.4 — troca de workspace sem vazamento', () => {
  test('trocar limpa o cache: nada ISCA- vaza, e URL cruzada responde 404', async ({ ownerPage, baseURL }) => {
    await entrarNoWorkspace(ownerPage, SEED.workspace.id)
    await ownerPage.goto('/')
    await expect(ownerPage.getByRole('link', { name: 'Visão Geral' })).toBeVisible()

    // Estamos no WS-E2E: o projeto próprio aparece, e NADA do tenant isca.
    await expect(ownerPage.locator('body')).toContainText(SEED.project.name)
    await expect(ownerPage.locator('body')).not.toContainText('ISCA-')

    // URL profunda CRUZADA (robô do WS-ISCA aberto no contexto do WS-E2E): 404, e o
    // corpo NÃO menciona o robô do outro tenant.
    await ownerPage.goto(`/robo/${SEED.isca.robot.id}`)
    await expect(ownerPage.getByRole('heading', { name: new RegExp(SEED.isca.robot.name) })).toHaveCount(0)
    await expect(ownerPage.locator('body')).not.toContainText(SEED.isca.robot.name)

    // GET forjado do robô cruzado com o header do WS-E2E → 404 (não 403: cross-tenant
    // é indistinguível de id inexistente).
    const token = await ownerPage.evaluate(() => {
      const raw = localStorage.getItem('robotrack.session')
      return raw ? ((JSON.parse(raw) as { accessToken?: string }).accessToken ?? '') : ''
    })
    const res = await ownerPage.request.get(`${apiBase(baseURL)}/api/v1/robots/${SEED.isca.robot.id}`, {
      headers: { Authorization: `Bearer ${token}`, 'X-Workspace-Id': SEED.workspace.id },
    })
    expect(res.status()).toBe(404)

    // — Troca pela UI para o WS-ISCA (o seletor só existe com >1 workspace) —
    await ownerPage.goto('/')
    await expect(ownerPage.getByRole('link', { name: 'Visão Geral' })).toBeVisible()
    await ownerPage.getByRole('button', { name: new RegExp(SEED.workspace.name) }).click()
    await ownerPage.getByRole('menu', { name: 'Trocar de workspace' }).getByText(SEED.isca.workspace.name).click()

    // Agora no WS-ISCA: aparece o projeto isca, e o do WS-E2E NÃO pisca (o cache foi
    // limpo ANTES do render — count 0 é asserção de estado final, não de intervalo).
    await expect(ownerPage.locator('body')).toContainText(SEED.isca.project.name)
    await expect(ownerPage.getByText(SEED.project.name, { exact: true })).toHaveCount(0)
  })
})
