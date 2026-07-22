import { QueryClient } from '@tanstack/react-query'

// QueryClient compartilhado (identity-and-auth 6.7). Extraído de main.tsx para
// que o logout possa chamar `queryClient.clear()` e o cache do usuário anterior
// NÃO ser servido ao próximo usuário na mesma aba.
// app-shell-navigation 1.1 (D9) — os defaults da convenção. `staleTime` 30s (o
// template usava 5min, tempo demais para dado de comissionamento que muda ao
// vivo); `gcTime` 5min; `retry` 1 em query e 0 em mutation (uma escrita que falha
// não deve ser reenviada em silêncio — o indicador de gravação mostra o erro).
export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 30,
      gcTime: 1000 * 60 * 5,
      retry: 1,
      refetchOnWindowFocus: false,
    },
    mutations: {
      retry: 0,
    },
  },
})
