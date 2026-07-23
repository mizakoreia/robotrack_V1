// ESLint (offline-pwa 1.2 / D7-11) — guarda MÍNIMO, não uma suíte de estilo.
//
// A invariante que importa: `localStorage`, `sessionStorage` e `indexedDB` só
// podem ser tocados dentro de `src/lib/safeStorage.ts`. Qualquer acesso direto
// (bare `localStorage` OU `window.localStorage`) num componente/store novo QUEBRA
// o pipeline, em vez de depender de revisão humana — que reintroduziria o bug de
// tela branca em modo privado no primeiro store novo.
//
// Só estas regras estão ligadas de propósito: um lint de estilo completo sobre o
// codebase existente é escopo de `quality-and-accessibility`, não desta onda.

const STORAGE_GLOBALS = ['localStorage', 'sessionStorage', 'indexedDB']
const MSG = 'Acesse storage só por src/lib/safeStorage.ts (D7-11): storage direto lança em modo privado.'

module.exports = {
  root: true,
  parser: '@typescript-eslint/parser',
  parserOptions: { ecmaVersion: 2022, sourceType: 'module', ecmaFeatures: { jsx: true } },
  env: { browser: true, es2022: true },
  ignorePatterns: [
    'dist',
    'node_modules',
    'coverage',
    'public/**',
    '*.config.*',
    'vite.config.ts',
    '.eslintrc.cjs',
  ],
  rules: {
    // bare `localStorage` etc.
    'no-restricted-globals': ['error', ...STORAGE_GLOBALS.map((name) => ({ name, message: MSG }))],
    // `window.localStorage` etc. — no-restricted-globals não pega a forma de membro.
    'no-restricted-properties': [
      'error',
      ...STORAGE_GLOBALS.map((property) => ({ object: 'window', property, message: MSG })),
      ...STORAGE_GLOBALS.map((property) => ({ object: 'self', property, message: MSG })),
    ],
  },
  overrides: [
    {
      // O ÚNICO lugar autorizado a falar com os globais de storage.
      files: ['src/lib/safeStorage.ts'],
      rules: { 'no-restricted-globals': 'off', 'no-restricted-properties': 'off' },
    },
    {
      // Testes e o service worker (offline-pwa G2) manipulam storage de propósito.
      files: ['**/__tests__/**', '**/*.test.{ts,tsx}', 'src/test/**', '**/*.sw.ts'],
      rules: { 'no-restricted-globals': 'off', 'no-restricted-properties': 'off' },
    },
  ],
}
