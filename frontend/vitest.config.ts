import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
    // Os specs de Playwright vivem em `e2e/` e rodam sob `@playwright/test`, NÃO
    // sob vitest — sem esta exclusão o vitest tenta coletá-los e falha no import
    // de `@playwright/test`. (Os testes de INTEGRAÇÃO `*.e2e.test.tsx` em `src/`
    // continuam sendo vitest e NÃO são afetados.)
    exclude: ['e2e/**', 'node_modules/**', 'dist/**'],
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
})