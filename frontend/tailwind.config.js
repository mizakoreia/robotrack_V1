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
        // design-system G1 — os PAPÉIS do RoboTrack (fonte única). A restrição de
        // namespace por propriedade (cheia só em bg/border/stroke/ring, tinta só
        // em text, sólida só em bg — D-DS-2) é do G2.
        'bg-main': 'hsl(var(--bg-main))',
        'bg-panel': 'hsl(var(--bg-panel))',
        'bg-nav': 'hsl(var(--bg-nav))',
        'bg-menu': 'hsl(var(--bg-menu))',
        'bg-sunken': 'hsl(var(--bg-sunken))',
        'bg-raised': 'hsl(var(--bg-raised))',
        'text-main': 'hsl(var(--text-main))',
        'text-muted': 'hsl(var(--text-muted))',
        track: 'hsl(var(--track))',
        success: 'hsl(var(--success))',
        'success-ink': 'hsl(var(--success-ink))',
        warning: 'hsl(var(--warning))',
        'warning-ink': 'hsl(var(--warning-ink))',
        danger: 'hsl(var(--danger))',
        'danger-ink': 'hsl(var(--danger-ink))',
        'danger-solid': 'hsl(var(--danger-solid))',
        na: 'hsl(var(--na))',
        'na-ink': 'hsl(var(--na-ink))',
        'accent-ink': 'hsl(var(--accent-ink))',
        'accent-solid': 'hsl(var(--accent-solid))',

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