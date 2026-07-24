import { defineConfig, devices } from '@playwright/test'

// quality-and-accessibility 6.1 (D-QA-1). O harness E2E aponta para o BUILD DE
// PRODUÇÃO servido (nunca `vite dev`): o service worker de D7 só registra em
// produção, e contra o dev server o fluxo offline falharia por um motivo obscuro
// em vez de dizer o que está errado. `E2E_BASE_URL` é o bundle prod servido
// (nginx da imagem, ou `vite preview`); sem ele o config aborta em vez de rodar
// contra um alvo errado por engano.
const baseURL = process.env.E2E_BASE_URL
if (!baseURL) {
  throw new Error(
    '[e2e] E2E_BASE_URL ausente — aponte para o BUILD DE PRODUÇÃO servido ' +
      '(ex.: http://localhost:4173 via `vite preview`, ou o nginx da imagem). ' +
      'Contra `vite dev` o service worker não registra e o fluxo offline mente.',
  )
}

const isCI = !!process.env.CI

export default defineConfig({
  testDir: './e2e/tests',
  // D-QA-1: retry local ESCONDE flake de quem podia consertá-lo no mesmo minuto.
  // 1 retry só sob CI (onde o flake vira ruído de merge), 0 local.
  retries: isCI ? 1 : 0,
  // 7.7: os 5 fluxos verdes em ≤8 min com 4 workers. Configurável pra o runner.
  workers: process.env.PLAYWRIGHT_WORKERS ? Number(process.env.PLAYWRIGHT_WORKERS) : 4,
  // Acima de 8 min a suíte é desligada por quem tem pressa (D-QA-1).
  globalTimeout: 8 * 60 * 1000,
  timeout: 60 * 1000,
  expect: { timeout: 10 * 1000 },
  forbidOnly: isCI,
  reporter: isCI ? [['github'], ['html', { open: 'never' }]] : [['list']],
  use: {
    baseURL,
    // Trace e vídeo SÓ em falha — o trace viewer é o que torna um flake depurável
    // em vez de virar `skip`; guardá-los sempre estoura a retenção do CI.
    trace: 'retain-on-failure',
    video: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [
    // PWA de chão de fábrica: Chromium (Android/desktop) + WebKit (iOS). Firefox
    // fica de fora de propósito (D-QA-1 — triplicaria o CI sem cobrir parque novo).
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'webkit', use: { ...devices['Desktop Safari'] } },
  ],
})
