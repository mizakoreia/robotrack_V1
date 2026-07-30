import { defineConfig, mergeConfig } from 'vite'
import base from './vite.config'

// Config do Vite DEV-ONLY para GitHub Codespaces. Ativa SÓ quando você roda
// `vite --config vite.config.codespaces.ts` (o script .devcontainer/scripts/dev.sh
// faz isso). NÃO afeta produção nem o dev local:
//   - `npm run build` (prod) usa `vite build`, que lê vite.config.ts — não este.
//   - o `tsc` do build só inclui `src` e `vite.config.ts` (tsconfig.node.json),
//     então este arquivo nunca é typechecked no build de produção.
//   - o dev local (`vite`/`npm run dev`) também continua usando vite.config.ts.
//
// O que adiciona sobre o config base (via mergeConfig):
//   1. allowedHosts `.app.github.dev` — o Vite 5+ bloqueia Host desconhecido;
//      no Codespace a página é servida por `<nome>-5173.app.github.dev`.
//   2. host: true — escuta em 0.0.0.0 (obrigatório para o forward do Codespace).
//   3. proxy same-origin para o Rails :3000 de TODOS os prefixos que o app usa.
//      Same-origin evita CORS e cross-porta: o dev.sh aponta VITE_API_URL/
//      VITE_WS_URL para a própria origem (-5173), e o proxy encaminha ao :3000.
const target = 'http://localhost:3000'

export default mergeConfig(
  base,
  defineConfig({
    server: {
      host: true,
      allowedHosts: ['.app.github.dev'],
      // No Codespace o WS de HMR sobe pela 443 (URL pública), não pela 5173.
      hmr: { clientPort: 443 },
      proxy: {
        '/api': { target, changeOrigin: true },
        '/auth': { target, changeOrigin: true },
        '/users': { target, changeOrigin: true },
        '/downloads': { target, changeOrigin: true },
        '/rails': { target, changeOrigin: true },
        '/cable': { target: 'ws://localhost:3000', ws: true },
      },
    },
  }),
)
