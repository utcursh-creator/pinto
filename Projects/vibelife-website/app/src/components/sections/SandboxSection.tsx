import { useRef, useLayoutEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Search, Wrench, FileCheck, Headphones, CheckCircle2 } from 'lucide-react';
import { MagneticElement } from '@/components/animation/MagneticElement';
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';

gsap.registerPlugin(ScrollTrigger);

interface SandboxSectionProps {
    onBookSandbox: () => void;
}

export function SandboxSection({ onBookSandbox }: SandboxSectionProps) {
    const sectionRef = useRef<HTMLDivElement>(null);
    const headerRef = useRef<HTMLDivElement>(null);
    const ctaRef = useRef<HTMLDivElement>(null);

    const steps = [
        { icon: Search, title: 'Audit Your Backlog', description: 'We look at everything sitting in your queue and figure out what matters most right now.' },
        { icon: Wrench, title: 'Build 2-5 Projects', description: 'We pick the most urgent builds and deliver them in your tools, your stack, your way.' },
        { icon: FileCheck, title: 'Document Everything', description: 'Video walkthroughs, SOPs, and handoff docs so your clients understand what they have.' },
        { icon: Headphones, title: 'Support Until It Sticks', description: 'We stay on until the systems are running and your clients are actually using them.' },
    ];

    const whatYouGet = [
        '2-5 completed projects from your existing backlog',
        'Each project built in your tools and deployed in your client\'s environment',
        'Full documentation and client-ready walkthroughs',
        'Adoption support — we make sure they use it',
        'A clear picture of what ongoing partnership looks like',
    ];

    useLayoutEffect(() => {
        const ctx = gsap.context(() => {
            gsap.from(headerRef.current, { y: 14, opacity: 0, duration: 0.8, ease: 'power2.out', scrollTrigger: { trigger: sectionRef.current, start: 'top 75%' } });

            gsap.utils.toArray('.step-card').forEach((card: any, i: number) => {
                gsap.from(card, { y: 14, opacity: 0, scale: 0.95, duration: 0.6, delay: i * 0.1, ease: 'power2.out', scrollTrigger: { trigger: card, start: 'top 88%' } });
            });

            gsap.from('.deliverables-card', { y: 14, opacity: 0, duration: 0.8, ease: 'power2.out', scrollTrigger: { trigger: '.deliverables-card', start: 'top 85%' } });

            gsap.from(ctaRef.current, { y: 14, opacity: 0, scale: 0.95, duration: 0.6, ease: 'power2.out', scrollTrigger: { trigger: ctaRef.current, start: 'top 90%' } });
        }, sectionRef);

        return () => ctx.revert();
    }, []);

    return (
        <section ref={sectionRef} className="relative w-full bg-charcoal py-32 overflow-hidden">
            <div className="absolute inset-0 pointer-events-none">
                <div className="absolute top-1/3 right-0 w-[400px] h-[400px] rounded-full bg-teal/5 blur-[120px]" />
                <div className="absolute bottom-1/4 left-0 w-[300px] h-[300px] rounded-full bg-gold/5 blur-[100px]" />
            </div>

            <div className="relative z-10 max-w-5xl mx-auto px-6">
                <p className="section-label mb-8 text-center">The 3-Week Sandbox</p>

                <div ref={headerRef}>
                    <h2 className="text-display-sm md:text-display font-display text-center mb-6">
                        <span className="text-ink">Test the partnership.</span>
                        <br />
                        <span className="text-teal">Keep everything we build.</span>
                    </h2>

                    <div className="max-w-3xl mx-auto text-center mb-16">
                        <p className="text-ink-2 text-xl leading-relaxed mb-4 text-balance">
                            We audit your project backlog, pick the 2-5 most urgent builds, and deliver them — in your tools, documented, supported.
                        </p>
                        <p className="text-ink-3 text-lg leading-relaxed text-balance">
                            No long-term commitment. No vague promises. You see exactly how we work before anything bigger.
                        </p>
                    </div>
                </div>

                <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-6 mb-16">
                    {steps.map((step, index) => {
                        const Icon = step.icon;
                        return (
                            <div key={index} className="step-card p-6 rounded-md bg-charcoal-light shadow-neu-raised hover:shadow-neu-hover transition-all duration-medium hover:-translate-y-[3px]">
                                <div className="w-12 h-12 mb-4 rounded-full bg-teal/10 border border-teal/20 flex items-center justify-center">
                                    <Icon className="w-5 h-5 text-teal" />
                                </div>
                                <h3 className="text-ink font-medium text-base mb-2">{step.title}</h3>
                                <p className="text-ink-2 text-sm leading-relaxed">{step.description}</p>
                            </div>
                        );
                    })}
                </div>

                <div className="deliverables-card max-w-3xl mx-auto p-8 md:p-12 bg-charcoal-light rounded-lg shadow-neu-raised border border-gold/20 hover:shadow-neu-hover transition-all duration-medium">
                    <p className="section-label text-gold/60 mb-6 text-center">What You Walk Away With</p>
                    <div className="space-y-3 mb-8">
                        {whatYouGet.map((item, i) => (
                            <div key={i} className="flex items-start gap-3">
                                <CheckCircle2 className="w-4 h-4 text-teal flex-shrink-0 mt-0.5" />
                                <span className="text-ink-2 text-sm">{item}</span>
                            </div>
                        ))}
                    </div>
                    <div className="h-px bg-gradient-to-r from-transparent via-gold/30 to-transparent my-6" />
                    <p className="text-ink-2 text-lg leading-relaxed text-center mb-2">
                        If it works, we talk about a longer partnership.
                    </p>
                    <p className="text-center text-gold text-xl font-medium">
                        If it doesn't, you still keep everything we built.
                    </p>
                </div>

                <div ref={ctaRef} className="text-center mt-12">
                    <MagneticElement strength={0.3} radius={100}>
                        <Button
                            onClick={onBookSandbox}
                            className="rounded-pill px-12 py-6 bg-teal text-void font-mono shadow-neu-raised hover:shadow-glow-teal transition-all duration-short text-lg font-medium"
                        >
                            Book a Discovery Call
                        </Button>
                    </MagneticElement>
                    <p className="text-ink-3 text-sm mt-4">
                        Limited capacity. Only taking on 3-4 new partners per quarter.
                    </p>
                </div>
            </div>
        </section>
    );
}
