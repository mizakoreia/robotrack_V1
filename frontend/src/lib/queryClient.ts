import { QueryClient } from '@tanstack/react-query'

// QueryClient compartilhado (identity-and-auth 6.7). Extraído de main.tsx para
// que o logout possa chamar `queryClient.clear()` e o cache do usuário anterior
// NÃO ser servido ao próximo usuário na mesma aba.
export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 60 * 5,
      retry: 1,
      refetchOnWindowFocus: false,
    },
  },
})
