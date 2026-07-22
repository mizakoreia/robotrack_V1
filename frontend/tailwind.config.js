/** @type {import('tailwindcss').Config} */
export default {
  darkMode: ['class'],
  content: [
    './pages/**/*.{ts,tsx}',
    './components/**/*.{ts,tsx}',
    './app/**/*.{ts,tsx}',
    './src/**/*.{ts,tsx}',
  ],
  theme: {
    container: {
      center: true,
      padding: '2rem',
      screens: {
        '2xl': '1400px',
      },
    },
    extend: {
      colors: {
        // design-system G1/G2 — PAPÉIS neutros (usados como bg E text por serem
        // neutros): base e superfícies. As cores de STATUS NÃO ficam aqui (D-DS-2):
        // um genérico geraria `text-success` e `bg-success-ink`, que reprovam AA.
        // Elas moram em backgroundColor/textColor/borderColor/ringColor/stroke,
        // cada namespace restrito à sua propriedade (abaixo).
        'bg-main': 'hsl(var(--bg-main))',
        'bg-panel': 'hsl(var(--bg-panel))',
        'bg-nav': 'hsl(var(--bg-nav))',
        'bg-menu': 'hsl(var(--bg-menu))',
        'bg-sunken': 'hsl(var(--bg-sunken))',
        'bg-raised': 'hsl(var(--bg-raised))',
        'text-main': 'hsl(var(--text-main))',
        'text-muted': 'hsl(var(--text-muted))',
        track: 'hsl(var(--track))',

        // Aliases shadcn (o G8 os remove)
        border: 'hsl(var(--border))',
        input: 'hsl(var(--input))',
        ring: 'hsl(var(--ring))',
        background: 'hsl(var(--background))',
        foreground: 'hsl(var(--foreground))',
        primary: {
          DEFAULT: 'hsl(var(--primary))',
          foreground: 'hsl(var(--primary-foreground))',
        },
        secondary: {
          DEFAULT: 'hsl(var(--secondary))',
          foreground: 'hsl(var(--secondary-foreground))',
        },
        destructive: {
          DEFAULT: 'hsl(var(--destructive))',
          foreground: 'hsl(var(--destructive-foreground))',
        },
        muted: {
          DEFAULT: 'hsl(var(--muted))',
          foreground: 'hsl(var(--muted-foreground))',
        },
        accent: {
          DEFAULT: 'hsl(var(--accent))',
          foreground: 'hsl(var(--accent-foreground))',
        },
        popover: {
          DEFAULT: 'hsl(var(--popover))',
          foreground: 'hsl(var(--popover-foreground))',
        },
        card: {
          DEFAULT: 'hsl(var(--card))',
          foreground: 'hsl(var(--card-foreground))',
        },
      },
      // design-system G2 (D-DS-2) — as três variantes, cada uma restrita à sua
      // propriedade. `text-success` (cheia como texto) e `bg-success-ink` (tinta
      // como fundo) NÃO existem: o Tailwind não gera a classe, o erro fica visível
      // na primeira execução em vez de reprovar AA seis meses depois.
      backgroundColor: {
        // cheia como fundo de pílula tingida
        success: 'hsl(var(--success) / <alpha-value>)',
        warning: 'hsl(var(--warning) / <alpha-value>)',
        danger: 'hsl(var(--danger) / <alpha-value>)',
        na: 'hsl(var(--na) / <alpha-value>)',
        // sólida — fundo de texto branco (a única forma AA de branco sobre a cor)
        'accent-solid': 'hsl(var(--accent-solid))',
        'danger-solid': 'hsl(var(--danger-solid))',
      },
      textColor: {
        // tinta — o ÚNICO uso de cor de status como texto
        'success-ink': 'hsl(var(--success-ink))',
        'warning-ink': 'hsl(var(--warning-ink))',
        'danger-ink': 'hsl(var(--danger-ink))',
        'accent-ink': 'hsl(var(--accent-ink))',
        'na-ink': 'hsl(var(--na-ink))',
      },
      borderColor: {
        success: 'hsl(var(--success))',
        warning: 'hsl(var(--warning))',
        danger: 'hsl(var(--danger))',
        na: 'hsl(var(--na))',
      },
      ringColor: {
        success: 'hsl(var(--success))',
        warning: 'hsl(var(--warning))',
        danger: 'hsl(var(--danger))',
        accent: 'hsl(var(--accent))',
        na: 'hsl(var(--na))',
      },
      stroke: {
        success: 'hsl(var(--success))',
        warning: 'hsl(var(--warning))',
        danger: 'hsl(var(--danger))',
        accent: 'hsl(var(--accent))',
        na: 'hsl(var(--na))',
      },
      borderRadius: {
        xs: 'var(--r-xs)',
        pill: 'var(--r-pill)',
        xl: 'var(--r-xl)',
        lg: 'var(--radius)',
        md: 'calc(var(--radius) - 2px)',
        sm: 'calc(var(--radius) - 4px)',
      },
      boxShadow: {
        'sh-1': 'var(--sh-1)',
        'sh-2': 'var(--sh-2)',
        'sh-3': 'var(--sh-3)',
      },
      gridTemplateColumns: {
        cards: 'repeat(auto-fill, minmax(260px, 1fr))',
      },
      keyframes: {
        'accordion-down': {
          from: { height: 0 },
          to: { height: 'var(--radix-accordion-content-height)' },
        },
        'accordion-up': {
          from: { height: 'var(--radix-accordion-content-height)' },
          to: { height: 0 },
        },
      },
      animation: {
        'accordion-down': 'accordion-down 0.2s ease-out',
        'accordion-up': 'accordion-up 0.2s ease-out',
      },
    },
  },
  plugins: [require('tailwindcss-animate')],
}