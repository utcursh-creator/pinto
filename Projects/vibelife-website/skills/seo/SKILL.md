# Technical SEO for React SPA (Vite) - Skill Guide

> Sources: awesome-cursorrules, cursor.directory, React SPA SEO best practices 2025-2026, Google structured data guidelines, vite-plugin-react-meta-map

## 1. The React SPA SEO Challenge

React SPAs render on the client. The initial HTML is just `<div id="root"></div>`. Search engines may not see content. This skill covers how to maximize SEO without switching to Next.js/SSR.

### Mitigation Strategies for Vite + React
1. **Pre-rendering at build time** using `vite-plugin-react-meta-map` or `vite-plugin-prerender`
2. **Dynamic meta tags** via `react-helmet-async` for client-side updates
3. **Static HTML generation** for key landing/pillar pages
4. **Comprehensive `index.html`** with default SEO tags as fallback
5. **Sitemap + robots.txt** generated at build time

## 2. Meta Tags - Per Page Requirements

Every route MUST have unique:

```html
<title>{Page Title} | {Brand Name}</title>
<meta name="description" content="{unique 150-160 char description}" />
<link rel="canonical" href="https://vibelife.io{pathname}" />

<!-- Open Graph -->
<meta property="og:title" content="{title}" />
<meta property="og:description" content="{description}" />
<meta property="og:image" content="{absolute URL to image}" />
<meta property="og:url" content="{canonical URL}" />
<meta property="og:type" content="website" />
<meta property="og:site_name" content="{Brand Name}" />

<!-- Twitter Card -->
<meta name="twitter:card" content="summary_large_image" />
<meta name="twitter:title" content="{title}" />
<meta name="twitter:description" content="{description}" />
<meta name="twitter:image" content="{absolute URL to image}" />
```

### Implementation Pattern (react-helmet-async)
```tsx
import { Helmet } from 'react-helmet-async';

function SEOHead({ title, description, path, image }: SEOProps) {
  const url = `https://vibelife.io${path}`;
  const fullTitle = `${title} | VibeLife`;
  return (
    <Helmet>
      <title>{fullTitle}</title>
      <meta name="description" content={description} />
      <link rel="canonical" href={url} />
      <meta property="og:title" content={fullTitle} />
      <meta property="og:description" content={description} />
      <meta property="og:url" content={url} />
      <meta property="og:image" content={image || 'https://vibelife.io/images/og-image.jpg'} />
      <meta property="og:type" content="website" />
      <meta name="twitter:card" content="summary_large_image" />
    </Helmet>
  );
}
```

## 3. Structured Data (JSON-LD Schema Markup)

### Organization Schema (site-wide, in index.html)
```json
{
  "@context": "https://schema.org",
  "@type": "Organization",
  "name": "VibeLife",
  "url": "https://vibelife.io",
  "logo": "https://vibelife.io/favicon.svg",
  "description": "Forward Deployed Dev Team for AI Automation Agencies",
  "sameAs": ["https://linkedin.com/in/anand-utkarsh-912183248/"],
  "contactPoint": {
    "@type": "ContactPoint",
    "email": "utkarsh@cashcowlabs.io",
    "contactType": "sales"
  }
}
```

### Service Schema (on service pages)
```json
{
  "@context": "https://schema.org",
  "@type": "Service",
  "name": "AI Automation Fulfillment",
  "provider": { "@type": "Organization", "name": "VibeLife" },
  "description": "Forward Deployed Dev Team that handles entire fulfillment cycle for AI automation agencies",
  "areaServed": ["US", "UK", "AU", "CA"],
  "serviceType": "AI Automation Development & Adoption"
}
```

### FAQ Schema (on pages with FAQ sections)
```json
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "What is a Forward Deployed Dev Team?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "An embedded engineering team that handles client communications, development, deployment, support, adoption, and education end-to-end."
      }
    }
  ]
}
```

### Article Schema (on blog posts)
```json
{
  "@context": "https://schema.org",
  "@type": "Article",
  "headline": "{title}",
  "datePublished": "{ISO date}",
  "author": { "@type": "Person", "name": "{author}" },
  "publisher": { "@type": "Organization", "name": "VibeLife" },
  "image": "{image URL}",
  "description": "{excerpt}"
}
```

### BreadcrumbList Schema (on all inner pages)
```json
{
  "@context": "https://schema.org",
  "@type": "BreadcrumbList",
  "itemListElement": [
    { "@type": "ListItem", "position": 1, "name": "Home", "item": "https://vibelife.io/" },
    { "@type": "ListItem", "position": 2, "name": "Services", "item": "https://vibelife.io/services" },
    { "@type": "ListItem", "position": 3, "name": "AI Automation Fulfillment" }
  ]
}
```

## 4. URL Structure Best Practices

```
/                                    → Homepage (pillar)
/services                           → Services overview (pillar)
/services/ai-automation-fulfillment  → Category page
/services/workflow-automation        → Category page
/services/automation-adoption        → Category page
/how-it-works                       → Process page
/resources                          → Blog hub
/resources/{slug}                   → Individual blog post
/case-studies                       → Case studies hub
/case-studies/{slug}                → Individual case study
/compare/{competitor}               → Comparison pages
```

### URL Rules
- Use lowercase, hyphenated slugs
- Keep URLs under 75 characters
- Include target keyword in the URL
- Use REAL `<a href>` tags, not onClick handlers
- Avoid hash-only navigation (`/#section`) for important indexable content
- Use React Router `<Link>` for internal navigation

## 5. Heading Hierarchy

Every page MUST follow:
```
<h1> — One per page, contains primary keyword
  <h2> — Section headings (3-6 per page)
    <h3> — Sub-sections within h2
      <h4> — Details within h3 (use sparingly)
```

### Rules
- Only ONE `<h1>` per page
- `<h1>` should contain the primary target keyword
- Never skip heading levels (h1 → h3 is wrong)
- Don't use headings for styling, use CSS classes
- Navbar brand should be `<span>` not `<h1>`

## 6. Internal Linking Strategy

### Pillar-Cluster Model
```
Homepage ←→ Services (pillar)
                ├── AI Automation Fulfillment (cluster)
                ├── Workflow Automation (cluster)
                ├── Adoption & Training (cluster)
                ├── Documentation & SOPs (cluster)
                └── Ongoing Support (cluster)

Homepage ←→ Resources (pillar)
                ├── Blog Post 1 (cluster)
                ├── Blog Post 2 (cluster)
                └── ...

Homepage ←→ Case Studies (pillar)
                ├── Case Study 1 (cluster)
                └── ...
```

### Rules
- Every page should have 3-5 internal links to related pages
- Use descriptive anchor text (not "click here")
- Pillar pages link to all cluster pages
- Cluster pages link back to pillar page
- Blog posts link to relevant service pages
- Footer and nav provide site-wide internal links

## 7. Image SEO

```tsx
<img
  src="/images/hero.webp"
  alt="AI automation workflow dashboard showing client onboarding process"
  width={1200}
  height={630}
  loading="lazy"           // below-the-fold images
  decoding="async"         // non-blocking decode
/>
```

### Rules
- Use descriptive alt text with keywords (not "image1.jpg")
- Use WebP or AVIF format
- Specify width/height to prevent CLS
- Lazy load below-fold images
- Use `loading="eager"` for above-fold hero images
- Keep file sizes under 200KB for hero, under 100KB for thumbnails

## 8. Sitemap & Robots.txt

### robots.txt (in /public/)
```
User-agent: *
Allow: /
Disallow: /api/

Sitemap: https://vibelife.io/sitemap.xml
```

### Sitemap Generation
Create a build script that generates `sitemap.xml` from routes:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>https://vibelife.io/</loc>
    <changefreq>weekly</changefreq>
    <priority>1.0</priority>
  </url>
  <url>
    <loc>https://vibelife.io/services</loc>
    <changefreq>monthly</changefreq>
    <priority>0.9</priority>
  </url>
  <!-- ... all routes -->
</urlset>
```

## 9. React SPA-Specific SEO Checklist

- [ ] `react-helmet-async` installed and wrapping App with `HelmetProvider`
- [ ] Every route has unique `<title>`, `<meta description>`, `<link canonical>`
- [ ] Open Graph + Twitter Card tags on all pages
- [ ] JSON-LD structured data (Organization, Service, Article, FAQ, Breadcrumb)
- [ ] `sitemap.xml` generated at build time in `/public/`
- [ ] `robots.txt` in `/public/`
- [ ] All links use `<a href>` or React Router `<Link>`, not onClick
- [ ] Clean URL structure with descriptive slugs
- [ ] One `<h1>` per page with target keyword
- [ ] Proper heading hierarchy (h1 > h2 > h3)
- [ ] Images have descriptive alt text, width/height, lazy loading
- [ ] No duplicate title/description across pages
- [ ] 404 page exists and returns appropriate messaging
- [ ] Internal linking between related pages (3-5 links per page)
- [ ] No orphan pages (every page reachable from nav or internal links)

## 10. Keyword Mapping for VibeLife

| Page | Primary Keyword | Secondary Keywords |
|------|----------------|-------------------|
| Homepage | AI automation fulfillment partner | white-label AI automation, agency fulfillment |
| Services | AI automation services for agencies | automation development, deployment, support |
| AI Automation Fulfillment | AI automation fulfillment | white-label automation development, outsource AI builds |
| Workflow Automation | n8n automation services, Make.com automation | workflow automation agency, no-code automation |
| Adoption & Training | automation adoption framework | client training automation, adoption support |
| Documentation | automation documentation service | SOP creation, video documentation automation |
| Ongoing Support | managed automation services | automation support retainer, ongoing maintenance |
| How It Works | forward deployed dev team | embedded engineering team, fulfillment process |
| Resources | AI automation blog | automation playbook, agency scaling tips |
| Case Studies | AI automation case studies | automation ROI, client success stories |

## References
- [awesome-cursorrules](https://github.com/PatrickJS/awesome-cursorrules) - Next.js 14 + Tailwind + SEO rules
- [cursor.directory](https://cursor.directory) - React + TypeScript rules
- [vite-plugin-react-meta-map](https://github.com/dqhendricks/vite-plugin-react-meta-map) - Vite SPA meta tags
- [React SPA SEO Best Practices](https://www.dheemanthshenoy.com/blogs/react-seo-best-practices-spa)
- [Technical SEO for React Sites 2026](https://seo4growth.com/technical-seo-audit-checklist-react/)
- [Strapi SEO Checklist for Developers](https://strapi.io/blog/seo-checklist-for-developers)
