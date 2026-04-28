import { useRef, useLayoutEffect } from 'react';
import { FloatingSphere } from '@/components/animation/FloatingSphere';
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';

gsap.registerPlugin(ScrollTrigger);

export function ProblemSection() {
    const sectionRef = useRef<HTMLDivElement>(null);
    const line1Ref = useRef<HTMLSpanElement>(null);
    const line2Ref = useRef<HTMLSpanElement>(null);
    const insightRef = useRef<HTMLDivElement>(null);
    const bgGlowRef = useRef<HTMLDivElement>(null);

    useLayoutEffect(() => {
        const ctx = gsap.context(() => {
            const tl = gsap.timeline({
                scrollTrigger: { trigger: sectionRef.current, start: 'top 75%' }
            });

            tl.from('.problem-label', { opacity: 0, y: 14, duration: 0.4, ease: 'power2.out' }, 0);
            tl.from(line1Ref.current, { y: 14, opacity: 0, scale: 0.9, duration: 0.7, ease: 'power3.out' }, 0.1);
            tl.from(line2Ref.current, { y: 14, opacity: 0, scale: 0.85, duration: 0.8, ease: 'power3.out' }, 0.4);
            tl.from(bgGlowRef.current, { opacity: 0, duration: 0.8, ease: 'power2.inOut' }, 0.3);
            tl.from(insightRef.current, { y: 14, opacity: 0, x: 14, duration: 0.6, ease: 'power2.out' }, 0.7);
        }, sectionRef);

        return () => ctx.revert();
    }, []);

    return (
        <section ref={sectionRef} className="relative min-h-screen w-full bg-void overflow-hidden">
            <div ref={bgGlowRef} className="absolute inset-0 pointer-events-none">
                <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[800px] h-[800px] rounded-full bg-gradient-to-br from-coral/6 via-gold/4 to-transparent blur-[120px]" />
            </div>

            <FloatingSphere src="/images/sphere_silver.png" size={180} position={{ top: '10%', left: '5%' }} delay={0} duration={5} />
            <FloatingSphere src="/images/sphere_silver.png" size={140} position={{ top: '15%', right: '10%' }} delay={0.5} duration={4.5} />
            <FloatingSphere src="/images/sphere_silver.png" size={100} position={{ bottom: '20%', left: '8%' }} delay={0.8} duration={5.5} />

            <div className="relative z-10 min-h-screen flex flex-col items-center justify-center px-6">
                <div className="max-w-5xl mx-auto w-full">
                    <p className="problem-label section-label text-coral/60 mb-8 text-center">
                        The Real Problem
                    </p>

                    <div className="text-center mb-16">
                        <h2 className="text-display-sm md:text-display-lg lg:text-display-xl font-display leading-tight">
                            <span ref={line1Ref} className="block text-ink will-change-transform">YOU CAN SELL IT.</span>
                            <span ref={line2Ref} className="block text-gold will-change-transform">YOU JUST CAN'T DELIVER IT ALL.</span>
                        </h2>
                    </div>

                    <div
                        ref={insightRef}
                        className="p-8 md:p-12 bg-charcoal-light rounded-md shadow-neu-raised max-w-3xl mx-auto will-change-transform hover:shadow-neu-hover transition-all duration-medium"
                    >
                        <p className="text-xl md:text-2xl text-center font-light leading-relaxed">
                            <span className="text-ink-2">You're turning down projects. Your backlog is growing. Freelancers ghost or underdeliver.</span>
                            <br />
                            <span className="text-gold">And you're still the one doing most of the building.</span>
                        </p>
                        <div className="h-px bg-gradient-to-r from-transparent via-gold/30 to-transparent my-6" />
                        <p className="text-center text-ink text-lg">
                            You don't have a sales problem. You have a fulfillment problem.
                            <br />
                            <span className="text-gold font-medium">That's the bottleneck keeping you stuck.</span>
                        </p>
                    </div>
                </div>
            </div>
        </section>
    );
}
