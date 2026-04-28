export const SITE_CONFIG = {
  name: 'VibeLife',
  tagline: 'Your expertise is the engine. AI is the multiplier.',
  description: 'We build AI systems around what you already know.',
  copyright: `© ${new Date().getFullYear()} VibeLife Inc. All rights reserved.`,

  // Links
  calendlyUrl: 'https://calendly.com/utkarsh-cashcowlabs/1-1-sessions',
  linkedinUrl: 'https://www.linkedin.com/in/anand-utkarsh-912183248/',
  email: 'utkarsh@cashcowlabs.io',

  // Stats (single source of truth)
  stats: {
    implementations: '50+',
    adoptionRate: '95%',
    reviews: '2,000+',
  },
} as const;
