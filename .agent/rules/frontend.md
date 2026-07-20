---
trigger: always_on
---

# Frontend Rules (React + TypeScript .tsx)

## 3) Frontend (React + TypeScript .tsx)

### 3.1 Stack

* **Builder**: Vite (ou Next.js se SSR necessário).
* **Linguagem**: TypeScript (.tsx).
* **UI**: Tailwind + shadcn/ui; ícones com `lucide-react`.
* **Estado**: React Query (server-state) + Zustand/Redux Toolkit (client-state).
* **HTTP**: Axios com **interceptores** para JWT/refresh e trat. de erros.
* **Roteamento**: React Router (ou Next Router).
* **i18n**: `react-i18next` (pt-BR default).
* **Themes**: dark/light via CSS vars + `prefers-color-scheme` + toggle persistido.
* **A11y**: WAI‑ARIA, foco visível, contraste AA+.

### 3.2 Organização de pastas

```
frontend/
  src/
    app/                 # rotas/pages
    components/
    features/
      auth/
      payments/
      chat/
    lib/
      api/
        client.ts        # axios preconfigurado
        endpoints.ts     # contratos TS das rotas
    store/
    styles/
    hooks/
    types/
```

### 3.3 Contratos & Tipagem

* **Gerar tipos** a partir do Swagger (`openapi-typescript`) e consumir em `endpoints.ts`.
* **Nunca** usar `any`. Estrito em `tsconfig`.

### 3.4 Realtime

* **Action Cable JS** (ou Sockette) com reconexão exponencial.
* Listeners por feature (ex.: `usePaymentsChannel`, `useNotificationsChannel`).

### 3.5 Erros & UX

* Toasts padronizados para sucesso/erro.
* Loading/skeletons; retry com `react-query`.
* Empty states com dicas de ação.

### 3.6 Comentários & Docs

* **JSDoc/TSdoc** obrigatório em componentes, hooks e funções utilitárias.
* Storybook (opcional) para catálogo de UI.

---

## 9) Temas (Dark/Light)

* **Design tokens** (CSS vars): `--bg`, `--fg`, `--muted`, `--primary`, `--accent`, `--radius`.
* `data-theme="dark|light"` na `<html>`; toggle salva em `localStorage`.
* Testes visuais mínimos por tema (screenshots Storybook/Playwright opcional).

---

## 11) Scripts & Comandos Rápidos (Frontend)

```bash
pnpm i
pnpm dev            # dev server
pnpm test           # vitest/jest
pnpm lint           # eslint
pnpm build          # produção
```
