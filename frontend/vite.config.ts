import { defineConfig, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'
import fs from 'fs'
import { createHash } from 'crypto'

// offline-pwa 2.4 — injeta o CACHE_NAME do build no service worker. O sw.js vive
// em public/ e é copiado cru para dist/ pelo Vite; aqui reescrevemos a cópia do
// dist trocando o placeholder `__CACHE_NAME__` por `robotrack-cache-<hash>`,
// onde o hash deriva do conteúdo do build. Cada deploy → cache novo → o
// `activate` do SW apaga o anterior. Roda só no build (não afeta dev/testes).
function swCacheName(): Plugin {
  let cacheName: string | undefined
  return {
    name: 'robotrack-sw-cache-name',
    apply: 'build',
    generateBundle(_options, bundle) {
      const material = Object.keys(bundle).sort().join('|')
      const hash = createHash('sha256').update(material).digest('hex').slice(0, 12)
      cacheName = `robotrack-cache-${hash}`
    },
    closeBundle() {
      const swPath = path.resolve(__dirname, 'dist/sw.js')
      if (cacheName && fs.existsSync(swPath)) {
        const src = fs.readFileSync(swPath, 'utf8').replace('__CACHE_NAME__', cacheName)
        fs.writeFileSync(swPath, src)
      }
    },
  }
}

export default defineConfig({
  plugins: [react(), swCacheName()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: 'http://localhost:3000',
        changeOrigin: true,
      },
      '/cable': {
        target: 'ws://localhost:3000',
        ws: true,
      },
    },
  },
  build: {
    // delivery-and-observability 4.2 — emite source maps para o Sentry mapear o
    // stack de produção. O CI os ENVIA ao Sentry e NÃO os publica no CDN (o
    // nginx.conf só serve /assets; os .map ficam fora do bundle servido).
    sourcemap: true,
    rollupOptions: {
      output: {
        manualChunks: {
          'react-vendor': ['react', 'react-dom'],
          'router-vendor': ['react-router-dom'],
          'ui-vendor': ['lucide-react', 'sonner'],
          'query-vendor': ['@tanstack/react-query'],
        },
      },
    },
  },
})