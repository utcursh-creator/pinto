# Web Performance & Core Web Vitals - Skill Guide

> Sources: Google Web Vitals documentation, awesome-cursorrules web-app-optimization, Lighthouse best practices 2025-2026

## Core Web Vitals Targets

| Metric | Good | Needs Improvement | Poor |
|--------|------|-------------------|------|
| **LCP** (Largest Contentful Paint) | < 2.5s | 2.5s - 4.0s | > 4.0s |
| **INP** (Interaction to Next Paint) | < 200ms | 200ms - 500ms | > 500ms |
| **CLS** (Cumulative Layout Shift) | < 0.1 | 0.1 - 0.25 | > 0.25 |

## 1. Largest Contentful Paint (LCP)

### What Causes Bad LCP
- Large unoptimized hero images
- Render-blocking CSS/JS
- Slow server response times
- Client-side rendering delay (SPA issue)

### Optimization Tactics

```html
<!-- Preload critical assets -->
<link rel="preload" href="/fonts/inter.woff2" as="font" type="font/woff2" crossorigin>
<link rel="preload" href="/images/hero.webp" as="image">

<!-- Preconnect to external origins -->
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
```

```tsx
// Hero image: eager load, explicit dimensions
<img
  src="/images/hero.webp"
  alt="Hero description"
  width={1920}
  height={1080}
  loading="eager"
  decoding="async"
  fetchPriority="high"
/>

// Below-fold images: lazy load
<img
  src="/images/feature.webp"
  alt="Feature description"
  width={600}
  height={400}
  loading="lazy"
  decoding="async"
/>
```

### Image Optimization
- Use WebP format (30-50% smaller than JPEG)
- Use AVIF for even better compression where supported
- Provide explicit width/height attributes
- Use srcset for responsive images
- Hero images: max 200KB
- Thumbnails: max 50KB
- Compress with tools like Squoosh, Sharp, or ImageOptim

## 2. Interaction to Next Paint (INP)

### What Causes Bad INP
- Heavy JavaScript execution during interactions
- Long hydration times
- Expensive re-renders
- Blocking the main thread

### Optimization Tactics

```tsx
// 1. Code split at route level
const Page = lazy(() => import('./Page'));

// 2. Debounce expensive handlers
import { useDebouncedCallback } from 'use-debounce';
const handleSearch = useDebouncedCallback((value: string) => {
  setSearchQuery(value);
}, 300);

// 3. Use startTransition for non-urgent updates
import { startTransition } from 'react';
function handleFilter(category: string) {
  startTransition(() => {
    setActiveCategory(category);
  });
}

// 4. Virtualize long lists (react-window or @tanstack/virtual)
// 5. Avoid inline object creation in render
// BAD: Creates new object every render
<Component style={{ color: 'red' }} />
// GOOD: Stable reference
const styles = { color: 'red' };
<Component style={styles} />
```

## 3. Cumulative Layout Shift (CLS)

### What Causes Bad CLS
- Images without dimensions
- Dynamically injected content above existing content
- Web fonts causing FOUT (Flash of Unstyled Text)
- Ads or embeds without reserved space

### Optimization Tactics

```tsx
// 1. Always specify width/height on images and videos
<img width={800} height={600} />
<video width={1920} height={1080} />

// 2. Reserve space for dynamic content
<div className="min-h-[400px]"> {/* Known content height */}
  {isLoaded ? <Content /> : <Skeleton />}
</div>

// 3. Use font-display: swap with size-adjust
@font-face {
  font-family: 'Inter';
  font-display: swap;
  size-adjust: 100%;
}

// 4. Avoid inserting content above existing content
// 5. Use transform for animations, not width/height/top/left
```

## 4. JavaScript Bundle Optimization

### Bundle Size Targets
- Initial JS: < 200KB gzipped
- Per-route chunks: < 50KB gzipped
- Total CSS: < 50KB gzipped

### Tactics

```typescript
// vite.config.ts - Manual chunk splitting
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

// Tree-shake imports
// BAD: Imports entire library
import { motion } from 'framer-motion';
// GOOD: Same (Framer Motion is tree-shakeable, but be aware of other libs)

// BAD: Import all icons
import * as Icons from 'lucide-react';
// GOOD: Import specific icons
import { ArrowRight, Check } from 'lucide-react';
```

### Audit Regularly
```bash
# Analyze bundle
npx vite-bundle-visualizer

# Check unused dependencies
npx depcheck

# Lighthouse performance audit
npx lighthouse https://vibelife.io --output=json
```

## 5. CSS Performance

```css
/* 1. Use transform/opacity for animations (GPU-accelerated) */
.animate-float {
  animation: float 4s ease-in-out infinite;
}
@keyframes float {
  0%, 100% { transform: translateY(0); }
  50% { transform: translateY(-20px); }
}

/* 2. Avoid will-change unless actively animating */
/* 3. Use contain: layout for isolated components */
.card {
  contain: layout;
}

/* 4. Minimize blur/filter usage (expensive) */
/* 5. Use CSS animations over JS for continuous effects */

/* 6. Respect reduced motion */
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
  }
}
```

## 6. Font Optimization

```html
<!-- Preconnect to Google Fonts -->
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>

<!-- Load only needed weights -->
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
```

### Rules
- Load only weights you actually use (400, 500, 600, 700)
- Use `font-display: swap` (Google Fonts does this by default)
- Consider self-hosting fonts for faster load (no DNS lookup)
- Use `woff2` format (best compression)
- Subset fonts if only using Latin characters

## 7. Network Optimization

```html
<!-- DNS prefetch for third-party domains -->
<link rel="dns-prefetch" href="https://calendly.com">

<!-- Preconnect for critical third-party origins -->
<link rel="preconnect" href="https://fonts.googleapis.com">
```

### Rules
- Minimize third-party scripts
- Defer non-critical scripts
- Use HTTP/2 or HTTP/3
- Enable gzip/brotli compression on server
- Set proper cache headers (static assets: 1 year, HTML: no-cache)

## 8. Performance Monitoring Checklist

- [ ] Lighthouse score > 90 on all categories
- [ ] LCP < 2.5s on 3G throttled connection
- [ ] INP < 200ms on mid-range device
- [ ] CLS < 0.1
- [ ] Total JS bundle < 300KB gzipped
- [ ] CSS < 50KB gzipped
- [ ] No render-blocking resources
- [ ] Images optimized (WebP, lazy loaded, sized)
- [ ] Fonts preloaded with font-display: swap
- [ ] prefers-reduced-motion respected
- [ ] No unused CSS/JS in production bundle
- [ ] Code split at route level

## References
- [Google Web Vitals](https://web.dev/vitals/)
- [React Performance](https://react.dev/learn/render-and-commit)
- [Vite Build Optimization](https://vite.dev/guide/build)
- [Tailwind CSS Performance](https://tailwindcss.com/docs/optimizing-for-production)
