The code is not the product; the experience is. Code is merely the medium.
# Micro Website - Technical Specification

## 1. Tech Stack Overview

| Category | Technology |
|----------|------------|
| Framework | React 18 + TypeScript |
| Build Tool | Vite |
| Styling | Tailwind CSS 3.4 |
| UI Components | shadcn/ui |
| Animation | Framer Motion |
| Scroll Animation | GSAP ScrollTrigger |
| Icons | Lucide React |
| Font | Inter (Google Fonts) |

## 2. Tailwind Configuration

```javascript
// tailwind.config.js extensions
{
  theme: {
    extend: {
      colors: {
        'bg-primary': '#0a0a0a',
        'bg-secondary': '#111111',
        'bg-tertiary': '#1a1a1a',
        'accent-teal': '#14b8a6',
        'accent-gold': '#c9a962',
        'text-secondary': '#a1a1aa',
        'text-muted': '#71717a',
        'light-bg': '#f5f5f0',
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
      },
      animation: {
        'float': 'float 4s ease-in-out infinite',
        'float-slow': 'float 6s ease-in-out infinite',
        'float-fast': 'float 3s ease-in-out infinite',
        'pulse-glow': 'pulse-glow 3s ease-in-out infinite',
        'gradient-border': 'gradient-border 3s linear infinite',
        'marquee': 'marquee 20s linear infinite',
      },
      keyframes: {
        float: {
          '0%, 100%': { transform: 'translateY(0)' },
          '50%': { transform: 'translateY(-20px)' },
        },
        'pulse-glow': {
          '0%, 100%': { opacity: '0.6' },
          '50%': { opacity: '1' },
        },
        'gradient-border': {
          '0%': { backgroundPosition: '0% 50%' },
          '100%': { backgroundPosition: '200% 50%' },
        },
        marquee: {
          '0%': { transform: 'translateX(0%)' },
          '100%': { transform: 'translateX(-50%)' },
        },
      },
    },
  },
}
```

## 3. Component Inventory

### Shadcn/UI Components (Pre-installed)
- Button (customized: pill shape)
- Card (customized: dark theme)
- Input (customized: pill shape)
- Badge
- Tabs

### Custom Components

#### Layout Components
| Component | Props | Description |
|-----------|-------|-------------|
| `Navbar` | `scrolled: boolean` | Fixed navigation with scroll effect |
| `Section` | `className, children, id` | Wrapper for page sections |
| `Container` | `className, children` | Max-width container |

#### Animation Components
| Component | Props | Description |
|-----------|-------|-------------|
| `FloatingSphere` | `src, size, position, delay, duration` | Animated 3D sphere |
| `FadeInView` | `children, delay, direction` | Scroll-triggered fade in |
| `TextReveal` | `text, delay` | Character-by-character reveal |
| `ParallaxImage` | `src, speed` | Parallax background image |
| `GradientBorder` | `children` | Animated gradient border |

#### Section Components
| Component | Description |
|-----------|-------------|
| `LoadingScreen` | Initial loading animation |
| `HeroSection` | Hero with landscape and floating orbs |
| `WorkingHardSection` | "Working hard got easy" with spheres |
| `IntroducingSection` | App UI mockup showcase |
| `WorksWaySection` | Floating cards with gold sphere |
| `FeatureCardsSection` | Horizontal feature cards |
| `FeatureTextSection` | Text-only feature descriptions |
| `BuiltDifferentSection` | Light theme with marquee |
| `FocusQuoteSection` | Centered quote |
| `TestimonialSection` | Pill-shaped testimonial |
| `CTASection` | Call to action |
| `FooterSection` | Text mask footer |

#### UI Components
| Component | Props | Description |
|-----------|-------|-------------|
| `AppMockup` | `activeTab` | App interface mockup |
| `FeatureCard` | `title, description, tags, icon` | Feature card |
| `ChatBubble` | `name, message, position` | Collaborative chat bubble |
| `GeometricCard` | `title, description, illustration` | Built different card |

## 4. Animation Implementation Plan

| Interaction | Tech | Implementation |
|-------------|------|----------------|
| Page Load Sequence | Framer Motion | AnimatePresence + staggered children |
| Logo Gradient Border | CSS | Animated gradient background-position |
| Progress Bar Fill | Framer Motion | animate width 0% to 100% |
| Hero Text Reveal | Framer Motion | staggerChildren + y: 20→0, opacity |
| Floating Spheres | CSS Animation | float keyframes with different delays |
| Sphere Glow Pulse | CSS Animation | opacity pulse animation |
| Scroll Reveal | GSAP ScrollTrigger | fade + translateY on scroll |
| Parallax Hero | GSAP ScrollTrigger | backgroundPositionY on scroll |
| Card Hover | Tailwind + Framer | whileHover scale + y offset |
| Button Hover | Tailwind | hover:scale-102 transition |
| Marquee Text | CSS Animation | infinite translateX |
| Tab Switch | Framer Motion | layoutId for active indicator |
| Chat Bubble Pop | Framer Motion | scale 0→1 with spring |
| Text Mask Footer | CSS | background-clip: text |

### Animation Timing Reference

```javascript
// Easing functions
const easings = {
  outExpo: [0.16, 1, 0.3, 1],
  outQuart: [0.25, 1, 0.5, 1],
  inOut: [0.4, 0, 0.2, 1],
};

// Durations
const durations = {
  micro: 0.15,    // 150ms - hovers
  short: 0.3,     // 300ms - state changes
  medium: 0.5,    // 500ms - reveals
  long: 0.8,      // 800ms - sections
  extended: 1.2,  // 1200ms - complex
};

// Stagger delays
const staggers = {
  fast: 0.05,
  normal: 0.1,
  slow: 0.15,
};
```

## 5. Project File Structure

```
/mnt/okcomputer/output/app/
├── public/
│   ├── images/
│   │   ├── hero-landscape.jpg
│   │   ├── sphere-silver.png
│   │   ├── sphere-gold.png
│   │   └── sphere-pearl.png
│   └── fonts/
├── src/
│   ├── components/
│   │   ├── ui/              # shadcn components
│   │   ├── layout/
│   │   │   ├── Navbar.tsx
│   │   │   ├── Section.tsx
│   │   │   └── Container.tsx
│   │   ├── animation/
│   │   │   ├── FloatingSphere.tsx
│   │   │   ├── FadeInView.tsx
│   │   │   ├── TextReveal.tsx
│   │   │   ├── ParallaxImage.tsx
│   │   │   └── GradientBorder.tsx
│   │   └── sections/
│   │       ├── LoadingScreen.tsx
│   │       ├── HeroSection.tsx
│   │       ├── WorkingHardSection.tsx
│   │       ├── IntroducingSection.tsx
│   │       ├── WorksWaySection.tsx
│   │       ├── FeatureCardsSection.tsx
│   │       ├── FeatureTextSection.tsx
│   │       ├── BuiltDifferentSection.tsx
│   │       ├── FocusQuoteSection.tsx
│   │       ├── TestimonialSection.tsx
│   │       ├── CTASection.tsx
│   │       └── FooterSection.tsx
│   ├── hooks/
│   │   ├── useScrollPosition.ts
│   │   └── useInView.ts
│   ├── lib/
│   │   └── utils.ts
│   ├── styles/
│   │   └── globals.css
│   ├── App.tsx
│   ├── main.tsx
│   └── index.html
├── tailwind.config.js
├── vite.config.ts
└── package.json
```

## 6. Package Installation

```bash
# Initialize project
bash /app/.kimi/skills/webapp-building/scripts/init-webapp.sh "Micro"

# Install animation libraries
npm install framer-motion gsap @gsap/react

# Install additional dependencies
npm install lucide-react clsx tailwind-merge
```

## 7. Key Implementation Notes

### Loading Screen Sequence
1. Show black screen
2. Render logo with gradient border animation
3. Animate progress bar 0→100% (2s)
4. Scale down logo, fade out overlay
5. Reveal hero section

### Floating Spheres
- Use absolute positioning
- Apply different animation delays for organic feel
- Use will-change: transform for performance
- Z-index layering for depth

### Scroll-Triggered Animations
- Use GSAP ScrollTrigger for complex scroll animations
- Set trigger points at 20% from bottom of viewport
- Use scrub: 1 for smooth parallax

### Text Mask Footer
- Use CSS background-clip: text
- Background image same as hero
- Large font size (200px+)
- Transparent text color

### Responsive Considerations
- Mobile: Reduce sphere count, simplify animations
- Tablet: Adjust spacing and font sizes
- Desktop: Full experience

## 8. Performance Checklist

- [ ] Use transform/opacity for animations
- [ ] Lazy load images below fold
- [ ] Apply will-change sparingly
- [ ] Respect prefers-reduced-motion
- [ ] Optimize images (WebP format)
- [ ] Use CSS animations where possible
- [ ] Debounce scroll handlers
