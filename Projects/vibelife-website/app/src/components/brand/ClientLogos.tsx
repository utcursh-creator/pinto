/**
 * Client logo components for the marquee showcase.
 * Microsoft, Loom, n8n, Wise use official SVG paths from Simple Icons.
 * Remaining logos use SVG text wordmarks styled to match each brand.
 * All monochrome with currentColor for consistent dark-theme rendering.
 */

interface LogoProps {
  className?: string;
}

// Official SVG path from Simple Icons (simpleicons.org)
export function MicrosoftLogo({ className = '' }: LogoProps) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="currentColor" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Microsoft">
      <path d="M0 0v11.408h11.408V0zm12.594 0v11.408H24V0zM0 12.594V24h11.408V12.594zm12.594 0V24H24V12.594z" />
    </svg>
  );
}

// Official SVG path from Simple Icons
export function WiseLogo({ className = '' }: LogoProps) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="currentColor" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Wise">
      <path d="M6.488 7.469 0 15.05h11.585l1.301-3.576H7.922l3.033-3.507.01-.092L8.993 4.48h8.873l-6.878 18.925h4.706L24 .595H2.543l3.945 6.874Z" />
    </svg>
  );
}

// Official SVG path from Simple Icons
export function N8nLogo({ className = '' }: LogoProps) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="currentColor" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="n8n">
      <path d="M21.4737 5.6842c-1.1772 0-2.1663.8051-2.4468 1.8947h-2.8955c-1.235 0-2.289.893-2.492 2.111l-.1038.623a1.263 1.263 0 0 1-1.246 1.0555H11.289c-.2805-1.0896-1.2696-1.8947-2.4468-1.8947s-2.1663.8051-2.4467 1.8947H4.973c-.2805-1.0896-1.2696-1.8947-2.4468-1.8947C1.1311 9.4737 0 10.6047 0 12s1.131 2.5263 2.5263 2.5263c1.1772 0 2.1663-.8051 2.4468-1.8947h1.4223c.2804 1.0896 1.2696 1.8947 2.4467 1.8947 1.1772 0 2.1663-.8051 2.4468-1.8947h1.0008a1.263 1.263 0 0 1 1.2459 1.0555l.1038.623c.203 1.218 1.257 2.111 2.492 2.111h.3692c.2804 1.0895 1.2696 1.8947 2.4468 1.8947 1.3952 0 2.5263-1.131 2.5263-2.5263s-1.131-2.5263-2.5263-2.5263c-1.1772 0-2.1664.805-2.4468 1.8947h-.3692a1.263 1.263 0 0 1-1.246-1.0555l-.1037-.623A2.52 2.52 0 0 0 13.9607 12a2.52 2.52 0 0 0 .821-1.4794l.1038-.623a1.263 1.263 0 0 1 1.2459-1.0555h2.8955c.2805 1.0896 1.2696 1.8947 2.4468 1.8947 1.3952 0 2.5263-1.131 2.5263-2.5263s-1.131-2.5263-2.5263-2.5263m0 1.2632a1.263 1.263 0 0 1 1.2631 1.2631 1.263 1.263 0 0 1-1.2631 1.2632 1.263 1.263 0 0 1-1.2632-1.2632 1.263 1.263 0 0 1 1.2632-1.2631M2.5263 10.7368A1.263 1.263 0 0 1 3.7895 12a1.263 1.263 0 0 1-1.2632 1.2632A1.263 1.263 0 0 1 1.2632 12a1.263 1.263 0 0 1 1.2631-1.2632m6.3158 0A1.263 1.263 0 0 1 10.1053 12a1.263 1.263 0 0 1-1.2632 1.2632A1.263 1.263 0 0 1 7.579 12a1.263 1.263 0 0 1 1.2632-1.2632m10.1053 3.7895a1.263 1.263 0 0 1 1.2631 1.2632 1.263 1.263 0 0 1-1.2631 1.2631 1.263 1.263 0 0 1-1.2632-1.2631 1.263 1.263 0 0 1 1.2632-1.2632" />
    </svg>
  );
}

// Official SVG path from Simple Icons
export function LoomLogo({ className = '' }: LogoProps) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="currentColor" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Loom">
      <path d="M24 10.665h-7.018l6.078-3.509-1.335-2.312-6.078 3.509 3.508-6.077L16.843.94l-3.508 6.077V0h-2.67v7.018L7.156.94 4.844 2.275l3.509 6.077-6.078-3.508L.94 7.156l6.078 3.509H0v2.67h7.017L.94 16.844l1.335 2.313 6.077-3.508-3.509 6.077 2.312 1.335 3.509-6.078V24h2.67v-7.017l3.508 6.077 2.312-1.335-3.509-6.078 6.078 3.509 1.335-2.313-6.077-3.508h7.017v-2.67H24zm-12 4.966a3.645 3.645 0 1 1 0-7.29 3.645 3.645 0 0 1 0 7.29z" />
    </svg>
  );
}

// Sirion - Spiral circular logo with wordmark
export function SirionLogo({ className = '' }: LogoProps) {
  return (
    <svg className={className} viewBox="0 0 140 32" fill="currentColor" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Sirion">
      {/* Spiral circular icon */}
      <g transform="translate(0, 4)">
        <circle cx="12" cy="12" r="11" fill="none" stroke="currentColor" strokeWidth="2"/>
        <path d="M12 4c4.4 0 8 3.6 8 8s-3.6 8-8 8" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
        <path d="M12 7c2.8 0 5 2.2 5 5s-2.2 5-5 5" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
        <path d="M12 10c1.1 0 2 .9 2 2s-.9 2-2 2" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
      </g>
      <text x="30" y="22" fill="currentColor" fontSize="18" fontFamily="'Segoe UI', system-ui, sans-serif" fontWeight="500" letterSpacing="0.5">sirion</text>
    </svg>
  );
}

// Relevance AI - Overlapping circles forming rounded square shape + wordmark
export function RelevanceAILogo({ className = '' }: LogoProps) {
  return (
    <svg className={className} viewBox="0 0 170 32" fill="currentColor" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Relevance AI">
      {/* Icon: overlapping rounded shapes */}
      <g transform="translate(0, 2)">
        <rect x="2" y="8" width="16" height="16" rx="6" fill="currentColor" opacity="0.4"/>
        <circle cx="16" cy="12" r="9" fill="currentColor" opacity="0.6"/>
        <circle cx="12" cy="8" r="6" fill="currentColor" opacity="0.8"/>
      </g>
      <text x="28" y="22" fill="currentColor" fontSize="16" fontFamily="'Segoe UI', system-ui, sans-serif" fontWeight="500" letterSpacing="-0.3">Relevance AI</text>
    </svg>
  );
}

// BenAI - Smiley face circle icon
export function BenAILogo({ className = '' }: LogoProps) {
  return (
    <svg className={className} viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="BenAI">
      {/* Circle outline */}
      <circle cx="16" cy="16" r="14" stroke="currentColor" strokeWidth="2.5" fill="none"/>
      {/* Smile - U shape arc */}
      <path d="M9 14c0 5 3.5 9 7 9s7-4 7-9" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" fill="none"/>
    </svg>
  );
}

// Neil Patel Digital - Stacked text wordmark
export function NeilPatelLogo({ className = '' }: LogoProps) {
  return (
    <svg className={className} viewBox="0 0 100 32" fill="currentColor" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Neil Patel">
      <text x="0" y="14" fill="currentColor" fontSize="12" fontFamily="'Segoe UI', system-ui, sans-serif" fontWeight="400" letterSpacing="3">NEILPATEL</text>
      <text x="0" y="26" fill="currentColor" fontSize="9" fontFamily="'Segoe UI', system-ui, sans-serif" fontWeight="600" letterSpacing="1.5">DIGITAL INDIA</text>
    </svg>
  );
}

// Text wordmark - upGrad
export function UpGradLogo({ className = '' }: LogoProps) {
  return (
    <svg className={className} viewBox="0 0 110 32" fill="none" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="upGrad">
      <text x="0" y="23" fill="currentColor" fontSize="20" fontFamily="'Segoe UI', system-ui, -apple-system, sans-serif" fontWeight="400" letterSpacing="-0.3">up</text>
      <text x="27" y="23" fill="currentColor" fontSize="20" fontFamily="'Segoe UI', system-ui, -apple-system, sans-serif" fontWeight="700" letterSpacing="-0.3">Grad</text>
    </svg>
  );
}

export const CLIENT_LOGOS = [
  { name: 'Microsoft', component: MicrosoftLogo, type: 'icon' as const },
  { name: 'Wise', component: WiseLogo, type: 'icon' as const },
  { name: 'Loom', component: LoomLogo, type: 'icon' as const },
  { name: 'n8n', component: N8nLogo, type: 'icon' as const },
  { name: 'Relevance AI', component: RelevanceAILogo, type: 'wordmark' as const },
  { name: 'Sirion', component: SirionLogo, type: 'wordmark' as const },
  { name: 'BenAI', component: BenAILogo, type: 'icon' as const },
  { name: 'Neil Patel', component: NeilPatelLogo, type: 'wordmark' as const },
  { name: 'upGrad', component: UpGradLogo, type: 'wordmark' as const },
] as const;
