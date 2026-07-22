import { useState } from 'react'
import { useWorkspaceStore } from '@/store/workspaceStore'
import { PeoplePanel } from '@/features/settings/PeoplePanel'
import { CatalogPanel } from '@/features/settings/CatalogPanel'
import { AppearancePanel } from '@/features/settings/AppearancePanel'
import { UtilitiesPanel } from '@/features/settings/UtilitiesPanel'
import { AuditLogModal } from '@/features/audit/AuditLogModal'
import { Button } from '@/components/ui/Button'
import { settingsText as T } from '@/lib/i18n/settings'
import { auditText } from '@/lib/i18n/audit'

// workspace-settings 6.x (§3.9, §3.11, §2.8) — a tela de Configurações que MONTA
// os painéis já entregues: Equipe (chips), Tarefas-base, Aparência, Utilitários
// (owner: backup + reset) e o gatilho do modal de auditoria (aberto a `view` —
// leitura é `read_workspace`; o servidor garante o clamp 200 e a ordem).
//
// Papel: o servidor é a AUTORIDADE (403/404); aqui o papel do store só decide o
// que renderizar — `view` não vê controles de escrita (fora do DOM, não
// `disabled`), e Utilitários só existe para o dono.
export function SettingsPage() {
  const role = useWorkspaceStore((s) => s.currentRoleLabel)
  const canWrite = role === 'owner' || role === 'edit'
  const [auditOpen, setAuditOpen] = useState(false)

  return (
    <div className="mx-auto max-w-3xl space-y-8 p-4">
      <h1 className="page-title">{T.title}</h1>
      <PeoplePanel canWrite={canWrite} />
      <CatalogPanel canWrite={canWrite} />
      <AppearancePanel />
      <section aria-labelledby="audit-section-title" className="space-y-3">
        <h2 id="audit-section-title" className="panel-header">{auditText.title}</h2>
        <div className="surface-panel space-y-2 rounded-lg border p-4">
          <p className="label-sm text-text-muted">{auditText.subtitle}</p>
          <Button type="button" variant="outline" onClick={() => setAuditOpen(true)}>
            {T.auditOpenButton}
          </Button>
          <AuditLogModal open={auditOpen} onClose={() => setAuditOpen(false)} />
        </div>
      </section>
      {role === 'owner' && <UtilitiesPanel />}
    </div>
  )
}
