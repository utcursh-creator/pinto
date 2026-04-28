/** @type {import('tailwindcss').Config} */
module.exports = {
  darkMode: ["class"],
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        // --- Semantic CSS variable colors (shadcn compatibility) ---
        border: "hsl(var(--border))",
        input: "hsl(var(--input))",
        ring: "hsl(var(--ring))",
        background: "hsl(var(--background))",
        foreground: "hsl(var(--foreground))",
        primary: {
          DEFAULT: "hsl(var(--primary))",
          foreground: "hsl(var(--primary-foreground))",
        },
        secondary: {
          DEFAULT: "hsl(var(--secondary))",
          foreground: "hsl(var(--secondary-foreground))",
        },
        destructive: {
          DEFAULT: "hsl(var(--destructive) / <alpha-value>)",
          foreground: "hsl(var(--destructive-foreground) / <alpha-value>)",
        },
        muted: {
          DEFAULT: "hsl(var(--muted))",
          foreground: "hsl(var(--muted-foreground))",
        },
        accent: {
          DEFAULT: "hsl(var(--accent))",
          foreground: "hsl(var(--accent-foreground))",
        },
        popover: {
          DEFAULT: "hsl(var(--popover))",
          foreground: "hsl(var(--popover-foreground))",
        },
        card: {
          DEFAULT: "hsl(var(--card))",
          foreground: "hsl(var(--card-foreground))",
        },

        // --- Brand colors (CSS variable based, swap with theme) ---
        'void':           'rgb(var(--color-void) / <alpha-value>)',
        'void-deep':      'rgb(var(--color-void-deep) / <alpha-value>)',
        'charcoal':       'rgb(var(--color-charcoal) / <alpha-value>)',
        'charcoal-light': 'rgb(var(--color-charcoal-light) / <alpha-value>)',
        'panel-raised':   'rgb(var(--color-panel-raised) / <alpha-value>)',
        'gold':           'rgb(var(--color-gold) / <alpha-value>)',
        'gold-light':     'rgb(var(--color-gold-light) / <alpha-value>)',
        'teal':           'rgb(var(--color-teal) / <alpha-value>)',
        'coral':          'rgb(var(--color-coral) / <alpha-value>)',
        'sage':           'rgb(var(--color-sage) / <alpha-value>)',
        'lavender':       'rgb(var(--color-lavender) / <alpha-value>)',
        'slate-info':     'rgb(var(--color-slate-info) / <alpha-value>)',
        'ink':            'rgb(var(--color-ink) / <alpha-value>)',
        'ink-2':          'rgb(var(--color-ink-2) / <alpha-value>)',
        'ink-3':          'rgb(var(--color-ink-3) / <alpha-value>)',
        'ink-disabled':   'rgb(var(--color-ink-disabled) / <alpha-value>)',

        // --- Aliases for light mode compatibility ---
        'cream':          'rgb(var(--color-void) / <alpha-value>)',
        'warm-white':     'rgb(var(--color-panel-raised) / <alpha-value>)',
      },
      fontSize: {
        'display-xl': ['8rem', { lineHeight: '0.9', letterSpacing: '-0.03em' }],
        'display-lg': ['6rem', { lineHeight: '0.9', letterSpacing: '-0.03em' }],
        'display':    ['4.5rem', { lineHeight: '0.95', letterSpacing: '-0.03em' }],
        'display-sm': ['3.5rem', { lineHeight: '1.0', letterSpacing: '-0.03em' }],
        'title-xl':   ['2.5rem', { lineHeight: '1.1', letterSpacing: '-0.02em' }],
        'title':      ['2rem', { lineHeight: '1.15', letterSpacing: '-0.015em' }],
        'title-sm':   ['1.5rem', { lineHeight: '1.25', letterSpacing: '-0.01em' }],
        'body-lg':    ['1.125rem', { lineHeight: '1.7' }],
        'body':       ['1rem', { lineHeight: '1.7' }],
        'body-sm':    ['0.875rem', { lineHeight: '1.65' }],
        'caption':    ['0.75rem', { lineHeight: '1.5' }],
        'micro':      ['0.625rem', { lineHeight: '1.4' }],
        'label':      ['0.62rem', { lineHeight: '1.3', letterSpacing: '0.16em', fontWeight: '500' }],
      },
      fontFamily: {
        sans: ['DM Sans', 'system-ui', 'sans-serif'],
        display: ['Syne', 'system-ui', 'sans-serif'],
        mono: ['DM Mono', 'monospace'],
      },
      transitionTimingFunction: {
        'apple': 'cubic-bezier(0.25, 0.1, 0.25, 1)',
        'apple-bounce': 'cubic-bezier(0.34, 1.56, 0.64, 1)',
        'apple-smooth': 'cubic-bezier(0.4, 0, 0, 1)',
      },
      transitionDuration: {
        'micro': '120ms',
        'short': '280ms',
        'medium': '450ms',
        'long': '750ms',
      },
      borderRadius: {
        xl: "calc(var(--radius) + 4px)",
        lg: "22px",
        md: "14px",
        sm: "9px",
        xs: "4px",
        pill: "99px",
        '2xl': '1rem',
        '3xl': '1.5rem',
        '4xl': '2rem',
      },
      boxShadow: {
        xs: "0 1px 2px 0 rgb(0 0 0 / 0.05)",
        // Neumorphic shadows (swap via CSS variables)
        'neu-raised': 'var(--neu-raised)',
        'neu-inset':  'var(--neu-inset)',
        'neu-hover':  'var(--neu-hover)',
        // Glow effects (swap via CSS variables)
        'glow-gold': '0 0 60px rgb(var(--color-gold) / 0.3)',
        'glow-teal': '0 0 60px rgb(var(--color-teal) / 0.3)',
        // General shadows
        'soft': '0 4px 20px rgb(0 0 0 / 0.08)',
        'soft-lg': '0 8px 40px rgb(0 0 0 / 0.12)',
        'glass': '0 8px 32px rgb(var(--shadow-dark) / 0.3)',
      },
      maxWidth: {
        'content': '900px',
      },
      keyframes: {
        float: {
          '0%, 100%': { transform: 'translateY(0)' },
          '50%': { transform: 'translateY(-20px)' },
        },
        'float-slow': {
          '0%, 100%': { transform: 'translateY(0)' },
          '50%': { transform: 'translateY(-30px)' },
        },
        'pulse-glow': {
          '0%, 100%': { opacity: '0.6', transform: 'scale(1)' },
          '50%': { opacity: '1', transform: 'scale(1.05)' },
        },
        'gradient-border': {
          '0%': { backgroundPosition: '0% 50%' },
          '100%': { backgroundPosition: '200% 50%' },
        },
        marquee: {
          '0%': { transform: 'translateX(0%)' },
          '100%': { transform: 'translateX(-50%)' },
        },
        'section-enter': {
          '0%': { opacity: '0', transform: 'translateY(14px)' },
          '100%': { opacity: '1', transform: 'translateY(0)' },
        },
      },
      animation: {
        'float': 'float 4s ease-in-out infinite',
        'float-slow': 'float-slow 6s ease-in-out infinite',
        'pulse-glow': 'pulse-glow 3s ease-in-out infinite',
        'gradient-border': 'gradient-border 3s linear infinite',
        'marquee': 'marquee 35s linear infinite',
        'section-enter': 'section-enter 0.45s ease forwards',
      },
    },
  },
  plugins: [require("tailwindcss-animate")],
}
