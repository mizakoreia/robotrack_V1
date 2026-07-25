import { test, expect, SEED } from '../fixtures/session'

// join-workspace-by-code G2.1 — o fluxo IN-APP por código, para um usuário JÁ
// AUTENTICADO. Irmão de `invite-code.spec.ts` (que digita o código na tela de
// ENTRADA): aqui o convidado nunca passa por `/entrar` — ele abre o menu da conta,
// escolhe "Entrar em outro workspace com código" e digita SÓ o código (o e-mail é
// o da sessão). Requer o cenário `[convite]` semeado.
//
// Locators ancorados por diálogo/região + `{ exact: true }` (regra da casa): o
// campo "Código do convite" existe também no diálogo do dono, mas em PÁGINA distinta
// (ownerPage/guestPage) — sem colisão. O gatilho do menu da conta tem nome dinâmico
// ("Conta: <nome>"), casado por regex ancorada.

test.describe('Fluxo por código — in-app, usuário logado (duas sessões)', () => {
  test('membro logado entra noutro workspace pelo menu da conta + código', async ({
    ownerPage,
    guestPage,
  }) => {
    // — Dono: cria o convite `edit` pela UI e copia o CÓDIGO —
    await ownerPage.goto('/configuracoes/equipe')
    const equipe = ownerPage.getByRole('region', { name: 'Equipe' })
    await equipe.getByRole('button', { name: 'Convidar pessoa' }).click()

    const dialogoDono = ownerPage.getByRole('dialog', { name: 'Convidar pessoa' })
    await dialogoDono.getByLabel('E-mail').fill(SEED.guest.email)
    await dialogoDono.getByLabel('Papel').selectOption({ label: 'Pode editar' })
    await dialogoDono.getByRole('button', { name: 'Gerar código de convite' }).click()

    const codigo = await dialogoDono
      .getByRole('textbox', { name: 'Código do convite', exact: true })
      .inputValue()
    expect(codigo).toMatch(/^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$/)

    // — Convidado (autenticado, na Visão Geral do PRÓPRIO workspace): abre o menu da
    //   conta e escolhe a entrada por código. Nunca visita `/entrar`. —
    await guestPage.goto('/')
    await guestPage.getByRole('button', { name: /^Conta:/ }).click()
    const menuConta = guestPage.getByRole('menu', { name: 'Conta' })
    await menuConta.getByRole('menuitem', { name: 'Entrar em outro workspace com código' }).click()

    // Diálogo in-app: e-mail da sessão fixo + só o código.
    const dialogoEntrar = guestPage.getByRole('dialog', { name: 'Entrar em outro workspace' })
    await expect(dialogoEntrar.getByText(`Entrando como ${SEED.guest.email}`)).toBeVisible()
    await dialogoEntrar.getByLabel('Código do convite', { exact: true }).fill(codigo)
    await dialogoEntrar.getByRole('button', { name: 'Entrar no workspace' }).click()

    // Aceite consome, troca de workspace e o diálogo fecha (vai para a Visão Geral).
    await expect(dialogoEntrar).toHaveCount(0, { timeout: 15_000 })

    // — Dono: o novo MEMBRO aparece SEM reload manual (tempo real) —
    const membros = ownerPage.getByRole('region', { name: 'Membros' })
    await expect(membros.getByText(SEED.guest.email)).toBeVisible({ timeout: 15_000 })

    // E o convite SAI de "Convites pendentes" — não se mostra pendente a quem já é membro.
    const pendentes = ownerPage.getByRole('region', { name: 'Convites pendentes' })
    await expect(pendentes.getByText(SEED.guest.email)).toHaveCount(0, { timeout: 15_000 })
  })
})
