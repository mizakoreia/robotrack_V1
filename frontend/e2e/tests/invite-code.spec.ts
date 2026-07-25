import { test, expect, SEED } from '../fixtures/session'

// invite-by-code G5.2 — o fluxo por CÓDIGO ponta a ponta, irmão de `invite.spec.ts`
// (que cobre o LINK). O dono cria o convite, copia o CÓDIGO exibido no diálogo, e o
// convidado o digita na seção "Tenho um código de convite" da tela de entrada; o
// membro aparece no painel do dono. Requer o cenário `[convite]` semeado.
//
// Locators ancorados por região/diálogo + `{ exact: true }` (regra da casa): o
// código do diálogo do dono e o campo de código da tela do convidado têm o MESMO
// nome acessível ("Código do convite"), mas vivem em PÁGINAS distintas
// (ownerPage/guestPage) — sem colisão.

test.describe('Fluxo por código — convite (duas sessões)', () => {
  test('dono cria convite, convidado aceita pelo CÓDIGO na tela de entrada', async ({
    ownerPage,
    guestPage,
  }) => {
    // — Dono: cria o convite `edit` pela UI e copia o CÓDIGO —
    await ownerPage.goto('/configuracoes/equipe')
    const equipe = ownerPage.getByRole('region', { name: 'Equipe' })
    await equipe.getByRole('button', { name: 'Convidar pessoa' }).click()

    const dialogo = ownerPage.getByRole('dialog', { name: 'Convidar pessoa' })
    await dialogo.getByLabel('E-mail').fill(SEED.guest.email)
    await dialogo.getByLabel('Papel').selectOption({ label: 'Pode editar' })
    await dialogo.getByRole('button', { name: 'Gerar link de convite' }).click()

    const codigo = await dialogo.getByRole('textbox', { name: 'Código do convite', exact: true }).inputValue()
    // Crockford, 8 chars XXXX-XXXX, sem I/L/O/U.
    expect(codigo).toMatch(/^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$/)

    // — Convidado (autenticado): digita e-mail+código na seção da tela de entrada —
    await guestPage.goto('/entrar')
    await guestPage.getByText('Tenho um código de convite').click() // abre o <details>
    await guestPage.getByLabel('E-mail do convite', { exact: true }).fill(SEED.guest.email)
    await guestPage.getByLabel('Código do convite', { exact: true }).fill(codigo)
    await guestPage.getByRole('button', { name: 'Aceitar convite' }).click()

    // Aceite autenticado consome e navega para a Visão Geral (sai do /entrar).
    await expect(guestPage).not.toHaveURL(/\/entrar/)

    // — Dono: o novo MEMBRO aparece SEM reload manual —
    const membros = ownerPage.getByRole('region', { name: 'Membros' })
    await expect(membros.getByText(SEED.guest.email)).toBeVisible({ timeout: 15_000 })

    // E o convite SAI de "Convites pendentes" — não se mostra convite pendente para
    // quem já é membro.
    const pendentes = ownerPage.getByRole('region', { name: 'Convites pendentes' })
    await expect(pendentes.getByText(SEED.guest.email)).toHaveCount(0, { timeout: 15_000 })
  })
})
