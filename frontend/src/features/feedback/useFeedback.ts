import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { feedbackApi, type FeedbackContext, type FeedbackDTO } from '@/lib/api/endpoints'
import { qk } from '@/lib/query/keys'
import { useWorkspaceStore } from '@/store/workspaceStore'

// send-feedback — o envio (qualquer membro) e a leitura da caixa (dono). Os
// componentes em `features/*` podem falar com `lib/api` (regra A dos sweeps); as
// telas em `app/` e os primitivos consomem estes hooks.

// Envio do feedback. `context` é o pacote automático montado pela tela (rota/
// workspace/papel/dispositivo). No sucesso invalida a caixa do próprio workspace
// (se quem enviou for o dono, a lista dele já reflete) — só a chave específica
// (regra D), nunca o tenant inteiro.
export function useSubmitFeedback() {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: { message: string; context: FeedbackContext }) => feedbackApi.create(input),
    onSuccess: () => {
      if (wsId) qc.invalidateQueries({ queryKey: qk.feedbacks(wsId) })
    },
  })
}

// Caixa do dono. Só é montada em contexto owner (a tela gateia por papel); a query
// carrega a lista do workspace corrente, mais recentes primeiro (ordem do servidor).
export function useFeedbacks() {
  const wsId = useWorkspaceStore((s) => s.currentWorkspaceId)
  return useQuery<FeedbackDTO[]>({
    queryKey: qk.feedbacks(wsId ?? '_'),
    queryFn: () => feedbackApi.list(),
    enabled: Boolean(wsId),
  })
}
