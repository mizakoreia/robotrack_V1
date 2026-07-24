import { useMemo, useState } from 'react'
import { newId } from '../../lib/ids'
import { Button } from '@/components/ui/Button'
import { useRobotApplications } from '../catalog/useTaskTemplates'
import { useBatchCreateRobots, clampQuantity } from './useBatchRobots'

// Campos legíveis nos DOIS temas: sem estes tokens os inputs caíam no padrão do
// navegador (fundo branco), e no tema escuro o texto branco ficava invisível —
// branco sobre branco. Mesmos tokens do fix de contraste do login (bg-bg-main /
// text-text-main / border-input / placeholder text-text-muted).
const FIELD_CLASS =
  'mt-1 w-full rounded-md border border-input bg-bg-main px-3 py-2 text-text-main placeholder:text-text-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring'
const LABEL_CLASS = 'block text-sm font-medium text-text-main'

// robot-tasks 5.6 (§2.5) — assistente de DOIS passos, UMA requisição.
//
// Passo 1: quantidade (clamp visual em 50) + Aplicação (do endpoint de
// metadados, sem lista literal). Passo 2: um campo por robô, placeholder
// `R01 - Solda` que NUNCA vira o nome — só o que o usuário digita é enviado;
// nomes vazios são descartados. O servidor re-normaliza (é a fonte da verdade).
//
// Sem visual definitivo aqui (a tela é de `robot-task-table`/`hierarchy-screens`):
// isto é a lógica do fluxo, com marcações de teste.
export function BatchRobotWizard({ cellId, onDone }: { cellId: string; onDone?: () => void }) {
  const { data: applications } = useRobotApplications()
  const batch = useBatchCreateRobots(cellId)

  const [step, setStep] = useState<1 | 2>(1)
  const [quantity, setQuantity] = useState(1)
  const [application, setApplication] = useState<string>('')
  const [names, setNames] = useState<string[]>([''])

  const appList = applications ?? []
  const currentApp = application || appList[0] || ''

  const goToStep2 = () => {
    const n = clampQuantity(quantity)
    setNames((prev) => Array.from({ length: n }, (_, i) => prev[i] ?? ''))
    setStep(2)
  }

  const robots = useMemo(
    () =>
      names
        .map((name) => name.trim())
        .filter((name) => name.length > 0)
        .map((name) => ({ id: newId(), name })),
    [names],
  )

  const submit = () => {
    batch.mutate(
      { application: currentApp, robots },
      { onSuccess: () => onDone?.() },
    )
  }

  if (step === 1) {
    return (
      <div data-testid="batch-step-1" className="space-y-4">
        <label className={LABEL_CLASS}>
          Quantidade
          <input
            type="number"
            aria-label="Quantidade"
            className={FIELD_CLASS}
            value={quantity}
            min={1}
            max={50}
            onChange={(e) => setQuantity(clampQuantity(Number(e.target.value)))}
          />
        </label>
        <label className={LABEL_CLASS}>
          Aplicação
          <select
            aria-label="Aplicação"
            className={FIELD_CLASS}
            value={currentApp}
            onChange={(e) => setApplication(e.target.value)}
          >
            {appList.map((app) => (
              <option key={app} value={app}>
                {app}
              </option>
            ))}
          </select>
        </label>
        <div className="flex justify-end pt-2">
          <Button type="button" onClick={goToStep2}>
            Avançar
          </Button>
        </div>
      </div>
    )
  }

  return (
    <div data-testid="batch-step-2" className="space-y-4">
      <p className="text-sm text-text-muted">
        Dê um nome a cada robô. Os campos em branco são ignorados.
      </p>
      <div className="max-h-72 space-y-2 overflow-y-auto pr-1">
        {names.map((name, i) => (
          <input
            key={i}
            aria-label={`Nome do robô ${i + 1}`}
            className={FIELD_CLASS}
            placeholder="R01 - Solda"
            value={name}
            onChange={(e) =>
              setNames((prev) => {
                const next = [...prev]
                next[i] = e.target.value
                return next
              })
            }
          />
        ))}
      </div>
      <div className="flex items-center justify-between gap-2 pt-2">
        <Button type="button" variant="outline" onClick={() => setStep(1)}>
          Voltar
        </Button>
        <Button type="button" onClick={submit} disabled={robots.length === 0 || batch.isPending}>
          Criar {robots.length} robô(s)
        </Button>
      </div>
    </div>
  )
}
