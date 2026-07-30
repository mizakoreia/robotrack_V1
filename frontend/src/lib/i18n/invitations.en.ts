import type { InviteText } from './invitations'

// internationalization G4 — tradução EN dos textos de convite, equipe e revogação.
// Glossário confirmado: Convite→Invitation, "Código de convite"→"Invite code",
// "Convites pendentes"→"Pending invitations", "Convidar pessoa"→"Invite person",
// "Gerar código de convite"→"Generate invite code", Equipe→Team, Membros→Members,
// Revogar→Revoke, Remover→Remove, "Alterar papel"→"Change role", Papel→Role,
// E-mail→Email, Expirado→Expired, Pendente→Pending, Dono→Owner,
// "Pode editar"→"Can edit", "Pode visualizar"→"Can view".
export const inviteTextEn: InviteText = {
  // Guest flow
  opening: 'Opening the invitation…',
  previewTitle: 'You have been invited',
  previewRole: (role: string) => (role === 'edit' ? 'with permission to edit' : 'with permission to view'),
  previewFor: (emailMasked: string) => `Invitation for ${emailMasked}`,
  previewExpired: 'This invitation has expired. Ask the workspace administrator for a new one.',
  previewUsed: 'This invitation has already been used.',
  previewNotFound: 'Invitation not found. Check the link or ask for a new one.',
  previewContinue: 'Sign in to accept',
  previewLoading: 'Loading invitation…',

  // Accept outcomes
  accepted: (workspaceName?: string | null) =>
    workspaceName ? `You are now part of ${workspaceName}.` : 'Invitation accepted.',
  expired: 'This invitation has expired. Ask the workspace administrator for a new one.',
  alreadyUsed: 'This invitation has already been used.',
  alreadyMember: 'You are already part of this workspace.',
  emailMismatch: (emailMasked?: string | null) =>
    emailMasked
      ? `This invitation is for ${emailMasked}. Sign out and sign in with that account to accept it.`
      : 'This invitation is for another email. Sign out and sign in with the invited account to accept it.',
  emailMismatchAction: 'Sign out and sign in with another account',
  personConflict: 'The invitation email is already linked to another account in this workspace. Contact the administrator.',
  offline: 'Connect to accept the invitation.',
  genericFailure: 'Could not accept the invitation right now.',
  lostToken: 'We could not recover your invitation in this browser. You are already signed in — ask for the invite code again.',

  // Team panel
  teamTitle: 'Team',
  membersTitle: 'Members',
  invitationsTitle: 'Pending invitations',
  membersEmpty: 'There are no other members in this workspace yet.',
  invitationsEmpty: 'No pending invitations.',
  roleOwner: 'Owner',
  roleEdit: 'Can edit',
  roleView: 'Can view',
  statusExpired: 'Expired',
  statusPending: 'Pending',
  changeRole: 'Change role',
  removeMember: 'Remove',
  removeConfirm: (name: string) => `Remove ${name} from this workspace? The tasks assigned to this person are kept.`,
  confirmRemoveTitle: 'Remove member',
  revokeInvite: 'Revoke',
  revokeConfirm: (email: string) => `Revoke the invitation for ${email}? The code stops working immediately.`,
  confirmRevokeTitle: 'Revoke invitation',
  cancel: 'Cancel',
  loadFailure: 'Could not load the team.',
  mutateFailure: 'Could not complete the change.',
  readOnlyNotice: 'Only the workspace owner can invite, change roles or remove members.',

  // Invite dialog
  inviteTitle: 'Invite person',
  inviteEmailLabel: 'Email',
  inviteRoleLabel: 'Role',
  inviteSubmit: 'Generate invite code',
  inviteInvalidEmail: 'Enter a valid email.',
  invitePending: 'There is already a pending invitation for this email. Revoke the previous one to create another.',
  inviteForbidden: 'Only the workspace owner can invite.',
  close: 'Close',

  // code-only-invites — the code is the only path in the creation dialog
  inviteCodeReady: 'Invite code',
  inviteCodeHint: 'Whoever is at the computer can type this code on the sign-in screen. It expires in 48 hours.',
  copyCode: 'Copy code',
  codeCopied: 'Code copied.',
  copyCodeManual: 'Could not copy automatically. Select the code and copy it manually.',

  // invite-by-code — code status in the pending list
  codeStatusActive: 'Active code',
  codeStatusExpired: 'Expired code',
  codeStatusLocked: 'Locked code',

  // invite-by-code — "I have a code" section on the sign-in screen
  codeSectionTitle: 'I have an invite code',
  codeSectionHint: 'Received a code from the person in charge? Enter the invitation email and the code.',
  codeLabel: 'Invite code',
  codePlaceholder: 'XXXX-XXXX',
  codeEmailLabel: 'Invitation email',
  codeSubmitAuthed: 'Accept invitation',
  codeSubmitGuest: 'Save and sign in to accept',
  codeInvalidFormat: 'The code has 8 characters, in the format XXXX-XXXX.',
  codeSaved: 'Invitation saved. Sign in with your account to accept it.',

  // invite-by-code — accept-by-code outcomes
  codeLocked: 'This code has been locked after too many attempts. Ask the person in charge for a new code.',
  codeExpired: 'This code has expired. Ask the person in charge for a new one (or use the link, if you still have it).',
  codeInvalidPair: 'Code or email incorrect. Check both and try again.',

  // join-workspace-by-code — join another workspace by code while SIGNED IN.
  joinByCodeMenu: 'Join another workspace with a code',
  joinByCodeTitle: 'Join another workspace',
  joinByCodeHint: 'Received a code to collaborate in another workspace? Enter it below.',
  joinByCodeAs: (email: string) => `Joining as ${email}`,
  joinByCodeSubmit: 'Join workspace',

  // Access revocation
  accessRevoked: (workspaceName?: string | null) =>
    workspaceName
      ? `Your access to ${workspaceName} was removed by the workspace owner.`
      : 'Your access to this workspace was removed by the workspace owner.',
}
