import { useRef, useLayoutEffect } from 'react';
import { Button } from '@/components/ui/button';
import { FloatingSphere } from '@/components/animation/FloatingSphere';
import { MagneticElement } from '@/components/animation/MagneticElement';
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';

gsap.registerPlugin(ScrollTrigger);

interface FinalCTASectionProps {
    onBookSandbox: () => void;
}

export function FinalCTASection({ onBookSandbox }: FinalCTASectionProps) {
    const sectionRef = useRef<HTMLDivElement>(null);
    const headlineRef = useRef<HTMLDivElement>(null);
    const taglineRef = useRef<HTMLDivElement>(null);
    const ctaRef = useRef<HTMLDivElement>(null);
    const bgGlowRef = useRef<HTMLDivElement>(null);

    useLayoutEffect(() => {
        const ctx = gsap.context(() => {
            const tl = gsap.timeline({ scrollTrigger: { trigger: sectionRef.current, start: 'top 75%' } });

            tl.from(bgGlowRef.current, { opacity: 0, duration: 0.8 }, 0);
            tl.from(headlineRef.current, { scale: 0.8, opacity: 0, duration: 0.8, ease: 'power3.out' }, 0);
            tl.from(taglineRef.current, { y: 14, opacity: 0, duration: 0.6, ease: 'power2.out' }, 0.3);
            tl.from(ctaRef.current, { y: 14, opacity: 0, scale: 0.9, duration: 0.6, ease: 'power2.out' }, 0.5);
        }, sectionRef);

        return () => ctx.revert();
    }, []);

    return (
        <section ref={sectionRef} className="relative w-full bg-void overflow-hidden py-28 md:py-36">
            <div ref={bgGlowRef} className="absolute inset-0 pointer-events-none">
                <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[500px] h-[500px] rounded-full bg-gradient-to-br from-gold/8 via-teal/4 to-transparent blur-[150px]" />
            </div>

            <FloatingSphere src="/images/sphere_gold.png" size={100} position={{ top: '20%', left: '10%' }} delay={0} duration={5} />
            <FloatingSphere src="/images/sphere_gold.png" size={80} position={{ bottom: '20%', right: '10%' }} delay={0.5} duration={4.5} />

            <div className="relative z-10 flex flex-col items-center justify-center px-6 text-center">
                <div ref={headlineRef} className="will-change-transform">
                    <h2 className="text-3xl md:text-display-sm lg:text-display font-display leading-tight mb-6">
                        <span className="text-ink">You sell. We build.</span>
                        <br />
                        <span className="text-gold">They use it.</span>
                    </h2>
                </div>

                <div ref={taglineRef}>
                    <p className="text-ink-2 text-lg md:text-xl font-light mb-3 text-balance max-w-2xl">
                        Stop hunting for developers. Stop doing fulfillment yourself.
                    </p>
                    <p className="text-ink-3 text-base mb-10">
                        One partnership. Full-cycle delivery. Clients that actually use what we build.
                    </p>
                </div>

                <div ref={ctaRef}>
                    <MagneticElement strength={0.4} radius={120}>
                        <Button
                            onClick={onBookSandbox}
                            variant="gold-pill"
                            className="px-10 py-5 text-base shadow-neu-raised hover:shadow-glow-gold hover:scale-[1.02] transition-all duration-medium"
                        >
                            Book a Discovery Call
                        </Button>
                    </MagneticElement>

                    <p className="text-ink-3 text-sm mt-8">
                        Limited capacity. Only taking on 3-4 new partners per quarter.
                    </p>
                </div>
            </div>
        </section>
    );
}
