---
type: reference
date: 2026-03-12
project: vibelife-website
status: active
tags: [brand, design-system, visual-identity, colors, typography, components]
---

# Brand Design System — Forward Deployed AI Partner

This is the definitive design reference for the VibeLife website. Every visual decision traces back to one positioning: **practitioner with depth who operates where the complexity is.**

Full design research at: `Research/design-language-deep-research.md`

---

## The Brand Feeling

When someone lands on this website, they should feel like they've entered a space that was built by someone who thinks about details the way they think about their business. Not flashy. Not generic. Not another SaaS landing page.

The feeling is: **"This person operates at a different level."**

Three emotional layers:
1. **Depth** — Dark, focused, serious. Complex work happens here.
2. **Warmth** — Gold, parchment, grain. A human built this, not a template.
3. **Precision** — Teal accents, monospace data, systematic layout. Every element is intentional.

---

## Color System

### The Palette Story

This isn't a random collection of colors. It's a narrative:

- **Void** enters first — "Something serious happens here."
- **Gold** rewards attention — "Value. Results that earned this."
- **Teal** punctuates with precision — "I see the system clearly."
- **Parchment** holds it together — "Crafted by a human, not generated."

The palette is a **modified complementary** scheme. Gold (~49°) and Teal (~176°) sit 127° apart — strong warm/cool tension without visual aggression. Three warm elements (Gold, Parchment, Void) create home. One cool element (Teal) creates intelligent intervention.

Muted saturation is deliberate. In a 2026 landscape of dopamine-bright colors, going muted says: "I'm not chasing attention. I've already earned it."

### Light Mode

| Token | Hex | RGB | Role |
|-------|-----|-----|------|
| `--bg` | `#EDE8DF` | 237, 232, 223 | Canvas — warm parchment, NOT white. Says "craft over commodity." |
| `--bg2` | `#E6E0D6` | 230, 224, 214 | Slightly recessed canvas for contrast zones |
| `--surface` | `#EEEAE1` | 238, 234, 225 | Elevated surface layer — cards, panels float above this |
| `--panel` | `#F4F0E9` | 244, 240, 233 | Card/panel backgrounds — the primary container |
| `--panel-raised` | `#F8F5EF` | 248, 245, 239 | Hover states, active cards — lightest solid |
| `--ink` | `#18140E` | 24, 20, 14 | Primary text — warm black, NOT pure #000 |
| `--ink-2` | `#3E382E` | 62, 56, 46 | Secondary text — body copy, descriptions |
| `--ink-3` | `#7A7368` | 122, 115, 104 | Muted text — labels, captions, timestamps |
| `--ink-4` | `#B0A89A` | 176, 168, 154 | Disabled text, divider lines, placeholder |
| `--accent` | `#C8B560` | 200, 181, 96 | Gold — primary accent. Use sparingly: CTAs, key metrics, achievement moments. If everything is gold, nothing is gold. |
| `--accent-dim` | `rgba(200,181,96,0.18)` | — | Gold glow behind active elements |
| `--teal` | `#4E9E98` | 78, 158, 152 | Trust + precision — interactive elements, links, data highlights, success states |
| `--green` | `#6A9E7F` | 106, 158, 127 | Sage — positive/success confirmation |
| `--red` | `#C47070` | 196, 112, 112 | Clay — danger/destructive actions, NOT aggressive red |
| `--blue` | `#5E86A8` | 94, 134, 168 | Slate — informational, neutral emphasis |
| `--purple` | `#8B7EC8` | 139, 126, 200 | Lavender — tertiary accent, creative/unique |

### Dark Mode

| Token | Hex | Shift from Light |
|-------|-----|-----------------|
| `--bg` | `#1A1610` | Warm void — amber undertones, NOT cold tech-black. Feels like a room with the lights dimmed, not a server room. |
| `--bg2` | `#151209` | Deep void for recessed areas |
| `--surface` | `#22201A` | Elevated layer |
| `--panel` | `#2C2820` | Card backgrounds |
| `--panel-raised` | `#333028` | Active/hover cards |
| `--ink` | `#F0EAE0` | Primary text — warm white |
| `--ink-2` | `#C8BFB0` | Secondary text |
| `--ink-3` | `#7A7268` | Muted text |
| `--ink-4` | `#4A4540` | Disabled/divider |
| `--accent` | `#D4C068` | Gold — slightly brighter to maintain contrast |
| `--teal` | `#58AAA4` | Teal — slightly brighter |

### Color Usage Rules

**Gold (accent):**
- Reserve for the most important elements: primary CTAs, key stats, achievement indicators
- Gold on dark backgrounds GLOWS — use this for emphasis
- Never use gold for body text or large areas
- Maximum 10-15% of any screen

**Teal:**
- Interactive elements: links, hover states, active indicators
- Data visualization and technical proof points
- Secondary CTAs ("See how it works" vs gold "Start now")
- System status (active, connected, processing)

**Parchment (light bg):**
- The base canvas in light mode — every other color sits on this
- NOT white. This single choice separates the brand from every SaaS template
- Conveys heritage, craft, accumulated knowledge
- Reduces eye fatigue for long reading sessions

**Void (dark bg):**
- Primary mode — dark is the DEFAULT experience, not an afterthought
- Products appear more expensive against black
- Creates focus — eliminates distraction, forces the eye toward content
- The warm undertone prevents "cold tech" feeling

### Semantic Colors

| State | Color | Usage |
|-------|-------|-------|
| Active/Running | `--teal` | Live processes, connected states |
| Success/Complete | `--green` (sage) | Confirmations, completed milestones |
| Warning/Attention | `--accent` (gold) | Important notices, key metrics |
| Error/Danger | `--red` (clay) | Errors, destructive actions — warm, not alarming |
| Info/Neutral | `--blue` (slate) | Tooltips, informational badges |
| Creative/Special | `--purple` (lavender) | Unique features, premium indicators |

---

## Typography System

### The Three Voices

The typography creates three registers that mirror how Utkarsh communicates:

| Font | Weight | Role | Voice | Example |
|------|--------|------|-------|---------|
| **Syne** | 700, 800 | Headlines, declarations, brand mark | Bold conviction — "I have a point of view." | Section headers, hero text, stat values |
| **DM Sans** | 300, 400, 500, 600 | Body text, explanation, UI | Warm precision — "Let me explain it simply." | Paragraphs, descriptions, navigation |
| **DM Mono** | 400, 500 | Technical proof, data, labels | Technical authority — "Here's the evidence." | Stats, tags, timestamps, code |

**Why these fonts:** DM Sans and DM Mono were designed by Colophon Foundry for Google DeepMind — an AI organization. Using them for an AI services brand creates real lineage. Syne was designed for Synesthesie and "integrates a part of surprise in its design process." Together: conviction + clarity + proof.

### Type Scale

| Token | Size | Line Height | Font | Usage |
|-------|------|------------|------|-------|
| `display-xl` | `8rem` (128px) | 0.9 | Syne 800 | Hero statement only — maximum one per page |
| `display-lg` | `6rem` (96px) | 0.9 | Syne 800 | Major section headers |
| `display` | `4.5rem` (72px) | 0.95 | Syne 800 | Section headers |
| `display-sm` | `3.5rem` (56px) | 1.0 | Syne 700 | Sub-section headers |
| `title-xl` | `2.5rem` (40px) | 1.1 | Syne 700 | Card titles, feature headers |
| `title` | `2rem` (32px) | 1.15 | Syne 700 | Component headers |
| `title-sm` | `1.5rem` (24px) | 1.25 | DM Sans 600 | Small titles |
| `body-lg` | `1.125rem` (18px) | 1.7 | DM Sans 400 | Lead paragraphs, descriptions |
| `body` | `1rem` (16px) | 1.7 | DM Sans 400 | Default body text |
| `body-sm` | `0.875rem` (14px) | 1.65 | DM Sans 400 | Compact body, card descriptions |
| `caption` | `0.75rem` (12px) | 1.5 | DM Mono 400 | Labels, tags, timestamps |
| `micro` | `0.625rem` (10px) | 1.4 | DM Mono 400 | Version numbers, fine print |

### Typography Rules

- **Letter spacing:** Syne headlines at `-0.03em`. DM Mono labels at `0.12-0.18em` (tracked wide).
- **Uppercase:** Only DM Mono labels/tags. Never uppercase Syne or DM Sans.
- **Eyebrow pattern:** DM Mono, `0.65rem`, accent color, `0.18em` letter-spacing, uppercase, with a small line before it (`::before` pseudo-element).
- **Highlighted text:** Gold background (`--accent`) with `#18140E` text and `border-radius: 6-8px`. Used for key words in headlines.

---

## Depth System

### Neumorphism — The Craft Signal

Neumorphism says "refined instrument, not generic tool." 64% of users find neumorphic design more premium than flat. But the rule: **10-20% of elements only.** It's a spice, not the dish.

### Shadow Tokens

**Raised (default card state):**
```
Light: 6px 6px 14px rgba(175,165,148,0.52), -4px -4px 10px rgba(255,252,244,0.9)
Dark:  6px 6px 16px rgba(8,6,2,0.92), -4px -4px 10px rgba(60,52,36,0.8)
```

**Inset (pressed state, input fields):**
```
Light: inset 3px 3px 8px rgba(175,165,148,0.52), inset -3px -3px 8px rgba(255,252,244,0.9)
Dark:  inset 3px 3px 9px rgba(8,6,2,0.92), inset -3px -3px 8px rgba(60,52,36,0.8)
```

**Hover (lifted state):**
```
Light: 8px 10px 22px rgba(175,165,148,0.52), -4px -4px 12px rgba(255,252,244,0.9)
Dark:  8px 10px 24px rgba(8,6,2,0.92), -4px -4px 12px rgba(60,52,36,0.8)
```

### Where to Use Neumorphism

| Use | Don't Use |
|-----|-----------|
| Stat cards | Body text areas |
| Action buttons | Navigation menus |
| Toggle switches | Dense form fields |
| Feature cards | Full-width sections |
| Tags and badges | Background containers |
| Progress bars (inset container) | Image galleries |

### Light Source

Consistent across all elements: **top-left.** Light comes from upper-left, shadow falls lower-right. Every neumorphic element must follow this direction. Inconsistent light source breaks the illusion instantly.

---

## Glass Effects

### The Layered Intelligence Signal

Glassmorphism communicates depth — complex systems running beneath a clear interface. "There's depth here, but I'm making it easy for you to see what matters."

### Glass Tokens

**Light mode:**
```css
background: rgba(248, 244, 238, 0.52);
backdrop-filter: blur(16px);
border: 1px solid rgba(255, 255, 255, 0.6);
```

**Dark mode:**
```css
background: rgba(38, 32, 22, 0.58);
backdrop-filter: blur(18px);
border: 1px solid rgba(255, 255, 255, 0.07);
```

### Where to Use Glass

- **Sticky navigation bar** — Floats above content, content visible beneath
- **Overlay cards** on dark motion panels — Key insight cards, video overlays
- **Modal backgrounds** — Creates depth without hard opacity cutoff
- **Floating UI elements** — Tooltips, popovers, dropdown menus

### Where NOT to Use Glass

- Primary content cards (use neumorphic panels instead)
- Body text containers (readability suffers)
- Full-page backgrounds
- Small elements (blur barely visible)

---

## Texture System

### Grain — The Human Signal

In 2026, as AI-generated content floods visual markets, grain is the intentional re-introduction of human touch. It says: "A person made this." It's the visual equivalent of Utkarsh's writing voice — the craft signal.

### Grain Implementation

```
SVG fractalNoise filter:
- baseFrequency: 0.72
- numOctaves: 4
- opacity: 0.035 (light mode) / 0.025 (dark mode)
```

**Rules:**
- Applied as a full-page background overlay, UNDER all content
- Should be FELT, not SEEN. If you can consciously notice the grain, it's too strong.
- Reduces the "too clean / too digital" look
- Adds analog warmth — like film grain in cinema
- Gives gradients and solid colors organic texture

### Vignette

Used on dark motion panels and hero sections:
```css
background: radial-gradient(ellipse at center, transparent 38%, rgba(0,0,0,0.6) 100%);
```
Creates cinematic focus — draws the eye to center content.

### Ambient Glow

Subtle radial gradient of accent color behind key elements:
```css
background: radial-gradient(ellipse, rgba(200,181,96,0.09) 0%, transparent 70%);
```
Creates warm presence without visible shape. The viewer feels the warmth without seeing the source.

---

## Border Radius

| Token | Value | Usage |
|-------|-------|-------|
| `--radius-lg` | `22px` | Panels, windows, motion panels, modals |
| `--radius-md` | `14px` | Cards, inputs, swatches, theme chips |
| `--radius-sm` | `9px` | Tags, inner elements, small components |
| `--radius-pill` | `99px` | Buttons, badges, progress bars, toggles |

**Philosophy:** Rounded = approachable. The generous radii soften the dark/premium aesthetic into something that feels inviting, not intimidating. This is "Palantir's authority + a craftsman's warmth."

---

## Motion System

### Philosophy

Motion should feel like the interface is alive but calm. Not performative. Not attention-seeking. Like the brand itself — confident enough to move slowly.

### Timing

| Duration | Value | Usage |
|----------|-------|-------|
| Micro | `0.12-0.15s` | Hover states, button feedback |
| Short | `0.28-0.3s` | Toggle animations, state changes |
| Medium | `0.4-0.45s` | Section reveals, theme transitions |
| Long | `0.7-0.8s` | Complex entrances, parallax |

### Easings

| Name | Value | Usage |
|------|-------|-------|
| Default | `ease` | Most transitions |
| Bounce | `cubic-bezier(.4,0,.2,1)` | Toggle thumb, playful interactions |
| Smooth out | `ease-out` | Exit animations |

### Entry Animations

- **Section entrance:** `translateY(14px) → 0` with `0.45s ease`, staggered at 60ms between siblings
- **Card hover:** `translateY(-3px)` with expanded shadow
- **Button press:** Swap raised shadow to inset shadow (physical press feel)
- **Theme toggle:** `0.4s` transition on all background/color properties

### Continuous Animations

- **Floating spheres:** `translateY(0) → translateY(-20px) → translateY(0)` at 4-6s per cycle
- **Pulse glow:** `opacity 0.35 → 1 → 0.35` at 1.4s per cycle
- **Progress stripe:** `background-position shift` at 0.7s linear infinite
- **Marquee:** `translateX(0) → translateX(-50%)` at 20s linear infinite

### Accent Gradient Bar

Top edge of dark panels — a thin 3px gradient that signals premium:
```css
background: linear-gradient(90deg, var(--accent) 0%, var(--teal) 55%, var(--purple) 100%);
```
Gold → Teal → Lavender. Warm to cool. Authority to precision to creativity.

---

## Component Patterns

### Cards

**Standard Card (neumorphic):**
- Background: `--panel`
- Border-radius: `--radius-md` (14px)
- Shadow: raised neumorphic
- Hover: lift -3px + deeper shadow
- Padding: 18-22px
- Optional: color tint via `::before` pseudo-element with radial gradient at 13% opacity

**Glass Card (on dark backgrounds):**
- Background: `rgba(255,255,255,0.07)`
- Backdrop-filter: `blur(14px)`
- Border: `1px solid rgba(255,255,255,0.12)`
- Border-radius: 18px
- Shadow: `0 8px 32px rgba(0,0,0,0.3), inset 0 1px 0 rgba(255,255,255,0.1)`

**Active Card (selected state):**
- Left border: 3px gold accent line
- Inner glow: `inset 0 0 24px var(--accent-dim)`

### Buttons

**Primary (gold accent):**
- Background: `--accent`
- Text: `#18140E` (ink on gold)
- Shape: pill (`99px` radius)
- Font: DM Mono, 0.74rem, 500
- Shadow: gold-tinted (`rgba(140,110,30,0.4)`)
- Hover: lift -2px + deeper gold shadow

**Ghost (secondary):**
- Background: `--panel`
- Text: `--ink-2`
- Shadow: raised neumorphic
- Hover: lift -2px + deeper neumorphic shadow
- Active: swap to inset shadow (press feel)

**Teal (tertiary/action):**
- Background: `--teal`
- Text: white
- Shadow: teal-tinted

**Ink (dark/contrast):**
- Background: `--ink`
- Text: `--bg`
- Shadow: raised neumorphic

### Tags / Badges

- Shape: pill (`99px` radius)
- Font: DM Mono, 0.6rem
- Padding: 3px 10px
- Background: `--surface`
- Shadow: small neumorphic (`2px 2px 5px shadow, -1px -1px 4px highlight`)
- Colored variants: gold, teal, blue backgrounds with appropriate text colors, no shadow

### Inputs

- Background: `--surface`
- Shadow: inset neumorphic
- Font: DM Mono, 0.76rem
- Border-radius: `--radius-sm` (9px)
- Focus: inset shadow + `0 0 0 2px var(--accent-dim)` ring
- Placeholder: `--ink-4`

### Windows (App-like panels)

- Container: `--panel` background, `--radius-lg` (22px), raised shadow
- Titlebar: `--surface` background, 38px height, bottom border, DM Mono filename
- Body: 22px padding, content area
- Tag in titlebar: DM Mono, `--ink-3`, border-left separator

### Progress Bars

- Container: inset neumorphic shadow, `99px` radius, 11px height
- Fill: gradient `teal → gold`, same radius
- Animated stripe overlay at 14px spacing, 0.7s infinite

### Status Indicators

- Dot: 7px circle, `--teal` background with matching box-shadow glow
- Animation: `pulse` (opacity 1 → 0.35 → 1, 1.4s ease-in-out infinite)
- Label: DM Mono, 0.75rem, teal color

---

## Layout Principles

### Spacing

- Max content width: 900px (focused reading)
- Section margin-bottom: 60px
- Card gaps: 11-12px
- Padding (cards): 17-22px
- Padding (main): 52px top, 24px sides, 100px bottom

### Section Labels

Pattern: DM Mono, 0.62rem, 500 weight, 0.16em letter-spacing, uppercase, `--ink-3` color. Followed by a fading horizontal line (`::after` with gradient from `--ink-4` to transparent at 35% opacity).

Format: `01 — Section Name`

### Grid Patterns

- **Stats:** `grid-template-columns: repeat(auto-fill, minmax(155px, 1fr))`, 12px gap
- **Theme selection:** `grid-template-columns: repeat(auto-fill, minmax(138px, 1fr))`, 12px gap
- **Two-column:** `grid-template-columns: 1fr 1fr`, 18px gap, collapses to single column at 580px
- **Card lists:** `flex-direction: column`, 11px gap

---

## The Palantir Parallel

This brand's visual language should feel like **Palantir's authority + a craftsman's warmth:**

| Palantir DNA | Our Warmth Layer |
|-------------|-----------------|
| Dark interfaces | Warm void (#1A1610), not cold black |
| Data-dense layouts | Information presented with breathing room |
| Mission control precision | Gold and grain add human craft |
| Blueprint systematic consistency | Neumorphic depth adds tactility |
| Technical competence | DM Mono proves, DM Sans explains |

The target: open this website and feel like opening a precision instrument built by someone who understands your problem deeply. Not a SaaS tool. Not a consulting deck. A **crafted system** designed by a practitioner.

---

## What the Current Codebase Needs

### Design Token Mismatches

The app currently uses a different color system than the brand theme:

| Element | Current App | Brand Theme | Action |
|---------|-------------|-------------|--------|
| Background | `#0a0a0a` (cold void) | `#1A1610` (warm void) | Replace — warm undertone is critical |
| Gold accent | `#d4a574` (copper) | `#C8B560` (true gold) | Replace — copper reads as "earthy", gold reads as "valuable" |
| Body font | Inter | DM Sans | Replace — DM Sans has DeepMind lineage |
| Display font | Instrument Serif | Syne | Replace — Syne carries conviction |
| Mono font | JetBrains Mono | DM Mono | Replace — stays in the DM family |
| Light bg | `#f5f5f0` (generic cream) | `#EDE8DF` (warm parchment) | Replace — parchment has more warmth and character |
| Neumorphism | None | Neumorphic shadows on cards/buttons | Add — currently flat design throughout |
| Grain texture | Has `grain-overlay` class | SVG fractalNoise at 3.5% | Verify implementation matches |
| Glass | Has `.glass` utility | Full glass system with mode-specific values | Align with brand tokens |

### What's Already Aligned

- Dark mode as primary ✓
- Teal accent color (close match) ✓
- Smooth scroll (Lenis) ✓
- GSAP ScrollTrigger animations ✓
- Framer Motion page transitions ✓
- Grain overlay concept ✓
- Glass utility concept ✓
- Pill-shaped buttons ✓
- DM Mono is already in the current tailwind config ✓

---

## Quick Reference: The Brand in One Sentence

**"Palantir's depth and precision, wrapped in the warmth and craft of someone who builds by hand."**

Dark. Gold. Grain. Glass. Neumorphic. Warm. Precise. Human.
