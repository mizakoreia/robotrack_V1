import { useNavigate } from 'react-router-dom'
import { Icon } from '@/components/icons/Icon'
import { Badge, type BadgeStatus } from '@/components/ui/Badge'
import { PortalMenu } from '@/components/menu/PortalMenu'
import { useMenu } from '@/components/menu/useMenu'
import { useWorkspaceStore } from '@/store/workspaceStore'
import { switchWorkspace } from '@/lib/workspace/switchWorkspace'
import { useWorkspaceIndex } from '@/lib/workspace/useWorkspaceIndex'

// app-shell-navigation 5.2/5.3 (§3.10, D-G) — o contexto do workspace. O seletor
// SÓ aparece com mais de um workspace; com exatamente um, o nome é texto estático
// FORA da ordem de tabulação (não um select desabilitado). O papel é BADGE
// (rótulo), nunca select (controle): lado a lado, só o seletor tem chevron e Tab.
const ROLE: Record<string, { label: string; status: BadgeStatus }> = {
  owner: { label: 'Dono', status: 'accent' },
  edit: { label: 'Editor', status: 'success' },
  view: { label: 'Somente leitura', status: 'na' },
}

function RoleBadge({ role }: { role: string | null }) {
  const r = (role && ROLE[role]) || ROLE.view // papel ausente cai para somente leitura
  return <Badge status={r.status}>{r.label}</Badge>
}

export function WorkspaceContext() {
  const navigate = useNavigate()
  const menu = useMenu()
  const { isError, refetch } = useWorkspaceIndex()
  const workspaces = useWorkspaceStore((s) => s.workspaces)
  const currentId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const role = useWorkspaceStore((s) => s.currentRoleLabel)
  const current = workspaces.find((w) => w.id === currentId)

  async function pick(id: string) {
    await switchWorkspace(id)
    navigate('/')
  }

  // 5.8 — degradação do índice: rede falhou e não há nenhum workspace em cache. A
  // casca segue navegável; aqui só o texto estático e a ação de nova tentativa —
  // sem seletor, sem badge (não há papel a exibir).
  if (isError && workspaces.length === 0) {
    return (
      <div className="flex min-w-0 items-center gap-2">
        <span className="panel-header truncate" tabIndex={-1}>
          RoboTrack
        </span>
        <button className="label-sm text-accent-ink hover:underline" onClick={() => void refetch()}>
          Recarregar
        </button>
      </div>
    )
  }

  return (
    <div className="flex min-w-0 items-center gap-2">
      {workspaces.length > 1 ? (
        <>
          <button
            {...menu.triggerProps}
            className="label-md flex min-w-0 items-center gap-1 rounded-md px-2 py-1 font-medium hover:bg-accent/10"
          >
            <span className="truncate">{current?.name ?? 'Selecionar workspace'}</span>
            <Icon name="chevron-down" size="sm" className="text-text-muted" />
          </button>
          <PortalMenu
            anchorRef={menu.anchorRef}
            open={menu.open}
            onClose={menu.close}
            label="Trocar de workspace"
            items={workspaces.map((w) => ({ label: w.name, onSelect: () => void pick(w.id) }))}
          />
        </>
      ) : (
        // exatamente 1 (ou 0): texto estático, sem affordance de clique, fora do Tab
        <span className="panel-header truncate" tabIndex={-1}>
          {current?.name ?? workspaces[0]?.name ?? 'RoboTrack'}
        </span>
      )}
      {/* badge só quando há workspace: índice vazio não exibe papel (5.8) */}
      {workspaces.length > 0 && <RoleBadge role={role} />}
    </div>
  )
}
