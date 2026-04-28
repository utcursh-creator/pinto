---
description: VibeLife specific design guidelines and aesthetic direction
---

# VibeLife Design Guidelines

## Brand Aesthetic Direction

**Tone**: Luxury/refined meets editorial/magazine with subtle retro-futuristic influences.

**Core Palette**:
- **Void** (#0a0a0a) - Deep black background
- **Charcoal** (#1a1a1a) - Secondary dark surfaces  
- **Gold** (#CDAF7E) - Primary accent, luxury feel
- **Teal** (#4DA6A6) - Secondary accent, trust/tech
- **Coral** (#E07A5F) - Tertiary accent, warmth

**Typography**:
- Display: Use distinctive, premium fonts (not generic Inter/Roboto)
- Body: Clean, readable but characterful

## What Makes VibeLife Unforgettable

1. **The Forward Deployed Dev Team** concept - embedded partner, not freelancer
2. **"You sell. I build. They use it."** - simple, memorable promise  
3. **Adoption over delivery** - the key differentiator
4. **30-Day Sandbox** - low-risk entry point

## Design Principles

### DO:
- Use generous negative space
- Create atmosphere with subtle gradients and floating spheres
- Apply staggered reveal animations on scroll
- Use glassmorphism sparingly for depth
- Implement smooth, spring-based physics for interactions
- Create unexpected layouts with asymmetry

### DON'T:
- Use stock photography or generic AI images
- Use cliched tech gradients (purple/blue on white)
- Create predictable 3-column layouts
- Use generic icons without context
- Ignore mobile-first responsive design

## Motion Guidelines

- **Page transitions**: Smooth, subtle fades
- **Scroll reveals**: Staggered animations with `animation-delay`
- **Hover states**: Scale transforms with spring physics
- **Loading states**: Skeleton screens, not spinners
- **Micro-interactions**: Only where they add meaning

## Component Patterns

### Hero Sections
- Full viewport height
- Bold headline with gradient text
- Subtle floating background elements
- Clear CTA with hover animation

### Cards
- Glassmorphism borders (border-white/10)
- Subtle hover lift effects
- Consistent rounded corners (rounded-2xl or rounded-3xl)
- Backdrop blur where appropriate

### CTAs
- Primary: Gold gradient with dark text
- Secondary: Outlined with gold/teal border
- Always include directional icon (ArrowRight)
- Hover scale + color shift

## Current Issues to Fix

Based on the skill guidelines, check for:
- [ ] Generic font usage (Inter?)
- [ ] Predictable layout patterns
- [ ] Missing animation polish
- [ ] Inconsistent spacing
- [ ] Weak visual hierarchy
- [ ] Missing atmospheric backgrounds
- [ ] Generic icon usage
