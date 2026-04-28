import { useRef, useLayoutEffect } from 'react';
import { Search, Code, Rocket, Headphones, Users, BookOpen } from 'lucide-react';
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';

gsap.registerPlugin(ScrollTrigger);

const capabilities = [
    { title: 'Map Your Knowledge', description: 'We learn your process, your domain, your edge cases — before writing a line of code.', icon: Search, color: 'teal' },
    { title: 'Build Around It', description: 'Custom AI systems shaped by how you actually work. Not generic templates.', icon: Code, color: 'gold' },
    { title: 'Deploy in Your Environment', description: 'Configured inside your tools, your data, your team\'s workflow.', icon: Rocket, color: 'coral' },
    { title: 'Train Your Team', description: 'Video walkthroughs, SOPs, live sessions — until your team runs it solo.', icon: Users, color: 'teal' },
    { title: 'Document Everything', description: 'Knowledge base, troubleshooting guides, onboarding docs. Nothing is a black box.', icon: BookOpen, color: 'gold' },
    { title: 'Stay Until It Sticks', description: 'Ongoing support and iteration. We don\'t disappear after launch.', icon: Headphones, color: 'coral' }
];

const colorClasses: Record<string, { text: string; bg: string }> = {
    teal: { text: 'text-teal', bg: 'hover:bg-teal/5' },
    gold: { text: 'text-gold', bg: 'hover:bg-gold/5' },
    coral: { text: 'text-coral', bg: 'hover:bg-coral/5' },
};

export function ForwardDeployedSection() {
    const sectionRef = useRef<HTMLDivElement>(null);
    const headerRef = useRef<HTMLDivElement>(null);
    const bottomRef = useRef<HTMLDivElement>(null);

    useLayoutEffect(() => {
        const ctx = gsap.context(() => {
            gsap.from(headerRef.current, { y: 14, opacity: 0, duration: 0.8, ease: 'power2.out', scrollTrigger: { trigger: sectionRef.current, start: 'top 75%' } });

            gsap.utils.toArray('.capability-card').forEach((card: any, i: number) => {
                gsap.from(card, { y: 14, opacity: 0, scale: 0.92, rotateY: i % 2 === 0 ? -8 : 8, duration: 0.7, ease: 'power3.out', scrollTrigger: { trigger: card, start: 'top 88%' }, delay: i * 0.08 });
            });

            gsap.from(bottomRef.current, { y: 14, opacity: 0, duration: 0.6, ease: 'power2.out', scrollTrigger: { trigger: bottomRef.current, start: 'top 90%' } });
        }, sectionRef);

        return () => ctx.revert();
    }, []);

    return (
        <section ref={sectionRef} className="relative py-24 md:py-32 bg-charcoal overflow-hidden">
            <div className="absolute inset-0">
                <div className="absolute top-0 left-0 right-0 h-px bg-gradient-to-r from-transparent via-ink-disabled/20 to-transparent" />
                <div className="absolute bottom-0 left-0 right-0 h-px bg-gradient-to-r from-transparent via-ink-disabled/20 to-transparent" />
            </div>

            <div className="relative z-10 max-w-6xl mx-auto px-6">
                <div ref={headerRef} className="text-center mb-16">
                    <p className="section-label mb-4">How We Work</p>
                    <h2 className="text-display-sm md:text-display font-display mb-6">
                        <span className="text-ink">Your Expertise In.</span>
                        <br />
                        <span className="text-gold">AI Systems Out.</span>
                    </h2>
                    <p className="text-ink-2 max-w-2xl mx-auto text-lg text-balance">
                        Step by step. <span className="text-gold">You stay in control the entire time.</span> We map your domain knowledge into AI systems that your team actually uses.
                    </p>
                </div>

                <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4 md:gap-6 mb-16" style={{ perspective: '1200px' }}>
                    {capabilities.map((cap, index) => {
                        const Icon = cap.icon;
                        const colors = colorClasses[cap.color];
                        return (
                            <div key={index} className={`capability-card p-5 md:p-6 rounded-md bg-charcoal-light shadow-neu-raised transition-all duration-medium hover:-translate-y-[3px] hover:shadow-neu-hover ${colors.bg}`} style={{ willChange: 'transform, opacity' }}>
                                <div className="flex items-start gap-4">
                                    <div className="p-2 rounded-sm bg-charcoal">
                                        <Icon className={`w-5 h-5 ${colors.text}`} />
                                    </div>
                                    <div>
                                        <h3 className="text-ink font-medium mb-1">{cap.title}</h3>
                                        <p className="text-ink-2 text-sm leading-relaxed">{cap.description}</p>
                                    </div>
                                </div>
                            </div>
                        );
                    })}
                </div>

                <div ref={bottomRef} className="text-center">
                    <div className="inline-flex items-center gap-4 px-6 py-3 rounded-pill bg-charcoal-light shadow-neu-raised">
                        <span className="text-ink-3 text-sm line-through">Generic AI tools</span>
                        <span className="text-gold">→</span>
                        <span className="text-gold text-sm font-medium">AI built on your expertise</span>
                    </div>
                </div>
            </div>
        </section>
    );
}
