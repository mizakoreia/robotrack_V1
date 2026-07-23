import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import { QueryClientProvider } from '@tanstack/react-query'
import App from './app/App'
import { queryClient } from './lib/queryClient'
import { installQueryKeyGuard } from './lib/query/guard'
import { registerServiceWorker } from './lib/pwa/register'
import './styles/globals.css'
import './styles/tokens-campfire.css'

// app-shell-navigation 6.3 (D9) — o guard de forma de key entra AQUI, depois de a
// migração das leituras estar feita: em DEV lança na primeira key fora da
// convenção (`['projects']`), em produção só reporta. Ligado só no runtime real;
// os testes usam clientes próprios e o exercitam isoladamente.
installQueryKeyGuard(queryClient)

// offline-pwa 2.4 — registra o service worker (só em produção) e avisa quando um
// deploy assume a aba durante a sessão.
registerServiceWorker()

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <App />
      </BrowserRouter>
    </QueryClientProvider>
  </React.StrictMode>,
)
