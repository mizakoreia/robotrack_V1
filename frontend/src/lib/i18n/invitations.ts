// Módulo ÚNICO de textos de convite, equipe e revogação (workspace-invitations
// 6.4 / D14). Nenhum literal dessas mensagens deve existir fora daqui no
// frontend — o CI verifica por grep. O motivo não é purismo de i18n: são as
// mensagens que o usuário lê num momento de confusão (convite errado, acesso
// perdido), e espalhá-las garante que uma delas fique dessincronizada das
// outras.

export const inviteText = {
  // Fluxo do convidado
  opening: 'Abrindo o convite…',
  previewTitle: 'Você foi convidado',
  previewRole: (role: string) => (role === 'edit' ? 'com permissão para editar' : 'com permissão para visualizar'),
  previewFor: (emailMasked: string) => `Convite para ${emailMasked}`,
  previewExpired: 'Este convite expirou. Peça um novo ao administrador do workspace.',
  previewUsed: 'Este convite já foi utilizado.',
  previewNotFound: 'Convite não encontrado. Confira o link ou peça um novo.',
  previewContinue: 'Entrar para aceitar',
  previewLoading: 'Carregando convite…',

  // Desfechos do aceite
  accepted: (workspaceName?: string | null) =>
    workspaceName ? `Você agora faz parte de ${workspaceName}.` : 'Convite aceito.',
  expired: 'Este convite expirou. Peça um novo ao administrador do workspace.',
  alreadyUsed: 'Este convite já foi utilizado.',
  alreadyMember: 'Você já faz parte deste workspace.',
  emailMismatch: (emailMasked?: string | null) =>
    emailMasked
      ? `Este convite é para ${emailMasked}. Saia e entre com essa conta para aceitá-lo.`
      : 'Este convite é para outro e-mail. Saia e entre com a conta convidada para aceitá-lo.',
  emailMismatchAction: 'Sair e entrar com outra conta',
  personConflict: 'O e-mail do convite já está vinculado a outra conta neste workspace. Fale com o administrador.',
  offline: 'Conecte-se para aceitar o convite.',
  genericFailure: 'Não foi possível aceitar o convite agora.',
  lostToken: 'Não conseguimos recuperar seu convite neste navegador. Você já está conectado — reabra o link do convite.',

  // Painel de equipe
  teamTitle: 'Equipe',
  membersTitle: 'Membros',
  invitationsTitle: 'Convites pendentes',
  membersEmpty: 'Ainda não há outros membros neste workspace.',
  invitationsEmpty: 'Nenhum convite pendente.',
  roleOwner: 'Dono',
  roleEdit: 'Pode editar',
  roleView: 'Pode visualizar',
  statusExpired: 'Expirado',
  statusPending: 'Pendente',
  changeRole: 'Alterar papel',
  removeMember: 'Remover',
  removeConfirm: (name: string) => `Remover ${name} deste workspace? As tarefas atribuídas a essa pessoa são mantidas.`,
  revokeInvite: 'Revogar',
  revokeConfirm: (email: string) => `Revogar o convite de ${email}? O link deixa de funcionar imediatamente.`,
  loadFailure: 'Não foi possível carregar a equipe.',
  mutateFailure: 'Não foi possível concluir a alteração.',
  readOnlyNotice: 'Só o dono do workspace pode convidar, alterar papéis ou remover membros.',

  // Diálogo de convite
  inviteTitle: 'Convidar pessoa',
  inviteEmailLabel: 'E-mail',
  inviteRoleLabel: 'Papel',
  inviteSubmit: 'Gerar link de convite',
  inviteLinkReady: 'Link do convite',
  inviteLinkHint: 'O RoboTrack não envia e-mail: copie o link e mande para a pessoa.',
  copyLink: 'Copiar link',
  copied: 'Link copiado.',
  copyManual: 'Não foi possível copiar automaticamente. Selecione o link e copie manualmente.',
  inviteInvalidEmail: 'Informe um e-mail válido.',
  invitePending: 'Já existe um convite pendente para este e-mail. Revogue o anterior para criar outro.',
  inviteForbidden: 'Só o dono do workspace pode convidar.',
  close: 'Fechar',

  // invite-by-code — código no diálogo de criação (ao lado do link)
  inviteCodeReady: 'Código do convite',
  inviteCodeHint: 'Quem está no computador pode digitar este código na tela de entrada. Ele expira antes do link — em 48 horas.',
  copyCode: 'Copiar código',
  codeCopied: 'Código copiado.',
  copyCodeManual: 'Não foi possível copiar automaticamente. Selecione o código e copie manualmente.',

  // invite-by-code — estado do código na lista de pendentes
  codeStatusActive: 'Código ativo',
  codeStatusExpired: 'Código expirado',
  codeStatusLocked: 'Código bloqueado',

  // invite-by-code — seção "Tenho um código" na tela de entrada
  codeSectionTitle: 'Tenho um código de convite',
  codeSectionHint: 'Recebeu um código do responsável? Digite o e-mail do convite e o código.',
  codeLabel: 'Código do convite',
  codePlaceholder: 'XXXX-XXXX',
  codeEmailLabel: 'E-mail do convite',
  codeSubmitAuthed: 'Aceitar convite',
  codeSubmitGuest: 'Guardar e entrar para aceitar',
  codeInvalidFormat: 'O código tem 8 caracteres, no formato XXXX-XXXX.',
  codeSaved: 'Convite guardado. Entre com sua conta para aceitá-lo.',

  // invite-by-code — desfechos do aceite por código
  codeLocked: 'Este código foi bloqueado por tentativas demais. Peça um novo código ao responsável.',
  codeExpired: 'Este código expirou. Peça um novo ao responsável (ou use o link, se ainda tiver).',
  codeInvalidPair: 'Código ou e-mail incorretos. Confira os dois e tente de novo.',

  // join-workspace-by-code — entrar noutro workspace por código estando LOGADO.
  // Diferente da tela de entrada: o e-mail é o da sessão (fixo), então só o
  // código é digitado. O item vive no menu da conta (sempre acessível, inclusive
  // com um único workspace — o seletor de workspace só existe com mais de um).
  joinByCodeMenu: 'Entrar em outro workspace com código',
  joinByCodeTitle: 'Entrar em outro workspace',
  joinByCodeHint: 'Recebeu um código para colaborar em outro workspace? Digite-o abaixo.',
  joinByCodeAs: (email: string) => `Entrando como ${email}`,
  joinByCodeSubmit: 'Entrar no workspace',

  // Revogação de acesso
  accessRevoked: (workspaceName?: string | null) =>
    workspaceName
      ? `Seu acesso a ${workspaceName} foi removido pelo dono do workspace.`
      : 'Seu acesso a este workspace foi removido pelo dono do workspace.',
} as const
