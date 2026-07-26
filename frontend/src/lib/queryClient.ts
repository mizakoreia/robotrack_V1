import { QueryClient } from '@tanstack/react-query'

// QueryClient compartilhado (identity-and-auth 6.7). Extraído de main.tsx para
// que o logout possa chamar `queryClient.clear()` e o cache do usuário anterior
// NÃO ser servido ao próximo usuário na mesma aba.
// app-shell-navigation 1.1 (D9) — os defaults da convenção. `staleTime` 30s (o
// template usava 5min, tempo demais para dado de comissionamento que muda ao
// vivo); `retry` 1 em query e 0 em mutation (uma escrita que falha não deve ser
// reenviada em silêncio — o indicador de gravação mostra o erro).
// offline-pwa (cache de leitura offline) — `gcTime` 24h: o snapshot reidratado do
// IndexedDB não pode ser coletado da memória no meio de uma sessão em modo avião,
// senão navegar para uma tela já vista (mas ociosa > gcTime) perderia os dados.
// A frescor continua governada pelo `staleTime` (30s) — offline a refetch fica
// PAUSADA (networkMode online) e o dado do cache segue à mostra.
export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 30,
      gcTime: 1000 * 60 * 60 * 24,
      retry: 1,
      refetchOnWindowFocus: false,
    },
    mutations: {
      retry: 0,
    },
  },
})
