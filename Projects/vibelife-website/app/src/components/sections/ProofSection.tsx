import { useRef, useLayoutEffect } from 'react';
import { Star, Users, TrendingUp, Award } from 'lucide-react';
import { SITE_CONFIG } from '@/config/site';
import { CLIENT_LOGOS } from '@/components/brand/ClientLogos';
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';

gsap.registerPlugin(ScrollTrigger);

const stats = [
    { value: SITE_CONFIG.stats.implementations, label: 'Projects Delivered', icon: TrendingUp, colorClass: 'text-teal' },
    { value: SITE_CONFIG.stats.adoptionRate, label: 'Client Retention', icon: Users, colorClass: 'text-gold' },
    { value: SITE_CONFIG.stats.reviews, label: 'Reviews Across Platforms', icon: Star, colorClass: 'text-coral' },
    { value: '3 weeks', label: 'Avg Time to First Delivery', icon: Award, colorClass: 'text-teal' },
];

function LogoMarquee() {
    return (
        <div className="relative overflow-hidden py-8" aria-label="Companies we've worked with">
            <div className="absolute left-0 top-0 bottom-0 w-24 bg-gradient-to-r from-charcoal to-transparent z-10 pointer-events-none" />
            <div className="absolute right-0 top-0 bottom-0 w-24 bg-gradient-to-l from-charcoal to-transparent z-10 pointer-events-none" />

            <div className="flex animate-marquee whitespace-nowrap">
                {[...CLIENT_LOGOS, ...CLIENT_LOGOS].map((logo, i) => (
                    <div
                        key={`${logo.name}-${i}`}
                        className="flex-shrink-0 mx-8 md:mx-12 flex items-center gap-2.5 text-ink-3 hover:text-ink-2 transition-all duration-medium"
                    >
                        <logo.component className={logo.type === 'icon' ? 'h-6 md:h-7 w-auto' : 'h-7 md:h-8 w-auto'} />
                        {logo.type === 'icon' && (
                            <span className="text-sm md:text-base font-medium tracking-tight">{logo.name}</span>
                        )}
                    </div>
                ))}
            </div>
        </div>
    );
}

export function ProofSection() {
    const sectionRef = useRef<HTMLDivElement>(null);
    const headerRef = useRef<HTMLDivElement>(null);
    const testimonialRef = useRef<HTMLDivElement>(null);

    useLayoutEffect(() => {
        const ctx = gsap.context(() => {
            gsap.from(headerRef.current, {
                y: 14,
                opacity: 0,
                duration: 0.7,
                ease: 'power2.out',
                scrollTrigger: {
                    trigger: sectionRef.current,
                    start: 'top 80%',
                }
            });

            gsap.utils.toArray('.stat-card').forEach((card: any, i: number) => {
                gsap.from(card, {
                    y: 14,
                    opacity: 0,
                    scale: 0.95,
                    duration: 0.6,
                    ease: 'power2.out',
                    delay: i * 0.1,
                    scrollTrigger: {
                        trigger: card,
                        start: 'top 88%',
                    }
                });
            });

            gsap.from(testimonialRef.current, {
                y: 14,
                opacity: 0,
                duration: 0.8,
                ease: 'power2.out',
                scrollTrigger: {
                    trigger: testimonialRef.current,
                    start: 'top 85%',
                }
            });
        }, sectionRef);

        return () => ctx.revert();
    }, []);

    return (
        <section ref={sectionRef} className="relative py-24 bg-charcoal overflow-hidden">
            <div className="absolute inset-0 bg-gradient-to-b from-void/50 to-transparent" />

            <div className="relative z-10 max-w-6xl mx-auto px-6">
                <div ref={headerRef} className="text-center mb-12">
                    <p className="section-label mb-5">
                        Track Record
                    </p>
                    <h2 className="text-display-sm md:text-display font-display text-ink text-balance">
                        Trusted by <span className="text-gold">AI businesses that ship</span>
                    </h2>
                </div>

                <div className="mb-14">
                    <p className="text-center section-label mb-4">
                        Built for teams at
                    </p>
                    <LogoMarquee />
                </div>

                <div className="grid grid-cols-2 lg:grid-cols-4 gap-6 mb-16">
                    {stats.map((stat, index) => (
                        <div
                            key={index}
                            className="stat-card relative p-6 rounded-md bg-charcoal-light shadow-neu-raised hover:shadow-neu-hover transition-all duration-medium group hover:-translate-y-[3px]"
                        >
                            <stat.icon className={`w-5 h-5 ${stat.colorClass} mb-4 opacity-60 group-hover:opacity-100 transition-opacity duration-short`} />
                            <p className="text-3xl md:text-4xl font-display text-ink mb-1">{stat.value}</p>
                            <p className="text-ink-2 text-sm">{stat.label}</p>
                        </div>
                    ))}
                </div>

                <div ref={testimonialRef} className="max-w-3xl mx-auto text-center">
                    <div className="relative">
                        <span className="absolute -top-4 -left-2 text-6xl text-gold/8 font-serif">"</span>
                        <blockquote className="text-xl md:text-2xl text-ink font-light leading-relaxed italic px-8">
                            We had 6 projects sitting in our backlog for months. They cleared them in 3 weeks and our clients never even knew we had a partner.
                            <span className="text-gold not-italic font-medium"> That's the whole point.</span>
                        </blockquote>
                        <span className="absolute -bottom-8 -right-2 text-6xl text-gold/8 font-serif rotate-180">"</span>
                    </div>
                    <div className="mt-8 pt-6 border-t border-ink-disabled/20">
                        <p className="text-ink-2 text-sm">Agency Owner</p>
                        <p className="text-gold text-sm font-medium">AI Automation Business, $25K MRR</p>
                    </div>
                </div>
            </div>
        </section>
    );
}
