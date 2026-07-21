import { useCallback, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { catalogKeys } from '../../lib/api/catalogKeys'
import type { TaskDTO } from '../../lib/api/endpoints'
import { useWorkspaceStore } from '../../store/workspaceStore'

// progress-advances 5.1–5.2 (§2.4 itens 1 e 5, D-UI/D9) — o estado do rascunho
// de avanço, sem espelhar o progresso do servidor.
//
// A regra que este hook existe para NÃO quebrar (D-UI): o valor dos botões
// `−10`/`+10` é lido do estado ATUAL (o cache das tarefas do robô), nunca de um
// valor capturado numa closure de render. É por isso que não há `useState` de
// progresso nem `useEffect` de sincronização: dois `+10` em avanços sucessivos
// somam `+20` porque cada leitura consulta o cache já invalidado, não uma cópia
// velha.
//
// O slider é controlado por `draft ?? serverProgress`: enquanto o rascunho é
// nulo, o slider mostra o valor persistido; cancelar/`Esc` zera o rascunho e,
// por construção, o slider VOLTA ao servidor sem nenhum código de "desfazer"
// (§2.4 item 5). `from`/`lockVersion` são congelados na ABERTURA (primeira
// alteração) — é o `lock_version` que vai no POST (5.4), o retrato do momento em
// que o operador começou a mexer.

export function clampProgress(value: number): number {
  if (!Number.isFinite(value)) return 0
  return Math.max(0, Math.min(100, Math.round(value)))
}

export interface AdvanceOrigin {
  from: number
  lockVersion: number
}

export function useAdvanceDraft(robotId: string, taskId: string) {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const queryClient = useQueryClient()
  const [draft, setDraftState] = useState<number | null>(null)
  const [origin, setOrigin] = useState<AdvanceOrigin | null>(null)

  // A fonte da verdade do progresso: o cache das tarefas do robô, lido no
  // INSTANTE da chamada (D-UI). `robot-task-table` popula essa chave; aqui só
  // consultamos.
  const readTask = useCallback((): TaskDTO | undefined => {
    const tasks = queryClient.getQueryData<TaskDTO[]>(catalogKeys.robotTasks(wsId, robotId))
    return tasks?.find((t) => t.id === taskId)
  }, [queryClient, wsId, robotId, taskId])

  const serverProgress = useCallback((): number => readTask()?.progress ?? 0, [readTask])

  // Congela `from`/`lockVersion` na primeira alteração do rascunho — não sobre-
  // escreve se já aberto (o operador pode arrastar várias vezes antes de
  // confirmar; o `lock_version` continua sendo o da abertura).
  const beginIfNeeded = useCallback(() => {
    setOrigin((prev) => {
      if (prev) return prev
      const t = readTask()
      return { from: t?.progress ?? 0, lockVersion: t?.lock_version ?? 0 }
    })
  }, [readTask])

  // Slider arrastado: define o rascunho direto.
  const setDraft = useCallback(
    (next: number) => {
      beginIfNeeded()
      setDraftState(clampProgress(next))
    },
    [beginIfNeeded],
  )

  // Botão `±10`: lê o progresso VIVO do cache e soma o delta, com clamp. `+10`
  // em 95 abre em 100; dois avanços de `+10` somam porque a segunda leitura já
  // vê o cache invalidado.
  const step = useCallback(
    (delta: number) => {
      const base = serverProgress()
      beginIfNeeded()
      setDraftState(clampProgress(base + delta))
    },
    [serverProgress, beginIfNeeded],
  )

  // Cancelar/`Esc`: zera rascunho e origem → slider volta ao servidor.
  const reset = useCallback(() => {
    setDraftState(null)
    setOrigin(null)
  }, [])

  const value = draft ?? serverProgress()

  return {
    value, // valor controlado do slider
    draft, // null = nada pendente
    origin, // { from, lockVersion } congelado na abertura
    isOpen: draft !== null,
    serverProgress,
    setDraft,
    step,
    reset,
  }
}
