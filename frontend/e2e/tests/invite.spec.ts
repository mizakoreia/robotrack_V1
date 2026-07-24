import { test, expect, SEED } from '../fixtures/session'

// quality-and-accessibility 7.1 (Fluxo 1) — convite ponta a ponta com as DUAS
// sessões abertas ao mesmo tempo (a razão de o harness existir): o dono convida, o
// convidado aceita, e o painel de equipe do DONO reflete o novo membro. Requer o
// cenário `[convite]` semeado (`rt:seed:e2e[convite]`).
//
// SLICE 1 (aqui): o núcleo do plumbing — convite edit criado pela UI do dono, link
// aberto pela sessão do convidado (já autenticada → aceite automático), e o membro
// aparece na lista do dono. Os sub-casos de 7.1 (registrar +10 e ver a equipe
// atualizar, convite `view` com controle desabilitado + PATCH forjado 403,
// sobrevivência do token ao redirect do Google) entram nas próximas slices, depois
// que este núcleo rodar verde no par (Chromium+WebKit).

test.describe('Fluxo 1 — convite (duas sessões)', () => {
  test('dono convida edit, convidado aceita, e o membro aparece no painel do dono', async ({
    ownerPage,
    guestPage,
  }) => {
    // — Dono: cria o convite `edit` pela UI e pega o link —
    await ownerPage.goto('/configuracoes/equipe')
    await ownerPage.getByRole('button', { name: 'Convidar pessoa' }).click()
    await ownerPage.getByLabel('E-mail').fill(SEED.guest.email)
    await ownerPage.getByLabel('Papel').selectOption({ label: 'Pode editar' })
    await ownerPage.getByRole('button', { name: 'Gerar link de convite' }).click()

    // `exact: true`: getByLabel casa por SUBSTRING, e a lista de convites pendentes
    // tem um input "Link do convite: <email>" — dois elementos com o mesmo value,
    // ambiguidade que aparece quando a lista já renderizou (corrida, não navegador).
    const inviteUrl = await ownerPage.getByRole('textbox', { name: 'Link do convite', exact: true }).inputValue()
    expect(inviteUrl).toContain('/convite/')
    // Navega pelo CAMINHO (relativo ao front), não pela URL absoluta: o backend
    // monta o link a partir de APP_URL, que no E2E pode não ser a origem do front.
    const invitePath = new URL(inviteUrl).pathname

    // — Convidado (já autenticado): abrir o link auto-consome o convite —
    await guestPage.goto(invitePath)
    // O InviteRoute autenticado aceita e navega para a Visão Geral (sai do /convite).
    await expect(guestPage).not.toHaveURL(/\/convite\//)

    // — Dono: o novo MEMBRO aparece SEM reload manual —
    // Ancorado na REGIÃO "Membros": o mesmo e-mail também aparece em "Convites
    // pendentes", então uma busca na página inteira passaria com o convite ainda
    // PENDENTE — o oposto do que este fluxo prova. (Playwright reconsulta até o
    // timeout: se o realtime invalidar a lista, o convidado aparece sem recarregar.)
    const membros = ownerPage.getByRole('region', { name: 'Membros' })
    await expect(membros.getByText(SEED.guest.email)).toBeVisible({ timeout: 15_000 })

    // E o convite SAI de "Convites pendentes" — o dono não deve ver convite
    // pendente para quem já é membro.
    const pendentes = ownerPage.getByRole('region', { name: 'Convites pendentes' })
    await expect(pendentes.getByText(SEED.guest.email)).toHaveCount(0, { timeout: 15_000 })
  })
})
