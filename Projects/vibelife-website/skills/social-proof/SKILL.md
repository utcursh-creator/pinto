# Social Proof & Brand Showcase - Skill Guide

## Purpose
Guidelines for building authoritative client logo showcases, trust bars, and social proof sections on agency/SaaS marketing websites.

## Design Principles

### 1. Logo Wall / Trust Bar
- Use a **horizontal scrolling marquee** or **static grid** of client/partner logos
- Logos should be **monochrome (white or muted)** on dark backgrounds to feel unified
- On hover, logos can reveal brand color or increase opacity for interactivity
- Keep logos at consistent height (24-40px) regardless of aspect ratio
- Minimum 6 logos for credibility; 8-12 is the sweet spot
- Add a subtle label above: "Trusted by", "Built for teams at", "Our clients include"

### 2. Stats Bar
- Show 3-4 key metrics in a horizontal row
- Use large display numbers with small labels underneath
- Animate numbers on scroll-into-view (countUp effect) for engagement
- Keep stats verifiable and specific (not vague)

### 3. Testimonials
- Use real names and titles (not anonymous)
- Include company name and role
- Keep quotes short (1-2 sentences max)
- Use quotation marks or blockquote styling for visual distinction

### 4. Layout Patterns

#### Pattern A: Logo Marquee + Stats + Testimonial (Recommended for agencies)
```
[Label: "Trusted by innovative teams"]
[Logo marquee - infinite scroll animation]
[Stats row: 3-4 metrics]
[Single featured testimonial with attribution]
```

#### Pattern B: Logo Grid + CTA
```
[Headline: "Join 50+ teams who ship faster"]
[3x3 or 4x2 logo grid]
[CTA button]
```

#### Pattern C: Social Proof Strip (minimal)
```
[Inline: "Trusted by" + logo row + "and 40+ more"]
```

### 5. Technical Implementation (React + Tailwind)

#### Infinite Marquee Animation
```css
@keyframes marquee {
  0% { transform: translateX(0); }
  100% { transform: translateX(-50%); }
}
.animate-marquee {
  animation: marquee 30s linear infinite;
}
```

#### Logo Component Pattern
```tsx
// Render logos as inline SVGs for zero network requests
// Use currentColor for monochrome rendering
// Wrap in flex container with consistent gap and alignment
<div className="flex items-center gap-12 opacity-40 hover:opacity-100 transition-opacity">
  {logos.map(logo => <logo.component key={logo.name} className="h-8 w-auto" />)}
</div>
```

### 6. Anti-Patterns to Avoid
- Don't use low-res PNGs for logos (use SVG or high-quality vectors)
- Don't hotlink logos from external CDNs (they break)
- Don't use different colored logos (unify with monochrome)
- Don't use fake/placeholder testimonials
- Don't overload with too many stats (3-4 max)
- Don't use logos without permission (stick to companies you've actually worked with)

### 7. Accessibility
- Add `aria-label` to logo containers: "Companies we've worked with"
- Use `role="img"` and `aria-label` on each SVG logo
- Ensure sufficient contrast for text overlays
- Provide `prefers-reduced-motion` media query for marquee animations

## References
- TailGrids Brand Components: https://tailgrids.com/react/components/brands
- Infinite marquee pattern: CSS-only with `translateX(-50%)` on duplicated content
- Logo monochrome technique: `filter: grayscale(100%) brightness(2)` or inline SVG with `fill="currentColor"`
