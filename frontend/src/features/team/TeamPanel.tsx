import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import {
  invitationsApi,
  membershipsApi,
  type InvitationDTO,
  type MemberDTO,
} from '../../lib/api/endpoints'
import { useWorkspaceStore } from '../../store/workspaceStore'
import { inviteText } from '../../lib/i18n/invitations'
import { Button } from '../../components/ui/Button'
import { InviteDialog } from './InviteDialog'

// team-access-management §"Painel de equipe" (tarefa 4.5 / D9, D-INV-10).
//
// Componente que `workspace-settings` (§3.9) vai montar na tela de
// Configurações; aqui ele já é montável sozinho pela rota `/configuracoes/equipe`.
//
// As chaves de cache são `['ws', wsId, …]` (D9) — o mesmo prefixo que
// `handleAccessRevoked` remove quando o acesso ao workspace é perdido. Se as
// chaves não tivessem o `wsId`, os dados da equipe de um workspace vazariam para
// a tela de outro na troca de contexto.
//
// Os controles de mutação só aparecem para o dono. Isso é CONVENIÊNCIA: quem
// chamar a API direto recebe 403 do servidor (invariante 1) — há request spec
// negativo provando exatamente isso.
export function TeamPanel() {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const roleLabel = useWorkspaceStore((s) => s.currentRoleLabel)
  const isOwner = roleLabel === 'owner'
  const queryClient = useQueryClient()
  const [dialogAberto, setDialogAberto] = useState(false)

  const members = useQuery({
    queryKey: ['ws', wsId, 'members'],
    queryFn: () => membershipsApi.list(),
    enabled: Boolean(wsId),
  })

  const invitations = useQuery({
    queryKey: ['ws', wsId, 'invitations'],
    queryFn: () => invitationsApi.list(),
    enabled: Boolean(wsId) && isOwner,
  })

  function invalidar(chave: 'members' | 'invitations') {
    void queryClient.invalidateQueries({ queryKey: ['ws', wsId, chave] })
  }

  const mudarPapel = useMutation({
    mutationFn: ({ id, role }: { id: string; role: 'view' | 'edit' }) => membershipsApi.updateRole(id, role),
    onSuccess: () => invalidar('members'),
    onError: () => toast.error(inviteText.mutateFailure),
  })

  const remover = useMutation({
    mutationFn: (id: string) => membershipsApi.remove(id),
    onSuccess: () => invalidar('members'),
    onError: () => toast.error(inviteText.mutateFailure),
  })

  const revogar = useMutation({
    mutationFn: (id: string) => invitationsApi.revoke(id),
    onSuccess: () => invalidar('invitations'),
    onError: () => toast.error(inviteText.mutateFailure),
  })

  return (
    <section aria-label={inviteText.teamTitle} className="space-y-8">
      <header className="flex items-center justify-between">
        <h2 className="text-xl font-semibold">{inviteText.teamTitle}</h2>
        {isOwner && !dialogAberto && (
          <Button onClick={() => setDialogAberto(true)}>{inviteText.inviteTitle}</Button>
        )}
      </header>

      {!isOwner && <p className="text-sm text-muted-foreground">{inviteText.readOnlyNotice}</p>}

      {dialogAberto && (
        <InviteDialog
          onCreated={() => invalidar('invitations')}
          onClose={() => setDialogAberto(false)}
        />
      )}

      <div>
        <h3 className="font-medium">{inviteText.membersTitle}</h3>
        {members.isError && <p className="mt-2 text-sm text-destructive">{inviteText.loadFailure}</p>}
        <ul className="mt-2 divide-y rounded-lg border">
          {(members.data ?? []).map((member) => (
            <LinhaMembro
              key={member.id}
              member={member}
              isOwner={isOwner}
              onChangeRole={(role) => mudarPapel.mutate({ id: member.id, role })}
              onRemove={() => {
                if (window.confirm(inviteText.removeConfirm(member.name ?? member.email ?? ''))) {
                  remover.mutate(member.id)
                }
              }}
            />
          ))}
        </ul>
      </div>

      {isOwner && (
        <div>
          <h3 className="font-medium">{inviteText.invitationsTitle}</h3>
          {(invitations.data ?? []).length === 0 && !invitations.isLoading && (
            <p className="mt-2 text-sm text-muted-foreground">{inviteText.invitationsEmpty}</p>
          )}
          <ul className="mt-2 divide-y rounded-lg border">
            {(invitations.data ?? []).map((invitation) => (
              <LinhaConvite
                key={invitation.id}
                invitation={invitation}
                onRevoke={() => {
                  if (window.confirm(inviteText.revokeConfirm(invitation.email))) {
                    revogar.mutate(invitation.id)
                  }
                }}
              />
            ))}
          </ul>
        </div>
      )}
    </section>
  )
}

function rotuloPapel(role: string) {
  if (role === 'owner') return inviteText.roleOwner
  if (role === 'edit') return inviteText.roleEdit
  return inviteText.roleView
}

function LinhaMembro({
  member,
  isOwner,
  onChangeRole,
  onRemove,
}: {
  member: MemberDTO
  isOwner: boolean
  onChangeRole: (role: 'view' | 'edit') => void
  onRemove: () => void
}) {
  // O dono nunca ganha controles: o papel dele é derivado de `owner_user_id` e é
  // imutável (invariante 5), e um workspace sem dono é irrecuperável.
  const mutavel = isOwner && !member.is_owner

  return (
    <li className="flex items-center justify-between gap-4 px-4 py-3">
      <div>
        <p className="text-sm font-medium">{member.name}</p>
        <p className="text-xs text-muted-foreground">{member.email}</p>
      </div>

      <div className="flex items-center gap-2">
        {mutavel ? (
          <select
            aria-label={`${inviteText.changeRole}: ${member.name ?? ''}`}
            value={member.role}
            onChange={(e) => onChangeRole(e.target.value as 'view' | 'edit')}
            className="rounded-md border bg-background px-2 py-1 text-sm"
          >
            <option value="view">{inviteText.roleView}</option>
            <option value="edit">{inviteText.roleEdit}</option>
          </select>
        ) : (
          <span className="text-sm text-muted-foreground">{rotuloPapel(member.role)}</span>
        )}

        {mutavel && (
          <Button variant="outline" size="sm" onClick={onRemove}>
            {inviteText.removeMember}
          </Button>
        )}
      </div>
    </li>
  )
}

function LinhaConvite({ invitation, onRevoke }: { invitation: InvitationDTO; onRevoke: () => void }) {
  // Um convite expirado que ainda não foi expurgado NÃO é apresentado como
  // pendente ativo: o dono precisa saber que aquele link já não funciona.
  const expirado = invitation.status === 'expired'

  return (
    <li className="flex items-center justify-between gap-4 px-4 py-3">
      <div>
        <p className="text-sm font-medium">{invitation.email}</p>
        <p className="text-xs text-muted-foreground">
          {rotuloPapel(invitation.role)} · {expirado ? inviteText.statusExpired : inviteText.statusPending}
        </p>
      </div>

      <div className="flex items-center gap-2">
        <input
          aria-label={`${inviteText.inviteLinkReady}: ${invitation.email}`}
          readOnly
          value={invitation.invite_url}
          onFocus={(e) => e.currentTarget.select()}
          className="hidden w-64 rounded-md border bg-background px-2 py-1 text-xs md:block"
        />
        <Button variant="outline" size="sm" onClick={onRevoke}>
          {inviteText.revokeInvite}
        </Button>
      </div>
    </li>
  )
}
