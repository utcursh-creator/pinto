# React 18 + Vite + TypeScript + Tailwind CSS - Skill Guide

> Sources: cursor.directory (Pontus Abrahamsson), awesome-cursorrules, React best practices 2025-2026

## Role

You are an expert in React 18, TypeScript, Vite, Tailwind CSS, Framer Motion, and modern component architecture. You build production-quality marketing websites with clean, maintainable code.

## Core Principles

1. Write concise, technical TypeScript code with accurate examples
2. Use functional and declarative programming patterns; avoid classes
3. Prefer iteration and modularization over code duplication
4. Use descriptive variable names with auxiliary verbs (isLoading, hasError, canSubmit)
5. Use lowercase-with-dashes for directories and files (e.g., `components/hero-section.tsx`)
6. Favor named exports for components
7. Use the `function` keyword for component definitions, not arrow functions for top-level exports

## TypeScript Standards

```typescript
// DO: Use interfaces for component props
interface HeroSectionProps {
  title: string;
  onBookCall: () => void;
}

// DO: Use function declarations for components
export function HeroSection({ title, onBookCall }: HeroSectionProps) {
  return <section>...</section>;
}

// DON'T: Use React.FC (adds children implicitly, less readable)
// DON'T: Use enums (use const objects or union types instead)
// DON'T: Use `any` type (use `unknown` if truly unknown)

// DO: Use `as const` for config objects
export const SITE_CONFIG = {
  name: 'VibeLife',
  tagline: 'You sell. I build. They use it.',
} as const;

// DO: Use union types for fixed sets
type NavLink = 'home' | 'services' | 'how-it-works' | 'resources';
```

## Component Architecture

### File Structure
```
src/
├── components/
│   ├── ui/              # Reusable primitives (button, modal)
│   ├── layout/          # Layout components (navbar, footer, smooth-scroll)
│   ├── animation/       # Animation wrappers (fade-in, floating-sphere)
│   ├── effects/         # Visual effects (grain, gradient-mesh)
│   ├── brand/           # Brand assets (client-logos)
│   └── sections/        # Page sections (hero, proof, cta)
├── pages/               # Route-level components
├── config/              # Centralized configuration
├── hooks/               # Custom hooks
└── lib/                 # Utilities
```

### Component Patterns

```tsx
// 1. Keep components small and focused (under 150 lines)
// 2. Extract sub-components when a section grows complex
// 3. Co-locate types with components
// 4. Use children sparingly; prefer explicit props

// Good: Explicit props
export function StatCard({ value, label, icon: Icon }: StatCardProps) {
  return (
    <div className="p-6 rounded-xl bg-void/50">
      <Icon className="w-5 h-5 text-gold" />
      <p className="text-3xl font-display">{value}</p>
      <p className="text-white/50 text-sm">{label}</p>
    </div>
  );
}

// Bad: Overly generic with children
export function Card({ children }: { children: React.ReactNode }) {
  return <div className="p-6">{children}</div>;
}
```

### State Management
```tsx
// 1. Lift state only as high as needed
// 2. Use useState for local UI state
// 3. Use useRef for DOM references and mutable values that don't trigger re-renders
// 4. Avoid useEffect for data derivation (use useMemo instead)
// 5. Minimize state; derive values from existing state

// Good: Derived state
const filteredPosts = posts.filter(p => p.category === activeCategory);

// Bad: Synced state
const [filteredPosts, setFilteredPosts] = useState([]);
useEffect(() => {
  setFilteredPosts(posts.filter(p => p.category === activeCategory));
}, [posts, activeCategory]);
```

## Tailwind CSS Standards

### Class Organization
```tsx
// Order: layout → sizing → spacing → typography → colors → borders → effects → states
<div className="flex items-center gap-4 p-6 text-sm text-white/60 bg-charcoal border border-white/10 rounded-xl shadow-lg hover:border-gold/20 transition-all duration-300">
```

### Rules
1. Mobile-first responsive design: `base → sm → md → lg → xl`
2. NEVER use dynamic class names: `text-${color}` breaks Tailwind JIT
3. Use pre-resolved static class strings instead
4. Extend theme in `tailwind.config.js` for brand colors, not arbitrary values
5. Use `@apply` sparingly (only for truly reusable patterns in CSS)
6. Prefer Tailwind utilities over custom CSS

```tsx
// BAD: Dynamic class (Tailwind can't detect this)
<span className={`text-${stat.color}`}>{stat.value}</span>

// GOOD: Pre-resolved static class
const stats = [
  { value: '50+', colorClass: 'text-teal' },
  { value: '95%', colorClass: 'text-gold' },
];
<span className={stat.colorClass}>{stat.value}</span>
```

## Vite Configuration

```typescript
// vite.config.ts
import path from "path";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

export default defineConfig({
  base: './',
  plugins: [react()],
  resolve: {
    alias: { "@": path.resolve(__dirname, "./src") },
  },
  build: {
    rollupOptions: {
      output: {
        manualChunks: {
          vendor: ['react', 'react-dom', 'react-router-dom'],
          animation: ['framer-motion'],
        },
      },
    },
  },
});
```

## Code Splitting

```tsx
// Always lazy-load route-level components
import { lazy, Suspense } from 'react';

const HomePage = lazy(() => import('@/pages/HomePage').then(m => ({ default: m.HomePage })));
const ServicesPage = lazy(() => import('@/pages/ServicesPage').then(m => ({ default: m.ServicesPage })));

function App() {
  return (
    <Suspense fallback={<div className="min-h-screen bg-void" />}>
      <Routes>
        <Route path="/" element={<HomePage />} />
        <Route path="/services" element={<ServicesPage />} />
      </Routes>
    </Suspense>
  );
}
```

## Framer Motion Patterns

```tsx
// 1. Use FadeInView wrapper for scroll-triggered animations
// 2. Prefer CSS animations for continuous effects (float, pulse, marquee)
// 3. Use Framer Motion for interactive/gesture-based animations
// 4. Always add layoutId for shared element transitions
// 5. Use AnimatePresence for exit animations
// 6. Respect prefers-reduced-motion

// Good: Scroll-triggered with viewport
<motion.div
  initial={{ opacity: 0, y: 20 }}
  whileInView={{ opacity: 1, y: 0 }}
  viewport={{ once: true }}
  transition={{ duration: 0.6 }}
>

// Good: Hover interaction
<motion.div whileHover={{ y: -4 }} transition={{ type: 'spring', stiffness: 300 }}>

// Bad: Continuous JS animation (use CSS instead)
<motion.div animate={{ y: [0, -20, 0] }} transition={{ repeat: Infinity, duration: 4 }}>
```

## Accessibility Standards

```tsx
// 1. Semantic HTML: <nav>, <main>, <section>, <article>, <aside>, <footer>
// 2. ARIA labels on interactive elements
// 3. Keyboard navigation support
// 4. Focus management for modals and dropdowns
// 5. Color contrast ratios (WCAG AA minimum)
// 6. Skip navigation link

<nav aria-label="Main navigation">
<button aria-label="Open menu" aria-expanded={isOpen}>
<dialog aria-modal="true" aria-labelledby="modal-title">

// Click-outside-to-close pattern for dropdowns
useEffect(() => {
  function handleClickOutside(e: MouseEvent) {
    if (ref.current && !ref.current.contains(e.target as Node)) {
      setIsOpen(false);
    }
  }
  document.addEventListener('mousedown', handleClickOutside);
  return () => document.removeEventListener('mousedown', handleClickOutside);
}, []);
```

## Error Handling

```tsx
// 1. Handle errors at the beginning of functions
// 2. Use early returns for error conditions
// 3. Place the happy path last
// 4. Use guard clauses for preconditions
// 5. Implement error boundaries for React component trees

function handleSubmit(email: string) {
  if (!email) return;                          // Guard clause
  if (!isValidEmail(email)) {                  // Validation
    setError('Invalid email address');
    return;
  }
  // Happy path
  submitForm(email);
}
```

## Performance Rules

1. Minimize `useEffect` usage; prefer event handlers and derived state
2. Use `React.memo` only for expensive components with stable props
3. Use `useMemo` for expensive computations, not for simple values
4. Use `useCallback` only when passing callbacks to memoized children
5. Lazy load images below the fold
6. Use CSS animations over JS animations for continuous effects
7. Avoid inline object/array creation in JSX (causes re-renders)
8. Use `will-change` sparingly and remove after animation completes

## Anti-Patterns to Avoid

1. Never use `index` as React key for dynamic lists
2. Never mutate state directly
3. Never use `any` type
4. Never suppress TypeScript errors with `@ts-ignore`
5. Never use inline styles when Tailwind classes exist
6. Never put business logic in components (extract to utils/hooks)
7. Never use `document.querySelector` in React (use refs)
8. Never install packages you don't actively use
9. Never leave debug plugins in production builds
10. Never use string interpolation for Tailwind classes

## References
- [cursor.directory - React TypeScript rules](https://cursor.directory/rules/react)
- [awesome-cursorrules](https://github.com/PatrickJS/awesome-cursorrules)
- [React docs](https://react.dev)
- [Vite docs](https://vite.dev)
- [Tailwind CSS docs](https://tailwindcss.com/docs)
