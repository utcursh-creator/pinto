import { Link } from 'react-router-dom';
import { Linkedin, Mail } from 'lucide-react';
import { SITE_CONFIG } from '@/config/site';

export function FooterSection() {
  return (
    <footer className="relative w-full bg-charcoal border-t border-ink-disabled/25">
      <div className="accent-bar w-full" />

      <div className="max-w-7xl mx-auto px-6 py-14">
        <div className="grid grid-cols-2 md:grid-cols-4 gap-8 md:gap-12">
          {/* Brand */}
          <div className="col-span-2 md:col-span-1">
            <Link to="/" className="inline-block">
              <h3 className="text-2xl font-display mb-4">
                <span className="text-gold">
                  {SITE_CONFIG.name}
                </span>
              </h3>
            </Link>
            <p className="text-ink-2 text-sm leading-relaxed">
              {SITE_CONFIG.description}
              <br />
              <span className="text-gold/80">{SITE_CONFIG.tagline}</span>
            </p>
          </div>

          {/* Pages */}
          <div>
            <h4 className="section-label mb-5">Explore</h4>
            <div className="space-y-2.5">
              <Link to="/how-it-works" className="block text-ink-3 hover:text-gold transition-colors duration-short text-sm">
                How It Works
              </Link>
              <Link to="/work" className="block text-ink-3 hover:text-gold transition-colors duration-short text-sm">
                What We Build
              </Link>
              <Link to="/resources" className="block text-ink-3 hover:text-gold transition-colors duration-short text-sm">
                Resources
              </Link>
            </div>
          </div>

          {/* Topics */}
          <div>
            <h4 className="section-label mb-5">Topics</h4>
            <div className="space-y-2.5">
              <span className="block text-ink-3 text-sm">AI Integration</span>
              <span className="block text-ink-3 text-sm">Domain Expertise</span>
              <span className="block text-ink-3 text-sm">Adoption & Training</span>
            </div>
          </div>

          {/* Contact */}
          <div>
            <h4 className="section-label mb-5">Connect</h4>
            <div className="space-y-3">
              <a
                href={SITE_CONFIG.linkedinUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-2 text-ink-3 hover:text-teal transition-colors duration-short text-sm"
              >
                <Linkedin className="w-4 h-4" />
                <span>LinkedIn</span>
              </a>
              <a
                href={`mailto:${SITE_CONFIG.email}`}
                className="flex items-center gap-2 text-ink-3 hover:text-gold transition-colors duration-short text-sm"
              >
                <Mail className="w-4 h-4" />
                <span>{SITE_CONFIG.email}</span>
              </a>
              <a
                href={SITE_CONFIG.calendlyUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="block text-gold hover:text-gold-light transition-colors duration-short text-sm font-medium mt-5"
              >
                Book a Discovery Call
              </a>
            </div>
          </div>
        </div>

        <div className="mt-14 pt-8 border-t border-ink-disabled/25 flex flex-col md:flex-row justify-between items-center gap-4">
          <p className="text-ink-3 text-xs">
            {SITE_CONFIG.copyright}
          </p>
          <div className="flex gap-6 text-xs text-ink-disabled">
            <span className="cursor-default">Privacy</span>
            <span className="cursor-default">Terms</span>
          </div>
        </div>
      </div>
    </footer>
  );
}
