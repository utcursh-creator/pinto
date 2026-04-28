import { useRef, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { ArrowRight } from 'lucide-react';
import gsap from 'gsap';
import { GradientMesh } from '@/components/effects/AtmosphericEffects';

interface NewHeroSectionProps {
    onBookSandbox: () => void;
}

export function NewHeroSection({ onBookSandbox }: NewHeroSectionProps) {
    const sectionRef = useRef<HTMLDivElement>(null);
    const headlineRef = useRef<HTMLDivElement>(null);
    const subheadRef = useRef<HTMLDivElement>(null);
    const ctaRef = useRef<HTMLDivElement>(null);
    const eyebrowRef = useRef<HTMLDivElement>(null);
    const orbRef = useRef<HTMLDivElement>(null);

    useEffect(() => {
        if (!sectionRef.current) return;

        const ctx = gsap.context(() => {
            const tl = gsap.timeline({ delay: 0.3 });

            if (eyebrowRef.current) {
                tl.from(eyebrowRef.current, {
                    y: 14,
                    opacity: 0,
                    duration: 0.6,
                    ease: 'power3.out',
                }, 0);
            }

            if (headlineRef.current) {
                tl.from(headlineRef.current, {
                    y: 14,
                    opacity: 0,
                    duration: 0.8,
                    ease: 'power3.out',
                }, 0.15);
            }

            if (subheadRef.current) {
                tl.from(subheadRef.current, {
                    y: 14,
                    opacity: 0,
                    duration: 0.6,
                    ease: 'power2.out',
                }, 0.5);
            }

            if (orbRef.current) {
                tl.from(orbRef.current, {
                    scale: 0,
                    opacity: 0,
                    duration: 0.8,
                    ease: 'power2.out',
                }, 0.5);
            }

            if (ctaRef.current) {
                tl.from(ctaRef.current, {
                    y: 14,
                    opacity: 0,
                    duration: 0.5,
                    ease: 'power2.out',
                }, 0.7);
            }

        }, sectionRef);

        return () => ctx.revert();
    }, []);

    return (
        <section ref={sectionRef} className="relative w-full bg-void overflow-hidden">
            <GradientMesh />

            <div
                ref={orbRef}
                className="absolute top-[30%] left-1/2 -translate-x-1/2 -translate-y-1/2 w-[600px] h-[600px] pointer-events-none z-0 hidden md:block"
            >
                <div className="w-full h-full rounded-full bg-gradient-to-br from-gold/10 via-teal/6 to-transparent blur-[100px]" />
            </div>

            <div className="relative z-10 flex flex-col items-center pt-40 md:pt-48 pb-28">
                <div className="w-full max-w-4xl mx-auto px-6 lg:px-8">

                    <div ref={eyebrowRef} className="flex items-center justify-center gap-4 mb-8">
                        <div className="h-px w-8 bg-ink-3/50" />
                        <span className="section-label">
                            For AI Automation Businesses
                        </span>
                        <div className="h-px w-8 bg-ink-3/50" />
                    </div>

                    <div ref={headlineRef} className="text-center mb-8">
                        <h1 className="text-3xl md:text-display-sm lg:text-display font-display leading-tight tracking-tight text-ink">
                            We cleared 5 projects for one business in 21 days and they never touched fulfillment again
                        </h1>
                    </div>

                    <div ref={subheadRef} className="text-center mb-12">
                        <p className="text-lg md:text-xl text-ink-2 font-light max-w-2xl mx-auto leading-relaxed">
                            If you're stuck building everything yourself we should probably talk
                        </p>
                    </div>

                    <div ref={ctaRef} className="flex flex-col sm:flex-row items-center justify-center gap-4">
                        <Button
                            onClick={onBookSandbox}
                            variant="gold-pill"
                            className="group relative px-8 py-6 text-base overflow-hidden hover:scale-[1.02] hover:shadow-glow-gold"
                        >
                            <span className="relative z-10 flex items-center gap-2">
                                Book a Discovery Call
                                <ArrowRight className="w-4 h-4 transition-transform duration-short group-hover:translate-x-1" />
                            </span>
                        </Button>

                        <a
                            href="#proof"
                            className="group flex items-center gap-2 px-6 py-4 text-ink-3 hover:text-ink-2 transition-colors duration-short text-sm font-mono"
                        >
                            See the track record
                            <ArrowRight className="w-3.5 h-3.5 transition-transform duration-short group-hover:translate-x-1" />
                        </a>
                    </div>

                </div>
            </div>
        </section>
    );
}
